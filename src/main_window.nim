import std/[random, strutils]
import clay
import sdl
import ui
import renderer
import graph_ui

type
  MainTabKind = enum
    main_tab_workspace
    main_tab_graph

  TabManager = object
    active_tab: MainTabKind

  Palette = object
    background: ClayColor
    ink: ClayColor
    paper: ClayColor
    yellow: ClayColor
    blue: ClayColor
    pink: ClayColor
    mint: ClayColor
    purple: ClayColor

  WorkspaceTab = ref object
    graph_view: GraphView
    debug_cycle_frame: uint64
    debug_last_phase: int

  ConversationSpeaker = enum
    conversation_node
    conversation_user

  ConversationMessage = object
    speaker: ConversationSpeaker
    content: string

  GraphTab = ref object
    graph_view: GraphView
    layout_edges: seq[GraphLayoutEdge]
    conversation_messages: seq[ConversationMessage]
    mutation_elapsed: float32
    mutation_count: int

  MainWindow* = ref object
    palette: Palette
    ui_state: UiState
    tab_manager: TabManager
    workspace_tab: WorkspaceTab
    graph_tab: GraphTab

# DEBUG GRAPH DEMO: remove this block to remove random graph activity.
proc debug_graph_color(index: int): ClayColor =
  case index mod 4
  of 0: rgba(255, 210, 63, 255)
  of 1: rgba(83, 220, 169, 255)
  of 2: rgba(169, 126, 255, 255)
  else: rgba(255, 103, 174, 255)

proc debug_refresh_arrows(tab: GraphTab) =
  tab.graph_view.arrows = newSeq[GraphArrow](tab.layout_edges.len)
  for index, edge in tab.layout_edges:
    tab.graph_view.arrows[index] = GraphArrow(
      start_node_id: edge.start_node_id,
      end_node_id: edge.end_node_id,
      padding: 8,
      color: rgba(20, 18, 15, 255),
      shaft_width: 3,
      head_length: 10,
      head_width: 10)

proc debug_randomize_graph(tab: GraphTab; node_count: int) =
  while tab.graph_view.nodes.len < node_count:
    let node_index = tab.graph_view.nodes.len
    tab.graph_view.nodes.add(GraphNode(
      stable_id: uint32(node_index + 1),
      screen_position: vector2(80 + node_index * 70, 70 + rand(250)),
      size: dimensions(32, 32),
      circle_color: debug_graph_color(node_index),
      z_index: int16(node_index)))
  if tab.graph_view.nodes.len > node_count:
    tab.graph_view.nodes.setLen(node_count)

  tab.layout_edges = newSeq[GraphLayoutEdge](0)
  for start_index in 0 ..< node_count - 1:
    tab.layout_edges.add(GraphLayoutEdge(
      start_node_id: uint32(start_index + 1),
      end_node_id: uint32(start_index + 2)))
  for start_index in 0 ..< node_count:
    for end_index in start_index + 2 ..< node_count:
      if rand(3) == 0:
        tab.layout_edges.add(GraphLayoutEdge(
          start_node_id: uint32(start_index + 1),
          end_node_id: uint32(end_index + 1)))

proc new_debug_graph_tab(): GraphTab =
  randomize()
  new(result)
  result.graph_view.node_pointer_capture_mode = clay_pointer_capture_mode_passthrough
  result.conversation_messages = @[
    ConversationMessage(
      speaker: conversation_node,
      content: "Graph node ready. I can inspect this branch."),
    ConversationMessage(
      speaker: conversation_user,
      content: "Show me what changed in this node."),
    ConversationMessage(
      speaker: conversation_node,
      content: "Three upstream links found. One is still waiting."),
    ConversationMessage(
      speaker: conversation_user,
      content: "Keep waiting state visible in the graph."),
    ConversationMessage(
      speaker: conversation_node,
      content: "Waiting state retained. Downstream output remains quiet."),
    ConversationMessage(
      speaker: conversation_user,
      content: "Add a longer note so this log can be scrolled independently."),
    ConversationMessage(
      speaker: conversation_node,
      content: "Long notes stay inside the conversation log while composer stays docked below."),
    ConversationMessage(
      speaker: conversation_user,
      content: "The graph remains interactive behind this panel."),
    ConversationMessage(
      speaker: conversation_node,
      content: "Correct. Panel captures its own pointer and wheel input."),
    ConversationMessage(
      speaker: conversation_user,
      content: "Ready for another message." )]
  result.debug_randomize_graph(8 + rand(5))
  result.debug_refresh_arrows()
  var layout_config = default_graph_layout_config()
  layout_config.layer_gap = 96
  layout_config.node_gap = 56
  discard result.graph_view.begin_graph_layout(result.layout_edges, layout_config)

proc debug_mutate_graph(tab: GraphTab) =
  tab.debug_randomize_graph(6 + rand(8))
  inc tab.mutation_count
  tab.debug_refresh_arrows()
  var layout_config = default_graph_layout_config()
  layout_config.layer_gap = 96
  layout_config.node_gap = 56
  discard tab.graph_view.begin_graph_layout(tab.layout_edges, layout_config)

proc update_debug_graph(view: MainWindow; delta_time: float32) =
  let tab = view.graph_tab
  tab.mutation_elapsed += max(delta_time, 0'f32)
  if tab.mutation_elapsed >= 5'f32:
    tab.mutation_elapsed -= 5'f32
    tab.debug_mutate_graph()
  discard tab.graph_view.step_graph_layout(delta_time)

const
  nav_labels = ["Overview", "Activity", "Analytics", "Deployments", "Alerts", "Settings", "Team", "Archive"]
  workspace_tab_button_id = "tab_workspace"
  graph_tab_button_id = "tab_graph"
  graph_conversation_input_id = "graph_conversation_input"
  graph_conversation_log_id = "graph_conversation_log"
  graph_conversation_composer_id = "graph_conversation_composer"

template scrollable_declaration(element_declaration: untyped): ClayElementDeclaration =
  var scroll_declaration = element_declaration
  scroll_declaration.clip.child_offset = clay_get_scroll_offset()
  scroll_declaration

template scrollable_element(element_id: untyped; element_declaration: untyped;
    body: untyped) =
  clay_element_scope(element_id, scrollable_declaration(element_declaration)):
    body

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
    ui_state: new_ui_state(),
    tab_manager: TabManager(active_tab: main_tab_workspace),
    workspace_tab: WorkspaceTab(
      graph_view: GraphView(nodes: @[
        GraphNode(
          stable_id: 1,
          screen_position: vector2(300, 300),
          size: dimensions(154, 62),
          circle_color: rgba(255, 210, 63, 255),
          title: "INPUT NODE",
          detail: "SOURCE / READY"),
        GraphNode(
          stable_id: 2,
          screen_position: vector2(500, 500),
          size: dimensions(154, 62),
          circle_color: rgba(83, 220, 169, 255),
          title: "OUTPUT NODE",
          detail: "SINK / WAITING")])),
    graph_tab: new_debug_graph_tab())

proc background_color*(view: MainWindow): ClayColor =
  view.palette.background

proc set_window*(view: MainWindow; window: ptr SdlWindow) =
  view.ui_state.set_window(window)

proc handle_event*(view: MainWindow; event: UiEvent) =
  view.ui_state.enqueue_event(event)

proc build_elements*(view: MainWindow; frame: ViewFrame)
proc build_workspace_tab(view: MainWindow; frame: ViewFrame)
proc build_graph_tab(view: MainWindow)
proc apply_ui_actions(view: MainWindow)
proc build_tab_bar(view: MainWindow)

proc render*(view: MainWindow; renderer: Renderer; clay_context: ptr ClayContext;
    string_cache: var ClayStringCache; delta_time: float32): bool =
  view.update_debug_graph(delta_time)
  renderer.render_frame(
    clay_context,
    string_cache,
    proc() =
      view.ui_state.prepare_frame(
        proc(event: UiEvent) =
          if view.tab_manager.active_tab == main_tab_graph:
            view.graph_tab.graph_view.handle_event(event),
        delta_time)
      view.apply_ui_actions(),
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

proc select_tab(view: MainWindow; tab_kind: MainTabKind) =
  if view.tab_manager.active_tab == tab_kind:
    return
  view.graph_tab.graph_view.cancel_pan()
  view.ui_state.clear_focus()
  view.tab_manager.active_tab = tab_kind

proc apply_ui_actions(view: MainWindow) =
  var action: UiAction
  while view.ui_state.next_action(action):
    case action.kind
    of ui_action_button_clicked:
      case action.button_id
      of workspace_tab_button_id:
        view.select_tab(main_tab_workspace)
      of graph_tab_button_id:
        view.select_tab(main_tab_graph)
      else:
        discard
    of ui_action_text_field_submitted:
      if action.text_field_id != graph_conversation_input_id:
        continue
      let content = view.ui_state.text_field_value(graph_conversation_input_id)
      if content.strip.len == 0:
        continue
      view.graph_tab.conversation_messages.add(ConversationMessage(
        speaker: conversation_user,
        content: content))
      view.ui_state.clear_text_field(graph_conversation_input_id)

proc build_tab_bar(view: MainWindow) =
  let workspace_button_element_id = clay_id(workspace_tab_button_id)
  let graph_button_element_id = clay_id(graph_tab_button_id)
  view.ui_state.register_button(
    workspace_tab_button_id, workspace_button_element_id)
  view.ui_state.register_button(graph_tab_button_id, graph_button_element_id)

  element("tab_bar"):
    layout:
      sizing:
        width = grow()
        height = fixed(48)
      padding = padding_all(6)
      child_gap = 8
      layout_direction = clay_left_to_right
    clip:
      vertical = true
    background_color = palette_color(view.palette.paper)
    border:
      color = palette_color(view.palette.ink)
      width = border_outside(4)

    element(workspace_button_element_id):
      layout:
        sizing:
          width = fixed(142)
          height = grow()
        padding = padding_all(6)
        child_alignment:
          x = clay_align_x_center
          y = clay_align_y_center
      clip:
        vertical = true
      background_color = if view.tab_manager.active_tab == main_tab_workspace:
        palette_color(view.palette.pink)
      else:
        palette_color(view.palette.paper)
      border:
        color = palette_color(view.palette.ink)
        width = border_outside(3)
      text("WORKSPACE"):
        font_size = 10
        text_color = palette_color(view.palette.ink)
        wrap_mode = clay_text_wrap_words_and_graphemes

    element(graph_button_element_id):
      layout:
        sizing:
          width = fixed(142)
          height = grow()
        padding = padding_all(6)
        child_alignment:
          x = clay_align_x_center
          y = clay_align_y_center
      clip:
        vertical = true
      background_color = if view.tab_manager.active_tab == main_tab_graph:
        palette_color(view.palette.pink)
      else:
        palette_color(view.palette.paper)
      border:
        color = palette_color(view.palette.ink)
        width = border_outside(3)
      text("GRAPH"):
        font_size = 10
        text_color = palette_color(view.palette.ink)
        wrap_mode = clay_text_wrap_words_and_graphemes


proc build_workspace_tab(view: MainWindow; frame: ViewFrame) =
  let search_element_id = clay_id("search_field")
  view.ui_state.register_text_field(
    text_field_search,
    search_element_id,
    initial_value = "type here")

  inc view.workspace_tab.debug_cycle_frame
  let debug_phase = int((view.workspace_tab.debug_cycle_frame div 60'u64) mod 4'u64)
  if debug_phase != view.workspace_tab.debug_last_phase:
    echo "Clay transition debug: phase ", debug_phase,
      ", exiting transitions = ", frame.exiting_transitions
    view.workspace_tab.debug_last_phase = debug_phase
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

    build_tab_bar(view)

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
                text("PANEL B // " & $view.workspace_tab.debug_cycle_frame):
                  font_size = 10
                  text_color = palette_color(view.palette.ink)
                  wrap_mode = clay_text_wrap_words_and_graphemes
                text("DYNAMIC / STABLE POINTER"):
                  font_size = 8
                  text_color = palette_color(view.palette.ink)
                  wrap_mode = clay_text_wrap_words_and_graphemes
              if debug_show_panel_a:
                element("debug_panel_a", debug_panel_a_declaration):
                  text("PANEL A // " & $view.workspace_tab.debug_cycle_frame):
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
                  text("PANEL A // " & $view.workspace_tab.debug_cycle_frame):
                    font_size = 10
                    text_color = palette_color(view.palette.ink)
                    wrap_mode = clay_text_wrap_words_and_graphemes
                  text("EXIT / RE-ENTER TEST"):
                    font_size = 8
                    text_color = palette_color(view.palette.ink)
                    wrap_mode = clay_text_wrap_words_and_graphemes
              element("debug_panel_b", debug_panel_b_declaration):
                text("PANEL B // " & $view.workspace_tab.debug_cycle_frame):
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
            horizontal = true
            vertical = true
          background_color = palette_color(view.palette.paper)
          border:
            color = palette_color(view.palette.purple)
            width = border_outside(4)

          graph_window(view.workspace_tab.graph_view, node):
            discard

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

proc build_graph_conversation_panel(view: MainWindow) =
  let input_element_id = clay_id(graph_conversation_input_id)
  view.ui_state.register_text_field(
    graph_conversation_input_id, input_element_id)

  element("graph_conversation_content"):
    layout:
      sizing:
        width = grow()
        height = grow()
      padding = padding_all(12)
      child_gap = 10
      layout_direction = clay_top_to_bottom
    background_color = palette_color(view.palette.paper)

    text("NODE CONVERSATION"):
      font_size = 10
      text_color = palette_color(view.palette.ink)
      wrap_mode = clay_text_wrap_words_and_graphemes
    text("NODE " & $view.graph_tab.graph_view.selected_node_id):
      font_size = 8
      text_color = palette_color(view.palette.ink)
      wrap_mode = clay_text_wrap_words_and_graphemes

    let log_element_id = clay_id(graph_conversation_log_id)
    let log_declaration = declaration(
      layout = layout(
        sizing = sizing(grow(), grow()),
        padding = padding_all(8),
        child_gap = 8,
        layout_direction = clay_top_to_bottom),
      background_color = palette_color(view.palette.background),
      border = ClayBorderElementConfig(
        color: palette_color(view.palette.ink), width: border_outside(2)),
      clip = ClayClipElementConfig(vertical: true))
    scrollable_element(log_element_id, log_declaration):
      for message_index, message in view.graph_tab.conversation_messages:
        let is_user = message.speaker == conversation_user
        let row_id = clay_id_with_index(
          "graph_conversation_message", uint32(message_index))
        let row_declaration = declaration(
          layout = layout(
            sizing = sizing(grow(), fit()),
            child_alignment = child_alignment(
              if is_user:
                clay_align_x_right
              else:
                clay_align_x_left,
              clay_align_y_top)))
        let bubble_declaration = declaration(
          layout = layout(
            sizing = sizing(fit(0, 260), fit()),
            padding = padding_all(8)),
          background_color = if is_user:
            palette_color(view.palette.blue)
          else:
            palette_color(view.palette.yellow),
          border = ClayBorderElementConfig(
            color: palette_color(view.palette.ink), width: border_outside(2)))
        element(row_id, row_declaration):
          element(clay_id_with_index(
              "graph_conversation_bubble", uint32(message_index)),
              bubble_declaration):
            text(message.content):
              font_size = 10
              text_color = if is_user:
                palette_color(view.palette.paper)
              else:
                palette_color(view.palette.ink)
              wrap_mode = clay_text_wrap_words_and_graphemes

    element(graph_conversation_composer_id):
      layout:
        sizing:
          width = grow()
          height = fit(52, 156)
        padding = padding_all(8)
        child_gap = 5
        layout_direction = clay_top_to_bottom
      background_color = if view.ui_state.text_field_focused(
          graph_conversation_input_id):
        palette_color(view.palette.yellow)
      else:
        palette_color(view.palette.background)
      border:
        color = palette_color(view.palette.ink)
        width = border_outside(2)
      text("MESSAGE / ENTER TO SEND"):
        font_size = 8
        text_color = palette_color(view.palette.ink)
        wrap_mode = clay_text_wrap_words_and_graphemes

      let input_declaration = declaration(
        layout = layout(
          sizing = sizing(grow(), fit(20, 124)),
          padding = padding_all(4)),
        background_color = palette_color(view.palette.paper),
        clip = ClayClipElementConfig(vertical: true))
      scrollable_element(input_element_id, input_declaration):
        text(view.ui_state.text_field_display(graph_conversation_input_id)):
          font_size = 11
          text_color = palette_color(view.palette.ink)
          wrap_mode = clay_text_wrap_words_and_graphemes

proc build_graph_tab(view: MainWindow) =
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

    build_tab_bar(view)

    element("graph_section"):
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

      text("GRAPH / RANDOM LIVE / MUT " & $view.graph_tab.mutation_count):
        font_size = 13
        text_color = palette_color(view.palette.paper)
        wrap_mode = clay_text_wrap_words_and_graphemes

      element("graph_stage"):
        layout:
          sizing:
            width = grow()
            height = grow()
        clip:
          horizontal = true
          vertical = true
        background_color = palette_color(view.palette.paper)
        border:
          color = palette_color(view.palette.purple)
          width = border_outside(4)

        graph_window_with_panel(
            view.graph_tab.graph_view, node,
            view.build_graph_conversation_panel()):
          discard
        if not view.graph_tab.graph_view.selected_node_valid and
            view.ui_state.text_field_focused(graph_conversation_input_id):
          view.ui_state.clear_focus()

proc build_elements*(view: MainWindow; frame: ViewFrame) =
  case view.tab_manager.active_tab
  of main_tab_workspace:
    view.build_workspace_tab(frame)
  of main_tab_graph:
    view.build_graph_tab()
