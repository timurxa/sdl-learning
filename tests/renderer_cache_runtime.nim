include "../src/renderer"

proc cached_layout(value: string): TextLayout =
  get_text_layout(clay_string_slice(value), 0, 12, 0, 16)

proc has_cached_layout(value: string): bool =
  text_cache.hasKey(make_text_key(clay_string_slice(value), 0, 12, 0, 16))

active_renderer = new_renderer()
text_cache = initTable[TextKey, TextCacheEntry]()
text_cache_usage_counter = 0
text_cache_hits = 0
text_cache_misses = 0
text_cache_evictions = 0
font_ready = false

let first_layout = cached_layout("repeat")
let second_layout = cached_layout("repeat")
doAssert first_layout.height == second_layout.height
doAssert text_cache.len == 1
doAssert text_cache_hits == 1
doAssert text_cache_misses == 1
doAssert text_cache_evictions == 0

for index in 0 ..< text_cache_max_entries - 1:
  discard cached_layout("entry" & $index)
doAssert text_cache.len == text_cache_max_entries
doAssert has_cached_layout("repeat")

discard cached_layout("repeat")
doAssert text_cache.len == text_cache_max_entries
doAssert has_cached_layout("repeat")

discard cached_layout("new entry")
doAssert text_cache.len == text_cache_max_entries
doAssert has_cached_layout("repeat")
doAssert not has_cached_layout("entry0")
doAssert text_cache_evictions == 1

discard cached_layout("repeat")
doAssert text_cache_hits == 3
doAssert text_cache_misses == text_cache_max_entries + 1
