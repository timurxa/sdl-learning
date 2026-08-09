import ../src/orchestration

var graph = WorkGraph(nodes: @[
  WorkNode(id: 1, state: pending),
  WorkNode(id: 2, wait_for: @[1], state: pending),
  WorkNode(id: 3, state: pending)
])

doAssert graph.runnable_node_ids() == @[1'u32, 3'u32]

graph.nodes[0].state = running
doAssert graph.complete_node(1)
doAssert graph.nodes[0].state == completed
doAssert graph.runnable_node_ids() == @[2'u32, 3'u32]

graph.nodes[1].state = running
doAssert graph.fail_node(2, "test failure")
doAssert graph.nodes[1].state == failed
doAssert graph.runnable_node_ids() == @[3'u32]
doAssert graph.log_messages == @["NODE 2 FAILED: test failure"]

doAssert not graph.complete_node(2)

graph.outgoing_messages = @[
  WorkGraphMessage(node_id: 3, text: "first"),
  WorkGraphMessage(node_id: 1, text: "second")]
let outgoing_messages = graph.drain_outgoing_messages()
doAssert outgoing_messages.len == 2
doAssert outgoing_messages[0].node_id == 3
doAssert outgoing_messages[0].text == "first"
doAssert outgoing_messages[1].node_id == 1
doAssert outgoing_messages[1].text == "second"
doAssert graph.drain_outgoing_messages().len == 0
