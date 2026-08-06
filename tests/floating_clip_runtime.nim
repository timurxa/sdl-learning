import "../src/clay"

proc measure_text(text: ClayStringSlice; config: ptr ClayTextElementConfig;
    user_data: pointer): ClayDimensions {.cdecl.} =
  discard config
  discard user_data
  ClayDimensions(width: cfloat(text.length), height: 1)

proc handle_error(error_data: ClayErrorData) {.cdecl.} =
  doAssert false, $error_data.error_type

proc run_clip_case(clip_horizontal, clip_vertical: bool) =
  let memory_size = clay_min_memory_size()
  let arena_memory = alloc0(int(memory_size))
  let arena = clay_create_arena_with_capacity_and_memory(memory_size, arena_memory)
  discard clay_initialize(
    arena,
    clay_dimensions(300, 200),
    ClayErrorHandler(error_handler_function: handle_error, user_data: nil))
  clay_set_measure_text_function(measure_text, nil)

  let root_id = clay_id("clip_test_root")
  let clip_id = clay_id("clip_test_container")
  let anchor_id = clay_id("clip_test_anchor")

  clay_begin_layout()
  element(root_id):
    layout:
      sizing:
        width = fixed(300)
        height = fixed(200)
    element("clip_test_stage"):
      layout:
        sizing:
          width = fixed(300)
          height = fixed(200)
      clip:
        horizontal = clip_horizontal
        vertical = clip_vertical
      element(clip_id):
        layout:
          sizing:
            width = fixed(80)
            height = fixed(80)
        clip:
          horizontal = clip_horizontal
          vertical = clip_vertical
        element(anchor_id):
          layout:
            sizing:
              width = fixed(12)
              height = fixed(12)
          background_color = rgba(4, 5, 6, 255)
          floating:
            parent_id = clip_id.id
            attach_points:
              element = clay_attach_point_left_top
              parent = clay_attach_point_left_top
            attach_to = clay_attach_to_element_with_id
            clip_to = clay_clip_to_attached_parent
            z_index = 10
          element("clip_test_panel"):
            layout:
              sizing:
                width = fixed(120)
                height = fixed(120)
            background_color = rgba(1, 2, 3, 255)
            floating:
              parent_id = anchor_id.id
              attach_points:
                element = clay_attach_point_left_top
                parent = clay_attach_point_left_top
              attach_to = clay_attach_to_element_with_id
              clip_to = clay_clip_to_attached_parent
              z_index = 11
  let commands = clay_end_layout(0)
  let clip_data = clay_get_element_data(clip_id)
  let anchor_data = clay_get_element_data(anchor_id)
  let panel_data = clay_get_element_data(clay_id("clip_test_panel"))
  doAssert clip_data.found
  doAssert anchor_data.found
  doAssert panel_data.found

  var found_panel_clip = false
  for command in commands:
    if command.command_type != clay_render_command_type_scissor_start or
        command.z_index != 11:
      continue
    doAssert command.render_data.clip.horizontal == clip_horizontal
    doAssert command.render_data.clip.vertical == clip_vertical
    found_panel_clip = true
  doAssert found_panel_clip

  clay_deinitialize()
  dealloc(arena_memory)

run_clip_case(true, true)
run_clip_case(false, true)
