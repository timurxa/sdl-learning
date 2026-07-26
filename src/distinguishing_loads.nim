import std/algorithm
import std/math
import std/monotimes
import std/random
import std/sequtils
import std/sets
import std/tables
import std/times

when not declared(distinguishing_loads_test):
  const distinguishing_loads_test = false

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

proc main() =
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

when isMainModule and not distinguishing_loads_test:
  main()
