import std/[json, options, strutils]
import ../src/codex_json

var pending: seq[Message] = @[]
let message = parse_message(parseJson(
  """{"method":"thread/newNotification","params":["alpha",{"value":true}]}"""),
  pending)

doAssert message.kind == mk_notification
doAssert message.notification.kind == nk_unknown
doAssert message.notification.params.raw_params.kind == JArray
doAssert message.notification.params.raw_params.len == 2

proc parse_notification_fixture(value: string): Notification =
  var pending: seq[Message] = @[]
  let parsed = parse_message(parseJson(value), pending)
  doAssert parsed.kind == mk_notification
  parsed.notification

let command_output = parse_notification_fixture(
  """{"method":"item/commandExecution/outputDelta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-1","delta":"hello\n"}}""")
doAssert command_output.kind == nk_command_execution_output_delta
doAssert command_output.params.thread_id.value == "thread-1"
doAssert command_output.params.turn_id.get == "turn-1"
doAssert command_output.params.item_id.get == "item-1"
doAssert command_output.params.delta.get == "hello\n"
doAssert command_output.kind.is_conversation_notification

let reasoning = parse_notification_fixture(
  """{"method":"item/reasoning/summaryTextDelta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-2","summaryIndex":0,"delta":"summary"}}""")
doAssert reasoning.kind == nk_reasoning_summary_text_delta
doAssert reasoning.params.summary_index.get == 0

let diff = """diff --git a/src/one.nim b/src/one.nim
--- a/src/one.nim
+++ b/src/one.nim
@@ -1,3 +1,4 @@
 old
-removed
+added
+new
--- removed-header
+++ added-header
diff --git a/src/two.nim b/src/two.nim
--- /dev/null
+++ b/src/two.nim
@@ -0,0 +1 @@
+created
"""
let diff_node = newJObject()
diff_node["method"] = %"turn/diff/updated"
diff_node["params"] = newJObject()
diff_node["params"]["threadId"] = %"thread-1"
diff_node["params"]["turnId"] = %"turn-1"
diff_node["params"]["diff"] = %diff
let diff_notification = parse_notification_fixture($diff_node)
let sanitized_diff = parseJson(notification_payload_json(diff_notification))
let summary = sanitized_diff["summary"]
doAssert summary["added"].getInt == 4
doAssert summary["removed"].getInt == 2
doAssert summary["files"][0]["path"].getStr == "src/one.nim"
doAssert summary["files"][0]["added"].getInt == 3
doAssert summary["files"][0]["removed"].getInt == 2
doAssert summary["files"][1]["path"].getStr == "src/two.nim"
doAssert summary["files"][1]["added"].getInt == 1
doAssert ($sanitized_diff).find("old") < 0

let metadata_diff = parseJson(diff_summary_json(
  """diff --git a/old.txt b/new.txt
similarity index 100%
rename from old.txt
rename to new.txt
diff --git a/image.png b/image.png
Binary files a/image.png and b/image.png differ
diff --git a/deleted.png /dev/null
Binary files a/deleted.png and /dev/null differ
"""))
doAssert metadata_diff["files"].len == 3
doAssert metadata_diff["files"][0]["path"].getStr == "new.txt"
doAssert metadata_diff["files"][1]["path"].getStr == "image.png"
doAssert metadata_diff["files"][2]["path"].getStr == "deleted.png"
