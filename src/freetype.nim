## Low-level FreeType 2 bindings.
##
## These declarations deliberately preserve FreeType ownership: no Nim finalizers
## are installed. `ft_init_free_type` creates a library released by
## `ft_done_free_type`; `ft_new_face` and `ft_new_memory_face` create faces
## released by `ft_done_face`. For `ft_new_memory_face`, the supplied bytes are
## borrowed and must remain alive until after `ft_done_face`.

{.passC: "-I/opt/homebrew/include/freetype2".}
{.passL: "-L/opt/homebrew/lib -lfreetype".}

type
  FtError* = cint
  FtInt32* = int32
  FtUInt* = cuint
  FtULong* = culong
  FtLong* = clong
  FtF26Dot6* = clong

  FtLibrary* {.importc: "FT_Library", header: "ft2build.h".} = ptr FtLibraryRec
  FtLibraryRec* {.importc: "struct FT_LibraryRec_", incompleteStruct,
      header: "freetype/freetype.h".} = object
  FtFace* {.importc: "FT_Face", header: "ft2build.h".} = ptr FtFaceRec
  FtFaceRec* {.importc: "struct FT_FaceRec_", incompleteStruct,
      header: "freetype/freetype.h".} = object

const
  ft_load_default* = FtInt32(0)
  ft_load_no_scale* = FtInt32(1 shl 0)
  ft_load_no_hinting* = FtInt32(1 shl 1)
  ft_load_render* = FtInt32(1 shl 2)
  ft_load_no_bitmap* = FtInt32(1 shl 3)

proc ft_init_free_type*(library: ptr FtLibrary): FtError {.
    importc: "FT_Init_FreeType", header: "freetype/freetype.h".}
proc ft_done_free_type*(library: FtLibrary): FtError {.
    importc: "FT_Done_FreeType", header: "freetype/freetype.h".}

proc ft_new_face*(library: FtLibrary; filepathname: cstring; face_index: FtLong;
    face: ptr FtFace): FtError {.importc: "FT_New_Face", header: "freetype/freetype.h".}
proc ft_new_memory_face*(library: FtLibrary; file_base: ptr uint8;
    file_size, face_index: FtLong; face: ptr FtFace): FtError {.
    importc: "FT_New_Memory_Face", header: "freetype/freetype.h".}
proc ft_reference_face*(face: FtFace): FtError {.
    importc: "FT_Reference_Face", header: "freetype/freetype.h".}
proc ft_done_face*(face: FtFace): FtError {.
    importc: "FT_Done_Face", header: "freetype/freetype.h".}

proc ft_set_char_size*(face: FtFace; char_width, char_height: FtF26Dot6;
    horz_resolution, vert_resolution: FtUInt): FtError {.
    importc: "FT_Set_Char_Size", header: "freetype/freetype.h".}
proc ft_set_pixel_sizes*(face: FtFace; pixel_width, pixel_height: FtUInt): FtError {.
    importc: "FT_Set_Pixel_Sizes", header: "freetype/freetype.h".}
proc ft_get_char_index*(face: FtFace; charcode: FtULong): FtUInt {.
    importc: "FT_Get_Char_Index", header: "freetype/freetype.h".}
proc ft_load_glyph*(face: FtFace; glyph_index: FtUInt; load_flags: FtInt32): FtError {.
    importc: "FT_Load_Glyph", header: "freetype/freetype.h".}
proc ft_load_char*(face: FtFace; char_code: FtULong; load_flags: FtInt32): FtError {.
    importc: "FT_Load_Char", header: "freetype/freetype.h".}
