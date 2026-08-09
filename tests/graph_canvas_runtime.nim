import ../src/clay
import ../src/graph_ui
import ../src/renderer
import ../src/sdl
import ../src/ui
import ../src/orchestration

proc handle_error(error_data: ClayErrorData) {.cdecl.} =
  doAssert false, $error_data.error_type

let memory_size = clay_min_memory_size()
let arena_memory = alloc0(int(memory_size))
let arena = clay_create_arena_with_capacity_and_memory(
  memory_size,
  arena_memory)
discard clay_initialize(
  arena,
  clay_dimensions(200, 120),
  ClayErrorHandler(error_handler_function: handle_error, user_data: nil))

var graph = GraphView(
  work_graph: WorkGraph(nodes: @[
    WorkNode(
      id: 0,
      state: pending,
      execution_plan: ExecutionPlan(`type`: llm_worker))]),
  draw_list: new_opaque_draw_list())

clay_begin_layout()
element("root"):
  layout:
    sizing:
      width = grow()
      height = grow()
  graph_window(graph):
    discard
discard clay_end_layout(0)

let initial_surface_data = clay_get_element_data(clay_id("graph_surface"))
doAssert initial_surface_data.found
graph.set_graph_viewport(initial_surface_data.bounding_box)

let node_pointer = vector2(96, 86)
graph.handle_event(UiEvent(
  kind: ui_event_mouse_button_down,
  x: node_pointer.x,
  y: node_pointer.y,
  button: sdl_button_left))
graph.handle_event(UiEvent(
  kind: ui_event_mouse_button_up,
  x: node_pointer.x,
  y: node_pointer.y,
  button: sdl_button_left))
doAssert graph.selected_node_valid
doAssert graph.selected_node_id == 0

clay_begin_layout()
element("root"):
  layout:
    sizing:
      width = grow()
      height = grow()
  graph_window(graph):
    discard
discard clay_end_layout(0)
let surface_data = clay_get_element_data(clay_id("graph_surface"))
let panel_data = clay_get_element_data(clay_id("graph_panel"))
doAssert surface_data.found
doAssert panel_data.found
doAssert panel_data.bounding_box.x > surface_data.bounding_box.x
doAssert panel_data.bounding_box.y > surface_data.bounding_box.y
doAssert panel_data.bounding_box.x + panel_data.bounding_box.width <
  surface_data.bounding_box.x + surface_data.bounding_box.width
doAssert panel_data.bounding_box.y + panel_data.bounding_box.height <
  surface_data.bounding_box.y + surface_data.bounding_box.height
doAssert abs(float32(panel_data.bounding_box.width) -
  (float32(surface_data.bounding_box.width) - 16'f32) / 3'f32) < 0.1

let panel_pointer = vector2(
  panel_data.bounding_box.x + panel_data.bounding_box.width / 2,
  panel_data.bounding_box.y + panel_data.bounding_box.height / 2)
graph.set_graph_viewport(
  surface_data.bounding_box,
  panel_data.bounding_box,
  panel_data.found)
let pan_before_panel = graph.pan
graph.handle_event(UiEvent(
  kind: ui_event_mouse_button_down,
  x: panel_pointer.x,
  y: panel_pointer.y,
  button: sdl_button_left))
graph.handle_event(UiEvent(
  kind: ui_event_mouse_move,
  x: panel_pointer.x + 10,
  y: panel_pointer.y + 10))
doAssert graph.pan == pan_before_panel
graph.handle_event(UiEvent(
  kind: ui_event_mouse_button_up,
  x: panel_pointer.x + 10,
  y: panel_pointer.y + 10,
  button: sdl_button_left))
let zoom_before_panel = graph.zoom
graph.handle_event(UiEvent(
  kind: ui_event_mouse_wheel,
  x: panel_pointer.x,
  y: panel_pointer.y,
  wheel_y: 1))
doAssert graph.zoom == zoom_before_panel

graph.handle_event(UiEvent(
  kind: ui_event_mouse_button_down,
  x: node_pointer.x,
  y: node_pointer.y,
  button: sdl_button_left))
graph.handle_event(UiEvent(
  kind: ui_event_mouse_button_up,
  x: node_pointer.x,
  y: node_pointer.y,
  button: sdl_button_left))
doAssert not graph.selected_node_valid

let retained_node = graph.work_graph.nodes[0]
graph.handle_event(UiEvent(
  kind: ui_event_mouse_button_down,
  x: node_pointer.x,
  y: node_pointer.y,
  button: sdl_button_left))
graph.handle_event(UiEvent(
  kind: ui_event_mouse_button_up,
  x: node_pointer.x,
  y: node_pointer.y,
  button: sdl_button_left))
doAssert graph.selected_node_valid

graph.work_graph.nodes.setLen(0)
clay_begin_layout()
element("root"):
  layout:
    sizing:
      width = grow()
      height = grow()
  graph_window(graph):
    discard
discard clay_end_layout(0)
doAssert not graph.selected_node_valid
doAssert not clay_get_element_data(clay_id("graph_panel")).found
graph.work_graph.nodes.add(retained_node)

let pointer = vector2(100, 60)
graph.handle_event(UiEvent(
  kind: ui_event_mouse_wheel,
  x: pointer.x,
  y: pointer.y,
  wheel_y: 1))
doAssert graph.zoom > 1
let zoomed_pointer = vector2(
  graph.pan.x + pointer.x * graph.zoom,
  graph.pan.y + pointer.y * graph.zoom)
doAssert abs(float32(zoomed_pointer.x) - pointer.x) < 0.001
doAssert abs(float32(zoomed_pointer.y) - pointer.y) < 0.001

clay_begin_layout()
element("root"):
  layout:
    sizing:
      width = grow()
      height = grow()
  graph_window(graph):
    discard
discard clay_end_layout(0)
doAssert abs(
  float32(graph.draw_list.items[0].size.width) - 32'f32 * graph.zoom) < 0.001
let popup_data = clay_get_element_data(clay_id_with_index("graph_node", 0))
doAssert popup_data.found
doAssert abs(float32(popup_data.bounding_box.width) - 32'f32 * graph.zoom) < 0.001
doAssert abs(float32(popup_data.bounding_box.height) - 32'f32 * graph.zoom) < 0.001

graph.zoom = 2.1'f32
graph.pan = vector2(pointer.x - 96'f32 * graph.zoom,
  pointer.y - 86'f32 * graph.zoom)
graph.handle_event(UiEvent(
  kind: ui_event_mouse_move,
  x: pointer.x,
  y: pointer.y))
doAssert graph.hovered_node_valid
doAssert graph.hovered_node_id == 0

let pan_before = graph.pan
graph.handle_event(UiEvent(
  kind: ui_event_mouse_button_down,
  x: 20,
  y: 20,
  button: sdl_button_left))
graph.handle_event(UiEvent(
  kind: ui_event_mouse_move,
  x: 35,
  y: 40))
doAssert abs(float32(graph.pan.x) - float32(pan_before.x + 15)) < 0.001
doAssert abs(float32(graph.pan.y) - float32(pan_before.y + 20)) < 0.001
graph.handle_event(UiEvent(
  kind: ui_event_mouse_button_up,
  x: 35,
  y: 40,
  button: sdl_button_left))

graph.zoom = 1'f32
graph.pan = vector2(-60, -50)
graph.set_graph_viewport(initial_surface_data.bounding_box)
graph.handle_event(UiEvent(
  kind: ui_event_mouse_move,
  x: 38,
  y: 30))
doAssert graph.hovered_node_valid
graph.handle_event(UiEvent(
  kind: ui_event_mouse_move,
  x: 55,
  y: 35))
doAssert not graph.hovered_node_valid
graph.handle_event(UiEvent(
  kind: ui_event_mouse_move,
  x: 38,
  y: 30))
doAssert graph.hovered_node_valid
graph.handle_event(UiEvent(kind: ui_event_window_focus_lost))
doAssert not graph.hovered_node_valid

var raw_wheel = SdlMouseWheelEvent(
  kind: sdl_event_mouse_wheel,
  x: 0,
  y: 2,
  mouse_x: 8,
  mouse_y: 9)
let normalized_wheel = to_ui_event(cast[ptr SdlEvent](addr raw_wheel))
doAssert normalized_wheel.kind == ui_event_mouse_wheel
doAssert normalized_wheel.x == 8
doAssert normalized_wheel.y == 9
doAssert normalized_wheel.wheel_y == 2

raw_wheel.direction = sdl_mousewheel_flipped
let normalized_flipped_wheel = to_ui_event(
  cast[ptr SdlEvent](addr raw_wheel))
doAssert normalized_flipped_wheel.wheel_y == -2

clay_deinitialize()
dealloc(arena_memory)
