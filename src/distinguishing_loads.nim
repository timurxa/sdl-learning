import std/algorithm
import std/math
import std/monotimes
import std/random
import std/sequtils
import std/sets
import std/tables
import std/times
import mapper_generator

type
  LoadKind = enum
    FullLoad
    PartialLoad
  Load = object
    offset: int
    case kind: LoadKind
    of FullLoad:
      discard
    of PartialLoad:
      width: int
  LengthClass = object
    min, max: int
  CollisionKey = tuple[class_index: int, value: uint64]
  CollisionClass = object
    len: int
    members: seq[int]
  LengthClassResult = object
    min, max: int
    loads: seq[Load]
  LengthJumpMap = object
    lengths: seq[int]
    map: seq[int]
  MinimumLoadsResult = object
    classes: seq[LengthClassResult]

proc create_length_jump_map(strings: openArray[string]): LengthJumpMap =
  if strings.len == 0:
    return

  result.map = newSeqWith(strings[^1].len + 1, -1)

  var last_length = -1
  for (i, string) in pairs(strings):
    if string.len != last_length:
      last_length = string.len
      result.lengths.add(last_length)
      result.map[last_length] = i

proc min_distinguishable_prefix_bytes(strings: openArray[string]): int =
  if strings.len <= 1:
    return 1

  var sorted_strings = newSeqOfCap[string](strings.len)
  for string in strings:
    sorted_strings.add(string)
  sorted_strings.sort()

  var max_lcp = 0
  for i in 0 ..< sorted_strings.len - 1:
    let a = sorted_strings[i]
    let b = sorted_strings[i + 1]

    var j = 0
    let n = min(a.len, b.len)

    while j < n and a[j] == b[j]: inc j

    max_lcp = max(max_lcp, j)
  result = max_lcp + 1

proc loaded_prefix_value(string: string, width: int): uint64 =
  for i in 0 ..< width:
    result = (result shl 8) or uint64(ord(string[i]))

proc prefixes_are_distinct(
    strings: openArray[string], prefix_length: int
  ): bool =
  if prefix_length <= 8:
    var prefixes = initHashSet[uint64]()
    for string in strings:
      let prefix = loaded_prefix_value(string, prefix_length)
      if prefix in prefixes:
        return false
      prefixes.incl(prefix)
    return true

  var prefixes = initHashSet[string]()
  for string in strings:
    let prefix = string[0 ..< prefix_length]
    if prefix in prefixes:
      return false
    prefixes.incl(prefix)
  true

proc load_order(a, b: string): int =
  if a.len == b.len:
    return cmp(a, b)
  cmp(a.len, b.len)

proc length_classes(strings: seq[string]; length_jump_map: LengthJumpMap): seq[LengthClass] =
  if strings.len == 0:
    return

  var first_group = 0
  while first_group < length_jump_map.lengths.len:
    let min_length = length_jump_map.lengths[first_group]
    let start = length_jump_map.map[min_length]

    var low = first_group
    var high = length_jump_map.lengths.len
    while low + 1 < high:
      let middle = (low + high) div 2
      let end_index = if middle + 1 < length_jump_map.lengths.len:
        length_jump_map.map[length_jump_map.lengths[middle + 1]] - 1
      else:
        strings.high
      if prefixes_are_distinct(
          strings.toOpenArray(start, end_index), min_length
        ):
        low = middle
      else:
        high = middle

    result.add(LengthClass(
      min: min_length,
      max: length_jump_map.lengths[low],
    ))
    first_group = low + 1

proc loaded_value(string: string, offset: int): uint64 =
  for i in 0 ..< 8:
    result = (result shl 8) or uint64(ord(string[offset + i]))

proc collision_score(
    strings: seq[string],
    collision_classes: seq[CollisionClass],
    log_fact: seq[float],
    group_sizes: var Table[CollisionKey, int],
    loaded_values: seq[uint64],
  ): float =
  group_sizes.clear()
  for class_index, collision_class in pairs(collision_classes):
    result += log_fact[collision_class.len]
    for string_index in collision_class.members:
      let key = (class_index, loaded_values[string_index])
      group_sizes.mgetOrPut(key).inc
  for group_size in group_sizes.values:
    result -= log_fact[group_size]

proc advance_loaded_values(
    strings: seq[string], collision_classes: seq[CollisionClass], offset: int,
    loaded_values: var seq[uint64],
  ) =
  for collision_class in collision_classes:
    for string_index in collision_class.members:
      loaded_values[string_index] =
        (loaded_values[string_index] shl 8) or
        uint64(ord(strings[string_index][offset + 7]))

proc apply_load(
    strings: seq[string],
    collision_classes: var seq[CollisionClass],
    offset: int,
  ) =
  var next_classes: seq[CollisionClass]

  for collision_class in collision_classes:
    var groups: seq[seq[int]]
    var group_of = initTable[uint64, int]()

    for string_index in collision_class.members:
      let value = loaded_value(strings[string_index], offset)
      let group_index = if group_of.hasKey(value):
        group_of[value]
      else:
        let new_group_index = groups.len
        group_of[value] = new_group_index
        groups.add(@[])
        new_group_index
      groups[group_index].add(string_index)

    for group in groups:
      if group.len > 1:
        next_classes.add(CollisionClass(len: group.len, members: group))

  collision_classes = next_classes

## `strings` must be sorted and deduplicated
proc minimum_loads(strings: seq[string]): MinimumLoadsResult =
  if strings.len == 0:
    return

  assert isSorted(strings, load_order)
  assert strings == deduplicate(strings, true)

  let length_jump_map = create_length_jump_map(strings)
  let classes = length_classes(strings, length_jump_map)
  var log_fact = newSeq[float](strings.len + 1)
  for i in 1 .. strings.len:
    log_fact[i] = log_fact[i - 1] + ln(float(i))

  result = MinimumLoadsResult(classes: newSeq[LengthClassResult](classes.len))

  for i, length_class in classes:
    let class_start = length_jump_map.map[length_class.min]
    let max_length_group = length_jump_map.lengths.find(length_class.max)
    let class_finish = if max_length_group + 1 < length_jump_map.lengths.len:
      length_jump_map.map[length_jump_map.lengths[max_length_group + 1]] - 1
    else:
      strings.high

    var collision_classes: seq[CollisionClass]
    if class_finish > class_start:
      var members = newSeqOfCap[int](class_finish - class_start + 1)
      for string_index in class_start .. class_finish:
        members.add(string_index)
      collision_classes.add(CollisionClass(len: members.len, members: members))

    var loads: seq[Load]
    let min_length = length_class.min
    if collision_classes.len > 0:
      if min_length < 8:
        let required_bytes = min_distinguishable_prefix_bytes(
          strings.toOpenArray(class_start, class_finish)
        )
        let width = min(nextPowerOfTwo(required_bytes), min(min_length, 8))
        loads.add(Load(kind: PartialLoad, offset: 0, width: width))
      else:
        var group_sizes = initTable[CollisionKey, int](class_finish - class_start + 1)
        var loaded_values = newSeq[uint64](strings.len)
        while collision_classes.len > 0:
          for collision_class in collision_classes:
            for string_index in collision_class.members:
              loaded_values[string_index] = loaded_value(strings[string_index], 0)
          var best_offset = -1
          var best_score = -1.0
          var perfect_score = 0.0
          for collision_class in collision_classes:
            perfect_score += log_fact[collision_class.len]
          for offset in 0 .. min_length - 8:
            if offset > 0:
              advance_loaded_values(strings, collision_classes, offset, loaded_values)
            let score = collision_score(
              strings,
              collision_classes,
              log_fact,
              group_sizes,
              loaded_values,
            )
            if score > best_score:
              best_score = score
              best_offset = offset
            if best_score == perfect_score:
              break

          doAssert best_offset >= 0
          apply_load(
            strings,
            collision_classes,
            best_offset,
          )
          loads.add(Load(kind: FullLoad, offset: best_offset))

    result.classes[i] = LengthClassResult(
      min: length_class.min,
      max: if i + 1 < classes.len: classes[i + 1].min - 1 else: length_class.max,
      loads: loads,
    )

const alphanumeric = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

proc random_alphanumeric(length: int): string =
  result = newString(length)
  for i in 0 ..< length:
    result[i] = alphanumeric[rand(alphanumeric.high)]

proc random_strings(count, length: int): seq[string] =
  var seen = initHashSet[string]()
  while result.len < count:
    let candidate = random_alphanumeric(length)
    if candidate notin seen:
      seen.incl(candidate)
      result.add(candidate)
  result.sort(load_order)

proc random_words(count: int): seq[string] =
  var seen = initHashSet[string]()
  while result.len < count:
    let candidate = random_alphanumeric(5 + rand(2))
    if candidate notin seen:
      seen.incl(candidate)
      result.add(candidate)
  result.sort(load_order)

proc repeated_a_strings(count: int): seq[string] =
  for length in 1 .. count:
    var value = newString(length)
    for index in 0 ..< length:
      value[index] = 'a'
    result.add(value)

proc two_component_strings(count, length, component_size: int): seq[string] =
  for index in 0 ..< count:
    var value = newString(length)
    for byte_index in 0 ..< length:
      value[byte_index] = 'a'
    value[0] = char(1 + index div component_size)
    value[component_size div 8] = char(1 + index mod component_size)
    result.add(value)
  result.sort(load_order)

proc four_component_strings(count, length, component_size: int): seq[string] =
  for index in 0 ..< count:
    var value = newString(length)
    for byte_index in 0 ..< length:
      value[byte_index] = 'a'
    for component in 0 ..< 4:
      let place = case component
      of 0: component_size * component_size * component_size
      of 1: component_size * component_size
      of 2: component_size
      else: 1
      let component_index = index div place mod component_size
      value[component * 8] = char(1 + component_index)
    result.add(value)
  result.sort(load_order)

proc benchmark_minimum_loads(name: string, strings: seq[string]) =
  let started = get_mono_time()
  let loads = minimum_loads(strings)
  let elapsed = get_mono_time() - started
  var counts: seq[int]
  var total = 0
  for length_class in loads.classes:
    counts.add(length_class.loads.len)
    total += length_class.loads.len
  if counts.len <= 32:
    echo name, " partitions: ", counts.len, " loads: ", counts
  else:
    echo name, " partitions: ", counts.len, " loads: first=", counts[0],
      " last=", counts[^1], " total=", total
  echo name, " time: ", inNanoseconds(elapsed), " ns"

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

  let bucketter = find_bucket_separator(byte_groups)
  echo bucketter.mixer
  doAssert bucketter.mixer != nil
  doAssert bucketter.mixer.kind == in_ubfx
  doAssert bucketter.g_index == 0

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

  let bucketter = find_bucket_separator(byte_groups)
  let repeated_bucketter = find_bucket_separator(byte_groups)
  let instruction_text = $bucketter.mixer
  doAssert bucketter.g_index == 1
  doAssert repeated_bucketter.g_index == bucketter.g_index
  doAssert $repeated_bucketter.mixer == instruction_text

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

proc main() =
  test_length_classes()
  test_multi_word_mapper_generator()
  test_mapper_generator()
  test_random_small_cases()
  randomize(12345)
  benchmark_minimum_loads("1 x 1", random_strings(1, 1))
  benchmark_minimum_loads("16 x 8", random_strings(16, 8))
  benchmark_minimum_loads("64 words", random_words(64))
  benchmark_minimum_loads("64 x 64", random_strings(64, 64))
  benchmark_minimum_loads("256 x 256", random_strings(256, 256))
  benchmark_minimum_loads("1024 x 1024", random_strings(1024, 1024))
  benchmark_minimum_loads("4096 x 4096", random_strings(4096, 4096))
  benchmark_minimum_loads(
    "4096 x 4096 two component",
    two_component_strings(4096, 4096, 64),
  )
  benchmark_minimum_loads(
    "4096 x 4096 four component",
    four_component_strings(4096, 4096, 8),
  )
  benchmark_minimum_loads("repeated a 4096", repeated_a_strings(4096))

main()
