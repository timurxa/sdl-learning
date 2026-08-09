import ../src/clay
import ../src/utf8proc
import std/strutils

var last_error: ClayErrorType
var error_count: int
var string_cache: ClayStringCache

proc measure_text(text: ClayStringSlice; config: ptr ClayTextElementConfig;
    user_data: pointer): ClayDimensions {.cdecl.} =
  discard config
  discard user_data
  ClayDimensions(width: cfloat(text.length), height: 1)

proc handle_error(error_data: ClayErrorData) {.cdecl.} =
  last_error = error_data.error_type
  inc error_count

proc make_multiline_text(size: int): string =
  const line_length = 65
  result = newString(size)
  for index in 0 ..< size:
    result[index] = if index mod line_length == line_length - 1: '\n' else: 'a'

proc render_text(value: string; width: int): tuple[rendered: string, line_lengths: seq[int]] =
  clay_string_cache_begin(string_cache)
  clay_begin_layout()
  clay_open_element()
  clay_configure_open_element(clay_declaration(
    layout = clay_layout(
      sizing = clay_sizing(clay_sizing_fixed(width), clay_sizing_fit()),
    ),
  ))
  clay_open_text_element(clay_string(value), clay_text_config(
    font_size = 1,
    wrap_mode = clay_text_wrap_words_and_graphemes,
  ))
  clay_close_element()
  let commands = clay_end_layout(0)
  for command in commands:
    if command.command_type != clay_render_command_type_text:
      continue
    let slice = command.render_data.text.string_contents
    if slice.length == 0:
      continue
    let previous_length = result.rendered.len
    result.rendered.setLen(previous_length + int(slice.length))
    copyMem(addr result.rendered[previous_length], slice.chars, int(slice.length))
    result.line_lengths.add(int(slice.length))
  clay_string_cache_end()

proc assert_wrapped(value: string; width: int) =
  let output = render_text(value, width)
  let expected = value.replace("\n", "")
  doAssert output.rendered == expected
  for line_length in output.line_lengths:
    doAssert line_length > 0 and line_length <= width

proc assert_no_measure_cache_error() =
  doAssert error_count == 0
  doAssert last_error != clay_error_type_text_measurement_capacity_exceeded

clay_set_max_measure_text_cache_word_count(131072)
let memory_size = clay_min_memory_size()
let arena_memory = alloc0(int(memory_size))
let arena = clay_create_arena_with_capacity_and_memory(memory_size, arena_memory)
discard clay_initialize(
  arena,
  clay_dimensions(128, 4096),
  ClayErrorHandler(error_handler_function: handle_error, user_data: nil),
)
clay_set_measure_text_function(measure_text, nil)
clay_set_grapheme_boundary_function(utf8proc_next_grapheme_boundary, nil)

for size in [4 * 1024, 16 * 1024, 32 * 1024]:
  let value = make_multiline_text(size)
  assert_wrapped(value, 32)
  assert_no_measure_cache_error()

var growing_message = ""
for frame_index in 0 ..< 256:
  growing_message.add("frame")
  growing_message.add($frame_index)
  growing_message.add(":")
  growing_message.add(repeat('b', 160))
  growing_message.add('\n')
  assert_wrapped(growing_message, 32)
  assert_no_measure_cache_error()

clay_string_cache_deinit(string_cache)
clay_deinitialize()
dealloc(arena_memory)
