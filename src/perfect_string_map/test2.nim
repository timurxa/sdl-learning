import std/macros
import perfect_string_map

expandMacros:
  define_perfect_string_map_internal(
    "ColorMap",
    "int",
    @["red", "tan", "blue"],
    false,
  )

var colors: ColorMap

colors.values_0[colors.candidate_index("red")] = 10
colors.values_0[colors.candidate_index("tan")] = 20
colors.values_0[colors.candidate_index("blue")] = 30

let slot = colors.candidate_index("tan")
if slot >= 0:
  echo colors.values_0[slot]  # 20

# doAssert colors.candidate_index("pink") == -1
