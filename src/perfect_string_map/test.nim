import std/sequtils

const distinguishing_loads_test = true

import mapper_generator

include distinguishing_loads

var strings = deduplicate(@[
  "act", "add", "age", "ago", "air", "all", "and", "any", "are", "arm", "art", "ask", "bad", "bar", "bat", "bed", "big", "bit", "box", "boy", "but", "buy", "can", "car", "cat", "cow", "cry", "cut", "dad", "day", "did", "die", "dog", "dry", "ear", "eat", "egg", "end", "eye", "far", "fat", "few", "fig", "fit", "fly", "for", "fun", "gas", "get", "got", "gun", "had", "has", "hat", "her", "him", "his", "hit", "hot", "how", "ice", "job", "joy", "key", "law", "lay", "led", "leg", "let", "lie", "log", "lot", "low", "man", "map", "may",
])
echo "input_strings: ", strings

strings.sort(load_order)
echo "sorted_strings: ", strings

let minimum = minimum_loads(strings)
echo "partition_count: ", minimum.classes.len

for partition_index, length_class in minimum.classes:
  var partition_strings: seq[string]
  for string in strings:
    if string.len >= length_class.min and string.len <= length_class.max:
      partition_strings.add(string)

  echo "partition ", partition_index, ":"
  echo "  length_range: ", length_class.min, "..", length_class.max
  echo "  strings: ", partition_strings
  echo "  loads:"
  for load_index, load in length_class.loads:
    case load.kind
    of FullLoad:
      echo "    ", load_index, ": kind=full offset=", load.offset,
        " width=8"
    of PartialLoad:
      echo "    ", load_index, ": kind=partial offset=", load.offset,
        " width=", load.width

  var groups: seq[ByteGroup]
  for string in partition_strings:
    var group: ByteGroup
    for load in length_class.loads:
      case load.kind
      of FullLoad:
        group.add(loaded_value(string, load.offset))
      of PartialLoad:
        group.add(loaded_prefix_value(string, load.width))
    groups.add(group)

  echo "  byte_groups:"
  for key_index, group in groups:
    echo "    key_index=", key_index,
      " string=", partition_strings[key_index],
      " group=", group

  let mapper = find_mapping(groups)
  let slot_count = 2 * nextPowerOfTwo(groups.len)
  let slot_mask = uint64(slot_count - 1)

  echo "  mapper:"
  echo "    mixer: ", mapper.mixer
  echo "    g_index: ", mapper.g_index
  echo "    pilots: ", mapper.pilots
  echo "    bucket_count: ", mapper.pilots.len
  echo "    slot_count: ", slot_count
  echo "    slot_mask: ", slot_mask
  echo "  mappings:"

  for key_index, group in groups:
    let bucket_id = int(evaluate(mapper.mixer, group))
    let pilot = mapper.pilots[bucket_id]
    let g = group[mapper.g_index]
    let slot = (g + uint64(pilot)) and slot_mask

    echo "    key_index=", key_index,
      " string=", partition_strings[key_index],
      " bucket=", bucket_id,
      " g=", g,
      " pilot=", pilot,
      " slot=", slot
