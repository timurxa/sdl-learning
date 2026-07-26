import std/algorithm
import std/math
import std/monotimes
import std/random
import std/sequtils
import std/sets
import std/strutils
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
  CollisionClass = object
    start: int
    len: int
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
      let min_distinguishing = min_distinguishable_prefix_bytes(
        strings.toOpenArray(start, end_index)
      )
      if min_distinguishing <= min_length:
        low = middle
      else:
        high = middle

    result.add(LengthClass(
      min: min_length,
      max: length_jump_map.lengths[low],
    ))
    first_group = low + 1

const no_collision_class = -1

proc loaded_value(string: string, offset: int): uint64 =
  for i in 0 ..< 8:
    result = (result shl 8) or uint64(ord(string[offset + i]))

proc collision_score(
    strings: seq[string],
    start, finish: int,
    collision_classes: seq[CollisionClass],
    class_of: seq[int],
    log_fact: seq[float],
    group_sizes: var Table[uint64, int],
    offset: int,
  ): float =
  for class_index, collision_class in pairs(collision_classes):
    group_sizes.clear()
    for string_index in start .. finish:
      if class_of[string_index] == class_index:
        let value = loaded_value(strings[string_index], offset)
        group_sizes.mgetOrPut(value).inc

    result += log_fact[collision_class.len]
    for group_size in group_sizes.values:
      result -= log_fact[group_size]

proc apply_load(
    strings: seq[string],
    start, finish: int,
    collision_classes: var seq[CollisionClass],
    class_of: var seq[int],
    offset: int,
  ) =
  var next_classes: seq[CollisionClass]
  var next_groups: seq[seq[int]]

  for class_index in 0 ..< collision_classes.len:
    var groups: seq[seq[int]]
    var group_of = initTable[uint64, int]()

    for string_index in start .. finish:
      if class_of[string_index] != class_index:
        continue

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
      next_groups.add(group)

  for group in next_groups:
    if group.len > 1:
      let new_class_index = next_classes.len
      next_classes.add(CollisionClass(start: group[0], len: group.len))
      for string_index in group:
        class_of[string_index] = new_class_index
    else:
      class_of[group[0]] = no_collision_class

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
    var class_of = newSeqWith(strings.len, no_collision_class)
    if class_finish > class_start:
      collision_classes.add(CollisionClass(
        start: class_start,
        len: class_finish - class_start + 1,
      ))
      for string_index in class_start .. class_finish:
        class_of[string_index] = 0

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
        var group_sizes = initTable[uint64, int](class_finish - class_start + 1)
        while collision_classes.len > 0:
          var best_offset = -1
          var best_score = -1.0
          for offset in 0 .. min_length - 8:
            let score = collision_score(
              strings,
              class_start,
              class_finish,
              collision_classes,
              class_of,
              log_fact,
              group_sizes,
              offset,
            )
            if score > best_score:
              best_score = score
              best_offset = offset

          doAssert best_offset >= 0
          apply_load(
            strings,
            class_start,
            class_finish,
            collision_classes,
            class_of,
            best_offset,
          )
          loads.add(Load(kind: FullLoad, offset: best_offset))

    result.classes[i] = LengthClassResult(
      min: length_class.min,
      max: length_class.max,
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

proc benchmark_minimum_loads(name: string, strings: seq[string]) =
  let started = get_mono_time()
  let loads = minimum_loads(strings)
  let elapsed = get_mono_time() - started
  echo name, " result: ", loads
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
  let instruction_text = $bucketter.mixer
  doAssert instruction_text.contains("index: 1")

proc assert_partial_width(strings: seq[string], expected: int) =
  let actual = minimum_loads(strings).classes
  doAssert actual.len == 1
  doAssert actual[0].loads.len == 1
  doAssert actual[0].loads[0].kind == PartialLoad
  doAssert actual[0].loads[0].offset == 0
  doAssert actual[0].loads[0].width == expected

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
  randomize()
  benchmark_minimum_loads("64 words", random_words(64))
  benchmark_minimum_loads("256 x 256", random_strings(256, 256))
  benchmark_minimum_loads("4096 x 4096", random_strings(4096, 4096))

main()
