import std/[bitops, endians, hashes, macros, os]

import mapping_plan

type PerfectStringMapConfig = object
  linear_scan_limit: int

const default_perfect_string_map_config = PerfectStringMapConfig(
  linear_scan_limit: 64)

var optimizer_cli_ready {.compileTime.} = false
var optimizer_cli_path {.compileTime.}: string

proc perfect_string_map_high_product(left, right: uint64): uint64 {.inline.} =
  const word_mask = 0xFFFF_FFFF'u64
  let left_low = left and word_mask
  let left_high = left shr 32
  let right_low = right and word_mask
  let right_high = right shr 32
  let product_low = left_low * right_low
  let product_middle = (product_low shr 32) +
    (left_high * right_low and word_mask) +
    (left_low * right_high and word_mask)
  left_high * right_high +
    (left_high * right_low shr 32) +
    (left_low * right_high shr 32) +
    (product_middle shr 32)

proc optimizer_mapping_plan(strings: seq[string]): MappingPlan {.compileTime.} =
  let source_dir = currentSourcePath().parentDir()
  let cli_source = source_dir / "perfect_string_map_cli.nim"

  if not optimizer_cli_ready:
    let cli_version = hash(
      getCurrentCompilerExe() &
      staticRead(cli_source) &
      staticRead(source_dir / "mapping_plan.nim") &
      staticRead(source_dir / "mapper_generator.nim") &
      staticRead(source_dir / "distinguishing_loads.nim")
    )
    optimizer_cli_path = getTempDir() /
      ("custom_ai_client_perfect_string_map_cli_" & $cli_version)
    if not fileExists(optimizer_cli_path):
      let build_command = quoteShellCommand([
        getCurrentCompilerExe(),
        "c",
        "-d:danger",
        "-d:lto",
        "-o:" & optimizer_cli_path,
        cli_source,
      ])
      let build_output = staticExec(build_command)
      if not fileExists(optimizer_cli_path):
        error(
          "Failed to build perfect_string_map_cli.\n" &
          "Command: " & build_command & "\n" &
          build_output
        )
    optimizer_cli_ready = true

  var command = quoteShell(optimizer_cli_path)
  for value in strings:
    command.add(' ')
    command.add(quoteShell(value))

  let serialized = staticExec(command)
  if serialized.len == 0:
    error(
      "perfect_string_map_cli produced no output.\n" &
      "Command: " & command
    )

  try:
    result = deserialize_mapping_plan(serialized)
  except CatchableError as exception:
    error(
      "perfect_string_map_cli failed or produced invalid output.\n" &
      "Command: " & command & "\n" &
      "Error: " & exception.msg & "\n" &
      "Output:\n" & serialized
    )

proc array_type(length: int; element_type: NimNode): NimNode {.compileTime.} =
  nnkBracketExpr.newTree(
    ident("array"),
    newLit(length),
    element_type,
  )

proc typed_const(
    name, value_type, value: NimNode
  ): NimNode {.compileTime.} =
  nnkConstSection.newTree(
    nnkConstDef.newTree(name, value_type, value),
  )

proc array_literal[T](values: openArray[T]): NimNode {.compileTime.} =
  result = newNimNode(nnkBracket)
  for value in values:
    result.add(newLit(value))

proc instruction_expression(
    instruction: Instruction; loads: seq[NimNode]
  ): NimNode {.compileTime.}

proc operand_expression(
    operand: Operand; loads: seq[NimNode]
  ): NimNode {.compileTime.} =
  case operand.kind
  of op_input:
    if operand.index < 0 or operand.index >= loads.len:
      error("Mapping plan instruction references an invalid load index")
    loads[operand.index]
  of op_constant:
    newLit(operand.value)
  of op_instruction:
    instruction_expression(operand.instruction, loads)

proc infix_expression(
    operator_name: string; left, right: NimNode
  ): NimNode {.compileTime.} =
  nnkInfix.newTree(ident(operator_name), left, right)

proc shifted_expression(
    source, shifted_source, shift: Operand;
    operator_name, shift_name: string;
    loads: seq[NimNode]
  ): NimNode {.compileTime.} =
  infix_expression(
    operator_name,
    operand_expression(source, loads),
    infix_expression(
      shift_name,
      operand_expression(shifted_source, loads),
      operand_expression(shift, loads),
    ),
  )

proc instruction_expression(
    instruction: Instruction; loads: seq[NimNode]
  ): NimNode {.compileTime.} =
  if instruction.isNil:
    error("Mapping plan contains a nil instruction")

  case instruction.kind
  of in_and:
    infix_expression(
      "and",
      operand_expression(instruction.left, loads),
      operand_expression(instruction.right, loads),
    )
  of in_xor:
    case instruction.premix_kind
    of xor_simple:
      infix_expression(
        "xor",
        operand_expression(instruction.source, loads),
        operand_expression(instruction.shifted_source, loads),
      )
    of xor_left_shift:
      shifted_expression(
        instruction.source,
        instruction.shifted_source,
        instruction.shift,
        "xor",
        "shl",
        loads,
      )
    of xor_right_shift:
      shifted_expression(
        instruction.source,
        instruction.shifted_source,
        instruction.shift,
        "xor",
        "shr",
        loads,
      )
    of xor_rotate_right:
      infix_expression(
        "xor",
        operand_expression(instruction.source, loads),
        newCall(
          bindSym("rotateRightBits"),
          operand_expression(instruction.shifted_source, loads),
          newCall(
            bindSym("int"),
            operand_expression(instruction.shift, loads),
          ),
        ),
      )
    else:
      error("Mapping plan contains an invalid XOR premix kind")
  of in_add:
    case instruction.add_premix_kind
    of add_simple:
      infix_expression(
        "+",
        operand_expression(instruction.add_source, loads),
        operand_expression(instruction.add_shifted_source, loads),
      )
    of add_left_shift:
      shifted_expression(
        instruction.add_source,
        instruction.add_shifted_source,
        instruction.add_shift,
        "+",
        "shl",
        loads,
      )
    of add_right_shift:
      shifted_expression(
        instruction.add_source,
        instruction.add_shifted_source,
        instruction.add_shift,
        "+",
        "shr",
        loads,
      )
    else:
      error("Mapping plan contains an invalid ADD premix kind")
  of in_sub:
    case instruction.sub_premix_kind
    of sub_simple:
      infix_expression(
        "-",
        operand_expression(instruction.sub_source, loads),
        operand_expression(instruction.sub_shifted_source, loads),
      )
    of sub_left_shift:
      shifted_expression(
        instruction.sub_source,
        instruction.sub_shifted_source,
        instruction.sub_shift,
        "-",
        "shl",
        loads,
      )
    of sub_right_shift:
      shifted_expression(
        instruction.sub_source,
        instruction.sub_shifted_source,
        instruction.sub_shift,
        "-",
        "shr",
        loads,
      )
    else:
      error("Mapping plan contains an invalid SUB premix kind")
  of in_ror:
    newCall(
      bindSym("rotateRightBits"),
      operand_expression(instruction.ror_source, loads),
      newCall(
        bindSym("int"),
        operand_expression(instruction.ror_shift, loads),
      ),
    )
  of in_extr:
    let shift = operand_expression(instruction.extr_shift, loads)
    infix_expression(
      "or",
      infix_expression(
        "shr",
        operand_expression(instruction.extr_left, loads),
        shift,
      ),
      infix_expression(
        "shl",
        operand_expression(instruction.extr_right, loads),
        infix_expression("-", newLit(64), shift.copyNimTree()),
      ),
    )
  of in_mul:
    infix_expression(
      "*",
      operand_expression(instruction.mul_left, loads),
      operand_expression(instruction.mul_right, loads),
    )
  of in_umulh:
    newCall(
      bindSym("perfect_string_map_high_product"),
      operand_expression(instruction.umulh_left, loads),
      operand_expression(instruction.umulh_right, loads),
    )
  of in_madd:
    infix_expression(
      "+",
      infix_expression(
        "*",
        operand_expression(instruction.madd_left, loads),
        operand_expression(instruction.madd_right, loads),
      ),
      operand_expression(instruction.madd_addend, loads),
    )
  of in_msub:
    infix_expression(
      "-",
      operand_expression(instruction.msub_subtrahend, loads),
      infix_expression(
        "*",
        operand_expression(instruction.msub_left, loads),
        operand_expression(instruction.msub_right, loads),
      ),
    )
  of in_ubfx:
    let width = operand_expression(instruction.len, loads)
    infix_expression(
      "and",
      infix_expression(
        "shr",
        operand_expression(instruction.input, loads),
        operand_expression(instruction.pos, loads),
      ),
      infix_expression(
        "-",
        infix_expression("shl", newLit(1'u64), width),
        newLit(1'u64),
      ),
    )

proc loaded_plan_value(value: string; load: SelectedByteLoad): uint64
    {.compileTime.} =
  for index in 0 ..< load.width:
    result = (result shl 8) or uint64(ord(value[load.offset + index]))

proc partition_slots(
    strings: seq[string]; partition: LengthPartitionPlan
  ): seq[string] {.compileTime.} =
  result = newSeq[string](partition.output_slot_count)
  var occupied = newSeq[bool](partition.output_slot_count)
  for value in strings:
    if value.len < partition.min_length or value.len > partition.max_length:
      continue
    var group: ByteGroup
    for load in partition.selected_byte_loads:
      group.add(loaded_plan_value(value, load))
    let mixer_result = evaluate(partition.mapper.mixer, group)
    if mixer_result >= uint64(partition.mapper.pilots.len):
      error("Mapping plan mixer produced an invalid pilot index")
    let pilot = partition.mapper.pilots[int(mixer_result)]
    let g = evaluate(partition.mapper.g, group)
    let slot = int(
      (g + uint64(pilot)) and uint64(partition.output_slot_count - 1))
    if occupied[slot]:
      error("Mapping plan produced duplicate slots")
    occupied[slot] = true
    result[slot] = value

proc validate_plan(plan: MappingPlan) {.compileTime.} =
  if plan.length_partitions.len == 0:
    error("Mapping plan contains no length partitions")
  var previous_maximum = -1
  for partition in plan.length_partitions:
    if partition.min_length < 0 or
        partition.max_length < partition.min_length or
        partition.min_length <= previous_maximum:
      error("Mapping plan contains invalid or overlapping length partitions")
    previous_maximum = partition.max_length
    if partition.output_slot_count <= 0 or
        (partition.output_slot_count and
         (partition.output_slot_count - 1)) != 0:
      error("Mapping plan slot count is not a positive power of two")
    if partition.mapper.pilots.len == 0:
      error("Mapping plan contains an empty pilot table")
    if partition.mapper.g.word_index < 0 or
        partition.mapper.g.word_index >= partition.selected_byte_loads.len:
      error("Mapping plan G references an invalid load index")
    for load in partition.selected_byte_loads:
      if load.offset < 0 or load.width < 1 or load.width > 8 or
          load.offset + load.width > partition.min_length:
        error("Mapping plan contains an unsafe serialized load")

proc load_statements(
    key: NimNode; partition: LengthPartitionPlan;
    loads: var seq[NimNode]
  ): NimNode {.compileTime.} =
  result = newStmtList()
  for load in partition.selected_byte_loads:
    let loaded_value = genSym(nskVar, "loaded_value")
    loads.add(loaded_value)
    let offset = newLit(load.offset)
    let width = newLit(load.width)
    result.add quote do:
      var `loaded_value`: uint64 = 0
      copyMem(
        addr `loaded_value`,
        cast[pointer](cast[uint](`key`.cstring) + uint(`offset`)),
        `width`,
      )
    case load.width
    of 1:
      discard
    of 2:
      result.add quote do:
        when cpuEndian == littleEndian:
          swapEndian16(addr `loaded_value`, addr `loaded_value`)
    of 4:
      result.add quote do:
        when cpuEndian == littleEndian:
          swapEndian32(addr `loaded_value`, addr `loaded_value`)
    of 8:
      result.add quote do:
        when cpuEndian == littleEndian:
          swapEndian64(addr `loaded_value`, addr `loaded_value`)
    else:
      let right_shift = newLit(8 * (8 - load.width))
      result.add quote do:
        when cpuEndian == littleEndian:
          swapEndian64(addr `loaded_value`, addr `loaded_value`)
          `loaded_value` = `loaded_value` shr `right_shift`

proc partition_body(
    key: NimNode; partition: LengthPartitionPlan;
    pilots, keys: NimNode; check: bool
  ): NimNode {.compileTime.} =
  var loads: seq[NimNode]
  result = load_statements(key, partition, loads)
  let mixer_result = genSym(nskLet, "mixer_result")
  let pilot = genSym(nskLet, "pilot")
  let g = genSym(nskLet, "g")
  let slot = genSym(nskLet, "slot")
  let mixer_expression = instruction_expression(partition.mapper.mixer, loads)
  result.add newLetStmt(mixer_result, mixer_expression)
  result.add newLetStmt(
    pilot,
    nnkBracketExpr.newTree(
      pilots,
      newCall(bindSym("int"), mixer_result),
    ),
  )
  let g_expression =
    case partition.mapper.g.kind
    of g_raw_word:
      loads[partition.mapper.g.word_index]
    of g_xor_right_shift:
      infix_expression(
        "xor",
        loads[partition.mapper.g.word_index],
        infix_expression(
          "shr",
          loads[partition.mapper.g.word_index],
          newLit(int(partition.mapper.g.shift)),
        ),
      )
  result.add newLetStmt(g, g_expression)
  result.add newLetStmt(
    slot,
    infix_expression(
      "and",
      infix_expression(
        "+",
        g,
        newCall(bindSym("uint64"), pilot),
      ),
      newLit(uint64(partition.output_slot_count - 1)),
    ),
  )
  if check:
    result.add nnkIfStmt.newTree(
      nnkElifBranch.newTree(
        infix_expression(
          "!=",
          nnkBracketExpr.newTree(
            keys,
            newCall(bindSym("int"), slot),
          ),
          key,
        ),
        newStmtList(
          nnkReturnStmt.newTree(newLit(-1)),
        ),
      ),
    )
  result.add nnkReturnStmt.newTree(
    newCall(bindSym("int"), slot),
  )

proc length_dispatch(
    key: NimNode; plan: MappingPlan;
    pilot_tables, key_tables: seq[NimNode];
    check: bool; first, last: int
  ): NimNode {.compileTime.} =
  if first == last:
    let body = partition_body(
      key,
      plan.length_partitions[first],
      pilot_tables[first],
      if check: key_tables[first] else: newEmptyNode(),
      check,
    )
    if not check:
      return body
    let partition = plan.length_partitions[first]
    return nnkIfStmt.newTree(
      nnkElifBranch.newTree(
        infix_expression(
          "or",
          infix_expression(
            "<",
            newDotExpr(key, ident("len")),
            newLit(partition.min_length),
          ),
          infix_expression(
            ">",
            newDotExpr(key, ident("len")),
            newLit(partition.max_length),
          ),
        ),
        newStmtList(
          nnkReturnStmt.newTree(newLit(-1)),
        ),
      ),
      nnkElse.newTree(body),
    )

  let right_first = (first + last + 1) div 2
  let left = length_dispatch(
    key, plan, pilot_tables, key_tables, check, first, right_first - 1)
  let right = length_dispatch(
    key, plan, pilot_tables, key_tables, check, right_first, last)
  nnkIfStmt.newTree(
    nnkElifBranch.newTree(
      infix_expression(
        "<=",
        newDotExpr(key, ident("len")),
        newLit(plan.length_partitions[right_first - 1].max_length),
      ),
      left,
    ),
    nnkElse.newTree(right),
  )

macro define_perfect_string_map_internal*(
    name, value_type: static string;
    strings: static seq[string];
    check: static bool;
    config: static PerfectStringMapConfig = default_perfect_string_map_config
): untyped =
  discard config
  let plan = optimizer_mapping_plan(strings)
  validate_plan(plan)

  let map_type = ident(name)
  let parsed_value_type = parseExpr(value_type)
  var fields = newNimNode(nnkRecList)
  var pilot_tables: seq[NimNode]
  var key_tables: seq[NimNode]

  result = newStmtList()
  for partition_index, partition in plan.length_partitions:
    fields.add newIdentDefs(
      postfix(ident("values_" & $partition_index), "*"),
      array_type(partition.output_slot_count, parsed_value_type.copyNimTree()),
    )

    let pilots = genSym(nskConst, "pilots_" & $partition_index)
    pilot_tables.add(pilots)
    result.add typed_const(
      pilots,
      array_type(partition.mapper.pilots.len, ident("uint16")),
      array_literal(partition.mapper.pilots),
    )

    if check:
      let keys = genSym(nskConst, "keys_" & $partition_index)
      key_tables.add(keys)
      let slots = partition_slots(strings, partition)
      result.add typed_const(
        keys,
        array_type(partition.output_slot_count, ident("string")),
        array_literal(slots),
      )

  let type_definition = nnkTypeDef.newTree(
    postfix(map_type, "*"),
    newEmptyNode(),
    nnkObjectTy.newTree(
      newEmptyNode(),
      newEmptyNode(),
      fields,
    ),
  )
  result.add nnkTypeSection.newTree(type_definition)

  let map_parameter = genSym(nskParam, "map")
  let key_parameter = genSym(nskParam, "s")
  let proc_body = newStmtList(
    newTree(nnkDiscardStmt, map_parameter),
  )
  proc_body.add length_dispatch(
    key_parameter,
    plan,
    pilot_tables,
    key_tables,
    check,
    0,
    plan.length_partitions.high,
  )
  result.add newProc(
    postfix(ident("candidate_index"), "*"),
    [
      ident("int"),
      newIdentDefs(
        map_parameter,
        map_type,
      ),
      newIdentDefs(key_parameter, ident("string")),
    ],
    proc_body,
    pragmas = nnkPragma.newTree(ident("inline")),
  )
