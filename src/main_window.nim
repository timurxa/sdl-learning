import clay
import sdl
import ui
import window
import renderer

type
  Palette = object
    background: ClayColor
    ink: ClayColor
    paper: ClayColor
    yellow: ClayColor
    blue: ClayColor
    pink: ClayColor
    mint: ClayColor
    purple: ClayColor

  MainWindow* = ref object of WindowView
    palette: Palette
    ui_state: UiState
    debug_cycle_frame: uint64
    debug_last_phase: int

const
  nav_labels = ["Overview", "Activity", "Analytics", "Deployments", "Alerts", "Settings", "Team", "Archive"]

proc palette_color(color: ClayColor): ClayColor =
  color

proc new_main_window*(): MainWindow =
  MainWindow(
    palette: Palette(
      background: rgba(241, 235, 217, 255),
      ink: rgba(20, 18, 15, 255),
      paper: rgba(255, 250, 235, 255),
      yellow: rgba(255, 210, 63, 255),
      blue: rgba(70, 145, 255, 255),
      pink: rgba(255, 103, 174, 255),
      mint: rgba(83, 220, 169, 255),
      purple: rgba(169, 126, 255, 255)),
    ui_state: new_ui_state())

proc background_color*(view: MainWindow): ClayColor =
  view.palette.background

method set_window*(view: MainWindow; window: ptr SdlWindow) =
  view.ui_state.set_window(window)

method handle_event*(view: MainWindow; event: UiEvent) =
  view.ui_state.enqueue_event(event)

method render*(view: MainWindow; renderer: Renderer; clay_context: ptr ClayContext;
    string_cache: var ClayStringCache; delta_time: float32): bool =
  renderer.render_frame(
    clay_context,
    string_cache,
    proc() = view.ui_state.prepare_frame(),
    proc(frame: ViewFrame) = view.build_elements(frame),
    proc() = view.ui_state.finish_frame(),
    delta_time)

proc debug_transition_set_initial_state(target_state: ClayTransitionData;
    properties: ClayTransitionProperty): ClayTransitionData {.cdecl.} =
  result = target_state
  if (int32(properties) and int32(clay_transition_property_x)) != 0:
    result.bounding_box.x -= 24
  if (int32(properties) and int32(clay_transition_property_y)) != 0:
    result.bounding_box.y += 12

proc debug_transition_set_final_state(initial_state: ClayTransitionData;
    properties: ClayTransitionProperty): ClayTransitionData {.cdecl.} =
  result = initial_state
  if (int32(properties) and int32(clay_transition_property_x)) != 0:
    result.bounding_box.x += 36
  if (int32(properties) and int32(clay_transition_property_y)) != 0:
    result.bounding_box.y += 18


method build_elements*(view: MainWindow; frame: ViewFrame) =
  let search_element_id = clay_id("search_field")
  view.ui_state.register_text_field(
    text_field_search,
    search_element_id,
    initial_value = "type here")

  inc view.debug_cycle_frame
  let debug_phase = int((view.debug_cycle_frame div 60'u64) mod 4'u64)
  if debug_phase != view.debug_last_phase:
    echo "Clay transition debug: phase ", debug_phase,
      ", exiting transitions = ", frame.exiting_transitions
    view.debug_last_phase = debug_phase
  let debug_show_panel_a = debug_phase != 2
  let debug_swap_panels = debug_phase == 1 or debug_phase == 2

  let debug_transition = ClayTransitionElementConfig(
    handler: clay_ease_out,
    duration: 0.45,
    properties: clay_transition_property_position,
    interaction_handling: clay_transition_allow_interactions_while_transitioning_position,
    enter: ClayTransitionEnter(
      set_initial_state: debug_transition_set_initial_state,
      trigger: clay_transition_enter_trigger_on_first_parent_frame),
    exit: ClayTransitionExit(
      set_final_state: debug_transition_set_final_state,
      trigger: clay_transition_exit_trigger_when_parent_exits,
      sibling_ordering: clay_exit_transition_ordering_natural_order))
  let debug_panel_layout = layout(
    sizing = sizing(grow(), grow()),
    padding = padding_all(6),
    child_gap = 3,
    layout_direction = clay_top_to_bottom)
  let vertical_panel_clip = ClayClipElementConfig(vertical: true)
  let debug_panel_a_declaration = declaration(
    layout = debug_panel_layout,
    clip = vertical_panel_clip,
    background_color = palette_color(view.palette.pink),
    border = ClayBorderElementConfig(
      color: palette_color(view.palette.ink), width: border_outside(3)),
    transition = debug_transition)
  let debug_panel_b_declaration = declaration(
    layout = debug_panel_layout,
    clip = vertical_panel_clip,
    background_color = palette_color(view.palette.mint),
    border = ClayBorderElementConfig(
      color: palette_color(view.palette.ink), width: border_outside(3)),
    transition = debug_transition)


  element("root"):
    layout:
      sizing:
        width = grow()
        height = grow()
      padding = padding_all(16)
      child_gap = 14
      layout_direction = clay_top_to_bottom
    background_color = palette_color(view.palette.background)
    border:
      color = palette_color(view.palette.ink)
      width = border_outside(4)

    element("top_bar"):
      layout:
        sizing:
          width = grow()
          height = fixed(66)
        padding = padding_all(10)
        child_gap = 12
        layout_direction = clay_left_to_right
      clip:
        vertical = true
      background_color = palette_color(view.palette.paper)
      border:
        color = palette_color(view.palette.ink)
        width = border_outside(4)

      element("brand"):
        layout:
          sizing:
            width = fixed(70)
            height = fixed(46)
          child_alignment:
            x = clay_align_x_center
            y = clay_align_y_center
        clip:
          vertical = true
        background_color = palette_color(view.palette.pink)
        border:
          color = palette_color(view.palette.ink)
          width = border_outside(4)
        text("NB/01"):
          font_size = 16
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes

      element("title"):
        layout:
          sizing:
            width = grow()
            height = grow()
          padding = padding_all(2)
          layout_direction = clay_top_to_bottom
          child_gap = 3
          child_alignment:
            y = clay_align_y_center
        clip:
          vertical = true
        text("NEO BRUTAL STACK"):
          font_size = 19
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes
        text("HARD EDGES / DEEP LAYERS"):
          font_size = 10
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes

      element(search_element_id):
        layout:
          sizing:
            width = fixed(174)
            height = grow()
          padding = padding_all(8)
          child_gap = 3
          layout_direction = clay_top_to_bottom
        clip:
          vertical = true
        background_color = if view.ui_state.text_field_focused(text_field_search):
          palette_color(view.palette.yellow)
        else:
          palette_color(view.palette.paper)
        border:
          color = palette_color(view.palette.ink)
          width = border_outside(3)
        text("INPUT // SEARCH"):
          font_size = 8
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes
        text(view.ui_state.text_field_display(text_field_search)):
          font_size = 11
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes

      element("status"):
        layout:
          sizing:
            width = fixed(116)
            height = grow()
          padding = padding_all(8)
          child_gap = 4
          layout_direction = clay_top_to_bottom
          child_alignment:
            x = clay_align_x_center
        clip:
          vertical = true
        background_color = palette_color(view.palette.mint)
        border:
          color = palette_color(view.palette.ink)
          width = border_outside(4)
        text("STATUS: LIVE"):
          font_size = 10
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes
        element("status_bar"):
          layout:
            sizing:
              width = grow()
              height = fixed(8)
          background_color = palette_color(view.palette.ink)

    element("body"):
      layout:
        sizing:
          width = grow()
          height = grow()
        child_gap = 14
        layout_direction = clay_left_to_right

      element("sidebar"):
        layout:
          sizing:
            width = fixed(150)
            height = grow()
          padding = padding_all(10)
          child_gap = 8
          layout_direction = clay_top_to_bottom
        clip:
          vertical = true
        background_color = palette_color(view.palette.yellow)
        border:
          color = palette_color(view.palette.ink)
          width = border_outside(4)
        text("INDEX // 08"):
          font_size = 13
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes
        for index in 0 ..< 8:
          element(clay_id_with_index("nav_item", uint32(index))):
            layout:
              sizing:
                width = grow()
                height = fixed(28)
              padding = padding_all(6)
              layout_direction = clay_left_to_right
            clip:
              vertical = true
            background_color = if index == 0:
              palette_color(view.palette.pink)
            else:
              palette_color(view.palette.paper)
            border:
              color = palette_color(view.palette.ink)
              width = border_outside(3)
            text(nav_labels[index]):
              font_size = 10
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes

      element("workbench"):
        layout:
          sizing:
            width = grow()
            height = grow()
          padding = padding_all(12)
          child_gap = 10
          layout_direction = clay_top_to_bottom
        clip:
          vertical = true
        background_color = palette_color(view.palette.blue)
        border:
          color = palette_color(view.palette.ink)
          width = border_outside(4)

        text("FLOATING BOX STUDY"):
          font_size = 13
          text_color = palette_color(view.palette.paper)
          wrap_mode = clay_text_wrap_words_and_graphemes

        element("string_pool_debug"):
          layout:
            sizing:
              width = grow()
              height = fixed(112)
            padding = padding_all(8)
            child_gap = 5
            layout_direction = clay_top_to_bottom
          clip:
            vertical = true
          background_color = palette_color(view.palette.yellow)
          border:
            color = palette_color(view.palette.ink)
            width = border_outside(3)
          text("STRING POOL / EXIT CYCLE"):
            font_size = 11
            text_color = palette_color(view.palette.ink)
            wrap_mode = clay_text_wrap_words_and_graphemes
          text("GEN " & $frame.string_cache_generation &
            " / LIVE " & $frame.string_cache_generation_count &
            " / EXIT " & $frame.exiting_transitions):
            font_size = 9
            text_color = palette_color(view.palette.ink)
            wrap_mode = clay_text_wrap_words_and_graphemes
          element("debug_slots"):
            layout:
              sizing:
                width = grow()
                height = grow()
              child_gap = 6
              layout_direction = clay_left_to_right
            if debug_swap_panels:
              element("debug_panel_b", debug_panel_b_declaration):
                text("PANEL B // " & $view.debug_cycle_frame):
                  font_size = 10
                  text_color = palette_color(view.palette.ink)
                  wrap_mode = clay_text_wrap_words_and_graphemes
                text("DYNAMIC / STABLE POINTER"):
                  font_size = 8
                  text_color = palette_color(view.palette.ink)
                  wrap_mode = clay_text_wrap_words_and_graphemes
              if debug_show_panel_a:
                element("debug_panel_a", debug_panel_a_declaration):
                  text("PANEL A // " & $view.debug_cycle_frame):
                    font_size = 10
                    text_color = palette_color(view.palette.ink)
                    wrap_mode = clay_text_wrap_words_and_graphemes
                  text("EXIT / RE-ENTER TEST"):
                    font_size = 8
                    text_color = palette_color(view.palette.ink)
                    wrap_mode = clay_text_wrap_words_and_graphemes
            else:
              if debug_show_panel_a:
                element("debug_panel_a", debug_panel_a_declaration):
                  text("PANEL A // " & $view.debug_cycle_frame):
                    font_size = 10
                    text_color = palette_color(view.palette.ink)
                    wrap_mode = clay_text_wrap_words_and_graphemes
                  text("EXIT / RE-ENTER TEST"):
                    font_size = 8
                    text_color = palette_color(view.palette.ink)
                    wrap_mode = clay_text_wrap_words_and_graphemes
              element("debug_panel_b", debug_panel_b_declaration):
                text("PANEL B // " & $view.debug_cycle_frame):
                  font_size = 10
                  text_color = palette_color(view.palette.ink)
                  wrap_mode = clay_text_wrap_words_and_graphemes
                text("DYNAMIC / STABLE POINTER"):
                  font_size = 8
                  text_color = palette_color(view.palette.ink)
                  wrap_mode = clay_text_wrap_words_and_graphemes

        element("stage"):
          layout:
            sizing:
              width = grow()
              height = grow()
          clip:
            vertical = true
          background_color = palette_color(view.palette.paper)
          border:
            color = palette_color(view.palette.ink)
            width = border_outside(4)

          element("stage_base"):
            layout:
              sizing:
                width = grow()
                height = grow()
              padding = padding_all(12)
              child_gap = 8
              layout_direction = clay_top_to_bottom
            clip:
              vertical = true
            background_color = palette_color(view.palette.purple)
            border:
              color = palette_color(view.palette.ink)
              width = border_outside(3)
            text("LAYER 0 / BACKPLATE"):
              font_size = 12
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            element("base_row"):
              layout:
                sizing:
                  width = grow()
                  height = grow()
                child_gap = 8
                layout_direction = clay_left_to_right
              element("base_left"):
                layout:
                  sizing:
                    width = percent(0.48)
                    height = grow()
                  padding = padding_all(8)
                  layout_direction = clay_top_to_bottom
                  child_gap = 6
                clip:
                  vertical = true
                background_color = palette_color(view.palette.yellow)
                border:
                  color = palette_color(view.palette.ink)
                  width = border_outside(3)
                text("STATIC BOX"):
                  font_size = 11
                  text_color = palette_color(view.palette.ink)
                  wrap_mode = clay_text_wrap_words_and_graphemes
                text("WAITING FOR IMPACT"):
                  font_size = 10
                  text_color = palette_color(view.palette.ink)
                  wrap_mode = clay_text_wrap_words_and_graphemes
              element("base_right"):
                layout:
                  sizing:
                    width = grow()
                    height = grow()
                  padding = padding_all(8)
                  layout_direction = clay_top_to_bottom
                  child_gap = 6
                clip:
                  vertical = true
                background_color = palette_color(view.palette.mint)
                border:
                  color = palette_color(view.palette.ink)
                  width = border_outside(3)
                text("DEPTH MAP"):
                  font_size = 11
                  text_color = palette_color(view.palette.ink)
                  wrap_mode = clay_text_wrap_words_and_graphemes
                text("supercalifragilisticexpialidocioussupercalifragilisticexpialidocioussupercalifragilisticexpialidocious"):
                  font_size = 10
                  text_color = palette_color(view.palette.ink)
                  wrap_mode = clay_text_wrap_words_and_graphemes
                text("0 / 1 / 2 / 3 / 4"):
                  font_size = 10
                  text_color = palette_color(view.palette.ink)
                  wrap_mode = clay_text_wrap_words_and_graphemes

          element("float_yellow"):
            layout:
              sizing:
                width = fixed(210)
                height = fixed(112)
              padding = padding_all(10)
              child_gap = 5
              layout_direction = clay_top_to_bottom
            clip:
              vertical = true
            background_color = palette_color(view.palette.yellow)
            border:
              color = palette_color(view.palette.ink)
              width = border_outside(4)
            floating:
              offset = vector2(18, 18)
              z_index = 1
              attach_points:
                element = clay_attach_point_left_top
                parent = clay_attach_point_left_top
              pointer_capture_mode = clay_pointer_capture_mode_passthrough
              attach_to = clay_attach_to_parent
              clip_to = clay_clip_to_none
            text("LAYER 1"):
              font_size = 12
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("YELLOW / FRONT LEFT"):
              font_size = 16
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("OFFSET +018 / +018"):
              font_size = 10
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            element("yellow_strip"):
              layout:
                sizing:
                  width = fixed(116)
                  height = fixed(8)
              background_color = palette_color(view.palette.ink)

          element("float_blue"):
            layout:
              sizing:
                width = fixed(214)
                height = fixed(116)
              padding = padding_all(10)
              child_gap = 5
              layout_direction = clay_top_to_bottom
            clip:
              vertical = true
            background_color = palette_color(view.palette.blue)
            border:
              color = palette_color(view.palette.ink)
              width = border_outside(4)
            floating:
              offset = vector2(104, 66)
              z_index = 2
              attach_points:
                element = clay_attach_point_left_top
                parent = clay_attach_point_left_top
              pointer_capture_mode = clay_pointer_capture_mode_passthrough
              attach_to = clay_attach_to_parent
              clip_to = clay_clip_to_none
            text("LAYER 2"):
              font_size = 12
              text_color = palette_color(view.palette.paper)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("BLUE / OVERLAP"):
              font_size = 16
              text_color = palette_color(view.palette.paper)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("Z-INDEX 002"):
              font_size = 10
              text_color = palette_color(view.palette.paper)
              wrap_mode = clay_text_wrap_words_and_graphemes
            element("blue_strip"):
              layout:
                sizing:
                  width = fixed(144)
                  height = fixed(8)
              background_color = palette_color(view.palette.ink)

          element("float_pink"):
            layout:
              sizing:
                width = fixed(190)
                height = fixed(106)
              padding = padding_all(10)
              child_gap = 5
              layout_direction = clay_top_to_bottom
            clip:
              vertical = true
            background_color = palette_color(view.palette.pink)
            border:
              color = palette_color(view.palette.ink)
              width = border_outside(4)
            floating:
              offset = vector2(188, 150)
              z_index = 3
              attach_points:
                element = clay_attach_point_left_top
                parent = clay_attach_point_left_top
              pointer_capture_mode = clay_pointer_capture_mode_passthrough
              attach_to = clay_attach_to_parent
              clip_to = clay_clip_to_none
            text("LAYER 3"):
              font_size = 12
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("PINK / CROSSOVER"):
              font_size = 15
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("Z-INDEX 003"):
              font_size = 10
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            element("pink_tag"):
              layout:
                sizing:
                  width = fixed(94)
                  height = fixed(28)
                padding = padding_all(4)
                child_alignment:
                  x = clay_align_x_center
                  y = clay_align_y_center
              clip:
                vertical = true
              background_color = palette_color(view.palette.ink)
              floating:
                offset = vector2(10, -14)
                z_index = 5
                attach_points:
                  element = clay_attach_point_right_top
                  parent = clay_attach_point_right_top
                pointer_capture_mode = clay_pointer_capture_mode_passthrough
                attach_to = clay_attach_to_parent
                clip_to = clay_clip_to_none
              text("LEVEL 5"):
                font_size = 10
                text_color = palette_color(view.palette.paper)
                wrap_mode = clay_text_wrap_words_and_graphemes

          element("float_mint"):
            layout:
              sizing:
                width = fixed(166)
                height = fixed(84)
              padding = padding_all(10)
              child_gap = 5
              layout_direction = clay_top_to_bottom
            clip:
              vertical = true
            background_color = palette_color(view.palette.mint)
            border:
              color = palette_color(view.palette.ink)
              width = border_outside(4)
            floating:
              offset = vector2(52, 190)
              z_index = 4
              attach_points:
                element = clay_attach_point_left_top
                parent = clay_attach_point_left_top
              pointer_capture_mode = clay_pointer_capture_mode_passthrough
              attach_to = clay_attach_to_parent
              clip_to = clay_clip_to_none
            text("LAYER 4"):
              font_size = 12
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("MINT / LAST WORD"):
              font_size = 13
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes
            text("Z-INDEX 004"):
              font_size = 10
              text_color = palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes

    element("footer"):
      layout:
        sizing:
          width = grow()
          height = fixed(40)
        padding = padding_all(8)
        child_gap = 10
        layout_direction = clay_left_to_right
        child_alignment:
          y = clay_align_y_center
      clip:
        vertical = true
      background_color = palette_color(view.palette.ink)
      border:
        color = palette_color(view.palette.ink)
        width = border_outside(4)
      text("CLAY / FLOATING / 60 FPS"):
        font_size = 10
        text_color = palette_color(view.palette.paper)
        wrap_mode = clay_text_wrap_words_and_graphemes
      element("footer_pink"):
        layout:
          sizing:
            width = fixed(74)
            height = fixed(18)
          child_alignment:
            x = clay_align_x_center
            y = clay_align_y_center
        clip:
          vertical = true
        background_color = palette_color(view.palette.pink)
        border:
          color = palette_color(view.palette.paper)
          width = border_outside(2)
        text("Z: 005"):
          font_size = 9
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes
      element("footer_yellow"):
        layout:
          sizing:
            width = fixed(112)
            height = fixed(18)
          child_alignment:
            x = clay_align_x_center
            y = clay_align_y_center
        clip:
          vertical = true
        background_color = palette_color(view.palette.yellow)
        border:
          color = palette_color(view.palette.paper)
          width = border_outside(2)
        text("NO ROUNDED CORNERS"):
          font_size = 8
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes
