import ../src/clay
import ../src/ui

proc handle_error(error_data: ClayErrorData) {.cdecl.} =
  doAssert false, $error_data.error_type

let memory_size = clay_min_memory_size()
let arena_memory = alloc0(int(memory_size))
let arena = clay_create_arena_with_capacity_and_memory(
  memory_size, arena_memory)
discard clay_initialize(
  arena,
  clay_dimensions(100, 100),
  ClayErrorHandler(error_handler_function: handle_error, user_data: nil))

let state = new_ui_state()
let button_id = clay_id("ui_test_button")
state.register_button("test_button", button_id)

clay_begin_layout()
element("root"):
  layout:
    sizing:
      width = grow()
      height = grow()
  element(button_id):
    layout:
      sizing:
        width = fixed(40)
        height = fixed(20)
let commands = clay_end_layout(0)
discard commands

state.enqueue_event(UiEvent(
  kind: ui_event_mouse_button_down,
  x: 5,
  y: 5,
  pointer_down: true))
state.enqueue_event(UiEvent(
  kind: ui_event_mouse_button_up,
  x: 5,
  y: 5,
  pointer_down: false))
state.prepare_frame()

var action: UiAction
doAssert state.next_action(action)
doAssert action.kind == ui_action_button_clicked
doAssert action.button_id == "test_button"
doAssert not state.next_action(action)

clay_deinitialize()
dealloc(arena_memory)
