import "../src/clay"

proc measure_text(text: ClayStringSlice; config: ptr ClayTextElementConfig;
    user_data: pointer): ClayDimensions {.cdecl.} =
  discard config
  discard user_data
  ClayDimensions(width: cfloat(text.length), height: 1)

proc set_final_state(initial_state: ClayTransitionData;
    properties: ClayTransitionProperty): ClayTransitionData {.cdecl.} =
  discard properties
  initial_state

var exit_should_complete = false

proc maybe_complete(arguments: ClayTransitionCallbackArguments): bool {.cdecl.} =
  discard arguments
  exit_should_complete

proc handle_error(error_data: ClayErrorData) {.cdecl.} =
  doAssert error_data.error_type != clay_error_type_internal_error

proc command_text(commands: ClayRenderCommandArray): seq[string] =
  for command in commands:
    if command.command_type != clay_render_command_type_text:
      continue
    let slice = command.render_data.text.string_contents
    var value = newString(int(slice.length))
    if slice.length > 0:
      copyMem(addr value[0], slice.chars, int(slice.length))
    result.add(value)

let transition = ClayTransitionElementConfig(
  handler: maybe_complete,
  duration: 1,
  properties: clay_transition_property_x,
  exit: ClayTransitionExit(
    set_final_state: set_final_state,
    trigger: clay_transition_exit_trigger_when_parent_exits,
    sibling_ordering: clay_exit_transition_ordering_natural_order))

let root_declaration = clay_declaration(
  layout = clay_layout(
    sizing = clay_sizing(clay_sizing_fixed(100), clay_sizing_fit()),
    layout_direction = clay_left_to_right))
let panel_declaration = clay_declaration(
  layout = clay_layout(
    sizing = clay_sizing(clay_sizing_fixed(40), clay_sizing_fit())),
  transition = transition)
let live_declaration = clay_declaration(
  layout = clay_layout(
    sizing = clay_sizing(clay_sizing_fixed(40), clay_sizing_fit())))
let child_declaration = clay_declaration(
  layout = clay_layout(
    sizing = clay_sizing(clay_sizing_fixed(40), clay_sizing_fit())))

var arena_memory = alloc0(int(clay_min_memory_size()))
var arena = clay_create_arena_with_capacity_and_memory(
  clay_min_memory_size(), arena_memory)
var cache: ClayStringCache
discard clay_initialize(arena, clay_dimensions(100, 100), ClayErrorHandler(
  error_handler_function: handle_error,
  user_data: nil))
clay_set_measure_text_function(measure_text, nil)

for frame_index in 0 .. 11:
  if frame_index == 8:
    exit_should_complete = true
  if frame_index == 9:
    exit_should_complete = false
  if frame_index == 11:
    exit_should_complete = true
  clay_string_cache_begin(cache)
  doAssert clay_string_cache_generation_count(cache) <= 2
  clay_begin_layout()
  clay_open_element_with_id(clay_id_local("root"))
  clay_configure_open_element(root_declaration)

  let showing_panel = frame_index < 2 or frame_index == 9
  if showing_panel:
    let panel_label = if frame_index == 9: "REUSE" else: $frame_index
    clay_open_element_with_id(clay_id_local("panel-" & "stable"))
    clay_configure_open_element(panel_declaration)
    clay_open_text_element(
      clay_string("PANEL_" & panel_label),
      clay_text_config(font_size = 1))
    clay_open_element_with_id(clay_id_local("child-" & "stable"))
    clay_configure_open_element(child_declaration)
    clay_open_text_element(
      clay_string("CHILD_" & panel_label),
      clay_text_config(font_size = 1))
    clay_close_element()
    clay_close_element()

  clay_open_element_with_id(clay_id_local("live"))
  clay_configure_open_element(live_declaration)
  clay_open_text_element(
    clay_string("LIVE_FRAME_" & $frame_index),
    clay_text_config(font_size = 1))
  clay_close_element()
  clay_close_element()

  let commands = clay_end_layout(0.016)
  clay_string_cache_end()
  let texts = command_text(commands)
  doAssert texts.contains("LIVE_FRAME_" & $frame_index)
  if frame_index >= 2 and frame_index <= 7:
    doAssert texts.contains("PANEL_1")
    doAssert texts.contains("CHILD_1")
  if frame_index >= 9 and frame_index <= 10:
    doAssert texts.contains("PANEL_REUSE")
    doAssert texts.contains("CHILD_REUSE")

clay_deinitialize()
clay_string_cache_deinit(cache)
dealloc(arena_memory)
