import std/[options, strutils]
import codex_bridge
import codex_json

type
  ExecutionPlanType* = enum
    llm_worker
    graph_creation
    human_input

  ExecutionPlan* = object
    `type`*: ExecutionPlanType
    instructions*: string

  NodeState* = enum
    pending
    running
    awaiting_human_input
    completed
    failed

  WorkNode* = object
    id*: uint32
    wait_for*: seq[uint32]
    state*: NodeState
    execution_plan*: ExecutionPlan

  WorkGraphMessage* = object
    node_id*: uint32
    text*: string

  WorkGraph* = object
    nodes*: seq[WorkNode]
    log_messages*: seq[string]
    outgoing_messages*: seq[WorkGraphMessage]

proc new_work_graph*(): WorkGraph =
  WorkGraph(nodes: @[
    WorkNode(
      id: 1,
      state: pending,
      execution_plan: ExecutionPlan(`type`: llm_worker)),
    WorkNode(
      id: 2,
      wait_for: @[1],
      state: pending,
      execution_plan: ExecutionPlan(
        `type`: human_input,
        instructions: "What should happen next?"))
  ])

proc node_index(graph: WorkGraph; node_id: uint32): int =
  for index, node in graph.nodes:
    if node.id == node_id:
      return index
  -1

proc node_runnable(graph: WorkGraph; node: WorkNode): bool =
  if node.state != pending:
    return false
  for dependency_id in node.wait_for:
    let dependency_index = graph.node_index(dependency_id)
    if dependency_index < 0 or
        graph.nodes[dependency_index].state != completed:
      return false
  true

proc node_state_is_active(state: NodeState): bool {.inline.} =
  state in {running, awaiting_human_input}

proc runnable_node_ids*(graph: WorkGraph): seq[uint32] =
  for node in graph.nodes:
    if graph.node_runnable(node):
      result.add(node.id)

proc node_prompt(node: WorkNode): string =
  if node.execution_plan.`type` == human_input and
      node.execution_plan.instructions.len > 0:
    return node.execution_plan.instructions
  "Your execution type is " & $node.execution_plan.`type` & ". Do nothing."

proc log_node_failure(graph: var WorkGraph; node_id: uint32; reason: string) =
  graph.log_messages.add("NODE " & $node_id & " FAILED: " & reason)

proc fail_node*(graph: var WorkGraph; node_id: uint32; reason: string): bool =
  let index = graph.node_index(node_id)
  if index < 0:
    graph.log_node_failure(node_id, reason)
    return false
  let can_fail = graph.nodes[index].state == pending or
    graph.nodes[index].state.node_state_is_active
  if can_fail:
    graph.nodes[index].state = failed
  graph.log_node_failure(node_id, reason)
  can_fail

proc complete_node*(graph: var WorkGraph; node_id: uint32): bool =
  let index = graph.node_index(node_id)
  if index < 0 or not graph.nodes[index].state.node_state_is_active:
    return false
  graph.nodes[index].state = completed
  true

proc node_is_running*(graph: WorkGraph; node_id: uint32): bool =
  let index = graph.node_index(node_id)
  index >= 0 and graph.nodes[index].state == running

proc node_can_accept_user_input*(graph: WorkGraph; node_id: uint32): bool =
  let index = graph.node_index(node_id)
  index >= 0 and graph.nodes[index].state.node_state_is_active

proc mark_awaiting_human_input*(graph: var WorkGraph; node_id: uint32): bool =
  let index = graph.node_index(node_id)
  if index < 0 or graph.nodes[index].state notin {pending, running}:
    return false
  graph.nodes[index].state = awaiting_human_input
  true

proc answer_human_input*(graph: var WorkGraph; node_id: uint32;
    answer: string): bool =
  let index = graph.node_index(node_id)
  if index < 0 or graph.nodes[index].execution_plan.`type` != human_input or
      graph.nodes[index].state != awaiting_human_input or answer.strip.len == 0:
    return false
  graph.complete_node(node_id)

proc drain_outgoing_messages*(graph: var WorkGraph): seq[WorkGraphMessage] =
  result = graph.outgoing_messages
  graph.outgoing_messages = @[]

proc send_work_graph_message(graph: var WorkGraph; bridge: CodexBridge;
    node_id: uint32; text: string): bool =
  try:
    bridge.send_node_message(node_id, text)
    graph.outgoing_messages.add(WorkGraphMessage(
      node_id: node_id,
      text: text))
    true
  except CatchableError as error:
    discard graph.fail_node(node_id, error.msg)
    false

proc start_available_nodes*(graph: var WorkGraph; bridge: CodexBridge) =
  for index in 0 ..< graph.nodes.len:
    if not graph.node_runnable(graph.nodes[index]):
      continue
    let node_id = graph.nodes[index].id
    let prompt = graph.nodes[index].node_prompt()
    if graph.nodes[index].execution_plan.`type` == human_input:
      if graph.mark_awaiting_human_input(node_id):
        graph.outgoing_messages.add(WorkGraphMessage(
          node_id: node_id, text: prompt))
      continue
    if bridge == nil:
      continue
    graph.nodes[index].state = running
    discard graph.send_work_graph_message(bridge, node_id, prompt)

proc reply_finish_node(bridge: CodexBridge; event: CodexRuntimeEvent;
    success: bool; message: string): bool =
  if bridge == nil:
    return false
  bridge.reply_server_request(
    event.request_id_value,
    event.node_id,
    DynamicToolCallResponse(
      success: success,
      content_items: if message.len > 0:
        @[dynamic_tool_text(message)]
      else: @[]))

proc handle_finish_node_call(graph: var WorkGraph; bridge: CodexBridge;
    event: CodexRuntimeEvent) =
  if event.tool_name != finish_node_name:
    discard graph.fail_node(event.node_id, "unknown dynamic tool: " & event.tool_name)
    discard bridge.reply_finish_node(event, false, "unknown dynamic tool")
    return

  let index = graph.node_index(event.node_id)
  if index >= 0 and graph.nodes[index].state == running:
    if not bridge.reply_finish_node(event, true, "node completed"):
      discard graph.fail_node(event.node_id, "finish_node response could not be queued")
  else:
    discard graph.fail_node(event.node_id, "finish_node called for non-running node")
    discard bridge.reply_finish_node(event, false, "finish_node failed")

proc handle_codex_event*(graph: var WorkGraph; bridge: CodexBridge;
    event: CodexRuntimeEvent) =
  case event.kind
  of cre_global_notification:
    if event.notification_kind == nk_thread_status_changed and
        event.thread_status.isSome and
        event.thread_status.get.thread_status_is_terminal:
      let reason = if event.thread_status.get == tsk_system_error:
        "Codex thread system error" else: "Codex thread not loaded"
      discard graph.fail_node(event.node_id, reason)
    elif event.server_request_kind == sr_tool_user_input:
      discard graph.mark_awaiting_human_input(event.node_id)
    elif event.server_request_kind == sr_tool_call:
      graph.handle_finish_node_call(bridge, event)
  of cre_turn_completed:
    discard graph.complete_node(event.node_id)
  of cre_tool_response_sent:
    if event.server_request_kind != sr_tool_user_input:
      discard graph.complete_node(event.node_id)
  of cre_thread_error, cre_node_error:
    discard graph.fail_node(event.node_id, event.text)
  of cre_runtime_closed:
    var active_node_ids: seq[uint32] = @[]
    for node in graph.nodes:
      if node.state.node_state_is_active:
        active_node_ids.add(node.id)
    for node_id in active_node_ids:
      discard graph.fail_node(node_id, "Codex runtime closed")
  else:
    discard
