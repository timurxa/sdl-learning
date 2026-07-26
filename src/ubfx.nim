## Pure-Nim bitfield extraction intended to be recognized as AArch64 UBFX.

type
  Ubfx*[lsb, width: static[int]] = object
    ## A zero-sized extractor whose operands are part of its type.
    discard

proc init_ubfx*[lsb, width: static[int]](): Ubfx[lsb, width] =
  static:
    doAssert lsb >= 0 and lsb < 64
    doAssert width > 0 and width <= 64 - lsb

proc extract*[lsb, width: static[int]](
    _: Ubfx[lsb, width], value: uint64
  ): uint64 {.inline.} =
  when width == 64:
    value
  else:
    (value shr lsb) and ((1'u64 shl width) - 1)

proc ubfx*[lsb, width: static[int]](value: uint64): uint64 {.inline.} =
  init_ubfx[lsb, width]().extract(value)

proc test_ubfx(value: uint64): uint64 {.noinline.} =
  ubfx[4, 12](value)

proc test_ubfx_other(value: uint64): uint64 {.noinline.} =
  ubfx[17, 9](value)

proc ubfx_runtime*(value: uint64; lsb, width: int): uint64 =
  ## Safe fallback for operands that are only known at runtime.
  if lsb < 0 or lsb >= 64 or width <= 0 or width > 64 - lsb:
    raise newException(ValueError, "UBFX operands are out of range")
  if width == 64:
    return value shr lsb
  (value shr lsb) and ((1'u64 shl width) - 1)

when isMainModule:
  let value = 0xFEDC_BA98_7654_3210'u64
  doAssert ubfx[0, 8](value) == 0x10
  doAssert ubfx[4, 12](value) == 0x321
  doAssert init_ubfx[32, 16]().extract(value) == 0xBA98
  doAssert ubfx[0, 64](value) == value
  doAssert test_ubfx(value) == 0x321
  doAssert test_ubfx_other(value) == 0x12A
  doAssert ubfx_runtime(value, 4, 12) == 0x321

  try:
    discard ubfx_runtime(value, 63, 2)
    doAssert false
  except ValueError:
    discard

  echo "pure Nim UBFX tests passed"
