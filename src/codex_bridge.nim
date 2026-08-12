import std/[json, locks, options, os, streams, tables]
import codex_json
import codex_runtime

type
  CodexServerResponseKind* = enum
    csr_dynamic_tool_call,
    csr_user_input

  CodexServerResponse* = object
    case kind*: CodexServerResponseKind
    of csr_dynamic_tool_call:
      dynamic_tool_response*: DynamicToolCallResponse
    of csr_user_input:
      user_input_answers*: seq[UserInputAnswer]

  CodexRuntimeInputKind* = enum
    cri_send_node_message,
    cri_reply_server_request,
    cri_terminalize_node,
    cri_shutdown,
    cri_stdout_line,
    cri_stderr_line,
    cri_stdout_closed

  CodexRuntimeInput* = object
    case kind*: CodexRuntimeInputKind
    of cri_send_node_message:
      message_node_id*: uint32
      message_text*: string
      developer_instructions*: string
      graph_creation_node*: bool
      reasoning_effort*: ReasoningEffort
    of cri_reply_server_request:
      server_request_id*: RequestId
      server_request_node_id*: uint32
      server_response*: CodexServerResponse
    of cri_terminalize_node:
      terminal_node_id*: uint32
    of cri_shutdown:
      discard
    of cri_stdout_line, cri_stderr_line:
      line*: string
    of cri_stdout_closed:
      discard

  CodexRuntimeEventKind* = enum
    cre_thread_ready,
    cre_thread_error,
    cre_agent_message_delta,
    cre_turn_completed,
    cre_node_error,
    cre_tool_response_sent,
    cre_global_notification,
    cre_lifecycle_diagnostic,
    cre_runtime_error,
    cre_runtime_closed

  CodexRuntimeEvent* = object
    kind*: CodexRuntimeEventKind
    node_id*: uint32
    text*: string
    method_name*: string
    thread_id*: string
    turn_id*: string
    item_id*: string
    request_id*: string
    request_id_value*: RequestId
    tool_name*: string
    params_json*: string
    response_json*: string
    conversation_scoped*: bool
    notification_kind*: NotificationKind
    thread_status*: Option[ThreadStatusKind]
    active_flags*: set[ActiveFlag]
    will_retry*: Option[bool]
    server_request_kind*: ServerRequestKind

  CodexReaderContext = object
    bridge: ptr CodexBridgeState
    stream: Stream
    line_kind: CodexRuntimeInputKind

  CodexBridgeState* = object
    input_channel: Channel[CodexRuntimeInput]
    event_channel: Channel[CodexRuntimeEvent]
    worker_thread: Thread[ptr CodexBridgeState]
    stdout_thread: Thread[ptr CodexReaderContext]
    stderr_thread: Thread[ptr CodexReaderContext]
    stdout_reader: CodexReaderContext
    stderr_reader: CodexReaderContext
    stdout_thread_started: bool
    stderr_thread_started: bool
    terminalization_lock: Lock
    terminalization_requests: Table[uint32, bool]

  CodexBridge* = ptr CodexBridgeState

proc server_request_kind(response: CodexServerResponse): ServerRequestKind =
  case response.kind
  of csr_dynamic_tool_call: sr_tool_call
  of csr_user_input: sr_tool_user_input

proc serialize(response: CodexServerResponse): JsonNode =
  case response.kind
  of csr_dynamic_tool_call:
    serialize_dynamic_tool_call_response(response.dynamic_tool_response)
  of csr_user_input:
    serialize_user_input_response(response.user_input_answers)

const
  finish_node_name* = "finish_node"
  create_node_name* = "create_node"
  update_node_name* = "update_node"
  delete_node_name* = "delete_node"
  reassign_output_name* = "reassign_output"
  get_node_name* = "get_node"
  get_graph_view_name* = "get_graph_view"
  list_pending_edits_name* = "list_pending_edits"
  get_pending_edit_name* = "get_pending_edit"
  discard_edit_name* = "discard_edit"
  llm_worker_type_name* = "llm_worker"
  graph_creation_type_name* = "graph_creation"
  human_input_type_name* = "human_input"
  straightforward_reasoning_name* = "straightforward"
  bounded_reasoning_name* = "bounded"
  deep_reasoning_name* = "deep_reasoning"

proc graph_creation_tools*(): seq[DynamicTool]

proc is_graph_creation_tool_name*(name: string): bool =
  for tool in graph_creation_tools():
    if tool.name == name:
      return true
  false

proc graph_tool(name, description: string; input_schema: JsonNode): DynamicTool =
  DynamicTool(
    name: name,
    description: description,
    input_schema: input_schema,
    data: nil,
    callback: nil)

proc object_schema(properties: JsonNode; required: seq[string]): JsonNode =
  result = newJObject()
  result["type"] = %"object"
  result["properties"] = properties
  result["additionalProperties"] = %false
  if required.len > 0:
    result["required"] = %required

proc finish_node_tool*(): DynamicTool =
  graph_tool(
    finish_node_name,
    "Complete node. Tip: write outputs first; graph creators need no pending edits.",
    object_schema(newJObject(), @[]))

proc string_schema(description = ""): JsonNode =
  result = newJObject()
  result["type"] = %"string"
  if description.len > 0:
    result["description"] = %description

proc string_array_schema(description = ""): JsonNode =
  result = newJObject()
  result["type"] = %"array"
  result["items"] = string_schema()
  if description.len > 0:
    result["description"] = %description

proc integer_schema(description = ""; minimum = 1): JsonNode =
  result = newJObject()
  result["type"] = %"integer"
  result["minimum"] = %minimum
  if description.len > 0:
    result["description"] = %description

proc node_definition_schema(): JsonNode =
  var properties = newJObject()
  properties["description"] = string_schema("Extremely short graph label.")
  properties["objective"] = string_schema("Required node result.")
  properties["inputs"] = newJObject()
  properties["inputs"]["type"] = %"array"
  properties["inputs"]["description"] = %"File inputs from earlier node outputs."
  var input_schema = object_schema(
    %*{
      "producer_node_id": {
        "type": "integer", "minimum": 1,
        "description": "Existing producer node ID."},
      "path": {
        "type": "string",
        "description": "Declared output path on producer."},
      "description": {
        "type": "string",
        "description": "How consumer uses this file."}
    }, @["producer_node_id", "path", "description"])
  input_schema["description"] = %"All three fields are required."
  properties["inputs"]["items"] = input_schema
  properties["outputs"] = newJObject()
  properties["outputs"]["type"] = %"array"
  properties["outputs"]["description"] = %"Files for final user or downstream workers. Omit for human_input; runtime adds response.txt."
  var output_schema = object_schema(
    %*{
      "path": {
        "type": "string",
        "description": "Relative file path this node writes."},
      "description": {
        "type": "string",
        "description": "What this file contains."},
      "final": {
        "type": "boolean",
        "description": "True when reportable to final user."}
    }, @["path", "description"])
  output_schema["description"] = %"Declare files only; do not use outputs for graph structure."
  properties["outputs"]["items"] = output_schema
  properties["wait_for"] = newJObject()
  properties["wait_for"]["type"] = %"array"
  properties["wait_for"]["description"] = %"Node IDs that must complete first."
  properties["wait_for"]["items"] = integer_schema()
  let reasoning_level_schema = %*{
    "type": "string", "enum": [
      straightforward_reasoning_name, bounded_reasoning_name,
      deep_reasoning_name]}
  let worker_type_schema = %*{
    "type": "string", "enum": [llm_worker_type_name, human_input_type_name]}
  let graph_creation_type_schema = %*{
    "type": "string", "enum": [graph_creation_type_name]}
  var worker_properties = newJObject()
  worker_properties["type"] = worker_type_schema
  worker_properties["instructions"] = string_schema()
  worker_properties["reasoning_level"] = reasoning_level_schema
  var graph_creation_properties = newJObject()
  graph_creation_properties["type"] = graph_creation_type_schema
  graph_creation_properties["instructions"] = string_schema()
  graph_creation_properties["allowed"] = string_array_schema(
    "Decision scopes allowed for graph_creation only.")
  graph_creation_properties["disallowed"] = string_array_schema(
    "Explicitly disallowed decision scopes for graph_creation only.")
  graph_creation_properties["reasoning_level"] = reasoning_level_schema
  properties["execution_plan"] = newJObject()
  properties["execution_plan"]["oneOf"] = newJArray()
  properties["execution_plan"]["oneOf"].add(object_schema(
    worker_properties, @["type", "instructions"]))
  properties["execution_plan"]["oneOf"].add(object_schema(
    graph_creation_properties, @["type", "instructions"]))
  object_schema(properties, @[
    "description", "objective", "inputs", "wait_for",
    "execution_plan"])

proc node_changes_schema(): JsonNode =
  result = node_definition_schema()
  result["required"] = newJArray()

proc graph_creation_tools*(): seq[DynamicTool] =
  var create_properties = newJObject()
  create_properties["node_definition"] = node_definition_schema()
  create_properties["edit_id"] = integer_schema("Pending edit to replace.")

  var update_properties = newJObject()
  update_properties["node_id"] = integer_schema()
  update_properties["changes"] = node_changes_schema()
  update_properties["edit_id"] = integer_schema("Pending edit to replace.")

  var delete_properties = newJObject()
  delete_properties["node_id"] = integer_schema()
  delete_properties["edit_id"] = integer_schema("Pending edit to replace.")

  var reassign_properties = newJObject()
  reassign_properties["source_node_id"] = integer_schema()
  reassign_properties["source_path"] = string_schema()
  reassign_properties["destination_node_id"] = integer_schema()
  reassign_properties["destination_path"] = string_schema(
    "Optional. Omit to preserve the source path.")
  reassign_properties["edit_id"] = integer_schema("Pending edit to replace.")

  var get_node_properties = newJObject()
  get_node_properties["node_id"] = integer_schema()

  var graph_view_properties = newJObject()
  graph_view_properties["direction"] = %*{
    "type": "string",
    "enum": ["ancestor", "descendant", "bidirectional"]
  }
  graph_view_properties["depth"] = integer_schema(minimum = 0)
  graph_view_properties["max_nodes"] = integer_schema()

  var pending_edit_properties = newJObject()
  pending_edit_properties["edit_id"] = integer_schema()

  result = @[
    graph_tool(create_node_name,
      "Create pending node. Inputs need producer_node_id, path, description; human_input may omit outputs; runtime adds response.txt.", object_schema(
      create_properties, @["node_definition"])),
    graph_tool(update_node_name,
      "Update pending node. On pending_invalid, retry same tool with edit_id.", object_schema(
      update_properties, @["node_id", "changes"])),
    graph_tool(delete_node_name,
      "Delete pending node. On pending_invalid, retry same tool with edit_id.", object_schema(
      delete_properties, @["node_id"])),
    graph_tool(reassign_output_name,
      "Move declared output. Omit destination_path to keep source path.", object_schema(
      reassign_properties, @[
        "source_node_id", "source_path", "destination_node_id"])),
    graph_tool(get_node_name, "Read canonical node before editing.", object_schema(
      get_node_properties, @["node_id"])),
    graph_tool(get_graph_view_name,
      "Inspect graph. Tip: bidirectional, depth 1, max_nodes 8.", object_schema(
      graph_view_properties, @["direction", "depth", "max_nodes"])),
    graph_tool(list_pending_edits_name, "List this creator's staged edits.", object_schema(
      newJObject(), @[])),
    graph_tool(get_pending_edit_name, "Inspect staged edit before correcting.", object_schema(
      pending_edit_properties, @["edit_id"])),
    graph_tool(discard_edit_name, "Discard staged edit instead of correcting.", object_schema(
      pending_edit_properties, @["edit_id"]))]

proc emit_event(bridge: ptr CodexBridgeState; event: CodexRuntimeEvent) =
  bridge[].event_channel.send(event)

proc emit_lifecycle_diagnostic(bridge: ptr CodexBridgeState; node_id: uint32;
    text: string; thread_id = ""; turn_id = ""; request_id = "") =
  bridge.emit_event(CodexRuntimeEvent(
    kind: cre_lifecycle_diagnostic,
    node_id: node_id,
    text: text,
    thread_id: thread_id,
    turn_id: turn_id,
    request_id: request_id))

proc read_lines(context: ptr CodexReaderContext) {.thread.} =
  var line = ""
  try:
    while context[].stream.readLine(line):
      case context[].line_kind
      of cri_stdout_line:
        context[].bridge[].input_channel.send(CodexRuntimeInput(
          kind: cri_stdout_line,
          line: line))
      of cri_stderr_line:
        context[].bridge[].input_channel.send(CodexRuntimeInput(
          kind: cri_stderr_line,
          line: line))
      else:
        discard
  except CatchableError:
    discard
  if context[].line_kind == cri_stdout_line:
    context[].bridge[].input_channel.send(CodexRuntimeInput(
      kind: cri_stdout_closed))

proc agent_id_for_node(node_id: uint32): AgentId =
  "graph_node_" & $node_id

proc node_id_for_thread(thread_nodes: Table[string, uint32];
    thread_id: string): Option[uint32] =
  if thread_nodes.hasKey(thread_id):
    return some(thread_nodes[thread_id])
  none(uint32)

proc params_prefix(params: JsonNode): string =
  result = $params
  if result.len > 40:
    result = result[0 ..< 40]

proc notification_thread_id(notification: Notification): string =
  if notification.params.thread_id.has_value:
    result = notification.params.thread_id.value

proc notification_turn_id(notification: Notification): string =
  if notification.params.turn_id.isSome:
    result = notification.params.turn_id.get

proc notification_item_id(notification: Notification): string =
  if notification.params.item_id.isSome:
    result = notification.params.item_id.get

proc server_request_event(thread_nodes: Table[string, uint32];
    request: ServerRequest): CodexRuntimeEvent =
  let identity = server_request_identity(request)
  let thread_id = identity.thread_id
  CodexRuntimeEvent(
    kind: cre_global_notification,
    node_id: if thread_id.isSome:
      node_id_for_thread(thread_nodes, thread_id.get).get(0'u32)
    else:
      0'u32,
    text: "server request: " & request.method_name,
    method_name: request.method_name,
    thread_id: if thread_id.isSome: thread_id.get else: "",
    turn_id: if identity.turn_id.isSome: identity.turn_id.get else: "",
    item_id: if identity.item_id.isSome: identity.item_id.get else: "",
    request_id: request_id_key(request.id),
    request_id_value: request.id,
    tool_name: if request.kind == sr_tool_call:
      request.params.tool_call.tool
    else: "",
    params_json: request.params_json,
    conversation_scoped: true,
    notification_kind: nk_unknown,
    server_request_kind: request.kind)

proc notification_event(notification: Notification; node_id: uint32;
    kind = cre_global_notification; text = ""): CodexRuntimeEvent =
  let event_text =
    if text.len > 0:
      text
    elif notification.kind in {nk_turn_diff_updated,
        nk_file_change_output_delta}:
      notification.method_name & " activity"
    else:
      notification.method_name & " " &
        params_prefix(notification.params.raw_params)
  CodexRuntimeEvent(
    kind: kind,
    node_id: node_id,
    text: event_text,
    method_name: notification.method_name,
    thread_id: notification_thread_id(notification),
    turn_id: notification_turn_id(notification),
    item_id: notification_item_id(notification),
    params_json: notification_payload_json(notification),
    conversation_scoped: notification.kind.is_conversation_notification,
    notification_kind: notification.kind,
    thread_status: notification.params.thread_status,
    active_flags: notification.params.active_flags,
    will_retry: notification.params.will_retry,
    server_request_kind: sr_unknown)

proc emit_unknown_notification(bridge: ptr CodexBridgeState;
    notification: Notification) =
  bridge.emit_event(CodexRuntimeEvent(
    kind: cre_global_notification,
    text: notification.method_name & " " &
      params_prefix(notification.params.raw_params)))

proc clear_queued_messages(queued_messages: var Table[uint32, string];
    node_id: uint32) =
  queued_messages.del(node_id)

proc clear_turn_request_mapping(runtime: ptr CodexRuntime;
    request_nodes: var Table[string, uint32]; node_id: uint32;
    turn_id: string) =
  var keys: seq[string] = @[]
  for key, mapped_node_id in request_nodes:
    if mapped_node_id != node_id or not runtime.requests.hasKey(key):
      continue
    let request = runtime.requests[key]
    if request.request.kind == mk_turn_start and
        request.turn_id.isSome and request.turn_id.get == turn_id:
      keys.add(key)
  for key in keys:
    request_nodes.del(key)

proc terminalize_node_transport(runtime: ptr CodexRuntime;
    node_id: uint32; thread_nodes: Table[string, uint32];
    turn_nodes: var Table[string, string];
    queued_messages: var Table[uint32, string];
    terminal_nodes: var Table[uint32, bool]) =
  if terminal_nodes.getOrDefault(node_id):
    return
  terminal_nodes[node_id] = true
  queued_messages.clear_queued_messages(node_id)
  var thread_ids: seq[string] = @[]
  for thread_id, mapped_node_id in thread_nodes:
    if mapped_node_id == node_id:
      thread_ids.add(thread_id)
  for thread_id in thread_ids:
    turn_nodes.del(thread_id)
  discard runtime.terminalize_agent(agent_id_for_node(node_id))

proc mark_terminalization_requested(bridge: ptr CodexBridgeState;
    node_id: uint32) =
  acquire(bridge[].terminalization_lock)
  bridge[].terminalization_requests[node_id] = true
  release(bridge[].terminalization_lock)

proc terminalization_requested(bridge: ptr CodexBridgeState;
    node_id: uint32): bool =
  acquire(bridge[].terminalization_lock)
  result = bridge[].terminalization_requests.getOrDefault(node_id)
  release(bridge[].terminalization_lock)

proc node_is_terminal(bridge: ptr CodexBridgeState;
    terminal_nodes: Table[uint32, bool]; node_id: uint32): bool =
  terminal_nodes.getOrDefault(node_id) or
    terminalization_requested(bridge, node_id)

proc wire_request_key(node: JsonNode): string =
  if not node.hasKey("id"):
    return ""
  let id = node["id"]
  case id.kind
  of JString:
    "s:" & id.getStr
  of JInt:
    "i:" & $id.getInt
  else:
    ""

proc terminal_node_for_wire_message(bridge: ptr CodexBridgeState;
    node: JsonNode; request_nodes: Table[string, uint32];
    thread_nodes: Table[string, uint32];
    terminal_nodes: Table[uint32, bool]): uint32 =
  let request_key = wire_request_key(node)
  if request_key.len > 0:
    let node_id = request_nodes.getOrDefault(request_key, 0'u32)
    if node_id > 0 and bridge.node_is_terminal(terminal_nodes, node_id):
      return node_id
  if node.kind != JObject or not node.hasKey("params") or
      node["params"].kind != JObject or
      not node["params"].hasKey("threadId"):
    return 0
  let node_id = thread_nodes.getOrDefault(
    node["params"]["threadId"].getStr,
    0'u32)
  if node_id > 0 and bridge.node_is_terminal(terminal_nodes, node_id):
    node_id
  else:
    0

proc send_next_queued_message(runtime: ptr CodexRuntime;
    bridge: ptr CodexBridgeState; node_id: uint32;
    request_nodes: var Table[string, uint32];
    queued_messages: var Table[uint32, string];
    terminal_nodes: Table[uint32, bool]) =
  if terminal_nodes.getOrDefault(node_id):
    queued_messages.clear_queued_messages(node_id)
    bridge.emit_lifecycle_diagnostic(
      node_id,
      "post-terminal turn start suppressed")
    return
  let agent_id = agent_id_for_node(node_id)
  if not queued_messages.hasKey(node_id):
    return
  if not runtime.agents.hasKey(agent_id):
    return
  let agent = runtime.agents[agent_id]
  if not agent.thread_id.has_value or agent.state != as_idle:
    return
  let message = queued_messages[node_id]
  try:
    let request_id = runtime.send_agent_message(agent_id, message)
    request_nodes[request_id_key(request_id)] = node_id
    queued_messages.clear_queued_messages(node_id)
  except CatchableError as error:
    var failed_agent = runtime.agents[agent_id]
    failed_agent.state = as_error
    runtime.agents[agent_id] = failed_agent
    queued_messages.clear_queued_messages(node_id)
    bridge.emit_event(CodexRuntimeEvent(
      kind: cre_node_error,
      node_id: node_id,
      text: error.msg))

proc suppress_terminal_event(bridge: ptr CodexBridgeState;
    terminal_nodes: Table[uint32, bool]; node_id: uint32; reason: string;
    thread_id = ""; turn_id = ""; request_id = ""): bool =
  if not bridge.node_is_terminal(terminal_nodes, node_id):
    return false
  bridge.emit_lifecycle_diagnostic(
    node_id, reason, thread_id, turn_id, request_id)
  true

proc handle_runtime_message(runtime: ptr CodexRuntime;
    bridge: ptr CodexBridgeState; message: Message;
    request_nodes: var Table[string, uint32];
    thread_nodes: var Table[string, uint32];
    turn_nodes: var Table[string, string];
    queued_messages: var Table[uint32, string];
    terminal_nodes: Table[uint32, bool]) =
  case message.kind
  of mk_success:
    let request_key = request_id_key(message.success.id)
    if not runtime.requests.hasKey(request_key):
      let node_id = request_nodes.getOrDefault(request_key, 0'u32)
      if terminal_nodes.getOrDefault(node_id):
        bridge.emit_lifecycle_diagnostic(
          node_id,
          "late provider success suppressed")
        request_nodes.del(request_key)
      return
    let request = runtime.requests[request_key]
    if request.request.kind == mk_initialize:
      return
    if request.request.kind == mk_thread_start and request.agent_id.isSome:
      let node_id = request_nodes.getOrDefault(request_key, 0'u32)
      if terminal_nodes.getOrDefault(node_id):
        bridge.emit_lifecycle_diagnostic(
          node_id,
          "post-terminal thread start suppressed",
          message.success.result.thread_id)
        discard runtime.state.terminalize_agent(request.agent_id.get)
        request_nodes.del(request_key)
        return
      thread_nodes[message.success.result.thread_id] = node_id
      bridge.emit_event(CodexRuntimeEvent(
        kind: cre_thread_ready,
        node_id: node_id,
        text: message.success.result.thread_id,
        thread_id: message.success.result.thread_id))
      request_nodes.del(request_key)
      send_next_queued_message(
        runtime, bridge, node_id, request_nodes, queued_messages,
        terminal_nodes)
  of mk_error:
    let request_key = request_id_key(message.error.id)
    let node_id = request_nodes.getOrDefault(request_key, 0'u32)
    if terminal_nodes.getOrDefault(node_id):
      bridge.emit_lifecycle_diagnostic(
        node_id,
        "late provider error suppressed")
      request_nodes.del(request_key)
      return
    var event_kind = if node_id == 0: cre_runtime_error else: cre_node_error
    if runtime.requests.hasKey(request_key):
      let request = runtime.requests[request_key]
      if request.request.kind == mk_thread_start:
        event_kind = cre_thread_error
        if request.agent_id.isSome:
          discard runtime.state.terminalize_agent(request.agent_id.get)
          queued_messages.clear_queued_messages(node_id)
      elif request.request.kind == mk_turn_start and request.agent_id.isSome:
        queued_messages.clear_queued_messages(node_id)
    request_nodes.del(request_key)
    bridge.emit_event(CodexRuntimeEvent(
      kind: event_kind,
      node_id: node_id,
      text: message.error.message))
  of mk_notification:
    let notification = message.notification
    let thread_id = notification.params.thread_id
    let thread_node_id = if thread_id.has_value:
      node_id_for_thread(thread_nodes, thread_id.value)
    else:
      none(uint32)
    case notification.kind
    of nk_agent_message_delta:
      if thread_node_id.isSome and notification.params.delta.isSome:
        let node_id = thread_node_id.get
        if bridge.suppress_terminal_event(
            terminal_nodes,
            node_id,
            "late agent message suppressed",
            thread_id.value,
            notification_turn_id(notification)):
          return
        bridge.emit_event(notification_event(
          notification,
          node_id,
          cre_agent_message_delta,
          notification.params.delta.get))
    of nk_turn_completed:
      if thread_node_id.isSome:
        let node_id = thread_node_id.get
        let turn_id = notification_turn_id(notification)
        if bridge.suppress_terminal_event(
            terminal_nodes,
            node_id,
            "late turn completion suppressed",
            thread_id.value,
            turn_id):
          return
        let current_turn_id = turn_nodes.getOrDefault(thread_id.value, "")
        if current_turn_id.len == 0 or turn_id.len == 0 or
            current_turn_id != turn_id:
          bridge.emit_lifecycle_diagnostic(
            node_id,
            if current_turn_id.len == 0:
              "turn completion without current turn correlation"
            elif turn_id.len == 0:
              "turn completion missing turn ID"
            else:
              "turn completion correlation mismatch",
            thread_id.value,
            turn_id)
          return
        let turn_succeeded = notification.params.turn_status.turn_succeeded
        let event_kind = if turn_succeeded: cre_turn_completed else: cre_node_error
        let event_text = if turn_succeeded: "" else:
          notification.params.error_message.get("turn failed")
        bridge.emit_event(notification_event(
          notification, node_id, event_kind, event_text))
        queued_messages.clear_queued_messages(node_id)
        clear_turn_request_mapping(runtime, request_nodes, node_id, turn_id)
        turn_nodes.del(thread_id.value)
      else:
        bridge.emit_event(CodexRuntimeEvent(
          kind: cre_runtime_error,
          node_id: 0,
          text: "unmapped completion",
          thread_id: if thread_id.has_value: thread_id.value else: "",
          turn_id: notification_turn_id(notification)))
    of nk_error:
      if thread_node_id.isSome and bridge.suppress_terminal_event(
          terminal_nodes,
          thread_node_id.get,
          "late provider error suppressed",
          if thread_id.has_value: thread_id.value else: "",
          notification_turn_id(notification)):
        return
      let event_kind = if notification.params.will_retry.retry_requested:
        cre_global_notification
      elif thread_node_id.isSome:
        cre_node_error
      else:
        cre_runtime_error
      let node_id = thread_node_id.get(0'u32)
      if event_kind == cre_node_error:
        queued_messages.clear_queued_messages(node_id)
      bridge.emit_event(notification_event(
        notification,
        node_id,
        event_kind,
        notification.params.error_message.get("runtime error")))
    of nk_thread_closed:
      if thread_node_id.isSome:
        let node_id = thread_node_id.get
        if bridge.suppress_terminal_event(
            terminal_nodes, node_id, "late thread close suppressed",
            thread_id.value):
          return
        discard runtime.terminalize_agent(agent_id_for_node(node_id))
        queued_messages.clear_queued_messages(node_id)
        bridge.emit_event(CodexRuntimeEvent(
          kind: cre_thread_error,
          node_id: node_id,
          text: "Codex thread closed"))
    of nk_unknown:
      if not notification.method_name.is_suppressed_notification:
        emit_unknown_notification(bridge, notification)
    else:
      if thread_node_id.isSome and bridge.suppress_terminal_event(
          terminal_nodes,
          thread_node_id.get,
          "late provider notification suppressed",
          if thread_id.has_value: thread_id.value else: "",
          notification_turn_id(notification)):
        discard
      elif notification.kind == nk_turn_started and thread_node_id.isSome:
        if notification.params.turn_id.isSome:
          turn_nodes[thread_id.value] = notification.params.turn_id.get
        bridge.emit_event(notification_event(
          notification,
          thread_node_id.get(0'u32)))
      elif notification.kind.is_conversation_notification:
        bridge.emit_event(notification_event(
          notification,
          thread_node_id.get(0'u32)))
  of mk_server_request:
    let request = message.server_request
    if request.kind.is_conversation_server_request:
      let request_event = server_request_event(thread_nodes, request)
      if request_event.node_id > 0 and bridge.suppress_terminal_event(
          terminal_nodes,
          request_event.node_id,
          "late server request suppressed",
          request_event.thread_id,
          request_event.turn_id,
          request_event.request_id):
        try:
          runtime.fail_server_request(request.id, -32000, "node is terminal")
        except CatchableError:
          discard
      else:
        bridge.emit_event(request_event)
    else:
      bridge.emit_event(CodexRuntimeEvent(
        kind: cre_global_notification,
        text: "unsupported server request: " & request.method_name,
        method_name: request.method_name,
        request_id: request_id_key(request.id)))
  else:
    discard

proc handle_stdout_line(runtime: ptr CodexRuntime;
    bridge: ptr CodexBridgeState; line: string;
    request_nodes: var Table[string, uint32];
    thread_nodes: var Table[string, uint32];
    turn_nodes: var Table[string, string];
    queued_messages: var Table[uint32, string];
    terminal_nodes: Table[uint32, bool]) =
  try:
    let raw_message = parseJson(line)
    let terminal_node_id = bridge.terminal_node_for_wire_message(
      raw_message, request_nodes, thread_nodes, terminal_nodes)
    let is_notification = raw_message.kind == JObject and
      raw_message.hasKey("method") and not raw_message.hasKey("id")
    if terminal_node_id > 0 and
        (is_notification or not raw_message.hasKey("method")):
      bridge.emit_lifecycle_diagnostic(
        terminal_node_id,
        "late provider message suppressed before runtime apply")
      return
    let message = runtime.accept_json(raw_message)
    handle_runtime_message(
      runtime, bridge, message, request_nodes, thread_nodes, turn_nodes,
      queued_messages, terminal_nodes)
  except CatchableError as error:
    bridge.emit_event(CodexRuntimeEvent(
      kind: cre_runtime_error,
      text: "Codex message error: " & error.msg))

proc handle_create_node_thread(runtime: ptr CodexRuntime;
    bridge: ptr CodexBridgeState; node_id: uint32;
    request_nodes: var Table[string, uint32]; developer_instructions: string;
    graph_creation_node: bool; reasoning_effort: ReasoningEffort) =
  let agent_id = agent_id_for_node(node_id)
  if runtime.agents.hasKey(agent_id):
    return
  try:
    var tools: DynamicToolRegistry = @[finish_node_tool()]
    if graph_creation_node:
      tools.add(graph_creation_tools())
    let request_id = runtime.create_agent(
      agent_id,
      "gpt-5.6-luna",
      tools,
      developer_instructions = developer_instructions,
      default_effort = reasoning_effort)
    request_nodes[request_id_key(request_id)] = node_id
  except CatchableError as error:
    bridge.emit_event(CodexRuntimeEvent(
      kind: cre_thread_error,
      node_id: node_id,
      text: error.msg))

proc handle_send_node_message(runtime: ptr CodexRuntime;
    bridge: ptr CodexBridgeState; input: CodexRuntimeInput;
    request_nodes: var Table[string, uint32];
    queued_messages: var Table[uint32, string];
    terminal_nodes: Table[uint32, bool]) =
  let node_id = input.message_node_id
  if terminal_nodes.getOrDefault(node_id):
    bridge.emit_lifecycle_diagnostic(
      node_id,
      "post-terminal turn start suppressed")
    queued_messages.clear_queued_messages(node_id)
    return
  let agent_id = agent_id_for_node(node_id)
  if runtime.agents.hasKey(agent_id) and
      runtime.agents[agent_id].state != as_idle:
    bridge.emit_event(CodexRuntimeEvent(
      kind: cre_global_notification,
      node_id: 0,
      text: "NODE " & $node_id & " IS BUSY"))
    return
  queued_messages[node_id] = input.message_text
  if not runtime.agents.hasKey(agent_id):
    handle_create_node_thread(runtime, bridge, node_id, request_nodes,
      input.developer_instructions, input.graph_creation_node,
      input.reasoning_effort)
    return
  send_next_queued_message(
    runtime, bridge, node_id, request_nodes, queued_messages, terminal_nodes)

proc handle_command(runtime: ptr CodexRuntime; bridge: ptr CodexBridgeState;
    input: CodexRuntimeInput; request_nodes: var Table[string, uint32];
    thread_nodes: Table[string, uint32];
    turn_nodes: var Table[string, string];
    queued_messages: var Table[uint32, string];
    terminal_nodes: var Table[uint32, bool]) =
  case input.kind
  of cri_send_node_message:
    handle_send_node_message(
      runtime, bridge, input, request_nodes, queued_messages, terminal_nodes)
  of cri_reply_server_request:
    try:
      let response_json = input.server_response.serialize()
      runtime.reply_server_request(
        input.server_request_id,
        response_json)
      bridge.emit_event(CodexRuntimeEvent(
        kind: cre_tool_response_sent,
        node_id: input.server_request_node_id,
        request_id: request_id_key(input.server_request_id),
        request_id_value: input.server_request_id,
        response_json: response_json.pretty,
        conversation_scoped: true,
        server_request_kind: input.server_response.server_request_kind()))
    except CatchableError as error:
      bridge.emit_event(CodexRuntimeEvent(
        kind: cre_node_error,
        node_id: input.server_request_node_id,
        text: "Codex tool response error: " & error.msg))
  of cri_terminalize_node:
    terminalize_node_transport(
      runtime,
      input.terminal_node_id,
      thread_nodes,
      turn_nodes,
      queued_messages,
      terminal_nodes)
  else:
    discard

proc fail_pending_input(bridge: ptr CodexBridgeState;
    input: CodexRuntimeInput; error_message: string) =
  var event = CodexRuntimeEvent(
    kind: cre_runtime_error,
    text: error_message)
  case input.kind
  of cri_send_node_message:
    event.kind = cre_node_error
    event.node_id = input.message_node_id
  else:
    discard
  bridge.emit_event(event)

proc fail_pending_inputs(bridge: ptr CodexBridgeState;
    pending_inputs: var seq[CodexRuntimeInput]; error_message: string) =
  for input in pending_inputs:
    fail_pending_input(bridge, input, error_message)
  pending_inputs.setLen(0)

proc codex_worker(state: ptr CodexBridgeState) {.thread.} =
  var runtime: ptr CodexRuntime = nil
  var request_nodes = initTable[string, uint32]()
  var thread_nodes = initTable[string, uint32]()
  var turn_nodes = initTable[string, string]()
  var queued_messages = initTable[uint32, string]()
  var terminal_nodes = initTable[uint32, bool]()
  var pending_inputs: seq[CodexRuntimeInput] = @[]
  var should_stop = false

  try:
    runtime = init_codex_runtime(getCurrentDir())
    state[].stdout_reader = CodexReaderContext(
      bridge: state,
      stream: runtime.server_stdout_stream(),
      line_kind: cri_stdout_line)
    state[].stderr_reader = CodexReaderContext(
      bridge: state,
      stream: runtime.server_stderr_stream(),
      line_kind: cri_stderr_line)
    createThread(
      state[].stdout_thread, read_lines, addr state[].stdout_reader)
    state[].stdout_thread_started = true
    createThread(
      state[].stderr_thread, read_lines, addr state[].stderr_reader)
    state[].stderr_thread_started = true
  except CatchableError as error:
    state.emit_event(CodexRuntimeEvent(
      kind: cre_runtime_error,
      text: "Codex startup error: " & error.msg))

  while not should_stop:
    let input = state[].input_channel.recv()
    if runtime != nil and not runtime.initialized and
        input.kind == cri_send_node_message:
      pending_inputs.add(input)
      continue
    case input.kind
    of cri_send_node_message, cri_reply_server_request, cri_terminalize_node:
      if runtime != nil:
        handle_command(
          runtime,
          state,
          input,
          request_nodes,
          thread_nodes,
          turn_nodes,
          queued_messages,
          terminal_nodes)
      else:
        fail_pending_input(state, input, "Codex runtime unavailable")
    of cri_shutdown:
      should_stop = true
    of cri_stdout_line:
      if runtime != nil:
        let was_initialized = runtime.initialized
        handle_stdout_line(
          runtime,
          state,
          input.line,
          request_nodes,
          thread_nodes,
          turn_nodes,
          queued_messages,
          terminal_nodes)
        if not was_initialized and runtime.initialized and pending_inputs.len > 0:
          let inputs = pending_inputs
          pending_inputs.setLen(0)
          for pending_input in inputs:
            handle_command(
              runtime,
              state,
              pending_input,
              request_nodes,
              thread_nodes,
              turn_nodes,
              queued_messages,
              terminal_nodes)
        elif runtime.initialization_error.isSome and pending_inputs.len > 0:
          fail_pending_inputs(
            state, pending_inputs, runtime.initialization_error.get)
    of cri_stderr_line:
      state.emit_event(CodexRuntimeEvent(
        kind: cre_global_notification,
        text: "codex stderr: " & input.line))
    of cri_stdout_closed:
      should_stop = true

  if runtime != nil:
    runtime.stop_codex_runtime()
  if state[].stdout_thread_started:
    joinThread(state[].stdout_thread)
  if state[].stderr_thread_started:
    joinThread(state[].stderr_thread)
  if runtime != nil:
    runtime.deinit_codex_runtime()
  state.emit_event(CodexRuntimeEvent(kind: cre_runtime_closed))

proc new_codex_bridge*(): CodexBridge =
  result = cast[CodexBridge](allocShared0(sizeof(CodexBridgeState)))
  result[].terminalization_lock.initLock()
  result[].terminalization_requests = initTable[uint32, bool]()
  result[].input_channel.open()
  result[].event_channel.open()
  createThread(result[].worker_thread, codex_worker, result)

proc send_node_message*(bridge: CodexBridge; node_id: uint32; text: string;
    developer_instructions = ""; graph_creation_node = false;
    reasoning_effort = re_low) =
  bridge[].input_channel.send(CodexRuntimeInput(
    kind: cri_send_node_message,
    message_node_id: node_id,
    message_text: text,
    developer_instructions: developer_instructions,
    graph_creation_node: graph_creation_node,
    reasoning_effort: reasoning_effort))

proc terminalize_node*(bridge: CodexBridge; node_id: uint32) =
  if bridge == nil:
    return
  mark_terminalization_requested(bridge, node_id)
  try:
    bridge[].input_channel.send(CodexRuntimeInput(
      kind: cri_terminalize_node,
      terminal_node_id: node_id))
  except CatchableError:
    discard

proc enqueue_server_response(bridge: CodexBridge;
    input: CodexRuntimeInput): bool =
  if bridge == nil:
    return false
  try:
    bridge[].input_channel.send(input)
    true
  except CatchableError:
    false

proc reply_server_request*(bridge: CodexBridge; request_id: RequestId;
    node_id: uint32; response: DynamicToolCallResponse): bool =
  bridge.enqueue_server_response(CodexRuntimeInput(
    kind: cri_reply_server_request,
    server_request_id: request_id,
    server_request_node_id: node_id,
    server_response: CodexServerResponse(
      kind: csr_dynamic_tool_call,
      dynamic_tool_response: response)))

proc reply_user_input*(bridge: CodexBridge; request_id: RequestId;
    node_id: uint32; answers: seq[UserInputAnswer]): bool =
  bridge.enqueue_server_response(CodexRuntimeInput(
      kind: cri_reply_server_request,
      server_request_id: request_id,
      server_request_node_id: node_id,
      server_response: CodexServerResponse(
        kind: csr_user_input,
        user_input_answers: answers)))

proc try_receive*(bridge: CodexBridge; event: var CodexRuntimeEvent): bool =
  let received = bridge[].event_channel.tryRecv()
  if not received.dataAvailable:
    return false
  event = received.msg
  true

proc deinit_codex_bridge*(bridge: CodexBridge) =
  if bridge == nil:
    return
  bridge[].input_channel.send(CodexRuntimeInput(kind: cri_shutdown))
  joinThread(bridge[].worker_thread)
  bridge[].input_channel.close()
  bridge[].event_channel.close()
  deinitLock(bridge[].terminalization_lock)
  deallocShared(bridge)
