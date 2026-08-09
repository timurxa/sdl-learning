import std/[os, times]
import ../src/codex_bridge

var bridge = new_codex_bridge()
bridge.send_node_message(1, "Do nothing")
let deadline = epochTime() + 10.0
var node_one_ready = false
var node_two_ready = false
var requested_node_two = false
while epochTime() < deadline:
  var event: CodexRuntimeEvent
  if bridge.try_receive(event):
    if event.kind == cre_thread_ready and event.node_id == 1:
      node_one_ready = true
      if not requested_node_two:
        bridge.send_node_message(2, "Do nothing")
        requested_node_two = true
    elif event.kind == cre_thread_ready and event.node_id == 2:
      node_two_ready = true
      break
  sleep(20)

deinit_codex_bridge(bridge)
doAssert node_one_ready
doAssert node_two_ready
