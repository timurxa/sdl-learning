import std/math
import std/os
import std/tables
import clay, sdl
import freetype, harfbuzz

type
  ViewFrame* = object
    logical_width*: uint32
    logical_height*: uint32
    pixel_width*: uint32
    pixel_height*: uint32
    display_scale*: float32
    delta_time*: float32
    string_cache_generation*: uint64
    string_cache_generation_count*: int
    exiting_transitions*: bool

  PrepareFrameProc* = proc()
  BuildElementsProc* = proc(frame: ViewFrame)
  FinishFrameProc* = proc()

  QuadVertex = object
    corners: array[2, uint16]
  SpriteInstance = object
    origin: array[2, uint16]
    size: array[2, uint16]
    color: array[4, uint8]
    depth: float32
  TextInstance = object
    origin: array[2, uint16]
    size: array[2, uint16]
    color: array[4, uint8]
    uv: array[4, float32]
    depth: float32
  Rect = object
    x, w, y, h: float32
  PixelRect = object
    origin: array[2, uint16]
    size: array[2, uint16]
  FrameData = object
    viewport_size: array[2, float32]
    inverse_viewport_size: array[2, float32]
  FontID = uint16
  TextKey = object
    raw: string
    pixel_size: uint16
    font_id: FontID
    letter_spacing: uint16
    line_height: uint16
  GlyphHandle = uint32
  GlyphKey = object
    font_id: FontID
    pixel_size: uint16
    glyph_handle: GlyphHandle
  GlyphCacheEntry = object
    atlas_x, atlas_y: uint32
    atlas_width, atlas_height: uint32
    bearing_x, bearing_y: int32
    bitmap: seq[uint8]
    rasterized: bool
  TextGlyph = object
    glyph_handle: GlyphHandle
    x_advance, y_advance: int32
    x_offset, y_offset: int32
  TextLayout = object
    width, height: float32
    glyphs: seq[TextGlyph]
  GlyphAtlasUpload = object
    x, y, width, height: uint32
    source_offset: uint32
  GlyphAtlas = object
    width, height: uint32
    padding: uint32
    cursor_x, cursor_y, row_height: uint32
    pixels: seq[uint8]
    pending_uploads: seq[GlyphAtlasUpload]
    texture: ptr SdlGpuTexture
    transfer_buffer: ptr SdlGpuTransferBuffer
    transfer_capacity: uint32
  Renderer* = ref object
    window: ptr SdlWindow
    display_scale: float32
    gpu_device: ptr SdlGpuDevice
    opaque_pipeline: ptr SdlGpuGraphicsPipeline
    coverage_pipeline: ptr SdlGpuGraphicsPipeline
    coverage_sampler: ptr SdlGpuSampler
    depth_texture: ptr SdlGpuTexture
    depth_texture_width, depth_texture_height: uint32
    quad_vertex_buffer: ptr SdlGpuBuffer
    instance_buffer: ptr SdlGpuBuffer
    instance_transfer_buffer: ptr SdlGpuTransferBuffer
    instance_buffer_capacity: uint32
    text_instance_buffer: ptr SdlGpuBuffer
    text_instance_transfer_buffer: ptr SdlGpuTransferBuffer
    text_instance_buffer_capacity: uint32
    quad_vertex_buffer_initialized: bool
    instance_data: seq[SpriteInstance]
    text_instance_data: seq[TextInstance]
    clip_stack: seq[Rect]
    ft_library: FtLibrary
    ft_face: FtFace
    hb_font: ptr HbFont
    hb_buffer: ptr HbBuffer
    font_ready: bool
    glyph_cache: Table[GlyphKey, GlyphCacheEntry]
    text_cache: Table[TextKey, TextLayout]
    glyph_atlas: GlyphAtlas
    clear_color: ClayColor

const
  project_dir = currentSourcePath().parentDir.parentDir
  quad_vertices = [
    QuadVertex(corners: [0, 0]),
    QuadVertex(corners: [1, 0]),
    QuadVertex(corners: [1, 1]),

    QuadVertex(corners: [0, 0]),
    QuadVertex(corners: [1, 1]),
    QuadVertex(corners: [0, 1]),
  ]
  shader_source_dir = project_dir / "shaders" / "src"
  shader_output_dir = project_dir / "shaders" / "compiled"
  default_font_path = "/Users/alex/Library/Fonts/JetBrainsMono-Regular.ttf"
  glyph_atlas_initial_size = 2048'u32
  glyph_atlas_padding = 1'u32


doAssert sizeof(SpriteInstance) == 16
doAssert sizeof(TextInstance) == 32
doAssert offsetOf(TextInstance, uv) == 12
doAssert offsetOf(TextInstance, depth) == 28

static:
  discard staticExec("mkdir -p " & quoteShell(shader_output_dir))
  discard staticExec("shadercross " & quoteShell(shader_source_dir / "opaque.vert.hlsl") &
    " -s HLSL -d MSL -t vertex -o " &
    quoteShell(shader_output_dir / "opaque.vert.msl"))
  discard staticExec("shadercross " & quoteShell(shader_source_dir / "opaque.frag.hlsl") &
    " -s HLSL -d MSL -t fragment -o " &
    quoteShell(shader_output_dir / "opaque.frag.msl"))
  discard staticExec("shadercross " & quoteShell(shader_source_dir / "coverage.vert.hlsl") &
    " -s HLSL -d MSL -t vertex -o " &
    quoteShell(shader_output_dir / "coverage.vert.msl"))
  discard staticExec("shadercross " & quoteShell(shader_source_dir / "coverage.frag.hlsl") &
    " -s HLSL -d MSL -t fragment -o " &
    quoteShell(shader_output_dir / "coverage.frag.msl"))

const
  opaque_vertex_shader_code = staticRead(
    project_dir / "shaders" / "compiled" / "opaque.vert.msl"
  )
  opaque_fragment_shader_code = staticRead(
    project_dir / "shaders" / "compiled" / "opaque.frag.msl"
  )
  coverage_vertex_shader_code = staticRead(
    project_dir / "shaders" / "compiled" / "coverage.vert.msl"
  )
  coverage_fragment_shader_code = staticRead(
    project_dir / "shaders" / "compiled" / "coverage.frag.msl"
  )


var active_renderer: Renderer

proc new_renderer*(): Renderer =
  new(result)

template window: untyped = active_renderer.window
template display_scale: untyped = active_renderer.display_scale
template gpu_device: untyped = active_renderer.gpu_device
template opaque_pipeline: untyped = active_renderer.opaque_pipeline
template coverage_pipeline: untyped = active_renderer.coverage_pipeline
template coverage_sampler: untyped = active_renderer.coverage_sampler
template depth_texture: untyped = active_renderer.depth_texture
template depth_texture_width: untyped = active_renderer.depth_texture_width
template depth_texture_height: untyped = active_renderer.depth_texture_height
template quad_vertex_buffer: untyped = active_renderer.quad_vertex_buffer
template instance_buffer: untyped = active_renderer.instance_buffer
template instance_transfer_buffer: untyped = active_renderer.instance_transfer_buffer
template instance_buffer_capacity: untyped = active_renderer.instance_buffer_capacity
template text_instance_buffer: untyped = active_renderer.text_instance_buffer
template text_instance_transfer_buffer: untyped = active_renderer.text_instance_transfer_buffer
template text_instance_buffer_capacity: untyped = active_renderer.text_instance_buffer_capacity
template quad_vertex_buffer_initialized: untyped = active_renderer.quad_vertex_buffer_initialized
template instance_data: untyped = active_renderer.instance_data
template text_instance_data: untyped = active_renderer.text_instance_data
template clip_stack: untyped = active_renderer.clip_stack
template ft_library: untyped = active_renderer.ft_library
template ft_face: untyped = active_renderer.ft_face
template hb_font: untyped = active_renderer.hb_font
template hb_buffer: untyped = active_renderer.hb_buffer
template font_ready: untyped = active_renderer.font_ready
template glyph_cache: untyped = active_renderer.glyph_cache
template text_cache: untyped = active_renderer.text_cache
template glyph_atlas: untyped = active_renderer.glyph_atlas
template clear_color: untyped = active_renderer.clear_color

converter clay_bb_to_rect(clay_bb: ClayBoundingBox): Rect =
  result.x = float32(clay_bb.x)
  result.y = float32(clay_bb.y)
  result.w = float32(clay_bb.width)
  result.h = float32(clay_bb.height)

proc clip_rect(rect: var Rect; mask: Rect) =
  let right = min(
    rect.x + rect.w,
    mask.x + mask.w,
  )
  rect.x = max(rect.x, mask.x)
  rect.w = max(right - rect.x, 0)

  let bottom = min(
    rect.y + rect.h,
    mask.y + mask.h,
  )
  rect.y = max(rect.y, mask.y)
  rect.h = max(bottom - rect.y, 0)

  discard

proc is_empty(rect: Rect): bool = rect.w <= 0 or rect.h <= 0

proc checked_pixel_value(value: int): uint16 {.inline.} =
  if value < 0 or value > int(high(uint16)):
    raise newException(Defect, "UI coordinate exceeds uint16 instance range")
  uint16(value)

proc rounded_pixel_value(value, scale: float32): int {.inline.} =
  int(round(value * scale))

proc to_pixel_rect(rect: Rect; scale: float32): PixelRect =
  let left = rounded_pixel_value(rect.x, scale)
  let top = rounded_pixel_value(rect.y, scale)
  let right = rounded_pixel_value(rect.x + rect.w, scale)
  let bottom = rounded_pixel_value(rect.y + rect.h, scale)
  result.origin = [checked_pixel_value(left), checked_pixel_value(top)]
  result.size = [
    checked_pixel_value(max(right - left, 0)),
    checked_pixel_value(max(bottom - top, 0)),
  ]

proc is_empty(rect: PixelRect): bool = rect.size[0] == 0 or rect.size[1] == 0

proc scaled_font_pixel_size(pixel_size: uint16; scale: float32): uint16 =
  checked_pixel_value(max(
    int(round(float32(max(pixel_size, 1'u16)) * scale)),
    1,
  ))

proc read_display_scale(): float32 =
  let scale = float32(get_window_display_scale(window))
  if scale > 0: scale else: 1

proc destroy_font() =
  if hb_buffer != nil:
    hb_buffer_destroy(hb_buffer)
    hb_buffer = nil
  if hb_font != nil:
    hb_font_destroy(hb_font)
    hb_font = nil
  if ft_face != nil:
    discard ft_done_face(ft_face)
    ft_face = nil
  if ft_library != nil:
    discard ft_done_free_type(ft_library)
    ft_library = nil
  font_ready = false

proc init_font(): bool =
  if ft_init_free_type(addr ft_library) != 0:
    return false
  if ft_new_face(ft_library, default_font_path, 0, addr ft_face) != 0:
    destroy_font()
    return false

  hb_font = hb_ft_font_create_referenced(ft_face)
  hb_buffer = hb_buffer_create()
  if hb_font == nil or hb_buffer == nil:
    destroy_font()
    return false

  glyph_cache = initTable[GlyphKey, GlyphCacheEntry]()
  text_cache = initTable[TextKey, TextLayout]()
  font_ready = true
  true

proc clay_text_to_string(text: ClayStringSlice): string =
  let length = int(text.length)
  if length <= 0:
    return ""
  result = newString(length)
  copyMem(addr result[0], cast[pointer](text.chars), length)

proc make_text_key(
    text: ClayStringSlice;
    font_id, pixel_size, letter_spacing, line_height: uint16
  ): TextKey =
  let actual_pixel_size = max(pixel_size, 1'u16)
  result = TextKey(
    raw: clay_text_to_string(text),
    pixel_size: actual_pixel_size,
    font_id: FontID(font_id),
    letter_spacing: letter_spacing,
    line_height: if line_height > 0: line_height else: actual_pixel_size,
  )

proc shape_text_layout(text: ClayStringSlice; key: TextKey): TextLayout =
  result.height = float32(key.line_height)
  if not font_ready or text.length <= 0:
    return
  if ft_set_pixel_sizes(ft_face, 0, FtUInt(key.pixel_size)) != 0:
    return

  hb_font_set_scale(
    hb_font,
    cint(key.pixel_size) * 64,
    cint(key.pixel_size) * 64,
  )
  hb_ft_font_changed(hb_font)
  hb_buffer_reset(hb_buffer)
  hb_buffer_add_utf8(
    hb_buffer,
    text.chars,
    cint(text.length),
    0,
    cint(text.length),
  )
  hb_buffer_guess_segment_properties(hb_buffer)
  hb_shape(hb_font, hb_buffer, nil, 0)

  var info_count: cuint
  var position_count: cuint
  let infos = hb_buffer_get_glyph_infos(hb_buffer, addr info_count)
  let positions = hb_buffer_get_glyph_positions(hb_buffer, addr position_count)
  if infos == nil or positions == nil:
    return

  let glyph_count = min(info_count, position_count)
  result.glyphs = newSeqOfCap[TextGlyph](int(glyph_count))
  let info_array = cast[ptr UncheckedArray[HbGlyphInfo]](infos)
  let position_array = cast[ptr UncheckedArray[HbGlyphPosition]](positions)
  var width_26_6: int64
  for index in 0 ..< int(glyph_count):
    let position = position_array[index]
    result.glyphs.add(TextGlyph(
      glyph_handle: info_array[index].codepoint,
      x_advance: position.x_advance,
      y_advance: position.y_advance,
      x_offset: position.x_offset,
      y_offset: position.y_offset,
    ))
    width_26_6 += int64(position.x_advance)
    if index + 1 < int(glyph_count):
      width_26_6 += int64(key.letter_spacing) * 64
  result.width = float32(width_26_6) / 64.0

proc get_text_layout(
    text: ClayStringSlice;
    font_id, pixel_size, letter_spacing, line_height: uint16
  ): TextLayout =
  let key = make_text_key(
    text,
    font_id,
    pixel_size,
    letter_spacing,
    line_height,
  )
  if text_cache.hasKey(key):
    return text_cache[key]
  result = shape_text_layout(text, key)
  text_cache[key] = result

proc glyph_atlas_transfer_capacity(width, height: uint32): uint32 {.inline.} =
  width * height * 2

proc create_glyph_atlas_resources(width, height: uint32;
    texture: var ptr SdlGpuTexture; transfer_buffer: var ptr SdlGpuTransferBuffer;
    transfer_capacity: var uint32): bool =
  var texture_create_info = SdlGpuTextureCreateInfo(
    `type`: sdl_gpu_texture_type_2d,
    format: sdl_gpu_texture_format_r8_unorm,
    usage: sdl_gpu_texture_usage_sampler,
    width: width,
    height: height,
    layer_count_or_depth: 1,
    num_levels: 1,
    sample_count: sdl_gpu_sample_count_1,
  )
  texture = create_gpu_texture(gpu_device, addr texture_create_info)
  if texture == nil:
    return false

  transfer_capacity = glyph_atlas_transfer_capacity(width, height)
  var transfer_buffer_create_info = SdlGpuTransferBufferCreateInfo(
    usage: sdl_gpu_transfer_buffer_usage_upload,
    size: transfer_capacity,
  )
  transfer_buffer = create_gpu_transfer_buffer(
    gpu_device,
    addr transfer_buffer_create_info,
  )
  if transfer_buffer == nil:
    release_gpu_texture(gpu_device, texture)
    texture = nil
    return false
  true

proc init_glyph_atlas(): bool =
  glyph_atlas = GlyphAtlas(
    width: glyph_atlas_initial_size,
    height: glyph_atlas_initial_size,
    padding: glyph_atlas_padding,
    pixels: newSeq[uint8](int(glyph_atlas_initial_size * glyph_atlas_initial_size)),
  )
  if not create_glyph_atlas_resources(
      glyph_atlas.width,
      glyph_atlas.height,
      glyph_atlas.texture,
      glyph_atlas.transfer_buffer,
      glyph_atlas.transfer_capacity):
    glyph_atlas = GlyphAtlas()
    return false
  true

proc deinit_glyph_atlas() =
  if glyph_atlas.texture != nil:
    release_gpu_texture(gpu_device, glyph_atlas.texture)
  if glyph_atlas.transfer_buffer != nil:
    release_gpu_transfer_buffer(gpu_device, glyph_atlas.transfer_buffer)
  glyph_atlas = GlyphAtlas()

proc update_display_scale(): bool =
  let next_scale = read_display_scale()
  if next_scale == display_scale:
    return true

  if not wait_for_gpu_idle(gpu_device):
    return false
  glyph_cache.clear()
  deinit_glyph_atlas()
  if not init_glyph_atlas():
    return false
  display_scale = next_scale
  echo "Display scale: ", display_scale
  true

proc glyph_atlas_place_key(key: GlyphKey): bool =
  var entry = glyph_cache[key]
  if entry.atlas_width == 0 or entry.atlas_height == 0:
    return true

  let outer_width = entry.atlas_width + glyph_atlas.padding * 2
  let outer_height = entry.atlas_height + glyph_atlas.padding * 2
  if outer_width > glyph_atlas.width or outer_height > glyph_atlas.height:
    return false

  if glyph_atlas.cursor_x + outer_width > glyph_atlas.width:
    glyph_atlas.cursor_x = 0
    glyph_atlas.cursor_y += glyph_atlas.row_height
    glyph_atlas.row_height = 0
  if glyph_atlas.cursor_y + outer_height > glyph_atlas.height:
    return false

  let x = glyph_atlas.cursor_x + glyph_atlas.padding
  let y = glyph_atlas.cursor_y + glyph_atlas.padding
  for row in 0 ..< int(entry.atlas_height):
    let source_index = row * int(entry.atlas_width)
    let destination_index = int((y + uint32(row)) * glyph_atlas.width + x)
    copyMem(
      addr glyph_atlas.pixels[destination_index],
      addr entry.bitmap[source_index],
      int(entry.atlas_width),
    )

  entry.atlas_x = x
  entry.atlas_y = y
  glyph_cache[key] = entry
  glyph_atlas.cursor_x += outer_width
  glyph_atlas.row_height = max(glyph_atlas.row_height, outer_height)
  glyph_atlas.pending_uploads.add(GlyphAtlasUpload(
    x: x - glyph_atlas.padding,
    y: y - glyph_atlas.padding,
    width: outer_width,
    height: outer_height,
  ))
  true

proc glyph_atlas_rebuild(): bool =
  var keys: seq[GlyphKey] = @[]
  for key, entry in glyph_cache:
    if entry.rasterized and entry.atlas_width > 0 and entry.atlas_height > 0:
      keys.add(key)
  for key in keys:
    if not glyph_atlas_place_key(key):
      return false
  true

proc grow_glyph_atlas() =
  let new_width = glyph_atlas.width * 2
  let new_height = glyph_atlas.height * 2
  var new_texture: ptr SdlGpuTexture
  var new_transfer_buffer: ptr SdlGpuTransferBuffer
  var new_transfer_capacity: uint32
  if not create_glyph_atlas_resources(
      new_width,
      new_height,
      new_texture,
      new_transfer_buffer,
      new_transfer_capacity):
    raise newException(Defect, "Glyph atlas resource allocation failed")

  let old_texture = glyph_atlas.texture
  let old_transfer_buffer = glyph_atlas.transfer_buffer
  glyph_atlas.width = new_width
  glyph_atlas.height = new_height
  glyph_atlas.pixels = newSeq[uint8](int(new_width * new_height))
  glyph_atlas.cursor_x = 0
  glyph_atlas.cursor_y = 0
  glyph_atlas.row_height = 0
  glyph_atlas.pending_uploads.setLen(0)
  glyph_atlas.texture = new_texture
  glyph_atlas.transfer_buffer = new_transfer_buffer
  glyph_atlas.transfer_capacity = new_transfer_capacity

  if not glyph_atlas_rebuild():
    release_gpu_texture(gpu_device, new_texture)
    release_gpu_transfer_buffer(gpu_device, new_transfer_buffer)
    raise newException(Defect, "Glyph atlas rebuild failed after growth")

  if old_texture != nil:
    release_gpu_texture(gpu_device, old_texture)
  if old_transfer_buffer != nil:
    release_gpu_transfer_buffer(gpu_device, old_transfer_buffer)
  echo "Glyph atlas: grew to ", new_width, "x", new_height

proc ensure_glyph_atlas_entry(font_id, pixel_size: uint16; glyph_handle: GlyphHandle) =
  let key = GlyphKey(
    font_id: FontID(font_id),
    pixel_size: pixel_size,
    glyph_handle: glyph_handle,
  )
  var entry = glyph_cache.mgetOrPut(key)
  if entry.rasterized:
    return

  var bitmap_width, bitmap_rows: uint32
  var bitmap_left, bitmap_top: int32
  entry.rasterized = true
  if ft_get_glyph_bitmap_metrics(
      ft_face,
      FtUInt(glyph_handle),
      FtUInt(pixel_size),
      addr bitmap_width,
      addr bitmap_rows,
      addr bitmap_left,
      addr bitmap_top) != 0:
    glyph_cache[key] = entry
    return

  entry.atlas_width = bitmap_width
  entry.atlas_height = bitmap_rows
  entry.bearing_x = bitmap_left
  entry.bearing_y = bitmap_top
  if bitmap_width > 0 and bitmap_rows > 0:
    entry.bitmap = newSeq[uint8](int(bitmap_width * bitmap_rows))
    if ft_copy_glyph_bitmap(
        ft_face,
        FtUInt(glyph_handle),
        FtUInt(pixel_size),
        addr entry.bitmap[0],
        uint32(entry.bitmap.len)) != 0:
      entry.bitmap.setLen(0)
      entry.atlas_width = 0
      entry.atlas_height = 0
  glyph_cache[key] = entry

  if entry.atlas_width > 0 and entry.atlas_height > 0 and
      not glyph_atlas_place_key(key):
    grow_glyph_atlas()

proc ensure_text_glyphs_in_atlas(text_layout: TextLayout; font_id, pixel_size: uint16) =
  let actual_pixel_size = max(pixel_size, 1'u16)
  for glyph in text_layout.glyphs:
    ensure_glyph_atlas_entry(font_id, actual_pixel_size, glyph.glyph_handle)

proc append_text_instances(
    text_data: ClayTextRenderData;
    text_box: Rect;
    text_layout: TextLayout;
    clip: Rect;
    depth: float32;
    scale: float32
  ): bool =
  let logical_pixel_size = max(text_data.font_size, 1'u16)
  let raster_pixel_size = scaled_font_pixel_size(text_data.font_size, scale)
  let atlas_width = float32(glyph_atlas.width)
  let atlas_height = float32(glyph_atlas.height)
  let baseline_y = text_box.y + float32(logical_pixel_size)
  var pen_x_26_6: int64

  for glyph_index, glyph in text_layout.glyphs:
    let key = GlyphKey(
      font_id: FontID(text_data.font_id),
      pixel_size: raster_pixel_size,
      glyph_handle: glyph.glyph_handle,
    )
    let entry = glyph_cache[key]
    if entry.atlas_width == 0 or entry.atlas_height == 0:
      pen_x_26_6 += int64(glyph.x_advance)
      if glyph_index + 1 < text_layout.glyphs.len:
        pen_x_26_6 += int64(text_data.letter_spacing) * 64
      continue

    let glyph_box = Rect(
      x: text_box.x + float32(pen_x_26_6 + int64(glyph.x_offset)) / 64.0 +
        float32(entry.bearing_x) / scale,
      y: baseline_y - float32(entry.bearing_y) / scale -
        float32(glyph.y_offset) / 64.0,
      w: float32(entry.atlas_width) / scale,
      h: float32(entry.atlas_height) / scale,
    )
    var clipped_box = glyph_box
    clip_rect(clipped_box, clip)
    if clipped_box.is_empty():
      pen_x_26_6 += int64(glyph.x_advance)
      if glyph_index + 1 < text_layout.glyphs.len:
        pen_x_26_6 += int64(text_data.letter_spacing) * 64
      continue

    if text_instance_data.len >= int(text_instance_buffer_capacity):
      return false

    let clip_left = (clipped_box.x - glyph_box.x) / glyph_box.w
    let clip_top = (clipped_box.y - glyph_box.y) / glyph_box.h
    let clip_right = (clipped_box.x + clipped_box.w - glyph_box.x) / glyph_box.w
    let clip_bottom = (clipped_box.y + clipped_box.h - glyph_box.y) / glyph_box.h
    let uv_origin_x = (float32(entry.atlas_x) + 0.5'f32) / atlas_width
    let uv_origin_y = (float32(entry.atlas_y) + 0.5'f32) / atlas_height
    let uv_extent_x = float32(max(entry.atlas_width, 1'u32) - 1) / atlas_width
    let uv_extent_y = float32(max(entry.atlas_height, 1'u32) - 1) / atlas_height
    let origin_x = uv_origin_x + uv_extent_x * clip_left
    let origin_y = uv_origin_y + uv_extent_y * clip_top
    let extent_x = uv_extent_x * (clip_right - clip_left)
    let extent_y = uv_extent_y * (clip_bottom - clip_top)
    let pixel_box = to_pixel_rect(clipped_box, scale)
    if not pixel_box.is_empty():
      text_instance_data.add(TextInstance(
        origin: pixel_box.origin,
        size: pixel_box.size,
        color: [
          uint8(text_data.text_color.r),
          uint8(text_data.text_color.g),
          uint8(text_data.text_color.b),
          uint8(text_data.text_color.a),
        ],
        uv: [origin_x, origin_y, extent_x, extent_y],
        depth: depth,
      ))

    pen_x_26_6 += int64(glyph.x_advance)
    if glyph_index + 1 < text_layout.glyphs.len:
      pen_x_26_6 += int64(text_data.letter_spacing) * 64
  true

proc align_up(value, alignment: uint32): uint32 {.inline.} =
  ((value + alignment - 1) div alignment) * alignment

proc stage_glyph_atlas_uploads(): bool =
  if glyph_atlas.pending_uploads.len == 0:
    return true

  var required_bytes: uint32
  for upload in glyph_atlas.pending_uploads:
    required_bytes = align_up(required_bytes, 512) + upload.width * upload.height
  if required_bytes > glyph_atlas.transfer_capacity:
    echo "Glyph atlas: upload staging buffer too small"
    return false

  let mapped = map_gpu_transfer_buffer(
    gpu_device,
    glyph_atlas.transfer_buffer,
    true,
  )
  if mapped == nil:
    return false

  var transfer_offset: uint32
  for index in 0 ..< glyph_atlas.pending_uploads.len:
    var upload = addr glyph_atlas.pending_uploads[index]
    transfer_offset = align_up(transfer_offset, 512)
    upload[].source_offset = transfer_offset
    for row in 0 ..< int(upload[].height):
      let source_index = int((upload[].y + uint32(row)) * glyph_atlas.width + upload[].x)
      let destination = cast[pointer](cast[uint](mapped) + uint(transfer_offset + uint32(row) * upload[].width))
      copyMem(destination, addr glyph_atlas.pixels[source_index], int(upload[].width))
    transfer_offset += upload[].width * upload[].height
  unmap_gpu_transfer_buffer(gpu_device, glyph_atlas.transfer_buffer)
  true

proc upload_glyph_atlas_regions(copy_pass: ptr SdlGpuCopyPass) =
  let upload_count = glyph_atlas.pending_uploads.len
  if upload_count == 0:
    return
  for upload in glyph_atlas.pending_uploads:
    var source = SdlGpuTextureTransferInfo(
      transfer_buffer: glyph_atlas.transfer_buffer,
      offset: upload.source_offset,
      pixels_per_row: upload.width,
      rows_per_layer: upload.height,
    )
    var destination = SdlGpuTextureRegion(
      texture: glyph_atlas.texture,
      mip_level: 0,
      layer: 0,
      x: upload.x,
      y: upload.y,
      z: 0,
      w: upload.width,
      h: upload.height,
      d: 1,
    )
    # The atlas is persistent. Cycling would invalidate every existing glyph,
    # because SDL cycles the whole texture even for a partial upload.
    upload_to_gpu_texture(copy_pass, addr source, addr destination, false)
  glyph_atlas.pending_uploads.setLen(0)
  echo "Glyph atlas: uploaded ", upload_count, " regions"


proc init_renderer*(renderer: Renderer; target_window: ptr SdlWindow;
    clear_color_value: ClayColor): bool =
  active_renderer = renderer
  window = target_window
  clear_color = clear_color_value
  if not init_font():
    return false
  display_scale = read_display_scale()
  echo "Display scale: ", display_scale
  gpu_device = create_gpu_device(sdl_gpu_shaderformat_msl, false, nil)

  if gpu_device == nil or not claim_window_for_gpu_device(gpu_device, window):
    return false
  # Keep persistent resources writable without cycling their contents.
  # Blocking acquisition plus one allowed frame keeps the previous atlas use
  # complete before the next frame updates it.
  if not set_gpu_allowed_frames_in_flight(gpu_device, 1):
    return false
  if not init_glyph_atlas():
    return false

  let opaque_color_target_format =
    get_gpu_swapchain_texture_format(gpu_device, window)

  var opaque_vertex_shader_create_info = SdlGpuShaderCreateInfo(
    code_size: csize_t(opaque_vertex_shader_code.len),
    code: cast[ptr uint8](cstring(opaque_vertex_shader_code)),
    entrypoint: "main0",
    format: sdl_gpu_shader_format_msl,
    stage: sdl_gpu_shader_stage_vertex,
    num_uniform_buffers: 1,
  )
  
  var opaque_vertex_shader =
    create_gpu_shader(gpu_device, addr opaque_vertex_shader_create_info)
  defer:
    release_gpu_shader(gpu_device, opaque_vertex_shader)
  
  var opaque_fragment_shader_create_info = SdlGpuShaderCreateInfo(
    code_size: csize_t(opaque_fragment_shader_code.len),
    code: cast[ptr uint8](cstring(opaque_fragment_shader_code)),
    entrypoint: "main0",
    format: sdl_gpu_shader_format_msl,
    stage: sdl_gpu_shader_stage_fragment,
  )
  
  var opaque_fragment_shader =
    create_gpu_shader(gpu_device, addr opaque_fragment_shader_create_info)
  defer:
    release_gpu_shader(gpu_device, opaque_fragment_shader)

  var coverage_vertex_shader_create_info = SdlGpuShaderCreateInfo(
    code_size: csize_t(coverage_vertex_shader_code.len),
    code: cast[ptr uint8](cstring(coverage_vertex_shader_code)),
    entrypoint: "main0",
    format: sdl_gpu_shader_format_msl,
    stage: sdl_gpu_shader_stage_vertex,
    num_uniform_buffers: 1,
  )
  var coverage_vertex_shader =
    create_gpu_shader(gpu_device, addr coverage_vertex_shader_create_info)
  defer:
    release_gpu_shader(gpu_device, coverage_vertex_shader)

  var coverage_fragment_shader_create_info = SdlGpuShaderCreateInfo(
    code_size: csize_t(coverage_fragment_shader_code.len),
    code: cast[ptr uint8](cstring(coverage_fragment_shader_code)),
    entrypoint: "main0",
    format: sdl_gpu_shader_format_msl,
    stage: sdl_gpu_shader_stage_fragment,
    num_samplers: 1,
  )
  var coverage_fragment_shader =
    create_gpu_shader(gpu_device, addr coverage_fragment_shader_create_info)
  defer:
    release_gpu_shader(gpu_device, coverage_fragment_shader)
  
  var opaque_vertex_buffer_descriptions = [
    SdlGpuVertexBufferDescription(
      slot: 0,
      pitch: uint32(sizeof(QuadVertex)),
      input_rate: sdl_gpu_vertex_input_rate_vertex,
      instance_step_rate: 0,
    ),
    SdlGpuVertexBufferDescription(
      slot: 1,
      pitch: uint32(sizeof(SpriteInstance)),
      input_rate: sdl_gpu_vertex_input_rate_instance,
      instance_step_rate: 0,
    ),
  ]
  
  var opaque_vertex_attributes = [
    SdlGpuVertexAttribute(
      location: 0,
      buffer_slot: 0,
      format: sdl_gpu_vertex_element_format_ushort2,
      offset: uint32(offsetOf(QuadVertex, corners)),
    ),
    SdlGpuVertexAttribute(
      location: 1,
      buffer_slot: 1,
      format: sdl_gpu_vertex_element_format_ushort2,
      offset: uint32(offsetOf(SpriteInstance, origin)),
    ),
    SdlGpuVertexAttribute(
      location: 2,
      buffer_slot: 1,
      format: sdl_gpu_vertex_element_format_ushort2,
      offset: uint32(offsetOf(SpriteInstance, size)),
    ),
    SdlGpuVertexAttribute(
      location: 3,
      buffer_slot: 1,
      format: sdl_gpu_vertex_element_format_ubyte4,
      offset: uint32(offsetOf(SpriteInstance, color)),
    ),
    SdlGpuVertexAttribute(
      location: 4,
      buffer_slot: 1,
      format: sdl_gpu_vertex_element_format_float,
      offset: uint32(offsetOf(SpriteInstance, depth)),
    ),
  ]
  
  var opaque_color_target_description = SdlGpuColorTargetDescription(
    format: opaque_color_target_format,
    blend_state: SdlGpuColorTargetBlendState(
      # Straight-alpha blending.
      src_color_blendfactor: sdl_gpu_blend_factor_src_alpha,
      dst_color_blendfactor: sdl_gpu_blend_factor_one_minus_src_alpha,
      color_blend_op: sdl_gpu_blend_op_add,
  
      src_alpha_blendfactor: sdl_gpu_blend_factor_one,
      dst_alpha_blendfactor: sdl_gpu_blend_factor_one_minus_src_alpha,
      alpha_blend_op: sdl_gpu_blend_op_add,
  
      enable_blend: true,
    ),
  )
  
  var opaque_pipeline_create_info = SdlGpuGraphicsPipelineCreateInfo(
    vertex_shader: opaque_vertex_shader,
    fragment_shader: opaque_fragment_shader,
  
    vertex_input_state: SdlGpuVertexInputState(
      vertex_buffer_descriptions: addr opaque_vertex_buffer_descriptions[0],
      num_vertex_buffers: uint32(opaque_vertex_buffer_descriptions.len),
      vertex_attributes: addr opaque_vertex_attributes[0],
      num_vertex_attributes: uint32(opaque_vertex_attributes.len),
    ),
  
    primitive_type: sdl_gpu_primitive_type_triangle_list,
  
    rasterizer_state: SdlGpuRasterizerState(
      fill_mode: sdl_gpu_fill_mode_fill,
      cull_mode: sdl_gpu_cull_mode_none,
      front_face: sdl_gpu_front_face_counter_clockwise,
      enable_depth_clip: true,
    ),
  
    multisample_state: SdlGpuMultisampleState(
      sample_count: sdl_gpu_sample_count_1,
    ),
  
    depth_stencil_state: SdlGpuDepthStencilState(
      compare_op: sdl_gpu_compare_op_less,
  
      back_stencil_state: SdlGpuStencilOpState(
        fail_op: sdl_gpu_stencil_op_keep,
        pass_op: sdl_gpu_stencil_op_keep,
        depth_fail_op: sdl_gpu_stencil_op_keep,
        compare_op: sdl_gpu_compare_op_always,
      ),
  
      front_stencil_state: SdlGpuStencilOpState(
        fail_op: sdl_gpu_stencil_op_keep,
        pass_op: sdl_gpu_stencil_op_keep,
        depth_fail_op: sdl_gpu_stencil_op_keep,
        compare_op: sdl_gpu_compare_op_always,
      ),
  
      compare_mask: 0xff,
      write_mask: 0xff,
      enable_depth_test: true,
      enable_depth_write: true,
      enable_stencil_test: false,
    ),
  
    target_info: SdlGpuGraphicsPipelineTargetInfo(
      color_target_descriptions: addr opaque_color_target_description,
      num_color_targets: 1,
      depth_stencil_format: sdl_gpu_texture_format_d16_unorm,
      has_depth_stencil_target: true,
    ),
  )

  opaque_pipeline = create_gpu_graphics_pipeline(gpu_device, addr opaque_pipeline_create_info)

  var coverage_sampler_create_info = SdlGpuSamplerCreateInfo(
    min_filter: sdl_gpu_filter_linear,
    mag_filter: sdl_gpu_filter_linear,
    mipmap_mode: sdl_gpu_sampler_mipmap_mode_nearest,
    address_mode_u: sdl_gpu_sampler_address_mode_clamp_to_edge,
    address_mode_v: sdl_gpu_sampler_address_mode_clamp_to_edge,
    address_mode_w: sdl_gpu_sampler_address_mode_clamp_to_edge,
    max_anisotropy: 1,
    min_lod: 0,
    max_lod: 0,
  )
  coverage_sampler = create_gpu_sampler(
    gpu_device,
    addr coverage_sampler_create_info,
  )

  var coverage_vertex_buffer_descriptions = [
    SdlGpuVertexBufferDescription(
      slot: 0,
      pitch: uint32(sizeof(QuadVertex)),
      input_rate: sdl_gpu_vertex_input_rate_vertex,
      instance_step_rate: 0,
    ),
    SdlGpuVertexBufferDescription(
      slot: 1,
      pitch: uint32(sizeof(TextInstance)),
      input_rate: sdl_gpu_vertex_input_rate_instance,
      instance_step_rate: 0,
    ),
  ]

  var coverage_vertex_attributes = [
    SdlGpuVertexAttribute(
      location: 0,
      buffer_slot: 0,
      format: sdl_gpu_vertex_element_format_ushort2,
      offset: uint32(offsetOf(QuadVertex, corners)),
    ),
    SdlGpuVertexAttribute(
      location: 1,
      buffer_slot: 1,
      format: sdl_gpu_vertex_element_format_ushort2,
      offset: uint32(offsetOf(TextInstance, origin)),
    ),
    SdlGpuVertexAttribute(
      location: 2,
      buffer_slot: 1,
      format: sdl_gpu_vertex_element_format_ushort2,
      offset: uint32(offsetOf(TextInstance, size)),
    ),
    SdlGpuVertexAttribute(
      location: 3,
      buffer_slot: 1,
      format: sdl_gpu_vertex_element_format_ubyte4,
      offset: uint32(offsetOf(TextInstance, color)),
    ),
    SdlGpuVertexAttribute(
      location: 4,
      buffer_slot: 1,
      format: sdl_gpu_vertex_element_format_float4,
      offset: uint32(offsetOf(TextInstance, uv)),
    ),
    SdlGpuVertexAttribute(
      location: 5,
      buffer_slot: 1,
      format: sdl_gpu_vertex_element_format_float,
      offset: uint32(offsetOf(TextInstance, depth)),
    ),
  ]

  var coverage_pipeline_create_info = opaque_pipeline_create_info
  coverage_pipeline_create_info.vertex_shader = coverage_vertex_shader
  coverage_pipeline_create_info.fragment_shader = coverage_fragment_shader
  coverage_pipeline_create_info.vertex_input_state = SdlGpuVertexInputState(
    vertex_buffer_descriptions: addr coverage_vertex_buffer_descriptions[0],
    num_vertex_buffers: uint32(coverage_vertex_buffer_descriptions.len),
    vertex_attributes: addr coverage_vertex_attributes[0],
    num_vertex_attributes: uint32(coverage_vertex_attributes.len),
  )
  coverage_pipeline_create_info.depth_stencil_state.enable_depth_write = false
  coverage_pipeline = create_gpu_graphics_pipeline(
    gpu_device,
    addr coverage_pipeline_create_info,
  )

  instance_buffer_capacity = uint32(clay_get_max_element_count())
  instance_data = newSeqOfCap[SpriteInstance](int(instance_buffer_capacity))
  text_instance_buffer_capacity = instance_buffer_capacity * 4
  text_instance_data = newSeqOfCap[TextInstance](int(text_instance_buffer_capacity))

  var quad_vertex_buffer_create_info = SdlGpuBufferCreateInfo(
    usage: sdl_gpu_buffer_usage_vertex,
    size: uint32(sizeof(quad_vertices)),
  )
  quad_vertex_buffer = create_gpu_buffer(gpu_device, addr quad_vertex_buffer_create_info)

  var instance_buffer_create_info = SdlGpuBufferCreateInfo(
    usage: sdl_gpu_buffer_usage_vertex,
    size: instance_buffer_capacity * uint32(sizeof(SpriteInstance)),
  )
  instance_buffer = create_gpu_buffer(gpu_device, addr instance_buffer_create_info)

  var instance_transfer_buffer_create_info = SdlGpuTransferBufferCreateInfo(
    usage: sdl_gpu_transfer_buffer_usage_upload,
    size: uint32(sizeof(quad_vertices)) +
      instance_buffer_capacity * uint32(sizeof(SpriteInstance)),
  )
  instance_transfer_buffer = create_gpu_transfer_buffer(
    gpu_device,
    addr instance_transfer_buffer_create_info,
  )

  var text_instance_buffer_create_info = SdlGpuBufferCreateInfo(
    usage: sdl_gpu_buffer_usage_vertex,
    size: text_instance_buffer_capacity * uint32(sizeof(TextInstance)),
  )
  text_instance_buffer = create_gpu_buffer(
    gpu_device,
    addr text_instance_buffer_create_info,
  )

  var text_instance_transfer_buffer_create_info = SdlGpuTransferBufferCreateInfo(
    usage: sdl_gpu_transfer_buffer_usage_upload,
    size: text_instance_buffer_capacity * uint32(sizeof(TextInstance)),
  )
  text_instance_transfer_buffer = create_gpu_transfer_buffer(
    gpu_device,
    addr text_instance_transfer_buffer_create_info,
  )

  if opaque_pipeline == nil or coverage_pipeline == nil or
      coverage_sampler == nil or quad_vertex_buffer == nil or
      instance_buffer == nil or instance_transfer_buffer == nil or
      text_instance_buffer == nil or text_instance_transfer_buffer == nil:
    return false

  true
proc measure_text*(text: ClayStringSlice; config: ptr ClayTextElementConfig;
    user_data: pointer): ClayDimensions {.cdecl.} =
  discard user_data
  let layout = get_text_layout(
    text,
    config[].font_id,
    config[].font_size,
    config[].letter_spacing,
    config[].line_height,
  )
  clay_dimensions(layout.width, layout.height)


proc handle_error*(error_data: ClayErrorData) {.cdecl.} =
  echo "Clay error: ", error_data.error_type


proc render_frame*(renderer: Renderer; clay_context: ptr ClayContext;
    string_cache: var ClayStringCache; prepare_frame: PrepareFrameProc;
    build_elements: BuildElementsProc; finish_frame: FinishFrameProc;
    delta_time: float32): bool =
  active_renderer = renderer
  clay_set_current_context(clay_context)
  var logical_width_c, logical_height_c: cint
  if not get_window_size(window, addr logical_width_c, addr logical_height_c) or
      logical_width_c <= 0 or logical_height_c <= 0:
    return false
  let logical_width = uint32(logical_width_c)
  let logical_height = uint32(logical_height_c)
  if not update_display_scale():
    return false

  let command_buffer = acquire_gpu_command_buffer(gpu_device)
  if command_buffer == nil:
    return false
  var command_buffer_consumed = false
  defer:
    if not command_buffer_consumed:
      discard submit_gpu_command_buffer(command_buffer)

  var swapchain_texture: ptr SdlGpuTexture
  var width, height: uint32
  if not wait_and_acquire_gpu_swapchain_texture(command_buffer, window,
      addr swapchain_texture, addr width, addr height):
    discard cancel_gpu_command_buffer(command_buffer)
    command_buffer_consumed = true
    return false
  if swapchain_texture == nil:
    command_buffer_consumed = true
    if not submit_gpu_command_buffer(command_buffer):
      return false
    return true

  if depth_texture == nil or depth_texture_width != width or depth_texture_height != height:
    if depth_texture != nil:
      if not wait_for_gpu_idle(gpu_device):
        return false
      release_gpu_texture(gpu_device, depth_texture)
      depth_texture = nil

    var depth_texture_create_info = SdlGpuTextureCreateInfo(
      `type`: sdl_gpu_texture_type_2d,
      format: sdl_gpu_texture_format_d16_unorm,
      usage: sdl_gpu_texture_usage_depth_stencil_target,
      width: width,
      height: height,
      layer_count_or_depth: 1,
      num_levels: 1,
      sample_count: sdl_gpu_sample_count_1,
    )
    depth_texture = create_gpu_texture(gpu_device, addr depth_texture_create_info)
    if depth_texture == nil:
      return false
    depth_texture_width = width
    depth_texture_height = height

  clay_set_layout_dimensions(clay_dimensions(logical_width, logical_height))

  if prepare_frame != nil:
    prepare_frame()
  let commands = clay(string_cache, delta_time):
    build_elements(ViewFrame(
      logical_width: logical_width,
      logical_height: logical_height,
      pixel_width: width,
      pixel_height: height,
      display_scale: display_scale,
      delta_time: delta_time,
      string_cache_generation: clay_string_cache_current_generation(string_cache),
      string_cache_generation_count: clay_string_cache_generation_count(string_cache),
      exiting_transitions: clay_has_exiting_transitions()))
  if finish_frame != nil:
    finish_frame()
  instance_data.setLen(0)
  text_instance_data.setLen(0)
  clip_stack.setLen(0)
  clip_stack.add Rect(
    x: 0'f32,
    y: 0'f32,
    w: float32(logical_width),
    h: float32(logical_height),
  )

  var paint_rank = 0
  for command in commands:
    let depth = 1.0'f32 - float32(paint_rank + 1) / float32(commands.length + 1)
    inc paint_rank
    case command.command_type:
    of clay_render_command_type_none: discard
    of clay_render_command_type_rectangle:
      let current_clip = clip_stack[^1]
      var box: Rect = command.bounding_box
      clip_rect(box, current_clip)
      let color = command.render_data.rectangle.background_color
      if box.is_empty(): continue
      let pixel_box = to_pixel_rect(box, display_scale)
      if pixel_box.is_empty(): continue
      if instance_data.len >= int(instance_buffer_capacity):
        return false
      instance_data.add(SpriteInstance(
        origin: pixel_box.origin,
        size: pixel_box.size,
        color: [
          uint8(color.r),
          uint8(color.g),
          uint8(color.b),
          uint8(color.a),
        ],
        depth: depth,
      ))
    of clay_render_command_type_border:
      let box: Rect = command.bounding_box
      let color = command.render_data.border.color
      let border_widths = command.render_data.border.width
      let current_clip = clip_stack[^1]

      var top = Rect(
        x: box.x,
        y: box.y,
        w: box.w,
        h: float32(border_widths.top),
      )
      var right = Rect(
        x: box.x + box.w - float32(border_widths.right),
        y: box.y + float32(border_widths.top),
        w: float32(border_widths.right),
        h: max(box.h - float32(border_widths.top) - float32(border_widths.bottom), 0),
      )
      var left = Rect(
        x: box.x,
        y: box.y + top.h,
        w: float32(border_widths.left),
        h: max(box.h - float32(border_widths.top) - float32(border_widths.bottom), 0),
      )
      var bottom = Rect(
        x: box.x,
        y: box.y + box.h - float32(border_widths.bottom),
        w: box.w,
        h: float32(border_widths.bottom),
      )
      for source_segment in [top, right, left, bottom]:
        var segment = source_segment
        clip_rect(segment, current_clip)
        if segment.is_empty(): continue
        let pixel_segment = to_pixel_rect(segment, display_scale)
        if pixel_segment.is_empty(): continue
        if instance_data.len >= int(instance_buffer_capacity):
          return false
        instance_data.add(SpriteInstance(
          origin: pixel_segment.origin,
          size: pixel_segment.size,
          color: [
            uint8(color.r),
            uint8(color.g),
            uint8(color.b),
            uint8(color.a),
          ],
          depth: depth,
        ))
    of clay_render_command_type_text:
      let text_data = command.render_data.text
      let text_layout = get_text_layout(
        text_data.string_contents,
        text_data.font_id,
        text_data.font_size,
        text_data.letter_spacing,
        text_data.line_height,
      )
      ensure_text_glyphs_in_atlas(
        text_layout,
        text_data.font_id,
        scaled_font_pixel_size(text_data.font_size, display_scale),
      )
      if not append_text_instances(
          text_data,
          Rect(
            x: command.bounding_box.x,
            y: command.bounding_box.y,
            w: text_layout.width,
            h: text_layout.height,
          ),
          text_layout,
          clip_stack[^1],
          depth,
          display_scale):
        return false
    of clay_render_command_type_image: discard
    of clay_render_command_type_scissor_start:
      let horizontal = command.render_data.clip.horizontal
      let vertical = command.render_data.clip.vertical
      var new_clip = clip_stack[^1]
      if horizontal:
        let right = min(
          new_clip.x + new_clip.w,
          float32(command.bounding_box.x + command.bounding_box.width),
        )
        new_clip.x = max(new_clip.x, float32(command.bounding_box.x))
        new_clip.w = max(right - new_clip.x, 0)
      if vertical:
        let bottom = min(
          new_clip.y + new_clip.h,
          float32(command.bounding_box.y + command.bounding_box.height),
        )
        new_clip.y = max(new_clip.y, float32(command.bounding_box.y))
        new_clip.h = max(bottom - new_clip.y, 0)
      clip_stack.add new_clip
    of clay_render_command_type_scissor_end:
      clip_stack.setLen(clip_stack.len - 1)
    of clay_render_command_type_overlay_color_start: discard
    of clay_render_command_type_overlay_color_end: discard
    of clay_render_command_type_custom: discard
    else: return false

  if not stage_glyph_atlas_uploads():
    return false

  let mapped_transfer_buffer = map_gpu_transfer_buffer(
    gpu_device,
    instance_transfer_buffer,
    true,
  )
  if mapped_transfer_buffer == nil:
    return false

  let instance_transfer_offset = sizeof(quad_vertices)
  if not quad_vertex_buffer_initialized:
    copyMem(
      mapped_transfer_buffer,
      unsafeAddr quad_vertices[0],
      sizeof(quad_vertices),
    )

  if instance_data.len > 0:
    copyMem(
      cast[pointer](cast[uint](mapped_transfer_buffer) + uint(instance_transfer_offset)),
      addr instance_data[0],
      instance_data.len * sizeof(SpriteInstance),
    )

  unmap_gpu_transfer_buffer(gpu_device, instance_transfer_buffer)

  if text_instance_data.len > 0:
    let mapped_text_transfer_buffer = map_gpu_transfer_buffer(
      gpu_device,
      text_instance_transfer_buffer,
      true,
    )
    if mapped_text_transfer_buffer == nil:
      return false
    copyMem(
      mapped_text_transfer_buffer,
      addr text_instance_data[0],
      text_instance_data.len * sizeof(TextInstance),
    )
    unmap_gpu_transfer_buffer(gpu_device, text_instance_transfer_buffer)

  let copy_pass = begin_gpu_copy_pass(command_buffer)
  if copy_pass == nil:
    return false

  upload_glyph_atlas_regions(copy_pass)

  if not quad_vertex_buffer_initialized:
    var quad_source = SdlGpuTransferBufferLocation(
      transfer_buffer: instance_transfer_buffer,
      offset: 0,
    )
    var quad_destination = SdlGpuBufferRegion(
      buffer: quad_vertex_buffer,
      offset: 0,
      size: uint32(sizeof(quad_vertices)),
    )
    upload_to_gpu_buffer(
      copy_pass,
      addr quad_source,
      addr quad_destination,
      true,
    )

  if instance_data.len > 0:
    var instance_source = SdlGpuTransferBufferLocation(
      transfer_buffer: instance_transfer_buffer,
      offset: uint32(instance_transfer_offset),
    )
    var instance_destination = SdlGpuBufferRegion(
      buffer: instance_buffer,
      offset: 0,
      size: uint32(instance_data.len * sizeof(SpriteInstance)),
    )
    upload_to_gpu_buffer(
      copy_pass,
      addr instance_source,
      addr instance_destination,
      true,
    )

  if text_instance_data.len > 0:
    var text_instance_source = SdlGpuTransferBufferLocation(
      transfer_buffer: text_instance_transfer_buffer,
      offset: 0,
    )
    var text_instance_destination = SdlGpuBufferRegion(
      buffer: text_instance_buffer,
      offset: 0,
      size: uint32(text_instance_data.len * sizeof(TextInstance)),
    )
    upload_to_gpu_buffer(
      copy_pass,
      addr text_instance_source,
      addr text_instance_destination,
      true,
    )

  end_gpu_copy_pass(copy_pass)

  let width_f32 = float32(width)
  let height_f32 = float32(height)
  
  var target = SdlGpuColorTargetInfo(
    texture: swapchain_texture,
    clear_color: SdlFColor(
      r: cfloat(clear_color.r) / 255.0,
      g: cfloat(clear_color.g) / 255.0,
      b: cfloat(clear_color.b) / 255.0,
      a: 1.0
    ),
    load_op: sdl_gpu_load_op_clear,
    store_op: sdl_gpu_store_op_store
  )
  var depth_target = SdlGpuDepthStencilTargetInfo(
    texture: depth_texture,
    clear_depth: 1.0,
    load_op: sdl_gpu_load_op_clear,
    store_op: sdl_gpu_store_op_store,
    stencil_load_op: sdl_gpu_load_op_dont_care,
    stencil_store_op: sdl_gpu_store_op_dont_care,
  )
  let render_pass = begin_gpu_render_pass(
    command_buffer,
    addr target,
    1,
    addr depth_target,
  )
  if render_pass == nil:
    return false

  bind_gpu_graphics_pipeline(render_pass, opaque_pipeline)

  var frame_data = FrameData(
    viewport_size: [width_f32, height_f32],
    inverse_viewport_size: [1'f32 / width_f32, 1'f32 / height_f32]
  )

  var vertex_bindings = [
    SdlGpuBufferBinding(
      buffer: quad_vertex_buffer,
      offset: 0,
    ),
    SdlGpuBufferBinding(
      buffer: instance_buffer,
      offset: 0,
    ),
  ]

  push_gpu_vertex_uniform_data(
    command_buffer,
    0,
    addr frame_data,
    uint32(sizeof(FrameData)),
  )

  bind_gpu_vertex_buffers(
    render_pass,
    0,
    addr vertex_bindings[0],
    uint32(vertex_bindings.len),
  )

  if instance_data.len > 0:
    draw_gpu_primitives(
      render_pass,
      6,
      uint32(instance_data.len),
      0,
      0,
    )

  end_gpu_render_pass(render_pass)

  if text_instance_data.len > 0:
    target.load_op = sdl_gpu_load_op_load
    depth_target.load_op = sdl_gpu_load_op_load
    depth_target.store_op = sdl_gpu_store_op_dont_care
    let coverage_render_pass = begin_gpu_render_pass(
      command_buffer,
      addr target,
      1,
      addr depth_target,
    )
    if coverage_render_pass == nil:
      return false

    bind_gpu_graphics_pipeline(coverage_render_pass, coverage_pipeline)
    push_gpu_vertex_uniform_data(
      command_buffer,
      0,
      addr frame_data,
      uint32(sizeof(FrameData)),
    )

    var text_vertex_bindings = [
      SdlGpuBufferBinding(
        buffer: quad_vertex_buffer,
        offset: 0,
      ),
      SdlGpuBufferBinding(
        buffer: text_instance_buffer,
        offset: 0,
      ),
    ]
    bind_gpu_vertex_buffers(
      coverage_render_pass,
      0,
      addr text_vertex_bindings[0],
      uint32(text_vertex_bindings.len),
    )

    var text_sampler_binding = SdlGpuTextureSamplerBinding(
      texture: glyph_atlas.texture,
      sampler: coverage_sampler,
    )
    bind_gpu_fragment_samplers(
      coverage_render_pass,
      0,
      addr text_sampler_binding,
      1,
    )
    draw_gpu_primitives(
      coverage_render_pass,
      6,
      uint32(text_instance_data.len),
      0,
      0,
    )
    end_gpu_render_pass(coverage_render_pass)

  let submission_succeeded = submit_gpu_command_buffer(command_buffer)
  command_buffer_consumed = true
  if not submission_succeeded:
    return false
  quad_vertex_buffer_initialized = true
  true
proc deinit_renderer*(renderer: Renderer) =
  active_renderer = renderer
  destroy_font()
  deinit_glyph_atlas()
  if gpu_device != nil:
    release_gpu_texture(gpu_device, depth_texture)
    release_gpu_transfer_buffer(gpu_device, instance_transfer_buffer)
    release_gpu_buffer(gpu_device, instance_buffer)
    release_gpu_transfer_buffer(gpu_device, text_instance_transfer_buffer)
    release_gpu_buffer(gpu_device, quad_vertex_buffer)
    release_gpu_sampler(gpu_device, coverage_sampler)
    release_gpu_graphics_pipeline(gpu_device, coverage_pipeline)
    release_gpu_graphics_pipeline(gpu_device, opaque_pipeline)
    if window != nil:
      release_window_from_gpu_device(gpu_device, window)
    destroy_gpu_device(gpu_device)
  active_renderer = nil
