import std/colors
import std/math
import std/os
import clay, sdl

type
  QuadVertex = object
    corners: array[2, float32]
  SpriteInstance = object
    origin: array[2, uint16]
    size: array[2, uint16]
    color: array[4, uint8]
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

  palette = Palette(background: rgb(0, 0, 0))

  clay_arena: ClayArena

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
      # false means SDL writes all RGBA channels.
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
        padding = padding_all(24)
        child_gap = 16
        layout_direction = clay_top_to_bottom
      background_color = rgba(24, 28, 36, 255)

      element("top_bar"):
        layout:
          sizing:
            width = grow()
            height = fixed(64)
        background_color = rgba(52, 64, 86, 255)

      element("content"):
        layout:
          sizing:
            width = grow()
            height = grow()
          child_gap = 16
          layout_direction = clay_left_to_right

        element("sidebar"):
          layout:
            sizing:
              width = fixed(180)
              height = grow()
            padding = padding_all(12)
            child_gap = 10
            layout_direction = clay_top_to_bottom
          background_color = rgba(38, 46, 62, 255)

          element("sidebar_item_1"):
            layout:
              sizing:
                width = grow()
                height = fixed(40)
            background_color = rgba(72, 91, 124, 255)

          element("sidebar_item_2"):
            layout:
              sizing:
                width = grow()
                height = fixed(40)
            background_color = rgba(55, 67, 91, 255)

          element("sidebar_item_3"):
            layout:
              sizing:
                width = grow()
                height = fixed(40)
            background_color = rgba(55, 67, 91, 255)

        element("main_panel"):
          layout:
            sizing:
              width = grow()
              height = grow()
            padding = padding_all(16)
            child_gap = 16
            layout_direction = clay_top_to_bottom
          background_color = rgba(44, 52, 70, 255)

          element("hero"):
            layout:
              sizing:
                width = grow()
                height = fixed(120)
            background_color = rgba(75, 94, 130, 255)

          element("card_row"):
            layout:
              sizing:
                width = grow()
                height = fixed(140)
              child_gap = 12
              layout_direction = clay_left_to_right

            element("card_1"):
              layout:
                sizing:
                  width = grow()
                  height = grow()
              background_color = rgba(64, 78, 105, 255)

            element("card_2"):
              layout:
                sizing:
                  width = grow()
                  height = grow()
              background_color = rgba(58, 73, 99, 255)

            element("card_3"):
              layout:
                sizing:
                  width = grow()
                  height = grow()
              background_color = rgba(68, 82, 108, 255)

          element("lower_panel"):
            layout:
              sizing:
                width = grow()
                height = grow()
            background_color = rgba(35, 43, 58, 255)

      element("footer"):
        layout:
          sizing:
            width = grow()
            height = fixed(48)
        background_color = rgba(52, 64, 86, 255)

  instance_data.setLen(0)
  for command in commands:
    if command.command_type != clay_render_command_type_rectangle:
      continue
    if instance_data.len >= int(instance_buffer_capacity):
      return app_failure
    let box = command.bounding_box
    let color = command.render_data.rectangle.background_color
    let x0 = floor(box.x)
    let y0 = floor(box.y)
    let x1 = ceil(box.x + box.width)
    let y1 = ceil(box.y + box.height)
    instance_data.add(SpriteInstance(
      origin: [uint16(x0), uint16(y0)],
      size: [uint16(x1 - x0), uint16(y1 - y0)],
      color: [
        uint8(color.r),
        uint8(color.g),
        uint8(color.b),
        uint8(color.a),
      ],
    ))

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
