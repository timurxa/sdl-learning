import std/colors
import clay
import sdl

type
  Palette = object
    background: Color

var
  window: ptr SdlWindow
  gpu_device: ptr SdlGpuDevice
  palette = Palette(background: rgb(0, 0, 0))

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
  app_continue

proc sdl_app_event(appstate: pointer; event: ptr SdlEvent): SdlAppResult {.cdecl.} =
  discard appstate
  if event[].kind == sdl_event_quit:
    return app_success
  app_continue

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
  end_gpu_render_pass(render_pass)
  if not submit_gpu_command_buffer(command_buffer):
    return app_failure
  app_continue

proc sdl_app_quit(appstate: pointer; result: SdlAppResult) {.cdecl.} =
  discard appstate
  discard result
  if gpu_device != nil:
    if window != nil:
      release_window_from_gpu_device(gpu_device, window)
    destroy_gpu_device(gpu_device)
  if window != nil:
    destroy_window(window)

proc run_app_callbacks(argc: cint; argv: ptr ptr char): cint {.cdecl.} =
  enter_app_main_callbacks(argc, argv, sdl_app_init, sdl_app_iterate, sdl_app_event, sdl_app_quit)

proc main() =
  discard run_app(0, nil, run_app_callbacks, nil)

  proc measure_text(text: ClayStringSlice; config: ptr ClayTextElementConfig;
      user_data: pointer): ClayDimensions {.cdecl.} =
    discard user_data
    clay_dimensions(cfloat(text.length * int32(config[].font_size) div 2),
      cfloat(config[].font_size))

  proc handle_error(error_data: ClayErrorData) {.cdecl.} =
    echo "Clay error: ", error_data.error_type

  let memory_size = clay_min_memory_size()
  var clay_memory = newSeq[byte](int(memory_size))
  let arena = clay_create_arena_with_capacity_and_memory(memory_size,
    addr clay_memory[0])
  discard clay_initialize(arena, clay_dimensions(640, 480), ClayErrorHandler(
    error_handler_function: handle_error, user_data: nil))
  clay_set_measure_text_function(measure_text, nil)

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

      element("card"):
        layout:
          sizing:
            width = fixed(360)
            height = fit()
          padding = padding_all(20)
          child_gap = 10
          child_alignment:
            x = clay_align_x_center
        background_color = rgba(48, 56, 72, 255)
        corner_radius = corner_radius(12)
        border:
          color = rgba(105, 120, 150, 255)
          width = border_outside(2)

        text("Clay test UI"):
          font_size = 26
          text_color = rgba(255, 255, 255, 255)
          text_alignment = clay_text_align_center

        text("Generated from a declarative layout"):
          font_size = 16
          text_color = rgba(190, 205, 225, 255)
          text_alignment = clay_text_align_center

  echo "Generated ", commands.length, " render commands:"
  for index in 0 ..< commands.length:
    let command = clay_render_command_array_get(commands, index)
    let box = command.bounding_box
    echo "[", index, "] type=", command.command_type,
      " x=", box.x, " y=", box.y,
      " w=", box.width, " h=", box.height

main()
