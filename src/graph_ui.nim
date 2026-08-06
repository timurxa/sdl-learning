import clay
import renderer

type
  GraphNode* = object
    stable_id*: uint32
    screen_position*: ClayVector2
    size*: ClayDimensions
    circle_color*: ClayColor
    z_index*: int16
    title*: string
    detail*: string

  GraphView* = object
    nodes*: seq[GraphNode]
    draw_list*: OpaqueDrawList
    node_pointer_capture_mode*: ClayPointerCaptureMode

proc graph_node_z_index*(node: GraphNode): int16 {.inline.} =
  int16(10 + int(node.z_index))

template graph_node*(graph: GraphView; graph_id: ClayElementId;
    node: GraphNode; body: untyped) =
  let circle_diameter = min(node.size.width, node.size.height)
  let circle_origin = vector2(
    node.screen_position.x + (node.size.width - circle_diameter) / 2,
    node.screen_position.y + (node.size.height - circle_diameter) / 2)
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
      offset: vector2(node.screen_position.x, node.screen_position.y),
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
  if graph.draw_list == nil:
    graph.draw_list = new_opaque_draw_list()
  clear_opaque_draw_list(graph.draw_list)
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
