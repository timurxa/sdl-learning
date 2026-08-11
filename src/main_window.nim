import std/[json, options, strutils, tables]
import clay
import sdl
import ui
import renderer
import graph_ui
import orchestration
import codex_bridge
import codex_json

type
  MainTabKind = enum
    main_tab_workspace
    main_tab_graph

  TabManager = object
    active_tab: MainTabKind

  Palette = object
    background: ClayColor
    ink: ClayColor
    paper: ClayColor
    yellow: ClayColor
    blue: ClayColor
    pink: ClayColor
    mint: ClayColor
    purple: ClayColor

  WorkspaceTab = ref object
    graph_view: GraphView
    debug_cycle_frame: uint64
    debug_last_phase: int

  ConversationSpeaker = enum
    conversation_node
    conversation_user,
    conversation_system

  ConversationState = enum
    conversation_starting,
    conversation_ready,
    conversation_working,
    conversation_error

  ConversationEntryKind = enum
    cek_message,
    cek_activity

  ConversationActivityKind = enum
    cak_thinking,
    cak_plan,
    cak_command,
    cak_tool,
    cak_changes,
    cak_model,
    cak_lifecycle,
    cak_request

  ConversationActivityState = enum
    cas_active,
    cas_complete,
    cas_waiting,
    cas_error,
    cas_notice

  ConversationFileSummary = object
    path: string
    added: int
    removed: int

  ConversationItemDescriptor = object
    kind: string
    activity_kind: ConversationActivityKind
    title: string
    detail: string

  ConversationEntry = object
    kind: ConversationEntryKind
    speaker: ConversationSpeaker
    content: string
    activity_kind: ConversationActivityKind
    activity_state: ConversationActivityState
    activity_id: string
    turn_id: string
    title: string
    detail: string
    body: string
    expanded: bool
    files: seq[ConversationFileSummary]
    added: int
    removed: int

  NodeConversation = object
    messages: seq[ConversationEntry]
    state: ConversationState
    thread_requested: bool
    status_detail: string
    token_usage: string
    current_model: string

  UserInputQuestions = object
    question_ids: seq[string]
    prompt: string

  PendingUserInput = object
    request_id: RequestId
    question_ids: seq[string]

  GraphTab = ref object
    graph_view: GraphView
    node_conversations: Table[uint32, NodeConversation]
    pending_user_inputs: Table[uint32, PendingUserInput]
    global_log_messages: seq[string]
    previous_selected_node_id: uint32
    previous_selected_node_valid: bool
    scroll_conversation_to_end: bool

  MainWindow* = ref object
    palette: Palette
    ui_state: UiState
    tab_manager: TabManager
    workspace_tab: WorkspaceTab
    graph_tab: GraphTab
    codex_bridge: CodexBridge
    codex_runtime_closed: bool
    pending_graph_events: seq[UiEvent]

proc new_debug_graph_tab(objective: string): GraphTab =
  new(result)
  result.node_conversations = initTable[uint32, NodeConversation]()
  result.pending_user_inputs = initTable[uint32, PendingUserInput]()
  result.graph_view.work_graph = new_work_graph(objective = objective)
  var layout_config = default_graph_layout_config()
  layout_config.layer_gap = 96
  layout_config.node_gap = 56
  discard result.graph_view.begin_graph_layout(layout_config)

const
  nav_labels = ["Overview", "Activity", "Analytics", "Deployments", "Alerts", "Settings", "Team", "Archive"]
  workspace_tab_button_id = "tab_workspace"
  graph_tab_button_id = "tab_graph"
  graph_conversation_input_id = "graph_conversation_input"
  graph_conversation_log_id = "graph_conversation_log"
  graph_global_log_id = "graph_global_log"
  graph_conversation_composer_id = "graph_conversation_composer"
  graph_activity_button_prefix = "graph_conversation_activity_"
  graph_node_tooltip_id = "graph_node_tooltip"
  graph_node_tooltip_width = 190
  graph_node_tooltip_height = 68
  graph_node_tooltip_gap = 10'f32
  graph_node_tooltip_z_index = 32767'i16

template scrollable_declaration(element_declaration: untyped): ClayElementDeclaration =
  var scroll_declaration = element_declaration
  scroll_declaration.clip.child_offset = clay_get_scroll_offset()
  scroll_declaration

template scrollable_element(element_id: untyped; element_declaration: untyped;
    body: untyped) =
  clay_element_scope(element_id, scrollable_declaration(element_declaration)):
    body

proc palette_color(color: ClayColor): ClayColor =
  color

proc new_main_window*(objective = ""): MainWindow =
  MainWindow(
    palette: Palette(
      background: rgba(241, 235, 217, 255),
      ink: rgba(20, 18, 15, 255),
      paper: rgba(255, 250, 235, 255),
      yellow: rgba(255, 210, 63, 255),
      blue: rgba(70, 145, 255, 255),
      pink: rgba(255, 103, 174, 255),
      mint: rgba(83, 220, 169, 255),
    purple: rgba(169, 126, 255, 255)),
    ui_state: new_ui_state(),
    tab_manager: TabManager(active_tab: main_tab_workspace),
    workspace_tab: WorkspaceTab(
      graph_view: GraphView(work_graph: new_work_graph(objective = objective))),
    graph_tab: new_debug_graph_tab(objective),
    codex_bridge: new_codex_bridge())

proc background_color*(view: MainWindow): ClayColor =
  view.palette.background

proc set_window*(view: MainWindow; window: ptr SdlWindow) =
  view.ui_state.set_window(window)

proc handle_event*(view: MainWindow; event: UiEvent) =
  view.ui_state.enqueue_event(event)

proc deinit*(view: MainWindow) =
  if view == nil:
    return
  deinit_codex_bridge(view.codex_bridge)

proc build_elements*(view: MainWindow; frame: ViewFrame)
proc build_workspace_tab(view: MainWindow; frame: ViewFrame)
proc build_graph_tab(view: MainWindow)
proc apply_ui_actions(view: MainWindow)
proc build_tab_bar(view: MainWindow)
proc sync_selected_node(view: MainWindow)
proc poll_codex_events(view: MainWindow)
proc process_pending_graph_events(view: MainWindow)

proc node_conversation(tab: GraphTab; node_id: uint32): var NodeConversation =
  tab.node_conversations.mgetOrPut(node_id, NodeConversation(
    state: conversation_starting))

proc message_entry(speaker: ConversationSpeaker;
    content: string): ConversationEntry =
  ConversationEntry(
    kind: cek_message,
    speaker: speaker,
    content: content,
    activity_kind: cak_lifecycle,
    activity_state: cas_complete,
    turn_id: "",
    files: @[])

proc activity_entry(kind: ConversationActivityKind; activity_id,
    turn_id, title: string): ConversationEntry =
  ConversationEntry(
    kind: cek_activity,
    activity_kind: kind,
    activity_state: cas_active,
    activity_id: activity_id,
    turn_id: turn_id,
    title: title,
    expanded: kind != cak_thinking,
    files: @[])

proc add_node_message(tab: GraphTab; node_id: uint32;
    speaker: ConversationSpeaker; content: string) =
  tab.node_conversation(node_id).messages.add(message_entry(speaker, content))

proc display_work_graph_messages(view: MainWindow) =
  let messages = view.graph_tab.graph_view.work_graph.drain_outgoing_messages()
  for message in messages:
    view.graph_tab.add_node_message(
      message.node_id, conversation_system, message.text)
  if messages.len > 0:
    view.graph_tab.scroll_conversation_to_end = true

proc add_global_message(tab: GraphTab; content: string) =
  tab.global_log_messages.add(content)
  tab.scroll_conversation_to_end = true

proc append_agent_delta(tab: GraphTab; node_id: uint32; delta: string) =
  var conversation = tab.node_conversation(node_id)
  conversation.state = conversation_working
  if conversation.messages.len == 0 or
      conversation.messages[^1].kind != cek_message or
      conversation.messages[^1].speaker != conversation_node:
    conversation.messages.add(message_entry(conversation_node, delta))
  else:
    conversation.messages[^1].content.add(delta)
  tab.node_conversations[node_id] = conversation
  tab.scroll_conversation_to_end = true

proc json_string(node: JsonNode; key: string): string =
  if node.kind == JObject and node.contains(key) and
      node[key].kind == JString:
    return node[key].getStr

proc json_int(node: JsonNode; key: string): int =
  if node.kind == JObject and node.contains(key) and
      node[key].kind == JInt:
    return int(node[key].getInt)

proc user_input_questions(payload: JsonNode): UserInputQuestions =
  if payload.kind != JObject or not payload.contains("questions") or
      payload["questions"].kind != JArray:
    return
  var prompts: seq[string] = @[]
  var question_index = 0
  for question in payload["questions"]:
    if question.kind != JObject:
      inc question_index
      continue
    let question_id = json_string(question, "id")
    if question_id.len == 0:
      continue
    result.question_ids.add(question_id)
    let header = json_string(question, "header")
    let body = json_string(question, "question")
    let prompt = if header.len > 0 and body.len > 0:
      header & ": " & body
    elif body.len > 0:
      body
    else:
      header
    if prompt.len > 0:
      prompts.add($(question_index + 1) & ". " & prompt)
    inc question_index
  result.prompt = prompts.join("\n")

proc parse_answers(input: PendingUserInput; content: string):
    tuple[success: bool; answers: seq[UserInputAnswer]; error: string] =
  let stripped = content.strip
  if stripped.len == 0:
    result.error = "INPUT RESPONSE CANNOT BE EMPTY"
    return
  let answer_values = if input.question_ids.len == 1:
    @[stripped]
  else:
    stripped.splitLines()
  if answer_values.len != input.question_ids.len:
    result.error = "EXPECTS " & $input.question_ids.len &
      " ANSWERS, ONE PER LINE"
    return
  for answer_index, question_id in input.question_ids:
    result.answers.add(UserInputAnswer(
      question_id: question_id,
      answer: answer_values[answer_index]))
  result.success = true

proc json_text(node: JsonNode; key: string): string =
  if node.kind != JObject or not node.contains(key):
    return ""
  let value = node[key]
  case value.kind:
  of JString:
    result = value.getStr
  of JArray:
    for item in value:
      if item.kind == JString:
        if result.len > 0: result.add(" ")
        result.add(item.getStr)
  else:
    discard

proc event_payload(event: CodexRuntimeEvent): JsonNode =
  if event.params_json.len == 0:
    return newJObject()
  try:
    parseJson(event.params_json)
  except CatchableError:
    newJObject()

proc activity_kind_for_notification(kind: NotificationKind): ConversationActivityKind =
  case kind:
  of nk_reasoning_summary_text_delta, nk_reasoning_summary_part_added:
    cak_thinking
  of nk_turn_plan_updated, nk_plan_delta:
    cak_plan
  of nk_command_execution_output_delta, nk_terminal_interaction:
    cak_command
  of nk_mcp_tool_call_progress:
    cak_tool
  of nk_turn_diff_updated, nk_file_change_output_delta:
    cak_changes
  of nk_model_rerouted:
    cak_model
  else:
    cak_lifecycle

proc activity_kind_for_request(kind: ServerRequestKind): ConversationActivityKind =
  case kind:
  of sr_command_execution_approval: cak_command
  of sr_file_change_approval: cak_changes
  of sr_tool_user_input, sr_tool_call: cak_tool
  else: cak_request

proc activity_key(event: CodexRuntimeEvent;
    kind: ConversationActivityKind): string =
  let prefix = $kind & ":"
  if event.server_request_kind != sr_unknown and event.request_id.len > 0:
    return prefix & "request:" & event.request_id
  if kind == cak_changes and event.turn_id.len > 0:
    return prefix & "turn:" & event.turn_id
  if event.item_id.len > 0:
    return prefix & "item:" & event.item_id
  if event.turn_id.len > 0:
    return prefix & "turn:" & event.turn_id
  if event.request_id.len > 0:
    return prefix & "request:" & event.request_id
  prefix & event.method_name

proc find_activity(conversation: NodeConversation; activity_id: string): int =
  for index, entry in conversation.messages:
    if entry.kind == cek_activity and entry.activity_id == activity_id:
      return index
  -1

proc item_descriptor(payload: JsonNode): ConversationItemDescriptor =
  if payload.kind != JObject or not payload.contains("item"):
    return ConversationItemDescriptor(activity_kind: cak_lifecycle)
  let item = payload["item"]
  result.kind = json_string(item, "type")
  case result.kind:
  of "commandExecution":
    result.activity_kind = cak_command
    result.title = "Command"
    result.detail = json_text(item, "command")
  of "fileChange":
    result.activity_kind = cak_changes
    result.title = "Changes"
  of "mcpToolCall":
    result.activity_kind = cak_tool
    result.title = "Tool"
  of "reasoning":
    result.activity_kind = cak_thinking
    result.title = "Thinking"
  of "plan":
    result.activity_kind = cak_plan
    result.title = "Plan"
  of "agentMessage":
    result.activity_kind = cak_lifecycle
    result.title = "Response"
  else:
    result.activity_kind = cak_lifecycle
    result.title = if result.kind.len > 0: result.kind else: "Activity"

proc status_text(state: ConversationState): string =
  case state:
  of conversation_starting: "STARTING"
  of conversation_ready: "READY"
  of conversation_working: "WORKING"
  of conversation_error: "ERROR"

proc activity_state_text(state: ConversationActivityState): string =
  case state:
  of cas_active: "RUNNING"
  of cas_complete: "DONE"
  of cas_waiting: "WAITING"
  of cas_error: "ERROR"
  of cas_notice: "INFO"

proc format_usage(payload: JsonNode): string =
  if payload.kind != JObject or not payload.contains("tokenUsage"):
    return ""
  let usage = payload["tokenUsage"]
  if usage.kind != JObject:
    return ""
  var parts: seq[string] = @[]
  if usage.contains("last") and usage["last"].kind == JObject:
    let last_tokens = json_int(usage["last"], "totalTokens")
    if last_tokens > 0: parts.add("LAST " & $last_tokens)
  if usage.contains("total") and usage["total"].kind == JObject:
    let total_tokens = json_int(usage["total"], "totalTokens")
    if total_tokens > 0: parts.add("TOTAL " & $total_tokens)
  if parts.len > 0: "TOKENS / " & parts.join(" · ") else: ""

proc format_diff_summary(entry: var ConversationEntry; summary: JsonNode) =
  if summary.kind != JObject:
    return
  entry.added = json_int(summary, "added")
  entry.removed = json_int(summary, "removed")
  entry.files.setLen(0)
  if summary.contains("files") and summary["files"].kind == JArray:
    for file in summary["files"]:
      entry.files.add(ConversationFileSummary(
        path: json_string(file, "path"),
        added: json_int(file, "added"),
        removed: json_int(file, "removed")))

proc format_plan(payload: JsonNode): string =
  if payload.kind != JObject:
    return ""
  result = json_string(payload, "explanation")
  if payload.contains("plan") and payload["plan"].kind == JArray:
    for item in payload["plan"]:
      let step = json_string(item, "step")
      let status = json_string(item, "status")
      if step.len > 0:
        if result.len > 0: result.add("\n")
        result.add("[" & (if status.len > 0: status else: "pending") & "] " & step)

proc update_activity(conversation: var NodeConversation;
    event: CodexRuntimeEvent; payload: JsonNode;
    kind: ConversationActivityKind;
    item: ConversationItemDescriptor; user_input: UserInputQuestions;
    title = "") =
  let key = event.activity_key(kind)
  var index = conversation.find_activity(key)
  if index < 0:
    conversation.messages.add(activity_entry(
      kind, key, event.turn_id,
      if title.len > 0: title else: "Activity"))
    index = conversation.messages.high
  var entry = conversation.messages[index]
  if title.len > 0:
    entry.title = title

  case event.notification_kind:
  of nk_item_started:
    entry.title = if item.title.len > 0: item.title else: "Activity"
    entry.detail = if item.detail.len > 0: item.detail else: "Started"
  of nk_item_completed:
    entry.activity_state = cas_complete
    entry.expanded = false
    entry.detail = "Completed"
  of nk_command_execution_output_delta:
    entry.title = "Command"
    entry.body.add(json_string(payload, "delta"))
  of nk_terminal_interaction:
    entry.title = "Command"
    entry.detail = "Terminal interaction"
    let stdin = json_string(payload, "stdin")
    if stdin.len > 0: entry.body.add(stdin)
  of nk_mcp_tool_call_progress:
    entry.title = "Tool progress"
    let progress = json_string(payload, "message")
    if progress.len > 0:
      if entry.body.len > 0: entry.body.add("\n")
      entry.body.add(progress)
  of nk_reasoning_summary_text_delta:
    entry.title = "Thinking"
    entry.body.add(json_string(payload, "delta"))
  of nk_reasoning_summary_part_added:
    entry.title = "Thinking"
    entry.detail = "Summary part " & $json_int(payload, "summaryIndex")
  of nk_turn_plan_updated:
    entry.title = "Plan"
    entry.body = format_plan(payload)
  of nk_plan_delta:
    entry.title = "Plan"
    entry.body.add(json_string(payload, "delta"))
  of nk_turn_diff_updated:
    entry.title = "Changes"
    if payload.contains("summary"):
      entry.format_diff_summary(payload["summary"])
  of nk_file_change_output_delta:
    entry.title = "Changes"
    let delta_length = json_int(payload, "deltaLength")
    if delta_length > 0:
      entry.detail = $delta_length & " chars of change output"
  of nk_model_rerouted:
    entry.title = "Model rerouted"
    entry.detail = json_string(payload, "fromModel") & " → " &
      json_string(payload, "toModel")
    entry.body = json_string(payload, "reason")
    entry.activity_state = cas_notice
    entry.expanded = false
  of nk_thread_compacted:
    entry.title = "Context compacted"
    entry.activity_state = cas_notice
    entry.expanded = false
  else:
    case event.server_request_kind:
    of sr_tool_call:
      entry.title = "Tool call"
      entry.activity_state = cas_waiting
      entry.detail = json_string(payload, "tool")
    of sr_tool_user_input:
      entry.title = "Input requested"
      entry.activity_state = cas_waiting
      entry.detail = if user_input.prompt.len > 0:
        user_input.prompt else: "Tool requested user input"
      entry.body = user_input.prompt
    of sr_command_execution_approval:
      entry.title = "Command approval requested"
      entry.activity_state = cas_waiting
      entry.detail = json_string(payload, "reason")
    of sr_file_change_approval:
      entry.title = "File approval requested"
      entry.activity_state = cas_waiting
      entry.detail = json_string(payload, "reason")
    else:
      discard
  conversation.messages[index] = entry

proc finalize_activities(conversation: var NodeConversation;
    turn_id = ""; error_state = false) =
  for index in 0 ..< conversation.messages.len:
    if conversation.messages[index].kind != cek_activity:
      continue
    if turn_id.len > 0 and conversation.messages[index].turn_id != turn_id:
      continue
    conversation.messages[index].activity_state = if error_state:
      cas_error else: cas_complete
    conversation.messages[index].expanded = false

proc apply_conversation_error(view: MainWindow; node_id: uint32;
    prefix, message: string; close_thread = false; status_detail = "";
    turn_id = "") =
  view.graph_tab.pending_user_inputs.del(node_id)
  var conversation = view.graph_tab.node_conversation(node_id)
  if close_thread:
    conversation.thread_requested = false
  conversation.state = conversation_error
  conversation.status_detail = status_detail
  conversation.finalize_activities(turn_id, error_state = true)
  conversation.messages.add(message_entry(conversation_system, prefix & message))
  view.graph_tab.node_conversations[node_id] = conversation
  view.graph_tab.scroll_conversation_to_end = true

proc apply_conversation_event(view: MainWindow; event: CodexRuntimeEvent) =
  var conversation = view.graph_tab.node_conversation(event.node_id)
  case event.kind
  of cre_agent_message_delta:
    view.graph_tab.append_agent_delta(event.node_id, event.text)
    return
  of cre_turn_completed:
    conversation.finalize_activities(event.turn_id)
    conversation.state = conversation_ready
    conversation.status_detail.setLen(0)
  of cre_node_error:
    view.apply_conversation_error(
      event.node_id, "ERROR: ", event.text, turn_id = event.turn_id)
    return
  of cre_global_notification:
    let payload = event.event_payload
    let user_input = if event.server_request_kind == sr_tool_user_input:
      user_input_questions(payload)
    else:
      UserInputQuestions()
    if event.server_request_kind == sr_tool_user_input:
      if user_input.question_ids.len > 0:
        let pending_input = PendingUserInput(
          request_id: event.request_id_value,
          question_ids: user_input.question_ids)
        view.graph_tab.pending_user_inputs[event.node_id] = pending_input
      conversation.state = conversation_working
    case event.notification_kind
    of nk_thread_started:
      conversation.state = conversation_ready
    of nk_thread_token_usage_updated:
      conversation.token_usage = format_usage(payload)
    of nk_turn_started:
      conversation.state = conversation_working
      conversation.status_detail.setLen(0)
    of nk_thread_status_changed:
      if event.thread_status.isSome:
        case event.thread_status.get
        of tsk_idle:
          conversation.state = conversation_ready
          conversation.status_detail.setLen(0)
        of tsk_active:
          conversation.state = conversation_working
          let waiting = event.active_flags.active_flags_are_waiting
          conversation.status_detail = if waiting: "WAITING" else: "WORKING"
        of tsk_system_error, tsk_not_loaded:
          view.graph_tab.pending_user_inputs.del(event.node_id)
          conversation.state = conversation_error
          conversation.status_detail = if event.thread_status.get == tsk_system_error:
            "SYSTEM ERROR" else: "NOT LOADED"
          conversation.finalize_activities(error_state = true)
        of tsk_unknown:
          discard
    of nk_error:
      if event.will_retry.retry_requested:
        conversation.state = conversation_working
        conversation.status_detail = "RETRYING"
    else:
      let is_item_lifecycle = event.notification_kind in {
        nk_item_started, nk_item_completed}
      let item = if is_item_lifecycle:
        item_descriptor(payload)
      else:
        ConversationItemDescriptor(activity_kind: cak_lifecycle)
      let activity_kind = if event.server_request_kind != sr_unknown:
        activity_kind_for_request(event.server_request_kind)
      elif item.kind.len > 0:
        item.activity_kind
      else:
        activity_kind_for_notification(event.notification_kind)
      if is_item_lifecycle and
          item.kind == "agentMessage":
        discard
      else:
        conversation.update_activity(
          event, payload, activity_kind, item, user_input)
      if event.server_request_kind != sr_unknown:
        conversation.status_detail = if event.server_request_kind == sr_tool_user_input:
          "WAITING FOR INPUT" else: "WAITING"
      elif event.notification_kind == nk_model_rerouted:
        conversation.current_model = json_string(payload, "toModel")
  of cre_tool_response_sent:
    if event.server_request_kind == sr_tool_user_input:
      view.graph_tab.pending_user_inputs.del(event.node_id)
  of cre_thread_ready, cre_thread_error, cre_runtime_error,
      cre_runtime_closed:
    discard
  view.graph_tab.node_conversations[event.node_id] = conversation
  view.graph_tab.scroll_conversation_to_end = true

proc apply_codex_event(view: MainWindow; event: CodexRuntimeEvent) =
  let conversation_event = event.conversation_scoped and event.node_id != 0
  case event.kind
  of cre_thread_ready:
    var conversation = view.graph_tab.node_conversation(event.node_id)
    conversation.thread_requested = true
    conversation.state = conversation_ready
    view.graph_tab.node_conversations[event.node_id] = conversation
  of cre_tool_response_sent:
    if conversation_event:
      view.apply_conversation_event(event)
  of cre_thread_error:
    view.apply_conversation_error(
      event.node_id, "THREAD ERROR: ", event.text, close_thread = true)
  of cre_agent_message_delta, cre_turn_completed, cre_global_notification:
    if conversation_event:
      view.apply_conversation_event(event)
    else:
      view.graph_tab.add_global_message(event.text)
  of cre_node_error:
    if conversation_event:
      view.apply_conversation_event(event)
    else:
      view.apply_conversation_error(
        event.node_id, "ERROR: ", event.text)
  of cre_runtime_error:
    view.graph_tab.add_global_message("RUNTIME ERROR: " & event.text)
  of cre_runtime_closed:
    view.codex_runtime_closed = true
    var active_node_ids: seq[uint32] = @[]
    for node_id, conversation in view.graph_tab.node_conversations:
      if conversation.state in {conversation_starting, conversation_working}:
        active_node_ids.add(node_id)
    for node_id in active_node_ids:
      view.apply_conversation_error(
        node_id,
        "ERROR: ",
        "CODEX RUNTIME CLOSED",
        close_thread = true,
        status_detail = "RUNTIME CLOSED")
    view.graph_tab.pending_user_inputs.clear()
    view.graph_tab.add_global_message("CODEX RUNTIME CLOSED")

proc poll_codex_events(view: MainWindow) =
  var event: CodexRuntimeEvent
  while view.codex_bridge.try_receive(event):
    view.graph_tab.graph_view.work_graph.handle_codex_event(
      view.codex_bridge, event)
    view.apply_codex_event(event)
  if not view.codex_runtime_closed:
    view.graph_tab.graph_view.work_graph.start_available_nodes(
      view.codex_bridge)
  view.display_work_graph_messages()

proc sync_graph_viewport(view: MainWindow) =
  let surface_data = clay_get_element_data(clay_id("graph_surface"))
  if not surface_data.found:
    case view.tab_manager.active_tab
    of main_tab_workspace:
      view.workspace_tab.graph_view.clear_graph_viewport()
    of main_tab_graph:
      view.graph_tab.graph_view.clear_graph_viewport()
    return

  let panel_data = clay_get_element_data(clay_id("graph_panel"))
  case view.tab_manager.active_tab
  of main_tab_workspace:
    view.workspace_tab.graph_view.set_graph_viewport(
      surface_data.bounding_box)
  of main_tab_graph:
    view.graph_tab.graph_view.set_graph_viewport(
      surface_data.bounding_box,
      panel_data.bounding_box,
      panel_data.found)

proc finish_frame(view: MainWindow) =
  view.sync_graph_viewport()
  if view.tab_manager.active_tab == main_tab_graph:
    view.graph_tab.graph_view.rebuild_graph_draw_list()
    view.sync_selected_node()
  view.ui_state.finish_frame()
  if not view.graph_tab.scroll_conversation_to_end:
    return
  let log_id = if view.graph_tab.graph_view.selected_node_valid:
    graph_conversation_log_id
  else:
    graph_global_log_id
  let scroll_data = clay_get_scroll_container_data(
    clay_id(log_id))
  if not scroll_data.found or scroll_data.scroll_position == nil:
    return
  let overflow = max(
    float32(scroll_data.content_dimensions.height) -
    float32(scroll_data.scroll_container_dimensions.height),
    0'f32)
  scroll_data.scroll_position[].y = -overflow
  view.graph_tab.scroll_conversation_to_end = false

proc render*(view: MainWindow; renderer: Renderer; clay_context: ptr ClayContext;
    string_cache: var ClayStringCache; delta_time: float32): bool =
  discard view.graph_tab.graph_view.step_graph_layout(delta_time)
  view.poll_codex_events()
  renderer.render_frame(
    clay_context,
    string_cache,
    proc() =
      view.ui_state.prepare_frame(
        proc(event: UiEvent) =
          if view.tab_manager.active_tab == main_tab_graph:
            case event.kind
            of ui_event_mouse_button_down, ui_event_mouse_button_up,
                ui_event_mouse_move, ui_event_mouse_wheel,
                ui_event_mouse_leave, ui_event_window_focus_lost:
              view.pending_graph_events.add(event)
            else:
              discard,
        delta_time)
      view.process_pending_graph_events()
      view.apply_ui_actions(),
    proc(frame: ViewFrame) = view.build_elements(frame),
    proc() = view.finish_frame(),
    delta_time)

proc debug_transition_set_initial_state(target_state: ClayTransitionData;
    properties: ClayTransitionProperty): ClayTransitionData {.cdecl.} =
  result = target_state
  if (int32(properties) and int32(clay_transition_property_x)) != 0:
    result.bounding_box.x -= 24
  if (int32(properties) and int32(clay_transition_property_y)) != 0:
    result.bounding_box.y += 12

proc debug_transition_set_final_state(initial_state: ClayTransitionData;
    properties: ClayTransitionProperty): ClayTransitionData {.cdecl.} =
  result = initial_state
  if (int32(properties) and int32(clay_transition_property_x)) != 0:
    result.bounding_box.x += 36
  if (int32(properties) and int32(clay_transition_property_y)) != 0:
    result.bounding_box.y += 18

proc select_tab(view: MainWindow; tab_kind: MainTabKind) =
  if view.tab_manager.active_tab == tab_kind:
    return
  view.graph_tab.graph_view.clear_graph_pointer()
  view.ui_state.clear_focus()
  view.tab_manager.active_tab = tab_kind
  if tab_kind == main_tab_graph:
    view.graph_tab.graph_view.set_graph_pointer(
      clay_get_pointer_state().position)

proc process_pending_graph_events(view: MainWindow) =
  if view.tab_manager.active_tab == main_tab_graph:
    for event in view.pending_graph_events:
      view.graph_tab.graph_view.handle_event(event)
  view.pending_graph_events.setLen(0)

proc apply_ui_actions(view: MainWindow) =
  view.sync_selected_node()
  var action: UiAction
  while view.ui_state.next_action(action):
    case action.kind
    of ui_action_button_clicked:
      case action.button_id
      of workspace_tab_button_id:
        view.select_tab(main_tab_workspace)
      of graph_tab_button_id:
        view.select_tab(main_tab_graph)
      else:
        if action.button_id.startsWith(graph_activity_button_prefix) and
            view.graph_tab.graph_view.selected_node_valid:
          let suffix = action.button_id[graph_activity_button_prefix.len .. ^1]
          try:
            let entry_index = parseInt(suffix)
            let node_id = view.graph_tab.graph_view.selected_node_id
            var conversation = view.graph_tab.node_conversation(node_id)
            if entry_index >= 0 and entry_index < conversation.messages.len and
                conversation.messages[entry_index].kind == cek_activity:
              conversation.messages[entry_index].expanded =
                not conversation.messages[entry_index].expanded
              view.graph_tab.node_conversations[node_id] = conversation
          except ValueError:
            discard
    of ui_action_text_field_submitted:
      if action.text_field_id != graph_conversation_input_id:
        continue
      let content = view.ui_state.text_field_value(graph_conversation_input_id)
      if content.strip.len == 0:
        continue
      if not view.graph_tab.graph_view.selected_node_valid:
        continue
      let node_id = view.graph_tab.graph_view.selected_node_id
      let graph = view.graph_tab.graph_view
      var submitted_user_input = false
      if view.graph_tab.pending_user_inputs.hasKey(node_id):
        if not graph.work_graph.node_can_accept_user_input(node_id):
          view.graph_tab.add_global_message(
            "NODE " & $node_id & " IS NOT WAITING FOR INPUT")
          continue
        let pending_input = view.graph_tab.pending_user_inputs[node_id]
        let parsed_answers = pending_input.parse_answers(content)
        if not parsed_answers.success:
          view.graph_tab.add_global_message(
            "NODE " & $node_id & " " & parsed_answers.error)
          continue
        if not view.codex_bridge.reply_user_input(
            pending_input.request_id, node_id, parsed_answers.answers):
          view.graph_tab.add_global_message(
            "NODE " & $node_id & " INPUT RESPONSE FAILED")
          continue
        submitted_user_input = true
      elif view.graph_tab.graph_view.work_graph.answer_human_input(
          node_id, content.strip):
        submitted_user_input = true
      elif not graph.work_graph.node_is_running(node_id):
        view.graph_tab.add_global_message(
          "NODE " & $node_id & " IS NOT RUNNING")
        continue
      let message = content.strip
      view.graph_tab.add_node_message(node_id, conversation_user, message)
      view.graph_tab.scroll_conversation_to_end = true
      if not submitted_user_input:
        discard view.graph_tab.graph_view.work_graph.set_node_objective(
          node_id, message)
        view.codex_bridge.send_node_message(node_id, message)
      view.ui_state.clear_text_field(graph_conversation_input_id)

proc sync_selected_node(view: MainWindow) =
  let graph = view.graph_tab.graph_view
  if graph.selected_node_valid == view.graph_tab.previous_selected_node_valid and
      (not graph.selected_node_valid or
        graph.selected_node_id == view.graph_tab.previous_selected_node_id):
    return

  view.graph_tab.previous_selected_node_valid = graph.selected_node_valid
  view.graph_tab.previous_selected_node_id = graph.selected_node_id
  if not graph.selected_node_valid:
    return

  let node_id = graph.selected_node_id
  var conversation = view.graph_tab.node_conversation(node_id)
  view.graph_tab.node_conversations[node_id] = conversation

proc build_tab_bar(view: MainWindow) =
  let workspace_button_element_id = clay_id(workspace_tab_button_id)
  let graph_button_element_id = clay_id(graph_tab_button_id)
  view.ui_state.register_button(
    workspace_tab_button_id, workspace_button_element_id)
  view.ui_state.register_button(graph_tab_button_id, graph_button_element_id)

  element("tab_bar"):
    layout:
      sizing:
        width = grow()
        height = fixed(48)
      padding = padding_all(6)
      child_gap = 8
      layout_direction = clay_left_to_right
    clip:
      vertical = true
    background_color = palette_color(view.palette.paper)
    border:
      color = palette_color(view.palette.ink)
      width = border_outside(4)

    element(workspace_button_element_id):
      layout:
        sizing:
          width = fixed(142)
          height = grow()
        padding = padding_all(6)
        child_alignment:
          x = clay_align_x_center
          y = clay_align_y_center
      clip:
        vertical = true
      background_color = if view.tab_manager.active_tab == main_tab_workspace:
        palette_color(view.palette.pink)
      else:
        palette_color(view.palette.paper)
      border:
        color = palette_color(view.palette.ink)
        width = border_outside(3)
      text("WORKSPACE"):
        font_size = 10
        text_color = palette_color(view.palette.ink)
        wrap_mode = clay_text_wrap_words_and_graphemes

    element(graph_button_element_id):
      layout:
        sizing:
          width = fixed(142)
          height = grow()
        padding = padding_all(6)
        child_alignment:
          x = clay_align_x_center
          y = clay_align_y_center
      clip:
        vertical = true
      background_color = if view.tab_manager.active_tab == main_tab_graph:
        palette_color(view.palette.pink)
      else:
        palette_color(view.palette.paper)
      border:
        color = palette_color(view.palette.ink)
        width = border_outside(3)
      text("GRAPH"):
        font_size = 10
        text_color = palette_color(view.palette.ink)
        wrap_mode = clay_text_wrap_words_and_graphemes


proc build_workspace_tab(view: MainWindow; frame: ViewFrame) =
  let search_element_id = clay_id("search_field")
  view.ui_state.register_text_field(
    text_field_search,
    search_element_id,
    initial_value = "type here")

  inc view.workspace_tab.debug_cycle_frame
  let debug_phase = int((view.workspace_tab.debug_cycle_frame div 60'u64) mod 4'u64)
  if debug_phase != view.workspace_tab.debug_last_phase:
    echo "Clay transition debug: phase ", debug_phase,
      ", exiting transitions = ", frame.exiting_transitions
    view.workspace_tab.debug_last_phase = debug_phase
  let debug_show_panel_a = debug_phase != 2
  let debug_swap_panels = debug_phase == 1 or debug_phase == 2

  let debug_transition = ClayTransitionElementConfig(
    handler: clay_ease_out,
    duration: 0.45,
    properties: clay_transition_property_position,
    interaction_handling: clay_transition_allow_interactions_while_transitioning_position,
    enter: ClayTransitionEnter(
      set_initial_state: debug_transition_set_initial_state,
      trigger: clay_transition_enter_trigger_on_first_parent_frame),
    exit: ClayTransitionExit(
      set_final_state: debug_transition_set_final_state,
      trigger: clay_transition_exit_trigger_when_parent_exits,
      sibling_ordering: clay_exit_transition_ordering_natural_order))
  let debug_panel_layout = layout(
    sizing = sizing(grow(), grow()),
    padding = padding_all(6),
    child_gap = 3,
    layout_direction = clay_top_to_bottom)
  let vertical_panel_clip = ClayClipElementConfig(vertical: true)
  let debug_panel_a_declaration = declaration(
    layout = debug_panel_layout,
    clip = vertical_panel_clip,
    background_color = palette_color(view.palette.pink),
    border = ClayBorderElementConfig(
      color: palette_color(view.palette.ink), width: border_outside(3)),
    transition = debug_transition)
  let debug_panel_b_declaration = declaration(
    layout = debug_panel_layout,
    clip = vertical_panel_clip,
    background_color = palette_color(view.palette.mint),
    border = ClayBorderElementConfig(
      color: palette_color(view.palette.ink), width: border_outside(3)),
    transition = debug_transition)


  element("root"):
    layout:
      sizing:
        width = grow()
        height = grow()
      padding = padding_all(16)
      child_gap = 14
      layout_direction = clay_top_to_bottom
    background_color = palette_color(view.palette.background)
    border:
      color = palette_color(view.palette.ink)
      width = border_outside(4)

    build_tab_bar(view)

    element("top_bar"):
      layout:
        sizing:
          width = grow()
          height = fixed(66)
        padding = padding_all(10)
        child_gap = 12
        layout_direction = clay_left_to_right
      clip:
        vertical = true
      background_color = palette_color(view.palette.paper)
      border:
        color = palette_color(view.palette.ink)
        width = border_outside(4)

      element("brand"):
        layout:
          sizing:
            width = fixed(70)
            height = fixed(46)
          child_alignment:
            x = clay_align_x_center
            y = clay_align_y_center
        clip:
          vertical = true
        background_color = palette_color(view.palette.pink)
        border:
          color = palette_color(view.palette.ink)
          width = border_outside(4)
        text("NB/01"):
          font_size = 16
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes

      element("title"):
        layout:
          sizing:
            width = grow()
            height = grow()
          padding = padding_all(2)
          layout_direction = clay_top_to_bottom
          child_gap = 3
          child_alignment:
            y = clay_align_y_center
        clip:
          vertical = true
        text("NEO BRUTAL STACK"):
          font_size = 19
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes
        text("HARD EDGES / DEEP LAYERS"):
          font_size = 10
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes

      element(search_element_id):
        layout:
          sizing:
            width = fixed(174)
            height = grow()
          padding = padding_all(8)
          child_gap = 3
          layout_direction = clay_top_to_bottom
        clip:
          vertical = true
        background_color = if view.ui_state.text_field_focused(text_field_search):
          palette_color(view.palette.yellow)
        else:
          palette_color(view.palette.paper)
        border:
          color = palette_color(view.palette.ink)
          width = border_outside(3)
        text("INPUT // SEARCH"):
          font_size = 8
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes
        text(view.ui_state.text_field_display(text_field_search)):
          font_size = 11
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes

      element("status"):
        layout:
          sizing:
            width = fixed(116)
            height = grow()
          padding = padding_all(8)
          child_gap = 4
          layout_direction = clay_top_to_bottom
          child_alignment:
            x = clay_align_x_center
        clip:
          vertical = true
        background_color = palette_color(view.palette.mint)
        border:
          color = palette_color(view.palette.ink)
          width = border_outside(4)
        text("STATUS: LIVE"):
          font_size = 10
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes
        element("status_bar"):
          layout:
            sizing:
              width = grow()
              height = fixed(8)
          background_color = palette_color(view.palette.ink)

    element("body"):
      layout:
        sizing:
          width = grow()
          height = grow()
        child_gap = 14
        layout_direction = clay_left_to_right

      element("sidebar"):
        layout:
          sizing:
            width = fixed(150)
            height = grow()
          padding = padding_all(10)
          child_gap = 8
          layout_direction = clay_top_to_bottom
        clip:
          vertical = true
        background_color = palette_color(view.palette.yellow)
        border:
          color = palette_color(view.palette.ink)
          width = border_outside(4)
        text("INDEX // 08"):
          font_size = 13
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes
        for index in 0 ..< 8:
          element(clay_id_with_index("nav_item", uint32(index))):
            layout:
              sizing:
                width = grow()
                height = fixed(28)
              padding = padding_all(6)
              layout_direction = clay_left_to_right
            clip:
              vertical = true
            background_color = if index == 0:
              palette_color(view.palette.pink)
            else:
              palette_color(view.palette.paper)
            border:
              color = palette_color(view.palette.ink)
              width = border_outside(3)
            text(nav_labels[index]):
              font_size = 10
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes

      element("workbench"):
        layout:
          sizing:
            width = grow()
            height = grow()
          padding = padding_all(12)
          child_gap = 10
          layout_direction = clay_top_to_bottom
        clip:
          vertical = true
        background_color = palette_color(view.palette.blue)
        border:
          color = palette_color(view.palette.ink)
          width = border_outside(4)

        text("FLOATING BOX STUDY"):
          font_size = 13
          text_color = palette_color(view.palette.paper)
          wrap_mode = clay_text_wrap_words_and_graphemes

        element("string_pool_debug"):
          layout:
            sizing:
              width = grow()
              height = fixed(112)
            padding = padding_all(8)
            child_gap = 5
            layout_direction = clay_top_to_bottom
          clip:
            vertical = true
          background_color = palette_color(view.palette.yellow)
          border:
            color = palette_color(view.palette.ink)
            width = border_outside(3)
          text("STRING POOL / EXIT CYCLE"):
            font_size = 11
            text_color = palette_color(view.palette.ink)
            wrap_mode = clay_text_wrap_words_and_graphemes
          text("GEN " & $frame.string_cache_generation &
            " / LIVE " & $frame.string_cache_generation_count &
            " / EXIT " & $frame.exiting_transitions):
            font_size = 9
            text_color = palette_color(view.palette.ink)
            wrap_mode = clay_text_wrap_words_and_graphemes
          element("debug_slots"):
            layout:
              sizing:
                width = grow()
                height = grow()
              child_gap = 6
              layout_direction = clay_left_to_right
            if debug_swap_panels:
              element("debug_panel_b", debug_panel_b_declaration):
                text("PANEL B // " & $view.workspace_tab.debug_cycle_frame):
                  font_size = 10
                  text_color = palette_color(view.palette.ink)
                  wrap_mode = clay_text_wrap_words_and_graphemes
                text("DYNAMIC / STABLE POINTER"):
                  font_size = 8
                  text_color = palette_color(view.palette.ink)
                  wrap_mode = clay_text_wrap_words_and_graphemes
              if debug_show_panel_a:
                element("debug_panel_a", debug_panel_a_declaration):
                  text("PANEL A // " & $view.workspace_tab.debug_cycle_frame):
                    font_size = 10
                    text_color = palette_color(view.palette.ink)
                    wrap_mode = clay_text_wrap_words_and_graphemes
                  text("EXIT / RE-ENTER TEST"):
                    font_size = 8
                    text_color = palette_color(view.palette.ink)
                    wrap_mode = clay_text_wrap_words_and_graphemes
            else:
              if debug_show_panel_a:
                element("debug_panel_a", debug_panel_a_declaration):
                  text("PANEL A // " & $view.workspace_tab.debug_cycle_frame):
                    font_size = 10
                    text_color = palette_color(view.palette.ink)
                    wrap_mode = clay_text_wrap_words_and_graphemes
                  text("EXIT / RE-ENTER TEST"):
                    font_size = 8
                    text_color = palette_color(view.palette.ink)
                    wrap_mode = clay_text_wrap_words_and_graphemes
              element("debug_panel_b", debug_panel_b_declaration):
                text("PANEL B // " & $view.workspace_tab.debug_cycle_frame):
                  font_size = 10
                  text_color = palette_color(view.palette.ink)
                  wrap_mode = clay_text_wrap_words_and_graphemes
                text("DYNAMIC / STABLE POINTER"):
                  font_size = 8
                  text_color = palette_color(view.palette.ink)
                  wrap_mode = clay_text_wrap_words_and_graphemes

        element("stage"):
          layout:
            sizing:
              width = grow()
              height = grow()
          clip:
            horizontal = true
            vertical = true
          background_color = palette_color(view.palette.paper)
          border:
            color = palette_color(view.palette.purple)
            width = border_outside(4)

          graph_window(view.workspace_tab.graph_view):
            discard

          element("float_yellow"):
            layout:
              sizing:
                width = fixed(210)
                height = fixed(112)
              padding = padding_all(10)
              child_gap = 5
              layout_direction = clay_top_to_bottom
            clip:
              vertical = true
            background_color = palette_color(view.palette.yellow)
            border:
              color = palette_color(view.palette.ink)
              width = border_outside(4)
            floating:
              offset = vector2(18, 18)
              z_index = 1
              attach_points:
                element = clay_attach_point_left_top
                parent = clay_attach_point_left_top
              pointer_capture_mode = clay_pointer_capture_mode_passthrough
              attach_to = clay_attach_to_parent
              clip_to = clay_clip_to_none
            text("LAYER 1"):
              font_size = 12
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("YELLOW / FRONT LEFT"):
              font_size = 16
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("OFFSET +018 / +018"):
              font_size = 10
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            element("yellow_strip"):
              layout:
                sizing:
                  width = fixed(116)
                  height = fixed(8)
              background_color = palette_color(view.palette.ink)

          element("float_blue"):
            layout:
              sizing:
                width = fixed(214)
                height = fixed(116)
              padding = padding_all(10)
              child_gap = 5
              layout_direction = clay_top_to_bottom
            clip:
              vertical = true
            background_color = palette_color(view.palette.blue)
            border:
              color = palette_color(view.palette.ink)
              width = border_outside(4)
            floating:
              offset = vector2(104, 66)
              z_index = 2
              attach_points:
                element = clay_attach_point_left_top
                parent = clay_attach_point_left_top
              pointer_capture_mode = clay_pointer_capture_mode_passthrough
              attach_to = clay_attach_to_parent
              clip_to = clay_clip_to_none
            text("LAYER 2"):
              font_size = 12
              text_color = palette_color(view.palette.paper)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("BLUE / OVERLAP"):
              font_size = 16
              text_color = palette_color(view.palette.paper)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("Z-INDEX 002"):
              font_size = 10
              text_color = palette_color(view.palette.paper)
              wrap_mode = clay_text_wrap_words_and_graphemes
            element("blue_strip"):
              layout:
                sizing:
                  width = fixed(144)
                  height = fixed(8)
              background_color = palette_color(view.palette.ink)

          element("float_pink"):
            layout:
              sizing:
                width = fixed(190)
                height = fixed(106)
              padding = padding_all(10)
              child_gap = 5
              layout_direction = clay_top_to_bottom
            clip:
              vertical = true
            background_color = palette_color(view.palette.pink)
            border:
              color = palette_color(view.palette.ink)
              width = border_outside(4)
            floating:
              offset = vector2(188, 150)
              z_index = 3
              attach_points:
                element = clay_attach_point_left_top
                parent = clay_attach_point_left_top
              pointer_capture_mode = clay_pointer_capture_mode_passthrough
              attach_to = clay_attach_to_parent
              clip_to = clay_clip_to_none
            text("LAYER 3"):
              font_size = 12
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("PINK / CROSSOVER"):
              font_size = 15
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("Z-INDEX 003"):
              font_size = 10
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            element("pink_tag"):
              layout:
                sizing:
                  width = fixed(94)
                  height = fixed(28)
                padding = padding_all(4)
                child_alignment:
                  x = clay_align_x_center
                  y = clay_align_y_center
              clip:
                vertical = true
              background_color = palette_color(view.palette.ink)
              floating:
                offset = vector2(10, -14)
                z_index = 5
                attach_points:
                  element = clay_attach_point_right_top
                  parent = clay_attach_point_right_top
                pointer_capture_mode = clay_pointer_capture_mode_passthrough
                attach_to = clay_attach_to_parent
                clip_to = clay_clip_to_none
              text("LEVEL 5"):
                font_size = 10
                text_color = palette_color(view.palette.paper)
                wrap_mode = clay_text_wrap_words_and_graphemes

          element("float_mint"):
            layout:
              sizing:
                width = fixed(166)
                height = fixed(84)
              padding = padding_all(10)
              child_gap = 5
              layout_direction = clay_top_to_bottom
            clip:
              vertical = true
            background_color = palette_color(view.palette.mint)
            border:
              color = palette_color(view.palette.ink)
              width = border_outside(4)
            floating:
              offset = vector2(52, 190)
              z_index = 4
              attach_points:
                element = clay_attach_point_left_top
                parent = clay_attach_point_left_top
              pointer_capture_mode = clay_pointer_capture_mode_passthrough
              attach_to = clay_attach_to_parent
              clip_to = clay_clip_to_none
            text("LAYER 4"):
              font_size = 12
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("MINT / LAST WORD"):
              font_size = 13
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("Z-INDEX 004"):
              font_size = 10
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes

    element("footer"):
      layout:
        sizing:
          width = grow()
          height = fixed(40)
        padding = padding_all(8)
        child_gap = 10
        layout_direction = clay_left_to_right
        child_alignment:
          y = clay_align_y_center
      clip:
        vertical = true
      background_color = palette_color(view.palette.ink)
      border:
        color = palette_color(view.palette.ink)
        width = border_outside(4)
      text("CLAY / FLOATING / 60 FPS"):
        font_size = 10
        text_color = palette_color(view.palette.paper)
        wrap_mode = clay_text_wrap_words_and_graphemes
      element("footer_pink"):
        layout:
          sizing:
            width = fixed(74)
            height = fixed(18)
          child_alignment:
            x = clay_align_x_center
            y = clay_align_y_center
        clip:
          vertical = true
        background_color = palette_color(view.palette.pink)
        border:
          color = palette_color(view.palette.paper)
          width = border_outside(2)
        text("Z: 005"):
          font_size = 9
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes
      element("footer_yellow"):
        layout:
          sizing:
            width = fixed(112)
            height = fixed(18)
          child_alignment:
            x = clay_align_x_center
            y = clay_align_y_center
        clip:
          vertical = true
        background_color = palette_color(view.palette.yellow)
        border:
          color = palette_color(view.palette.paper)
          width = border_outside(2)
        text("NO ROUNDED CORNERS"):
          font_size = 8
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes

proc activity_header(entry: ConversationEntry): string =
  result = "[" & activity_state_text(entry.activity_state) & "] " & entry.title
  if entry.detail.len > 0:
    result.add(" / " & entry.detail)
  if entry.activity_kind == cak_changes and
      (entry.added > 0 or entry.removed > 0):
    result.add(" / +" & $entry.added & " -" & $entry.removed)

proc activity_body(entry: ConversationEntry): string =
  result = entry.body
  if entry.files.len == 0:
    return
  if result.len > 0:
    result.add("\n")
  for file in entry.files:
    result.add(file.path & "  +" & $file.added & " -" & $file.removed)
    result.add("\n")
  result.setLen(result.len - 1)

proc build_graph_conversation_panel(view: MainWindow) =
  let input_element_id = clay_id(graph_conversation_input_id)
  view.ui_state.register_text_field(
    graph_conversation_input_id, input_element_id)
  let node_id = view.graph_tab.graph_view.selected_node_id
  let conversation = view.graph_tab.node_conversations[node_id]

  element("graph_conversation_content"):
    layout:
      sizing:
        width = grow()
        height = grow()
      padding = padding_all(12)
      child_gap = 10
      layout_direction = clay_top_to_bottom
    background_color = palette_color(view.palette.paper)

    text("NODE CONVERSATION"):
      font_size = 10
      text_color = palette_color(view.palette.ink)
      wrap_mode = clay_text_wrap_words_and_graphemes
    text("NODE " & $node_id):
      font_size = 8
      text_color = palette_color(view.palette.ink)
      wrap_mode = clay_text_wrap_words_and_graphemes
    text("STATUS / " & status_text(conversation.state) &
        (if conversation.status_detail.len > 0:
          " / " & conversation.status_detail
        else: "")):
      font_size = 8
      text_color = palette_color(view.palette.ink)
      wrap_mode = clay_text_wrap_words_and_graphemes
    if conversation.token_usage.len > 0:
      text(conversation.token_usage):
        font_size = 8
        text_color = palette_color(view.palette.ink)
        wrap_mode = clay_text_wrap_words_and_graphemes
    if conversation.current_model.len > 0:
      text("MODEL / " & conversation.current_model):
        font_size = 8
        text_color = palette_color(view.palette.ink)
        wrap_mode = clay_text_wrap_words_and_graphemes

    let log_element_id = clay_id(graph_conversation_log_id)
    let log_declaration = declaration(
      layout = layout(
        sizing = sizing(grow(), grow()),
        padding = padding_all(8),
        child_gap = 8,
        layout_direction = clay_top_to_bottom),
      background_color = palette_color(view.palette.background),
      border = ClayBorderElementConfig(
        color: palette_color(view.palette.ink), width: border_outside(2)),
      clip = ClayClipElementConfig(vertical: true))
    scrollable_element(log_element_id, log_declaration):
      for message_index, message in conversation.messages:
        let row_id = clay_id_with_index(
          "graph_conversation_message", uint32(message_index))
        if message.kind == cek_message:
          let is_user = message.speaker == conversation_user
          let row_declaration = declaration(
            layout = layout(
              sizing = sizing(grow(), fit()),
              child_alignment = child_alignment(
                if is_user:
                  clay_align_x_right
                else:
                  clay_align_x_left,
                clay_align_y_top)))
          let bubble_declaration = declaration(
            layout = layout(
              sizing = sizing(fit(0, 260), fit()),
              padding = padding_all(8)),
            background_color = if is_user:
              palette_color(view.palette.blue)
            else:
              palette_color(view.palette.yellow),
            border = ClayBorderElementConfig(
              color: palette_color(view.palette.ink), width: border_outside(2)))
          element(row_id, row_declaration):
            element(clay_id_with_index(
                "graph_conversation_bubble", uint32(message_index)),
                bubble_declaration):
              text(message.content):
                font_size = 10
                text_color = if is_user:
                  palette_color(view.palette.paper)
                else:
                  palette_color(view.palette.ink)
                wrap_mode = clay_text_wrap_words_and_graphemes
        else:
          let activity_button_id = graph_activity_button_prefix & $message_index
          let activity_element_id = clay_id(activity_button_id)
          view.ui_state.register_button(activity_button_id, activity_element_id)
          let activity_declaration = declaration(
            layout = layout(
              sizing = sizing(grow(), fit()),
              padding = padding_all(8),
              child_gap = 5,
              layout_direction = clay_top_to_bottom),
            background_color = if message.activity_state == cas_waiting:
              palette_color(view.palette.pink)
            elif message.activity_state == cas_error:
              palette_color(view.palette.yellow)
            else:
              palette_color(view.palette.background),
            border = ClayBorderElementConfig(
              color: palette_color(view.palette.ink), width: border_outside(2)))
          element(row_id, declaration(
              layout = layout(sizing = sizing(grow(), fit())))):
            element(activity_element_id, activity_declaration):
              text(activity_header(message)):
                font_size = 9
                text_color = palette_color(view.palette.ink)
                wrap_mode = clay_text_wrap_words_and_graphemes
              if message.expanded and
                  (message.body.len > 0 or message.files.len > 0):
                element(clay_id_with_index(
                    "graph_conversation_activity_body",
                    uint32(message_index)), declaration(
                      layout = layout(
                        sizing = sizing(grow(), fit()),
                        padding = padding_all(5)),
                      background_color = palette_color(view.palette.paper))):
                  text(activity_body(message)):
                    font_size = 9
                    text_color = palette_color(view.palette.ink)
                    wrap_mode = clay_text_wrap_words_and_graphemes

    element(graph_conversation_composer_id):
      layout:
        sizing:
          width = grow()
          height = fit(52, 156)
        padding = padding_all(8)
        child_gap = 5
        layout_direction = clay_top_to_bottom
      background_color = if view.ui_state.text_field_focused(
          graph_conversation_input_id):
        palette_color(view.palette.yellow)
      else:
        palette_color(view.palette.background)
      border:
        color = palette_color(view.palette.ink)
        width = border_outside(2)
      text("MESSAGE / ENTER TO SEND"):
        font_size = 8
        text_color = palette_color(view.palette.ink)
        wrap_mode = clay_text_wrap_words_and_graphemes

      let input_declaration = declaration(
        layout = layout(
          sizing = sizing(grow(), fit(20, 124)),
          padding = padding_all(4)),
        background_color = palette_color(view.palette.paper),
        clip = ClayClipElementConfig(vertical: true))
      scrollable_element(input_element_id, input_declaration):
        text(view.ui_state.text_field_display(graph_conversation_input_id)):
          font_size = 11
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes

proc build_graph_tab(view: MainWindow) =
  element("root"):
    layout:
      sizing:
        width = grow()
        height = grow()
      padding = padding_all(16)
      child_gap = 14
      layout_direction = clay_top_to_bottom
    background_color = palette_color(view.palette.background)
    border:
      color = palette_color(view.palette.ink)
      width = border_outside(4)

    build_tab_bar(view)

    element("graph_section"):
      layout:
        sizing:
          width = grow()
          height = grow()
        padding = padding_all(12)
        child_gap = 10
        layout_direction = clay_top_to_bottom
      clip:
        vertical = true
      background_color = palette_color(view.palette.blue)
      border:
        color = palette_color(view.palette.ink)
        width = border_outside(4)

      text("GRAPH / RANDOM INITIAL / CODEX CHAT"):
        font_size = 13
        text_color = palette_color(view.palette.paper)
        wrap_mode = clay_text_wrap_words_and_graphemes

      if view.graph_tab.global_log_messages.len > 0:
        element("graph_global_log_panel"):
          layout:
            sizing:
              width = grow()
              height = fit(28, 128)
            padding = padding_all(8)
            child_gap = 5
            layout_direction = clay_top_to_bottom
          background_color = palette_color(view.palette.paper)
          border:
            color = palette_color(view.palette.ink)
            width = border_outside(3)
          text("GLOBAL LOG"):
            font_size = 8
            text_color = palette_color(view.palette.ink)
            wrap_mode = clay_text_wrap_words_and_graphemes
          let global_log_element_id = clay_id(graph_global_log_id)
          let global_log_declaration = declaration(
            layout = layout(
              sizing = sizing(grow(), grow()),
              child_gap = 3,
              layout_direction = clay_top_to_bottom),
            clip = ClayClipElementConfig(vertical: true))
          scrollable_element(global_log_element_id, global_log_declaration):
            for message in view.graph_tab.global_log_messages:
              text(message):
                font_size = 8
                text_color = palette_color(view.palette.ink)
                wrap_mode = clay_text_wrap_words_and_graphemes

      element("graph_stage"):
        layout:
          sizing:
            width = grow()
            height = grow()
        clip:
          horizontal = true
          vertical = true
        background_color = palette_color(view.palette.paper)
        border:
          color = palette_color(view.palette.purple)
          width = border_outside(4)

        graph_window_with_panel(
            view.graph_tab.graph_view,
            view.build_graph_conversation_panel()):
          discard
        if view.graph_tab.graph_view.hovered_node_valid:
          let graph = view.graph_tab.graph_view
          let hovered_node = graph.hovered_work_node()
          let tooltip_size = dimensions(
            graph_node_tooltip_width,
            graph_node_tooltip_height)
          let node_id_text = "NODE // " & $hovered_node.id
          let plan_text = "PLAN // " & toUpperAscii(
            ($hovered_node.execution_plan.`type`).replace('_', ' '))
          let state_text = "STATE // " & toUpperAscii(
            ($hovered_node.state).replace('_', ' '))
          let tooltip_declaration = declaration(
            layout = layout(
              sizing = sizing(
                fixed(tooltip_size.width),
                fixed(tooltip_size.height)),
              padding = padding_all(8),
              child_gap = 3,
              layout_direction = clay_top_to_bottom),
            background_color = palette_color(view.palette.yellow),
            border = ClayBorderElementConfig(
              color: palette_color(view.palette.ink),
              width: border_outside(3)),
            floating = ClayFloatingElementConfig(
              offset: graph.graph_node_tooltip_position(
                clay_get_layout_dimensions(),
                tooltip_size,
                graph_node_tooltip_gap),
              attach_points: ClayFloatingAttachPoints(
                element: clay_attach_point_left_top,
                parent: clay_attach_point_left_top),
              pointer_capture_mode: clay_pointer_capture_mode_passthrough,
              attach_to: clay_attach_to_root,
              clip_to: clay_clip_to_none,
              z_index: graph_node_tooltip_z_index))
          element(graph_node_tooltip_id, tooltip_declaration):
            text(node_id_text):
              font_size = 8
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text(plan_text):
              font_size = 10
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text(state_text):
              font_size = 10
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
        if not view.graph_tab.graph_view.selected_node_valid and
            view.ui_state.text_field_focused(graph_conversation_input_id):
          view.ui_state.clear_focus()

proc build_elements*(view: MainWindow; frame: ViewFrame) =
  case view.tab_manager.active_tab
  of main_tab_workspace:
    view.build_workspace_tab(frame)
  of main_tab_graph:
    view.build_graph_tab()
