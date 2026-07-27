import std/cmdline

import mapping_plan

proc main() =
  let strings = commandLineParams()
  if strings.len == 0:
    raise newException(
      ValueError,
      "usage: perfect_string_map_cli <strings...>",
    )
  stdout.write(serialize_mapping_plan(create_mapping_plan(strings)))
  stdout.write('\n')

when isMainModule:
  main()
