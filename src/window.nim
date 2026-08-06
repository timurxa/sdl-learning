import clay, sdl
import ui
import renderer

type
  WindowConfig* = object
    title*: string
    width*, height*: cint
    flags*: uint64
    clear_color*: ClayColor

  WindowView* = ref object of RootObj

method build_elements*(view: WindowView; frame: ViewFrame) {.base.} =
  discard view
  discard frame

method render*(view: WindowView; renderer: Renderer; clay_context: ptr ClayContext;
    string_cache: var ClayStringCache; delta_time: float32): bool {.base.} =
  discard view
  discard renderer
  discard clay_context
  discard string_cache
  discard delta_time
  false

method set_window*(view: WindowView; window: ptr SdlWindow) {.base.} =
  discard view
  discard window

method handle_event*(view: WindowView; event: UiEvent) {.base.} =
  discard view
  discard event
