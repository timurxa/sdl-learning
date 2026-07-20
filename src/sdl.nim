{.passC: "-I/opt/homebrew/include -I/opt/homebrew/include/harfbuzz -DSDL_MAIN_HANDLED".}
{.passL: "-L/opt/homebrew/lib -lSDL3 -lharfbuzz".}

type
  SdlAppResult* {.importc: "SDL_AppResult", header: "SDL3/SDL_main.h".} = enum
    app_continue = 0
    app_success = 1
    app_failure = 2
  SdlEvent* {.importc: "SDL_Event", header: "SDL3/SDL.h".} = object
    kind* {.importc: "type".}: uint32
  SdlWindow* {.importc: "SDL_Window", header: "SDL3/SDL.h".} = object
  SdlGpuDevice* {.importc: "SDL_GPUDevice", header: "SDL3/SDL_gpu.h".} = object
  SdlGpuCommandBuffer* {.importc: "SDL_GPUCommandBuffer", header: "SDL3/SDL_gpu.h".} = object
  SdlGpuRenderPass* {.importc: "SDL_GPURenderPass", header: "SDL3/SDL_gpu.h".} = object
  SdlGpuTexture* {.importc: "SDL_GPUTexture", header: "SDL3/SDL_gpu.h".} = object
  SdlFColor* {.importc: "SDL_FColor", header: "SDL3/SDL_pixels.h".} = object
    r*: cfloat
    g*: cfloat
    b*: cfloat
    a*: cfloat
  SdlGpuColorTargetInfo* {.importc: "SDL_GPUColorTargetInfo", header: "SDL3/SDL_gpu.h".} = object
    texture*: ptr SdlGpuTexture
    mip_level*: uint32
    layer_or_depth_plane*: uint32
    clear_color*: SdlFColor
    load_op*: cint
    store_op*: cint
    resolve_texture*: ptr SdlGpuTexture
    resolve_mip_level*: uint32
    resolve_layer*: uint32
    cycle*: bool
    cycle_resolve_texture*: bool
    padding1*: uint8
    padding2*: uint8
  SdlAppInitFunc* = proc(appstate: ptr pointer; argc: cint; argv: ptr ptr char): SdlAppResult {.cdecl.}
  SdlAppIterateFunc* = proc(appstate: pointer): SdlAppResult {.cdecl.}
  SdlAppEventFunc* = proc(appstate: pointer; event: ptr SdlEvent): SdlAppResult {.cdecl.}
  SdlAppQuitFunc* = proc(appstate: pointer; result: SdlAppResult) {.cdecl.}
  SdlMainFunc* = proc(argc: cint; argv: ptr ptr char): cint {.cdecl.}

const
  sdl_gpu_shaderformat_msl* = 1'u32 shl 4
  sdl_gpu_load_op_clear* = 1.cint
  sdl_gpu_store_op_store* = 0.cint

var sdl_event_quit* {.importc: "SDL_EVENT_QUIT", header: "SDL3/SDL_events.h".}: uint32
var sdl_window_resizable* {.importc: "SDL_WINDOW_RESIZABLE", header: "SDL3/SDL_video.h".}: uint64
var sdl_window_borderless* {.importc: "SDL_WINDOW_BORDERLESS", header: "SDL3/SDL_video.h".}: uint64

proc enter_app_main_callbacks*(
    argc: cint; argv: ptr ptr char; appinit: SdlAppInitFunc;
    appiterate: SdlAppIterateFunc; appevent: SdlAppEventFunc;
    appquit: SdlAppQuitFunc
): cint {.importc: "SDL_EnterAppMainCallbacks", header: "SDL3/SDL_main.h".}

proc set_app_metadata*(name, version, identifier: cstring): bool
  {.importc: "SDL_SetAppMetadata", header: "SDL3/SDL_init.h".}

proc run_app*(argc: cint; argv: ptr ptr char; main_function: SdlMainFunc; reserved: pointer): cint
  {.importc: "SDL_RunApp", header: "SDL3/SDL_main.h".}

proc create_window*(
    title: cstring; width, height: cint; flags: uint64
): ptr SdlWindow {.importc: "SDL_CreateWindow", header: "SDL3/SDL_video.h".}

proc create_gpu_device*(
    format_flags: uint32; debug_mode: bool; name: cstring
): ptr SdlGpuDevice {.importc: "SDL_CreateGPUDevice", header: "SDL3/SDL_gpu.h".}

proc destroy_gpu_device*(device: ptr SdlGpuDevice)
  {.importc: "SDL_DestroyGPUDevice", header: "SDL3/SDL_gpu.h".}

proc claim_window_for_gpu_device*(device: ptr SdlGpuDevice; window: ptr SdlWindow): bool
  {.importc: "SDL_ClaimWindowForGPUDevice", header: "SDL3/SDL_gpu.h".}

proc release_window_from_gpu_device*(device: ptr SdlGpuDevice; window: ptr SdlWindow)
  {.importc: "SDL_ReleaseWindowFromGPUDevice", header: "SDL3/SDL_gpu.h".}

proc acquire_gpu_command_buffer*(device: ptr SdlGpuDevice): ptr SdlGpuCommandBuffer
  {.importc: "SDL_AcquireGPUCommandBuffer", header: "SDL3/SDL_gpu.h".}

proc wait_and_acquire_gpu_swapchain_texture*(
    command_buffer: ptr SdlGpuCommandBuffer; window: ptr SdlWindow;
    swapchain_texture: ptr ptr SdlGpuTexture; width, height: ptr uint32
): bool {.importc: "SDL_WaitAndAcquireGPUSwapchainTexture", header: "SDL3/SDL_gpu.h".}

proc begin_gpu_render_pass*(
    command_buffer: ptr SdlGpuCommandBuffer;
    color_target_infos: ptr SdlGpuColorTargetInfo;
    num_color_targets: uint32; depth_stencil_target_info: pointer
): ptr SdlGpuRenderPass {.importc: "SDL_BeginGPURenderPass", header: "SDL3/SDL_gpu.h".}

proc end_gpu_render_pass*(render_pass: ptr SdlGpuRenderPass)
  {.importc: "SDL_EndGPURenderPass", header: "SDL3/SDL_gpu.h".}

proc submit_gpu_command_buffer*(command_buffer: ptr SdlGpuCommandBuffer): bool
  {.importc: "SDL_SubmitGPUCommandBuffer", header: "SDL3/SDL_gpu.h".}

proc destroy_window*(window: ptr SdlWindow)
  {.importc: "SDL_DestroyWindow", header: "SDL3/SDL_video.h".}
