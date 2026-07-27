import std/[os, osproc, streams, strformat, strutils]

import ../src/perfect_string_map/mapping_plan

const cli_path = currentSourcePath().parentDir() / ".." / "out" /
  "perfect_string_map_cli"

proc run_cli(strings: seq[string]): string =
  let process = startProcess(
    cli_path,
    args = strings,
    options = {poUsePath, poStdErrToStdOut},
  )
  result = process.outputStream().readAll()
  let exit_code = process.waitForExit()
  process.close()
  doAssert exit_code == 0, result

proc assert_mapper_valid(partition: LengthPartitionPlan) =
  doAssert partition.mapper.mixer != nil
  doAssert partition.mapper.pilots.len > 0
  doAssert partition.mapper.g.word_index >= 0
  doAssert partition.mapper.g.word_index <
    partition.selected_byte_loads.len
  doAssert partition.output_slot_count > 0
  doAssert (partition.output_slot_count and
    (partition.output_slot_count - 1)) == 0

proc print_debug(plan: MappingPlan) =
  echo "length_partitions: ", plan.length_partitions.len
  for index, partition in plan.length_partitions:
    echo &"partition {index}: lengths={partition.min_length}.." &
      &"{partition.max_length} M={partition.output_slot_count}"
    for load in partition.selected_byte_loads:
      echo &"  load kind={load.kind} offset={load.offset} width={load.width}"
    echo "  mixer: ", partition.mapper.mixer
    echo "  g: ", partition.mapper.g
    echo "  pilots: ", partition.mapper.pilots

proc test_multiple_length_partitions() =
  let serialized = run_cli(@["a", "b", "c1", "ab1", "ab2"])
  let plan = deserialize_mapping_plan(serialized)
  doAssert plan.length_partitions.len == 2
  doAssert plan.length_partitions[0].min_length == 1
  doAssert plan.length_partitions[0].max_length == 2
  doAssert plan.length_partitions[1].min_length == 3
  doAssert plan.length_partitions[1].max_length == 3
  doAssert plan.length_partitions[0].selected_byte_loads ==
    @[SelectedByteLoad(
      kind: byte_load_partial,
      offset: 0,
      width: 1,
    )]
  doAssert plan.length_partitions[1].selected_byte_loads ==
    @[SelectedByteLoad(
      kind: byte_load_partial,
      offset: 0,
      width: 3,
    )]
  doAssert plan.length_partitions[0].output_slot_count == 8
  doAssert plan.length_partitions[1].output_slot_count == 4
  for partition in plan.length_partitions:
    doAssert partition.selected_byte_loads.len > 0
    assert_mapper_valid(partition)
  doAssert serialize_mapping_plan(plan) == serialized.strip()
  print_debug(plan)

proc test_nontrivial_mapper() =
  let serialized = run_cli(@[
    "0000aaaaaaaa0000",
    "0000aaaaaaaa1111",
    "1111aaaaaaaa0000",
    "1111aaaaaaaa1111",
  ])
  let plan = deserialize_mapping_plan(serialized)
  doAssert plan.length_partitions.len == 1
  let partition = plan.length_partitions[0]
  doAssert partition.selected_byte_loads.len == 2
  doAssert partition.output_slot_count == 8
  doAssert partition.mapper.mixer.kind == in_ubfx
  doAssert $partition.mapper.mixer ==
    $deserialize_mapping_plan(
      serialize_mapping_plan(plan)
    ).length_partitions[0].mapper.mixer
  assert_mapper_valid(partition)
  print_debug(plan)

proc test_nested_mapper_instruction() =
  let serialized = run_cli(@[
    "that", "with", "they", "have", "this", "from", "word", "what",
    "some", "were", "when", "your", "said", "each", "time", "will",
    "many", "then", "them", "like", "long", "make", "look", "more",
    "come", "most", "over", "know", "than", "call", "down", "side",
  ])
  doAssert "\"kind\":\"op_instruction\"" in serialized
  let plan = deserialize_mapping_plan(serialized)
  doAssert plan.length_partitions.len == 1
  let partition = plan.length_partitions[0]
  doAssert partition.output_slot_count == 64
  doAssert "op_instruction" in $partition.mapper.mixer
  doAssert serialize_mapping_plan(plan) == serialized.strip()
  assert_mapper_valid(partition)
  print_debug(plan)

test_multiple_length_partitions()
test_nontrivial_mapper()
test_nested_mapper_instruction()
echo "perfect string map CLI integration tests passed"
