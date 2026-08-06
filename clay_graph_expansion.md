# Clay graph expansion

## Design

Build the graph UI as a Nim composition layer on top of Clay. Do not add graph-specific element types to `clay.h`.

The component should be a `template` that emits several existing Clay elements:

```text
graph_surface        normal Clay element; owns layout and clipping
├── graph_paint      custom command; grid, edges, curves, previews
├── floating nodes   normal Clay subtrees; text, inputs, buttons
└── graph_overlay    optional custom/floating selection geometry
```

Clay’s `element` macro already preserves ordinary Nim statements, so loops and conditionals can create elements dynamically. A custom component is therefore a wrapper around `element`, not a new C-level Clay primitive.

## Component API

Keep the implementation in `src/graph_ui.nim` or, for generic helpers, `src/clay.nim`. `clay.h` should remain graph-agnostic.

Conceptual shape:

```nim
template graph_window*(graph: var GraphView; body: untyped) =
  let graph_id = clay_id("graph_surface")

  element(graph_id):
    layout:
      sizing:
        width = grow()
        height = grow()

    clip:
      horizontal = true
      vertical = true

    element("graph_paint"):
      layout:
        sizing:
          width = grow()
          height = grow()
      custom:
        custom_data = graph.paint_data

    for node in graph.visible_nodes:
      graph_node(graph, graph_id, node):
        render_node_contents(node)

    body
```

`graph_node` computes a graph-local screen position, then emits a stable, fixed-size floating Clay element:

```nim
template graph_node*(graph: var GraphView; graph_id: ClayElementId;
    node: GraphNode; body: untyped) =
  let node_id = clay_id_with_index("graph_node", node.stable_id)

  element(node_id):
    layout:
      sizing:
        width = fixed(node.size.width)
        height = fixed(node.size.height)

    floating:
      parent_id = graph_id.id
      offset = vector2(node.screen_position.x, node.screen_position.y)
      attach_points:
        element = clay_attach_point_left_top
        parent = clay_attach_point_left_top
      attach_to = clay_attach_to_element_with_id
      clip_to = clay_clip_to_attached_parent
      z_index = 10

    body
```

Use explicit stable IDs derived from domain IDs. Avoid `element_auto` for graph nodes because persistent selection, focus, transitions, and menus depend on IDs remaining stable when ordering changes.

## Rendering and layout lifecycle

1. Update graph state, viewport, pan/zoom transform, and visible-node query.
2. Build the Clay DSL. Emit the graph paint layer and visible floating node subtrees.
3. Call `clay_end_layout()`.
4. Query final node, port, and control bounds with `clay_get_element_data()`.
5. Populate the graph paint list using those bounds.
6. Render Clay commands, handling `CLAY_RENDER_COMMAND_TYPE_CUSTOM` in the renderer.

The custom command carries one raw `custom_data` pointer. Use a persistent or frame-owned `GraphPaintList`; do not point it at a temporary stack object or storage that may be reallocated before rendering. The paint list can contain renderer-neutral commands such as filled/stroked rectangles, lines, polylines, quadratic/cubic curves, circles, ellipses, and triangles.

Edges and grid should be drawn in the custom paint layer behind node roots. Use a higher-z floating custom layer for selection outlines, connection previews, or other geometry that must appear above nodes.

Put clipping on the enclosing `graph_surface`. Clay emits a custom element’s command before that element’s own clip command, so an outer clipped element is safer than relying on a custom element’s own clip.

## Controls inside nodes

Node contents remain ordinary Clay DSL:

- Text inputs are normal Clay elements with application-owned editing, focus, caret, and keyboard state.
- Use stable input IDs with `clay_pointer_over()` and `clay_get_element_data()`.
- Menus can be floating descendants attached to the node ID with a higher z-index.
- If a menu must extend beyond the graph viewport, emit it in an outer overlay layer or attach it to the root; otherwise the graph surface’s clip will contain it.
- Route pointer ownership explicitly between graph pan, node dragging, controls, menus, ports, and lasso selection. Clay handles element hit regions, but custom edges and ports need graph-specific hit testing.

## Culling

Clay culls individual normal/floating elements using their final bounding boxes after layout. This skips their render commands, but does not avoid constructing or laying out them. Pre-filter graph nodes with a viewport query or spatial index when the graph becomes large. Query a viewport expanded by a small margin and retain selected, dragged, focused, or menu-owning nodes.

A single custom graph paint element is culled only as one rectangle. Clay does not inspect or cull primitives inside `custom_data`; the graph paint builder must cull visible edges, nodes, and decorations itself. A uniform grid spatial index is sufficient initially.

Culling and clipping are separate. If custom geometry extends beyond its Clay bounding box, enlarge the element with `floating.expand` or use a larger paint layer. Disabling Clay culling globally is useful for debugging, not as the graph optimization strategy.

## Coordinate and sizing rules

Clay has no graph/world transform. Convert world coordinates to graph-local pixel offsets before declaring floating nodes. Keep node widgets in screen space if they should remain readable while the graph zooms; keep grid and edges in world space and transform them in the custom renderer.

Prefer fixed or cached node dimensions. If content determines a node’s size, use the previous frame’s size for placement and update the cache after layout; exact port anchors can be refreshed from the post-layout element bounds.

## Scope and expected complexity

The wrapper templates, runtime node generation, floating positioning, text controls, and menus are low-complexity because Clay already supports them. The moderate work is the graph-specific layer: world-to-screen transforms, paint-list rendering, edge routing, custom hit testing, and spatial culling. A large-graph optimization can later switch noninteractive nodes to custom drawing while retaining Clay subtrees for selected or edited nodes.
