import ../src/clay
import ../src/utf8proc

var error_count: int
var last_error: ClayErrorType
var string_cache: ClayStringCache

proc measure_text(text: ClayStringSlice; config: ptr ClayTextElementConfig;
    user_data: pointer): ClayDimensions {.cdecl.} =
  discard config
  discard user_data
  ClayDimensions(width: cfloat(text.length), height: 1)

proc handle_error(error_data: ClayErrorData) {.cdecl.} =
  last_error = error_data.error_type
  inc error_count

proc make_message(frame_index: int): string =
  for word_index in 0 ..< 80:
    if word_index > 0:
      result.add(' ')
    result.add("frame")
    result.add($frame_index)
    result.add('_')
    result.add($word_index)

proc render_message(value: string) =
  clay_string_cache_begin(string_cache)
  clay_begin_layout()
  clay_open_element()
  clay_configure_open_element(clay_declaration(
    layout = clay_layout(
      sizing = clay_sizing(clay_sizing_fixed(120), clay_sizing_fit()),
    ),
  ))
  clay_open_text_element(clay_string(value), clay_text_config(
    font_size = 1,
    wrap_mode = clay_text_wrap_words,
  ))
  clay_close_element()
  discard clay_end_layout(0)
  clay_string_cache_end()

clay_set_max_measure_text_cache_word_count(256)
let memory_size = clay_min_memory_size()
let arena_memory = alloc0(int(memory_size))
let arena = clay_create_arena_with_capacity_and_memory(memory_size, arena_memory)
discard clay_initialize(
  arena,
  clay_dimensions(120, 4096),
  ClayErrorHandler(error_handler_function: handle_error, user_data: nil),
)
clay_set_measure_text_function(measure_text, nil)
clay_set_grapheme_boundary_function(utf8proc_next_grapheme_boundary, nil)

for frame_index in 0 ..< 32:
  render_message(make_message(frame_index))
  doAssert error_count == 0
  doAssert last_error != clay_error_type_text_measurement_capacity_exceeded

clay_string_cache_deinit(string_cache)
clay_deinitialize()
dealloc(arena_memory)
