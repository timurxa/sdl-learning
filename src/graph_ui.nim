import std/math
import clay
import renderer
import sdl
import ui

type
  GraphArrow* = object
    start_node_index*: int
    end_node_index*: int
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

  GraphCanvasConfig* = object
    pan_button*: uint8
    zoom_factor*: float32

  GraphView* = object
    nodes*: seq[GraphNode]
    arrows*: seq[GraphArrow]
    draw_list*: OpaqueDrawList
    node_pointer_capture_mode*: ClayPointerCaptureMode
    canvas_config*: GraphCanvasConfig
    pan*: ClayVector2
    zoom*: float32
    pan_active: bool
    pan_pointer: ClayVector2

const
  default_graph_zoom_factor = 1.1'f32

proc ensure_graph_canvas_state(graph: var GraphView) {.inline.} =
  if graph.canvas_config.pan_button == 0:
    graph.canvas_config.pan_button = sdl_button_left
  if graph.canvas_config.zoom_factor <= 1 or
      graph.canvas_config.zoom_factor != graph.canvas_config.zoom_factor:
    graph.canvas_config.zoom_factor = default_graph_zoom_factor
  if graph.zoom <= 0 or graph.zoom != graph.zoom:
    graph.zoom = 1'f32

proc graph_surface_id(): ClayElementId {.inline.} =
  clay_id("graph_surface")

proc pointer_inside_canvas(bounds: ClayBoundingBox; pointer: ClayVector2): bool {.inline.} =
  pointer.x >= bounds.x and
    pointer.y >= bounds.y and
    pointer.x < bounds.x + bounds.width and
    pointer.y < bounds.y + bounds.height

proc valid_graph_float(value: float32): bool {.inline.} =
  value == value and value >= -high(float32) and value <= high(float32)

proc cancel_pan*(graph: var GraphView) {.inline.} =
  graph.pan_active = false

proc zoom_at_pointer(graph: var GraphView; pointer: ClayVector2; wheel_delta: float32) =
  let element_data = clay_get_element_data(graph_surface_id())
  if wheel_delta == 0 or not element_data.found or
      not pointer_inside_canvas(element_data.bounding_box, pointer):
    return

  let old_zoom = graph.zoom
  let local_pointer = vector2(
    pointer.x - element_data.bounding_box.x,
    pointer.y - element_data.bounding_box.y)
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

proc handle_event*(graph: var GraphView; event: UiEvent) =
  graph.ensure_graph_canvas_state()
  case event.kind
  of ui_event_mouse_button_down:
    let pointer = vector2(event.x, event.y)
    let element_data = clay_get_element_data(graph_surface_id())
    if event.button == graph.canvas_config.pan_button and
        element_data.found and
        pointer_inside_canvas(element_data.bounding_box, pointer) and
        clay_pointer_over(graph_surface_id()):
      graph.pan_active = true
      graph.pan_pointer = pointer
  of ui_event_mouse_move:
    if graph.pan_active:
      graph.pan = vector2(
        graph.pan.x + event.x - graph.pan_pointer.x,
        graph.pan.y + event.y - graph.pan_pointer.y)
      graph.pan_pointer = vector2(event.x, event.y)
  of ui_event_mouse_button_up:
    if graph.pan_active and
        (event.button == graph.canvas_config.pan_button or event.button == 0):
      graph.cancel_pan()
  of ui_event_mouse_wheel:
    graph.zoom_at_pointer(vector2(event.x, event.y), event.wheel_y)
  of ui_event_window_focus_lost:
    graph.cancel_pan()
  of ui_event_mouse_leave:
    graph.cancel_pan()
  else:
    discard

proc graph_transform_point(graph: GraphView; point: ClayVector2): ClayVector2 {.inline.} =
  vector2(
    graph.pan.x + point.x * graph.zoom,
    graph.pan.y + point.y * graph.zoom)

proc graph_node_center(node: GraphNode): ClayVector2 {.inline.} =
  vector2(
    float32(node.screen_position.x) + float32(node.size.width) / 2'f32,
    float32(node.screen_position.y) + float32(node.size.height) / 2'f32)

proc graph_node_radius(node: GraphNode): float32 {.inline.} =
  min(float32(node.size.width), float32(node.size.height)) / 2'f32

proc add_graph_arrow(graph: var GraphView; arrow: GraphArrow) =
  if arrow.start_node_index < 0 or
      arrow.start_node_index >= graph.nodes.len or
      arrow.end_node_index < 0 or
      arrow.end_node_index >= graph.nodes.len:
    return

  let start_node = graph.nodes[arrow.start_node_index]
  let end_node = graph.nodes[arrow.end_node_index]
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

template graph_node*(graph: GraphView; graph_id: ClayElementId;
    node: GraphNode; body: untyped) =
  let circle_diameter_world = min(node.size.width, node.size.height)
  let circle_origin_world = vector2(
    node.screen_position.x + (node.size.width - circle_diameter_world) / 2,
    node.screen_position.y + (node.size.height - circle_diameter_world) / 2)
  let circle_origin = graph.graph_transform_point(circle_origin_world)
  let circle_diameter = circle_diameter_world * graph.zoom
  let circle_color = if node.circle_color.a > 0:
    node.circle_color
  else:
    rgba(255, 255, 255, 255)
  let node_z_index = graph_node_z_index(node)
  graph.draw_list.add_opaque_circle(
    circle_origin,
    circle_diameter,
    circle_color,
    node_z_index)

  let node_id = clay_id_with_index("graph_node", node.stable_id)
  let node_declaration = declaration(
    layout = layout(
      sizing = sizing(fixed(node.size.width), fixed(node.size.height))),
    floating = ClayFloatingElementConfig(
      parent_id: graph_id.id,
      offset: graph.graph_transform_point(node.screen_position),
      attach_points: ClayFloatingAttachPoints(
        element: clay_attach_point_left_top,
        parent: clay_attach_point_left_top),
      pointer_capture_mode: graph.node_pointer_capture_mode,
      attach_to: clay_attach_to_element_with_id,
      clip_to: clay_clip_to_attached_parent,
      z_index: node_z_index))
  element(node_id, node_declaration):
    body

template graph_node_panel*(node: GraphNode; panel_background: ClayColor;
    border_color: ClayColor; body: untyped) =
  let node_id = clay_id_with_index("graph_node", node.stable_id)
  let panel_declaration = declaration(
    layout = layout(
      sizing = sizing(fixed(node.size.width), fixed(node.size.height)),
      padding = padding_all(8),
      child_gap = 4,
      layout_direction = clay_top_to_bottom),
    background_color = panel_background,
    border = ClayBorderElementConfig(
      color: border_color,
      width: border_outside(3)),
    floating = ClayFloatingElementConfig(
      parent_id: node_id.id,
      offset: vector2(0, 0),
      attach_points: ClayFloatingAttachPoints(
        element: clay_attach_point_left_top,
        parent: clay_attach_point_left_top),
      attach_to: clay_attach_to_element_with_id,
      clip_to: clay_clip_to_attached_parent,
      z_index: int16(graph_node_z_index(node) + 1)))
  element(clay_id_with_index("graph_node_panel", node.stable_id), panel_declaration):
    body

template graph_window*(graph: var GraphView; node_name: untyped; body: untyped) =
  graph.ensure_graph_canvas_state()
  if graph.draw_list == nil:
    graph.draw_list = new_opaque_draw_list()
  clear_opaque_draw_list(graph.draw_list)
  for arrow in graph.arrows:
    graph.add_graph_arrow(arrow)
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
      graph_node(graph, graph_id, node_name):
        body
