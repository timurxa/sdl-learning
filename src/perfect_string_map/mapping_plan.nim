import std/[json, strutils]

include mapper_generator

const distinguishing_loads_test = true
include distinguishing_loads

type
  ByteLoadKind* = enum
    byte_load_full,
    byte_load_partial

  SelectedByteLoad* = object
    kind*: ByteLoadKind
    offset*: int
    width*: int

  LengthPartitionPlan* = object
    min_length*: int
    max_length*: int
    selected_byte_loads*: seq[SelectedByteLoad]
    mapper*: Mapper
    output_slot_count*: int

  MappingPlan* = object
    length_partitions*: seq[LengthPartitionPlan]

proc uint64_to_json(value: uint64): JsonNode =
  %($value)

proc uint64_from_json(node: JsonNode): uint64 =
  parseBiggestUInt(node.getStr()).uint64

proc operand_to_json(operand: Operand): JsonNode
proc operand_from_json(node: JsonNode): Operand

proc instruction_to_json(instruction: Instruction): JsonNode =
  if instruction.isNil:
    raise newException(ValueError, "Cannot serialize nil instruction")

  result = newJObject()
  result["kind"] = %($instruction.kind)
  case instruction.kind
  of in_and:
    result["left"] = operand_to_json(instruction.left)
    result["right"] = operand_to_json(instruction.right)
  of in_xor:
    result["source"] = operand_to_json(instruction.source)
    result["shifted_source"] = operand_to_json(instruction.shifted_source)
    result["shift"] = operand_to_json(instruction.shift)
    result["premix_kind"] = %($instruction.premix_kind)
  of in_add:
    result["source"] = operand_to_json(instruction.add_source)
    result["shifted_source"] =
      operand_to_json(instruction.add_shifted_source)
    result["shift"] = operand_to_json(instruction.add_shift)
    result["premix_kind"] = %($instruction.add_premix_kind)
  of in_sub:
    result["source"] = operand_to_json(instruction.sub_source)
    result["shifted_source"] =
      operand_to_json(instruction.sub_shifted_source)
    result["shift"] = operand_to_json(instruction.sub_shift)
    result["premix_kind"] = %($instruction.sub_premix_kind)
  of in_ror:
    result["source"] = operand_to_json(instruction.ror_source)
    result["shift"] = operand_to_json(instruction.ror_shift)
  of in_extr:
    result["left"] = operand_to_json(instruction.extr_left)
    result["right"] = operand_to_json(instruction.extr_right)
    result["shift"] = operand_to_json(instruction.extr_shift)
  of in_mul:
    result["left"] = operand_to_json(instruction.mul_left)
    result["right"] = operand_to_json(instruction.mul_right)
  of in_umulh:
    result["left"] = operand_to_json(instruction.umulh_left)
    result["right"] = operand_to_json(instruction.umulh_right)
  of in_madd:
    result["left"] = operand_to_json(instruction.madd_left)
    result["right"] = operand_to_json(instruction.madd_right)
    result["addend"] = operand_to_json(instruction.madd_addend)
  of in_msub:
    result["left"] = operand_to_json(instruction.msub_left)
    result["right"] = operand_to_json(instruction.msub_right)
    result["subtrahend"] = operand_to_json(instruction.msub_subtrahend)
  of in_ubfx:
    result["input"] = operand_to_json(instruction.input)
    result["position"] = operand_to_json(instruction.pos)
    result["length"] = operand_to_json(instruction.len)

proc operand_to_json(operand: Operand): JsonNode =
  result = newJObject()
  result["kind"] = %($operand.kind)
  case operand.kind
  of op_input:
    result["index"] = %operand.index
  of op_constant:
    result["value"] = uint64_to_json(operand.value)
  of op_instruction:
    result["instruction"] = instruction_to_json(operand.instruction)

proc instruction_from_json(node: JsonNode): Instruction =
  let kind = parseEnum[InstructionKind](node["kind"].getStr())
  case kind
  of in_and:
    Instruction(kind: kind,
      left: operand_from_json(node["left"]),
      right: operand_from_json(node["right"]))
  of in_xor:
    Instruction(kind: kind,
      source: operand_from_json(node["source"]),
      shifted_source: operand_from_json(node["shifted_source"]),
      shift: operand_from_json(node["shift"]),
      premix_kind: parseEnum[PremixKind](node["premix_kind"].getStr()))
  of in_add:
    Instruction(kind: kind,
      add_source: operand_from_json(node["source"]),
      add_shifted_source: operand_from_json(node["shifted_source"]),
      add_shift: operand_from_json(node["shift"]),
      add_premix_kind: parseEnum[PremixKind](node["premix_kind"].getStr()))
  of in_sub:
    Instruction(kind: kind,
      sub_source: operand_from_json(node["source"]),
      sub_shifted_source: operand_from_json(node["shifted_source"]),
      sub_shift: operand_from_json(node["shift"]),
      sub_premix_kind: parseEnum[PremixKind](node["premix_kind"].getStr()))
  of in_ror:
    Instruction(kind: kind,
      ror_source: operand_from_json(node["source"]),
      ror_shift: operand_from_json(node["shift"]))
  of in_extr:
    Instruction(kind: kind,
      extr_left: operand_from_json(node["left"]),
      extr_right: operand_from_json(node["right"]),
      extr_shift: operand_from_json(node["shift"]))
  of in_mul:
    Instruction(kind: kind,
      mul_left: operand_from_json(node["left"]),
      mul_right: operand_from_json(node["right"]))
  of in_umulh:
    Instruction(kind: kind,
      umulh_left: operand_from_json(node["left"]),
      umulh_right: operand_from_json(node["right"]))
  of in_madd:
    Instruction(kind: kind,
      madd_left: operand_from_json(node["left"]),
      madd_right: operand_from_json(node["right"]),
      madd_addend: operand_from_json(node["addend"]))
  of in_msub:
    Instruction(kind: kind,
      msub_left: operand_from_json(node["left"]),
      msub_right: operand_from_json(node["right"]),
      msub_subtrahend: operand_from_json(node["subtrahend"]))
  of in_ubfx:
    Instruction(kind: kind,
      input: operand_from_json(node["input"]),
      pos: operand_from_json(node["position"]),
      len: operand_from_json(node["length"]))

proc operand_from_json(node: JsonNode): Operand =
  let kind = parseEnum[OperandKind](node["kind"].getStr())
  case kind
  of op_input:
    Operand(kind: kind, index: node["index"].getInt())
  of op_constant:
    Operand(kind: kind, value: uint64_from_json(node["value"]))
  of op_instruction:
    Operand(kind: kind,
      instruction: instruction_from_json(node["instruction"]))

proc mapper_to_json(mapper: Mapper): JsonNode =
  var g_node = newJObject()
  g_node["kind"] = %($mapper.g.kind)
  g_node["word_index"] = %mapper.g.word_index
  if mapper.g.kind == g_xor_right_shift:
    g_node["shift"] = %int(mapper.g.shift)

  var pilots = newJArray()
  for pilot in mapper.pilots:
    pilots.add(%int(pilot))

  result = newJObject()
  result["mixer"] = instruction_to_json(mapper.mixer)
  result["g"] = g_node
  result["pilots"] = pilots

proc mapper_from_json(node: JsonNode): Mapper =
  let g_node = node["g"]
  let g_kind = parseEnum[GKind](g_node["kind"].getStr())
  let g = case g_kind
  of g_raw_word:
    G(kind: g_raw_word, word_index: g_node["word_index"].getInt())
  of g_xor_right_shift:
    G(
      kind: g_xor_right_shift,
      word_index: g_node["word_index"].getInt(),
      shift: range[1 .. 63](g_node["shift"].getInt()),
    )

  var pilots: seq[uint16]
  for pilot in node["pilots"]:
    pilots.add(uint16(pilot.getInt()))

  Mapper(
    mixer: instruction_from_json(node["mixer"]),
    g: g,
    pilots: pilots,
  )

proc serialize_mapping_plan*(plan: MappingPlan): string =
  var partitions = newJArray()
  for partition in plan.length_partitions:
    var loads = newJArray()
    for load in partition.selected_byte_loads:
      loads.add(%*{
        "kind": $load.kind,
        "offset": load.offset,
        "width": load.width,
      })

    var partition_node = newJObject()
    partition_node["min_length"] = %partition.min_length
    partition_node["max_length"] = %partition.max_length
    partition_node["selected_byte_loads"] = loads
    partition_node["mapper"] = mapper_to_json(partition.mapper)
    partition_node["output_slot_count"] = %partition.output_slot_count
    partitions.add(partition_node)

  var root = newJObject()
  root["length_partitions"] = partitions
  $root

proc deserialize_mapping_plan*(data: string): MappingPlan =
  let root = parseJson(data)
  for partition_node in root["length_partitions"]:
    var loads: seq[SelectedByteLoad]
    for load_node in partition_node["selected_byte_loads"]:
      loads.add(SelectedByteLoad(
        kind: parseEnum[ByteLoadKind](load_node["kind"].getStr()),
        offset: load_node["offset"].getInt(),
        width: load_node["width"].getInt(),
      ))

    result.length_partitions.add(LengthPartitionPlan(
      min_length: partition_node["min_length"].getInt(),
      max_length: partition_node["max_length"].getInt(),
      selected_byte_loads: loads,
      mapper: mapper_from_json(partition_node["mapper"]),
      output_slot_count: partition_node["output_slot_count"].getInt(),
    ))

proc create_mapping_plan*(input_strings: openArray[string]): MappingPlan =
  if input_strings.len == 0:
    raise newException(ValueError, "Mapping requires at least one string")

  var strings = input_strings.toSeq()
  strings.sort(load_order)
  if strings != deduplicate(strings, true):
    raise newException(ValueError, "Mapping requires unique strings")

  let minimum = minimum_loads(strings)
  for length_class in minimum.classes:
    var partition_strings: seq[string]
    for value in strings:
      if value.len >= length_class.min and value.len <= length_class.max:
        partition_strings.add(value)

    var selected_byte_loads: seq[SelectedByteLoad]
    for load in length_class.loads:
      selected_byte_loads.add(SelectedByteLoad(
        kind: if load.kind == FullLoad:
          byte_load_full
        else:
          byte_load_partial,
        offset: load.offset,
        width: if load.kind == FullLoad: 8 else: load.width,
      ))

    var byte_groups: seq[ByteGroup]
    for value in partition_strings:
      var byte_group: ByteGroup
      for load in length_class.loads:
        case load.kind
        of FullLoad:
          byte_group.add(loaded_value(value, load.offset))
        of PartialLoad:
          byte_group.add(loaded_prefix_value(value, load.width))
      byte_groups.add(byte_group)

    result.length_partitions.add(LengthPartitionPlan(
      min_length: length_class.min,
      max_length: length_class.max,
      selected_byte_loads: selected_byte_loads,
      mapper: find_mapping(byte_groups),
      output_slot_count: 2 * nextPowerOfTwo(byte_groups.len),
    ))
