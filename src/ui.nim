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
    ui_event_key_down
    ui_event_text_editing
    ui_event_text_input
    ui_event_window_focus_lost

  UiEvent* = object
    kind*: UiEventKind
    window_id*: uint32
    x*, y*: float32
    pointer_down*: bool
    key*: uint32
    modifiers*: uint16
    repeat*: bool
    text*: string
    composition_start*: int32
    composition_length*: int32

  UiActionKind* = enum
    ui_action_button_clicked

  UiAction* = object
    kind*: UiActionKind
    button_id*: ButtonId

  InteractiveField = object
    id: TextFieldId
    element_id: ClayElementId
    interaction_priority: int
    registration_order: int

  InteractiveButton = object
    id: ButtonId
    element_id: ClayElementId
    registration_order: int

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
    window: ptr SdlWindow
    text_input_active: bool

const
  text_field_search* = "search"

proc new_ui_state*(): UiState =
  new(result)
  result.text_fields = initTable[TextFieldId, TextFieldState]()
  result.event_queue = initDeque[UiEvent]()
  result.action_queue = initDeque[UiAction]()

proc set_window*(state: UiState; window: ptr SdlWindow) =
  state.window = window

proc enqueue_event*(state: UiState; event: UiEvent) =
  if event.kind != ui_event_none:
    state.event_queue.addLast(event)

proc text_field_state_pointer(state: UiState; id: TextFieldId): ptr TextFieldState =
  if not state.text_fields.hasKey(id):
    state.text_fields[id] = TextFieldState()
  addr state.text_fields[id]

proc register_text_field*(state: UiState; id: TextFieldId;
    element_id: ClayElementId; initial_value = ""; interaction_priority = 0) =
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
    registration_order: state.current_fields.len))

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

proc text_field_display*(state: UiState; id: TextFieldId): string =
  if not state.text_fields.hasKey(id):
    return ""
  let field = state.text_fields[id]
  if state.focused_field != id:
    return field.value

  let cursor = max(0, min(field.cursor, field.value.len))
  let prefix = if cursor > 0: field.value[0 ..< cursor] else: ""
  let suffix = if cursor < field.value.len: field.value[cursor ..< field.value.len] else: ""
  result = prefix & field.composition & "|" & suffix

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
    if mouse_event.button != sdl_button_left:
      return
    return UiEvent(
      kind: if kind == sdl_event_mouse_button_down:
        ui_event_mouse_button_down
      else:
        ui_event_mouse_button_up,
      window_id: mouse_event.window_id,
      x: float32(mouse_event.x),
      y: float32(mouse_event.y),
      pointer_down: mouse_event.down)

  if kind == sdl_event_key_down:
    let key_event = cast[ptr SdlKeyboardEvent](event)
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

proc modifier_set(modifiers, mask: uint16): bool =
  (modifiers and mask) != 0

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

proc delete_selection(field: var TextFieldState): bool =
  if field.cursor == field.selection_anchor:
    return false
  let left = min(field.cursor, field.selection_anchor)
  let right = max(field.cursor, field.selection_anchor)
  let prefix = if left > 0: field.value[0 ..< left] else: ""
  let suffix = if right < field.value.len: field.value[right ..< field.value.len] else: ""
  field.value = prefix & suffix
  field.cursor = left
  field.selection_anchor = left
  true

proc replace_selection(field: var TextFieldState; inserted: string) =
  let left = min(field.cursor, field.selection_anchor)
  let right = max(field.cursor, field.selection_anchor)
  let prefix = if left > 0: field.value[0 ..< left] else: ""
  let suffix = if right < field.value.len: field.value[right ..< field.value.len] else: ""
  field.value = prefix & inserted & suffix
  field.cursor = left + inserted.len
  field.selection_anchor = field.cursor
  field.composition.setLen(0)
  field.composition_start = 0
  field.composition_length = 0

proc set_focus(state: UiState; id: TextFieldId) =
  if state.focused_field == id:
    return

  if state.focused_field.len > 0:
    let old_field = state.text_field_state_pointer(state.focused_field)
    old_field[].composition.setLen(0)
    old_field[].composition_start = 0
    old_field[].composition_length = 0

  if state.text_input_active and state.window != nil:
    discard stop_text_input(state.window)
    state.text_input_active = false

  state.focused_field = id
  if id.len == 0:
    return

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
  let control = modifier_set(event.modifiers, sdl_kmod_ctrl) or
    modifier_set(event.modifiers, sdl_kmod_gui)
  let extend_selection = modifier_set(event.modifiers, sdl_kmod_shift)

  if control and event.key == sdl_key_a:
    field[].cursor = field[].value.len
    field[].selection_anchor = 0
    return

  if event.key == sdl_key_left:
    field[].cursor = previous_grapheme(field[].value, field[].cursor)
    if not extend_selection:
      field[].selection_anchor = field[].cursor
    return

  if event.key == sdl_key_right:
    field[].cursor = next_grapheme(field[].value, field[].cursor)
    if not extend_selection:
      field[].selection_anchor = field[].cursor
    return

  if event.key == sdl_key_home:
    field[].cursor = 0
    if not extend_selection:
      field[].selection_anchor = field[].cursor
    return

  if event.key == sdl_key_end:
    field[].cursor = field[].value.len
    if not extend_selection:
      field[].selection_anchor = field[].cursor
    return

  if event.key == sdl_key_backspace:
    if delete_selection(field[]):
      return
    let previous = previous_grapheme(field[].value, field[].cursor)
    if previous < field[].cursor:
      field[].value = field[].value[0 ..< previous] & field[].value[field[].cursor ..< field[].value.len]
      field[].cursor = previous
      field[].selection_anchor = previous
    return

  if event.key == sdl_key_delete:
    if delete_selection(field[]):
      return
    let next = next_grapheme(field[].value, field[].cursor)
    if next > field[].cursor:
      field[].value = field[].value[0 ..< field[].cursor] & field[].value[next ..< field[].value.len]
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
    state.pointer_down = true
    clay_set_pointer_state(state.pointer_position, true)
    state.pressed_button = state.button_target()
    set_focus(state, state.pointer_target())
  of ui_event_mouse_button_up:
    state.pointer_position = clay_vector2(event.x, event.y)
    state.pointer_down = false
    clay_set_pointer_state(state.pointer_position, false)
    let released_button = state.button_target()
    if state.pressed_button.len > 0 and state.pressed_button == released_button:
      state.action_queue.addLast(UiAction(
        kind: ui_action_button_clicked,
        button_id: state.pressed_button))
    state.pressed_button.setLen(0)
  of ui_event_key_down:
    handle_key_down(state, event)
  of ui_event_text_editing:
    if state.focused_field.len > 0:
      let field = state.text_field_state_pointer(state.focused_field)
      field[].composition = event.text
      field[].composition_start = event.composition_start
      field[].composition_length = event.composition_length
  of ui_event_text_input:
    if state.focused_field.len > 0:
      replace_selection(state.text_field_state_pointer(state.focused_field)[], event.text)
  of ui_event_window_focus_lost:
    set_focus(state, "")
    state.pressed_button.setLen(0)
  of ui_event_none:
    discard

proc prepare_frame*(state: UiState) =
  state.previous_fields = state.current_fields
  state.current_fields = @[]
  state.previous_buttons = state.current_buttons
  state.current_buttons = @[]
  while state.event_queue.len > 0:
    handle_event(state, state.event_queue.popFirst())

proc finish_frame*(state: UiState) =
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
    discard set_text_input_area(state.window, addr rect, 0)
    return
