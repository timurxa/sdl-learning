import std/[json, options, strutils, tables]

type
  JsonObject* = Table[string, JsonNode]

  RequestKind* = enum
    mk_initialize,
    mk_thread_start,
    mk_turn_start

  ServerRequestKind* = enum
    sr_command_execution_approval,
    sr_file_change_approval,
    sr_tool_user_input,
    sr_tool_call,
    sr_auth_tokens_refresh,
    sr_apply_patch_approval,
    sr_exec_command_approval,
    sr_unknown

  RequestIdKind* = enum
    rid_string,
    rid_integer

  RequestId* = object
    case kind*: RequestIdKind
    of rid_string:
      string_value*: string
    of rid_integer:
      integer_value*: int64

  AskForApproval* = enum
    apa_untrusted,
    apa_on_failure,
    apa_on_request,
    apa_never

  SandboxMode* = enum
    sm_read_only,
    sm_workspace_write,
    sm_danger_full_access

  Personality* = enum
    p_none,
    p_friendly,
    p_pragmatic

  ReasoningEffort* = enum
    re_minimal,
    re_low,
    re_medium,
    re_high,
    re_xhigh

  TurnStatus* = enum
    ts_in_progress,
    ts_completed,
    ts_interrupted,
    ts_failed,
    ts_unknown

  ThreadStatusKind* = enum
    tsk_idle,
    tsk_active,
    tsk_system_error,
    tsk_not_loaded,
    tsk_unknown

  ActiveFlag* = enum
    af_waiting_on_approval,
    af_waiting_on_user_input

  Nullable*[T] = object
    case has_value*: bool
    of false:
      discard
    of true:
      value*: T

  NullableOptionState* = enum
    nos_none,
    nos_null,
    nos_value

  NullableOption*[T] = object
    case state*: NullableOptionState
    of nos_none, nos_null:
      discard
    of nos_value:
      value*: T

  InitializeCapabilities* = object
    experimental_api*: NullableOption[bool]
    opt_out_notification_methods*: NullableOption[seq[string]]
    extra_fields*: JsonObject

  ClientInfo* = object
    name*: string
    title*: NullableOption[string]
    version*: string
    extra_fields*: JsonObject

  InitializeParams* = object
    capabilities*: NullableOption[InitializeCapabilities]
    client_info*: ClientInfo
    extra_fields*: JsonObject

  Config* = JsonObject

  ThreadStartParams* = object
    approval_policy*: NullableOption[AskForApproval]
    base_instructions*: NullableOption[string]
    config*: NullableOption[Config]
    cwd*: NullableOption[string]
    developer_instructions*: NullableOption[string]
    sandbox*: NullableOption[SandboxMode]
    ephemeral*: NullableOption[bool]
    model_provider*: NullableOption[string]
    personality*: NullableOption[Personality]
    model*: NullableOption[string]
    dynamic_tools*: NullableOption[seq[DynamicToolSpec]]
    extra_fields*: JsonObject

  TextInput* = object
    text*: string
    extra_fields*: JsonObject

  TurnStartParams* = object
    thread_id*: string
    text*: string
    effort*: NullableOption[ReasoningEffort]
    extra_fields*: JsonObject

  Params* = object
    case kind*: RequestKind
    of mk_initialize:
      initialize*: InitializeParams
    of mk_thread_start:
      thread_start*: ThreadStartParams
    of mk_turn_start:
      turn_start*: TurnStartParams

  Request* = object
    kind*: RequestKind
    id*: RequestId
    params*: Params
    extra_fields*: JsonObject

  CommandActionKind* = enum
    cak_read,
    cak_list_files,
    cak_search,
    cak_unknown

  CommandAction* = object
    kind*: CommandActionKind
    command*: string
    name*: NullableOption[string]
    path*: NullableOption[string]
    query*: NullableOption[string]
    extra_fields*: JsonObject

  ParsedCommandKind* = enum
    pck_read,
    pck_list_files,
    pck_search,
    pck_unknown

  ParsedCommand* = object
    kind*: ParsedCommandKind
    cmd*: string
    name*: NullableOption[string]
    path*: NullableOption[string]
    query*: NullableOption[string]
    extra_fields*: JsonObject

  CommandExecutionRequestApprovalParams* = object
    approval_id*: NullableOption[string]
    command*: NullableOption[string]
    command_actions*: NullableOption[seq[CommandAction]]
    cwd*: NullableOption[string]
    item_id*: string
    proposed_execpolicy_amendment*: NullableOption[seq[string]]
    reason*: NullableOption[string]
    thread_id*: string
    turn_id*: string
    extra_fields*: JsonObject

  FileChangeKind* = enum
    fck_add,
    fck_delete,
    fck_update,
    fck_unknown

  FileChange* = object
    kind*: FileChangeKind
    content*: NullableOption[string]
    move_path*: NullableOption[string]
    unified_diff*: NullableOption[string]
    extra_fields*: JsonObject

  FileChangeRequestApprovalParams* = object
    grant_root*: NullableOption[string]
    item_id*: string
    reason*: NullableOption[string]
    thread_id*: string
    turn_id*: string
    extra_fields*: JsonObject

  ToolRequestUserInputOption* = object
    description*: string
    label*: string
    extra_fields*: JsonObject

  ToolRequestUserInputQuestion* = object
    header*: string
    id*: string
    is_other*: NullableOption[bool]
    is_secret*: NullableOption[bool]
    options*: NullableOption[seq[ToolRequestUserInputOption]]
    question*: string
    extra_fields*: JsonObject

  ToolRequestUserInputParams* = object
    item_id*: string
    questions*: seq[ToolRequestUserInputQuestion]
    thread_id*: string
    turn_id*: string
    extra_fields*: JsonObject

  DynamicToolCallParams* = object
    arguments*: JsonNode
    call_id*: string
    thread_id*: string
    tool*: string
    turn_id*: string
    extra_fields*: JsonObject

  ToolCallContext* = object
    request_id*: RequestId
    params*: DynamicToolCallParams

  DynamicToolCallback* = proc(data: pointer; context: ToolCallContext) {.closure.}

  DynamicTool* = object
    name*: string
    description*: string
    input_schema*: JsonNode
    data*: pointer
    callback*: DynamicToolCallback

  DynamicToolRegistry* = seq[DynamicTool]

  DynamicToolSpec* = object
    name*: string
    description*: string
    input_schema*: JsonNode
    extra_fields*: JsonObject

  DynamicToolContentKind* = enum
    dtc_input_text,
    dtc_input_image,
    dtc_input_audio

  DynamicToolContentItem* = object
    case kind*: DynamicToolContentKind
    of dtc_input_text:
      text*: string
    of dtc_input_image:
      image_url*: string
    of dtc_input_audio:
      audio_url*: string

  DynamicToolCallResponse* = object
    success*: bool
    content_items*: seq[DynamicToolContentItem]

  AuthTokensRefreshReason* = enum
    atrr_unauthorized,
    atrr_unknown

  ChatgptAuthTokensRefreshParams* = object
    previous_account_id*: NullableOption[string]
    reason*: AuthTokensRefreshReason
    extra_fields*: JsonObject

  ApplyPatchApprovalParams* = object
    call_id*: string
    conversation_id*: string
    file_changes*: Table[string, FileChange]
    grant_root*: NullableOption[string]
    reason*: NullableOption[string]
    extra_fields*: JsonObject

  ExecCommandApprovalParams* = object
    approval_id*: NullableOption[string]
    call_id*: string
    command*: seq[string]
    conversation_id*: string
    cwd*: string
    parsed_cmd*: seq[ParsedCommand]
    reason*: NullableOption[string]
    extra_fields*: JsonObject

  ServerRequestParams* = object
    case kind*: ServerRequestKind
    of sr_command_execution_approval:
      command_execution_approval*: CommandExecutionRequestApprovalParams
    of sr_file_change_approval:
      file_change_approval*: FileChangeRequestApprovalParams
    of sr_tool_user_input:
      tool_user_input*: ToolRequestUserInputParams
    of sr_tool_call:
      tool_call*: DynamicToolCallParams
    of sr_auth_tokens_refresh:
      auth_tokens_refresh*: ChatgptAuthTokensRefreshParams
    of sr_apply_patch_approval:
      apply_patch_approval*: ApplyPatchApprovalParams
    of sr_exec_command_approval:
      exec_command_approval*: ExecCommandApprovalParams
    of sr_unknown:
      unknown*: JsonNode

  Error* = object
    id*: RequestId
    code*: int64
    message*: string
    extra_fields*: JsonObject

  ServerRequest* = object
    id*: RequestId
    kind*: ServerRequestKind
    method_name*: string
    params_json*: string
    params*: ServerRequestParams
    extra_fields*: JsonObject

  ServerResponse* = object
    id*: RequestId
    result*: Option[JsonNode]
    error*: Option[Error]
    extra_fields*: JsonObject

  NotificationKind* = enum
    nk_initialized,
    nk_thread_started,
    nk_thread_token_usage_updated,
    nk_turn_started,
    nk_turn_completed,
    nk_turn_diff_updated,
    nk_turn_plan_updated,
    nk_item_started,
    nk_item_completed,
    nk_agent_message_delta,
    nk_plan_delta,
    nk_command_execution_output_delta,
    nk_terminal_interaction,
    nk_file_change_output_delta,
    nk_mcp_tool_call_progress,
    nk_reasoning_summary_text_delta,
    nk_reasoning_summary_part_added,
    nk_thread_compacted,
    nk_model_rerouted,
    nk_thread_status_changed,
    nk_thread_closed,
    nk_error,
    nk_unknown

  NotificationParams* = object
    thread_id*: Nullable[string]
    turn_id*: Option[string]
    item_id*: Option[string]
    turn_status*: Option[TurnStatus]
    delta*: Option[string]
    summary_index*: Option[int]
    will_retry*: Option[bool]
    raw_params*: JsonNode
    thread_status*: Option[ThreadStatusKind]
    active_flags*: set[ActiveFlag]
    error_message*: Option[string]
    thread_extra_fields*: JsonObject
    turn_extra_fields*: JsonObject
    extra_fields*: JsonObject

  Notification* = object
    kind*: NotificationKind
    method_name*: string
    params*: NotificationParams
    extra_fields*: JsonObject

  ResponseResult* = object
    case kind*: RequestKind
    of mk_initialize:
      discard
    of mk_thread_start:
      thread_id*: string
      thread_extra_fields*: JsonObject
    of mk_turn_start:
      turn_id*: string
      turn_status*: TurnStatus
      turn_extra_fields*: JsonObject

  Success* = object
    id*: RequestId
    result*: ResponseResult
    raw_result*: JsonNode
    extra_fields*: JsonObject

  MessageKind* = enum
    mk_request,
    mk_server_request,
    mk_server_response,
    mk_success,
    mk_error,
    mk_notification

  Message* = object
    case kind*: MessageKind
    of mk_request:
      request*: Request
    of mk_server_request:
      server_request*: ServerRequest
    of mk_server_response:
      server_response*: ServerResponse
    of mk_success:
      success*: Success
    of mk_error:
      error*: Error
    of mk_notification:
      notification*: Notification

proc new_notification_params*(): NotificationParams =
  NotificationParams(
    thread_id: Nullable[string](has_value: false),
    turn_id: none(string),
    item_id: none(string),
    turn_status: none(TurnStatus),
    delta: none(string),
    summary_index: none(int),
    will_retry: none(bool),
    raw_params: newJObject(),
    thread_status: none(ThreadStatusKind),
    active_flags: {},
    error_message: none(string),
    thread_extra_fields: initTable[string, JsonNode](),
    turn_extra_fields: initTable[string, JsonNode](),
    extra_fields: initTable[string, JsonNode]())

proc register_dynamic_tool*(registry: var DynamicToolRegistry;
    name, description: string; input_schema: JsonNode; data: pointer;
    callback: DynamicToolCallback) =
  registry.add(DynamicTool(
    name: name,
    description: description,
    input_schema: input_schema,
    data: data,
    callback: callback
  ))

proc dynamic_tool_text*(text: string): DynamicToolContentItem =
  DynamicToolContentItem(kind: dtc_input_text, text: text)

proc dynamic_tool_image*(image_url: string): DynamicToolContentItem =
  DynamicToolContentItem(kind: dtc_input_image, image_url: image_url)

proc dynamic_tool_audio*(audio_url: string): DynamicToolContentItem =
  DynamicToolContentItem(kind: dtc_input_audio, audio_url: audio_url)

proc json_object*(node: JsonNode): JsonObject =
  if node.kind != JObject:
    raise newException(ValueError, "expected a JSON object")
  result = initTable[string, JsonNode]()
  for key, value in node.pairs:
    result[key] = value

proc json_object_node(value: JsonObject): JsonNode =
  result = newJObject()
  for key, item in value.pairs:
    result[key] = item

proc extra_fields(node: JsonNode; known: varargs[string]): JsonObject =
  result = initTable[string, JsonNode]()
  if node.kind != JObject:
    return
  for key, value in node.pairs:
    var is_known = false
    for known_key in known:
      if key == known_key:
        is_known = true
        break
    if not is_known:
      result[key] = value

proc add_extra_fields(node: JsonNode; fields: JsonObject) =
  for key, value in fields.pairs:
    node[key] = value

proc put_nullable_option[T](node: JsonNode; key: string;
    value: NullableOption[T]; serialize: proc(value: T): JsonNode {.gcsafe.}) =
  case value.state:
  of nos_none:
    discard
  of nos_null:
    node[key] = newJNull()
  of nos_value:
    node[key] = serialize(value.value)

proc nullable_string(node: JsonNode; key: string): NullableOption[string] =
  if not node.contains(key):
    return NullableOption[string](state: nos_none)
  if node[key].kind == JNull:
    return NullableOption[string](state: nos_null)
  NullableOption[string](state: nos_value, value: node[key].getStr)

proc nullable_bool(node: JsonNode; key: string): NullableOption[bool] =
  if not node.contains(key):
    return NullableOption[bool](state: nos_none)
  if node[key].kind == JNull:
    return NullableOption[bool](state: nos_null)
  NullableOption[bool](state: nos_value, value: node[key].getBool)

proc nullable_strings(node: JsonNode; key: string): NullableOption[seq[string]] =
  if not node.contains(key):
    return NullableOption[seq[string]](state: nos_none)
  if node[key].kind == JNull:
    return NullableOption[seq[string]](state: nos_null)
  var values: seq[string] = @[]
  for item in node[key]:
    values.add(item.getStr)
  NullableOption[seq[string]](state: nos_value, value: values)

proc json_node(value: string): JsonNode = %value
proc json_node(value: bool): JsonNode = %value
proc json_node(value: int64): JsonNode = %value
proc json_node(value: AskForApproval): JsonNode =
  case value:
  of apa_untrusted: %"untrusted"
  of apa_on_failure: %"on-failure"
  of apa_on_request: %"on-request"
  of apa_never: %"never"

proc json_node(value: SandboxMode): JsonNode =
  case value:
  of sm_read_only: %"read-only"
  of sm_workspace_write: %"workspace-write"
  of sm_danger_full_access: %"danger-full-access"

proc json_node(value: Personality): JsonNode =
  case value:
  of p_none: %"none"
  of p_friendly: %"friendly"
  of p_pragmatic: %"pragmatic"

proc json_node(value: ReasoningEffort): JsonNode =
  case value:
  of re_minimal: %"minimal"
  of re_low: %"low"
  of re_medium: %"medium"
  of re_high: %"high"
  of re_xhigh: %"xhigh"

proc json_node(value: RequestId): JsonNode =
  case value.kind:
  of rid_string: %value.string_value
  of rid_integer: %value.integer_value

proc request_id_key*(value: RequestId): string =
  case value.kind:
  of rid_string: "s:" & value.string_value
  of rid_integer: "i:" & $value.integer_value

proc `==`(left, right: RequestId): bool =
  if left.kind != right.kind:
    return false
  case left.kind:
  of rid_string:
    left.string_value == right.string_value
  of rid_integer:
    left.integer_value == right.integer_value

proc json_node(value: seq[string]): JsonNode =
  result = newJArray()
  for item in value:
    result.add(%item)

proc serialize_dynamic_tool_spec(value: DynamicToolSpec): JsonNode =
  result = newJObject()
  add_extra_fields(result, value.extra_fields)
  result["type"] = %"function"
  result["name"] = %value.name
  result["description"] = %value.description
  result["inputSchema"] = value.input_schema

proc serialize_dynamic_tool_specs(value: seq[DynamicToolSpec]): JsonNode =
  result = newJArray()
  for item in value:
    result.add(serialize_dynamic_tool_spec(item))

proc serialize_dynamic_tool_content_item(value: DynamicToolContentItem): JsonNode =
  result = newJObject()
  case value.kind:
  of dtc_input_text:
    result["type"] = %"inputText"
    result["text"] = %value.text
  of dtc_input_image:
    result["type"] = %"inputImage"
    result["imageUrl"] = %value.image_url
  of dtc_input_audio:
    result["type"] = %"inputAudio"
    result["audioUrl"] = %value.audio_url

proc serialize_dynamic_tool_call_response*(value: DynamicToolCallResponse): JsonNode =
  result = newJObject()
  result["success"] = %value.success
  result["contentItems"] = newJArray()
  for item in value.content_items:
    result["contentItems"].add(serialize_dynamic_tool_content_item(item))

proc parse_ask_for_approval(node: JsonNode): AskForApproval =
  case node.getStr:
  of "untrusted": apa_untrusted
  of "on-failure": apa_on_failure
  of "on-request": apa_on_request
  of "never": apa_never
  else: raise newException(ValueError, "unknown approval policy")

proc parse_sandbox_mode(node: JsonNode): SandboxMode =
  case node.getStr:
  of "read-only": sm_read_only
  of "workspace-write": sm_workspace_write
  of "danger-full-access": sm_danger_full_access
  else: raise newException(ValueError, "unknown sandbox mode")

proc parse_personality(node: JsonNode): Personality =
  case node.getStr:
  of "none": p_none
  of "friendly": p_friendly
  of "pragmatic": p_pragmatic
  else: raise newException(ValueError, "unknown personality")

proc parse_reasoning_effort(node: JsonNode): ReasoningEffort =
  case node.getStr:
  of "minimal": re_minimal
  of "low": re_low
  of "medium": re_medium
  of "high": re_high
  of "xhigh": re_xhigh
  else: raise newException(ValueError, "unknown reasoning effort")

proc parse_turn_status(node: JsonNode): TurnStatus =
  case node.getStr:
  of "inProgress": ts_in_progress
  of "completed": ts_completed
  of "interrupted": ts_interrupted
  of "failed": ts_failed
  else: ts_unknown

proc serialize_initialize_capabilities(value: InitializeCapabilities): JsonNode =
  result = newJObject()
  add_extra_fields(result, value.extra_fields)
  put_nullable_option(result, "experimentalApi", value.experimental_api, json_node)
  put_nullable_option(result, "optOutNotificationMethods", value.opt_out_notification_methods, json_node)

proc parse_initialize_capabilities(node: JsonNode): InitializeCapabilities =
  InitializeCapabilities(
    experimental_api: nullable_bool(node, "experimentalApi"),
    opt_out_notification_methods: nullable_strings(node, "optOutNotificationMethods"),
    extra_fields: extra_fields(node, "experimentalApi", "optOutNotificationMethods")
  )

proc serialize_client_info(info: ClientInfo): JsonNode =
  result = newJObject()
  add_extra_fields(result, info.extra_fields)
  result["name"] = %info.name
  put_nullable_option(result, "title", info.title, json_node)
  result["version"] = %info.version

proc parse_client_info(node: JsonNode): ClientInfo =
  ClientInfo(
    name: node["name"].getStr,
    title: nullable_string(node, "title"),
    version: node["version"].getStr,
    extra_fields: extra_fields(node, "name", "title", "version")
  )

proc serialize_initialize_params(params: InitializeParams): JsonNode =
  result = newJObject()
  add_extra_fields(result, params.extra_fields)
  put_nullable_option(result, "capabilities", params.capabilities, serialize_initialize_capabilities)
  result["clientInfo"] = serialize_client_info(params.client_info)

proc parse_initialize_params(node: JsonNode): InitializeParams =
  var capabilities = NullableOption[InitializeCapabilities](state: nos_none)
  if node.contains("capabilities"):
    if node["capabilities"].kind == JNull:
      capabilities = NullableOption[InitializeCapabilities](state: nos_null)
    else:
      capabilities = NullableOption[InitializeCapabilities](
        state: nos_value,
        value: parse_initialize_capabilities(node["capabilities"])
      )
  InitializeParams(
    capabilities: capabilities,
    client_info: parse_client_info(node["clientInfo"]),
    extra_fields: extra_fields(node, "capabilities", "clientInfo")
  )

proc serialize_config(value: Config): JsonNode = json_object_node(value)

proc parse_config(node: JsonNode): Config = json_object(node)

proc serialize_thread_start_params(params: ThreadStartParams): JsonNode =
  result = newJObject()
  add_extra_fields(result, params.extra_fields)
  put_nullable_option(result, "approvalPolicy", params.approval_policy, json_node)
  put_nullable_option(result, "baseInstructions", params.base_instructions, json_node)
  put_nullable_option(result, "config", params.config, serialize_config)
  put_nullable_option(result, "cwd", params.cwd, json_node)
  put_nullable_option(result, "developerInstructions", params.developer_instructions, json_node)
  put_nullable_option(result, "sandbox", params.sandbox, json_node)
  put_nullable_option(result, "ephemeral", params.ephemeral, json_node)
  put_nullable_option(result, "modelProvider", params.model_provider, json_node)
  put_nullable_option(result, "personality", params.personality, json_node)
  put_nullable_option(result, "model", params.model, json_node)
  put_nullable_option(result, "dynamicTools", params.dynamic_tools, serialize_dynamic_tool_specs)

proc parse_dynamic_tool_spec(node: JsonNode): DynamicToolSpec =
  if node["type"].getStr != "function":
    raise newException(ValueError, "only function dynamic tools are supported")
  DynamicToolSpec(
    name: node["name"].getStr,
    description: node["description"].getStr,
    input_schema: node["inputSchema"],
    extra_fields: extra_fields(node, "type", "name", "description", "inputSchema")
  )

proc parse_dynamic_tool_specs(node: JsonNode): seq[DynamicToolSpec] =
  result = @[]
  for item in node:
    result.add(parse_dynamic_tool_spec(item))

proc nullable_dynamic_tool_specs(node: JsonNode; key: string): NullableOption[seq[DynamicToolSpec]] =
  if not node.contains(key):
    return NullableOption[seq[DynamicToolSpec]](state: nos_none)
  if node[key].kind == JNull:
    return NullableOption[seq[DynamicToolSpec]](state: nos_null)
  NullableOption[seq[DynamicToolSpec]](
    state: nos_value,
    value: parse_dynamic_tool_specs(node[key])
  )

proc parse_thread_start_params(node: JsonNode): ThreadStartParams =
  var approval = NullableOption[AskForApproval](state: nos_none)
  if node.contains("approvalPolicy"):
    if node["approvalPolicy"].kind == JNull:
      approval = NullableOption[AskForApproval](state: nos_null)
    else:
      approval = NullableOption[AskForApproval](state: nos_value, value: parse_ask_for_approval(node["approvalPolicy"]))
  var sandbox = NullableOption[SandboxMode](state: nos_none)
  if node.contains("sandbox"):
    if node["sandbox"].kind == JNull:
      sandbox = NullableOption[SandboxMode](state: nos_null)
    else:
      sandbox = NullableOption[SandboxMode](state: nos_value, value: parse_sandbox_mode(node["sandbox"]))
  var personality = NullableOption[Personality](state: nos_none)
  if node.contains("personality"):
    if node["personality"].kind == JNull:
      personality = NullableOption[Personality](state: nos_null)
    else:
      personality = NullableOption[Personality](state: nos_value, value: parse_personality(node["personality"]))
  var config = NullableOption[Config](state: nos_none)
  if node.contains("config"):
    if node["config"].kind == JNull:
      config = NullableOption[Config](state: nos_null)
    else:
      config = NullableOption[Config](state: nos_value, value: parse_config(node["config"]))
  ThreadStartParams(
    approval_policy: approval,
    base_instructions: nullable_string(node, "baseInstructions"),
    config: config,
    cwd: nullable_string(node, "cwd"),
    developer_instructions: nullable_string(node, "developerInstructions"),
    sandbox: sandbox,
    ephemeral: nullable_bool(node, "ephemeral"),
    model_provider: nullable_string(node, "modelProvider"),
    personality: personality,
    model: nullable_string(node, "model"),
    dynamic_tools: nullable_dynamic_tool_specs(node, "dynamicTools"),
    extra_fields: extra_fields(node, "approvalPolicy", "baseInstructions", "config", "cwd", "developerInstructions", "sandbox", "ephemeral", "modelProvider", "personality", "model", "dynamicTools")
  )

proc serialize_text_input(value: TextInput): JsonNode =
  result = newJObject()
  add_extra_fields(result, value.extra_fields)
  result["type"] = %"text"
  result["text"] = %value.text

proc serialize_turn_start_params(params: TurnStartParams): JsonNode =
  result = newJObject()
  add_extra_fields(result, params.extra_fields)
  result["threadId"] = %params.thread_id
  result["input"] = newJArray()
  result["input"].add(serialize_text_input(TextInput(text: params.text)))
  put_nullable_option(result, "effort", params.effort, json_node)

proc serialize_params(params: Params): JsonNode =
  case params.kind:
  of mk_initialize: serialize_initialize_params(params.initialize)
  of mk_thread_start: serialize_thread_start_params(params.thread_start)
  of mk_turn_start: serialize_turn_start_params(params.turn_start)

proc serialize_notification_params(params: NotificationParams): JsonNode =
  result = newJObject()
  add_extra_fields(result, params.extra_fields)

proc serialize_message*(message: Message): JsonNode =
  result = newJObject()
  case message.kind:
  of mk_request:
    add_extra_fields(result, message.request.extra_fields)
    result["id"] = json_node(message.request.id)
    case message.request.kind:
    of mk_initialize: result["method"] = %"initialize"
    of mk_thread_start: result["method"] = %"thread/start"
    of mk_turn_start: result["method"] = %"turn/start"
    result["params"] = serialize_params(message.request.params)
  of mk_server_request:
    raise newException(ValueError, "server requests are not client-sendable")
  of mk_server_response:
    add_extra_fields(result, message.server_response.extra_fields)
    result["id"] = json_node(message.server_response.id)
    if message.server_response.result.isSome:
      result["result"] = message.server_response.result.get
    elif message.server_response.error.isSome:
      let error = message.server_response.error.get
      result["error"] = newJObject()
      add_extra_fields(result["error"], error.extra_fields)
      result["error"]["code"] = %error.code
      result["error"]["message"] = %error.message
    else:
      raise newException(ValueError, "server response needs result or error")
  of mk_success:
    add_extra_fields(result, message.success.extra_fields)
    result["id"] = json_node(message.success.id)
    result["result"] = message.success.raw_result
  of mk_error:
    result["id"] = json_node(message.error.id)
    result["error"] = newJObject()
    add_extra_fields(result["error"], message.error.extra_fields)
    result["error"]["code"] = %message.error.code
    result["error"]["message"] = %message.error.message
  of mk_notification:
    add_extra_fields(result, message.notification.extra_fields)
    case message.notification.kind:
    of nk_initialized:
      result["method"] = %"initialized"
      result["params"] = serialize_notification_params(message.notification.params)
    else:
      raise newException(ValueError, "only initialized notification is client-sendable")

proc server_request_kind*(method_name: string): ServerRequestKind =
  case method_name:
  of "item/commandExecution/requestApproval": sr_command_execution_approval
  of "item/fileChange/requestApproval": sr_file_change_approval
  of "item/tool/requestUserInput": sr_tool_user_input
  of "item/tool/call": sr_tool_call
  of "account/chatgptAuthTokens/refresh": sr_auth_tokens_refresh
  of "applyPatchApproval": sr_apply_patch_approval
  of "execCommandApproval": sr_exec_command_approval
  else: sr_unknown

proc server_request_method*(kind: ServerRequestKind): string =
  case kind:
  of sr_command_execution_approval: "item/commandExecution/requestApproval"
  of sr_file_change_approval: "item/fileChange/requestApproval"
  of sr_tool_user_input: "item/tool/requestUserInput"
  of sr_tool_call: "item/tool/call"
  of sr_auth_tokens_refresh: "account/chatgptAuthTokens/refresh"
  of sr_apply_patch_approval: "applyPatchApproval"
  of sr_exec_command_approval: "execCommandApproval"
  of sr_unknown: ""

proc is_conversation_server_request*(kind: ServerRequestKind): bool =
  kind in {
    sr_command_execution_approval,
    sr_file_change_approval,
    sr_tool_user_input,
    sr_tool_call
  }

proc is_conversation_notification*(kind: NotificationKind): bool =
  kind in {
    nk_thread_started,
    nk_thread_token_usage_updated,
    nk_turn_started,
    nk_turn_completed,
    nk_turn_diff_updated,
    nk_turn_plan_updated,
    nk_item_started,
    nk_item_completed,
    nk_agent_message_delta,
    nk_plan_delta,
    nk_command_execution_output_delta,
    nk_terminal_interaction,
    nk_file_change_output_delta,
    nk_mcp_tool_call_progress,
    nk_reasoning_summary_text_delta,
    nk_reasoning_summary_part_added,
    nk_thread_compacted,
    nk_model_rerouted,
    nk_error
  }

proc is_suppressed_notification*(method_name: string): bool =
  method_name == "item/reasoning/textDelta"

proc unquote_diff_path(value: string): string =
  result = value.strip
  if result.len >= 2 and result[0] == '"' and result[^1] == '"':
    try:
      let parsed = parseJson(result)
      if parsed.kind == JString:
        return parsed.getStr
    except CatchableError:
      discard
    result = result[1 .. ^2]

proc diff_path(value: string; prefix: string): string =
  result = unquote_diff_path(value)
  if result == "/dev/null":
    result.setLen(0)
    return
  if result.startsWith(prefix & "/"):
    result = result[(prefix.len + 1) .. ^1]

proc diff_summary*(diff: string): JsonNode =
  var files = newJArray()
  var current_path = ""
  var current_added = 0
  var current_removed = 0
  var have_file = false
  var have_headers = false
  var in_hunk = false
  var total_added = 0
  var total_removed = 0

  proc flush_file() =
    if not have_file:
      return
    let file = newJObject()
    file["path"] = %current_path
    file["added"] = %current_added
    file["removed"] = %current_removed
    files.add(file)
    total_added += current_added
    total_removed += current_removed
    current_path.setLen(0)
    current_added = 0
    current_removed = 0
    have_file = false
    have_headers = false
    in_hunk = false

  for line in diff.splitLines:
    if line.startsWith("diff --git "):
      flush_file()
      let parts = line.splitWhitespace
      if parts.len >= 4:
        if not parts[3].startsWith("\"") and not parts[3].endsWith("\""):
          current_path = diff_path(parts[3], "b")
      have_file = true
    elif not in_hunk and line.startsWith("rename to "):
      current_path = diff_path(line[10 .. ^1], "b")
      have_file = true
    elif not in_hunk and line.startsWith("Binary files "):
      let body = line[13 .. ^1]
      let separator = body.rfind(" and ")
      if separator >= 0:
        let source = body[0 ..< separator].strip
        var target = body[(separator + 5) .. ^1].strip
        if target.endsWith(" differ"):
          target = target[0 ..< target.len - 7]
        current_path = diff_path(target, "b")
        if current_path.len == 0:
          current_path = diff_path(source, "a")
        have_file = true
    elif line.startsWith("@@ "):
      in_hunk = true
    elif not in_hunk and line.startsWith("--- "):
      if have_headers:
        flush_file()
      current_path = diff_path(line[4 .. ^1], "a")
      have_file = true
      have_headers = true
    elif not in_hunk and line.startsWith("+++ "):
      let path = diff_path(line[4 .. ^1], "b")
      if path.len > 0:
        current_path = path
      have_file = true
      have_headers = true
    elif in_hunk and line.startsWith("+"):
      inc current_added
    elif in_hunk and line.startsWith("-"):
      inc current_removed
  flush_file()

  result = newJObject()
  result["files"] = files
  result["added"] = %total_added
  result["removed"] = %total_removed

proc diff_summary_json*(diff: string): string =
  $diff_summary(diff)

proc notification_payload_json*(notification: Notification): string =
  let params = notification.params.raw_params
  if notification.kind == nk_turn_diff_updated:
    let sanitized = newJObject()
    if params.contains("threadId"):
      sanitized["threadId"] = params["threadId"]
    if params.contains("turnId"):
      sanitized["turnId"] = params["turnId"]
    if params.contains("diff"):
      sanitized["summary"] = diff_summary(params["diff"].getStr)
    return $sanitized

  if notification.kind == nk_file_change_output_delta:
    let sanitized = newJObject()
    for key, value in params.pairs:
      if key != "delta":
        sanitized[key] = value
    if params.contains("delta"):
      sanitized["deltaLength"] = %params["delta"].getStr.len
    return $sanitized

  $params

proc parse_request_id(node: JsonNode): RequestId =
  case node.kind:
  of JString: RequestId(kind: rid_string, string_value: node.getStr)
  of JInt: RequestId(kind: rid_integer, integer_value: node.getInt.int64)
  else: raise newException(ValueError, "JSON-RPC id must be string or integer")

proc parse_command_action(node: JsonNode): CommandAction =
  let kind = case node["type"].getStr:
    of "read": cak_read
    of "listFiles": cak_list_files
    of "search": cak_search
    else: cak_unknown
  CommandAction(
    kind: kind,
    command: node["command"].getStr,
    name: nullable_string(node, "name"),
    path: nullable_string(node, "path"),
    query: nullable_string(node, "query"),
    extra_fields: extra_fields(node, "type", "command", "name", "path", "query")
  )

proc parse_parsed_command(node: JsonNode): ParsedCommand =
  let kind = case node["type"].getStr:
    of "read": pck_read
    of "list_files": pck_list_files
    of "search": pck_search
    else: pck_unknown
  ParsedCommand(
    kind: kind,
    cmd: node["cmd"].getStr,
    name: nullable_string(node, "name"),
    path: nullable_string(node, "path"),
    query: nullable_string(node, "query"),
    extra_fields: extra_fields(node, "type", "cmd", "name", "path", "query")
  )

proc parse_command_execution_params(node: JsonNode): CommandExecutionRequestApprovalParams =
  var actions = NullableOption[seq[CommandAction]](state: nos_none)
  if node.contains("commandActions"):
    if node["commandActions"].kind == JNull:
      actions = NullableOption[seq[CommandAction]](state: nos_null)
    else:
      var values: seq[CommandAction] = @[]
      for item in node["commandActions"]:
        values.add(parse_command_action(item))
      actions = NullableOption[seq[CommandAction]](state: nos_value, value: values)
  var amendment = nullable_strings(node, "proposedExecpolicyAmendment")
  CommandExecutionRequestApprovalParams(
    approval_id: nullable_string(node, "approvalId"),
    command: nullable_string(node, "command"),
    command_actions: actions,
    cwd: nullable_string(node, "cwd"),
    item_id: node["itemId"].getStr,
    proposed_execpolicy_amendment: amendment,
    reason: nullable_string(node, "reason"),
    thread_id: node["threadId"].getStr,
    turn_id: node["turnId"].getStr,
    extra_fields: extra_fields(node, "approvalId", "command", "commandActions", "cwd", "itemId", "proposedExecpolicyAmendment", "reason", "threadId", "turnId")
  )

proc parse_file_change_params(node: JsonNode): FileChangeRequestApprovalParams =
  FileChangeRequestApprovalParams(
    grant_root: nullable_string(node, "grantRoot"),
    item_id: node["itemId"].getStr,
    reason: nullable_string(node, "reason"),
    thread_id: node["threadId"].getStr,
    turn_id: node["turnId"].getStr,
    extra_fields: extra_fields(node, "grantRoot", "itemId", "reason", "threadId", "turnId")
  )

proc parse_tool_question(node: JsonNode): ToolRequestUserInputQuestion =
  var options = NullableOption[seq[ToolRequestUserInputOption]](state: nos_none)
  if node.contains("options"):
    if node["options"].kind == JNull:
      options = NullableOption[seq[ToolRequestUserInputOption]](state: nos_null)
    else:
      var values: seq[ToolRequestUserInputOption] = @[]
      for item in node["options"]:
        values.add(ToolRequestUserInputOption(
          description: item["description"].getStr,
          label: item["label"].getStr,
          extra_fields: extra_fields(item, "description", "label")
        ))
      options = NullableOption[seq[ToolRequestUserInputOption]](state: nos_value, value: values)
  ToolRequestUserInputQuestion(
    header: node["header"].getStr,
    id: node["id"].getStr,
    is_other: nullable_bool(node, "isOther"),
    is_secret: nullable_bool(node, "isSecret"),
    options: options,
    question: node["question"].getStr,
    extra_fields: extra_fields(node, "header", "id", "isOther", "isSecret", "options", "question")
  )

proc parse_tool_user_input_params(node: JsonNode): ToolRequestUserInputParams =
  var questions: seq[ToolRequestUserInputQuestion] = @[]
  for item in node["questions"]:
    questions.add(parse_tool_question(item))
  ToolRequestUserInputParams(
    item_id: node["itemId"].getStr,
    questions: questions,
    thread_id: node["threadId"].getStr,
    turn_id: node["turnId"].getStr,
    extra_fields: extra_fields(node, "itemId", "questions", "threadId", "turnId")
  )

proc parse_dynamic_tool_call_params(node: JsonNode): DynamicToolCallParams =
  DynamicToolCallParams(
    arguments: node["arguments"],
    call_id: node["callId"].getStr,
    thread_id: node["threadId"].getStr,
    tool: node["tool"].getStr,
    turn_id: node["turnId"].getStr,
    extra_fields: extra_fields(node, "arguments", "callId", "threadId", "tool", "turnId")
  )

proc parse_auth_refresh_params(node: JsonNode): ChatgptAuthTokensRefreshParams =
  let reason = case node["reason"].getStr:
    of "unauthorized": atrr_unauthorized
    else: atrr_unknown
  ChatgptAuthTokensRefreshParams(
    previous_account_id: nullable_string(node, "previousAccountId"),
    reason: reason,
    extra_fields: extra_fields(node, "previousAccountId", "reason")
  )

proc parse_file_change(node: JsonNode): FileChange =
  let kind = case node["type"].getStr:
    of "add": fck_add
    of "delete": fck_delete
    of "update": fck_update
    else: fck_unknown
  FileChange(
    kind: kind,
    content: nullable_string(node, "content"),
    move_path: nullable_string(node, "move_path"),
    unified_diff: nullable_string(node, "unified_diff"),
    extra_fields: extra_fields(node, "type", "content", "move_path", "unified_diff")
  )

proc parse_apply_patch_params(node: JsonNode): ApplyPatchApprovalParams =
  var changes = initTable[string, FileChange]()
  for path, value in node["fileChanges"].pairs:
    changes[path] = parse_file_change(value)
  ApplyPatchApprovalParams(
    call_id: node["callId"].getStr,
    conversation_id: node["conversationId"].getStr,
    file_changes: changes,
    grant_root: nullable_string(node, "grantRoot"),
    reason: nullable_string(node, "reason"),
    extra_fields: extra_fields(node, "callId", "conversationId", "fileChanges", "grantRoot", "reason")
  )

proc parse_exec_command_params(node: JsonNode): ExecCommandApprovalParams =
  var command: seq[string] = @[]
  for item in node["command"]:
    command.add(item.getStr)
  var parsed: seq[ParsedCommand] = @[]
  for item in node["parsedCmd"]:
    parsed.add(parse_parsed_command(item))
  ExecCommandApprovalParams(
    approval_id: nullable_string(node, "approvalId"),
    call_id: node["callId"].getStr,
    command: command,
    conversation_id: node["conversationId"].getStr,
    cwd: node["cwd"].getStr,
    parsed_cmd: parsed,
    reason: nullable_string(node, "reason"),
    extra_fields: extra_fields(node, "approvalId", "callId", "command", "conversationId", "cwd", "parsedCmd", "reason")
  )

proc parse_server_request_params(kind: ServerRequestKind; node: JsonNode): ServerRequestParams =
  case kind:
  of sr_command_execution_approval:
    ServerRequestParams(kind: kind, command_execution_approval: parse_command_execution_params(node))
  of sr_file_change_approval:
    ServerRequestParams(kind: kind, file_change_approval: parse_file_change_params(node))
  of sr_tool_user_input:
    ServerRequestParams(kind: kind, tool_user_input: parse_tool_user_input_params(node))
  of sr_tool_call:
    ServerRequestParams(kind: kind, tool_call: parse_dynamic_tool_call_params(node))
  of sr_auth_tokens_refresh:
    ServerRequestParams(kind: kind, auth_tokens_refresh: parse_auth_refresh_params(node))
  of sr_apply_patch_approval:
    ServerRequestParams(kind: kind, apply_patch_approval: parse_apply_patch_params(node))
  of sr_exec_command_approval:
    ServerRequestParams(kind: kind, exec_command_approval: parse_exec_command_params(node))
  of sr_unknown:
    ServerRequestParams(kind: kind, unknown: node)

proc parse_thread_status(node: JsonNode; flags: var set[ActiveFlag]): ThreadStatusKind =
  flags = {}
  case node["type"].getStr:
  of "idle": tsk_idle
  of "active":
    if node.contains("activeFlags"):
      for flag in node["activeFlags"]:
        case flag.getStr:
        of "waitingOnApproval": flags.incl(af_waiting_on_approval)
        of "waitingOnUserInput": flags.incl(af_waiting_on_user_input)
        else: discard
    tsk_active
  of "systemError": tsk_system_error
  of "notLoaded": tsk_not_loaded
  else: tsk_unknown

proc parse_notification(node: JsonNode): Notification =
  let method_name = node["method"].getStr
  var params = new_notification_params()
  let wire_params = if node.contains("params"): node["params"] else: newJObject()
  params.raw_params = wire_params
  case method_name:
  of "initialized":
    result.kind = nk_initialized
  of "thread/started":
    result.kind = nk_thread_started
    params.thread_id = Nullable[string](has_value: true, value: wire_params["thread"]["id"].getStr)
    params.thread_extra_fields = extra_fields(wire_params["thread"], "id")
    params.extra_fields = extra_fields(wire_params, "thread")
  of "thread/tokenUsage/updated":
    result.kind = nk_thread_token_usage_updated
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "tokenUsage")
  of "turn/started":
    result.kind = nk_turn_started
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turn"]["id"].getStr)
    params.turn_status = some(parse_turn_status(wire_params["turn"]["status"]))
    params.turn_extra_fields = extra_fields(wire_params["turn"], "id", "status")
    params.extra_fields = extra_fields(wire_params, "threadId", "turn")
  of "turn/completed":
    result.kind = nk_turn_completed
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turn"]["id"].getStr)
    params.turn_status = some(parse_turn_status(wire_params["turn"]["status"]))
    if wire_params["turn"].contains("error") and wire_params["turn"]["error"].kind != JNull:
      params.error_message = some(wire_params["turn"]["error"]["message"].getStr)
    params.turn_extra_fields = extra_fields(wire_params["turn"], "id", "status", "error")
    params.extra_fields = extra_fields(wire_params, "threadId", "turn")
  of "turn/diff/updated":
    result.kind = nk_turn_diff_updated
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "diff")
  of "turn/plan/updated":
    result.kind = nk_turn_plan_updated
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "explanation", "plan")
  of "item/started":
    result.kind = nk_item_started
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.item_id = some(wire_params["item"]["id"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "item")
  of "item/completed":
    result.kind = nk_item_completed
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.item_id = some(wire_params["item"]["id"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "item")
  of "item/agentMessage/delta":
    result.kind = nk_agent_message_delta
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.item_id = some(wire_params["itemId"].getStr)
    params.delta = some(wire_params["delta"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "itemId", "delta")
  of "item/plan/delta":
    result.kind = nk_plan_delta
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.item_id = some(wire_params["itemId"].getStr)
    params.delta = some(wire_params["delta"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "itemId", "delta")
  of "item/commandExecution/outputDelta":
    result.kind = nk_command_execution_output_delta
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.item_id = some(wire_params["itemId"].getStr)
    params.delta = some(wire_params["delta"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "itemId", "delta")
  of "item/commandExecution/terminalInteraction":
    result.kind = nk_terminal_interaction
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.item_id = some(wire_params["itemId"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "itemId", "processId", "stdin")
  of "item/fileChange/outputDelta":
    result.kind = nk_file_change_output_delta
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.item_id = some(wire_params["itemId"].getStr)
    params.delta = some(wire_params["delta"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "itemId", "delta")
  of "item/mcpToolCall/progress":
    result.kind = nk_mcp_tool_call_progress
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.item_id = some(wire_params["itemId"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "itemId", "message")
  of "item/reasoning/summaryTextDelta":
    result.kind = nk_reasoning_summary_text_delta
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.item_id = some(wire_params["itemId"].getStr)
    params.summary_index = some(wire_params["summaryIndex"].getInt)
    params.delta = some(wire_params["delta"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "itemId", "summaryIndex", "delta")
  of "item/reasoning/summaryPartAdded":
    result.kind = nk_reasoning_summary_part_added
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.item_id = some(wire_params["itemId"].getStr)
    params.summary_index = some(wire_params["summaryIndex"].getInt)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "itemId", "summaryIndex")
  of "item/reasoning/textDelta":
    result.kind = nk_unknown
  of "thread/compacted":
    result.kind = nk_thread_compacted
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId")
  of "model/rerouted":
    result.kind = nk_model_rerouted
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "fromModel", "toModel", "reason")
  of "thread/status/changed":
    result.kind = nk_thread_status_changed
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    var flags: set[ActiveFlag]
    params.thread_status = some(parse_thread_status(wire_params["status"], flags))
    params.active_flags = flags
    params.extra_fields = extra_fields(wire_params, "threadId", "status")
  of "thread/closed":
    result.kind = nk_thread_closed
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId")
  of "error":
    result.kind = nk_error
    if wire_params.contains("threadId"):
      params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    if wire_params.contains("turnId"):
      params.turn_id = some(wire_params["turnId"].getStr)
    if wire_params.contains("error"):
      params.error_message = some(wire_params["error"]["message"].getStr)
    if wire_params.contains("willRetry"):
      params.will_retry = some(wire_params["willRetry"].getBool)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "error", "willRetry")
  else:
    result.kind = nk_unknown
    if wire_params.kind == JObject:
      params.extra_fields = json_object(wire_params)
  result.method_name = method_name
  result.params = params
  result.extra_fields = extra_fields(node, "method", "params")

proc parse_server_request(node: JsonNode): ServerRequest =
  let method_name = node["method"].getStr
  let kind = server_request_kind(method_name)
  let wire_params = if node.contains("params"): node["params"] else: newJObject()
  ServerRequest(
    id: parse_request_id(node["id"]),
    kind: kind,
    method_name: method_name,
    params_json: $wire_params,
    params: parse_server_request_params(kind, wire_params),
    extra_fields: extra_fields(node, "id", "method", "params")
  )

proc parse_message*(node: JsonNode; pending: var seq[Message]): Message =
  if node.contains("id"):
    if node.contains("method"):
      return Message(kind: mk_server_request, server_request: parse_server_request(node))

    if not node.contains("result") and not node.contains("error"):
      raise newException(ValueError, "JSON-RPC message with id has neither method, result, nor error")

    let id = parse_request_id(node["id"])
    var request_kind = mk_initialize
    var found = false
    for i in 0 ..< pending.len:
      if pending[i].kind == mk_request and pending[i].request.id == id:
        request_kind = pending[i].request.kind
        pending.del(i)
        found = true
        break
    if not found:
      raise newException(Defect, "couldn't find matching request with id=" & request_id_key(id))

    if node.contains("result"):
      let raw_result = node["result"]
      case request_kind:
      of mk_initialize:
        result = Message(
          kind: mk_success,
          success: Success(
            id: id,
            result: ResponseResult(kind: mk_initialize),
            raw_result: raw_result,
            extra_fields: extra_fields(node, "id", "result")
          )
        )
      of mk_thread_start:
        result = Message(
          kind: mk_success,
          success: Success(
            id: id,
            result: ResponseResult(
              kind: mk_thread_start,
              thread_id: raw_result["thread"]["id"].getStr,
              thread_extra_fields: extra_fields(raw_result["thread"], "id")
            ),
            raw_result: raw_result,
            extra_fields: extra_fields(node, "id", "result")
          )
        )
      of mk_turn_start:
        result = Message(
          kind: mk_success,
          success: Success(
            id: id,
            result: ResponseResult(
              kind: mk_turn_start,
              turn_id: raw_result["turn"]["id"].getStr,
              turn_status: parse_turn_status(raw_result["turn"]["status"]),
              turn_extra_fields: extra_fields(raw_result["turn"], "id", "status")
            ),
            raw_result: raw_result,
            extra_fields: extra_fields(node, "id", "result")
          )
        )
    else:
      result = Message(
        kind: mk_error,
        error: Error(
          id: id,
          code: node["error"]["code"].getInt.int64,
          message: node["error"]["message"].getStr,
          extra_fields: extra_fields(node["error"], "code", "message")
        )
      )
  elif node.contains("method"):
    result = Message(kind: mk_notification, notification: parse_notification(node))
  else:
    raise newException(ValueError, "JSON-RPC message has neither id nor method")
