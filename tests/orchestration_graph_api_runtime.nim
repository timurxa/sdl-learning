import std/[json, os, strutils, times]
import ../src/codex_bridge
import ../src/codex_json
import ../src/orchestration

proc worker_node(objective, output_path: string): WorkNode =
  WorkNode(
    description: objective,
    objective: objective,
    outputs: @[OutputArtifactDecl(
      path: output_path,
      description: "worker output")],
    execution_plan: ExecutionPlan(
      `type`: llm_worker,
      instructions: "Do work"))

let test_root = joinPath(getTempDir(),
  "orchestration-graph-api-" & $int64(epochTime() * 1_000_000))
createDir(test_root)

var graph = new_work_graph(test_root, "build result")
graph.nodes[0].state = running

let created = graph.create_node(1, worker_node("Build result", "result.txt"))
doAssert created.status == committed
doAssert created.node_id > 1
doAssert graph.nodes.len == 2
doAssert graph.nodes[1].id == created.node_id
doAssert graph.nodes[1].wait_for == @[1'u32]
doAssert graph.graph_validation_errors().len == 0

var sequential_graph = new_work_graph(test_root, "sequential IDs")
sequential_graph.nodes[0].state = running
let sequential_first = sequential_graph.create_node(
  1, worker_node("First", "first.txt"))
let sequential_second = sequential_graph.create_node(
  1, worker_node("Second", "second.txt"))
doAssert sequential_first.node_id == 2
doAssert sequential_second.node_id == 3

var creator_artifact_graph = new_work_graph(test_root, "creator artifact")
creator_artifact_graph.nodes[0].state = running
let creator_output = creator_artifact_graph.create_node(1, WorkNode(
  description: "Create manifest",
  objective: "Create manifest",
  outputs: @[OutputArtifactDecl(
    path: "manifest.txt", description: "Manifest", final: true)],
  execution_plan: ExecutionPlan(
    `type`: graph_creation,
    instructions: "Create the manifest")))
doAssert creator_output.status == committed
doAssert creator_artifact_graph.node_artifact_error(
  creator_artifact_graph.nodes[1]).len == 0
creator_artifact_graph.nodes[1].state = running
doAssert creator_artifact_graph.node_completion_error(
  creator_output.node_id).startsWith("missing output artifact:")
createDir(joinPath(creator_artifact_graph.artifact_root,
  $creator_output.node_id))
writeFile(joinPath(creator_artifact_graph.artifact_root,
  $creator_output.node_id, "manifest.txt"), "manifest")
doAssert creator_artifact_graph.complete_node(creator_output.node_id)
doAssert creator_artifact_graph.final_artifact_paths() == @[
  joinPath(creator_artifact_graph.artifact_root,
    $creator_output.node_id, "manifest.txt")]
let creator_consumer = creator_artifact_graph.create_node(1, WorkNode(
  description: "Use manifest",
  objective: "Use manifest",
  inputs: @[InputArtifactRef(
    producer_node_id: creator_output.node_id,
    path: "manifest.txt",
    description: "Created manifest")],
  execution_plan: ExecutionPlan(
    `type`: llm_worker,
    instructions: "Use the manifest")))
doAssert creator_consumer.status == committed
let creator_consumer_node = creator_artifact_graph.nodes[2]
doAssert creator_consumer_node.wait_for == @[]
doAssert creator_consumer_node.inputs.len == 1
doAssert creator_consumer_node.inputs[0].producer_node_id == creator_output.node_id
doAssert creator_consumer_node.node_dependency_ids == @[creator_output.node_id]

var dependency_matrix_graph = new_work_graph(test_root, "dependency matrix")
dependency_matrix_graph.nodes[0].state = running
let intermediate = dependency_matrix_graph.create_node(1, WorkNode(
  description: "Intermediate",
  objective: "Intermediate",
  outputs: @[OutputArtifactDecl(path: "intermediate.txt", description: "Intermediate")],
  execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")))
doAssert intermediate.status == committed
let transitive_consumer = dependency_matrix_graph.create_node(1, WorkNode(
  description: "Transitive consumer",
  objective: "Transitive consumer",
  inputs: @[InputArtifactRef(
    producer_node_id: intermediate.node_id,
    path: "intermediate.txt",
    description: "Intermediate input")],
  execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")))
doAssert transitive_consumer.status == committed
let transitive_node = dependency_matrix_graph.nodes[2]
doAssert transitive_node.wait_for == @[]
doAssert transitive_node.inputs.len == 1
doAssert transitive_node.node_dependency_ids == @[intermediate.node_id]
doAssert dependency_matrix_graph.graph_validation_errors().len == 0

let duplicate_effective = dependency_matrix_graph.create_node(1, WorkNode(
  description: "Duplicate effective dependency",
  objective: "Duplicate effective dependency",
  wait_for: @[intermediate.node_id],
  inputs: @[InputArtifactRef(
    producer_node_id: intermediate.node_id,
    path: "intermediate.txt",
    description: "Retained declaration")],
  execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")))
doAssert duplicate_effective.status == committed
doAssert dependency_matrix_graph.nodes[3].wait_for == @[intermediate.node_id]
doAssert dependency_matrix_graph.nodes[3].inputs.len == 1
doAssert dependency_matrix_graph.nodes[3].node_dependency_ids == @[intermediate.node_id]

var bypass_dependency_graph = WorkGraph(nodes: @[
  WorkNode(id: 1, state: completed, execution_plan: ExecutionPlan(
    `type`: graph_creation, instructions: "Root")),
  WorkNode(id: 2, state: running, wait_for: @[1'u32], outputs: @[
    OutputArtifactDecl(path: "owner.txt", description: "Owner output")],
    execution_plan: ExecutionPlan(
      `type`: graph_creation, instructions: "Owner")),
  WorkNode(id: 3, state: pending, wait_for: @[2'u32], execution_plan: ExecutionPlan(
    `type`: llm_worker, instructions: "Descendant")),
  WorkNode(id: 4, state: pending, wait_for: @[1'u32], execution_plan: ExecutionPlan(
    `type`: llm_worker, instructions: "Bypass"))])
let bypass_consumer = bypass_dependency_graph.create_node(2, WorkNode(
  description: "Required owner dependency",
  objective: "Required owner dependency",
  wait_for: @[3'u32, 4'u32],
  execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")))
doAssert bypass_consumer.status == pending_invalid
doAssert bypass_consumer.errors.len > 0
doAssert bypass_consumer.errors[0].message.contains("bypasses")
let bypass_pending = bypass_dependency_graph.pending_edit_json(
  2, bypass_consumer.edit_id)
var bypass_definition_json = bypass_pending["mutation"]["node_definition"]
bypass_definition_json.delete("id")
bypass_definition_json.delete("state")
let bypass_definition = parse_node_definition(bypass_definition_json)
doAssert bypass_definition.wait_for == @[3'u32, 4'u32, 2'u32]
doAssert bypass_definition.node_dependency_ids == @[3'u32, 4'u32, 2'u32]

var owner_after_bypass_input_graph = WorkGraph(nodes: @[
  WorkNode(id: 1, state: completed, execution_plan: ExecutionPlan(
    `type`: graph_creation, instructions: "Root")),
  WorkNode(id: 2, state: running, wait_for: @[1'u32], outputs: @[
    OutputArtifactDecl(path: "owner.txt", description: "Owner output")],
    execution_plan: ExecutionPlan(`type`: graph_creation, instructions: "Owner")),
  WorkNode(id: 3, state: pending, wait_for: @[1'u32], execution_plan: ExecutionPlan(
    `type`: llm_worker, instructions: "Bypass"))])
let owner_after_bypass_input = owner_after_bypass_input_graph.create_node(
  2, WorkNode(
    description: "Owner input after bypass",
    objective: "Owner input after bypass",
    wait_for: @[3'u32],
    inputs: @[InputArtifactRef(
      producer_node_id: 2,
      path: "owner.txt",
      description: "Retained owner input")],
    execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")))
doAssert owner_after_bypass_input.status == pending_invalid
let owner_after_bypass_input_json =
  owner_after_bypass_input_graph.pending_edit_json(
    2, owner_after_bypass_input.edit_id)
var owner_after_bypass_input_definition_json =
  owner_after_bypass_input_json["mutation"]["node_definition"]
owner_after_bypass_input_definition_json.delete("id")
owner_after_bypass_input_definition_json.delete("state")
let owner_after_bypass_input_definition = parse_node_definition(
  owner_after_bypass_input_definition_json)
doAssert owner_after_bypass_input_definition.wait_for == @[3'u32]
doAssert owner_after_bypass_input_definition.inputs.len == 1
doAssert owner_after_bypass_input_definition.inputs[0].producer_node_id == 2
doAssert owner_after_bypass_input_definition.node_dependency_ids == @[3'u32, 2'u32]

let owner_after_bypass_wait = owner_after_bypass_input_graph.create_node(
  2, WorkNode(
    description: "Owner wait after bypass",
    objective: "Owner wait after bypass",
    wait_for: @[3'u32, 2'u32],
    execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")))
doAssert owner_after_bypass_wait.status == pending_invalid
let owner_after_bypass_wait_json = owner_after_bypass_input_graph.pending_edit_json(
  2, owner_after_bypass_wait.edit_id)
var owner_after_bypass_wait_definition_json =
  owner_after_bypass_wait_json["mutation"]["node_definition"]
owner_after_bypass_wait_definition_json.delete("id")
owner_after_bypass_wait_definition_json.delete("state")
let owner_after_bypass_wait_definition = parse_node_definition(
  owner_after_bypass_wait_definition_json)
doAssert owner_after_bypass_wait_definition.wait_for == @[3'u32, 2'u32]
doAssert owner_after_bypass_wait_definition.node_dependency_ids == @[3'u32, 2'u32]

var multi_parent_graph = new_work_graph(test_root, "multi-parent dependencies")
multi_parent_graph.nodes[0].state = running
let multi_parent_a = multi_parent_graph.create_node(
  1, worker_node("Multi-parent A", "multi-parent-a.txt"))
let multi_parent_b = multi_parent_graph.create_node(
  1, worker_node("Multi-parent B", "multi-parent-b.txt"))
let multi_parent_c = multi_parent_graph.create_node(
  1, worker_node("Multi-parent C", "multi-parent-c.txt"))
let multi_parent = multi_parent_graph.create_node(1, WorkNode(
  description: "Multi-parent consumer",
  objective: "Multi-parent consumer",
  wait_for: @[multi_parent_a.node_id, multi_parent_b.node_id],
  inputs: @[
    InputArtifactRef(
      producer_node_id: multi_parent_b.node_id,
      path: "multi-parent-b.txt",
      description: "B input"),
    InputArtifactRef(
      producer_node_id: multi_parent_c.node_id,
      path: "multi-parent-c.txt",
      description: "C input")],
  execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")))
doAssert multi_parent.status == committed
let multi_parent_node = multi_parent_graph.nodes[4]
doAssert multi_parent_node.wait_for == @[multi_parent_a.node_id, multi_parent_b.node_id]
doAssert multi_parent_node.inputs.len == 2
doAssert multi_parent_node.inputs[0].producer_node_id == multi_parent_b.node_id
doAssert multi_parent_node.inputs[1].producer_node_id == multi_parent_c.node_id
doAssert multi_parent_node.node_dependency_ids == @[
  multi_parent_a.node_id, multi_parent_b.node_id, multi_parent_c.node_id]

var staged_path_graph = new_work_graph(test_root, "staged dependency path")
staged_path_graph.nodes[0].state = running
let staged_intermediate = staged_path_graph.create_node(1, WorkNode(
  description: "Staged intermediate",
  objective: "Staged intermediate",
  inputs: @[InputArtifactRef(
    producer_node_id: 1,
    path: "not-yet-declared.txt",
    description: "Invalid until corrected")],
  execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")))
let staged_consumer = staged_path_graph.create_node(1, WorkNode(
  description: "Staged consumer",
  objective: "Staged consumer",
  inputs: @[InputArtifactRef(
    producer_node_id: staged_intermediate.node_id,
    path: "staged.txt",
    description: "Staged input")],
  execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")))
doAssert staged_intermediate.status == pending_invalid
doAssert staged_consumer.status == pending_invalid
let staged_correction = staged_path_graph.create_node(1, WorkNode(
  description: "Staged intermediate",
  objective: "Staged intermediate",
  outputs: @[OutputArtifactDecl(path: "staged.txt", description: "Staged output")],
  execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")),
  staged_intermediate.edit_id)
doAssert staged_correction.status == committed
doAssert staged_path_graph.nodes.len == 3
doAssert staged_path_graph.nodes[2].wait_for == @[]
doAssert staged_path_graph.nodes[2].inputs[0].producer_node_id ==
  staged_intermediate.node_id
doAssert staged_path_graph.graph_validation_errors().len == 0

var duplicate_dependency_graph = new_work_graph(test_root, "duplicate dependency")
duplicate_dependency_graph.nodes[0].state = running
let duplicate_dependency = duplicate_dependency_graph.create_node(1, WorkNode(
  description: "Duplicate dependency",
  objective: "Duplicate dependency",
  wait_for: @[1'u32, 1'u32],
  execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")))
doAssert duplicate_dependency.status == pending_invalid
doAssert duplicate_dependency.errors.len > 0

var directory_artifact_graph = new_work_graph(test_root, "directory artifact")
directory_artifact_graph.nodes[0].state = running
let directory_output = directory_artifact_graph.create_node(1, WorkNode(
  description: "Directory output",
  objective: "Directory output",
  outputs: @[OutputArtifactDecl(
    path: "directory", description: "Directory", final: true)],
  execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")))
doAssert directory_output.status == committed
directory_artifact_graph.nodes[1].state = running
createDir(joinPath(directory_artifact_graph.artifact_root,
  $directory_output.node_id))
createDir(joinPath(directory_artifact_graph.artifact_root,
  $directory_output.node_id, "directory"))
doAssert directory_artifact_graph.node_completion_error(
  directory_output.node_id).len == 0
doAssert directory_artifact_graph.complete_node(directory_output.node_id)
doAssert directory_artifact_graph.final_artifact_paths() == @[
  joinPath(directory_artifact_graph.artifact_root,
    $directory_output.node_id, "directory")]

let dot_output = directory_artifact_graph.create_node(1, WorkNode(
  description: "Dot output",
  objective: "Dot output",
  outputs: @[OutputArtifactDecl(path: ".", description: "File")],
  execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")))
doAssert dot_output.status == pending_invalid
doAssert dot_output.errors.len > 0

var supplied_id_graph = new_work_graph(test_root, "supplied ID")
supplied_id_graph.nodes[0].state = running
let supplied_id = supplied_id_graph.create_node(
  1, WorkNode(id: 99, description: "Supplied", objective: "Supplied",
    outputs: @[OutputArtifactDecl(path: "supplied.txt", description: "Output")],
    execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")))
doAssert supplied_id.status == committed
doAssert supplied_id.node_id > 1
doAssert supplied_id.node_id != 99
doAssert supplied_id_graph.nodes[1].id == supplied_id.node_id

var bypass_graph = WorkGraph(nodes: @[
  WorkNode(id: 1, state: completed, execution_plan: ExecutionPlan(
    `type`: graph_creation, instructions: "Root")),
  WorkNode(id: 2, state: running, wait_for: @[1'u32], execution_plan: ExecutionPlan(
    `type`: graph_creation, instructions: "Creator")),
  WorkNode(id: 3, state: pending, wait_for: @[2'u32], execution_plan: ExecutionPlan(
    `type`: llm_worker, instructions: "Target")),
  WorkNode(id: 4, state: pending, wait_for: @[1'u32], execution_plan: ExecutionPlan(
    `type`: llm_worker, instructions: "Sibling"))])
let bypass = bypass_graph.update_node(
  2, 3, WorkNodeChanges(has_wait_for: true, wait_for: @[2'u32, 4'u32]))
doAssert bypass.status == pending_invalid
doAssert bypass.errors.len > 0

var nested_graph = new_work_graph(test_root, "nested creator")
nested_graph.nodes[0].state = completed
nested_graph.nodes.add(WorkNode(
  id: 2,
  state: running,
  wait_for: @[1'u32],
  execution_plan: ExecutionPlan(
    `type`: graph_creation,
    instructions: "Expand")))
let nested_created = nested_graph.create_node(
  2, worker_node("Nested result", "nested.txt"))
doAssert nested_created.status == committed
doAssert nested_created.node_id > 0

let human_definition = parse_node_definition(%*{
  "description": "Ask target",
  "objective": "Get target",
  "inputs": [],
  "wait_for": [],
  "execution_plan": {
    "type": "human_input",
    "instructions": "Which target?"
  }
})
let human = graph.create_node(1, human_definition)
doAssert human.status == committed
doAssert human.node_id > 1
doAssert graph.nodes[2].outputs[0].path == "response.txt"
doAssert graph.node_artifact_error(graph.nodes[2]).len == 0

let invalid = graph.create_node(1, WorkNode(
  description: "Bad input",
  objective: "Use result",
  inputs: @[InputArtifactRef(
    producer_node_id: created.node_id,
    path: "missing.txt",
    description: "Missing")],
  execution_plan: ExecutionPlan(
    `type`: llm_worker,
    instructions: "Use input")))
doAssert invalid.status == pending_invalid
doAssert invalid.edit_id > 0
doAssert invalid.node_id > 1
doAssert graph.nodes.len == 3

var staged_graph = new_work_graph(test_root, "staged edits")
staged_graph.nodes[0].state = running
let first_invalid = staged_graph.create_node(1, WorkNode(
  description: "Bad first",
  objective: "Bad first",
  inputs: @[InputArtifactRef(
    producer_node_id: 1,
    path: "missing.txt",
    description: "Missing")],
  execution_plan: ExecutionPlan(
    `type`: llm_worker,
    instructions: "Work")))
let later_valid = staged_graph.create_node(
  1, worker_node("Later valid", "later.txt"))
doAssert first_invalid.status == pending_invalid
doAssert later_valid.status == pending_invalid
doAssert later_valid.errors.len > 0
discard staged_graph.discard_edit(1, later_valid.edit_id)
doAssert staged_graph.discard_edit(1, first_invalid.edit_id).status == committed

var reassignment_graph = new_work_graph(test_root, "reassignment correction")
reassignment_graph.nodes[0].state = running
let invalid_prefix = reassignment_graph.create_node(1, WorkNode(
  description: "Invalid prefix",
  objective: "Invalid prefix",
  inputs: @[InputArtifactRef(
    producer_node_id: 1,
    path: "missing.txt",
    description: "Missing")],
  execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")))
let staged_source = reassignment_graph.create_node(
  1, worker_node("Source", "source.txt"))
let staged_destination = reassignment_graph.create_node(
  1, worker_node("Destination", "destination.txt"))
let staged_reassign = reassignment_graph.reassign_output(
  1,
  staged_source.node_id,
  "source.txt",
  staged_destination.node_id,
  "moved.txt")
doAssert staged_reassign.status == pending_invalid
let retained_path = reassignment_graph.reassign_output(
  1,
  staged_source.node_id,
  "source.txt",
  staged_destination.node_id,
  edit_id = staged_reassign.edit_id)
doAssert retained_path.status == pending_invalid
doAssert reassignment_graph.discard_edit(1, invalid_prefix.edit_id).status == committed
var moved_output_found = false
for output in reassignment_graph.nodes[2].outputs:
  moved_output_found = moved_output_found or output.path == "moved.txt"
doAssert moved_output_found

let correction = graph.create_node(1, WorkNode(
  description: "Use result",
  objective: "Use result",
  inputs: @[InputArtifactRef(
    producer_node_id: created.node_id,
    path: "result.txt",
    description: "Result")],
  execution_plan: ExecutionPlan(
    `type`: llm_worker,
    instructions: "Use input")), invalid.edit_id)
doAssert correction.status == committed
doAssert graph.nodes.len == 4
doAssert graph.nodes[3].id == correction.node_id
doAssert graph.graph_validation_errors().len == 0

let cycle_edit = graph.update_node(
  1,
  correction.node_id,
  WorkNodeChanges(has_wait_for: true, wait_for: @[correction.node_id]))
doAssert cycle_edit.status == pending_invalid
doAssert cycle_edit.errors.len > 0
let discarded = graph.discard_edit(1, cycle_edit.edit_id)
doAssert discarded.status == committed
doAssert graph.nodes[3].wait_for != @[correction.node_id]

var pending_completion_graph = new_work_graph(test_root, "pending completion")
pending_completion_graph.nodes[0].state = running
let pending_creation = pending_completion_graph.create_node(1, WorkNode(
  description: "Bad output",
  objective: "Bad output",
  inputs: @[InputArtifactRef(
    producer_node_id: 1,
    path: "unknown.txt",
    description: "Unknown")],
  execution_plan: ExecutionPlan(
    `type`: llm_worker,
    instructions: "Work")))
doAssert pending_creation.status == pending_invalid
doAssert not pending_completion_graph.attempt_completion(1)
doAssert pending_completion_graph.nodes[0].state == failed

var human_graph = WorkGraph(
  artifact_root: joinPath(test_root, "human-artifacts"),
  nodes: @[WorkNode(
    id: 1,
    state: awaiting_human_input,
    outputs: @[OutputArtifactDecl(
      path: "response.txt",
      description: "Target")],
    execution_plan: ExecutionPlan(
      `type`: human_input,
      instructions: "Which target?"))])
doAssert human_graph.answer_human_input(1, "  answer  ")
doAssert readFile(joinPath(
  human_graph.artifact_root, "1", "response.txt")) ==
  "Instructions:\nWhich target?\n\nResponse:\n  answer  "

var tool_graph = new_work_graph(test_root, "tool graph")
tool_graph.nodes[0].state = running
let tool_event = CodexRuntimeEvent(
  kind: cre_global_notification,
  node_id: 1,
  server_request_kind: sr_tool_call,
  tool_name: create_node_name,
  params_json: $(%*{
    "arguments": {
      "node_definition": {
        "description": "Tool node",
        "objective": "Tool result",
        "inputs": [],
        "outputs": [{
          "path": "tool.txt",
          "description": "Tool output"
        }],
        "wait_for": [],
        "execution_plan": {
          "type": "llm_worker",
          "instructions": "Work",
          "reasoning_level": "bounded"
        }
      }
    }
  }))
let tool_error = tool_graph.handle_codex_event(nil, tool_event)
doAssert tool_graph.nodes.len == 2
doAssert tool_graph.nodes[1].id > 1
doAssert tool_graph.nodes[1].execution_plan.reasoning_level == bounded
doAssert tool_graph.nodes[0].state == failed
doAssert tool_error == "graph tool response could not be queued"

var consumer_graph = WorkGraph(nodes: @[
  WorkNode(id: 1, state: completed),
  WorkNode(id: 2, state: running, wait_for: @[1'u32], execution_plan: ExecutionPlan(
    `type`: graph_creation, instructions: "Reassign")),
  WorkNode(id: 3, state: pending, wait_for: @[2'u32], outputs: @[
    OutputArtifactDecl(path: "old.txt", description: "Old")]),
  WorkNode(id: 4, state: pending, wait_for: @[2'u32]),
  WorkNode(id: 5, state: pending, wait_for: @[1'u32, 3'u32], inputs: @[
    InputArtifactRef(
      producer_node_id: 3,
      path: "old.txt",
      description: "Old input")])])
let unauthorized_reassign = consumer_graph.reassign_output(
  2, 3, "old.txt", 4, "new.txt")
doAssert unauthorized_reassign.status == pending_invalid
doAssert unauthorized_reassign.errors.len > 0

let summary = graph.graph_view_summary(1, "descendant", 2, 8)
doAssert summary.contains("Node 1: Create work graph")
doAssert summary.contains("Outgoing: " & $created.node_id & ", " & $human.node_id)
doAssert not summary.contains("Outgoing: " & $created.node_id & ", " &
  $human.node_id & ", " & $correction.node_id)
doAssert summary.contains("Node " & $created.node_id & ": Build result")

var disconnected = WorkGraph(nodes: @[
  WorkNode(id: 1, state: running, execution_plan: ExecutionPlan(
    `type`: graph_creation, instructions: "Create")),
  WorkNode(id: 2, state: pending)])
doAssert disconnected.graph_validation_errors().len > 0

var wrong_root = WorkGraph(nodes: @[WorkNode(
  id: 42, state: pending, execution_plan: ExecutionPlan(
    `type`: graph_creation, instructions: "Create"))])
doAssert wrong_root.graph_validation_errors().len > 0

var wrong_root_type = WorkGraph(nodes: @[WorkNode(
  id: 1, state: pending, execution_plan: ExecutionPlan(
    `type`: llm_worker, instructions: "Work"))])
doAssert wrong_root_type.graph_validation_errors().len > 0
