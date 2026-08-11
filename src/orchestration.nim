import std/[os, options, strutils]
import codex_bridge
import codex_json
import orchestration_storage

type
  ExecutionPlanType* = enum
    llm_worker
    graph_creation
    human_input

  ExecutionPlan* = object
    `type`*: ExecutionPlanType
    instructions*: string

  InputArtifactRef* = object
    producer_node_id*: uint32
    path*: string
    description*: string

  OutputArtifactDecl* = object
    path*: string
    description*: string
    final*: bool

  NodeState* = enum
    pending
    running
    awaiting_human_input
    completed
    failed

  WorkNode* = object
    id*: uint32
    description*: string
    objective*: string
    inputs*: seq[InputArtifactRef]
    outputs*: seq[OutputArtifactDecl]
    wait_for*: seq[uint32]
    state*: NodeState
    execution_plan*: ExecutionPlan

  WorkGraphMessage* = object
    node_id*: uint32
    text*: string

  WorkGraph* = object
    nodes*: seq[WorkNode]
    artifact_root*: string
    log_messages*: seq[string]
    outgoing_messages*: seq[WorkGraphMessage]

proc new_work_graph*(cwd = getCurrentDir(); objective = ""): WorkGraph =
  WorkGraph(
    artifact_root: orchestration_paths(cwd).artifacts,
    nodes: @[
      WorkNode(
        id: 1,
        description: "Create work graph",
        objective: objective,
        state: pending,
        execution_plan: ExecutionPlan(
          `type`: graph_creation,
          instructions: "Construct the work graph for the objective. If material ambiguities or underspecifications exist, strongly prefer creating one or more human_input nodes and a subsequent graph_creation node that consumes and synthesizes their responses before expanding the affected work."))])

proc node_index(graph: WorkGraph; node_id: uint32): int =
  for index, node in graph.nodes:
    if node.id == node_id:
      return index
  -1

proc artifact_path_is_valid(path: string): bool =
  if path.len == 0 or path.isAbsolute:
    return false
  for component in path.split({DirSep, AltSep}):
    if component == "..":
      return false
  true

proc graph_artifact_root(graph: WorkGraph): string =
  if graph.artifact_root.len == 0:
    raise newException(ValueError, "artifact root is not configured")
  graph.artifact_root

proc resolve_artifact_path(graph: WorkGraph; node_id: uint32;
    path: string): string =
  if not path.artifact_path_is_valid:
    raise newException(ValueError, "invalid artifact path: " & path)
  joinPath(graph.graph_artifact_root, $node_id, path)

proc resolve_input_path*(graph: WorkGraph; input: InputArtifactRef): string =
  graph.resolve_artifact_path(input.producer_node_id, input.path)

proc resolve_output_path*(graph: WorkGraph; node_id: uint32;
    output: OutputArtifactDecl): string =
  graph.resolve_artifact_path(node_id, output.path)

proc output_declared(node: WorkNode; path: string): bool =
  for output in node.outputs:
    if output.path == path:
      return true
  false

proc node_artifact_error*(graph: WorkGraph; node: WorkNode): string =
  var output_paths: seq[string] = @[]
  for output in node.outputs:
    if not output.path.artifact_path_is_valid:
      return "invalid output artifact path: " & output.path
    if output.path in output_paths:
      return "duplicate output artifact path: " & output.path
    output_paths.add(output.path)

  if node.execution_plan.`type` == graph_creation and node.outputs.len > 0:
    return "graph_creation nodes cannot declare output artifacts"

  for input in node.inputs:
    if not input.path.artifact_path_is_valid:
      return "invalid input artifact path: " & input.path
    let producer_index = graph.node_index(input.producer_node_id)
    if producer_index < 0:
      return "unknown input artifact producer node: " &
        $input.producer_node_id
    if not graph.nodes[producer_index].output_declared(input.path):
      return "input artifact is not declared by producer: " &
        $input.producer_node_id & "/" & input.path
  ""

proc node_dependency_ids(node: WorkNode): seq[uint32] =
  for dependency_id in node.wait_for:
    if dependency_id notin result:
      result.add(dependency_id)
  for input in node.inputs:
    if input.producer_node_id notin result:
      result.add(input.producer_node_id)

proc node_completion_error*(graph: WorkGraph; node_id: uint32): string =
  let index = graph.node_index(node_id)
  if index < 0:
    return "unknown node"
  let node = graph.nodes[index]
  result = graph.node_artifact_error(node)
  if result.len > 0:
    return
  if node.execution_plan.`type` == human_input:
    let path = graph.resolve_artifact_path(node_id, "response.txt")
    if not path.path_exists:
      return "missing human input artifact: " & path
    return
  if node.execution_plan.`type` != llm_worker:
    return
  for output in node.outputs:
    let path = graph.resolve_output_path(node_id, output)
    if not path.path_exists:
      return "missing output artifact: " & path

proc add_artifact_prompt(result: var string; path, description: string) =
  result.add("Resolved path: " & path & "\n")
  result.add("Description: " & description & "\n\n")

proc node_developer_prompt*(graph: WorkGraph; node: WorkNode): string =
  if node.inputs.len == 0 and node.outputs.len == 0:
    return ""
  result = ""
  if node.inputs.len > 0:
    result.add("Input artifacts:\n")
  for input in node.inputs:
    result.add_artifact_prompt(graph.resolve_input_path(input), input.description)
  if node.outputs.len > 0:
    result.add("Output artifacts:\n")
  for output in node.outputs:
    result.add_artifact_prompt(
      graph.resolve_output_path(node.id, output), output.description)

proc final_artifact_paths*(graph: WorkGraph): seq[string] =
  for node in graph.nodes:
    if node.state != completed:
      continue
    for output in node.outputs:
      if output.final:
        let path = graph.resolve_output_path(node.id, output)
        if path.path_exists:
          result.add(path)

proc node_runnable(graph: WorkGraph; node: WorkNode): bool =
  if node.state != pending:
    return false
  if graph.node_artifact_error(node).len > 0:
    return false
  for dependency_id in node.node_dependency_ids:
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
  result = node.execution_plan.instructions
  if node.objective.len > 0:
    if result.len > 0:
      result.add("\n\n")
    result.add("Objective:\n" & node.objective)
  if result.len > 0:
    return
  return "Your execution type is " & $node.execution_plan.`type` & ". Do nothing."

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

proc complete_node_state(graph: var WorkGraph; index: int): bool =
  if index < 0 or not graph.nodes[index].state.node_state_is_active:
    return false
  graph.nodes[index].state = completed
  true

proc attempt_completion*(graph: var WorkGraph; node_id: uint32): bool =
  let index = graph.node_index(node_id)
  if index < 0 or not graph.nodes[index].state.node_state_is_active:
    return false
  let completion_error = graph.node_completion_error(node_id)
  if completion_error.len > 0:
    discard graph.fail_node(node_id, completion_error)
    return false
  graph.complete_node_state(index)

proc complete_node*(graph: var WorkGraph; node_id: uint32): bool =
  graph.attempt_completion(node_id)

proc node_is_running*(graph: WorkGraph; node_id: uint32): bool =
  let index = graph.node_index(node_id)
  index >= 0 and graph.nodes[index].state == running

proc node_can_accept_user_input*(graph: WorkGraph; node_id: uint32): bool =
  let index = graph.node_index(node_id)
  index >= 0 and graph.nodes[index].state.node_state_is_active

proc set_node_objective*(graph: var WorkGraph; node_id: uint32;
    objective: string): bool =
  let index = graph.node_index(node_id)
  if index < 0 or objective.len == 0:
    return false
  if graph.nodes[index].objective.len > 0:
    return false
  graph.nodes[index].objective = objective
  true

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
  try:
    let path = graph.resolve_artifact_path(node_id, "response.txt")
    createDir(graph.graph_artifact_root)
    createDir(parentDir(path))
    writeFile(path, "Instructions:\n" &
      graph.nodes[index].execution_plan.instructions &
      "\n\nResponse:\n" & answer)
    graph.attempt_completion(node_id)
  except CatchableError as error:
    discard graph.fail_node(node_id, error.msg)
    false

proc drain_outgoing_messages*(graph: var WorkGraph): seq[WorkGraphMessage] =
  result = graph.outgoing_messages
  graph.outgoing_messages = @[]

proc send_work_graph_message(graph: var WorkGraph; bridge: CodexBridge;
    node_id: uint32; text: string; developer_instructions = ""): bool =
  try:
    bridge.send_node_message(node_id, text, developer_instructions)
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
    let developer_prompt = graph.node_developer_prompt(graph.nodes[index])
    if graph.nodes[index].execution_plan.`type` == human_input:
      if graph.mark_awaiting_human_input(node_id):
        graph.outgoing_messages.add(WorkGraphMessage(
          node_id: node_id, text: prompt))
      continue
    if bridge == nil:
      continue
    graph.nodes[index].state = running
    discard graph.send_work_graph_message(bridge, node_id, prompt,
      developer_prompt)

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
    let completion_error = graph.node_completion_error(event.node_id)
    if completion_error.len > 0:
      discard graph.fail_node(event.node_id, completion_error)
      discard bridge.reply_finish_node(event, false, completion_error)
    elif not bridge.reply_finish_node(event, true, "node completed"):
      discard graph.fail_node(event.node_id, "finish_node response could not be queued")
    else:
      discard graph.complete_node_state(index)
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
    discard graph.attempt_completion(event.node_id)
  of cre_tool_response_sent:
    discard
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
