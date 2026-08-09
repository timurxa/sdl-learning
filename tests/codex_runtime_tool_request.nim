import std/[json, tables]
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
deallocShared(runtime)
