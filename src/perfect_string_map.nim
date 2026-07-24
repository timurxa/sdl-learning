# this implements a macro to generate a string map where all keys are known at compile time

import std/[macros, random]
import variable_lookup

type PerfectStringMapConfig = object
  linear_scan_limit: int

const default_perfect_string_map_config = PerfectStringMapConfig(
  linear_scan_limit: 64)

macro define_perfect_string_map_internal(
    name, value_type: static string;
    strings: static seq[string];
    check: static bool;
    config: static PerfectStringMapConfig = default_perfect_string_map_config
): untyped =
  discard value_type
  discard check
  discard config

  let lookup_plan = chooseLookupPlan(strings)
  if lookup_plan.classes.len > 256:
    raise newException(ValueError,
      "perfect string map supports at most 256 length classes")

  var maximum_string_length = 0
  for value in strings:
    if value.len > maximum_string_length:
      maximum_string_length = value.len

  var length_class_values = newSeq[byte](maximum_string_length + 1)
  var length_class_valid = newSeq[bool](maximum_string_length + 1)
  for class_index, class_item in lookup_plan.classes:
    let first_length = max(0, class_item.minLength)
    let last_length = min(maximum_string_length, class_item.maxLength)
    var length = first_length
    while length <= last_length:
      if length_class_valid[length] and
          length_class_values[length] != byte(class_index):
        raise newException(ValueError,
          "overlapping length classes from chooseLookupPlan")
      length_class_values[length] = byte(class_index)
      length_class_valid[length] = true
      inc length

  let type_name = ident(name)
  let length_class_table_identifier = ident("length_class_table")
  let length_class_valid_identifier = ident("length_class_valid")
  let length_class_table_values = nnkBracket.newTree()
  let length_class_valid_values = nnkBracket.newTree()
  for value in length_class_values:
    length_class_table_values.add(newLit(value))
  for value in length_class_valid:
    length_class_valid_values.add(newLit(value))

  let table_type = nnkBracketExpr.newTree(
    ident("array"), newLit(maximum_string_length + 1), ident("byte"))
  let valid_table_type = nnkBracketExpr.newTree(
    ident("array"), newLit(maximum_string_length + 1), ident("bool"))
  let length_class_table_definition = nnkConstDef.newTree(
    length_class_table_identifier, table_type, length_class_table_values)
  let length_class_valid_definition = nnkConstDef.newTree(
    length_class_valid_identifier, valid_table_type, length_class_valid_values)

  let type_definition = nnkTypeDef.newTree(
    type_name,
    newEmptyNode(),
    nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), newNimNode(nnkRecList)))

  let map_parameter = newIdentDefs(
    ident("map"), nnkVarTy.newTree(type_name))
  let string_parameter = newIdentDefs(ident("s"), ident("string"))
  var proc_body = newStmtList()

  proc_body.add quote do:
    if s.len >= `length_class_table_identifier`.len or
        not `length_class_valid_identifier`[s.len]:
      return -1

  let length_expression = nnkBracketExpr.newTree(
    length_class_table_identifier,
    newDotExpr(ident("s"), ident("len")))
  let case_statement = nnkCaseStmt.newTree(length_expression)
  for class_index, class_item in lookup_plan.classes:
    let branch_body = newStmtList()
    var strategy = "class " & $class_index & " lengths " &
                   $class_item.minLength & ".." & $class_item.maxLength &
                   " byte-load strategy:"
    if class_item.loads.len == 0:
      strategy.add(" none")
    else:
      for load_index, load in class_item.loads:
        if load_index != 0:
          strategy.add(",")
        strategy.add(" offset=" & $load.offset &
                     " width=" & $load.width)
    branch_body.add newCall(ident("echo"), newLit(strategy))
    if class_item.loads.len == 0:
      branch_body.add newCall(
        ident("echo"), newLit("class " & $class_index &
                               " loaded byte values: none"))
    else:
      for load in class_item.loads:
        let loaded_values = newCall(
          ident("echo"),
          newLit("class " & $class_index & " loaded byte values " &
                 "offset=" & $load.offset & " width=" & $load.width & ":"))
        for byte_index in 0 ..< load.width:
          if byte_index != 0:
            loaded_values.add(newLit(","))
          loaded_values.add(newCall(
            ident("ord"),
            nnkBracketExpr.newTree(
              ident("s"), newLit(load.offset + byte_index))))
        branch_body.add loaded_values
    branch_body.add quote do:
      return -1
    case_statement.add nnkOfBranch.newTree(newLit(class_index), branch_body)
  case_statement.add nnkElse.newTree(quote do:
    return -1)
  proc_body.add case_statement

  result = newStmtList()
  result.add nnkConstSection.newTree(
    length_class_table_definition, length_class_valid_definition)
  result.add nnkTypeSection.newTree(type_definition)
  result.add newProc(
    ident("candidate_index"),
    [ident("int"), map_parameter, string_parameter],
    proc_body)

const generated_test_strings = block:
  var random_generator = initRand(0x4D595448'u64.int64)
  var generated_strings: seq[string] = @[]
  while generated_strings.len < 256:
    let candidate_length = random_generator.rand(1..256)
    var candidate = newString(candidate_length)
    for index in 0 ..< candidate.len:
      candidate[index] = random_generator.rand('a'..'z')
    if candidate notin generated_strings:
      generated_strings.add(candidate)
  generated_strings

const generated_test_input_index = block:
  var selected_index = -1
  for index, value in generated_test_strings:
    if value.len <= 7:
      selected_index = index
      break
  doAssert selected_index >= 0
  selected_index

expandMacros:
  define_perfect_string_map_internal("Hi", "Bye", generated_test_strings, false)

var h: Hi
echo candidate_index(h, generated_test_strings[generated_test_input_index])
