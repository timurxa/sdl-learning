## Minimal utf8proc bindings used for UAX #29 extended grapheme boundaries.

import clay

{.passC: "-I/opt/homebrew/include".}
{.passL: "-L/opt/homebrew/lib -lutf8proc".}

type
  Utf8ProcCodepoint* = int32
  Utf8ProcSize* = int
  Utf8ProcBool* = uint8

proc utf8proc_iterate*(text: ptr uint8; text_length: Utf8ProcSize;
    codepoint: ptr Utf8ProcCodepoint): Utf8ProcSize {.importc, header: "utf8proc.h".}
proc utf8proc_grapheme_break_stateful*(codepoint_1, codepoint_2: Utf8ProcCodepoint;
    state: ptr Utf8ProcCodepoint): Utf8ProcBool {.importc, header: "utf8proc.h".}

proc utf8proc_next_grapheme_boundary*(text: ClayStringSlice; offset: int32;
    user_data: pointer): int32 {.cdecl.} =
  discard user_data
  if offset >= text.length:
    return text.length
  if offset < 0:
    return 0

  let bytes = cast[ptr UncheckedArray[uint8]](text.chars)
  var previous_codepoint: Utf8ProcCodepoint
  let first_length = utf8proc_iterate(
    addr bytes[int(offset)],
    Utf8ProcSize(text.length - offset),
    addr previous_codepoint,
  )
  if first_length <= 0:
    return min(offset + 1, text.length)

  var current_offset = offset + int32(first_length)
  var state: Utf8ProcCodepoint
  while current_offset < text.length:
    var next_codepoint: Utf8ProcCodepoint
    let next_length = utf8proc_iterate(
      addr bytes[int(current_offset)],
      Utf8ProcSize(text.length - current_offset),
      addr next_codepoint,
    )
    if next_length <= 0:
      return min(current_offset + 1, text.length)
    if utf8proc_grapheme_break_stateful(
        previous_codepoint, next_codepoint, addr state) != 0:
      return current_offset
    previous_codepoint = next_codepoint
    current_offset += int32(next_length)
  text.length
