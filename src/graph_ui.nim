import clay

type
  GraphNode* = object
    stable_id*: uint32
    screen_position*: ClayVector2
    size*: ClayDimensions
    title*: string
    detail*: string

  GraphView* = object
    nodes*: seq[GraphNode]

template graph_node*(graph_id: ClayElementId; node: GraphNode; body: untyped) =
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
      attach_to: clay_attach_to_element_with_id,
      clip_to: clay_clip_to_attached_parent,
      z_index: 10))
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
      z_index: 11))
  element(clay_id_with_index("graph_node_panel", node.stable_id), panel_declaration):
    body

template graph_window*(graph: GraphView; node_name: untyped; body: untyped) =
  let graph_id = clay_id("graph_surface")
  let graph_declaration = declaration(
    layout = layout(sizing = sizing(grow(), grow())),
    clip = ClayClipElementConfig(horizontal: true, vertical: true))
  element(graph_id, graph_declaration):
    for graph_node_value in graph.nodes:
      let node_name = graph_node_value
      graph_node(graph_id, node_name):
        body
