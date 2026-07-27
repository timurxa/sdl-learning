const distinguishing_loads_test = true

import ../src/perfect_string_map/mapper_generator

include ../src/perfect_string_map/distinguishing_loads

proc assert_mapping(byte_groups: seq[ByteGroup], mapper: Mapper) =
  let slot_count = 2 * nextPowerOfTwo(byte_groups.len)
  let slot_mask = uint64(slot_count - 1)
  var occupied = newSeq[bool](slot_count)
  for group in byte_groups:
    let bucket_id = int(evaluate(mapper.mixer, group))
    doAssert bucket_id >= 0 and bucket_id < mapper.pilots.len
    let slot = int(
      (evaluate(mapper.g, group) +
       uint64(mapper.pilots[bucket_id])) and slot_mask)
    doAssert not occupied[slot]
    occupied[slot] = true

proc assert_class_bounds(strings: seq[string], expected: seq[(int, int)]) =
  let actual = length_classes(strings, create_length_jump_map(strings))
  doAssert actual.len == expected.len
  for i in 0 ..< expected.len:
    doAssert actual[i].min == expected[i][0]
    doAssert actual[i].max == expected[i][1]

proc assert_load_count(strings: seq[string], expected: int) =
  let actual = minimum_loads(strings).classes
  doAssert actual.len == 1
  doAssert actual[0].loads.len == expected
  for load in actual[0].loads:
    doAssert load.kind == FullLoad

proc test_mapper_generator() =
  let strings = random_strings(4096, 4096)
  let loads = minimum_loads(strings)
  doAssert loads.classes.len == 1
  doAssert loads.classes[0].loads.len == 1
  doAssert loads.classes[0].loads[0].kind == FullLoad

  let load = loads.classes[0].loads[0]
  var byte_groups: seq[ByteGroup]
  for string in strings:
    byte_groups.add(@[loaded_value(string, load.offset)])

  let mapper = find_mapping(byte_groups)
  echo mapper.mixer
  doAssert mapper.mixer != nil
  doAssert mapper.mixer.kind == in_ubfx
  doAssert mapper.g.word_index == 0
  assert_mapping(byte_groups, mapper)

proc test_multi_word_mapper_generator() =
  var strings = @[
    "aaaaaaaa1",
    "aaaaaaaa2",
    "1bbbbbbbb",
    "2bbbbbbbb",
  ]
  strings.sort(load_order)
  let loads = minimum_loads(strings)
  doAssert loads.classes.len == 1
  doAssert loads.classes[0].loads.len == 2
  for load in loads.classes[0].loads:
    doAssert load.kind == FullLoad

  var byte_groups: seq[ByteGroup]
  for string in strings:
    var byte_group: ByteGroup
    for load in loads.classes[0].loads:
      byte_group.add(loaded_value(string, load.offset))
    byte_groups.add(byte_group)

  let mapper = find_mapping(byte_groups)
  let repeated_mapper = find_mapping(byte_groups)
  let instruction_text = $mapper.mixer
  doAssert mapper.g.word_index >= 0 and
    mapper.g.word_index < byte_groups[0].len
  doAssert repeated_mapper.g.kind == mapper.g.kind
  doAssert repeated_mapper.g.word_index == mapper.g.word_index
  if mapper.g.kind == g_xor_right_shift:
    doAssert repeated_mapper.g.shift == mapper.g.shift
  doAssert $repeated_mapper.mixer == instruction_text
  doAssert repeated_mapper.pilots == mapper.pilots
  assert_mapping(byte_groups, mapper)

proc assert_partial_width(strings: seq[string], expected: int) =
  let actual = minimum_loads(strings).classes
  doAssert actual.len == 1
  doAssert actual[0].loads.len == 1
  doAssert actual[0].loads[0].kind == PartialLoad
  doAssert actual[0].loads[0].offset == 0
  doAssert actual[0].loads[0].width == expected

proc assert_result_class_bounds(strings: seq[string], expected: seq[(int, int)]) =
  let actual = minimum_loads(strings).classes
  doAssert actual.len == expected.len
  for i in 0 ..< expected.len:
    doAssert actual[i].min == expected[i][0]
    doAssert actual[i].max == expected[i][1]

proc reference_prefix_length(strings: openArray[string]): int =
  if strings.len <= 1:
    return 1

  for first in 0 ..< strings.len:
    for second in first + 1 ..< strings.len:
      var common = 0
      let limit = min(strings[first].len, strings[second].len)
      while common < limit and strings[first][common] == strings[second][common]:
        inc common
      result = max(result, common + 1)

proc load_value_for_test(string: string, load: Load): uint64 =
  let width = if load.kind == FullLoad: 8 else: load.width
  for index in 0 ..< width:
    result = (result shl 8) or uint64(ord(string[load.offset + index]))

proc assert_loads_valid(strings: seq[string], loads: MinimumLoadsResult) =
  let jump_map = create_length_jump_map(strings)
  for length_class in loads.classes:
    let start = jump_map.map[length_class.min]
    let length_group = jump_map.lengths.find(length_class.max)
    let finish = if length_group + 1 < jump_map.lengths.len:
      jump_map.map[jump_map.lengths[length_group + 1]] - 1
    else:
      strings.high
    for load in length_class.loads:
      doAssert load.offset >= 0
      if load.kind == FullLoad:
        doAssert load.offset + 8 <= length_class.min
      else:
        doAssert load.width > 0 and load.width <= 8
        doAssert load.offset + load.width <= length_class.min
    for first in start ..< finish:
      for second in first + 1 .. finish:
        var first_values: seq[uint64]
        var second_values: seq[uint64]
        for load in length_class.loads:
          first_values.add(load_value_for_test(strings[first], load))
          second_values.add(load_value_for_test(strings[second], load))
        doAssert first_values != second_values

proc reference_partition_count(strings: seq[string]): int =
  let jump_map = create_length_jump_map(strings)
  var best = newSeqWith(jump_map.lengths.len + 1, high(int))
  best[0] = 0
  for first_group in 0 ..< jump_map.lengths.len:
    let start = jump_map.map[jump_map.lengths[first_group]]
    for last_group in first_group ..< jump_map.lengths.len:
      let finish = if last_group + 1 < jump_map.lengths.len:
        jump_map.map[jump_map.lengths[last_group + 1]] - 1
      else:
        strings.high
      let prefix_length = reference_prefix_length(
        strings.toOpenArray(start, finish)
      )
      if prefix_length <= jump_map.lengths[first_group]:
        best[last_group + 1] = min(best[last_group + 1], best[first_group] + 1)
  best[^1]

proc test_random_small_cases() =
  randomize(99173)
  for trial in 0 ..< 300:
    var strings: seq[string]
    var seen = initHashSet[string]()
    let count = 1 + rand(11)
    while strings.len < count:
      let candidate = random_alphanumeric(1 + rand(11))
      if candidate notin seen:
        seen.incl(candidate)
        strings.add(candidate)
    strings.sort(load_order)
    let actual = minimum_loads(strings)
    doAssert actual.classes.len == reference_partition_count(strings)
    assert_loads_valid(strings, actual)

proc test_length_classes() =
  assert_class_bounds(
    @[
      "a",
      "b",
      "c1",
      "ab1",
      "ab2",
    ], @[(1, 2), (3, 3)])
  assert_class_bounds(
    @[
      "a",
      "b",
      "c1",
      "c2",
      "ab1",
      "ab2",
    ], @[(1, 1), (2, 2), (3, 3)])
  assert_class_bounds(@["a", "b", "aa", "ab"], @[(1, 1), (2, 2)])
  assert_class_bounds(@["abc", "abdX", "abcdef"], @[(3, 4), (6, 6)])
  assert_result_class_bounds(@["a", "abc"], @[(1, 2), (3, 3)])
  assert_class_bounds(@["a", "b", "c"], @[(1, 1)])
  assert_class_bounds(@["x"], @[(1, 1)])
  assert_class_bounds(@[], @[])
  assert_load_count(@["aaaaaaaa", "aaaaaaab", "aaaaaaac"], 1)
  assert_load_count(
    @[
      "0000aaaaaaaa0000",
      "0000aaaaaaaa1111",
      "1111aaaaaaaa0000",
      "1111aaaaaaaa1111",
    ], 2)
  assert_partial_width(@["a", "b"], 1)
  assert_partial_width(@["aa", "ab"], 2)
  assert_partial_width(@["aaa", "aab"], 3)
  assert_partial_width(@["aaaa", "aaab"], 4)
  assert_partial_width(@["aaaaa", "aaaab"], 5)
  assert_partial_width(@["aaaaaa", "aaaaab"], 6)
  assert_partial_width(@["aaaaaaa", "aaaaaab"], 7)
  echo "length class tests passed"

test_length_classes()
test_multi_word_mapper_generator()
test_mapper_generator()
test_random_small_cases()
