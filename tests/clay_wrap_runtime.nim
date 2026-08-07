import ../src/clay
import ../src/utf8proc
import std/strutils

var last_error: ClayErrorType
var error_count: int
var measure_call_count: int
var unstable_boundary_calls: int

proc measure_text(text: ClayStringSlice; config: ptr ClayTextElementConfig;
    user_data: pointer): ClayDimensions {.cdecl.} =
  discard config
  discard user_data
  inc measure_call_count
  ClayDimensions(width: cfloat(text.length), height: 1)

proc handle_error(error_data: ClayErrorData) {.cdecl.} =
  last_error = error_data.error_type
  inc error_count

proc invalid_grapheme_boundary(text: ClayStringSlice; offset: int32;
    user_data: pointer): int32 {.cdecl.} =
  discard text
  discard user_data
  offset

proc unstable_grapheme_boundary(text: ClayStringSlice; offset: int32;
    user_data: pointer): int32 {.cdecl.} =
  discard text
  discard user_data
  inc unstable_boundary_calls
  if unstable_boundary_calls <= 100:
    offset + 1
  else:
    offset

proc clay_string_contents(value: ClayString): string =
  result = newString(int(value.length))
  if value.length > 0:
    copyMem(addr result[0], value.chars, int(value.length))

var arena_memory: pointer
var clay_arena: ClayArena

proc text_lines(value: string; width: int; wrap_mode: ClayTextElementConfigWrapMode): seq[string] =
  clay_begin_layout()
  clay_open_element()
  clay_configure_open_element(clay_declaration(
    layout = clay_layout(
      sizing = clay_sizing(clay_sizing_fixed(width), clay_sizing_fit()),
    ),
  ))
  clay_open_text_element(clay_string(value), clay_text_config(
    font_size = 1,
    wrap_mode = wrap_mode,
  ))
  clay_close_element()
  let commands = clay_end_layout(0)
  for command in commands:
    if command.command_type == clay_render_command_type_text:
      let slice = command.render_data.text.string_contents
      var line = newString(int(slice.length))
      if slice.length > 0:
        copyMem(addr line[0], slice.chars, int(slice.length))
      result.add(line)

clay_set_max_measure_text_cache_word_count(32)
let memory_size = clay_min_memory_size()
arena_memory = alloc0(int(memory_size))
clay_arena = clay_create_arena_with_capacity_and_memory(memory_size, arena_memory)
discard clay_initialize(clay_arena, clay_dimensions(100, 100), ClayErrorHandler(
  error_handler_function: handle_error,
  user_data: nil,
))
clay_set_layout_dimensions(clay_dimensions(100, 100))
clay_set_measure_text_function(measure_text, nil)
clay_set_grapheme_boundary_function(utf8proc_next_grapheme_boundary, nil)

var string_cache: ClayStringCache
clay_string_cache_begin(string_cache)
let retained_string = clay_string("PANEL A FRAME 1")
discard clay_string("AFTER PANEL A FRAME 1")
clay_string_cache_end()

clay_string_cache_begin(string_cache)
discard clay_string("AFTER PANEL A FRAME 2")
doAssert clay_string_contents(retained_string) == "PANEL A FRAME 1"
clay_string_cache_end()
clay_string_cache_deinit(string_cache)

doAssert text_lines("abcdef", 2, clay_text_wrap_words_and_graphemes) == @[
  "ab", "cd", "ef"
]
doAssert text_lines("abcdef", 2, clay_text_wrap_words) == @["abcdef"]
doAssert text_lines("e\u0301x", 1, clay_text_wrap_words_and_graphemes) == @[
  "e\u0301", "x"
]
doAssert text_lines("👩‍👩‍👧‍👦x", 1, clay_text_wrap_words_and_graphemes) == @[
  "👩‍👩‍👧‍👦", "x"
]
doAssert text_lines("🇺🇸x", 1, clay_text_wrap_words_and_graphemes) == @[
  "🇺🇸", "x"
]
doAssert text_lines("क्षx", 1, clay_text_wrap_words_and_graphemes) == @[
  "क्ष", "x"
]

error_count = 0
let long_lines = text_lines(repeat('a', 100), 2, clay_text_wrap_words_and_graphemes)
doAssert long_lines.len == 50
for line in long_lines:
  doAssert line == "aa"
doAssert error_count == 0

let long_emoji = repeat("👩‍👩‍👧‍👦", 40)
let long_emoji_lines = text_lines(long_emoji, 1, clay_text_wrap_words_and_graphemes)
var long_emoji_text = ""
for line in long_emoji_lines:
  long_emoji_text.add(line)
doAssert long_emoji_lines.len == 40
doAssert long_emoji_text == long_emoji
doAssert error_count == 0

clay_set_grapheme_boundary_function(unstable_grapheme_boundary, nil)
unstable_boundary_calls = 0
error_count = 0
let unstable_lines = text_lines(repeat('a', 100), 2, clay_text_wrap_words_and_graphemes)
var unstable_text = ""
for line in unstable_lines:
  unstable_text.add(line)
doAssert unstable_text == repeat('a', 100)
doAssert error_count == 1

clay_set_grapheme_boundary_function(utf8proc_next_grapheme_boundary, nil)
clay_reset_measure_text_cache()
measure_call_count = 0
discard text_lines("abcdef", 2, clay_text_wrap_words_and_graphemes)
let first_measure_call_count = measure_call_count
discard text_lines("abcdef", 2, clay_text_wrap_words_and_graphemes)
doAssert measure_call_count < first_measure_call_count * 2

clay_set_grapheme_boundary_function(invalid_grapheme_boundary, nil)
clay_reset_measure_text_cache()
error_count = 0
discard text_lines("abcdef", 2, clay_text_wrap_words_and_graphemes)
doAssert error_count == 1
doAssert last_error == clay_error_type_grapheme_boundary_function_invalid

clay_set_grapheme_boundary_function(nil, nil)
clay_reset_measure_text_cache()
error_count = 0
discard text_lines("abcdef", 2, clay_text_wrap_words_and_graphemes)
doAssert error_count == 1
doAssert last_error == clay_error_type_grapheme_boundary_function_not_provided

dealloc(arena_memory)
