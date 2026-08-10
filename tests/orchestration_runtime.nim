import std/options
import ../src/orchestration
import ../src/codex_bridge
import ../src/codex_json

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
direct_human_graph.start_available_nodes(nil)
doAssert direct_human_graph.nodes[0].state == awaiting_human_input
doAssert direct_human_graph.outgoing_messages.len == 1
doAssert direct_human_graph.outgoing_messages[0].text == "Choose a direction"
doAssert direct_human_graph.answer_human_input(7, "forward")
doAssert direct_human_graph.nodes[0].state == completed

var closed_input_graph = WorkGraph(nodes: @[
  WorkNode(id: 8, state: awaiting_human_input)])
closed_input_graph.handle_codex_event(nil, CodexRuntimeEvent(
  kind: cre_runtime_closed))
doAssert closed_input_graph.nodes[0].state == failed
