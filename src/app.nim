import std/deques
import std/locks
import clay
import sdl
import utf8proc
import main_window
import renderer
import ui
import window

type
  WindowKind = enum
    window_kind_main

  WindowState = ref object
    window_id: uint32
    sdl_window: ptr SdlWindow
    config: WindowConfig
    clay_arena_memory: pointer
    clay_arena: ClayArena
    clay_context: ptr ClayContext
    clay_string_cache: ClayStringCache
    renderer: Renderer
    case kind: WindowKind
    of window_kind_main:
      main_window: MainWindow

  AppState = ref object
    windows: seq[WindowState]
    event_queue: Deque[UiEvent]
    event_lock: Lock

var app_state_root: AppState

proc init_window_state(
    state: var WindowState;
    main_window: MainWindow;
    config: WindowConfig;
    window_id: uint32
  ): bool =
  state = WindowState(
    kind: window_kind_main,
    window_id: window_id,
    config: config,
    main_window: main_window)
  state.sdl_window = create_window(
    config.title.cstring,
    config.width,
    config.height,
    config.flags)
  if state.sdl_window == nil:
    state = nil
    return false
  state.window_id = get_window_id(state.sdl_window)

  let memory_size = clay_min_memory_size()
  state.clay_arena_memory = alloc0(int(memory_size))
  state.clay_arena = clay_create_arena_with_capacity_and_memory(
    memory_size,
    state.clay_arena_memory)
  state.clay_context = clay_initialize(
    state.clay_arena,
    clay_dimensions(config.width, config.height),
    ClayErrorHandler(
      error_handler_function: handle_error,
      user_data: nil))
  if state.clay_context == nil:
    destroy_window(state.sdl_window)
    dealloc(state.clay_arena_memory)
    state = nil
    return false

  state.renderer = new_renderer()
  if not init_renderer(state.renderer, state.sdl_window, config.clear_color):
    clay_deinitialize()
    dealloc(state.clay_arena_memory)
    deinit_renderer(state.renderer)
    destroy_window(state.sdl_window)
    state = nil
    return false

  clay_set_measure_text_function(measure_text, nil)
  clay_set_grapheme_boundary_function(utf8proc_next_grapheme_boundary, nil)
  true

proc deinit_window_state(state: WindowState) =
  if state == nil:
    return

  if state.clay_context != nil:
    clay_set_current_context(state.clay_context)
    clay_deinitialize()
  clay_string_cache_deinit(state.clay_string_cache)
  if state.clay_arena_memory != nil:
    dealloc(state.clay_arena_memory)
  if state.renderer != nil:
    deinit_renderer(state.renderer)
  if state.sdl_window != nil:
    destroy_window(state.sdl_window)

proc new_app_state(): AppState =
  new(result)
  result.event_queue = initDeque[UiEvent]()
  initLock(result.event_lock)

proc dispatch_events(state: AppState) =
  while true:
    var event: UiEvent
    acquire(state.event_lock)
    if state.event_queue.len == 0:
      release(state.event_lock)
      break
    event = popFirst(state.event_queue)
    release(state.event_lock)

    for window in state.windows:
      if event.window_id == 0 or event.window_id == window.window_id:
        case window.kind:
        of window_kind_main:
          window.main_window.handle_event(event)

proc sdl_app_init(appstate: ptr pointer; argc: cint;
    argv: ptr ptr char): SdlAppResult {.cdecl.} =
  discard argc
  discard argv
  if not set_app_metadata("SDL GPU Window", "1.0", "com.example.sdl-gpu-window"):
    return app_failure

  app_state_root = new_app_state()
  let main_window = new_main_window()
  let config = WindowConfig(
    title: "SDL GPU Window",
    width: 640,
    height: 480,
    flags: sdl_window_resizable or sdl_window_borderless or
      sdl_window_high_pixel_density,
    clear_color: main_window.background_color())

  var window_state: WindowState
  if not init_window_state(window_state, main_window, config, 0):
    deinitLock(app_state_root.event_lock)
    app_state_root = nil
    return app_failure
  case window_state.kind:
  of window_kind_main:
    window_state.main_window.set_window(window_state.sdl_window)

  app_state_root.windows.add(window_state)
  appstate[] = cast[pointer](app_state_root)
  app_continue

proc sdl_app_event(appstate: pointer; event: ptr SdlEvent): SdlAppResult {.cdecl.} =
  if event[].kind == sdl_event_quit:
    return app_success
  if appstate == nil:
    return app_failure

  let state = cast[AppState](appstate)
  let ui_event = to_ui_event(event)
  if ui_event.kind == ui_event_none:
    return app_continue
  acquire(state.event_lock)
  state.event_queue.addLast(ui_event)
  release(state.event_lock)
  app_continue

proc sdl_app_iterate(appstate: pointer): SdlAppResult {.cdecl.} =
  if appstate == nil:
    return app_failure

  let state = cast[AppState](appstate)
  dispatch_events(state)
  for window in state.windows:
    case window.kind:
    of window_kind_main:
      if not window.main_window.render(
          window.renderer,
          window.clay_context,
          window.clay_string_cache,
          1.0 / 60.0):
        return app_failure
  app_continue

proc sdl_app_quit(appstate: pointer; result: SdlAppResult) {.cdecl.} =
  discard result
  let state = cast[AppState](appstate)
  if state == nil:
    return

  for window in state.windows:
    deinit_window_state(window)
  state.windows.setLen(0)
  state.event_queue.clear()
  deinitLock(state.event_lock)
  app_state_root = nil

proc run_app_callbacks(argc: cint; argv: ptr ptr char): cint {.cdecl.} =
  enter_app_main_callbacks(
    argc,
    argv,
    sdl_app_init,
    sdl_app_iterate,
    sdl_app_event,
    sdl_app_quit)

proc run_application*(): cint =
  run_app(0, nil, run_app_callbacks, nil)
