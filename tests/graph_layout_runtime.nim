import ../src/graph_ui
import ../src/clay

proc nodes_overlap(left, right: GraphNode): bool =
  left.screen_position.x < right.screen_position.x + right.size.width and
    right.screen_position.x < left.screen_position.x + left.size.width and
    left.screen_position.y < right.screen_position.y + right.size.height and
    right.screen_position.y < left.screen_position.y + left.size.height

proc settle(solver: var GraphLayoutSolver; nodes: var seq[GraphNode]) =
  var frame_count = 0
  while solver.step_graph_layout(1'f32 / 60'f32):
    solver.apply_graph_layout(nodes)
    inc frame_count
    doAssert frame_count < 32
  solver.apply_graph_layout(nodes)

var nodes = @[
  GraphNode(stable_id: 1, screen_position: vector2(0, 0), size: dimensions(24, 24)),
  GraphNode(stable_id: 2, screen_position: vector2(120, 60), size: dimensions(24, 24)),
  GraphNode(stable_id: 3, screen_position: vector2(120, -60), size: dimensions(24, 24)),
  GraphNode(stable_id: 4, screen_position: vector2(240, 0), size: dimensions(24, 24))]
let diamond_edges = @[
  GraphLayoutEdge(start_node_id: 1, end_node_id: 2),
  GraphLayoutEdge(start_node_id: 1, end_node_id: 3),
  GraphLayoutEdge(start_node_id: 2, end_node_id: 4),
  GraphLayoutEdge(start_node_id: 3, end_node_id: 4)]

var solver = GraphLayoutSolver()
var config = default_graph_layout_config()
config.transition_seconds = 0
doAssert solver.begin_graph_layout(nodes, diamond_edges, config)
settle(solver, nodes)
doAssert solver.status == graph_layout_complete
doAssert nodes[0].screen_position.x < nodes[1].screen_position.x
doAssert nodes[0].screen_position.x < nodes[2].screen_position.x
doAssert nodes[1].screen_position.x < nodes[3].screen_position.x
doAssert nodes[2].screen_position.x < nodes[3].screen_position.x
for left_index in 0 ..< nodes.len:
  for right_index in left_index + 1 ..< nodes.len:
    doAssert not nodes_overlap(nodes[left_index], nodes[right_index])

nodes.setLen(4)
doAssert solver.begin_graph_layout(nodes, diamond_edges, config)
settle(solver, nodes)
doAssert solver.positions.len == 4
for left_index in 0 ..< nodes.len:
  for right_index in left_index + 1 ..< nodes.len:
    doAssert not nodes_overlap(nodes[left_index], nodes[right_index])

var crossing_nodes = @[
  GraphNode(stable_id: 1, screen_position: vector2(0, 0), size: dimensions(24, 24)),
  GraphNode(stable_id: 2, screen_position: vector2(0, 60), size: dimensions(24, 24)),
  GraphNode(stable_id: 3, screen_position: vector2(120, 0), size: dimensions(24, 24)),
  GraphNode(stable_id: 4, screen_position: vector2(120, 60), size: dimensions(24, 24))]
let crossing_edges = @[
  GraphLayoutEdge(start_node_id: 1, end_node_id: 4),
  GraphLayoutEdge(start_node_id: 2, end_node_id: 3)]
var crossing_solver = GraphLayoutSolver()
doAssert crossing_solver.begin_graph_layout(crossing_nodes, crossing_edges, config)
settle(crossing_solver, crossing_nodes)
doAssert crossing_nodes[3].screen_position.y < crossing_nodes[2].screen_position.y

var animated_nodes = @[
  GraphNode(stable_id: 1, screen_position: vector2(0, 0), size: dimensions(24, 24)),
  GraphNode(stable_id: 2, screen_position: vector2(0, 60), size: dimensions(24, 24)),
  GraphNode(stable_id: 3, screen_position: vector2(120, 0), size: dimensions(24, 24)),
  GraphNode(stable_id: 4, screen_position: vector2(120, 60), size: dimensions(24, 24))]
var animated_config = default_graph_layout_config()
animated_config.crossing_sweeps = 2
var animated_solver = GraphLayoutSolver()
doAssert animated_solver.begin_graph_layout(
  animated_nodes, crossing_edges, animated_config)
discard animated_solver.step_graph_layout(1'f32 / 60'f32)
animated_solver.apply_graph_layout(animated_nodes)
let live_position = animated_solver.positions[0]
animated_nodes.add(GraphNode(
  stable_id: 5,
  screen_position: vector2(120, 120),
  size: dimensions(24, 24)))
let animated_changed_edges = @[
  crossing_edges[0],
  crossing_edges[1],
  GraphLayoutEdge(start_node_id: 2, end_node_id: 5)]
doAssert animated_solver.begin_graph_layout(
  animated_nodes, animated_changed_edges, animated_config)
doAssert animated_solver.positions[0] == live_position
for frame in 0 ..< 12:
  discard animated_solver.step_graph_layout(1'f32 / 60'f32)
  animated_solver.apply_graph_layout(animated_nodes)
  for left_index in 0 ..< animated_nodes.len:
    for right_index in left_index + 1 ..< animated_nodes.len:
      doAssert not nodes_overlap(animated_nodes[left_index], animated_nodes[right_index])

let old_position = nodes[3].screen_position
nodes.add(GraphNode(
  stable_id: 5,
  screen_position: vector2(120, 120),
  size: dimensions(24, 24)))
let changed_edges = @[
  GraphLayoutEdge(start_node_id: 1, end_node_id: 2),
  GraphLayoutEdge(start_node_id: 1, end_node_id: 3),
  GraphLayoutEdge(start_node_id: 2, end_node_id: 4),
  GraphLayoutEdge(start_node_id: 3, end_node_id: 4),
  GraphLayoutEdge(start_node_id: 2, end_node_id: 5)]
doAssert solver.begin_graph_layout(nodes, changed_edges, config)
settle(solver, nodes)
doAssert nodes[3].screen_position == old_position
doAssert solver.positions.len == nodes.len
for left_index in 0 ..< nodes.len:
  for right_index in left_index + 1 ..< nodes.len:
    doAssert not nodes_overlap(nodes[left_index], nodes[right_index])

var invalid_solver = GraphLayoutSolver()
let invalid_nodes = @[
  GraphNode(stable_id: 1, size: dimensions(24, 24)),
  GraphNode(stable_id: 2, size: dimensions(24, 24))]
let invalid_edges = @[
  GraphLayoutEdge(start_node_id: 1, end_node_id: 2),
  GraphLayoutEdge(start_node_id: 2, end_node_id: 1)]
doAssert not invalid_solver.begin_graph_layout(invalid_nodes, invalid_edges)
let preserved_position = nodes[0].screen_position
doAssert not solver.begin_graph_layout(nodes, invalid_edges, config)
doAssert solver.status == graph_layout_complete
doAssert solver.positions[0] == preserved_position

for edge_mask in 0 ..< (1 shl 10):
  var generated_nodes = newSeq[GraphNode](5)
  for node_index in 0 ..< generated_nodes.len:
    generated_nodes[node_index] = GraphNode(
      stable_id: uint32(10 + node_index),
      screen_position: vector2(float32(node_index * 70),
        float32((node_index mod 2) * 55)),
      size: dimensions(18 + node_index, 18 + node_index))
  var generated_edges = newSeq[GraphLayoutEdge](0)
  var bit = 0
  for start_index in 0 ..< generated_nodes.len:
    for end_index in start_index + 1 ..< generated_nodes.len:
      if (edge_mask and (1 shl bit)) != 0:
        generated_edges.add(GraphLayoutEdge(
          start_node_id: uint32(10 + start_index),
          end_node_id: uint32(10 + end_index)))
      inc bit
  var generated_solver = GraphLayoutSolver()
  doAssert generated_solver.begin_graph_layout(
    generated_nodes, generated_edges, config)
  settle(generated_solver, generated_nodes)
  for left_index in 0 ..< generated_nodes.len:
    for right_index in left_index + 1 ..< generated_nodes.len:
      doAssert not nodes_overlap(
        generated_nodes[left_index], generated_nodes[right_index])
  for edge in generated_edges:
    var start_index = 0
    var end_index = 0
    for node_index, node in generated_nodes:
      if node.stable_id == edge.start_node_id:
        start_index = node_index
      if node.stable_id == edge.end_node_id:
        end_index = node_index
    doAssert generated_nodes[start_index].screen_position.x <
      generated_nodes[end_index].screen_position.x
