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
      (evaluate(candidate.g, group) + uint64(pilots[bucket_id])) and slot_mask)
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
      (evaluate(mapper.g, first) +
       uint64(mapper.pilots[int(first_bucket)])) and slot_mask)
    doAssert not occupied[slot]
    occupied[slot] = true
    for second_index in first_index + 1 ..< groups.len:
      let second = groups[second_index]
      if evaluate(mapper.mixer, second) == first_bucket:
        doAssert (evaluate(mapper.g, first) and slot_mask) !=
          (evaluate(mapper.g, second) and slot_mask)

proc test_g_evaluation() =
  let word = 0xFEDC_BA98_7654_3210'u64
  let group: ByteGroup = @[word]
  const compile_time_shifted = evaluate(
    G(kind: g_xor_right_shift, word_index: 0, shift: 63),
    @[0xFEDC_BA98_7654_3210'u64])
  doAssert evaluate(
    G(kind: g_raw_word, word_index: 0), group) == word
  doAssert evaluate(
    G(kind: g_xor_right_shift, word_index: 0, shift: 1), group) ==
      (word xor (word shr 1))
  doAssert evaluate(
    G(kind: g_xor_right_shift, word_index: 0, shift: 63), group) ==
      (word xor (word shr 63))
  doAssert compile_time_shifted == (word xor (word shr 63))

proc test_g_candidate_enumeration() =
  var empty_count = 0
  for _ in g_candidates(0):
    inc empty_count
  doAssert empty_count == 0

  var candidates: seq[G]
  for g in g_candidates(2):
    candidates.add(g)
  doAssert candidates.len == 128
  doAssert candidates[0].kind == g_raw_word
  doAssert candidates[0].word_index == 0
  doAssert candidates[1].kind == g_raw_word
  doAssert candidates[1].word_index == 1
  var seen = newSeq[bool](2 * 64)
  for g in candidates:
    let shift = if g.kind == g_raw_word: 0 else: int(g.shift)
    doAssert shift >= 0 and shift <= 63
    let index = g.word_index * 64 + shift
    doAssert not seen[index]
    seen[index] = true
  for present in seen:
    doAssert present

proc test_g_cost_ranking() =
  let raw_g = G(kind: g_raw_word, word_index: 0)
  let shifted_g = G(
    kind: g_xor_right_shift,
    word_index: 0,
    shift: 1,
  )
  doAssert g_cost(raw_g) == 0.0
  doAssert g_cost(shifted_g) == 2.0

  var candidates: seq[SearchCandidate]
  var seen = newSeq[uint32](4)
  var generation: uint32
  find_ubfx_separator(
    @[@[0xFEDC_BA98_7654_3210'u64]],
    0, no_premix, 0, 1, 1,
    candidates, seen, generation)
  doAssert candidates[0].g.kind == g_raw_word
  doAssert candidates[0].cost == 1.0
  var shifted_cost = -1.0
  for candidate in candidates:
    if candidate.g.kind == g_xor_right_shift:
      shifted_cost = candidate.cost
      break
  doAssert shifted_cost == 3.0
  doAssert shifted_cost - candidates[0].cost == 2.0

  candidates.setLen(0)
  candidates.retain_candidate(SearchCandidate(
    g: raw_g,
    cost: 4.0 + g_cost(raw_g),
  ))
  candidates.retain_candidate(SearchCandidate(
    g: shifted_g,
    cost: 1.0 + g_cost(shifted_g),
  ))
  doAssert candidates[0].g.kind == g_xor_right_shift
  doAssert candidates[0].cost == 3.0
  doAssert candidates[1].cost == 4.0

  candidates.setLen(0)
  for _ in 0 ..< retained_candidate_count:
    candidates.add(SearchCandidate(cost: 3.0))
  doAssert not candidates.cannot_improve(1.0)
  doAssert candidates.cannot_improve(3.0)

proc some_raw_g_bucket_partition_avoids_collisions(
    groups: seq[ByteGroup]; bucket_count, slot_count: int
  ): bool =
  doAssert bucket_count == 2
  let raw_g = G(kind: g_raw_word, word_index: 0)
  let slot_mask = uint64(slot_count - 1)
  for bucket_assignment in 0 ..< (1 shl groups.len):
    var seen = newSeq[bool](bucket_count * slot_count)
    var valid = true
    for group_index, group in groups:
      let bucket = (bucket_assignment shr group_index) and 1
      let slot = int(evaluate(raw_g, group) and slot_mask)
      let index = bucket * slot_count + slot
      if seen[index]:
        valid = false
        break
      seen[index] = true
    if valid:
      return true

proc test_shifted_g_succeeds_when_raw_g_fails() =
  let groups: seq[ByteGroup] = @[
    @[0x1_0000'u64],
    @[0x2_0000'u64],
    @[0x3_0000'u64],
    @[0x4_0000'u64],
  ]
  const bucket_count = 2
  const slot_count = 8
  doAssert not some_raw_g_bucket_partition_avoids_collisions(
    groups, bucket_count, slot_count)
  let candidates = find_h1_g_candidates(
    groups, fastLog2(bucket_count), slot_count)
  doAssert candidates.len <= retained_candidate_count

  let mapper = find_mapping(groups)
  doAssert mapper.g.kind == g_xor_right_shift
  doAssert mapper.g.word_index == 0
  doAssert mapper.g.shift >= 1 and mapper.g.shift <= 63
  assert_public_mapping(groups, mapper)

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
    g: G(kind: g_raw_word, word_index: 1),
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
    g: G(kind: g_raw_word, word_index: 1),
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
    g: G(kind: g_raw_word, word_index: 1),
  )
  let groups: seq[ByteGroup] = @[
    @[0'u64, 3'u64],
    @[0'u64, 11'u64],
  ]
  var pilots: seq[uint16]
  doAssert not construct_pilots(groups, candidate, 2, 8, pilots)

proc test_empty_and_singleton_buckets() =
  let mapper = find_mapping(@[@[high(uint64)]])
  doAssert mapper.g.kind == g_raw_word
  doAssert mapper.g.word_index == 0
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
    g: G(kind: g_raw_word, word_index: 1),
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

test_g_evaluation()
test_g_candidate_enumeration()
test_g_cost_ranking()
test_shifted_g_succeeds_when_raw_g_fails()
test_evaluator_matches_search_semantics()
test_bucket_order_and_pilot_indexing()
test_addition_wrap_without_pre_mask()
test_rejects_duplicate_slots_within_bucket()
test_empty_and_singleton_buckets()
test_failure_paths()
test_generated_mapper_invariants()
test_highest_uint16_pilot()

echo "mapper generator adversarial tests passed"
