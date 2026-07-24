## Low-level HarfBuzz bindings, including the FreeType bridge.
##
## HarfBuzz objects are reference counted. Call the matching `*_destroy` proc
## once for each owned reference; `*_reference` adds one. Glyph arrays returned
## by a buffer are borrowed views and become invalid after the buffer changes or
## is destroyed. `hb_ft_font_create_referenced` holds an FT_Face reference until
## the HarfBuzz font is destroyed.

import freetype

{.passC: "-I/opt/homebrew/include/harfbuzz -I/opt/homebrew/include/freetype2".}
{.passL: "-L/opt/homebrew/lib -lharfbuzz".}

type
  HbBool* = cint
  HbCodepoint* = uint32
  HbMask* = uint32
  HbPosition* = int32
  HbTag* = uint32
  HbDirection* = cint
  HbScript* = uint32
  HbLanguage* = ptr HbLanguageImpl
  HbLanguageImpl* {.importc: "struct hb_language_impl_t", incompleteStruct,
      header: "hb.h".} = object

  HbBuffer* {.importc: "hb_buffer_t", incompleteStruct, header: "hb.h".} = object
  HbFace* {.importc: "hb_face_t", incompleteStruct, header: "hb.h".} = object
  HbFont* {.importc: "hb_font_t", incompleteStruct, header: "hb.h".} = object

  HbFeature* {.importc: "hb_feature_t", header: "hb.h".} = object
    tag*: HbTag
    value*: uint32
    start*: cuint
    `end`*: cuint

  HbGlyphInfo* {.importc: "hb_glyph_info_t", header: "hb.h".} = object
    codepoint*: HbCodepoint
    mask*: HbMask
    cluster*: uint32
    var1*: uint32
    var2*: uint32

  HbGlyphPosition* {.importc: "hb_glyph_position_t", header: "hb.h".} = object
    x_advance*: HbPosition
    y_advance*: HbPosition
    x_offset*: HbPosition
    y_offset*: HbPosition
    var_int*: uint32

const
  hb_direction_invalid* = HbDirection(0)
  hb_direction_ltr* = HbDirection(4)
  hb_direction_rtl* = HbDirection(5)
  hb_direction_ttb* = HbDirection(6)
  hb_direction_btt* = HbDirection(7)
  hb_feature_global_start* = cuint(0)
  hb_feature_global_end* = high(cuint)

proc hb_language_from_string*(value: cstring; length: cint): HbLanguage {.
    importc, header: "hb.h".}

proc hb_buffer_create*(): ptr HbBuffer {.importc, header: "hb.h".}
proc hb_buffer_reference*(buffer: ptr HbBuffer): ptr HbBuffer {.importc, header: "hb.h".}
proc hb_buffer_destroy*(buffer: ptr HbBuffer) {.importc, header: "hb.h".}
proc hb_buffer_reset*(buffer: ptr HbBuffer) {.importc, header: "hb.h".}
proc hb_buffer_set_direction*(buffer: ptr HbBuffer; direction: HbDirection) {.importc, header: "hb.h".}
proc hb_buffer_set_script*(buffer: ptr HbBuffer; script: HbScript) {.importc, header: "hb.h".}
proc hb_buffer_set_language*(buffer: ptr HbBuffer; language: HbLanguage) {.importc, header: "hb.h".}
proc hb_buffer_guess_segment_properties*(buffer: ptr HbBuffer) {.importc, header: "hb.h".}
proc hb_buffer_add_utf8*(buffer: ptr HbBuffer; text: cstring; text_length: cint;
    item_offset: cuint; item_length: cint) {.importc, header: "hb.h".}
proc hb_buffer_get_length*(buffer: ptr HbBuffer): cuint {.importc, header: "hb.h".}
proc hb_buffer_get_glyph_infos*(buffer: ptr HbBuffer; length: ptr cuint): ptr HbGlyphInfo {.
    importc, header: "hb.h".}
proc hb_buffer_get_glyph_positions*(buffer: ptr HbBuffer; length: ptr cuint): ptr HbGlyphPosition {.
    importc, header: "hb.h".}

proc hb_face_reference*(face: ptr HbFace): ptr HbFace {.importc, header: "hb.h".}
proc hb_face_destroy*(face: ptr HbFace) {.importc, header: "hb.h".}
proc hb_font_create*(face: ptr HbFace): ptr HbFont {.importc, header: "hb.h".}
proc hb_font_reference*(font: ptr HbFont): ptr HbFont {.importc, header: "hb.h".}
proc hb_font_destroy*(font: ptr HbFont) {.importc, header: "hb.h".}
proc hb_font_set_scale*(font: ptr HbFont; x_scale, y_scale: cint) {.importc, header: "hb.h".}
proc hb_font_get_scale*(font: ptr HbFont; x_scale, y_scale: ptr cint) {.importc, header: "hb.h".}

proc hb_ft_face_create_referenced*(face: FtFace): ptr HbFace {.
    importc, header: "hb-ft.h".}
proc hb_ft_font_create_referenced*(face: FtFace): ptr HbFont {.
    importc, header: "hb-ft.h".}
proc hb_ft_font_get_ft_face*(font: ptr HbFont): FtFace {.
    importc, header: "hb-ft.h".}
proc hb_ft_font_changed*(font: ptr HbFont) {.importc, header: "hb-ft.h".}

proc hb_shape*(font: ptr HbFont; buffer: ptr HbBuffer; features: ptr HbFeature;
    num_features: cuint) {.importc, header: "hb.h".}
