## Low-level FreeType 2 bindings.
##
## These declarations deliberately preserve FreeType ownership: no Nim finalizers
## are installed. `ft_init_free_type` creates a library released by
## `ft_done_free_type`; `ft_new_face` and `ft_new_memory_face` create faces
## released by `ft_done_face`. For `ft_new_memory_face`, the supplied bytes are
## borrowed and must remain alive until after `ft_done_face`.

{.passC: "-I/opt/homebrew/include/freetype2".}
{.passL: "-L/opt/homebrew/lib -lfreetype".}
{.emit: """
#include <stdint.h>
#include <string.h>
#include <ft2build.h>
#include FT_FREETYPE_H

static FT_Error ft_prepare_glyph_bitmap(FT_Face face, FT_UInt glyph_index,
    FT_UInt pixel_size) {
    FT_Error error = FT_Set_Pixel_Sizes(face, 0, pixel_size);
    if (error != 0) {
        return error;
    }
    return FT_Load_Glyph(face, glyph_index,
        FT_LOAD_RENDER | FT_LOAD_TARGET_NORMAL);
}

int ft_get_glyph_bitmap_metrics(FT_Face face, FT_UInt glyph_index,
    FT_UInt pixel_size, uint32_t *width, uint32_t *rows,
    int32_t *left, int32_t *top) {
    FT_Error error = ft_prepare_glyph_bitmap(face, glyph_index, pixel_size);
    if (error != 0) {
        return (int)error;
    }

    FT_Bitmap *bitmap = &face->glyph->bitmap;
    *width = bitmap->width;
    *rows = bitmap->rows;
    *left = face->glyph->bitmap_left;
    *top = face->glyph->bitmap_top;
    return 0;
}

int ft_copy_glyph_bitmap(FT_Face face, FT_UInt glyph_index,
    FT_UInt pixel_size, uint8_t *destination, uint32_t destination_capacity) {
    FT_Error error = ft_prepare_glyph_bitmap(face, glyph_index, pixel_size);
    if (error != 0) {
        return (int)error;
    }

    FT_Bitmap *bitmap = &face->glyph->bitmap;
    uint32_t required = bitmap->width * bitmap->rows;
    if (destination == NULL || destination_capacity < required) {
        return 1;
    }

    for (uint32_t row = 0; row < bitmap->rows; ++row) {
        const unsigned char *source_row;
        if (bitmap->pitch >= 0) {
            source_row = bitmap->buffer + row * bitmap->pitch;
        } else {
            source_row = bitmap->buffer + (bitmap->rows - 1 - row) * (-bitmap->pitch);
        }

        if (bitmap->pixel_mode == FT_PIXEL_MODE_GRAY) {
            memcpy(destination + row * bitmap->width, source_row, bitmap->width);
        } else if (bitmap->pixel_mode == FT_PIXEL_MODE_MONO) {
            for (uint32_t column = 0; column < bitmap->width; ++column) {
                destination[row * bitmap->width + column] =
                    (source_row[column >> 3] & (0x80 >> (column & 7))) ? 255 : 0;
            }
        } else {
            return 1;
        }
    }
    return 0;
}
""".}

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

proc ft_get_glyph_bitmap_metrics*(face: FtFace; glyph_index, pixel_size: FtUInt;
    width, rows: ptr uint32; left, top: ptr int32): FtError {.
    importc: "ft_get_glyph_bitmap_metrics".}
proc ft_copy_glyph_bitmap*(face: FtFace; glyph_index, pixel_size: FtUInt;
    destination: ptr uint8; destination_capacity: uint32): FtError {.
    importc: "ft_copy_glyph_bitmap".}
