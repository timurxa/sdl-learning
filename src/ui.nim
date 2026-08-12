import std/deques
import std/tables
import clay
import sdl
import utf8proc

type
  TextFieldId* = string
  ButtonId* = string

  TextFieldState* = object
    value*: string
    cursor*: int
    selection_anchor*: int
    composition*: string
    composition_start*: int32
    composition_length*: int32

  UiEventKind* = enum
    ui_event_none
    ui_event_mouse_move
    ui_event_mouse_button_down
    ui_event_mouse_button_up
    ui_event_mouse_wheel
    ui_event_mouse_leave
    ui_event_key_down
    ui_event_text_editing
    ui_event_text_input
    ui_event_window_focus_lost

  UiEvent* = object
    kind*: UiEventKind
    window_id*: uint32
    x*, y*: float32
    pointer_down*: bool
    button*: uint8
    wheel_y*: float32
    key*: uint32
    modifiers*: uint16
    repeat*: bool
    text*: string
    composition_start*: int32
    composition_length*: int32

  UiEventHandler* = proc(event: UiEvent) {.closure.}
  TextMeasureProc* = proc(text: string; font_size: uint16): ClayDimensions {.closure.}

  UiActionKind* = enum
    ui_action_button_clicked
    ui_action_text_field_submitted

  UiAction* = object
    kind*: UiActionKind
    button_id*: ButtonId
    text_field_id*: TextFieldId

  InteractiveField = object
    id: TextFieldId
    element_id: ClayElementId
    interaction_priority: int
    registration_order: int
    text_offset_x: float32
    text_offset_y: float32
    font_size: uint16

  InteractiveButton = object
    id: ButtonId
    element_id: ClayElementId
    registration_order: int

  TextLine = object
    start_index: int
    end_index: int

  VisibleText = object
    value: string
    boundaries: seq[int]
    raw_indices: seq[int]

  UiState* = ref object
    text_fields*: Table[TextFieldId, TextFieldState]
    focused_field*: TextFieldId
    event_queue: Deque[UiEvent]
    action_queue: Deque[UiAction]
    previous_fields: seq[InteractiveField]
    current_fields: seq[InteractiveField]
    previous_buttons: seq[InteractiveButton]
    current_buttons: seq[InteractiveButton]
    pressed_button: ButtonId
    pointer_position: ClayVector2
    pointer_down: bool
    scroll_delta_y: float32
    scroll_pointer: ClayVector2
    scroll_pointer_valid: bool
    window: ptr SdlWindow
    text_input_active: bool
    scroll_focused_field_to_end: bool
    text_measurement: TextMeasureProc

const
  text_field_search* = "search"

proc new_ui_state*(): UiState =
  new(result)
  result.text_fields = initTable[TextFieldId, TextFieldState]()
  result.event_queue = initDeque[UiEvent]()
  result.action_queue = initDeque[UiAction]()

proc set_window*(state: UiState; window: ptr SdlWindow) =
  state.window = window

proc set_text_measurement*(state: UiState; measure: TextMeasureProc) =
  state.text_measurement = measure

proc enqueue_event*(state: UiState; event: UiEvent) =
  if event.kind != ui_event_none:
    state.event_queue.addLast(event)

proc text_field_state_pointer(state: UiState; id: TextFieldId): ptr TextFieldState =
  if not state.text_fields.hasKey(id):
    state.text_fields[id] = TextFieldState()
  addr state.text_fields[id]

proc register_text_field*(state: UiState; id: TextFieldId;
    element_id: ClayElementId; initial_value = ""; interaction_priority = 0;
    text_offset_x = 0'f32; text_offset_y = 0'f32; font_size = 11'u16) =
  if id.len == 0:
    return
  if not state.text_fields.hasKey(id):
    state.text_fields[id] = TextFieldState(
      value: initial_value,
      cursor: initial_value.len,
      selection_anchor: initial_value.len)
  state.current_fields.add(InteractiveField(
    id: id,
    element_id: element_id,
    interaction_priority: interaction_priority,
    registration_order: state.current_fields.len,
    text_offset_x: text_offset_x,
    text_offset_y: text_offset_y,
    font_size: font_size))

proc register_button*(state: UiState; id: ButtonId; element_id: ClayElementId) =
  if id.len == 0:
    return
  state.current_buttons.add(InteractiveButton(
    id: id,
    element_id: element_id,
    registration_order: state.current_buttons.len))

proc next_action*(state: UiState; action: var UiAction): bool =
  if state.action_queue.len == 0:
    return false
  action = state.action_queue.popFirst()
  true

proc text_field_value*(state: UiState; id: TextFieldId): string =
  if state.text_fields.hasKey(id):
    state.text_fields[id].value
  else:
    ""

proc text_field_focused*(state: UiState; id: TextFieldId): bool =
  state.focused_field == id

proc clear_composition(field: var TextFieldState) =
  field.composition.setLen(0)
  field.composition_start = 0
  field.composition_length = 0

proc visible_text_for_field(field: TextFieldState): VisibleText

proc text_field_display*(state: UiState; id: TextFieldId): string =
  if not state.text_fields.hasKey(id):
    return ""
  let field = state.text_fields[id]
  if state.focused_field != id:
    return field.value
  result = visible_text_for_field(field).value

proc clear_text_field*(state: UiState; id: TextFieldId) =
  if not state.text_fields.hasKey(id):
    return
  let field = state.text_field_state_pointer(id)
  field[].value.setLen(0)
  field[].cursor = 0
  field[].selection_anchor = 0
  clear_composition(field[])
  for interactive_field in state.previous_fields:
    if interactive_field.id != id:
      continue
    let scroll_data = clay_get_scroll_container_data(interactive_field.element_id)
    if scroll_data.found and scroll_data.scroll_position != nil:
      scroll_data.scroll_position[].y = 0
    break
  if state.focused_field == id:
    state.scroll_focused_field_to_end = true

proc modifier_set(modifiers, mask: uint16): bool =
  (modifiers and mask) != 0

proc shortcut_modifier(modifiers: uint16): bool =
  modifier_set(modifiers, sdl_kmod_ctrl) or
    modifier_set(modifiers, sdl_kmod_gui)

proc copy_sdl_text(text: cstring): string =
  if text != nil:
    result = $text

proc to_ui_event*(event: ptr SdlEvent): UiEvent =
  if event == nil:
    return

  let kind = event[].kind
  if kind == sdl_event_mouse_motion:
    let mouse_event = cast[ptr SdlMouseMotionEvent](event)
    return UiEvent(
      kind: ui_event_mouse_move,
      window_id: mouse_event.window_id,
      x: float32(mouse_event.x),
      y: float32(mouse_event.y),
      pointer_down: (mouse_event.state and sdl_button_left_mask) != 0)

  if kind == sdl_event_mouse_button_down or kind == sdl_event_mouse_button_up:
    let mouse_event = cast[ptr SdlMouseButtonEvent](event)
    return UiEvent(
      kind: if kind == sdl_event_mouse_button_down:
        ui_event_mouse_button_down
      else:
        ui_event_mouse_button_up,
      window_id: mouse_event.window_id,
      x: float32(mouse_event.x),
      y: float32(mouse_event.y),
      pointer_down: mouse_event.down,
      button: mouse_event.button)

  if kind == sdl_event_mouse_wheel:
    let wheel_event = cast[ptr SdlMouseWheelEvent](event)
    return UiEvent(
      kind: ui_event_mouse_wheel,
      window_id: wheel_event.window_id,
      x: float32(wheel_event.mouse_x),
      y: float32(wheel_event.mouse_y),
      wheel_y: if wheel_event.direction == sdl_mousewheel_flipped:
        -float32(wheel_event.y)
      else:
        float32(wheel_event.y))

  if kind == sdl_event_window_mouse_leave:
    let window_event = cast[ptr SdlWindowEvent](event)
    return UiEvent(
      kind: ui_event_mouse_leave,
      window_id: window_event.window_id)

  if kind == sdl_event_key_down:
    let key_event = cast[ptr SdlKeyboardEvent](event)
    if not key_event.repeat and key_event.key == sdl_key_v and
        shortcut_modifier(key_event.modifiers):
      return UiEvent(
        kind: ui_event_text_input,
        window_id: key_event.window_id,
        text: clipboard_text())
    return UiEvent(
      kind: ui_event_key_down,
      window_id: key_event.window_id,
      key: key_event.key,
      modifiers: key_event.modifiers,
      repeat: key_event.repeat)

  if kind == sdl_event_text_editing:
    let editing_event = cast[ptr SdlTextEditingEvent](event)
    return UiEvent(
      kind: ui_event_text_editing,
      window_id: editing_event.window_id,
      composition_start: editing_event.start,
      composition_length: editing_event.length,
      text: copy_sdl_text(editing_event.text))

  if kind == sdl_event_text_input:
    let text_event = cast[ptr SdlTextInputEvent](event)
    return UiEvent(
      kind: ui_event_text_input,
      window_id: text_event.window_id,
      text: copy_sdl_text(text_event.text))

  if kind == sdl_event_window_focus_lost:
    let window_event = cast[ptr SdlWindowEvent](event)
    return UiEvent(
      kind: ui_event_window_focus_lost,
      window_id: window_event.window_id)

proc previous_grapheme(value: string; cursor: int): int =
  if cursor <= 0:
    return 0
  let text = clay_string_slice(value)
  var boundary = 0
  while boundary < cursor:
    let next_boundary = int(utf8proc_next_grapheme_boundary(
      text, int32(boundary), nil))
    if next_boundary >= cursor:
      return boundary
    if next_boundary <= boundary:
      return max(boundary - 1, 0)
    boundary = next_boundary
  boundary

proc next_grapheme(value: string; cursor: int): int =
  int(utf8proc_next_grapheme_boundary(
    clay_string_slice(value), int32(cursor), nil))

proc move_cursor(field: var TextFieldState; position: int;
    extend_selection: bool) =
  field.cursor = position
  if not extend_selection:
    field.selection_anchor = field.cursor

proc append_visible_segment(visible: var VisibleText; source: string;
    start, finish, raw_index: int; preserve_raw_indices: bool) =
  var boundary = start
  while boundary < finish:
    let next_boundary = next_grapheme(source, boundary)
    if next_boundary <= boundary:
      break
    visible.value.add(source[boundary ..< next_boundary])
    visible.boundaries.add(visible.value.len)
    visible.raw_indices.add(
      if preserve_raw_indices: next_boundary else: raw_index)
    boundary = next_boundary

proc visible_text_for_field(field: TextFieldState): VisibleText =
  let cursor = max(0, min(field.cursor, field.value.len))
  result.boundaries = @[0]
  result.raw_indices = @[0]
  append_visible_segment(
    result, field.value, 0, cursor, 0, true)
  append_visible_segment(
    result, field.composition, 0, field.composition.len,
    cursor, false)
  result.value.add("|")
  result.boundaries.add(result.value.len)
  result.raw_indices.add(cursor)
  append_visible_segment(
    result, field.value, cursor, field.value.len, 0, true)

proc raw_index_at_boundary(visible: VisibleText; boundary: int): int =
  for index, visible_boundary in visible.boundaries:
    if visible_boundary == boundary:
      return visible.raw_indices[index]
  visible.raw_indices[^1]

proc cursor_index_in_line(state: UiState; visible: VisibleText;
    line_start, line_end: int; pointer_x: float32; font_size: uint16): int =
  if pointer_x <= 0:
    return visible.raw_index_at_boundary(line_start)
  var boundary = line_start
  var previous_width = 0'f32
  while boundary < line_end:
    let next_boundary = next_grapheme(visible.value, boundary)
    if next_boundary <= boundary:
      return visible.raw_index_at_boundary(boundary)
    let prefix_width = state.text_measurement(
      visible.value[line_start ..< next_boundary], font_size).width
    if pointer_x < (previous_width + prefix_width) / 2'f32:
      return visible.raw_index_at_boundary(boundary)
    previous_width = prefix_width
    boundary = next_boundary
  visible.raw_index_at_boundary(line_end)

proc wrap_text_lines(state: UiState; value: string; max_width: float32;
    font_size: uint16): seq[TextLine] =
  if value.len == 0:
    return @[TextLine(start_index: 0, end_index: 0)]

  var line_start = 0
  var line_end = 0
  var line_width = 0'f32
  var boundary = 0
  while boundary < value.len:
    let next_boundary = next_grapheme(value, boundary)
    if next_boundary <= boundary:
      break
    if value[boundary] == '\n':
      result.add(TextLine(start_index: line_start, end_index: line_end))
      boundary = next_boundary
      line_start = boundary
      line_end = boundary
      line_width = 0
      continue

    let word_start = boundary
    var word_end = boundary
    while word_end < value.len and value[word_end] != ' ' and
        value[word_end] != '\n':
      let word_next = next_grapheme(value, word_end)
      if word_next <= word_end:
        break
      word_end = word_next
    let word_end_with_space = if word_end < value.len and
        value[word_end] == ' ': next_grapheme(value, word_end) else: word_end
    let word_width = state.text_measurement(
      value[word_start ..< word_end_with_space], font_size).width

    if line_width > 0 and line_width + word_width > max_width:
      result.add(TextLine(start_index: line_start, end_index: line_end))
      line_start = word_start
      line_end = word_start
      line_width = 0

    if word_width > max_width and line_width == 0 and word_end > word_start:
      var segment_start = word_start
      var segment_width = 0'f32
      var segment_boundary = word_start
      while segment_boundary < word_end:
        let segment_next = next_grapheme(value, segment_boundary)
        if segment_next <= segment_boundary:
          break
        var segment_candidate_width = state.text_measurement(
          value[segment_start ..< segment_next], font_size).width
        if segment_width > 0 and segment_candidate_width > max_width:
          result.add(TextLine(
            start_index: segment_start, end_index: segment_boundary))
          segment_start = segment_boundary
          segment_width = 0
          segment_candidate_width = state.text_measurement(
            value[segment_start ..< segment_next], font_size).width
        segment_width = segment_candidate_width
        segment_boundary = segment_next
      if segment_start < word_end:
        result.add(TextLine(start_index: segment_start, end_index: word_end))
      boundary = word_end_with_space
      line_start = boundary
      line_end = boundary
      line_width = 0
      continue

    line_width += word_width
    line_end = word_end
    boundary = word_end_with_space

  if line_start < value.len or line_end > line_start or result.len == 0 or
      value[^1] == '\n':
    result.add(TextLine(start_index: line_start, end_index: line_end))

proc cursor_index_for_pointer(state: UiState; field: TextFieldState;
    interactive_field: InteractiveField; pointer_x, pointer_y: float32): int =
  if state.text_measurement == nil:
    return field.cursor
  let data = clay_get_element_data(interactive_field.element_id)
  if not data.found:
    return field.cursor
  let local_x = pointer_x - float32(data.bounding_box.x) -
    interactive_field.text_offset_x
  var scroll_y = 0'f32
  let scroll_data = clay_get_scroll_container_data(interactive_field.element_id)
  if scroll_data.found and scroll_data.scroll_position != nil:
    scroll_y = scroll_data.scroll_position[].y
  let line_height = max(
    state.text_measurement("M", interactive_field.font_size).height,
    1'f32)
  let local_y = pointer_y - float32(data.bounding_box.y) -
    interactive_field.text_offset_y - scroll_y
  let target_line = max(0, int(local_y / line_height))
  let max_width = max(
    float32(data.bounding_box.width) - 2'f32 * interactive_field.text_offset_x,
    1'f32)
  let visible = visible_text_for_field(field)
  let lines = state.wrap_text_lines(
    visible.value, max_width, interactive_field.font_size)
  let line_index = min(target_line, lines.len - 1)
  let line = lines[line_index]
  state.cursor_index_in_line(
    visible, line.start_index, line.end_index, local_x,
    interactive_field.font_size)

proc set_cursor_from_pointer(state: UiState; id: TextFieldId;
    pointer_x, pointer_y: float32) =
  let field = state.text_field_state_pointer(id)
  for interactive_field in state.previous_fields:
    if interactive_field.id != id:
      continue
    move_cursor(field[], state.cursor_index_for_pointer(
      field[], interactive_field, pointer_x, pointer_y), false)
    clear_composition(field[])
    break

proc replace_range(field: var TextFieldState; range_left, range_right: int;
    inserted: string) =
  let left = min(range_left, range_right)
  let right = max(range_left, range_right)
  let prefix = if left > 0: field.value[0 ..< left] else: ""
  let suffix = if right < field.value.len: field.value[right ..< field.value.len] else: ""
  field.value = prefix & inserted & suffix
  field.cursor = left + inserted.len
  field.selection_anchor = field.cursor
  clear_composition(field)

proc delete_selection(field: var TextFieldState): bool =
  if field.cursor == field.selection_anchor:
    return false
  replace_range(field, field.cursor, field.selection_anchor, "")
  true

proc replace_selection(field: var TextFieldState; inserted: string) =
  replace_range(field, field.cursor, field.selection_anchor, inserted)

proc set_focus(state: UiState; id: TextFieldId) =
  if state.focused_field == id:
    return

  if state.focused_field.len > 0:
    let old_field = state.text_field_state_pointer(state.focused_field)
    clear_composition(old_field[])

  if state.text_input_active and state.window != nil:
    discard stop_text_input(state.window)
    state.text_input_active = false

  state.focused_field = id
  if id.len == 0:
    return

  state.scroll_focused_field_to_end = true

  let field = state.text_field_state_pointer(id)
  field[].cursor = max(0, min(field[].cursor, field[].value.len))
  field[].selection_anchor = field[].cursor
  if state.window != nil:
    state.text_input_active = start_text_input(state.window)

proc clear_focus*(state: UiState) =
  set_focus(state, "")

proc pointer_target(state: UiState): TextFieldId =
  var best_priority = low(int)
  var best_pointer_rank = high(int)
  var pointer_rank = 0
  for hovered_id in clay_get_pointer_over_ids():
    for field in state.previous_fields:
      if field.element_id.id != hovered_id.id:
        continue
      if field.interaction_priority > best_priority or
          (field.interaction_priority == best_priority and
            pointer_rank < best_pointer_rank):
        result = field.id
        best_priority = field.interaction_priority
        best_pointer_rank = pointer_rank
    inc pointer_rank

  if result.len == 0:
    var best_order = -1
    for field in state.previous_fields:
      if not clay_pointer_over(field.element_id):
        continue
      if field.interaction_priority > best_priority or
          (field.interaction_priority == best_priority and
            field.registration_order > best_order):
        result = field.id
        best_priority = field.interaction_priority
        best_order = field.registration_order

proc button_target(state: UiState): ButtonId =
  var best_order = -1
  for button in state.previous_buttons:
    if not clay_pointer_over(button.element_id):
      continue
    if button.registration_order > best_order:
      result = button.id
      best_order = button.registration_order

proc handle_key_down(state: UiState; event: UiEvent) =
  if state.focused_field.len == 0:
    return
  let field = state.text_field_state_pointer(state.focused_field)
  if (event.key == sdl_key_return or event.key == sdl_key_kp_enter) and
      not event.repeat:
    state.action_queue.addLast(UiAction(
      kind: ui_action_text_field_submitted,
      text_field_id: state.focused_field))
    return
  state.scroll_focused_field_to_end = true
  let control = shortcut_modifier(event.modifiers)
  let extend_selection = modifier_set(event.modifiers, sdl_kmod_shift)

  if control and event.key == sdl_key_a:
    move_cursor(field[], field[].value.len, true)
    field[].selection_anchor = 0
    return

  if event.key == sdl_key_left:
    move_cursor(field[], previous_grapheme(field[].value, field[].cursor),
      extend_selection)
    return

  if event.key == sdl_key_right:
    move_cursor(field[], next_grapheme(field[].value, field[].cursor),
      extend_selection)
    return

  if event.key == sdl_key_home:
    move_cursor(field[], 0, extend_selection)
    return

  if event.key == sdl_key_end:
    move_cursor(field[], field[].value.len, extend_selection)
    return

  if event.key == sdl_key_backspace:
    if delete_selection(field[]):
      return
    let previous = previous_grapheme(field[].value, field[].cursor)
    if previous < field[].cursor:
      replace_range(field[], previous, field[].cursor, "")
    return

  if event.key == sdl_key_delete:
    if delete_selection(field[]):
      return
    let next = next_grapheme(field[].value, field[].cursor)
    if next > field[].cursor:
      replace_range(field[], field[].cursor, next, "")
    return

  if event.key == sdl_key_escape:
    set_focus(state, "")

proc handle_event(state: UiState; event: UiEvent) =
  case event.kind
  of ui_event_mouse_move:
    state.pointer_position = clay_vector2(event.x, event.y)
    state.pointer_down = event.pointer_down
    clay_set_pointer_state(state.pointer_position, state.pointer_down)
  of ui_event_mouse_button_down:
    state.pointer_position = clay_vector2(event.x, event.y)
    if event.button == 0 or event.button == sdl_button_left:
      state.pointer_down = true
    clay_set_pointer_state(state.pointer_position, state.pointer_down)
    if event.button != 0 and event.button != sdl_button_left:
      return
    state.pressed_button = state.button_target()
    let target = state.pointer_target()
    set_focus(state, target)
    if target.len > 0:
      state.set_cursor_from_pointer(
        target, state.pointer_position.x, state.pointer_position.y)
  of ui_event_mouse_button_up:
    state.pointer_position = clay_vector2(event.x, event.y)
    if event.button == 0 or event.button == sdl_button_left:
      state.pointer_down = false
    clay_set_pointer_state(state.pointer_position, state.pointer_down)
    if event.button != 0 and event.button != sdl_button_left:
      return
    let released_button = state.button_target()
    if state.pressed_button.len > 0 and state.pressed_button == released_button:
      state.action_queue.addLast(UiAction(
        kind: ui_action_button_clicked,
        button_id: state.pressed_button))
    state.pressed_button.setLen(0)
  of ui_event_mouse_wheel:
    state.pointer_position = clay_vector2(event.x, event.y)
    clay_set_pointer_state(state.pointer_position, state.pointer_down)
    if not state.scroll_pointer_valid or
        state.scroll_pointer.x != state.pointer_position.x or
        state.scroll_pointer.y != state.pointer_position.y:
      state.scroll_delta_y = 0
    state.scroll_pointer = state.pointer_position
    state.scroll_pointer_valid = true
    state.scroll_delta_y -= event.wheel_y
  of ui_event_mouse_leave:
    discard
  of ui_event_key_down:
    handle_key_down(state, event)
  of ui_event_text_editing:
    state.scroll_focused_field_to_end = true
    if state.focused_field.len > 0:
      let field = state.text_field_state_pointer(state.focused_field)
      field[].composition = event.text
      field[].composition_start = event.composition_start
      field[].composition_length = event.composition_length
  of ui_event_text_input:
    state.scroll_focused_field_to_end = true
    if state.focused_field.len > 0 and event.text.len > 0:
      replace_selection(state.text_field_state_pointer(state.focused_field)[], event.text)
  of ui_event_window_focus_lost:
    set_focus(state, "")
    state.pressed_button.setLen(0)
  of ui_event_none:
    discard

proc prepare_frame*(state: UiState; event_handler: UiEventHandler = nil;
    delta_time: float32 = 0'f32) =
  state.previous_fields = state.current_fields
  state.current_fields = @[]
  state.previous_buttons = state.current_buttons
  state.current_buttons = @[]
  while state.event_queue.len > 0:
    let event = state.event_queue.popFirst()
    handle_event(state, event)
    if event_handler != nil:
      event_handler(event)
  clay_update_scroll_containers(
    false, clay_vector2(0'f32, state.scroll_delta_y), delta_time)
  state.scroll_delta_y = 0
  state.scroll_pointer_valid = false

proc finish_frame*(state: UiState) =
  if state.scroll_focused_field_to_end and state.focused_field.len > 0:
    for field in state.current_fields:
      if field.id != state.focused_field:
        continue
      let scroll_data = clay_get_scroll_container_data(field.element_id)
      if scroll_data.found and scroll_data.scroll_position != nil:
        let overflow = max(
          float32(scroll_data.content_dimensions.height) -
          float32(scroll_data.scroll_container_dimensions.height),
          0'f32)
        scroll_data.scroll_position[].y =
          if state.text_fields[state.focused_field].value.len == 0:
            0'f32
          else:
            -overflow
        state.scroll_focused_field_to_end = false
      break
  if state.window == nil or state.focused_field.len == 0:
    return
  for field in state.current_fields:
    if field.id != state.focused_field:
      continue
    let data = clay_get_element_data(field.element_id)
    if not data.found:
      return
    var rect = SdlRect(
      x: cint(data.bounding_box.x),
      y: cint(data.bounding_box.y),
      w: cint(data.bounding_box.width),
      h: cint(data.bounding_box.height))
    let text_field = state.text_fields[state.focused_field]
    let cursor = max(0, min(text_field.cursor, text_field.value.len))
    let prefix = if cursor > 0: text_field.value[0 ..< cursor] else: ""
    let text_width = if state.text_measurement == nil:
      0'f32
    else:
      state.text_measurement(
        prefix & text_field.composition, field.font_size).width
    let cursor_offset = cint(field.text_offset_x + text_width)
    discard set_text_input_area(state.window, addr rect, cursor_offset)
    return
