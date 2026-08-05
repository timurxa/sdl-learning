import ../src/clay

var clay_string_cache: ClayStringCache

proc measure_text(text: ClayStringSlice; config: ptr ClayTextElementConfig;
    user_data: pointer): ClayDimensions {.cdecl.} =
  discard user_data
  ClayDimensions(width: cfloat(text.length * int32(config[].font_size)),
    height: cfloat(config[].font_size))

proc next_grapheme_boundary(text: ClayStringSlice; offset: int32;
    user_data: pointer): int32 {.cdecl.} =
  discard user_data
  if offset < text.length: offset + 1 else: text.length

proc handle_error(error_data: ClayErrorData) {.cdecl.} =
  discard error_data

proc build_layout(): ClayRenderCommandArray =
  let reusable_declaration = clay_declaration(
    layout = clay_layout(sizing = clay_sizing(clay_sizing_fixed(10), clay_sizing_fixed(10))),
    background_color = clay_color(1, 2, 3, 4))
  let reusable_text = clay_text_config(font_size = 12)
  clay_frame(clay_string_cache, 1.0 / 60.0):
    element("root"):
      layout:
        sizing:
          width = clay_sizing_grow(0)
          height = clay_sizing_grow(0)
        padding = clay_padding_all(16)
        child_gap = 8
        layout_direction = clay_top_to_bottom
      background_color = clay_color(24, 28, 36, 255)
      corner_radius = clay_corner_radius(8)
      border:
        color = clay_color(100, 110, 130, 255)
        width = clay_border_outside(1)

      element("panel"):
        layout:
          sizing:
            width = clay_sizing_fixed(320)
            height = clay_sizing_percent(0.5)
          child_alignment:
            x = clay_align_x_center
            y = clay_align_y_center
        image:
          image_data = nil
        aspect_ratio:
          aspect_ratio = 16.0 / 9.0

        text("Clay"):
          font_id = 0
          font_size = 24
          text_color = clay_color(255, 255, 255, 255)
          wrap_mode = clay_text_wrap_words_and_graphemes
          text_alignment = clay_text_align_center

      for index in 0 ..< 4:
        element(clay_id_with_index("item", uint32(index))):
          user_data = nil

      element("reusable", reusable_declaration):
        text("typed config", reusable_text):
          discard

      element_auto(reusable_declaration):
        discard

      element("closed", reusable_declaration)
      element_auto(reusable_declaration)
      text("plain text")
      text("plain typed text", reusable_text)

      element("all-public-fields"):
        floating:
          offset = clay_vector2(1, 2)
          expand = clay_dimensions(3, 4)
          parent_id = 0'u32
          z_index = 1'i16
          attach_points:
            element = clay_attach_point_center_center
            parent = clay_attach_point_left_top
          pointer_capture_mode = clay_pointer_capture_mode_passthrough
          attach_to = clay_attach_to_parent
          clip_to = clay_clip_to_attached_parent
        custom:
          custom_data = nil
        clip:
          horizontal = true
          vertical = true
          child_offset = clay_vector2(0, 0)
      transition:
          handler = nil
          duration = 0.2
          properties = clay_transition_property_position
          interaction_handling = clay_transition_allow_interactions_while_transitioning_position
          enter:
            set_initial_state = nil
            trigger = clay_transition_enter_trigger_on_first_parent_frame
          exit:
            set_final_state = nil
            trigger = clay_transition_exit_trigger_when_parent_exits
            sibling_ordering = clay_exit_transition_ordering_natural_order

proc build_layout_with_alias(): ClayRenderCommandArray =
  clay(clay_string_cache, 1.0 / 60.0):
    element_auto:
      layout:
        sizing:
          width = grow()
          height = grow()
      background_color = rgba(0, 0, 0, 255)

proc compile_short_constructors() =
  discard dimensions(640, 480)
  discard vector2(1, 2)
  discard corner_radius(4)
  discard padding_all(8)
  discard border_all(1)
  discard border_outside(1)
  discard fit()
  discard fit(1, 2)
  discard grow()
  discard grow(1, 2)
  discard fixed(4)
  discard percent(0.5)
  discard sizing(grow(), fixed(10))
  discard child_alignment()
  discard layout()
  discard declaration()
  discard text_config(font_size = 16)

proc compile_dynamic_strings(value: string; bytes: cstring) =
  discard clay_string(value)
  discard clay_string(bytes, 3)
  discard clay_string_slice(value)
  discard clay_string_slice(bytes, 3)
  discard clay_id(value)
  discard clay_id_with_index(value, 1)
  discard clay_id_local(value)
  discard clay_id_with_index_local(value, 1)

proc compile_public_api() =
  discard clay_sizing_fit()
  discard clay_sizing_grow()
  var arena = clay_create_arena_with_capacity_and_memory(0, nil)
  var handler = ClayErrorHandler(error_handler_function: handle_error, user_data: nil)
  var dimensions = clay_dimensions(640, 480)
  discard clay_initialize(arena, dimensions, handler)
  clay_set_layout_dimensions(dimensions)
  clay_update_scroll_containers(false, clay_vector2(0, 0), 0.016)
  discard clay_get_pointer_state()
  discard clay_get_current_context()
  discard clay_get_layout_dimensions()
  discard clay_get_open_element_id()
  discard clay_get_element_data(clay_id("root"))
  discard clay_hovered()
  discard clay_pointer_over(clay_id("root"))
  discard clay_get_pointer_over_ids()
  discard clay_get_scroll_container_data(clay_id("root"))
  clay_set_measure_text_function(measure_text, nil)
  clay_set_grapheme_boundary_function(next_grapheme_boundary, nil)
  clay_set_query_scroll_offset_function(proc(element_id: uint32; user_data: pointer): ClayVector2 {.cdecl.} =
    (discard user_data; clay_vector2(element_id, 0)), nil)
  clay_set_debug_mode_enabled(true)
  discard clay_is_debug_mode_enabled()
  clay_set_culling_enabled(true)
  discard clay_get_max_element_count()
  clay_set_max_element_count(8192)
  discard clay_get_max_measure_text_cache_word_count()
  clay_set_max_measure_text_cache_word_count(16384)
  clay_reset_measure_text_cache()
  clay_on_hover(nil, nil)
  discard clay_ease_out(ClayTransitionCallbackArguments())
  clay_deinitialize()

proc compile_render_union(command: var ClayRenderCommand) =
  command.command_type = clay_render_command_type_rectangle
  command.render_data.rectangle.background_color = clay_color(1, 2, 3, 4)
  command.render_data.border.width = clay_border_all(1)
  command.render_data.text.font_size = 16
  command.render_data.image.image_data = nil
  command.render_data.custom.custom_data = nil
  command.render_data.clip.vertical = true
  command.render_data.overlay_color.color = clay_color(1, 1, 1, 1)

proc compile_iteration(commands: var ClayRenderCommandArray) =
  discard clay_render_command_array_get(addr commands, 0)
  for command in commands:
    case command.command_type
    of clay_render_command_type_none:
      discard
    of clay_render_command_type_rectangle:
      discard command.render_data.rectangle
    of clay_render_command_type_border:
      discard command.render_data.border
    of clay_render_command_type_text:
      discard command.render_data.text
    of clay_render_command_type_image:
      discard command.render_data.image
    of clay_render_command_type_scissor_start, clay_render_command_type_scissor_end:
      discard command.render_data.clip
    of clay_render_command_type_overlay_color_start, clay_render_command_type_overlay_color_end:
      discard command.render_data.overlay_color
    of clay_render_command_type_custom:
      discard command.render_data.custom
    else:
      discard
