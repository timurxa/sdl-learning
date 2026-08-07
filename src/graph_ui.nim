import std/[algorithm, math, tables]
import clay
import renderer
import sdl
import ui

type
  GraphArrow* = object
    start_node_index*: int
    end_node_index*: int
    use_stable_ids*: bool
    start_node_id*: uint32
    end_node_id*: uint32
    padding*: float32
    color*: ClayColor
    shaft_width*: float32
    head_length*: float32
    head_width*: float32
    z_index*: int16

  GraphNode* = object
    stable_id*: uint32
    screen_position*: ClayVector2
    size*: ClayDimensions
    circle_color*: ClayColor
    z_index*: int16
    title*: string
    detail*: string

  GraphLayoutEdge* = object
    start_node_id*: uint32
    end_node_id*: uint32

  GraphLayoutConfig* = object
    layer_gap*: float32
    node_gap*: float32
    transition_seconds*: float32
    crossing_sweeps*: int

  GraphLayoutStatus* = enum
    graph_layout_idle
    graph_layout_solving
    graph_layout_transitioning
    graph_layout_complete

  GraphLayoutVertex = object
    stable_key: uint64
    real_node_index: int
    layer: int
    old_position: ClayVector2
    size: ClayDimensions

  GraphLayoutLink = object
    start_vertex: int
    end_vertex: int

  GraphLayoutSolver* = object
    config*: GraphLayoutConfig
    status*: GraphLayoutStatus
    positions*: seq[ClayVector2]
    node_ids: seq[uint32]
    node_sizes: seq[ClayDimensions]
    edge_keys: seq[uint64]
    node_layers: seq[int]
    old_positions: seq[ClayVector2]
    target_positions: seq[ClayVector2]
    affected_nodes: seq[bool]
    vertices: seq[GraphLayoutVertex]
    links: seq[GraphLayoutLink]
    direct_links: seq[GraphLayoutLink]
    predecessors: seq[seq[int]]
    successors: seq[seq[int]]
    layers: seq[seq[int]]
    vertex_orders: seq[int]
    affected_layers: seq[bool]
    sweep_index: int
    last_crossings: int

  GraphCanvasConfig* = object
    pan_button*: uint8
    zoom_factor*: float32

  GraphNodeGeometry = object
    screen_bounds: ClayBoundingBox
    circle_origin: ClayVector2
    circle_diameter: float32

  GraphView* = object
    nodes*: seq[GraphNode]
    arrows*: seq[GraphArrow]
    draw_list*: OpaqueDrawList
    selected_node_id*: uint32
    selected_node_valid*: bool
    hovered_node_id*: uint32
    hovered_node_valid*: bool
    canvas_config*: GraphCanvasConfig
    pan*: ClayVector2
    zoom*: float32
    pan_active: bool
    pan_pointer: ClayVector2
    pressed_node_id: uint32
    pressed_node_pointer: ClayVector2
    pressed_node_valid: bool
    viewport_bounds: ClayBoundingBox
    panel_bounds: ClayBoundingBox
    viewport_valid: bool
    panel_valid: bool
    pointer_position: ClayVector2
    pointer_valid: bool
    layout_solver*: GraphLayoutSolver

const
  default_graph_zoom_factor = 1.1'f32
  graph_node_border_width = 3'f32
  graph_node_highlight_width = 4'f32
  graph_node_click_slop = 3'f32
  graph_panel_width_fraction = 1'f32 / 3'f32
  graph_panel_top_padding = 16
  graph_panel_right_padding = 16
  graph_panel_bottom_padding = 16
  graph_panel_host_z_index = 32766'i16
  graph_panel_z_index = 32767'i16

proc default_graph_layout_config*(): GraphLayoutConfig =
  GraphLayoutConfig(
    layer_gap: 72'f32,
    node_gap: 24'f32,
    transition_seconds: 0.18'f32,
    crossing_sweeps: 8)

proc valid_graph_float(value: float32): bool {.inline.}

proc graph_layout_edge_key(edge: GraphLayoutEdge): uint64 {.inline.} =
  (uint64(edge.start_node_id) shl 32) or uint64(edge.end_node_id)

proc graph_layout_center(position: ClayVector2; size: ClayDimensions): ClayVector2 {.inline.} =
  vector2(
    position.x + float32(size.width) / 2'f32,
    position.y + float32(size.height) / 2'f32)

proc graph_layout_vertex_height(vertex: GraphLayoutVertex): float32 {.inline.} =
  float32(vertex.size.height)

proc graph_layout_vertex_width(vertex: GraphLayoutVertex): float32 {.inline.} =
  float32(vertex.size.width)

proc graph_layout_compare_float(left, right: float64): int {.inline.} =
  if left < right - 0.001:
    -1
  elif left > right + 0.001:
    1
  else:
    0

proc graph_layout_compare_initial(
    vertices: seq[GraphLayoutVertex]; left, right: int): int =
  result = graph_layout_compare_float(
    float64(vertices[left].old_position.y),
    float64(vertices[right].old_position.y))
  if result == 0:
    if vertices[left].stable_key < vertices[right].stable_key:
      result = -1
    elif vertices[left].stable_key > vertices[right].stable_key:
      result = 1
    else:
      result = cmp(left, right)

proc graph_layout_rebuild_orders(solver: var GraphLayoutSolver) =
  solver.vertex_orders.setLen(solver.vertices.len)
  for layer in solver.layers:
    for order, vertex in layer:
      solver.vertex_orders[vertex] = order

proc graph_layout_orientation(
    first, second, third: ClayVector2): float64 {.inline.} =
  float64(second.x - first.x) * float64(third.y - first.y) -
    float64(second.y - first.y) * float64(third.x - first.x)

proc graph_layout_segments_cross(
    first_start, first_end, second_start, second_end: ClayVector2): bool =
  let first_orientation = graph_layout_orientation(
    first_start, first_end, second_start)
  let second_orientation = graph_layout_orientation(
    first_start, first_end, second_end)
  let third_orientation = graph_layout_orientation(
    second_start, second_end, first_start)
  let fourth_orientation = graph_layout_orientation(
    second_start, second_end, first_end)
  (first_orientation < 0 and second_orientation > 0 or
    first_orientation > 0 and second_orientation < 0) and
    (third_orientation < 0 and fourth_orientation > 0 or
    third_orientation > 0 and fourth_orientation < 0)

proc graph_layout_count_crossings(solver: GraphLayoutSolver): int =
  for first_index, first_link in solver.direct_links:
    for second_index in first_index + 1 ..< solver.direct_links.len:
      let second_link = solver.direct_links[second_index]
      if first_link.start_vertex == second_link.start_vertex or
          first_link.start_vertex == second_link.end_vertex or
          first_link.end_vertex == second_link.start_vertex or
          first_link.end_vertex == second_link.end_vertex:
        continue
      let first_start = graph_layout_center(
        solver.target_positions[first_link.start_vertex],
        solver.node_sizes[first_link.start_vertex])
      let first_end = graph_layout_center(
        solver.target_positions[first_link.end_vertex],
        solver.node_sizes[first_link.end_vertex])
      let second_start = graph_layout_center(
        solver.target_positions[second_link.start_vertex],
        solver.node_sizes[second_link.start_vertex])
      let second_end = graph_layout_center(
        solver.target_positions[second_link.end_vertex],
        solver.node_sizes[second_link.end_vertex])
      if graph_layout_segments_cross(
          first_start, first_end, second_start, second_end):
        inc result

proc graph_layout_mark_edge_endpoints(
    changed_nodes: var seq[bool]; node_lookup: Table[uint32, int];
    edge_key: uint64) =
  let start_node_id = uint32(edge_key shr 32)
  let end_node_id = uint32(edge_key and 0xffffffff'u64)
  if node_lookup.hasKey(start_node_id):
    changed_nodes[node_lookup[start_node_id]] = true
  if node_lookup.hasKey(end_node_id):
    changed_nodes[node_lookup[end_node_id]] = true

proc graph_layout_resolve_overlaps(solver: var GraphLayoutSolver) =
  for pass in 0 ..< max(solver.positions.len, 1):
    var changed = false
    for left_index in 0 ..< solver.positions.len:
      let left_position = solver.positions[left_index]
      let left_size = solver.node_sizes[left_index]
      for right_index in left_index + 1 ..< solver.positions.len:
        let right_position = solver.positions[right_index]
        let right_size = solver.node_sizes[right_index]
        let overlap_x = min(
          left_position.x + float32(left_size.width),
          right_position.x + float32(right_size.width)) -
          max(left_position.x, right_position.x)
        let overlap_y = min(
          left_position.y + float32(left_size.height),
          right_position.y + float32(right_size.height)) -
          max(left_position.y, right_position.y)
        if overlap_x <= 0 or overlap_y <= 0:
          continue
        let left_center = graph_layout_center(left_position, left_size)
        let right_center = graph_layout_center(right_position, right_size)
        var direction_x = float32(right_center.x - left_center.x)
        var direction_y = float32(right_center.y - left_center.y)
        if direction_x == 0 and direction_y == 0:
          direction_x = if left_index mod 2 == 0: -1'f32 else: 1'f32
        let left_affected = solver.affected_nodes[left_index]
        let right_affected = solver.affected_nodes[right_index]
        if overlap_x <= overlap_y:
          let direction = if direction_x < 0: -1'f32 else: 1'f32
          let separation = overlap_x + 0.01'f32
          if left_affected and not right_affected:
            solver.positions[left_index].x -= separation * direction
          elif right_affected and not left_affected:
            solver.positions[right_index].x += separation * direction
          else:
            solver.positions[left_index].x -= separation / 2'f32 * direction
            solver.positions[right_index].x += separation / 2'f32 * direction
        else:
          let direction = if direction_y < 0: -1'f32 else: 1'f32
          let separation = overlap_y + 0.01'f32
          if left_affected and not right_affected:
            solver.positions[left_index].y -= separation * direction
          elif right_affected and not left_affected:
            solver.positions[right_index].y += separation * direction
          else:
            solver.positions[left_index].y -= separation / 2'f32 * direction
            solver.positions[right_index].y += separation / 2'f32 * direction
        changed = true
    if not changed:
      break

proc graph_layout_mark_changed_nodes(
    node_lookup: Table[uint32, int];
    current_edge_keys: Table[uint64, bool];
    current_nodes: openArray[GraphNode];
    previous_node_ids: seq[uint32];
    previous_node_sizes: seq[ClayDimensions];
    previous_edge_keys: seq[uint64]): seq[bool] =
  result = newSeq[bool](current_nodes.len)
  if previous_node_ids.len == 0:
    for index in 0 ..< result.len:
      result[index] = true
    return

  var previous_nodes = initTable[uint32, int]()
  for index, node_id in previous_node_ids:
    previous_nodes[node_id] = index
  var previous_edges = initTable[uint64, bool]()
  for edge_key in previous_edge_keys:
    previous_edges[edge_key] = true

  for index, node in current_nodes:
    if not previous_nodes.hasKey(node.stable_id):
      result[index] = true
    else:
      let previous_index = previous_nodes[node.stable_id]
      if previous_index >= previous_node_sizes.len or
          previous_node_sizes[previous_index].width != node.size.width or
          previous_node_sizes[previous_index].height != node.size.height:
        result[index] = true

  for edge_key in current_edge_keys.keys:
    if not previous_edges.hasKey(edge_key):
      graph_layout_mark_edge_endpoints(result, node_lookup, edge_key)
  for edge_key in previous_edges.keys:
    if not current_edge_keys.hasKey(edge_key):
      graph_layout_mark_edge_endpoints(result, node_lookup, edge_key)

proc graph_layout_rebuild_target(solver: var GraphLayoutSolver)

proc graph_layout_try_sweep(solver: var GraphLayoutSolver; downward: bool) =
  if solver.layers.len < 2:
    return

  graph_layout_rebuild_orders(solver)
  var previous_layers = newSeq[seq[int]](solver.layers.len)
  for layer_index, layer in solver.layers:
    previous_layers[layer_index] = newSeq[int](layer.len)
    for order, vertex in layer:
      previous_layers[layer_index][order] = vertex

  var layer_index = if downward: 1 else: solver.layers.len - 2
  while (if downward: layer_index < solver.layers.len else: layer_index >= 0):
    if solver.affected_layers[layer_index]:
      let layer = solver.layers[layer_index]
      var scores = newSeq[float64](solver.vertices.len)
      for vertex in layer:
        let neighbors = if downward:
          solver.predecessors[vertex]
        else:
          solver.successors[vertex]
        if neighbors.len == 0:
          scores[vertex] = float64(solver.vertex_orders[vertex])
        else:
          var score = 0'f64
          for neighbor in neighbors:
            score += float64(solver.vertex_orders[neighbor])
          scores[vertex] = score / float64(neighbors.len)

      var candidate = newSeq[int](layer.len)
      for order, vertex in layer:
        candidate[order] = vertex
      let vertices = solver.vertices
      let vertex_orders = solver.vertex_orders
      candidate.sort(proc(left, right: int): int =
        var comparison = graph_layout_compare_float(scores[left], scores[right])
        if comparison == 0:
          comparison = graph_layout_compare_float(
            float64(vertices[left].old_position.y),
            float64(vertices[right].old_position.y))
        if comparison == 0:
          comparison = cmp(vertex_orders[left], vertex_orders[right])
        if comparison == 0:
          comparison = cmp(left, right)
        comparison)
      solver.layers[layer_index] = candidate

    if downward:
      inc layer_index
    else:
      dec layer_index

  graph_layout_rebuild_orders(solver)
  solver.graph_layout_rebuild_target()
  let candidate_crossings = solver.graph_layout_count_crossings()
  if candidate_crossings < solver.last_crossings:
    solver.last_crossings = candidate_crossings
  else:
    solver.layers = previous_layers
    graph_layout_rebuild_orders(solver)
    solver.graph_layout_rebuild_target()

proc graph_layout_rebuild_target(solver: var GraphLayoutSolver) =
  if solver.node_ids.len == 0:
    solver.target_positions.setLen(0)
    return

  var layer_widths = newSeq[float32](solver.layers.len)
  var layer_heights = newSeq[float32](solver.layers.len)
  var candidate_y = newSeq[float32](solver.vertices.len)
  var candidate_lefts = newSeq[float32](solver.layers.len)
  var old_layer_x = newSeq[float64](solver.layers.len)
  var old_layer_x_count = newSeq[int](solver.layers.len)
  var old_center_y = 0'f64
  var candidate_center_y = 0'f64
  var old_center_x = 0'f64
  var candidate_center_x = 0'f64
  var real_node_count = 0

  for layer_index, layer in solver.layers:
    var layer_height = 0'f32
    var layer_width = 0'f32
    for vertex in layer:
      layer_width = max(layer_width, graph_layout_vertex_width(
        solver.vertices[vertex]))
      layer_height += graph_layout_vertex_height(solver.vertices[vertex])
    if layer.len > 1:
      layer_height += float32(layer.len - 1) * solver.config.node_gap
    layer_widths[layer_index] = layer_width
    layer_heights[layer_index] = layer_height

  var max_layer_height = 0'f32
  for layer_height in layer_heights:
    max_layer_height = max(max_layer_height, layer_height)

  for layer_index, layer in solver.layers:
    var y = (max_layer_height - layer_heights[layer_index]) / 2'f32
    for vertex in layer:
      candidate_y[vertex] = y
      y += graph_layout_vertex_height(solver.vertices[vertex]) +
        solver.config.node_gap

  var x = 0'f32
  for layer_index, layer in solver.layers:
    candidate_lefts[layer_index] = x
    x += layer_widths[layer_index] + solver.config.layer_gap

  for vertex_index, vertex in solver.vertices:
    if vertex.real_node_index < 0:
      continue
    let node_index = vertex.real_node_index
    let layer_index = vertex.layer
    let old_center = graph_layout_center(
      solver.old_positions[node_index], solver.node_sizes[node_index])
    let candidate_center = graph_layout_center(
      vector2(
        candidate_lefts[layer_index] +
          (layer_widths[layer_index] - graph_layout_vertex_width(vertex)) / 2'f32,
        candidate_y[vertex_index]),
      vertex.size)
    old_layer_x[layer_index] += float64(old_center.x)
    inc old_layer_x_count[layer_index]
    old_center_y += float64(old_center.y)
    candidate_center_y += float64(candidate_center.y)
    old_center_x += float64(old_center.x)
    candidate_center_x += float64(candidate_center.x)
    inc real_node_count

  if real_node_count > 0:
    let x_offset = float32(
      (old_center_x - candidate_center_x) / float64(real_node_count))
    let y_offset = float32(
      (old_center_y - candidate_center_y) / float64(real_node_count))
    for layer_index in 0 ..< candidate_lefts.len:
      candidate_lefts[layer_index] += x_offset
    for vertex_index in 0 ..< candidate_y.len:
      candidate_y[vertex_index] += y_offset

  var previous_left = 0'f32
  var previous_width = 0'f32
  for layer_index, layer in solver.layers:
    var desired_left = candidate_lefts[layer_index]
    if old_layer_x_count[layer_index] > 0 and
        not solver.affected_layers[layer_index]:
      desired_left = float32(
        old_layer_x[layer_index] / float64(old_layer_x_count[layer_index])) -
        layer_widths[layer_index] / 2'f32
    if layer_index > 0:
      desired_left = max(
        desired_left,
        previous_left + previous_width + solver.config.layer_gap)
    candidate_lefts[layer_index] = desired_left
    previous_left = desired_left
    previous_width = layer_widths[layer_index]

    var previous_y = -high(float32)
    var previous_height = 0'f32
    for vertex in layer:
      var desired_y = candidate_y[vertex]
      if solver.vertices[vertex].real_node_index >= 0:
        let node_index = solver.vertices[vertex].real_node_index
        if not solver.affected_nodes[node_index]:
          desired_y = solver.old_positions[node_index].y
      let minimum_y = previous_y + previous_height + solver.config.node_gap
      if previous_y > -high(float32) / 2'f32:
        desired_y = max(desired_y, minimum_y)
      candidate_y[vertex] = desired_y
      previous_y = desired_y
      previous_height = graph_layout_vertex_height(solver.vertices[vertex])

  solver.target_positions = newSeq[ClayVector2](solver.node_ids.len)
  for vertex_index, vertex in solver.vertices:
    if vertex.real_node_index < 0:
      continue
    let node_index = vertex.real_node_index
    solver.target_positions[node_index] = vector2(
      candidate_lefts[vertex.layer] +
        (layer_widths[vertex.layer] - graph_layout_vertex_width(vertex)) / 2'f32,
      candidate_y[vertex_index])

proc graph_layout_positions_close(solver: GraphLayoutSolver): bool =
  for index in 0 ..< solver.positions.len:
    if abs(float64(solver.positions[index].x - solver.target_positions[index].x)) >
        0.05 or
        abs(float64(solver.positions[index].y - solver.target_positions[index].y)) >
        0.05:
      return false
  true

proc normalize_graph_layout_config(config: GraphLayoutConfig): GraphLayoutConfig =
  result = config
  if result.layer_gap < 0 or not valid_graph_float(result.layer_gap):
    result.layer_gap = 72'f32
  if result.node_gap < 0 or not valid_graph_float(result.node_gap):
    result.node_gap = 24'f32
  if result.transition_seconds < 0 or
      not valid_graph_float(result.transition_seconds):
    result.transition_seconds = 0.18'f32
  if result.crossing_sweeps < 1:
    result.crossing_sweeps = 8

proc begin_graph_layout*(solver: var GraphLayoutSolver;
    nodes: openArray[GraphNode]; edges: openArray[GraphLayoutEdge];
    config: GraphLayoutConfig): bool =
  var node_lookup = initTable[uint32, int]()
  for index, node in nodes:
    if node_lookup.hasKey(node.stable_id) or
        node.size.width < 0 or node.size.height < 0 or
        not valid_graph_float(float32(node.size.width)) or
        not valid_graph_float(float32(node.size.height)) or
        not valid_graph_float(float32(node.screen_position.x)) or
        not valid_graph_float(float32(node.screen_position.y)):
      return false
    node_lookup[node.stable_id] = index

  var ordered_edges = newSeq[GraphLayoutEdge](edges.len)
  for index, edge in edges:
    ordered_edges[index] = edge
  ordered_edges.sort(proc(left, right: GraphLayoutEdge): int =
    if left.start_node_id < right.start_node_id:
      -1
    elif left.start_node_id > right.start_node_id:
      1
    elif left.end_node_id < right.end_node_id:
      -1
    elif left.end_node_id > right.end_node_id:
      1
    else:
      0)

  var current_edge_table = initTable[uint64, bool]()
  var current_edge_keys = newSeq[uint64](ordered_edges.len)
  for index, edge in ordered_edges:
    if edge.start_node_id == edge.end_node_id or
        not node_lookup.hasKey(edge.start_node_id) or
        not node_lookup.hasKey(edge.end_node_id):
      return false
    let edge_key = graph_layout_edge_key(edge)
    if current_edge_table.hasKey(edge_key):
      return false
    current_edge_table[edge_key] = true
    current_edge_keys[index] = edge_key

  var validation_outgoing = newSeq[seq[int]](nodes.len)
  var validation_indegree = newSeq[int](nodes.len)
  for edge in ordered_edges:
    let start_index = node_lookup[edge.start_node_id]
    let end_index = node_lookup[edge.end_node_id]
    validation_outgoing[start_index].add(end_index)
    inc validation_indegree[end_index]
  var validation_queue = newSeq[int](0)
  for index, degree in validation_indegree:
    if degree == 0:
      validation_queue.add(index)
  var validation_head = 0
  var topological_order = newSeq[int](0)
  while validation_head < validation_queue.len:
    let node_index = validation_queue[validation_head]
    inc validation_head
    topological_order.add(node_index)
    for end_index in validation_outgoing[node_index]:
      dec validation_indegree[end_index]
      if validation_indegree[end_index] == 0:
        validation_queue.add(end_index)
  if topological_order.len != nodes.len:
    return false

  let previous_node_ids = solver.node_ids
  let previous_node_sizes = solver.node_sizes
  let previous_node_layers = solver.node_layers
  let previous_positions = solver.positions
  let previous_edge_keys = solver.edge_keys
  let normalized_config = normalize_graph_layout_config(config)
  solver.config = normalized_config
  solver.node_ids = newSeq[uint32](nodes.len)
  solver.node_sizes = newSeq[ClayDimensions](nodes.len)
  solver.positions = newSeq[ClayVector2](nodes.len)
  solver.target_positions = newSeq[ClayVector2](nodes.len)
  solver.old_positions = newSeq[ClayVector2](nodes.len)
  for index, node in nodes:
    solver.node_ids[index] = node.stable_id
    solver.node_sizes[index] = node.size
    var initial_position = node.screen_position
    for previous_index, previous_node_id in previous_node_ids:
      if previous_node_id == node.stable_id and previous_index < previous_positions.len:
        initial_position = previous_positions[previous_index]
        break
    solver.positions[index] = initial_position
    solver.old_positions[index] = initial_position
  solver.edge_keys = current_edge_keys
  solver.affected_nodes = graph_layout_mark_changed_nodes(
    node_lookup,
    current_edge_table,
    nodes,
    previous_node_ids,
    previous_node_sizes,
    previous_edge_keys)

  var real_layers = newSeq[int](nodes.len)
  for node_index in topological_order:
    for end_index in validation_outgoing[node_index]:
      real_layers[end_index] = max(
        real_layers[end_index], real_layers[node_index] + 1)

  var previous_layers_by_id = initTable[uint32, int]()
  for index, node_id in previous_node_ids:
    if index < previous_node_layers.len:
      previous_layers_by_id[node_id] = previous_node_layers[index]
  for index, node in nodes:
    if previous_layers_by_id.hasKey(node.stable_id) and
        previous_layers_by_id[node.stable_id] != real_layers[index]:
      solver.affected_nodes[index] = true
  solver.node_layers = real_layers

  var max_layer = 0
  for layer in real_layers:
    max_layer = max(max_layer, layer)
  solver.vertices = newSeq[GraphLayoutVertex](nodes.len)
  solver.layers = newSeq[seq[int]](max_layer + 1)
  for index, node in nodes:
    solver.vertices[index] = GraphLayoutVertex(
      stable_key: uint64(node.stable_id),
      real_node_index: index,
      layer: real_layers[index],
      old_position: solver.old_positions[index],
      size: node.size)
    solver.layers[real_layers[index]].add(index)

  solver.links.setLen(0)
  solver.direct_links.setLen(0)
  for edge_index, edge in ordered_edges:
    let start_index = node_lookup[edge.start_node_id]
    let end_index = node_lookup[edge.end_node_id]
    var previous_vertex = start_index
    let start_layer = real_layers[start_index]
    let end_layer = real_layers[end_index]
    for layer in start_layer + 1 ..< end_layer:
      let ratio = float32(layer - start_layer) / float32(end_layer - start_layer)
      let dummy_index = solver.vertices.len
      solver.vertices.add(GraphLayoutVertex(
        stable_key: 0x100000000'u64 + uint64(edge_index),
        real_node_index: -1,
        layer: layer,
        old_position: vector2(
          solver.old_positions[start_index].x +
            (solver.old_positions[end_index].x -
            solver.old_positions[start_index].x) * ratio,
          solver.old_positions[start_index].y +
            (solver.old_positions[end_index].y -
            solver.old_positions[start_index].y) * ratio),
        size: dimensions(0, 0)))
      solver.layers[layer].add(dummy_index)
      solver.links.add(GraphLayoutLink(
        start_vertex: previous_vertex,
        end_vertex: dummy_index))
      previous_vertex = dummy_index
    solver.links.add(GraphLayoutLink(
      start_vertex: previous_vertex,
      end_vertex: end_index))
    solver.direct_links.add(GraphLayoutLink(
      start_vertex: start_index,
      end_vertex: end_index))

  solver.predecessors = newSeq[seq[int]](solver.vertices.len)
  solver.successors = newSeq[seq[int]](solver.vertices.len)
  for link in solver.links:
    solver.successors[link.start_vertex].add(link.end_vertex)
    solver.predecessors[link.end_vertex].add(link.start_vertex)

  solver.affected_layers = newSeq[bool](solver.layers.len)
  for vertex_index, vertex in solver.vertices:
    if vertex.real_node_index >= 0:
      if solver.affected_nodes[vertex.real_node_index]:
        solver.affected_layers[vertex.layer] = true
    elif solver.predecessors[vertex_index].len > 0 and
        solver.successors[vertex_index].len > 0:
      let start_vertex = solver.predecessors[vertex_index][0]
      let end_vertex = solver.successors[vertex_index][0]
      if (solver.vertices[start_vertex].real_node_index >= 0 and
          solver.affected_nodes[solver.vertices[start_vertex].real_node_index]) or
          (solver.vertices[end_vertex].real_node_index >= 0 and
          solver.affected_nodes[solver.vertices[end_vertex].real_node_index]):
        solver.affected_layers[vertex.layer] = true

  for layer_index in 0 ..< solver.layers.len:
    let layout_vertices = solver.vertices
    solver.layers[layer_index].sort(proc(left, right: int): int =
      graph_layout_compare_initial(layout_vertices, left, right))
  graph_layout_rebuild_orders(solver)
  solver.sweep_index = 0
  solver.graph_layout_rebuild_target()
  solver.last_crossings = solver.graph_layout_count_crossings()
  solver.status = if nodes.len == 0:
    graph_layout_complete
  else:
    graph_layout_solving
  result = true

proc begin_graph_layout*(solver: var GraphLayoutSolver;
    nodes: openArray[GraphNode]; edges: openArray[GraphLayoutEdge]): bool =
  solver.begin_graph_layout(nodes, edges, default_graph_layout_config())

proc step_graph_layout*(solver: var GraphLayoutSolver; delta_time: float32): bool =
  if solver.status in {graph_layout_idle, graph_layout_complete}:
    return false

  if solver.sweep_index < solver.config.crossing_sweeps:
    solver.graph_layout_try_sweep(solver.sweep_index mod 2 == 0)
    inc solver.sweep_index
    solver.graph_layout_rebuild_target()
    if solver.sweep_index >= solver.config.crossing_sweeps:
      solver.status = graph_layout_transitioning

  let safe_delta_time = max(delta_time, 0'f32)
  var alpha = 1'f32
  if solver.config.transition_seconds > 0:
    alpha = float32(1.0 - exp(
      -6.0 * float64(safe_delta_time) /
      float64(solver.config.transition_seconds)))
  for index in 0 ..< solver.positions.len:
    solver.positions[index] = vector2(
      solver.positions[index].x +
        (solver.target_positions[index].x - solver.positions[index].x) * alpha,
      solver.positions[index].y +
        (solver.target_positions[index].y - solver.positions[index].y) * alpha)
  if solver.config.transition_seconds > 0:
    solver.graph_layout_resolve_overlaps()

  if solver.status == graph_layout_transitioning and
      (solver.config.transition_seconds <= 0 or
      solver.graph_layout_positions_close()):
    solver.positions = solver.target_positions
    solver.status = graph_layout_complete
  result = solver.status notin {graph_layout_idle, graph_layout_complete}

proc apply_graph_layout*(solver: GraphLayoutSolver; nodes: var seq[GraphNode]) =
  var positions = initTable[uint32, ClayVector2]()
  for index, node_id in solver.node_ids:
    if index < solver.positions.len:
      positions[node_id] = solver.positions[index]
  for node in nodes.mitems:
    if positions.hasKey(node.stable_id):
      node.screen_position = positions[node.stable_id]

proc begin_graph_layout*(graph: var GraphView;
    edges: openArray[GraphLayoutEdge]; config: GraphLayoutConfig): bool =
  graph.layout_solver.begin_graph_layout(graph.nodes, edges, config)

proc begin_graph_layout*(graph: var GraphView;
    edges: openArray[GraphLayoutEdge]): bool =
  graph.layout_solver.begin_graph_layout(graph.nodes, edges)

proc step_graph_layout*(graph: var GraphView; delta_time: float32): bool =
  result = graph.layout_solver.step_graph_layout(delta_time)
  graph.layout_solver.apply_graph_layout(graph.nodes)

proc ensure_graph_canvas_state(graph: var GraphView) {.inline.} =
  if graph.canvas_config.pan_button == 0:
    graph.canvas_config.pan_button = sdl_button_left
  if graph.canvas_config.zoom_factor <= 1 or
      graph.canvas_config.zoom_factor != graph.canvas_config.zoom_factor:
    graph.canvas_config.zoom_factor = default_graph_zoom_factor
  if graph.zoom <= 0 or graph.zoom != graph.zoom:
    graph.zoom = 1'f32

proc graph_transform_point(graph: GraphView; point: ClayVector2): ClayVector2 {.inline.} =
  vector2(
    graph.pan.x + point.x * graph.zoom,
    graph.pan.y + point.y * graph.zoom)

proc pointer_inside_canvas(bounds: ClayBoundingBox; pointer: ClayVector2): bool {.inline.} =
  pointer.x >= bounds.x and
    pointer.y >= bounds.y and
    pointer.x < bounds.x + bounds.width and
    pointer.y < bounds.y + bounds.height

proc graph_node_geometry(graph: GraphView; node: GraphNode): GraphNodeGeometry =
  let circle_diameter_world = min(node.size.width, node.size.height)
  let circle_origin_world = vector2(
    node.screen_position.x + (node.size.width - circle_diameter_world) / 2,
    node.screen_position.y + (node.size.height - circle_diameter_world) / 2)
  result.screen_bounds = ClayBoundingBox(
    x: graph.graph_transform_point(node.screen_position).x,
    y: graph.graph_transform_point(node.screen_position).y,
    width: float32(node.size.width) * graph.zoom,
    height: float32(node.size.height) * graph.zoom)
  result.circle_origin = graph.graph_transform_point(circle_origin_world)
  result.circle_diameter = circle_diameter_world * graph.zoom

proc graph_local_pointer(graph: GraphView; pointer: ClayVector2): ClayVector2 {.inline.} =
  vector2(
    pointer.x - graph.viewport_bounds.x,
    pointer.y - graph.viewport_bounds.y)

proc pointer_inside_graph(graph: GraphView; pointer: ClayVector2): bool {.inline.} =
  graph.viewport_valid and
    pointer_inside_canvas(graph.viewport_bounds, pointer) and
    (not graph.panel_valid or not pointer_inside_canvas(graph.panel_bounds, pointer))

proc graph_pointer_inside*(graph: GraphView; pointer: ClayVector2): bool {.inline.} =
  graph.pointer_inside_graph(pointer)

proc hovered_graph_node(graph: GraphView; pointer: ClayVector2): tuple[found: bool; stable_id: uint32] =
  var best_z_index = low(int16)
  for node in graph.nodes:
    let geometry = graph.graph_node_geometry(node)
    let radius = geometry.circle_diameter / 2'f32
    let center = vector2(
      geometry.circle_origin.x + radius,
      geometry.circle_origin.y + radius)
    let delta_x = pointer.x - center.x
    let delta_y = pointer.y - center.y
    if delta_x * delta_x + delta_y * delta_y <= radius * radius and
        (not result.found or node.z_index >= best_z_index):
      result = (true, node.stable_id)
      best_z_index = node.z_index

proc graph_node_at_pointer(graph: GraphView; pointer: ClayVector2): tuple[found: bool; stable_id: uint32] =
  if graph.pointer_inside_graph(pointer):
    result = graph.hovered_graph_node(graph.graph_local_pointer(pointer))

proc refresh_graph_hover(graph: var GraphView) =
  graph.hovered_node_valid = false
  if not graph.pointer_valid:
    return
  let hovered_node = graph.graph_node_at_pointer(graph.pointer_position)
  if hovered_node.found:
    graph.hovered_node_id = hovered_node.stable_id
    graph.hovered_node_valid = true

proc set_graph_viewport*(graph: var GraphView; viewport_bounds: ClayBoundingBox;
    panel_bounds: ClayBoundingBox = ClayBoundingBox(); panel_valid = false) =
  graph.viewport_bounds = viewport_bounds
  graph.panel_bounds = panel_bounds
  graph.viewport_valid = viewport_bounds.width > 0 and viewport_bounds.height > 0
  graph.panel_valid = panel_valid
  graph.refresh_graph_hover()

proc clear_graph_viewport*(graph: var GraphView) =
  graph.viewport_valid = false
  graph.panel_valid = false
  graph.pointer_valid = false
  graph.refresh_graph_hover()

proc clear_graph_pointer*(graph: var GraphView) =
  graph.pressed_node_valid = false
  graph.pan_active = false
  graph.pointer_valid = false
  graph.refresh_graph_hover()

proc valid_graph_float(value: float32): bool {.inline.} =
  value == value and value >= -high(float32) and value <= high(float32)

proc cancel_pan*(graph: var GraphView) {.inline.} =
  graph.pan_active = false

proc zoom_at_pointer(graph: var GraphView; pointer: ClayVector2; wheel_delta: float32) =
  if wheel_delta == 0 or not graph.pointer_inside_graph(pointer):
    return

  let old_zoom = graph.zoom
  let local_pointer = graph.graph_local_pointer(pointer)
  let world_pointer = vector2(
    (local_pointer.x - graph.pan.x) / old_zoom,
    (local_pointer.y - graph.pan.y) / old_zoom)
  let zoom_multiplier = pow(
    float64(graph.canvas_config.zoom_factor),
    float64(wheel_delta))
  let next_zoom = old_zoom * float32(zoom_multiplier)
  if next_zoom <= 0 or next_zoom > high(float32) or next_zoom != next_zoom:
    return

  let next_pan = vector2(
    local_pointer.x - world_pointer.x * next_zoom,
    local_pointer.y - world_pointer.y * next_zoom)
  if not valid_graph_float(next_pan.x) or not valid_graph_float(next_pan.y):
    return

  graph.zoom = next_zoom
  graph.pan = next_pan

proc update_graph_pointer(graph: var GraphView; event: UiEvent) =
  case event.kind
  of ui_event_mouse_move,
      ui_event_mouse_button_down,
      ui_event_mouse_button_up,
      ui_event_mouse_wheel:
    graph.pointer_position = vector2(event.x, event.y)
    graph.pointer_valid = true
  else:
    discard

proc handle_event*(graph: var GraphView; event: UiEvent) =
  graph.ensure_graph_canvas_state()
  graph.update_graph_pointer(event)
  case event.kind
  of ui_event_mouse_button_down:
    let pointer = vector2(event.x, event.y)
    graph.pressed_node_valid = false
    if event.button == graph.canvas_config.pan_button and
        graph.pointer_inside_graph(pointer):
      let hovered_node = graph.graph_node_at_pointer(pointer)
      if hovered_node.found:
        graph.pressed_node_id = hovered_node.stable_id
        graph.pressed_node_pointer = pointer
        graph.pressed_node_valid = true
      graph.pan_active = true
      graph.pan_pointer = pointer
  of ui_event_mouse_move:
    if graph.pressed_node_valid:
      let delta_x = event.x - graph.pressed_node_pointer.x
      let delta_y = event.y - graph.pressed_node_pointer.y
      if delta_x * delta_x + delta_y * delta_y >
          graph_node_click_slop * graph_node_click_slop:
        graph.pressed_node_valid = false
    if graph.pan_active:
      graph.pan = vector2(
        graph.pan.x + event.x - graph.pan_pointer.x,
        graph.pan.y + event.y - graph.pan_pointer.y)
      graph.pan_pointer = vector2(event.x, event.y)
    graph.refresh_graph_hover()
  of ui_event_mouse_button_up:
    if graph.pressed_node_valid and
        (event.button == graph.canvas_config.pan_button or event.button == 0):
      let hovered_node = graph.graph_node_at_pointer(graph.pointer_position)
      if hovered_node.found and hovered_node.stable_id == graph.pressed_node_id:
        if graph.selected_node_valid and
            graph.selected_node_id == hovered_node.stable_id:
          graph.selected_node_valid = false
        else:
          graph.selected_node_id = hovered_node.stable_id
          graph.selected_node_valid = true
    graph.pressed_node_valid = false
    if graph.pan_active and
        (event.button == graph.canvas_config.pan_button or event.button == 0):
      graph.cancel_pan()
    graph.refresh_graph_hover()
  of ui_event_mouse_wheel:
    graph.zoom_at_pointer(vector2(event.x, event.y), event.wheel_y)
    graph.refresh_graph_hover()
  of ui_event_window_focus_lost, ui_event_mouse_leave:
    graph.clear_graph_pointer()
  else:
    discard

proc graph_node_center(node: GraphNode): ClayVector2 {.inline.} =
  vector2(
    float32(node.screen_position.x) + float32(node.size.width) / 2'f32,
    float32(node.screen_position.y) + float32(node.size.height) / 2'f32)

proc graph_node_radius(node: GraphNode): float32 {.inline.} =
  min(float32(node.size.width), float32(node.size.height)) / 2'f32

proc graph_node_index_by_id(graph: GraphView; stable_id: uint32): int {.inline.} =
  for index, node in graph.nodes:
    if node.stable_id == stable_id:
      return index
  -1

proc add_graph_arrow(graph: var GraphView; arrow: GraphArrow) =
  var start_node_index = arrow.start_node_index
  var end_node_index = arrow.end_node_index
  if arrow.use_stable_ids or arrow.start_node_id != 0 or arrow.end_node_id != 0:
    start_node_index = graph.graph_node_index_by_id(arrow.start_node_id)
    end_node_index = graph.graph_node_index_by_id(arrow.end_node_id)
  if start_node_index < 0 or
      start_node_index >= graph.nodes.len or
      end_node_index < 0 or
      end_node_index >= graph.nodes.len:
    return

  let start_node = graph.nodes[start_node_index]
  let end_node = graph.nodes[end_node_index]
  let start_center = graph_node_center(start_node)
  let end_center = graph_node_center(end_node)
  let delta_x = float32(end_center.x - start_center.x)
  let delta_y = float32(end_center.y - start_center.y)
  let center_distance = sqrt(delta_x * delta_x + delta_y * delta_y)
  let padding = max(arrow.padding, 0'f32)
  let start_offset = graph_node_radius(start_node) + padding
  let end_offset = graph_node_radius(end_node) + padding
  if center_distance <= start_offset + end_offset:
    return

  let direction_x = delta_x / center_distance
  let direction_y = delta_y / center_distance
  let start_point_world = vector2(
    float32(start_center.x) + direction_x * start_offset,
    float32(start_center.y) + direction_y * start_offset)
  let end_point_world = vector2(
    float32(end_center.x) - direction_x * end_offset,
    float32(end_center.y) - direction_y * end_offset)
  let start_point = graph.graph_transform_point(start_point_world)
  let end_point = graph.graph_transform_point(end_point_world)
  graph.draw_list.add_opaque_arrow(
    start_point,
    end_point,
    arrow.color,
    arrow.shaft_width * graph.zoom,
    arrow.head_length * graph.zoom,
    arrow.head_width * graph.zoom,
    arrow.z_index)

proc graph_node_z_index*(node: GraphNode): int16 {.inline.} =
  int16(10 + int(node.z_index))

proc add_graph_node_draw_items(graph: GraphView; node: GraphNode) =
  let geometry = graph.graph_node_geometry(node)
  let highlighted = graph.hovered_node_valid and
    graph.hovered_node_id == node.stable_id
  let circle_color = if node.circle_color.a > 0:
    node.circle_color
  else:
    rgba(255, 255, 255, 255)
  let border_color = rgba(20, 18, 15, 255)
  let inner_circle_diameter_world = max(
    min(node.size.width, node.size.height) - graph_node_border_width * 2'f32,
    0'f32)
  let inner_circle_origin = vector2(
    geometry.circle_origin.x + graph_node_border_width * graph.zoom,
    geometry.circle_origin.y + graph_node_border_width * graph.zoom)
  let node_z_index = graph_node_z_index(node)
  if highlighted:
    let highlight_origin = vector2(
      geometry.circle_origin.x - graph_node_highlight_width * graph.zoom,
      geometry.circle_origin.y - graph_node_highlight_width * graph.zoom)
    graph.draw_list.add_opaque_circle(
      highlight_origin,
      geometry.circle_diameter + graph_node_highlight_width * 2'f32 * graph.zoom,
      rgba(70, 145, 255, 255),
      node_z_index)
  graph.draw_list.add_opaque_circle(
    geometry.circle_origin,
    geometry.circle_diameter,
    border_color,
    node_z_index)
  if inner_circle_diameter_world > 0:
    graph.draw_list.add_opaque_circle(
      inner_circle_origin,
      inner_circle_diameter_world * graph.zoom,
      circle_color,
      node_z_index)

proc rebuild_graph_draw_list*(graph: var GraphView) =
  graph.ensure_graph_canvas_state()
  if graph.draw_list == nil:
    graph.draw_list = new_opaque_draw_list()
  clear_opaque_draw_list(graph.draw_list)
  for arrow in graph.arrows:
    graph.add_graph_arrow(arrow)
  for node in graph.nodes:
    graph.add_graph_node_draw_items(node)

template graph_node_element(graph: GraphView; graph_id: ClayElementId;
    node: GraphNode; body: untyped) =
  let node_id = clay_id_with_index("graph_node", node.stable_id)
  let geometry = graph.graph_node_geometry(node)
  let node_z_index = graph_node_z_index(node)

  let node_declaration = declaration(
    layout = layout(
      sizing = sizing(
        fixed(geometry.screen_bounds.width),
        fixed(geometry.screen_bounds.height))),
    floating = ClayFloatingElementConfig(
      parent_id: graph_id.id,
      offset: vector2(geometry.screen_bounds.x, geometry.screen_bounds.y),
      attach_points: ClayFloatingAttachPoints(
        element: clay_attach_point_left_top,
        parent: clay_attach_point_left_top),
      pointer_capture_mode: clay_pointer_capture_mode_passthrough,
      attach_to: clay_attach_to_element_with_id,
      clip_to: clay_clip_to_attached_parent,
      z_index: node_z_index))
  element(node_id, node_declaration):
    body

template graph_node*(graph: GraphView; graph_id: ClayElementId;
    node: GraphNode; body: untyped) =
  graph.add_graph_node_draw_items(node)
  graph_node_element(graph, graph_id, node):
    body

template graph_window_with_panel*(graph: var GraphView; node_name: untyped;
    panel_body: untyped; body: untyped) =
  graph.ensure_graph_canvas_state()
  graph.refresh_graph_hover()
  if graph.selected_node_valid and
      graph.graph_node_index_by_id(graph.selected_node_id) < 0:
    graph.selected_node_valid = false
  graph.rebuild_graph_draw_list()
  let graph_id = clay_id("graph_surface")
  let graph_declaration = declaration(
    layout = layout(sizing = sizing(grow(), grow())),
    clip = ClayClipElementConfig(horizontal: true, vertical: true))
  let paint_declaration = declaration(
    layout = layout(sizing = sizing(grow(), grow())),
    custom = ClayCustomElementConfig(
      custom_data: opaque_draw_list_pointer(graph.draw_list)))
  element(graph_id, graph_declaration):
    element("graph_paint", paint_declaration):
      discard
    for graph_node_value in graph.nodes:
      let node_name = graph_node_value
      graph_node_element(graph, graph_id, node_name):
        body
    if graph.selected_node_valid:
      let panel_host_declaration = declaration(
        layout = layout(
          sizing = sizing(grow(), grow()),
          padding = clay_padding(
            0,
            graph_panel_right_padding,
            graph_panel_top_padding,
            graph_panel_bottom_padding)),
        floating = ClayFloatingElementConfig(
          pointer_capture_mode: clay_pointer_capture_mode_passthrough,
          attach_to: clay_attach_to_parent,
          clip_to: clay_clip_to_attached_parent,
          z_index: graph_panel_host_z_index))
      let panel_area_declaration = declaration(
        layout = layout(sizing = sizing(grow(), grow())))
      let panel_declaration = declaration(
        layout = layout(sizing = sizing(percent(graph_panel_width_fraction), grow())),
        background_color = rgba(255, 250, 235, 255),
        border = ClayBorderElementConfig(
          color: rgba(20, 18, 15, 255), width: border_outside(4)),
        floating = ClayFloatingElementConfig(
          attach_points: ClayFloatingAttachPoints(
            element: clay_attach_point_right_top,
            parent: clay_attach_point_right_top),
          pointer_capture_mode: clay_pointer_capture_mode_capture,
          attach_to: clay_attach_to_parent,
          clip_to: clay_clip_to_attached_parent,
          z_index: graph_panel_z_index))
      element("graph_panel_host", panel_host_declaration):
        element("graph_panel_area", panel_area_declaration):
          element("graph_panel", panel_declaration):
            panel_body

proc graph_no_panel() =
  discard

template graph_window*(graph: var GraphView; node_name: untyped; body: untyped) =
  graph_window_with_panel(graph, node_name, graph_no_panel()):
    body
