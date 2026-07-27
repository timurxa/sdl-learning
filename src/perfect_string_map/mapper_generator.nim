import std/math
import std/bitops
import std/algorithm

type ByteGroup* = seq[uint64]

# for each length partition, we have N static keys
# which we'll map into M = 2 * next_pow_2(N) slots
# we'll have approximately B = N/4 buckets
# then construct simple H1(tuple) -> bucket
# pilot = pilots[bucket]
# H2(G(tuple), pilot) -> slot

type
  GKind* = enum
    g_raw_word,
    g_xor_right_shift,
  G* = object
    word_index*: int
    case kind*: GKind
    of g_raw_word:
      discard
    of g_xor_right_shift:
      shift*: range[1 .. 63]
  InstructionKind* = enum
    in_and,
    in_xor,
    in_add,
    in_sub,
    in_ror,
    in_extr,
    in_mul,
    in_umulh,
    in_madd,
    in_msub,
    in_ubfx,
  PremixKind* = enum
    no_premix,
    rotate_right,
    xor_simple,
    xor_right_shift,
    xor_left_shift,
    xor_rotate_right,
    add_simple,
    add_left_shift,
    add_right_shift,
    sub_simple,
    sub_left_shift,
    sub_right_shift,
    multiply_self,
    multiply_high_self,
    multiply_add_self,
    multiply_sub_self,
    multiply_constant,
  OperandKind* = enum
    op_input,
    op_constant,
    op_instruction,
  Operand* = object
    case kind*: OperandKind
    of op_input:
      index*: int
    of op_constant:
      value*: uint64
    of op_instruction:
      instruction*: Instruction
  Instruction* = ref object
    case kind*: InstructionKind
    of in_and:
      left*, right*: Operand
    of in_xor:
      source*: Operand
      shifted_source*: Operand
      shift*: Operand
      premix_kind*: PremixKind
    of in_add:
      add_source*: Operand
      add_shifted_source*: Operand
      add_shift*: Operand
      add_premix_kind*: PremixKind
    of in_sub:
      sub_source*: Operand
      sub_shifted_source*: Operand
      sub_shift*: Operand
      sub_premix_kind*: PremixKind
    of in_ror:
      ror_source*: Operand
      ror_shift*: Operand
    of in_extr:
      extr_left*: Operand
      extr_right*: Operand
      extr_shift*: Operand
    of in_mul:
      mul_left*: Operand
      mul_right*: Operand
    of in_umulh:
      umulh_left*: Operand
      umulh_right*: Operand
    of in_madd:
      madd_left*: Operand
      madd_right*: Operand
      madd_addend*: Operand
    of in_msub:
      msub_left*: Operand
      msub_right*: Operand
      msub_subtrahend*: Operand
    of in_ubfx:
      input*: Operand
      pos*: Operand
      len*: Operand
  Mapper* = object
    mixer*: Instruction
    g*: G
    pilots*: seq[uint16]
  SearchCandidate = object
    instruction: Instruction
    g: G
    cost: float
  Bucket = object
    id: int
    g_values: seq[uint64]
  CrossKind = enum
    cross_xor_simple,
    cross_add_simple,
    cross_sub_simple,
    cross_extr,
    cross_xor_left_shift,
    cross_xor_right_shift,
    cross_xor_rotate_right,
    cross_add_left_shift,
    cross_add_right_shift,
    cross_sub_left_shift,
    cross_sub_right_shift,
    cross_mul,
    cross_umulh,
    cross_madd,
    cross_msub,
    cross_mul_constant,
    cross_umulh_constant,
    cross_madd_constant,
    cross_msub_constant,
  CrossExpression = object
    kind: CrossKind
    left, right, third: int
    shift: int
    constant: uint64

proc `$`*(instruction: Instruction): string = $(instruction[])

proc evaluate*(g: G; group: ByteGroup): uint64 =
  let word = group[g.word_index]
  case g.kind
  of g_raw_word:
    word
  of g_xor_right_shift:
    word xor (word shr g.shift)

proc g_cost(g: G): float =
  case g.kind
  of g_raw_word:
    0.0
  of g_xor_right_shift:
    2.0

iterator g_candidates(word_count: int): G =
  for word_index in 0 ..< word_count:
    yield G(kind: g_raw_word, word_index: word_index)
  for word_index in 0 ..< word_count:
    for shift in 1 .. 63:
      yield G(
        kind: g_xor_right_shift,
        word_index: word_index,
        shift: shift,
      )

proc submixer(value: uint64; bit_count: int): uint64 =
  if bit_count == 0:
    0'u64
  else:
    value and ((1'u64 shl bit_count) - 1'u64)

template next_generation(seen: var seq[uint32]; generation: var uint32) =
  if generation == high(uint32):
    for index in 0 ..< seen.len:
      seen[index] = 0
    generation = 1
  else:
    inc generation

proc ubfx_runtime(value: uint64; lsb, width: int): uint64 =
  if lsb < 0 or lsb >= 64 or width <= 0 or width > 64 - lsb:
    raise newException(ValueError, "UBFX operands are out of range")
  if width == 64:
    return value shr lsb
  (value shr lsb) and ((1'u64 shl width) - 1)

proc high_product(left, right: uint64): uint64 =
  const word_mask = 0xFFFF_FFFF'u64
  let left_low = left and word_mask
  let left_high = left shr 32
  let right_low = right and word_mask
  let right_high = right shr 32
  let product_low = left_low * right_low
  let product_low_high = product_low shr 32
  let product_middle = product_low_high +
    (left_high * right_low and word_mask) +
    (left_low * right_high and word_mask)
  result = left_high * right_high +
    (left_high * right_low shr 32) +
    (left_low * right_high shr 32) +
    (product_middle shr 32)

proc extr_value(left, right: uint64; shift: int): uint64
proc evaluate*(instruction: Instruction; group: ByteGroup): uint64

proc evaluate(operand: Operand; group: ByteGroup): uint64 =
  case operand.kind
  of op_input:
    group[operand.index]
  of op_constant:
    operand.value
  of op_instruction:
    evaluate(operand.instruction, group)

proc evaluate*(instruction: Instruction; group: ByteGroup): uint64 =
  case instruction.kind
  of in_and:
    evaluate(instruction.left, group) and evaluate(instruction.right, group)
  of in_xor:
    let source = evaluate(instruction.source, group)
    let shifted_source = evaluate(instruction.shifted_source, group)
    let shift = int(evaluate(instruction.shift, group))
    case instruction.premix_kind
    of xor_simple:
      source xor shifted_source
    of xor_left_shift:
      source xor (shifted_source shl shift)
    of xor_right_shift:
      source xor (shifted_source shr shift)
    of xor_rotate_right:
      source xor rotateRightBits(
        shifted_source, range[0 .. 64](shift))
    else:
      raise newException(ValueError, "Invalid XOR premix kind")
  of in_add:
    let source = evaluate(instruction.add_source, group)
    let shifted_source = evaluate(instruction.add_shifted_source, group)
    let shift = int(evaluate(instruction.add_shift, group))
    case instruction.add_premix_kind
    of add_simple:
      source + shifted_source
    of add_left_shift:
      source + (shifted_source shl shift)
    of add_right_shift:
      source + (shifted_source shr shift)
    else:
      raise newException(ValueError, "Invalid ADD premix kind")
  of in_sub:
    let source = evaluate(instruction.sub_source, group)
    let shifted_source = evaluate(instruction.sub_shifted_source, group)
    let shift = int(evaluate(instruction.sub_shift, group))
    case instruction.sub_premix_kind
    of sub_simple:
      source - shifted_source
    of sub_left_shift:
      source - (shifted_source shl shift)
    of sub_right_shift:
      source - (shifted_source shr shift)
    else:
      raise newException(ValueError, "Invalid SUB premix kind")
  of in_ror:
    rotateRightBits(
      evaluate(instruction.ror_source, group),
      range[0 .. 64](evaluate(instruction.ror_shift, group)))
  of in_extr:
    extr_value(
      evaluate(instruction.extr_left, group),
      evaluate(instruction.extr_right, group),
      int(evaluate(instruction.extr_shift, group)))
  of in_mul:
    evaluate(instruction.mul_left, group) *
      evaluate(instruction.mul_right, group)
  of in_umulh:
    high_product(
      evaluate(instruction.umulh_left, group),
      evaluate(instruction.umulh_right, group))
  of in_madd:
    evaluate(instruction.madd_left, group) *
      evaluate(instruction.madd_right, group) +
      evaluate(instruction.madd_addend, group)
  of in_msub:
    evaluate(instruction.msub_subtrahend, group) -
      (evaluate(instruction.msub_left, group) *
       evaluate(instruction.msub_right, group))
  of in_ubfx:
    ubfx_runtime(
      evaluate(instruction.input, group),
      int(evaluate(instruction.pos, group)),
      int(evaluate(instruction.len, group)))

proc premix_value(value: uint64; premix_kind: PremixKind; shift: int): uint64 =
  case premix_kind
  of no_premix:
    value
  of rotate_right:
    rotateRightBits(value, range[0 .. 64](shift))
  of xor_simple, add_simple, sub_simple:
    raise newException(ValueError, "Cross-only premix kind")
  of xor_right_shift:
    value xor (value shr shift)
  of xor_left_shift:
    value xor (value shl shift)
  of xor_rotate_right:
    value xor rotateRightBits(value, range[0 .. 64](shift))
  of add_left_shift:
    value + (value shl shift)
  of add_right_shift:
    value + (value shr shift)
  of sub_left_shift:
    value - (value shl shift)
  of sub_right_shift:
    value - (value shr shift)
  of multiply_self:
    value * value
  of multiply_high_self:
    high_product(value, value)
  of multiply_add_self:
    value * value + value
  of multiply_sub_self:
    value - value * value
  of multiply_constant:
    value * uint64(shift)

proc instruction_cost(premix_kind: PremixKind): float =
  case premix_kind
  of no_premix:
    1.0 # UBFX
  of rotate_right:
    2.0 # ROR + UBFX
  of xor_simple, add_simple, sub_simple:
    2.0 # simple binary op + UBFX
  of xor_right_shift, xor_left_shift, xor_rotate_right,
      add_left_shift, add_right_shift, sub_left_shift, sub_right_shift:
    3.0 # shifted/rotated EOR or shifted ADD/SUB + UBFX
  of multiply_self, multiply_high_self, multiply_add_self, multiply_sub_self:
    4.0 # multiply + UBFX
  of multiply_constant:
    4.1 # MUL + MOVZ + UBFX

proc premix_operand(
    premix_kind: PremixKind; shift, input_index: int
  ): Operand =
  case premix_kind
  of no_premix:
    Operand(kind: op_input, index: input_index)
  of xor_simple, add_simple, sub_simple:
    raise newException(ValueError, "Cross-only premix kind")
  of rotate_right:
    Operand(
      kind: op_instruction,
      instruction: Instruction(
        kind: in_ror,
        ror_source: Operand(kind: op_input, index: input_index),
        ror_shift: Operand(kind: op_constant, value: uint64(shift)),
      ),
    )

  of xor_right_shift, xor_left_shift, xor_rotate_right:
    Operand(
      kind: op_instruction,
      instruction: Instruction(
        kind: in_xor,
        source: Operand(kind: op_input, index: input_index),
        shifted_source: Operand(kind: op_input, index: input_index),
        shift: Operand(kind: op_constant, value: uint64(shift)),
        premix_kind: premix_kind,
      ),
    )
  of add_left_shift, add_right_shift:
    Operand(
      kind: op_instruction,
      instruction: Instruction(
        kind: in_add,
        add_source: Operand(kind: op_input, index: input_index),
        add_shifted_source: Operand(kind: op_input, index: input_index),
        add_shift: Operand(kind: op_constant, value: uint64(shift)),
        add_premix_kind: premix_kind,
      ),
    )
  of sub_left_shift, sub_right_shift:
    Operand(
      kind: op_instruction,
      instruction: Instruction(
        kind: in_sub,
        sub_source: Operand(kind: op_input, index: input_index),
        sub_shifted_source: Operand(kind: op_input, index: input_index),
        sub_shift: Operand(kind: op_constant, value: uint64(shift)),
        sub_premix_kind: premix_kind,
      ),
    )
  of multiply_self:
    Operand(
      kind: op_instruction,
      instruction: Instruction(
        kind: in_mul,
        mul_left: Operand(kind: op_input, index: input_index),
        mul_right: Operand(kind: op_input, index: input_index),
      ),
    )
  of multiply_high_self:
    Operand(
      kind: op_instruction,
      instruction: Instruction(
        kind: in_umulh,
        umulh_left: Operand(kind: op_input, index: input_index),
        umulh_right: Operand(kind: op_input, index: input_index),
      ),
    )
  of multiply_add_self:
    Operand(
      kind: op_instruction,
      instruction: Instruction(
        kind: in_madd,
        madd_left: Operand(kind: op_input, index: input_index),
        madd_right: Operand(kind: op_input, index: input_index),
        madd_addend: Operand(kind: op_input, index: input_index),
      ),
    )
  of multiply_sub_self:
    Operand(
      kind: op_instruction,
      instruction: Instruction(
        kind: in_msub,
        msub_left: Operand(kind: op_input, index: input_index),
        msub_right: Operand(kind: op_input, index: input_index),
        msub_subtrahend: Operand(kind: op_input, index: input_index),
      ),
    )
  of multiply_constant:
    Operand(
      kind: op_instruction,
      instruction: Instruction(
        kind: in_mul,
        mul_left: Operand(kind: op_input, index: input_index),
        mul_right: Operand(kind: op_constant, value: uint64(shift)),
      ),
    )

proc input_operand(index: int): Operand =
  Operand(kind: op_input, index: index)

proc constant_operand(value: uint64): Operand =
  Operand(kind: op_constant, value: value)

proc extr_value(left, right: uint64; shift: int): uint64 =
  (left shr shift) or (right shl (64 - shift))

proc cross_value(group: ByteGroup; expression: CrossExpression): uint64 =
  let left = group[expression.left]
  let right = group[expression.right]
  let third = if expression.third >= 0: group[expression.third] else: 0'u64
  case expression.kind
  of cross_xor_simple:
    left xor right
  of cross_add_simple:
    left + right
  of cross_sub_simple:
    left - right
  of cross_extr:
    extr_value(left, right, expression.shift)
  of cross_xor_left_shift:
    left xor (right shl expression.shift)
  of cross_xor_right_shift:
    left xor (right shr expression.shift)
  of cross_xor_rotate_right:
    left xor rotateRightBits(right, range[0 .. 64](expression.shift))
  of cross_add_left_shift:
    left + (right shl expression.shift)
  of cross_add_right_shift:
    left + (right shr expression.shift)
  of cross_sub_left_shift:
    left - (right shl expression.shift)
  of cross_sub_right_shift:
    left - (right shr expression.shift)
  of cross_mul:
    left * right
  of cross_umulh:
    high_product(left, right)
  of cross_madd:
    left * right + third
  of cross_msub:
    third - left * right
  of cross_mul_constant:
    left * expression.constant
  of cross_umulh_constant:
    high_product(left, expression.constant)
  of cross_madd_constant:
    left * expression.constant + third
  of cross_msub_constant:
    third - left * expression.constant

proc cross_instruction(expression: CrossExpression): Instruction =
  let left = input_operand(expression.left)
  let right = input_operand(expression.right)
  let third = input_operand(expression.third)
  let shift = constant_operand(uint64(expression.shift))
  case expression.kind
  of cross_xor_simple:
    Instruction(kind: in_xor, source: left, shifted_source: right,
      shift: constant_operand(0), premix_kind: xor_simple)
  of cross_add_simple:
    Instruction(kind: in_add, add_source: left, add_shifted_source: right,
      add_shift: constant_operand(0), add_premix_kind: add_simple)
  of cross_sub_simple:
    Instruction(kind: in_sub, sub_source: left, sub_shifted_source: right,
      sub_shift: constant_operand(0), sub_premix_kind: sub_simple)
  of cross_extr:
    Instruction(kind: in_extr, extr_left: left, extr_right: right,
      extr_shift: shift)
  of cross_xor_left_shift:
    Instruction(kind: in_xor, source: left, shifted_source: right, shift: shift,
      premix_kind: xor_left_shift)
  of cross_xor_right_shift:
    Instruction(kind: in_xor, source: left, shifted_source: right, shift: shift,
      premix_kind: xor_right_shift)
  of cross_xor_rotate_right:
    Instruction(kind: in_xor, source: left, shifted_source: right, shift: shift,
      premix_kind: xor_rotate_right)
  of cross_add_left_shift:
    Instruction(kind: in_add, add_source: left, add_shifted_source: right,
      add_shift: shift,
      add_premix_kind: add_left_shift)
  of cross_add_right_shift:
    Instruction(kind: in_add, add_source: left, add_shifted_source: right,
      add_shift: shift,
      add_premix_kind: add_right_shift)
  of cross_sub_left_shift:
    Instruction(kind: in_sub, sub_source: left, sub_shifted_source: right,
      sub_shift: shift,
      sub_premix_kind: sub_left_shift)
  of cross_sub_right_shift:
    Instruction(kind: in_sub, sub_source: left, sub_shifted_source: right,
      sub_shift: shift,
      sub_premix_kind: sub_right_shift)
  of cross_mul:
    Instruction(kind: in_mul, mul_left: left, mul_right: right)
  of cross_umulh:
    Instruction(kind: in_umulh, umulh_left: left, umulh_right: right)
  of cross_madd:
    Instruction(kind: in_madd, madd_left: left, madd_right: right,
      madd_addend: third)
  of cross_msub:
    Instruction(kind: in_msub, msub_left: left, msub_right: right,
      msub_subtrahend: third)
  of cross_mul_constant:
    Instruction(kind: in_mul, mul_left: left,
      mul_right: constant_operand(expression.constant))
  of cross_umulh_constant:
    Instruction(kind: in_umulh, umulh_left: left,
      umulh_right: constant_operand(expression.constant))
  of cross_madd_constant:
    Instruction(kind: in_madd, madd_left: left,
      madd_right: constant_operand(expression.constant), madd_addend: third)
  of cross_msub_constant:
    Instruction(kind: in_msub, msub_left: left,
      msub_right: constant_operand(expression.constant), msub_subtrahend: third)

proc cross_instruction_cost(kind: CrossKind): float =
  case kind
  of cross_xor_simple, cross_add_simple, cross_sub_simple, cross_extr:
    2.0
  of cross_xor_left_shift, cross_xor_right_shift, cross_xor_rotate_right,
      cross_add_left_shift, cross_add_right_shift,
      cross_sub_left_shift, cross_sub_right_shift:
    3.0
  of cross_mul, cross_umulh, cross_madd, cross_msub:
    4.0
  of cross_mul_constant, cross_umulh_constant,
      cross_madd_constant, cross_msub_constant:
    4.1

const retained_candidate_count = 16

proc retain_candidate(
    candidates: var seq[SearchCandidate]; candidate: SearchCandidate
  ) =
  var insertion_index = 0
  while insertion_index < candidates.len and
      candidates[insertion_index].cost <= candidate.cost:
    inc insertion_index
  if insertion_index >= retained_candidate_count:
    return
  candidates.insert(candidate, insertion_index)
  if candidates.len > retained_candidate_count:
    candidates.setLen(retained_candidate_count)

proc cannot_improve(candidates: seq[SearchCandidate]; cost: float): bool =
  candidates.len == retained_candidate_count and candidates[^1].cost <= cost

proc find_cross_separator(
    byte_groups: seq[ByteGroup]; expression: CrossExpression;
    bucket_bit_count, submixer_bit_count: int;
    candidates: var seq[SearchCandidate];
    seen: var seq[uint32]; generation: var uint32
  ) =
  let h1_cost = cross_instruction_cost(expression.kind)
  if candidates.cannot_improve(h1_cost):
    return

  for g in g_candidates(byte_groups[0].len):
    let total_cost = h1_cost + g_cost(g)
    if candidates.cannot_improve(total_cost):
      continue
    for offset in 0 .. 64 - bucket_bit_count:
      next_generation(seen, generation)
      var valid = true
      for group in byte_groups:
        let bucket = ubfx_runtime(
          cross_value(group, expression), offset, bucket_bit_count)
        let sub = submixer(evaluate(g, group), submixer_bit_count)
        let index = int((bucket shl submixer_bit_count) or sub)
        if seen[index] == generation:
          valid = false
          break
        seen[index] = generation

      if valid:
        candidates.retain_candidate(SearchCandidate(
          instruction: Instruction(
            kind: in_ubfx,
            input: Operand(
              kind: op_instruction,
              instruction: cross_instruction(expression),
            ),
            pos: constant_operand(uint64(offset)),
            len: constant_operand(uint64(bucket_bit_count)),
          ),
          g: g,
          cost: total_cost,
        ))
        break

proc make_cross_expression(
    kind: CrossKind; left, right: int; third = -1; shift = 0;
    constant = 0'u64
  ): CrossExpression =
  CrossExpression(
    kind: kind,
    left: left,
    right: right,
    third: third,
    shift: shift,
    constant: constant,
  )

proc find_cross_separators(
    byte_groups: seq[ByteGroup]; bucket_bit_count, submixer_bit_count: int;
    candidates: var seq[SearchCandidate];
    seen: var seq[uint32]; generation: var uint32
  ) =
  let d = byte_groups[0].len

  if candidates.cannot_improve(2.0):
    return

  for i in 0 ..< d:
    for j in i ..< d:
      find_cross_separator(
        byte_groups, make_cross_expression(cross_xor_simple, i, j),
        bucket_bit_count, submixer_bit_count,
        candidates, seen, generation)
      find_cross_separator(
        byte_groups, make_cross_expression(cross_add_simple, i, j),
        bucket_bit_count, submixer_bit_count,
        candidates, seen, generation)
      if candidates.cannot_improve(2.0):
        return

  for i in 0 ..< d:
    for j in 0 ..< d:
      find_cross_separator(
        byte_groups, make_cross_expression(cross_sub_simple, i, j),
        bucket_bit_count, submixer_bit_count,
        candidates, seen, generation)
      if candidates.cannot_improve(2.0):
        return

      for shift in 1 .. 63:
        find_cross_separator(
          byte_groups, make_cross_expression(cross_extr, i, j, shift = shift),
          bucket_bit_count, submixer_bit_count,
          candidates, seen, generation)
        if candidates.cannot_improve(2.0):
          return

      for shift in 1 .. 63:
        find_cross_separator(
          byte_groups,
          make_cross_expression(cross_xor_left_shift, i, j, shift = shift),
          bucket_bit_count, submixer_bit_count,
          candidates, seen, generation)
        find_cross_separator(
          byte_groups,
          make_cross_expression(cross_xor_right_shift, i, j, shift = shift),
          bucket_bit_count, submixer_bit_count,
          candidates, seen, generation)
        find_cross_separator(
          byte_groups,
          make_cross_expression(cross_xor_rotate_right, i, j, shift = shift),
          bucket_bit_count, submixer_bit_count,
          candidates, seen, generation)
        find_cross_separator(
          byte_groups,
          make_cross_expression(cross_add_left_shift, i, j, shift = shift),
          bucket_bit_count, submixer_bit_count,
          candidates, seen, generation)
        find_cross_separator(
          byte_groups,
          make_cross_expression(cross_add_right_shift, i, j, shift = shift),
          bucket_bit_count, submixer_bit_count,
          candidates, seen, generation)
        find_cross_separator(
          byte_groups,
          make_cross_expression(cross_sub_left_shift, i, j, shift = shift),
          bucket_bit_count, submixer_bit_count,
          candidates, seen, generation)
        find_cross_separator(
          byte_groups,
          make_cross_expression(cross_sub_right_shift, i, j, shift = shift),
          bucket_bit_count, submixer_bit_count,
          candidates, seen, generation)
        if candidates.cannot_improve(3.0):
          return

  for i in 0 ..< d:
    for j in i ..< d:
      find_cross_separator(
        byte_groups, make_cross_expression(cross_mul, i, j),
        bucket_bit_count, submixer_bit_count,
        candidates, seen, generation)
      find_cross_separator(
        byte_groups, make_cross_expression(cross_umulh, i, j),
        bucket_bit_count, submixer_bit_count,
        candidates, seen, generation)
      for k in 0 ..< d:
        find_cross_separator(
          byte_groups, make_cross_expression(cross_madd, i, j, third = k),
          bucket_bit_count, submixer_bit_count,
          candidates, seen, generation)
        if candidates.cannot_improve(4.0):
          return
        find_cross_separator(
          byte_groups, make_cross_expression(cross_msub, i, j, third = k),
          bucket_bit_count, submixer_bit_count,
          candidates, seen, generation)
        if candidates.cannot_improve(4.0):
          return

  const multiplication_constant_count = 1024
  for i in 0 ..< d:
    for constant_index in 0 ..< multiplication_constant_count:
      let multiplier = uint64(2 * constant_index + 1)
      find_cross_separator(
        byte_groups,
        make_cross_expression(cross_mul_constant, i, 0, constant = multiplier),
        bucket_bit_count, submixer_bit_count,
        candidates, seen, generation)
      find_cross_separator(
        byte_groups,
        make_cross_expression(cross_umulh_constant, i, 0, constant = multiplier),
        bucket_bit_count, submixer_bit_count,
        candidates, seen, generation)
      for j in 0 ..< d:
        find_cross_separator(
          byte_groups,
          make_cross_expression(
            cross_madd_constant, i, 0, third = j, constant = multiplier),
          bucket_bit_count, submixer_bit_count,
          candidates, seen, generation)
        find_cross_separator(
          byte_groups,
          make_cross_expression(
            cross_msub_constant, i, 0, third = j, constant = multiplier),
          bucket_bit_count, submixer_bit_count,
          candidates, seen, generation)

      if candidates.cannot_improve(4.1):
        return
proc find_ubfx_separator(
    byte_groups: seq[ByteGroup]; input_index: int;
    premix_kind: PremixKind;
    shift, bucket_bit_count, submixer_bit_count: int;
    candidates: var seq[SearchCandidate];
    seen: var seq[uint32]; generation: var uint32
  ) =
  let h1_cost = instruction_cost(premix_kind)
  if candidates.cannot_improve(h1_cost):
    return

  for g in g_candidates(byte_groups[0].len):
    let total_cost = h1_cost + g_cost(g)
    if candidates.cannot_improve(total_cost):
      continue
    for offset in 0 .. 64 - bucket_bit_count:
      next_generation(seen, generation)
      var valid = true
      for group in byte_groups:
        let mixed_value = premix_value(group[input_index], premix_kind, shift)
        let bucket = ubfx_runtime(mixed_value, offset, bucket_bit_count)
        let sub = submixer(evaluate(g, group), submixer_bit_count)
        let index = int((bucket shl submixer_bit_count) or sub)
        if seen[index] == generation:
          valid = false
          break
        seen[index] = generation

      if valid:
        candidates.retain_candidate(SearchCandidate(
          instruction: Instruction(
            kind: in_ubfx,
            input: premix_operand(premix_kind, shift, input_index),
            pos: Operand(kind: op_constant, value: uint64(offset)),
            len: Operand(kind: op_constant, value: uint64(bucket_bit_count)),
          ),
          g: g,
          cost: total_cost,
        ))
        break

proc find_single_word_separators(
    byte_groups: seq[ByteGroup];
    input_index, bucket_bit_count, submixer_bit_count: int;
    candidates: var seq[SearchCandidate];
    seen: var seq[uint32]; generation: var uint32
  ) =
  for shift in 0 .. 63:
    find_ubfx_separator(
      byte_groups, input_index, rotate_right, shift,
      bucket_bit_count, submixer_bit_count,
      candidates, seen, generation)
  if candidates.cannot_improve(2.0):
    return

  const shifted_kinds = [
    xor_left_shift, xor_right_shift, xor_rotate_right,
    add_left_shift, add_right_shift, sub_left_shift, sub_right_shift,
  ]
  for premix_kind in shifted_kinds:
    for shift in 0 .. 63:
      find_ubfx_separator(
        byte_groups, input_index, premix_kind, shift,
        bucket_bit_count, submixer_bit_count,
        candidates, seen, generation)
    if candidates.cannot_improve(3.0):
      return

  const multiply_kinds = [
    multiply_self, multiply_high_self, multiply_add_self, multiply_sub_self,
  ]
  for premix_kind in multiply_kinds:
    find_ubfx_separator(
      byte_groups, input_index, premix_kind, 0,
      bucket_bit_count, submixer_bit_count,
      candidates, seen, generation)
    if candidates.cannot_improve(4.0):
      return

  const multiplication_constant_count = 1024
  for constant_index in 0 ..< multiplication_constant_count:
    let multiplier = 2 * constant_index + 1
    find_ubfx_separator(
      byte_groups, input_index, multiply_constant, multiplier,
      bucket_bit_count, submixer_bit_count,
      candidates, seen, generation)
    if candidates.cannot_improve(4.1):
      return

proc find_h1_g_candidates(
    byte_groups: seq[ByteGroup]; bucket_bit_count, slot_count: int
  ): seq[SearchCandidate] =
  let submixer_bit_count = fastLog2(slot_count)
  let seen_table_size = 1 shl (bucket_bit_count + submixer_bit_count)
  var seen = newSeq[uint32](seen_table_size)
  var generation: uint32

  for input_index in 0 ..< byte_groups[0].len:
    find_ubfx_separator(
      byte_groups, input_index, no_premix, 0,
      bucket_bit_count, submixer_bit_count,
      result, seen, generation)

  for input_index in 0 ..< byte_groups[0].len:
    find_single_word_separators(
      byte_groups, input_index, bucket_bit_count, submixer_bit_count,
      result, seen, generation)

  if byte_groups[0].len > 1:
    find_cross_separators(
      byte_groups, bucket_bit_count, submixer_bit_count,
      result, seen, generation)

proc construct_pilots(
    byte_groups: seq[ByteGroup]; candidate: SearchCandidate;
    bucket_count, slot_count: int; pilots: var seq[uint16]
  ): bool =
  var buckets = newSeq[Bucket](bucket_count)
  for bucket_id in 0 ..< bucket_count:
    buckets[bucket_id].id = bucket_id

  for group in byte_groups:
    let bucket_value = evaluate(candidate.instruction, group)
    if bucket_value >= uint64(bucket_count):
      raise newException(ValueError, "H1 bucket ID is out of range")
    buckets[int(bucket_value)].g_values.add(evaluate(candidate.g, group))

  var non_empty_buckets: seq[Bucket]
  for bucket in buckets:
    if bucket.g_values.len > 0:
      non_empty_buckets.add(bucket)
  non_empty_buckets.sort(proc(left, right: Bucket): int =
    result = cmp(right.g_values.len, left.g_values.len)
    if result == 0:
      result = cmp(left.id, right.id)
  )

  pilots = newSeq[uint16](bucket_count)
  var occupied = newSeq[bool](slot_count)
  var current_slots = newSeq[int](byte_groups.len)
  var slot_seen = newSeq[uint32](slot_count)
  var generation: uint32
  let slot_mask = uint64(slot_count - 1)

  for bucket in non_empty_buckets:
    var found_pilot = false
    for pilot in 0 ..< slot_count:
      next_generation(slot_seen, generation)
      var valid = true
      for item_index, g_value in bucket.g_values:
        let slot = int((g_value + uint64(pilot)) and slot_mask)
        if occupied[slot] or slot_seen[slot] == generation:
          valid = false
          break
        slot_seen[slot] = generation
        current_slots[item_index] = slot

      if valid:
        pilots[bucket.id] = uint16(pilot)
        for item_index in 0 ..< bucket.g_values.len:
          occupied[current_slots[item_index]] = true
        found_pilot = true
        break

    if not found_pilot:
      return false

  true

proc find_mapping*(byte_groups: seq[ByteGroup]): Mapper =
  if byte_groups.len == 0:
    raise newException(ValueError, "Mapping requires at least one key")
  let group_len = byte_groups[0].len
  if group_len == 0:
    raise newException(ValueError, "Mapping requires non-empty byte groups")
  for group in byte_groups:
    if group.len != group_len:
      raise newException(ValueError, "Byte groups must have equal lengths")

  let key_count = byte_groups.len
  if key_count > (int(high(uint16)) + 1) div 2:
    raise newException(ValueError, "Slot count exceeds uint16 pilot range")

  let slot_count = 2 * nextPowerOfTwo(key_count)
  if slot_count > int(high(uint16)) + 1:
    raise newException(ValueError, "Slot count exceeds uint16 pilot range")

  let approximate_bucket_count = max(2, (key_count + 3) div 4)
  let bucket_count = nextPowerOfTwo(approximate_bucket_count)
  let bucket_bit_count = fastLog2(bucket_count)
  let candidates = find_h1_g_candidates(
    byte_groups, bucket_bit_count, slot_count)

  if candidates.len == 0:
    raise newException(ValueError, "No valid H1/G candidate")

  for candidate in candidates:
    var pilots: seq[uint16]
    if construct_pilots(
        byte_groups, candidate, bucket_count, slot_count, pilots):
      return Mapper(
        mixer: candidate.instruction,
        g: candidate.g,
        pilots: pilots,
      )

  raise newException(ValueError, "Pilot construction failed for all candidates")
