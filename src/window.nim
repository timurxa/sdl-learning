import clay, sdl

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

  WindowConfig* = object
    title*: string
    width*, height*: cint
    flags*: uint64
    clear_color*: ClayColor

  WindowView* = ref object of RootObj

method build_elements*(view: WindowView; frame: ViewFrame) {.base.} =
  discard view
  discard frame

method handle_event*(view: WindowView; event: ptr SdlEvent) {.base.} =
  discard view
  discard event

