import clay

type
  WindowConfig* = object
    title*: string
    width*, height*: cint
    flags*: uint64
    clear_color*: ClayColor
