import std/colors
import std/os
import clay, sdl

type
  QuadVertex = object
    corners: array[2, float32]
  SpriteInstance = object
    origin: array[2, uint16]
    size: array[2, uint16]
    color: array[4, uint8]
  Rect = object
    x, w, y, h: float32
  FrameData = object
    viewport_size: array[2, float32]
    inverse_viewport_size: array[2, float32]
  Palette = object
    background: Color

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

doAssert sizeof(SpriteInstance) == 12

static:
  discard staticExec("mkdir -p " & quoteShell(shader_output_dir))
  discard staticExec("shadercross " & quoteShell(shader_source_dir / "analytic.vert.hlsl") &
    " -s HLSL -d MSL -t vertex -o " &
    quoteShell(shader_output_dir / "analytic.vert.msl"))
  discard staticExec("shadercross " & quoteShell(shader_source_dir / "analytic.frag.hlsl") &
    " -s HLSL -d MSL -t fragment -o " &
    quoteShell(shader_output_dir / "analytic.frag.msl"))

const
  analytic_vertex_shader_code = staticRead(
    project_dir / "shaders" / "compiled" / "analytic.vert.msl"
  )
  analytic_fragment_shader_code = staticRead(
    project_dir / "shaders" / "compiled" / "analytic.frag.msl"
  )

var
  window: ptr SdlWindow

  gpu_device: ptr SdlGpuDevice
  analytic_pipeline: ptr SdlGpuGraphicsPipeline
  quad_vertex_buffer: ptr SdlGpuBuffer
  instance_buffer: ptr SdlGpuBuffer
  instance_transfer_buffer: ptr SdlGpuTransferBuffer
  instance_buffer_capacity: uint32
  quad_vertex_buffer_initialized: bool
  instance_data: seq[SpriteInstance]
  clip_stack: seq[Rect]

  palette = Palette(background: rgb(0, 0, 0))

  clay_arena: ClayArena

converter clay_bb_to_rect(clay_bb: ClayBoundingBox): Rect =
  result.x = float32(clay_bb.x)
  result.y = float32(clay_bb.y)
  result.w = float32(clay_bb.width)
  result.h = float32(clay_bb.height)

proc clip(rect: var Rect; mask: Rect): Rect =
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

  rect

proc is_empty(rect: Rect): bool = rect.w <= 0 or rect.h <= 0

proc append_clipped_rect(box: Rect; clip_rect: Rect; color: ClayColor): bool =
  var clipped_box = box
  discard clipped_box.clip(clip_rect)
  if clipped_box.is_empty():
    return true
  if instance_data.len >= int(instance_buffer_capacity):
    return false
  instance_data.add(SpriteInstance(
    origin: [uint16(clipped_box.x), uint16(clipped_box.y)],
    size: [uint16(clipped_box.w), uint16(clipped_box.h)],
    color: [
      uint8(color.r),
      uint8(color.g),
      uint8(color.b),
      uint8(color.a),
    ],
  ))
  true

proc sdl_app_init(appstate: ptr pointer; argc: cint; argv: ptr ptr char): SdlAppResult {.cdecl.} =
  discard appstate
  discard argc
  discard argv
  if not set_app_metadata("SDL GPU Window", "1.0", "com.example.sdl-gpu-window"):
    return app_failure
  window = create_window("SDL GPU Window", 640, 480,
    sdl_window_resizable or sdl_window_borderless)
  if window == nil:
    return app_failure
  gpu_device = create_gpu_device(sdl_gpu_shaderformat_msl, false, nil)

  if gpu_device == nil or not claim_window_for_gpu_device(gpu_device, window):
    return app_failure
  if not set_gpu_allowed_frames_in_flight(gpu_device, 1):
    return app_failure

  let analytic_color_target_format =
    get_gpu_swapchain_texture_format(gpu_device, window)

  var analytic_vertex_shader_create_info = SdlGpuShaderCreateInfo(
    code_size: csize_t(analytic_vertex_shader_code.len),
    code: cast[ptr uint8](cstring(analytic_vertex_shader_code)),
    entrypoint: "main0",
    format: sdl_gpu_shader_format_msl,
    stage: sdl_gpu_shader_stage_vertex,
    num_uniform_buffers: 1,
  )
  
  var analytic_vertex_shader =
    create_gpu_shader(gpu_device, addr analytic_vertex_shader_create_info)
  defer:
    release_gpu_shader(gpu_device, analytic_vertex_shader)
  
  var analytic_fragment_shader_create_info = SdlGpuShaderCreateInfo(
    code_size: csize_t(analytic_fragment_shader_code.len),
    code: cast[ptr uint8](cstring(analytic_fragment_shader_code)),
    entrypoint: "main0",
    format: sdl_gpu_shader_format_msl,
    stage: sdl_gpu_shader_stage_fragment,
  )
  
  var analytic_fragment_shader =
    create_gpu_shader(gpu_device, addr analytic_fragment_shader_create_info)
  defer:
    release_gpu_shader(gpu_device, analytic_fragment_shader)
  
  var analytic_vertex_buffer_descriptions = [
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
  
  var analytic_vertex_attributes = [
    SdlGpuVertexAttribute(
      location: 0,
      buffer_slot: 0,
      format: sdl_gpu_vertex_element_format_float2,
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
  ]
  
  var analytic_color_target_description = SdlGpuColorTargetDescription(
    format: analytic_color_target_format,
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
  
  var analytic_pipeline_create_info = SdlGpuGraphicsPipelineCreateInfo(
    vertex_shader: analytic_vertex_shader,
    fragment_shader: analytic_fragment_shader,
  
    vertex_input_state: SdlGpuVertexInputState(
      vertex_buffer_descriptions: addr analytic_vertex_buffer_descriptions[0],
      num_vertex_buffers: uint32(analytic_vertex_buffer_descriptions.len),
      vertex_attributes: addr analytic_vertex_attributes[0],
      num_vertex_attributes: uint32(analytic_vertex_attributes.len),
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
      compare_op: sdl_gpu_compare_op_always,
  
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
      enable_depth_test: false,
      enable_depth_write: false,
      enable_stencil_test: false,
    ),
  
    target_info: SdlGpuGraphicsPipelineTargetInfo(
      color_target_descriptions: addr analytic_color_target_description,
      num_color_targets: 1,
      depth_stencil_format: sdl_gpu_texture_format_invalid,
      has_depth_stencil_target: false,
    ),
  )

  analytic_pipeline = create_gpu_graphics_pipeline(gpu_device, addr analytic_pipeline_create_info)

  instance_buffer_capacity = uint32(clay_get_max_element_count())
  instance_data = newSeqOfCap[SpriteInstance](int(instance_buffer_capacity))

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

  if analytic_pipeline == nil or quad_vertex_buffer == nil or
      instance_buffer == nil or instance_transfer_buffer == nil:
    return app_failure

  app_continue

proc sdl_app_event(appstate: pointer; event: ptr SdlEvent): SdlAppResult {.cdecl.} =
  discard appstate
  if event[].kind == sdl_event_quit:
    return app_success
  app_continue

proc measure_text(text: ClayStringSlice; config: ptr ClayTextElementConfig;
    user_data: pointer): ClayDimensions {.cdecl.} =
  discard user_data
  clay_dimensions(cfloat(text.length * int32(config[].font_size) div 2),
    cfloat(config[].font_size))

proc handle_error(error_data: ClayErrorData) {.cdecl.} =
  echo "Clay error: ", error_data.error_type

proc sdl_app_iterate(appstate: pointer): SdlAppResult {.cdecl.} =
  discard appstate

  let command_buffer = acquire_gpu_command_buffer(gpu_device)
  if command_buffer == nil:
    return app_failure

  var swapchain_texture: ptr SdlGpuTexture
  var width, height: uint32
  if not wait_and_acquire_gpu_swapchain_texture(command_buffer, window,
      addr swapchain_texture, addr width, addr height):
    return app_failure
  if swapchain_texture == nil:
    return app_continue

  clay_set_layout_dimensions(clay_dimensions(width, height))

  let commands = clay(1.0 / 60.0):
    element("root"):
      layout:
        sizing:
          width = grow()
          height = grow()
        padding = padding_all(18)
        child_gap = 14
        layout_direction = clay_top_to_bottom
      background_color = rgba(19, 24, 34, 255)
      corner_radius = corner_radius(16)
      border:
        color = rgba(75, 92, 124, 255)
        width = border_outside(2)

      element("header"):
        layout:
          sizing:
            width = grow()
            height = fixed(58)
          padding = padding_all(12)
          child_gap = 12
          layout_direction = clay_left_to_right
        background_color = rgba(31, 42, 59, 255)
        corner_radius = corner_radius(10)
        border:
          color = rgba(84, 108, 148, 255)
          width = border_outside(1)

        element("brand_mark"):
          layout:
            sizing:
              width = fixed(34)
              height = grow()
            child_alignment:
              x = clay_align_x_center
              y = clay_align_y_center
          background_color = rgba(82, 190, 177, 255)
          corner_radius = corner_radius(8)
          border:
            color = rgba(151, 241, 218, 255)
            width = border_outside(2)

        element("header_title"):
          layout:
            sizing:
              width = grow()
              height = grow()
            layout_direction = clay_top_to_bottom
            child_gap = 5
            child_alignment:
              y = clay_align_y_center
          background_color = rgba(43, 57, 79, 255)
          border:
            color = rgba(70, 91, 125, 255)
            width = clay_border_width(0, 0, 0, 1, 0)
          element("title_line"):
            layout:
              sizing:
                width = fixed(180)
                height = fixed(8)
            background_color = rgba(225, 235, 250, 255)
            corner_radius = corner_radius(4)
          element("subtitle_line"):
            layout:
              sizing:
                width = fixed(112)
                height = fixed(5)
            background_color = rgba(126, 151, 188, 255)
            corner_radius = corner_radius(3)

        element("header_status"):
          layout:
            sizing:
              width = fixed(108)
              height = grow()
            padding = padding_all(8)
            child_gap = 6
            layout_direction = clay_left_to_right
            child_alignment:
              y = clay_align_y_center
          background_color = rgba(25, 35, 50, 255)
          corner_radius = corner_radius(8)
          border:
            color = rgba(67, 93, 129, 255)
            width = border_outside(1)
          element("status_dot"):
            layout:
              sizing:
                width = fixed(10)
                height = fixed(10)
            background_color = rgba(92, 224, 157, 255)
            corner_radius = corner_radius(5)
          element("status_bar"):
            layout:
              sizing:
                width = grow()
                height = fixed(6)
            background_color = rgba(93, 132, 169, 255)
            corner_radius = corner_radius(3)

      element("body"):
        layout:
          sizing:
            width = grow()
            height = grow()
          child_gap = 14
          layout_direction = clay_left_to_right

        element("sidebar"):
          layout:
            sizing:
              width = fixed(154)
              height = grow()
            padding = padding_all(12)
            child_gap = 10
            layout_direction = clay_top_to_bottom
          background_color = rgba(28, 37, 52, 255)
          corner_radius = corner_radius(10)
          border:
            color = rgba(77, 99, 133, 255)
            width = border_outside(1)
          clip:
            horizontal = true
            vertical = true

          element("nav_heading"):
            layout:
              sizing:
                width = fixed(110)
                height = fixed(8)
            background_color = rgba(119, 148, 188, 255)
            corner_radius = corner_radius(4)
          for index in 0 ..< 8:
            element(clay_id_with_index("nav_item", uint32(index))):
              layout:
                sizing:
                  width = fixed(178)
                  height = fixed(32)
                padding = padding_all(8)
                child_gap = 7
                layout_direction = clay_left_to_right
              background_color = if index == 0:
                rgba(62, 105, 135, 255)
              else:
                rgba(34, 47, 66, 255)
              corner_radius = corner_radius(6)
              border:
                color = if index == 0:
                  rgba(107, 226, 198, 255)
                else:
                  rgba(58, 77, 105, 255)
                width = border_outside(1)
              element(clay_id_with_index("nav_glyph", uint32(index))):
                layout:
                  sizing:
                    width = fixed(8)
                    height = fixed(8)
                background_color = if index == 0:
                  rgba(142, 245, 214, 255)
                else:
                  rgba(109, 132, 164, 255)
                corner_radius = corner_radius(4)
              element(clay_id_with_index("nav_label", uint32(index))):
                layout:
                  sizing:
                    width = fixed(92)
                    height = fixed(5)
                background_color = rgba(103, 128, 161, 255)
                corner_radius = corner_radius(3)

        element("main_content"):
          layout:
            sizing:
              width = grow()
              height = grow()
            child_gap = 14
            layout_direction = clay_top_to_bottom

          element("metrics"):
            layout:
              sizing:
                width = grow()
                height = fixed(82)
              child_gap = 12
              layout_direction = clay_left_to_right
            for index, metric_color in [
                (rgba(50, 76, 106, 255), rgba(93, 195, 238, 255)),
                (rgba(49, 76, 75, 255), rgba(93, 224, 176, 255)),
                (rgba(75, 60, 91, 255), rgba(205, 143, 246, 255))]:
              element(clay_id_with_index("metric", uint32(index))):
                layout:
                  sizing:
                    width = grow()
                    height = grow()
                  padding = padding_all(12)
                  child_gap = 8
                  layout_direction = clay_top_to_bottom
                background_color = metric_color[0]
                corner_radius = corner_radius(9)
                border:
                  color = metric_color[1]
                  width = border_outside(1)
                element(clay_id_with_index("metric_value", uint32(index))):
                  layout:
                    sizing:
                      width = fixed(74 + index * 18)
                      height = fixed(12)
                  background_color = metric_color[1]
                  corner_radius = corner_radius(5)
                element(clay_id_with_index("metric_delta", uint32(index))):
                  layout:
                    sizing:
                      width = fixed(46 + index * 12)
                      height = fixed(5)
                  background_color = rgba(155, 176, 204, 255)
                  corner_radius = corner_radius(3)

          element("content_grid"):
            layout:
              sizing:
                width = grow()
                height = grow()
              child_gap = 14
              layout_direction = clay_left_to_right

            element("chart_panel"):
              layout:
                sizing:
                  width = percent(0.57)
                  height = grow()
                padding = padding_all(12)
                child_gap = 10
                layout_direction = clay_top_to_bottom
              background_color = rgba(29, 40, 56, 255)
              corner_radius = corner_radius(10)
              border:
                color = rgba(76, 104, 143, 255)
                width = border_outside(1)

              element("chart_header"):
                layout:
                  sizing:
                    width = grow()
                    height = fixed(18)
                  layout_direction = clay_left_to_right
                  child_alignment:
                    y = clay_align_y_center
                element("chart_title"):
                  layout:
                    sizing:
                      width = fixed(118)
                      height = fixed(7)
                  background_color = rgba(219, 231, 248, 255)
                  corner_radius = corner_radius(4)
                element("chart_action"):
                  layout:
                    sizing:
                      width = fixed(42)
                      height = fixed(7)
                  background_color = rgba(87, 122, 166, 255)
                  corner_radius = corner_radius(4)

              element("chart_clip"):
                layout:
                  sizing:
                    width = grow()
                    height = grow()
                  padding = padding_all(8)
                  layout_direction = clay_left_to_right
                background_color = rgba(20, 29, 42, 255)
                corner_radius = corner_radius(7)
                clip:
                  horizontal = true
                  vertical = true
                element("chart_canvas"):
                  layout:
                    sizing:
                      width = fixed(620)
                      height = fixed(214)
                    child_gap = 8
                    layout_direction = clay_left_to_right
                    child_alignment:
                      y = clay_align_y_bottom
                  background_color = rgba(24, 35, 50, 255)
                  corner_radius = corner_radius(6)
                  border:
                    color = rgba(75, 122, 151, 255)
                    width = border_outside(2)
                  for index in 0 ..< 14:
                    element(clay_id_with_index("bar", uint32(index))):
                      layout:
                        sizing:
                          width = fixed(24)
                          height = fixed(42 + ((index * 17) mod 122))
                      background_color = if index mod 3 == 0:
                        rgba(91, 208, 190, 255)
                      else:
                        rgba(63, 124, 174, 255)
                      corner_radius = corner_radius(4)

            element("activity_panel"):
              layout:
                sizing:
                  width = grow()
                  height = grow()
                padding = padding_all(12)
                child_gap = 10
                layout_direction = clay_top_to_bottom
              background_color = rgba(29, 40, 56, 255)
              corner_radius = corner_radius(10)
              border:
                color = rgba(76, 104, 143, 255)
                width = border_outside(1)
              clip:
                horizontal = true
                vertical = true

              element("activity_heading"):
                layout:
                  sizing:
                    width = fixed(136)
                    height = fixed(8)
                background_color = rgba(219, 231, 248, 255)
                corner_radius = corner_radius(4)
              for index in 0 ..< 11:
                element(clay_id_with_index("activity_row", uint32(index))):
                  layout:
                    sizing:
                      width = fixed(360)
                      height = fixed(34)
                    padding = padding_all(8)
                    child_gap = 8
                    layout_direction = clay_left_to_right
                  background_color = if index mod 2 == 0:
                    rgba(37, 52, 72, 255)
                  else:
                    rgba(32, 45, 63, 255)
                  border:
                    color = rgba(61, 83, 112, 255)
                    width = clay_border_width(0, 0, 0, 1, 0)
                  element(clay_id_with_index("activity_dot", uint32(index))):
                    layout:
                      sizing:
                        width = fixed(7)
                        height = fixed(7)
                    background_color = if index mod 4 == 0:
                      rgba(244, 188, 92, 255)
                    else:
                      rgba(106, 192, 232, 255)
                    corner_radius = corner_radius(4)
                  element(clay_id_with_index("activity_line", uint32(index))):
                    layout:
                      sizing:
                        width = fixed(170 + index * 8)
                        height = fixed(5)
                    background_color = rgba(114, 143, 178, 255)
                    corner_radius = corner_radius(3)

      element("footer"):
        layout:
          sizing:
              width = grow()
              height = fixed(28)
          padding = padding_all(8)
          child_alignment:
            y = clay_align_y_center
        background_color = rgba(27, 37, 52, 255)
        corner_radius = corner_radius(7)
        border:
          color = rgba(66, 86, 116, 255)
          width = border_outside(1)
        element("footer_indicator"):
          layout:
            sizing:
              width = fixed(220)
              height = fixed(5)
          background_color = rgba(91, 208, 190, 255)
          corner_radius = corner_radius(3)

  instance_data.setLen(0)
  clip_stack.setLen(0)
  clip_stack.add Rect(
    x: 0'f32,
    y: 0'f32,
    w: float32(width),
    h: float32(height),
  )

  for command in commands:
    case command.command_type:
    of clay_render_command_type_none: discard
    of clay_render_command_type_rectangle:
      let clip_rect = clip_stack[^1]
      let color = command.render_data.rectangle.background_color
      if not append_clipped_rect(command.bounding_box, clip_rect, color):
        return app_failure
    of clay_render_command_type_border:
      let box: Rect = command.bounding_box
      let color = command.render_data.border.color
      let border_widths = command.render_data.border.width
      let clip_rect = clip_stack[^1]

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
      for segment in [top, right, left, bottom]:
        if not append_clipped_rect(segment, clip_rect, color):
          return app_failure
    of clay_render_command_type_text: discard
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
    else: return app_failure

  let mapped_transfer_buffer = map_gpu_transfer_buffer(
    gpu_device,
    instance_transfer_buffer,
    true,
  )
  if mapped_transfer_buffer == nil:
    return app_failure

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

  let copy_pass = begin_gpu_copy_pass(command_buffer)
  if copy_pass == nil:
    return app_failure

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

  end_gpu_copy_pass(copy_pass)

  let width_f32 = float32(width)
  let height_f32 = float32(height)
  
  let color = extractRGB(palette.background)
  var target = SdlGpuColorTargetInfo(
    texture: swapchain_texture,
    clear_color: SdlFColor(
      r: cfloat(color.r) / 255.0,
      g: cfloat(color.g) / 255.0,
      b: cfloat(color.b) / 255.0,
      a: 1.0
    ),
    load_op: sdl_gpu_load_op_clear,
    store_op: sdl_gpu_store_op_store
  )
  let render_pass = begin_gpu_render_pass(command_buffer, addr target, 1, nil)
  if render_pass == nil:
    return app_failure

  bind_gpu_graphics_pipeline(render_pass, analytic_pipeline)

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
  if not submit_gpu_command_buffer(command_buffer):
    return app_failure
  quad_vertex_buffer_initialized = true
  app_continue

proc sdl_app_quit(appstate: pointer; result: SdlAppResult) {.cdecl.} =
  discard appstate
  discard result
  if gpu_device != nil:
    release_gpu_transfer_buffer(gpu_device, instance_transfer_buffer)
    release_gpu_buffer(gpu_device, instance_buffer)
    release_gpu_buffer(gpu_device, quad_vertex_buffer)
    release_gpu_graphics_pipeline(gpu_device, analytic_pipeline)
    if window != nil:
      release_window_from_gpu_device(gpu_device, window)
    destroy_gpu_device(gpu_device)
  if window != nil:
    destroy_window(window)

proc run_app_callbacks(argc: cint; argv: ptr ptr char): cint {.cdecl.} =
  enter_app_main_callbacks(argc, argv, sdl_app_init, sdl_app_iterate, sdl_app_event, sdl_app_quit)

proc main() =
  let memory_size = clay_min_memory_size()
  clay_arena = clay_create_arena_with_capacity_and_memory(memory_size,
    alloc0(int(memory_size)))
  discard clay_initialize(clay_arena, clay_dimensions(640, 480), ClayErrorHandler(
    error_handler_function: handle_error, user_data: nil))
  clay_set_measure_text_function(measure_text, nil)

  discard run_app(0, nil, run_app_callbacks, nil)

main()
