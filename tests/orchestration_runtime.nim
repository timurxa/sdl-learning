import std/[options, os, strutils, times]
import ../src/orchestration
import ../src/orchestration_storage
import ../src/codex_bridge
import ../src/codex_json

let test_root = joinPath(getTempDir(),
  "orchestration-runtime-" & $int64(epochTime() * 1_000_000))
createDir(test_root)

let storage_workspace = joinPath(test_root, "storage-workspace")
createDir(joinPath(storage_workspace, "orchestration", "artifacts"))
writeFile(joinPath(storage_workspace, "orchestration", "debug.log"), "old")
writeFile(joinPath(storage_workspace, "orchestration", "artifacts", "old.txt"),
  "old artifact")
let storage = initialize_orchestration_storage(storage_workspace)
doAssert dirExists(storage.artifacts)
doAssert dirExists(storage.backups)
var backup_count = 0
var backup_path = ""
for kind, path in walkDir(storage.backups):
  if kind == pcDir:
    inc backup_count
    backup_path = path
doAssert backup_count == 1
doAssert fileExists(joinPath(backup_path, "debug.log"))
doAssert fileExists(joinPath(backup_path, "artifacts", "old.txt"))
discard initialize_orchestration_storage(storage_workspace)
var second_backup_count = 0
for kind, path in walkDir(storage.backups):
  if kind == pcDir:
    inc second_backup_count
doAssert second_backup_count == 1

let artifact_root = joinPath(test_root, "artifact-root")
createDir(artifact_root)

let bootstrap = new_work_graph(test_root, "build a thing")
doAssert bootstrap.nodes.len == 1
doAssert bootstrap.nodes[0].execution_plan.`type` == graph_creation
doAssert bootstrap.nodes[0].objective == "build a thing"
doAssert bootstrap.nodes[0].execution_plan.instructions.len > 0

var graph = WorkGraph(nodes: @[
  WorkNode(id: 1, state: pending),
  WorkNode(id: 2, wait_for: @[1], state: pending),
  WorkNode(id: 3, state: pending)
])

doAssert graph.runnable_node_ids() == @[1'u32, 3'u32]

graph.nodes[0].state = running
doAssert graph.complete_node(1)
doAssert graph.nodes[0].state == completed
doAssert graph.runnable_node_ids() == @[2'u32, 3'u32]

graph.nodes[1].state = running
doAssert graph.fail_node(2, "test failure")
doAssert graph.nodes[1].state == failed
doAssert graph.runnable_node_ids() == @[3'u32]
doAssert graph.log_messages == @["NODE 2 FAILED: test failure"]

doAssert not graph.complete_node(2)

graph.outgoing_messages = @[
  WorkGraphMessage(node_id: 3, text: "first"),
  WorkGraphMessage(node_id: 1, text: "second")]
let outgoing_messages = graph.drain_outgoing_messages()
doAssert outgoing_messages.len == 2
doAssert outgoing_messages[0].node_id == 3
doAssert outgoing_messages[0].text == "first"
doAssert outgoing_messages[1].node_id == 1
doAssert outgoing_messages[1].text == "second"
doAssert graph.drain_outgoing_messages().len == 0

var awaiting_graph = WorkGraph(nodes: @[
  WorkNode(id: 4, state: awaiting_human_input)])
awaiting_graph.artifact_root = artifact_root
createDir(joinPath(artifact_root, "4"))
writeFile(joinPath(artifact_root, "4", "response.txt"), "response")
doAssert awaiting_graph.runnable_node_ids().len == 0
doAssert awaiting_graph.complete_node(4)
doAssert awaiting_graph.nodes[0].state == completed

var failed_awaiting_graph = WorkGraph(nodes: @[
  WorkNode(id: 5, state: awaiting_human_input)])
doAssert failed_awaiting_graph.fail_node(5, "test failure")
doAssert failed_awaiting_graph.nodes[0].state == failed

var input_graph = WorkGraph(nodes: @[
  WorkNode(id: 6, state: running)])
input_graph.handle_codex_event(nil, CodexRuntimeEvent(
  kind: cre_global_notification,
  node_id: 6,
  server_request_kind: sr_tool_user_input))
doAssert input_graph.nodes[0].state == awaiting_human_input
doAssert input_graph.node_can_accept_user_input(6)
input_graph.handle_codex_event(nil, CodexRuntimeEvent(
  kind: cre_tool_response_sent,
  node_id: 6,
  server_request_kind: sr_tool_user_input))
doAssert input_graph.nodes[0].state == awaiting_human_input
input_graph.handle_codex_event(nil, CodexRuntimeEvent(
  kind: cre_turn_completed,
  node_id: 6))
doAssert input_graph.nodes[0].state == completed

var terminal_status_graph = WorkGraph(nodes: @[
  WorkNode(id: 9, state: awaiting_human_input)])
terminal_status_graph.handle_codex_event(nil, CodexRuntimeEvent(
  kind: cre_global_notification,
  node_id: 9,
  notification_kind: nk_thread_status_changed,
  thread_status: some(tsk_system_error)))
doAssert terminal_status_graph.nodes[0].state == failed

var direct_human_graph = WorkGraph(nodes: @[
  WorkNode(id: 7, state: pending, execution_plan: ExecutionPlan(
    `type`: human_input, instructions: "Choose a direction"))])
direct_human_graph.artifact_root = artifact_root
direct_human_graph.start_available_nodes(nil)
doAssert direct_human_graph.nodes[0].state == awaiting_human_input
doAssert direct_human_graph.outgoing_messages.len == 1
doAssert direct_human_graph.outgoing_messages[0].text == "Choose a direction"
doAssert direct_human_graph.answer_human_input(7, "forward")
doAssert direct_human_graph.nodes[0].state == completed
doAssert readFile(joinPath(artifact_root, "7", "response.txt")) ==
  "Instructions:\nChoose a direction\n\nResponse:\nforward"

var closed_input_graph = WorkGraph(nodes: @[
  WorkNode(id: 8, state: awaiting_human_input)])
closed_input_graph.handle_codex_event(nil, CodexRuntimeEvent(
  kind: cre_runtime_closed))
doAssert closed_input_graph.nodes[0].state == failed

var artifact_graph = WorkGraph(
  artifact_root: artifact_root,
  nodes: @[
    WorkNode(
      id: 20,
      state: running,
      execution_plan: ExecutionPlan(`type`: llm_worker),
      outputs: @[OutputArtifactDecl(
        path: "result.txt", description: "result", final: true)]),
    WorkNode(
      id: 21,
      state: pending,
      execution_plan: ExecutionPlan(`type`: llm_worker),
      inputs: @[InputArtifactRef(
        producer_node_id: 20,
        path: "result.txt",
        description: "input result")],
      outputs: @[OutputArtifactDecl(
        path: "final.txt", description: "final result")])])
doAssert artifact_graph.runnable_node_ids().len == 0
doAssert not artifact_graph.complete_node(20)
doAssert artifact_graph.nodes[0].state == failed

artifact_graph.nodes[0].state = running
createDir(joinPath(artifact_root, "20"))
writeFile(joinPath(artifact_root, "20", "result.txt"), "result")
doAssert artifact_graph.complete_node(20)
doAssert artifact_graph.runnable_node_ids() == @[21'u32]
doAssert artifact_graph.final_artifact_paths() == @[
  joinPath(artifact_root, "20", "result.txt")]
let developer_prompt = artifact_graph.node_developer_prompt(artifact_graph.nodes[1])
doAssert developer_prompt.contains("Input artifacts:")
doAssert developer_prompt.contains("Output artifacts:")
doAssert developer_prompt.contains(
  joinPath(artifact_root, "20", "result.txt"))
doAssert developer_prompt.contains(
  joinPath(artifact_root, "21", "final.txt"))
doAssert developer_prompt.contains("input result")
doAssert developer_prompt.contains("final result")
doAssert not developer_prompt.contains("producer_node_id")

var invalid_graph = WorkGraph(nodes: @[WorkNode(
  id: 40,
  state: running,
  execution_plan: ExecutionPlan(`type`: llm_worker),
  outputs: @[OutputArtifactDecl(path: "../escape")])])
doAssert invalid_graph.node_artifact_error(invalid_graph.nodes[0]).len > 0
doAssert not invalid_graph.complete_node(40)
doAssert invalid_graph.nodes[0].state == failed

var finish_graph = WorkGraph(
  artifact_root: artifact_root,
  nodes: @[WorkNode(
    id: 30,
    state: running,
    execution_plan: ExecutionPlan(`type`: llm_worker),
    outputs: @[OutputArtifactDecl(path: "missing.txt")])])
finish_graph.handle_codex_event(nil, CodexRuntimeEvent(
  kind: cre_global_notification,
  node_id: 30,
  server_request_kind: sr_tool_call,
  tool_name: finish_node_name))
doAssert finish_graph.nodes[0].state == failed

var tool_response_graph = WorkGraph(nodes: @[WorkNode(
  id: 50,
  state: running,
  execution_plan: ExecutionPlan(`type`: llm_worker))])
tool_response_graph.handle_codex_event(nil, CodexRuntimeEvent(
  kind: cre_tool_response_sent,
  node_id: 50,
  server_request_kind: sr_tool_call))
doAssert tool_response_graph.nodes[0].state == running
tool_response_graph.handle_codex_event(nil, CodexRuntimeEvent(
  kind: cre_turn_completed,
  node_id: 50))
doAssert tool_response_graph.nodes[0].state == completed
