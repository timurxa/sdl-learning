import std/[json, options, os, streams, tables]
import codex_json
import codex_runtime

type
  CodexRuntimeInputKind* = enum
    cri_create_node_thread,
    cri_send_node_message,
    cri_shutdown,
    cri_stdout_line,
    cri_stderr_line,
    cri_stdout_closed

  CodexRuntimeInput* = object
    case kind*: CodexRuntimeInputKind
    of cri_create_node_thread:
      node_id*: uint32
    of cri_send_node_message:
      message_node_id*: uint32
      message_text*: string
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
    cre_global_notification,
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
    params_json*: string
    conversation_scoped*: bool
    notification_kind*: NotificationKind
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

  CodexBridge* = ptr CodexBridgeState

proc emit_event(bridge: ptr CodexBridgeState; event: CodexRuntimeEvent) =
  bridge[].event_channel.send(event)

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

proc notification_will_retry(notification: Notification): bool =
  notification.params.will_retry.isSome and notification.params.will_retry.get

proc notification_node_id(thread_nodes: Table[string, uint32];
    notification: Notification): uint32 =
  let thread_id = notification_thread_id(notification)
  if thread_id.len > 0:
    return node_id_for_thread(thread_nodes, thread_id).get(0'u32)

proc server_request_event(thread_nodes: Table[string, uint32];
    request: ServerRequest): CodexRuntimeEvent =
  let identity = server_request_identity(request)
  CodexRuntimeEvent(
    kind: cre_global_notification,
    node_id: if identity.thread_id.isSome:
      node_id_for_thread(thread_nodes, identity.thread_id.get).get(0'u32)
    else:
      0'u32,
    text: "server request: " & request.method_name,
    method_name: request.method_name,
    thread_id: if identity.thread_id.isSome: identity.thread_id.get else: "",
    turn_id: if identity.turn_id.isSome: identity.turn_id.get else: "",
    item_id: if identity.item_id.isSome: identity.item_id.get else: "",
    request_id: request_id_key(request.id),
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
    server_request_kind: sr_unknown)

proc emit_unknown_notification(bridge: ptr CodexBridgeState;
    notification: Notification) =
  bridge.emit_event(CodexRuntimeEvent(
    kind: cre_global_notification,
    text: notification.method_name & " " &
      params_prefix(notification.params.raw_params)))

proc send_next_queued_message(runtime: ptr CodexRuntime;
    bridge: ptr CodexBridgeState; node_id: uint32;
    request_nodes: var Table[string, uint32];
    queued_messages: var Table[uint32, seq[string]]) =
  let agent_id = agent_id_for_node(node_id)
  if not queued_messages.hasKey(node_id) or queued_messages[node_id].len == 0:
    return
  if not runtime.agents.hasKey(agent_id):
    return
  let agent = runtime.agents[agent_id]
  if not agent.thread_id.has_value or
      agent.state in {as_starting, as_working, as_waiting, as_closed}:
    return
  let message = queued_messages[node_id][0]
  try:
    let request_id = runtime.send_agent_message(agent_id, message)
    request_nodes[request_id_key(request_id)] = node_id
    queued_messages[node_id].delete(0)
    if queued_messages[node_id].len == 0:
      queued_messages.del(node_id)
  except CatchableError as error:
    var failed_agent = runtime.agents[agent_id]
    failed_agent.state = as_idle
    runtime.agents[agent_id] = failed_agent
    bridge.emit_event(CodexRuntimeEvent(
      kind: cre_node_error,
      node_id: node_id,
      text: error.msg))

proc handle_runtime_message(runtime: ptr CodexRuntime;
    bridge: ptr CodexBridgeState; message: Message;
    request_nodes: var Table[string, uint32];
    thread_nodes: var Table[string, uint32];
    queued_messages: var Table[uint32, seq[string]]) =
  case message.kind
  of mk_success:
    let request_key = request_id_key(message.success.id)
    if not runtime.requests.hasKey(request_key):
      return
    let request = runtime.requests[request_key]
    if request.request.kind == mk_initialize:
      return
    if request.request.kind == mk_thread_start and request.agent_id.isSome:
      let node_id = request_nodes.getOrDefault(request_key, 0'u32)
      thread_nodes[message.success.result.thread_id] = node_id
      bridge.emit_event(CodexRuntimeEvent(
        kind: cre_thread_ready,
        node_id: node_id,
        text: message.success.result.thread_id))
      send_next_queued_message(
        runtime, bridge, node_id, request_nodes, queued_messages)
  of mk_error:
    let request_key = request_id_key(message.error.id)
    let node_id = request_nodes.getOrDefault(request_key, 0'u32)
    var event_kind = if node_id == 0: cre_runtime_error else: cre_node_error
    if runtime.requests.hasKey(request_key):
      let request = runtime.requests[request_key]
      if request.request.kind == mk_thread_start:
        event_kind = cre_thread_error
        if request.agent_id.isSome:
          runtime.agents.del(request.agent_id.get)
      elif request.request.kind == mk_turn_start and request.agent_id.isSome:
        send_next_queued_message(
          runtime,
          bridge,
          request_nodes.getOrDefault(request_key, node_id),
          request_nodes,
          queued_messages)
    bridge.emit_event(CodexRuntimeEvent(
      kind: event_kind,
      node_id: node_id,
      text: message.error.message))
  of mk_notification:
    let notification = message.notification
    case notification.kind
    of nk_agent_message_delta:
      if notification.params.thread_id.has_value and
          notification.params.delta.isSome:
        let node_id = node_id_for_thread(
          thread_nodes, notification.params.thread_id.value)
        if node_id.isSome:
          bridge.emit_event(notification_event(
            notification,
            node_id.get,
            cre_agent_message_delta,
            notification.params.delta.get))
    of nk_turn_completed:
      if notification.params.thread_id.has_value:
        let node_id = node_id_for_thread(
          thread_nodes, notification.params.thread_id.value)
        if node_id.isSome:
          if notification.params.turn_status.isSome and
              notification.params.turn_status.get == ts_failed:
            bridge.emit_event(notification_event(
              notification,
              node_id.get,
              cre_node_error,
              notification.params.error_message.get("turn failed")))
          else:
            bridge.emit_event(notification_event(
              notification,
              node_id.get,
              cre_turn_completed))
          send_next_queued_message(
            runtime, bridge, node_id.get, request_nodes, queued_messages)
    of nk_error:
      if notification.params.thread_id.has_value:
        let node_id = node_id_for_thread(
          thread_nodes, notification.params.thread_id.value)
        if node_id.isSome:
          let event_kind = if notification.notification_will_retry:
            cre_global_notification
          else:
            cre_node_error
          bridge.emit_event(notification_event(
            notification,
            node_id.get,
            event_kind,
            notification.params.error_message.get("runtime error")))
      else:
        let event_kind = if notification.notification_will_retry:
          cre_global_notification
        else:
          cre_runtime_error
        bridge.emit_event(notification_event(
          notification,
          0,
          event_kind,
          notification.params.error_message.get("runtime error")))
    of nk_thread_closed:
      if notification.params.thread_id.has_value:
        let node_id = node_id_for_thread(
          thread_nodes, notification.params.thread_id.value)
        if node_id.isSome:
          runtime.agents.del(agent_id_for_node(node_id.get))
          thread_nodes.del(notification.params.thread_id.value)
          bridge.emit_event(CodexRuntimeEvent(
            kind: cre_thread_error,
            node_id: node_id.get,
            text: "Codex thread closed"))
    of nk_unknown:
      if not notification.method_name.is_suppressed_notification:
        emit_unknown_notification(bridge, notification)
    else:
      if notification.kind.is_conversation_notification:
        bridge.emit_event(notification_event(
          notification,
          notification_node_id(thread_nodes, notification)))
  of mk_server_request:
    let request = message.server_request
    if request.kind.is_conversation_server_request:
      bridge.emit_event(server_request_event(thread_nodes, request))
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
    queued_messages: var Table[uint32, seq[string]]) =
  try:
    let message = runtime.accept_json(parseJson(line))
    handle_runtime_message(
      runtime, bridge, message, request_nodes, thread_nodes, queued_messages)
  except CatchableError as error:
    bridge.emit_event(CodexRuntimeEvent(
      kind: cre_runtime_error,
      text: "Codex message error: " & error.msg))

proc handle_create_node_thread(runtime: ptr CodexRuntime;
    bridge: ptr CodexBridgeState; node_id: uint32;
    request_nodes: var Table[string, uint32]) =
  let agent_id = agent_id_for_node(node_id)
  if runtime.agents.hasKey(agent_id):
    return
  try:
    let request_id = runtime.create_agent(agent_id, "")
    request_nodes[request_id_key(request_id)] = node_id
  except CatchableError as error:
    bridge.emit_event(CodexRuntimeEvent(
      kind: cre_thread_error,
      node_id: node_id,
      text: error.msg))

proc handle_send_node_message(runtime: ptr CodexRuntime;
    bridge: ptr CodexBridgeState; input: CodexRuntimeInput;
    request_nodes: var Table[string, uint32];
    queued_messages: var Table[uint32, seq[string]]) =
  let node_id = input.message_node_id
  let agent_id = agent_id_for_node(node_id)
  if not runtime.agents.hasKey(agent_id):
    queued_messages.mgetOrPut(node_id, @[]).add(input.message_text)
    handle_create_node_thread(runtime, bridge, node_id, request_nodes)
    return
  let agent = runtime.agents[agent_id]
  queued_messages.mgetOrPut(node_id, @[]).add(input.message_text)
  if agent.thread_id.has_value and agent.state notin {as_starting, as_working, as_waiting}:
    send_next_queued_message(
      runtime, bridge, node_id, request_nodes, queued_messages)

proc handle_command(runtime: ptr CodexRuntime; bridge: ptr CodexBridgeState;
    input: CodexRuntimeInput; request_nodes: var Table[string, uint32];
    queued_messages: var Table[uint32, seq[string]]) =
  case input.kind
  of cri_create_node_thread:
    handle_create_node_thread(runtime, bridge, input.node_id, request_nodes)
  of cri_send_node_message:
    handle_send_node_message(runtime, bridge, input, request_nodes, queued_messages)
  else:
    discard

proc input_node_id(input: CodexRuntimeInput): uint32 =
  case input.kind
  of cri_create_node_thread:
    input.node_id
  of cri_send_node_message:
    input.message_node_id
  else:
    0

proc fail_pending_input(bridge: ptr CodexBridgeState;
    input: CodexRuntimeInput; error_message: string) =
  let event_kind = if input.kind == cri_create_node_thread:
    cre_thread_error
  else:
    cre_node_error
  bridge.emit_event(CodexRuntimeEvent(
    kind: event_kind,
    node_id: input_node_id(input),
    text: error_message))

proc fail_pending_inputs(bridge: ptr CodexBridgeState;
    pending_inputs: var seq[CodexRuntimeInput]; error_message: string) =
  for input in pending_inputs:
    fail_pending_input(bridge, input, error_message)
  pending_inputs.setLen(0)

proc codex_worker(state: ptr CodexBridgeState) {.thread.} =
  var runtime: ptr CodexRuntime = nil
  var request_nodes = initTable[string, uint32]()
  var thread_nodes = initTable[string, uint32]()
  var queued_messages = initTable[uint32, seq[string]]()
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
        input.kind in {cri_create_node_thread, cri_send_node_message}:
      pending_inputs.add(input)
      continue
    case input.kind
    of cri_create_node_thread, cri_send_node_message:
      if runtime != nil:
        handle_command(runtime, state, input, request_nodes, queued_messages)
      else:
        fail_pending_input(state, input, "Codex runtime unavailable")
    of cri_shutdown:
      should_stop = true
    of cri_stdout_line:
      if runtime != nil:
        let was_initialized = runtime.initialized
        handle_stdout_line(
          runtime, state, input.line, request_nodes, thread_nodes, queued_messages)
        if not was_initialized and runtime.initialized and pending_inputs.len > 0:
          let inputs = pending_inputs
          pending_inputs.setLen(0)
          for pending_input in inputs:
            handle_command(
              runtime, state, pending_input, request_nodes, queued_messages)
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
  result[].input_channel.open()
  result[].event_channel.open()
  createThread(result[].worker_thread, codex_worker, result)

proc request_node_thread*(bridge: CodexBridge; node_id: uint32) =
  bridge[].input_channel.send(CodexRuntimeInput(
    kind: cri_create_node_thread,
    node_id: node_id))

proc send_node_message*(bridge: CodexBridge; node_id: uint32; text: string) =
  bridge[].input_channel.send(CodexRuntimeInput(
    kind: cri_send_node_message,
    message_node_id: node_id,
    message_text: text))

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
  deallocShared(bridge)
