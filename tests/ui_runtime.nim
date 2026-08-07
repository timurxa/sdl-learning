import ../src/clay
import ../src/sdl
import ../src/ui

proc handle_error(error_data: ClayErrorData) {.cdecl.} =
  doAssert false, $error_data.error_type

var arena_memory: pointer

proc setup_clay(): ptr ClayContext =
  let memory_size = clay_min_memory_size()
  arena_memory = alloc0(int(memory_size))
  let arena = clay_create_arena_with_capacity_and_memory(
    memory_size,
    arena_memory)
  result = clay_initialize(
    arena,
    clay_dimensions(100, 100),
    ClayErrorHandler(
      error_handler_function: handle_error,
      user_data: nil))

discard setup_clay()

var raw_mouse_event = SdlMouseMotionEvent(
  kind: sdl_event_mouse_motion,
  x: 12,
  y: 34)
let normalized_mouse_event = to_ui_event(cast[ptr SdlEvent](addr raw_mouse_event))
doAssert normalized_mouse_event.kind == ui_event_mouse_move
doAssert normalized_mouse_event.x == 12
doAssert normalized_mouse_event.y == 34

var raw_text_event = SdlTextInputEvent(
  kind: sdl_event_text_input,
  text: "copied")
let normalized_text_event = to_ui_event(cast[ptr SdlEvent](addr raw_text_event))
doAssert normalized_text_event.text == "copied"

let state = new_ui_state()
let field_id = clay_id("ui_test_field")
state.register_text_field("test", field_id, initial_value = "abc")

clay_begin_layout()
clay_open_element_with_id(field_id)
clay_configure_open_element(declaration(
  layout = layout(sizing = sizing(fixed(80), fixed(20)))))
clay_close_element()
discard clay_end_layout(0)

state.enqueue_event(UiEvent(
  kind: ui_event_mouse_button_down,
  x: 5,
  y: 5,
  pointer_down: true))
state.enqueue_event(UiEvent(kind: ui_event_text_input, text: "x"))
state.prepare_frame()
doAssert state.focused_field == "test"
doAssert state.text_field_value("test") == "abcx"

state.enqueue_event(UiEvent(kind: ui_event_key_down, key: sdl_key_left))
state.enqueue_event(UiEvent(kind: ui_event_key_down, key: sdl_key_backspace))
state.prepare_frame()
doAssert state.text_field_value("test") == "abx"

state.enqueue_event(UiEvent(kind: ui_event_key_down, key: sdl_key_return))
state.prepare_frame()
var action: UiAction
doAssert state.next_action(action)
doAssert action.kind == ui_action_text_field_submitted
doAssert action.text_field_id == "test"
state.clear_text_field("test")
doAssert state.text_field_value("test") == ""
state.enqueue_event(UiEvent(kind: ui_event_key_down, key: sdl_key_kp_enter))
state.prepare_frame()
doAssert state.next_action(action)
doAssert action.kind == ui_action_text_field_submitted
doAssert action.text_field_id == "test"

let scroll_id = clay_id("ui_scroll_test")
state.enqueue_event(UiEvent(
  kind: ui_event_mouse_move,
  x: 5,
  y: 5,
  pointer_down: false))
state.prepare_frame()
clay_begin_layout()
clay_open_element_with_id(scroll_id)
var scroll_declaration = declaration(
  layout = layout(
    sizing = sizing(fixed(80), fixed(20)),
    layout_direction = clay_top_to_bottom),
  clip = ClayClipElementConfig(
    vertical: true,
    child_offset: clay_get_scroll_offset()))
clay_configure_open_element(scroll_declaration)
for child_index in 0 ..< 3:
  element(clay_id_with_index("ui_scroll_child", uint32(child_index))):
    layout:
      sizing:
        width = fixed(80)
        height = fixed(20)
clay_close_element()
discard clay_end_layout(0)

state.enqueue_event(UiEvent(
  kind: ui_event_mouse_wheel,
  x: 5,
  y: 5,
  wheel_y: 1))
state.prepare_frame()
clay_begin_layout()
clay_open_element_with_id(scroll_id)
scroll_declaration.clip.child_offset = clay_get_scroll_offset()
clay_configure_open_element(scroll_declaration)
for child_index in 0 ..< 3:
  element(clay_id_with_index("ui_scroll_child", uint32(child_index))):
    layout:
      sizing:
        width = fixed(80)
        height = fixed(20)
clay_close_element()
discard clay_end_layout(0)
let scroll_data = clay_get_scroll_container_data(scroll_id)
doAssert scroll_data.found
doAssert scroll_data.scroll_position[].y < 0

clay_deinitialize()
dealloc(arena_memory)
