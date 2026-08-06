import ../src/clay
import ../src/graph_ui
import ../src/renderer

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
  nodes: @[
    GraphNode(
      stable_id: 1,
      screen_position: vector2(12, 16),
      size: dimensions(24, 24),
      circle_color: rgba(255, 0, 0, 255),
      z_index: 2),
    GraphNode(
      stable_id: 2,
      screen_position: vector2(56, 16),
      size: dimensions(24, 24),
      circle_color: rgba(0, 255, 0, 255),
      z_index: -1)],
  draw_list: new_opaque_draw_list())

clay_begin_layout()
element("root"):
  layout:
    sizing:
      width = grow()
      height = grow()
  graph_window(graph, node):
    discard
let commands = clay_end_layout(0)

doAssert graph.draw_list.items.len == 2
doAssert graph.draw_list.items[0].kind == opaque_draw_circle
doAssert graph.draw_list.items[1].kind == opaque_draw_circle
doAssert graph.draw_list.items[0].z_index == 12
doAssert graph.draw_list.items[1].z_index == 9

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
