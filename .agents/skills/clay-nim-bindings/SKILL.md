---
name: clay-nim-bindings
description: Use when writing, reviewing, or debugging this project's Nim bindings and declarative DSL for Clay, including layout declarations, text, render commands, strings, arenas, and compile-only checks.
---

# Clay Nim Bindings

Import with `import clay`. The binding exposes typed constructors plus macros that mirror Clay's declarative layout style.

## Declarative layout

```nim
clay_frame(1.0 / 60.0):
  element("panel"):
    layout:
      layout(direction = clay_top_to_bottom,
             padding = padding_all(16),
             child_gap = 8)
    background_color = rgba(30, 35, 45, 255)
    corner_radius = corner_radius(8)

    text("Hello"):
      text_config = text_config(font_id = 0, font_size = 18,
                                text_color = rgba(255, 255, 255, 255))
```

Use `clay(delta_time):` as the short frame alias. Nested `element` and `text` blocks accept ordinary Nim statements, so loops and conditionals work:

```nim
clay(0.016):
  element_auto:
    for index, label in labels:
      element("row", index):
        text(label)
```

For reusable values, construct typed declarations/configs:

```nim
let row = declaration(layout = layout(direction = clay_left_to_right,
                                      child_gap = 4),
                      background_color = rgba(40, 40, 40, 255))
element("row", row):
  text("Ready", text_config(font_size = 16))
```

## Render commands

After `clay_end_layout()`, iterate the returned commands. Handle rectangle, border, text, image, scissor start/end, overlay start/end, and custom commands; ignore `none`.

```nim
let commands = clay_render_command_array()
for command in commands:
  case command.command_type
  of clay_render_command_type_rectangle:
    draw_rect(command.bounding_box, command.render_data.rectangle)
  of clay_render_command_type_scissor_start:
    push_scissor(command.bounding_box)
  of clay_render_command_type_scissor_end:
    pop_scissor()
  else:
    discard
```

## Memory semantics

Do not infer ownership or lifetime from these examples. Read the implementation before changing memory-sensitive code:

- `src/clay.nim`: wrapper overloads, static/dynamic string flags, slices, arena/context setup, macro expansion, and render-data access.
- `src/clay.h`: authoritative Clay ownership, arena capacity, pointer lifetime, string, and render-command-union semantics.

Clay strings and slices are non-owning views. Dynamic character buffers must stay alive while Clay may read them; static literals use the static-allocation overload. Arena-backed context and render-command pointers must not be retained past their documented lifetime. Verify exact behavior in source, especially when passing callbacks, images, custom data, or user arenas.

## Verification

Compile without running:

```sh
nim c --warnings:on -o:out/clay_compile tests/clay_compile.nim
nim c --warnings:on -o:out/main src/main.nim
```

Remove generated binaries and Nim cache artifacts after compile-only checks.
