import std/[
  algorithm,
  hashes,
  macros,
  monotimes,
  os,
  random,
  sequtils,
  strformat,
  tables,
  times,
]

import mapping_plan
import perfect_string_map

macro common_words_from_test(): untyped =
  let test_path = currentSourcePath().parentDir() / "test.nim"
  let test_syntax = parseStmt(staticRead(test_path))

  proc find_strings_constant(node: NimNode): NimNode {.compileTime.} =
    if node.kind == nnkConstDef and node[0].eqIdent("strings"):
      return node[2].copyNimTree()
    for child in node:
      let match = find_strings_constant(child)
      if not match.isNil:
        return match

  result = find_strings_constant(test_syntax)
  if result.isNil:
    error("Could not find the common-word strings constant in " & test_path)

const
  benchmark_keys = common_words_from_test()
  key_count = benchmark_keys.len
  lookup_seed = 0x1000_00C5'i64
  lookup_sequence_length = 1 shl 18
  repetitions_per_trial = 32
  trial_count = 11

define_perfect_string_map_internal(
  "BenchmarkPerfectMap",
  "int",
  benchmark_keys,
  false,
)

proc benchmark_mapping_plan(
    strings: seq[string]
): MappingPlan {.compileTime.} =
  let source_dir = currentSourcePath().parentDir()
  let cli_source = source_dir / "perfect_string_map_cli.nim"
  let cli_version = hash(
    getCurrentCompilerExe() &
    staticRead(cli_source) &
    staticRead(source_dir / "mapping_plan.nim") &
    staticRead(source_dir / "mapper_generator.nim") &
    staticRead(source_dir / "distinguishing_loads.nim")
  )
  let cli_path = getTempDir() /
    ("custom_ai_client_perfect_string_map_cli_" & $cli_version)

  if not fileExists(cli_path):
    let build_command = quoteShellCommand([
      getCurrentCompilerExe(),
      "c",
      "-d:danger",
      "-d:lto",
      "-o:" & cli_path,
      cli_source,
    ])
    let build_output = staticExec(build_command)
    if not fileExists(cli_path):
      error(
        "Failed to build perfect_string_map_cli.\n" &
        "Command: " & build_command & "\n" &
        build_output
      )

  var command = quoteShell(cli_path)
  for value in strings:
    command.add(' ')
    command.add(quoteShell(value))
  deserialize_mapping_plan(staticExec(command))

macro define_benchmark_accessors(
    strings: static seq[string]
): untyped =
  let plan = benchmark_mapping_plan(strings)
  let map_type = ident("BenchmarkPerfectMap")

  proc partition_dispatch(
      map_parameter, key_parameter: NimNode;
      value_parameter: NimNode = nil
  ): NimNode {.compileTime.} =
    result = newNimNode(nnkIfStmt)
    for partition_index, partition in plan.length_partitions:
      let slot = newCall(
        ident("candidate_index"),
        map_parameter,
        key_parameter,
      )
      let value_access = nnkBracketExpr.newTree(
        newDotExpr(
          map_parameter,
          ident("values_" & $partition_index),
        ),
        slot,
      )
      let body =
        if value_parameter.isNil:
          newStmtList(nnkReturnStmt.newTree(value_access))
        else:
          newStmtList(nnkAsgn.newTree(value_access, value_parameter))

      if partition_index < plan.length_partitions.high:
        result.add(nnkElifBranch.newTree(
          nnkInfix.newTree(
            ident("<="),
            newDotExpr(key_parameter, ident("len")),
            newLit(partition.max_length),
          ),
          body,
        ))
      else:
        result.add(nnkElse.newTree(body))

  let lookup_map = genSym(nskParam, "map")
  let lookup_key = genSym(nskParam, "key")
  let lookup_proc = newProc(
    ident("benchmark_lookup"),
    [
      ident("int"),
      newIdentDefs(lookup_map, map_type),
      newIdentDefs(lookup_key, ident("string")),
    ],
    partition_dispatch(lookup_map, lookup_key),
    pragmas = nnkPragma.newTree(ident("inline")),
  )

  let set_map = genSym(nskParam, "map")
  let set_key = genSym(nskParam, "key")
  let set_value = genSym(nskParam, "value")
  let set_proc = newProc(
    ident("set_benchmark_value"),
    [
      newEmptyNode(),
      newIdentDefs(
        set_map,
        nnkVarTy.newTree(map_type),
      ),
      newIdentDefs(set_key, ident("string")),
      newIdentDefs(set_value, ident("int")),
    ],
    partition_dispatch(set_map, set_key, set_value),
    pragmas = nnkPragma.newTree(ident("inline")),
  )

  result = newStmtList(lookup_proc, set_proc)

define_benchmark_accessors(benchmark_keys)

type TrialResult = object
  nanoseconds_per_lookup: float64
  checksum: uint64

var observable_checksum: uint64

proc make_lookup_sequence(): seq[string] =
  var rng = initRand(lookup_seed)
  result = newSeq[string](lookup_sequence_length)
  for index in 0 ..< result.len:
    result[index] = benchmark_keys[rng.rand(benchmark_keys.high)]

proc run_perfect_trial(
    perfect_map: BenchmarkPerfectMap;
    lookup_sequence: openArray[string]
): TrialResult {.noinline.} =
  var checksum = 0'u64
  let start_time = getMonoTime()
  for repetition_index in 0 ..< repetitions_per_trial:
    for key_index in 0 ..< lookup_sequence.len:
      checksum += uint64(
        perfect_map.benchmark_lookup(lookup_sequence[key_index]))
  let elapsed_nanoseconds = (getMonoTime() - start_time).inNanoseconds
  result = TrialResult(
    nanoseconds_per_lookup:
      float64(elapsed_nanoseconds) /
      float64(repetitions_per_trial * lookup_sequence.len),
    checksum: checksum,
  )

proc run_table_trial(
    standard_map: Table[string, int];
    lookup_sequence: openArray[string]
): TrialResult {.noinline.} =
  var checksum = 0'u64
  let start_time = getMonoTime()
  for repetition_index in 0 ..< repetitions_per_trial:
    for key_index in 0 ..< lookup_sequence.len:
      checksum += uint64(standard_map[lookup_sequence[key_index]])
  let elapsed_nanoseconds = (getMonoTime() - start_time).inNanoseconds
  result = TrialResult(
    nanoseconds_per_lookup:
      float64(elapsed_nanoseconds) /
      float64(repetitions_per_trial * lookup_sequence.len),
    checksum: checksum,
  )

proc median(values: var seq[float64]): float64 =
  values.sort()
  values[values.len div 2]

proc verify_checksum(
    implementation: string;
    actual_checksum, expected_checksum: uint64
) =
  if actual_checksum != expected_checksum:
    stderr.writeLine(
      implementation,
      " checksum mismatch: expected ",
      expected_checksum,
      ", got ",
      actual_checksum,
    )
    quit(QuitFailure)

proc main() =
  var perfect_map: BenchmarkPerfectMap
  var standard_map = initTable[string, int](key_count)
  for key_index, key in benchmark_keys:
    perfect_map.set_benchmark_value(key, key_index)
    standard_map[key] = key_index

  for key_index, key in benchmark_keys:
    if perfect_map.benchmark_lookup(key) != key_index or
        standard_map[key] != key_index:
      stderr.writeLine("map initialization mismatch for key ", key_index)
      quit(QuitFailure)

  let lookup_sequence = make_lookup_sequence()

  var expected_checksum = 0'u64
  for key in lookup_sequence:
    expected_checksum += uint64(standard_map[key])
  expected_checksum *= uint64(repetitions_per_trial)

  var perfect_timings = newSeqOfCap[float64](trial_count)
  var table_timings = newSeqOfCap[float64](trial_count)
  var verified_checksum = 0'u64

  for trial_index in 0 ..< trial_count:
    let perfect_result =
      if (trial_index and 1) == 0:
        run_perfect_trial(perfect_map, lookup_sequence)
      else:
        let table_result =
          run_table_trial(standard_map, lookup_sequence)
        table_timings.add(table_result.nanoseconds_per_lookup)
        verify_checksum(
          "Table[string, int]",
          table_result.checksum,
          expected_checksum,
        )
        observable_checksum += table_result.checksum
        run_perfect_trial(perfect_map, lookup_sequence)

    perfect_timings.add(perfect_result.nanoseconds_per_lookup)
    verify_checksum(
      "perfect_string_map",
      perfect_result.checksum,
      expected_checksum,
    )
    verified_checksum = perfect_result.checksum
    observable_checksum += perfect_result.checksum

    if (trial_index and 1) == 0:
      let table_result = run_table_trial(standard_map, lookup_sequence)
      table_timings.add(table_result.nanoseconds_per_lookup)
      verify_checksum(
        "Table[string, int]",
        table_result.checksum,
        perfect_result.checksum,
      )
      observable_checksum += table_result.checksum

  let perfect_median = median(perfect_timings)
  let table_median = median(table_timings)

  echo "keys: ", key_count
  echo "dataset: 1000 most common English words from test.nim"
  echo "lookup sequence length: ", lookup_sequence.len
  echo "lookups per trial: ",
    repetitions_per_trial * lookup_sequence.len
  echo "trials: ", trial_count
  echo &"perfect_string_map: {perfect_median:.3f} ns/lookup"
  echo &"Table[string, int]: {table_median:.3f} ns/lookup"
  echo &"relative speedup: {table_median / perfect_median:.2f}x"
  echo "checksum: ", verified_checksum, " (identical)"
  echo "observable checksum sink: ", observable_checksum

when isMainModule:
  main()
