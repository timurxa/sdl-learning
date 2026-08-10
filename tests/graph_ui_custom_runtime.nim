import ../src/clay
import ../src/graph_ui
import ../src/renderer
import ../src/ui
import ../src/orchestration

proc handle_error(error_data: ClayErrorData) {.cdecl.} =
  doAssert false, $error_data.error_type

let memory_size = clay_min_memory_size()
let arena_memory = alloc0(int(memory_size))
let arena = clay_create_arena_with_capacity_and_memory(memory_size, arena_memory)
discard clay_initialize(
  arena,
  clay_dimensions(200, 120),
  ClayErrorHandler(error_handler_function: handle_error, user_data: nil))

var graph = GraphView(
  work_graph: WorkGraph(nodes: @[
    WorkNode(
      id: 1,
      state: pending,
      execution_plan: ExecutionPlan(`type`: llm_worker)),
    WorkNode(
      id: 2,
      wait_for: @[1],
      state: running,
      execution_plan: ExecutionPlan(`type`: graph_creation))]),
  draw_list: new_opaque_draw_list())

let tooltip_size = dimensions(96, 28)
let window_size = dimensions(200, 120)
graph.handle_event(UiEvent(kind: ui_event_mouse_move, x: 40, y: 40))
let top_left_tooltip = graph.graph_node_tooltip_position(
  window_size, tooltip_size, 10)
doAssert top_left_tooltip.x == 50
doAssert top_left_tooltip.y == 50
graph.handle_event(UiEvent(kind: ui_event_mouse_move, x: 190, y: 110))
let bottom_right_tooltip = graph.graph_node_tooltip_position(
  window_size, tooltip_size, 10)
doAssert bottom_right_tooltip.x == 84
doAssert bottom_right_tooltip.y == 72
let oversized_tooltip = graph.graph_node_tooltip_position(
  dimensions(200, 120), dimensions(240, 140), 10)
doAssert oversized_tooltip.x == 0
doAssert oversized_tooltip.y == 0

clay_begin_layout()
element("root"):
  layout:
    sizing:
      width = grow()
      height = grow()
  graph_window(graph):
    discard
let commands = clay_end_layout(0)
let surface_data = clay_get_element_data(clay_id("graph_surface"))
doAssert surface_data.found
graph.set_graph_viewport(surface_data.bounding_box)

doAssert graph.draw_list.items.len == 11
doAssert graph.draw_list.items[0].kind == opaque_draw_quad
doAssert graph.draw_list.items[1].kind == opaque_draw_triangle
doAssert graph.draw_list.items[2].kind == opaque_draw_circle
doAssert graph.draw_list.items[3].kind == opaque_draw_circle
doAssert graph.draw_list.items[4].kind == opaque_draw_circle
doAssert graph.draw_list.items[5].kind == opaque_draw_circle
doAssert graph.draw_list.items[6].kind == opaque_draw_circle
doAssert graph.draw_list.items[7].kind == opaque_draw_circle
doAssert graph.draw_list.items[8].kind == opaque_draw_circle
doAssert graph.draw_list.items[9].kind == opaque_draw_circle
doAssert graph.draw_list.items[10].kind == opaque_draw_circle
doAssert graph.draw_list.items[0].z_index == 0
doAssert graph.draw_list.items[1].z_index == 0
doAssert graph.draw_list.items[0].shape_data[0] == 120
doAssert graph.draw_list.items[0].shape_data[2] == 132
doAssert graph.draw_list.items[2].z_index == 10
doAssert graph.draw_list.items[3].z_index == 10
doAssert graph.draw_list.items[4].z_index == 10
doAssert graph.draw_list.items[5].z_index == 11
doAssert graph.draw_list.items[6].z_index == 11
doAssert graph.draw_list.items[7].z_index == 11
doAssert graph.draw_list.items[8].z_index == 12
doAssert graph.draw_list.items[9].z_index == 12
doAssert graph.draw_list.items[10].z_index == 12
doAssert graph.draw_list.items[2].size.width == 32
doAssert graph.draw_list.items[3].size.width == 26
doAssert graph.draw_list.items[4].size.width == 24

graph.handle_event(UiEvent(
  kind: ui_event_mouse_move,
  x: 96,
  y: 86))
clay_begin_layout()
element("root"):
  layout:
    sizing:
      width = grow()
      height = grow()
  graph_window(graph):
    discard
discard clay_end_layout(0)

clay_begin_layout()
element("root"):
  layout:
    sizing:
      width = grow()
      height = grow()
  graph_window(graph):
    discard
discard clay_end_layout(0)

doAssert graph.draw_list.items.len == 12
doAssert graph.draw_list.items[2].kind == opaque_draw_circle
doAssert graph.draw_list.items[3].kind == opaque_draw_circle
doAssert graph.draw_list.items[4].kind == opaque_draw_circle
doAssert graph.draw_list.items[5].kind == opaque_draw_circle
doAssert graph.draw_list.items[6].kind == opaque_draw_circle
doAssert graph.draw_list.items[7].kind == opaque_draw_circle
doAssert graph.draw_list.items[8].kind == opaque_draw_circle
doAssert graph.draw_list.items[9].kind == opaque_draw_circle
doAssert graph.draw_list.items[10].kind == opaque_draw_circle
doAssert graph.draw_list.items[11].kind == opaque_draw_circle
doAssert graph.draw_list.items[2].size.width == 40
doAssert graph.draw_list.items[3].size.width == 32
doAssert graph.draw_list.items[4].size.width == 26
doAssert graph.draw_list.items[5].size.width == 24
doAssert graph.draw_list.items[6].size.width == 32
doAssert graph.draw_list.items[7].size.width == 26
doAssert graph.draw_list.items[8].size.width == 24
doAssert graph.draw_list.items[2].z_index == 10
doAssert graph.draw_list.items[3].z_index == 10
doAssert graph.draw_list.items[4].z_index == 10
doAssert graph.draw_list.items[5].z_index == 10
doAssert graph.draw_list.items[6].z_index == 11
doAssert graph.draw_list.items[7].z_index == 11
doAssert graph.draw_list.items[8].z_index == 11
doAssert graph.draw_list.items[9].z_index == 12
doAssert graph.draw_list.items[10].z_index == 12
doAssert graph.draw_list.items[11].z_index == 12

var custom_command_count: int
for command in commands:
  if command.command_type == clay_render_command_type_custom:
    inc custom_command_count
    doAssert command.render_data.custom.custom_data ==
      opaque_draw_list_pointer(graph.draw_list)

doAssert custom_command_count == 1
doAssert clay_get_element_data(clay_id_with_index("graph_node", 1)).found
doAssert clay_get_element_data(clay_id_with_index("graph_node", 2)).found

clay_deinitialize()
dealloc(arena_memory)
