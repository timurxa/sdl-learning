import std/[json, options, tables]
import ../src/codex_json
import ../src/codex_runtime

let request_id = RequestId(kind: rid_integer, integer_value: 7)
let request = ServerRequest(
  id: request_id,
  kind: sr_tool_call,
  method_name: "item/tool/call",
  params_json: "{}",
  params: ServerRequestParams(
    kind: sr_tool_call,
    tool_call: DynamicToolCallParams(
      arguments: newJObject(),
      call_id: "call",
      thread_id: "thread",
      tool: "finish_node",
      turn_id: "turn")))

var runtime = cast[ptr CodexRuntime](allocShared0(sizeof(CodexRuntime)))
runtime.state = new_runtime_state()
runtime.handle_message(Message(kind: mk_server_request, server_request: request))
doAssert runtime.server_requests.hasKey(request_id_key(request_id))
runtime.state.server_requests.clear()

let user_input_request_id = RequestId(kind: rid_integer, integer_value: 8)
let user_input_request = ServerRequest(
  id: user_input_request_id,
  kind: sr_tool_user_input,
  method_name: "item/tool/requestUserInput",
  params_json: "{}",
  params: ServerRequestParams(
    kind: sr_tool_user_input,
    tool_user_input: ToolRequestUserInputParams(
      item_id: "item",
      questions: @[],
      thread_id: "thread",
      turn_id: "turn")))
runtime.handle_message(Message(
  kind: mk_server_request,
  server_request: user_input_request))
doAssert runtime.server_requests.hasKey(request_id_key(user_input_request_id))
runtime.state.agents["agent"] = Agent(
  id: "agent",
  thread_id: Nullable[string](has_value: true, value: "thread"),
  turn_id: none(string),
  state: as_waiting,
  last_error: NullableOption[string](state: nos_none),
  tools: @[])
runtime.state.apply_notification(Notification(
  kind: nk_thread_status_changed,
  params: NotificationParams(
    thread_id: Nullable[string](has_value: true, value: "thread"),
    thread_status: some(tsk_system_error))))
doAssert not runtime.server_requests.hasKey(request_id_key(user_input_request_id))
runtime.state.agents.clear()
var orphan_request = user_input_request
orphan_request.id = RequestId(kind: rid_integer, integer_value: 9)
runtime.handle_message(Message(
  kind: mk_server_request,
  server_request: orphan_request))
doAssert runtime.server_requests.hasKey(request_id_key(orphan_request.id))
runtime.state.apply_notification(Notification(
  kind: nk_thread_status_changed,
  params: NotificationParams(
    thread_id: Nullable[string](has_value: true, value: "thread"),
    thread_status: some(tsk_not_loaded))))
doAssert not runtime.server_requests.hasKey(request_id_key(orphan_request.id))
runtime.state.agents["agent"] = Agent(
  id: "agent",
  thread_id: Nullable[string](has_value: true, value: "thread"),
  turn_id: none(string),
  state: as_waiting,
  last_error: NullableOption[string](state: nos_none),
  tools: @[])
var interrupted_request = user_input_request
interrupted_request.id = RequestId(kind: rid_integer, integer_value: 10)
runtime.handle_message(Message(
  kind: mk_server_request,
  server_request: interrupted_request))
doAssert runtime.server_requests.hasKey(request_id_key(interrupted_request.id))
runtime.state.apply_notification(Notification(
  kind: nk_turn_completed,
  params: NotificationParams(
    thread_id: Nullable[string](has_value: true, value: "thread"),
    turn_status: some(ts_interrupted))))
doAssert not runtime.server_requests.hasKey(request_id_key(interrupted_request.id))
let user_input_response = serialize_user_input_response(@[
  UserInputAnswer(question_id: "question", answer: "answer")])
doAssert user_input_response["answers"]["question"]["answers"][0].getStr ==
  "answer"
runtime.state.server_requests.clear()
deallocShared(runtime)
