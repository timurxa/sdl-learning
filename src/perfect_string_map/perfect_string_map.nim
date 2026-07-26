# bare-bones skeleton for generated perfect string maps

import std/macros

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
  discard strings
  discard check
  discard config

  let type_definition = nnkTypeDef.newTree(
    ident(name),
    newEmptyNode(),
    nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(),
      newNimNode(nnkRecList)))
  let map_parameter = newIdentDefs(
    ident("map"), nnkVarTy.newTree(ident(name)))
  let key_parameter = newIdentDefs(ident("key"), ident("string"))
  let proc_body = newStmtList(
    newTree(nnkDiscardStmt, newEmptyNode()))

  result = newStmtList()
  result.add nnkTypeSection.newTree(type_definition)
  result.add newProc(
    ident("candidate_index"),
    [ident("int"), map_parameter, key_parameter],
    proc_body)
