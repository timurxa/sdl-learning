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
doAssert created.node_id == 2
doAssert graph.nodes.len == 2
doAssert graph.nodes[1].wait_for == @[1'u32]
doAssert graph.graph_validation_errors().len == 0

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
  outputs: @[OutputArtifactDecl(path: "directory", description: "File")],
  execution_plan: ExecutionPlan(`type`: llm_worker, instructions: "Work")))
doAssert directory_output.status == committed
directory_artifact_graph.nodes[1].state = running
createDir(joinPath(directory_artifact_graph.artifact_root,
  $directory_output.node_id))
createDir(joinPath(directory_artifact_graph.artifact_root,
  $directory_output.node_id, "directory"))
doAssert directory_artifact_graph.node_completion_error(
  directory_output.node_id).startsWith("missing output artifact:")

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
doAssert supplied_id.node_id == 2
doAssert supplied_id_graph.nodes[1].id == 2

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
doAssert nested_created.node_id == 3

let human = graph.create_node(1, WorkNode(
  description: "Ask target",
  objective: "Get target",
  outputs: @[OutputArtifactDecl(
    path: "answer.txt",
    description: "Target answer")],
  execution_plan: ExecutionPlan(
    `type`: human_input,
    instructions: "Which target?")))
doAssert human.status == committed
doAssert human.node_id == 3
doAssert graph.node_artifact_error(graph.nodes[2]).len == 0

let invalid = graph.create_node(1, WorkNode(
  description: "Bad input",
  objective: "Use result",
  inputs: @[InputArtifactRef(
    producer_node_id: 2,
    path: "missing.txt",
    description: "Missing")],
  execution_plan: ExecutionPlan(
    `type`: llm_worker,
    instructions: "Use input")))
doAssert invalid.status == pending_invalid
doAssert invalid.edit_id > 0
doAssert invalid.node_id == 4
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
    producer_node_id: 2,
    path: "result.txt",
    description: "Result")],
  execution_plan: ExecutionPlan(
    `type`: llm_worker,
    instructions: "Use input")), invalid.edit_id)
doAssert correction.status == committed
doAssert graph.nodes.len == 4
doAssert graph.nodes[3].id == 4
doAssert graph.graph_validation_errors().len == 0

let cycle_edit = graph.update_node(
  1,
  4,
  WorkNodeChanges(has_wait_for: true, wait_for: @[4'u32]))
doAssert cycle_edit.status == pending_invalid
doAssert cycle_edit.errors.len > 0
let discarded = graph.discard_edit(1, cycle_edit.edit_id)
doAssert discarded.status == committed
doAssert graph.nodes[3].wait_for != @[4'u32]

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
      path: "answers/target.txt",
      description: "Target")],
    execution_plan: ExecutionPlan(
      `type`: human_input,
      instructions: "Which target?"))])
doAssert human_graph.answer_human_input(1, "  answer  ")
doAssert readFile(joinPath(
  human_graph.artifact_root, "1", "answers", "target.txt")) ==
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
          "instructions": "Work"
        }
      }
    }
  }))
let tool_error = tool_graph.handle_codex_event(nil, tool_event)
doAssert tool_graph.nodes.len == 2
doAssert tool_graph.nodes[1].id == 2
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
doAssert summary.contains("Outgoing: 2, 3, 4")
doAssert summary.contains("Node 2: Build result")

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
