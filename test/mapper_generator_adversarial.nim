include ../src/perfect_string_map/mapper_generator

proc assert_raises_value_error(body: proc()) =
  var raised = false
  try:
    body()
  except ValueError:
    raised = true
  doAssert raised

proc ubfx_instruction(input_index, offset, width: int): Instruction =
  Instruction(
    kind: in_ubfx,
    input: input_operand(input_index),
    pos: constant_operand(uint64(offset)),
    len: constant_operand(uint64(width)),
  )

proc assert_constructed_mapping(
    groups: seq[ByteGroup]; candidate: SearchCandidate;
    bucket_count, slot_count: int; pilots: seq[uint16]
  ) =
  let slot_mask = uint64(slot_count - 1)
  var occupied = newSeq[bool](slot_count)
  for group in groups:
    let bucket_id = int(evaluate(candidate.instruction, group))
    let slot = int(
      (group[candidate.g_index] + uint64(pilots[bucket_id])) and slot_mask)
    doAssert not occupied[slot]
    occupied[slot] = true

proc assert_public_mapping(groups: seq[ByteGroup]; mapper: Mapper) =
  let slot_count = 2 * nextPowerOfTwo(groups.len)
  let slot_mask = uint64(slot_count - 1)
  var occupied = newSeq[bool](slot_count)
  for first_index, first in groups:
    let first_bucket = evaluate(mapper.mixer, first)
    doAssert first_bucket < uint64(mapper.pilots.len)
    let slot = int(
      (first[mapper.g_index] +
       uint64(mapper.pilots[int(first_bucket)])) and slot_mask)
    doAssert not occupied[slot]
    occupied[slot] = true
    for second_index in first_index + 1 ..< groups.len:
      let second = groups[second_index]
      if evaluate(mapper.mixer, second) == first_bucket:
        doAssert (first[mapper.g_index] and slot_mask) !=
          (second[mapper.g_index] and slot_mask)

proc test_evaluator_matches_search_semantics() =
  let group: ByteGroup = @[
    0xFEDC_BA98_7654_3210'u64,
    0x0123_4567_89AB_CDEF'u64,
    0xA5A5_5A5A_F0F0_0F0F'u64,
  ]
  let premix_kinds = [
    no_premix,
    rotate_right,
    xor_right_shift,
    xor_left_shift,
    xor_rotate_right,
    add_left_shift,
    add_right_shift,
    sub_left_shift,
    sub_right_shift,
    multiply_self,
    multiply_high_self,
    multiply_add_self,
    multiply_sub_self,
    multiply_constant,
  ]
  for kind in premix_kinds:
    let shift = if kind == multiply_constant: 2051 else: 17
    let operand = premix_operand(kind, shift, 0)
    doAssert evaluate(operand, group) == premix_value(group[0], kind, shift)

  let cross_kinds = [
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
  ]
  for kind in cross_kinds:
    let expression = make_cross_expression(
      kind, 0, 1, third = 2, shift = 17,
      constant = 0xFFFF_FFFF_FFFF_FFC5'u64)
    doAssert evaluate(cross_instruction(expression), group) ==
      cross_value(group, expression)

proc test_bucket_order_and_pilot_indexing() =
  let candidate = SearchCandidate(
    instruction: ubfx_instruction(0, 0, 1),
    g_index: 1,
  )
  let groups: seq[ByteGroup] = @[
    @[1'u64, 0'u64],
    @[1'u64, 1'u64],
    @[1'u64, 2'u64],
    @[0'u64, 0'u64],
  ]
  var pilots: seq[uint16]
  doAssert construct_pilots(groups, candidate, 2, 8, pilots)
  doAssert pilots == @[3'u16, 0'u16]
  assert_constructed_mapping(groups, candidate, 2, 8, pilots)

proc test_addition_wrap_without_pre_mask() =
  let candidate = SearchCandidate(
    instruction: ubfx_instruction(0, 0, 1),
    g_index: 1,
  )
  let groups: seq[ByteGroup] = @[
    @[0'u64, high(uint64)],
    @[0'u64, 0'u64],
    @[1'u64, high(uint64)],
    @[1'u64, 0'u64],
  ]
  var pilots: seq[uint16]
  doAssert construct_pilots(groups, candidate, 2, 8, pilots)
  doAssert pilots[0] == 0
  doAssert pilots[1] == 2
  assert_constructed_mapping(groups, candidate, 2, 8, pilots)

proc test_rejects_duplicate_slots_within_bucket() =
  let candidate = SearchCandidate(
    instruction: ubfx_instruction(0, 0, 1),
    g_index: 1,
  )
  let groups: seq[ByteGroup] = @[
    @[0'u64, 3'u64],
    @[0'u64, 11'u64],
  ]
  var pilots: seq[uint16]
  doAssert not construct_pilots(groups, candidate, 2, 8, pilots)

proc test_empty_and_singleton_buckets() =
  let mapper = find_mapping(@[@[high(uint64)]])
  doAssert mapper.pilots.len == 2
  doAssert mapper.pilots[0] == 0 or mapper.pilots[1] == 0
  let slot = (high(uint64) + uint64(
    mapper.pilots[int(evaluate(mapper.mixer, @[high(uint64)]))])) and 1'u64
  doAssert slot <= 1

proc test_failure_paths() =
  assert_raises_value_error(proc() = discard find_mapping(@[]))
  assert_raises_value_error(
    proc() = discard find_mapping(@[ByteGroup(@[])]))
  assert_raises_value_error(
    proc() = discard find_mapping(@[@[0'u64], @[0'u64, 1'u64]]))
  assert_raises_value_error(
    proc() = discard find_mapping(@[@[7'u64], @[7'u64]]))

  var too_many = newSeq[ByteGroup](32769)
  for index in 0 ..< too_many.len:
    too_many[index] = @[uint64(index)]
  assert_raises_value_error(proc() = discard find_mapping(too_many))

proc test_generated_mapper_invariants() =
  var state = 0xD1B5_4A32_D192_ED03'u64
  for trial in 0 ..< 32:
    let key_count = 2 + trial mod 23
    let group_len = 1 + trial mod 3
    var groups: seq[ByteGroup]
    for key_index in 0 ..< key_count:
      var group: ByteGroup
      for word_index in 0 ..< group_len:
        state = state * 6364136223846793005'u64 + 1442695040888963407'u64
        group.add(
          (state and not 0x1_FFFF'u64) or
          uint64(key_index div 2) or
          (uint64(key_index mod 2) shl 16))
      groups.add(group)
    assert_public_mapping(groups, find_mapping(groups))

proc test_highest_uint16_pilot() =
  let slot_count = int(high(uint16)) + 1
  let candidate = SearchCandidate(
    instruction: ubfx_instruction(0, 0, 1),
    g_index: 1,
  )
  var groups = newSeqOfCap[ByteGroup](slot_count)
  for g_value in 0 ..< high(uint16).int:
    groups.add(@[0'u64, uint64(g_value)])
  groups.add(@[1'u64, 0'u64])

  var pilots: seq[uint16]
  doAssert construct_pilots(groups, candidate, 2, slot_count, pilots)
  doAssert pilots[0] == 0
  doAssert pilots[1] == high(uint16)
  assert_constructed_mapping(groups, candidate, 2, slot_count, pilots)

test_evaluator_matches_search_semantics()
test_bucket_order_and_pilot_indexing()
test_addition_wrap_without_pre_mask()
test_rejects_duplicate_slots_within_bucket()
test_empty_and_singleton_buckets()
test_failure_paths()
test_generated_mapper_invariants()
test_highest_uint16_pilot()

echo "mapper generator adversarial tests passed"
