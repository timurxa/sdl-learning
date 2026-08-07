import std/json
import ../src/codex_json

var pending: seq[Message] = @[]
let message = parse_message(parseJson(
  """{"method":"thread/newNotification","params":["alpha",{"value":true}]}"""),
  pending)

doAssert message.kind == mk_notification
doAssert message.notification.kind == nk_unknown
doAssert message.notification.params.raw_params.kind == JArray
doAssert message.notification.params.raw_params.len == 2
