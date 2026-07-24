# this implements a macro to generate a string map where all keys are known at compile time

import std/macros
import std/bitops
import std/random

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

  let type_name = ident(name)
  let static_strings_identifier = ident("static_strings")
  let static_string_values = nnkBracket.newTree()
  for value in strings:
    static_string_values.add(newLit(value))

  let static_strings_definition = if strings.len == 0:
    nnkConstDef.newTree(
      static_strings_identifier,
      nnkBracketExpr.newTree(ident("array"), newLit(0), ident("string")),
      static_string_values)
  else:
    nnkConstDef.newTree(
      static_strings_identifier,
      newEmptyNode(),
      static_string_values)

  var partitions: seq[tuple[bucket: int, indices: seq[int]]] = @[]
  var empty_indices: seq[int] = @[]
  for index, value in strings:
    if value.len == 0:
      empty_indices.add(index)
      continue
    let bucket = fastLog2(value.len)
    var partition_index = -1
    for index in 0 ..< partitions.len:
      if partitions[index].bucket == bucket:
        partition_index = index
        break
    if partition_index == -1:
      partitions.add((bucket, @[index]))
    else:
      partitions[partition_index].indices.add(index)

  let type_definition = nnkTypeDef.newTree(
    type_name,
    newEmptyNode(),
    nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), newNimNode(nnkRecList)))

  let map_parameter = newIdentDefs(
    ident("map"), nnkVarTy.newTree(type_name))
  let key_parameter = newIdentDefs(ident("key"), ident("string"))
  let bucket_identifier = genSym(nskLet, "bucket")
  var proc_body = newStmtList()

  let empty_body = newStmtList()
  if empty_indices.len == 0:
    empty_body.add quote do:
      raise newException(ValueError, "perfect string map lookup failed")
  elif check:
    for index in empty_indices:
      let static_index = newLit(index)
      empty_body.add quote do:
        if key == `static_strings_identifier`[`static_index`]:
          return `static_index`
    empty_body.add quote do:
      raise newException(ValueError, "perfect string map lookup failed")
  else:
    let static_index = newLit(empty_indices[0])
    empty_body.add quote do:
      return `static_index`

  proc_body.add quote do:
    if key.len == 0:
      `empty_body`
  proc_body.add quote do:
    let `bucket_identifier` = fastLog2(key.len)

  let case_statement = nnkCaseStmt.newTree(bucket_identifier)
  for partition in partitions:
    let bucket = partition.bucket
    let branch_body = newStmtList()
    if partition.indices.len == 1:
      let static_index = newLit(partition.indices[0])
      if check:
        branch_body.add quote do:
          if key == `static_strings_identifier`[`static_index`]:
            return `static_index`
        branch_body.add quote do:
          raise newException(ValueError, "perfect string map lookup failed")
      else:
        branch_body.add quote do:
          return `static_index`
    else:
      var total_length = 0
      for index in partition.indices:
        total_length += strings[index].len
      if total_length <= config.linear_scan_limit:
        for index in partition.indices:
          let static_index = newLit(index)
          branch_body.add quote do:
            if key.len == `static_strings_identifier`[`static_index`].len and
                equalMem(unsafeAddr key[0],
                         unsafeAddr `static_strings_identifier`[`static_index`][0],
                         key.len):
              return `static_index`
        branch_body.add quote do:
          raise newException(ValueError, "perfect string map lookup failed")
      else:
        branch_body.add quote do:
          raise newException(ValueError, "perfect string map lookup failed")
    case_statement.add nnkOfBranch.newTree(newLit(bucket), branch_body)
  case_statement.add nnkElse.newTree(quote do:
    raise newException(ValueError, "perfect string map lookup failed"))
  proc_body.add case_statement

  result = newStmtList()
  result.add nnkConstSection.newTree(static_strings_definition)
  result.add nnkTypeSection.newTree(type_definition)
  result.add newProc(
    ident("candidate_index"),
    [ident("int"), map_parameter, key_parameter],
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
