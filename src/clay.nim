## Idiomatic Nim binding for Clay 0.14.
##
## Clay remains a single-header C library. Its implementation is emitted once
## here; all public data is represented directly in Nim, preserving Clay's C
## layout, arena ownership, pointer semantics, and command unions.

import std/macros

{.passC: "-Isrc".}
{.emit: """
#define CLAY_IMPLEMENTATION
#include "clay.h"

bool clay_nim_has_exiting_transitions(void) {
    Clay_Context *context = Clay_GetCurrentContext();
    if (context == NULL) {
        return false;
    }
    for (int32_t i = 0; i < context->transitionDatas.length; ++i) {
        Clay__TransitionDataInternal *data =
            Clay__TransitionDataInternalArray_Get(&context->transitionDatas, i);
        if (data->state == CLAY_TRANSITION_STATE_EXITING) {
            return true;
        }
    }
    return false;
}
""".}

type
  ClayString* {.importc: "Clay_String", header: "clay.h".} = object
    is_statically_allocated* {.importc: "isStaticallyAllocated".}: bool
    length*: int32
    chars*: cstring

  ClayStringSlice* {.importc: "Clay_StringSlice", header: "clay.h".} = object
    length*: int32
    chars*: cstring
    base_chars* {.importc: "baseChars".}: cstring

  ClayContext* {.importc: "Clay_Context", incompleteStruct, header: "clay.h".} = object

  ClayArena* {.importc: "Clay_Arena", header: "clay.h".} = object
    next_allocation* {.importc: "nextAllocation".}: uint
    capacity*: csize_t
    memory*: pointer

  ClayStringGeneration = object
    strings: seq[string]
    frame_number: uint64

  ClayStringCache* = object
    generations: seq[ClayStringGeneration]
    next_frame_number: uint64
    last_exiting_transitions: bool

  ClayDimensions* {.importc: "Clay_Dimensions", header: "clay.h".} = object
    width*: cfloat
    height*: cfloat

  ClayVector2* {.importc: "Clay_Vector2", header: "clay.h".} = object
    x*: cfloat
    y*: cfloat

  ClayColor* {.importc: "Clay_Color", header: "clay.h".} = object
    r*: cfloat
    g*: cfloat
    b*: cfloat
    a*: cfloat

  ClayBoundingBox* {.importc: "Clay_BoundingBox", header: "clay.h".} = object
    x*: cfloat
    y*: cfloat
    width*: cfloat
    height*: cfloat

  ClayElementId* {.importc: "Clay_ElementId", header: "clay.h".} = object
    id*: uint32
    offset*: uint32
    base_id* {.importc: "baseId".}: uint32
    string_id* {.importc: "stringId".}: ClayString

  ClayElementIdArray* {.importc: "Clay_ElementIdArray", header: "clay.h".} = object
    capacity*: int32
    length*: int32
    internal_array* {.importc: "internalArray".}: ptr ClayElementId

  ClayCornerRadius* {.importc: "Clay_CornerRadius", header: "clay.h".} = object
    top_left* {.importc: "topLeft".}: cfloat
    top_right* {.importc: "topRight".}: cfloat
    bottom_left* {.importc: "bottomLeft".}: cfloat
    bottom_right* {.importc: "bottomRight".}: cfloat

  # Packed C enums are one byte in clay.h. Regular C enums below are four bytes.
  ClayLayoutDirection* = uint8
  ClayLayoutAlignmentX* = uint8
  ClayLayoutAlignmentY* = uint8
  ClaySizingType* = uint8
  ClayTextElementConfigWrapMode* = uint8
  ClayTextAlignment* = uint8
  ClayFloatingAttachPointType* = uint8
  ClayPointerCaptureMode* = uint8
  ClayFloatingAttachToElement* = uint8
  ClayFloatingClipToElement* = uint8
  ClayTransitionEnterTriggerType* = uint8
  ClayTransitionExitTriggerType* = uint8
  ClayTransitionInteractionHandlingType* = uint8
  ClayExitTransitionSiblingOrdering* = uint8
  ClayRenderCommandType* = uint8
  ClayPointerDataInteractionState* = uint8
  ClayErrorType* = uint8

  ClayTransitionState* = cint
  ClayTransitionProperty* {.importc: "Clay_TransitionProperty", header: "clay.h".} = distinct cint

  ClayChildAlignment* {.importc: "Clay_ChildAlignment", header: "clay.h".} = object
    x*: ClayLayoutAlignmentX
    y*: ClayLayoutAlignmentY

  ClaySizingMinMax* {.importc: "Clay_SizingMinMax", header: "clay.h".} = object
    min*: cfloat
    max*: cfloat

  ClaySizingAxisSize* {.union.} = object
    min_max* {.importc: "minMax".}: ClaySizingMinMax
    percent*: cfloat

  ClaySizingAxis* {.importc: "Clay_SizingAxis", header: "clay.h".} = object
    size*: ClaySizingAxisSize
    kind* {.importc: "type".}: ClaySizingType

  ClaySizing* {.importc: "Clay_Sizing", header: "clay.h".} = object
    width*: ClaySizingAxis
    height*: ClaySizingAxis

  ClayPadding* {.importc: "Clay_Padding", header: "clay.h".} = object
    left*: uint16
    right*: uint16
    top*: uint16
    bottom*: uint16

  ClayLayoutConfig* {.importc: "Clay_LayoutConfig", header: "clay.h".} = object
    sizing*: ClaySizing
    padding*: ClayPadding
    child_gap* {.importc: "childGap".}: uint16
    child_alignment* {.importc: "childAlignment".}: ClayChildAlignment
    layout_direction* {.importc: "layoutDirection".}: ClayLayoutDirection

  ClayTextElementConfig* {.importc: "Clay_TextElementConfig", header: "clay.h".} = object
    user_data* {.importc: "userData".}: pointer
    text_color* {.importc: "textColor".}: ClayColor
    font_id* {.importc: "fontId".}: uint16
    font_size* {.importc: "fontSize".}: uint16
    letter_spacing* {.importc: "letterSpacing".}: uint16
    line_height* {.importc: "lineHeight".}: uint16
    wrap_mode* {.importc: "wrapMode".}: ClayTextElementConfigWrapMode
    text_alignment* {.importc: "textAlignment".}: ClayTextAlignment

  ClayAspectRatioElementConfig* {.importc: "Clay_AspectRatioElementConfig", header: "clay.h".} = object
    aspect_ratio* {.importc: "aspectRatio".}: cfloat

  ClayImageElementConfig* {.importc: "Clay_ImageElementConfig", header: "clay.h".} = object
    image_data* {.importc: "imageData".}: pointer

  ClayFloatingAttachPoints* {.importc: "Clay_FloatingAttachPoints", header: "clay.h".} = object
    element*: ClayFloatingAttachPointType
    parent*: ClayFloatingAttachPointType

  ClayFloatingElementConfig* {.importc: "Clay_FloatingElementConfig", header: "clay.h".} = object
    offset*: ClayVector2
    expand*: ClayDimensions
    parent_id* {.importc: "parentId".}: uint32
    z_index* {.importc: "zIndex".}: int16
    attach_points* {.importc: "attachPoints".}: ClayFloatingAttachPoints
    pointer_capture_mode* {.importc: "pointerCaptureMode".}: ClayPointerCaptureMode
    attach_to* {.importc: "attachTo".}: ClayFloatingAttachToElement
    clip_to* {.importc: "clipTo".}: ClayFloatingClipToElement

  ClayCustomElementConfig* {.importc: "Clay_CustomElementConfig", header: "clay.h".} = object
    custom_data* {.importc: "customData".}: pointer

  ClayClipElementConfig* {.importc: "Clay_ClipElementConfig", header: "clay.h".} = object
    horizontal*: bool
    vertical*: bool
    child_offset* {.importc: "childOffset".}: ClayVector2

  ClayBorderWidth* {.importc: "Clay_BorderWidth", header: "clay.h".} = object
    left*: uint16
    right*: uint16
    top*: uint16
    bottom*: uint16
    between_children* {.importc: "betweenChildren".}: uint16

  ClayBorderElementConfig* {.importc: "Clay_BorderElementConfig", header: "clay.h".} = object
    color*: ClayColor
    width*: ClayBorderWidth

  ClayTransitionData* {.importc: "Clay_TransitionData", header: "clay.h".} = object
    bounding_box* {.importc: "boundingBox".}: ClayBoundingBox
    background_color* {.importc: "backgroundColor".}: ClayColor
    overlay_color* {.importc: "overlayColor".}: ClayColor
    border_color* {.importc: "borderColor".}: ClayColor
    border_width* {.importc: "borderWidth".}: ClayBorderWidth

  ClayTransitionCallbackArguments* {.importc: "Clay_TransitionCallbackArguments", header: "clay.h".} = object
    transition_state* {.importc: "transitionState".}: ClayTransitionState
    initial*: ClayTransitionData
    current*: ptr ClayTransitionData
    target*: ClayTransitionData
    elapsed_time* {.importc: "elapsedTime".}: cfloat
    duration*: cfloat
    properties*: ClayTransitionProperty

  ClayTransitionHandlerProc* = proc(arguments: ClayTransitionCallbackArguments): bool {.cdecl.}
  ClayTransitionSetInitialStateProc* = proc(target_state: ClayTransitionData;
      properties: ClayTransitionProperty): ClayTransitionData {.cdecl.}
  ClayTransitionSetFinalStateProc* = proc(initial_state: ClayTransitionData;
      properties: ClayTransitionProperty): ClayTransitionData {.cdecl.}

  ClayTransitionEnter* {.importc: "", header: "clay.h".} = object
    set_initial_state* {.importc: "setInitialState".}: ClayTransitionSetInitialStateProc
    trigger*: ClayTransitionEnterTriggerType

  ClayTransitionExit* {.importc: "", header: "clay.h".} = object
    set_final_state* {.importc: "setFinalState".}: ClayTransitionSetFinalStateProc
    trigger*: ClayTransitionExitTriggerType
    sibling_ordering* {.importc: "siblingOrdering".}: ClayExitTransitionSiblingOrdering

  ClayTransitionElementConfig* {.importc: "Clay_TransitionElementConfig", header: "clay.h".} = object
    handler*: ClayTransitionHandlerProc
    duration*: cfloat
    properties*: ClayTransitionProperty
    interaction_handling* {.importc: "interactionHandling".}: ClayTransitionInteractionHandlingType
    enter*: ClayTransitionEnter
    exit*: ClayTransitionExit

  ClayElementDeclaration* {.importc: "Clay_ElementDeclaration", header: "clay.h".} = object
    layout*: ClayLayoutConfig
    background_color* {.importc: "backgroundColor".}: ClayColor
    overlay_color* {.importc: "overlayColor".}: ClayColor
    corner_radius* {.importc: "cornerRadius".}: ClayCornerRadius
    aspect_ratio* {.importc: "aspectRatio".}: ClayAspectRatioElementConfig
    image*: ClayImageElementConfig
    floating*: ClayFloatingElementConfig
    custom*: ClayCustomElementConfig
    clip*: ClayClipElementConfig
    border*: ClayBorderElementConfig
    transition*: ClayTransitionElementConfig
    user_data* {.importc: "userData".}: pointer

  ClayTextRenderData* {.importc: "Clay_TextRenderData", header: "clay.h".} = object
    string_contents* {.importc: "stringContents".}: ClayStringSlice
    text_color* {.importc: "textColor".}: ClayColor
    font_id* {.importc: "fontId".}: uint16
    font_size* {.importc: "fontSize".}: uint16
    letter_spacing* {.importc: "letterSpacing".}: uint16
    line_height* {.importc: "lineHeight".}: uint16

  ClayRectangleRenderData* {.importc: "Clay_RectangleRenderData", header: "clay.h".} = object
    background_color* {.importc: "backgroundColor".}: ClayColor
    corner_radius* {.importc: "cornerRadius".}: ClayCornerRadius

  ClayImageRenderData* {.importc: "Clay_ImageRenderData", header: "clay.h".} = object
    background_color* {.importc: "backgroundColor".}: ClayColor
    corner_radius* {.importc: "cornerRadius".}: ClayCornerRadius
    image_data* {.importc: "imageData".}: pointer

  ClayCustomRenderData* {.importc: "Clay_CustomRenderData", header: "clay.h".} = object
    background_color* {.importc: "backgroundColor".}: ClayColor
    corner_radius* {.importc: "cornerRadius".}: ClayCornerRadius
    custom_data* {.importc: "customData".}: pointer

  ClayClipRenderData* {.importc: "Clay_ClipRenderData", header: "clay.h".} = object
    horizontal*: bool
    vertical*: bool

  ClayOverlayColorRenderData* {.importc: "Clay_OverlayColorRenderData", header: "clay.h".} = object
    color*: ClayColor

  ClayBorderRenderData* {.importc: "Clay_BorderRenderData", header: "clay.h".} = object
    color*: ClayColor
    corner_radius* {.importc: "cornerRadius".}: ClayCornerRadius
    width*: ClayBorderWidth

  ClayRenderData* {.importc: "Clay_RenderData", union, header: "clay.h".} = object
    rectangle*: ClayRectangleRenderData
    text*: ClayTextRenderData
    image*: ClayImageRenderData
    custom*: ClayCustomRenderData
    border*: ClayBorderRenderData
    clip*: ClayClipRenderData
    overlay_color* {.importc: "overlayColor".}: ClayOverlayColorRenderData

  ClayRenderCommand* {.importc: "Clay_RenderCommand", header: "clay.h".} = object
    bounding_box* {.importc: "boundingBox".}: ClayBoundingBox
    render_data* {.importc: "renderData".}: ClayRenderData
    user_data* {.importc: "userData".}: pointer
    id*: uint32
    z_index* {.importc: "zIndex".}: int16
    command_type* {.importc: "commandType".}: ClayRenderCommandType

  ClayRenderCommandArray* {.importc: "Clay_RenderCommandArray", header: "clay.h".} = object
    capacity*: int32
    length*: int32
    internal_array* {.importc: "internalArray".}: ptr ClayRenderCommand

  ClayPointerData* {.importc: "Clay_PointerData", header: "clay.h".} = object
    position*: ClayVector2
    state*: ClayPointerDataInteractionState

  ClayScrollContainerData* {.importc: "Clay_ScrollContainerData", header: "clay.h".} = object
    scroll_position* {.importc: "scrollPosition".}: ptr ClayVector2
    scroll_container_dimensions* {.importc: "scrollContainerDimensions".}: ClayDimensions
    content_dimensions* {.importc: "contentDimensions".}: ClayDimensions
    config*: ClayClipElementConfig
    found*: bool

  ClayElementData* {.importc: "Clay_ElementData", header: "clay.h".} = object
    bounding_box* {.importc: "boundingBox".}: ClayBoundingBox
    found*: bool

  ClayErrorData* {.importc: "Clay_ErrorData", header: "clay.h".} = object
    error_type* {.importc: "errorType".}: ClayErrorType
    error_text* {.importc: "errorText".}: ClayString
    user_data* {.importc: "userData".}: pointer

  ClayErrorHandlerProc* = proc(error_data: ClayErrorData) {.cdecl.}
  ClayMeasureTextProc* = proc(text: ClayStringSlice; config: ptr ClayTextElementConfig;
      user_data: pointer): ClayDimensions {.cdecl.}
  ClayQueryScrollOffsetProc* = proc(element_id: uint32; user_data: pointer): ClayVector2 {.cdecl.}
  ClayHoverProc* = proc(element_id: ClayElementId; pointer_data: ClayPointerData;
      user_data: pointer) {.cdecl.}

  ClayErrorHandler* {.importc: "Clay_ErrorHandler", header: "clay.h".} = object
    error_handler_function* {.importc: "errorHandlerFunction".}: ClayErrorHandlerProc
    user_data* {.importc: "userData".}: pointer

static:
  doAssert sizeof(ClayLayoutDirection) == 1
  doAssert sizeof(ClayRenderCommandType) == 1
  doAssert sizeof(ClayErrorType) == 1
  doAssert sizeof(ClayTransitionState) == sizeof(cint)
  doAssert sizeof(ClayTransitionProperty) == sizeof(cint)

const
  clay_left_to_right* = ClayLayoutDirection(0)
  clay_top_to_bottom* = ClayLayoutDirection(1)

  clay_align_x_left* = ClayLayoutAlignmentX(0)
  clay_align_x_right* = ClayLayoutAlignmentX(1)
  clay_align_x_center* = ClayLayoutAlignmentX(2)

  clay_align_y_top* = ClayLayoutAlignmentY(0)
  clay_align_y_bottom* = ClayLayoutAlignmentY(1)
  clay_align_y_center* = ClayLayoutAlignmentY(2)

  clay_sizing_type_fit* = ClaySizingType(0)
  clay_sizing_type_grow* = ClaySizingType(1)
  clay_sizing_type_percent* = ClaySizingType(2)
  clay_sizing_type_fixed* = ClaySizingType(3)

  clay_text_wrap_words* = ClayTextElementConfigWrapMode(0)
  clay_text_wrap_newlines* = ClayTextElementConfigWrapMode(1)
  clay_text_wrap_none* = ClayTextElementConfigWrapMode(2)

  clay_text_align_left* = ClayTextAlignment(0)
  clay_text_align_center* = ClayTextAlignment(1)
  clay_text_align_right* = ClayTextAlignment(2)

  clay_attach_point_left_top* = ClayFloatingAttachPointType(0)
  clay_attach_point_left_center* = ClayFloatingAttachPointType(1)
  clay_attach_point_left_bottom* = ClayFloatingAttachPointType(2)
  clay_attach_point_center_top* = ClayFloatingAttachPointType(3)
  clay_attach_point_center_center* = ClayFloatingAttachPointType(4)
  clay_attach_point_center_bottom* = ClayFloatingAttachPointType(5)
  clay_attach_point_right_top* = ClayFloatingAttachPointType(6)
  clay_attach_point_right_center* = ClayFloatingAttachPointType(7)
  clay_attach_point_right_bottom* = ClayFloatingAttachPointType(8)

  clay_pointer_capture_mode_capture* = ClayPointerCaptureMode(0)
  clay_pointer_capture_mode_passthrough* = ClayPointerCaptureMode(1)

  clay_attach_to_none* = ClayFloatingAttachToElement(0)
  clay_attach_to_parent* = ClayFloatingAttachToElement(1)
  clay_attach_to_element_with_id* = ClayFloatingAttachToElement(2)
  clay_attach_to_root* = ClayFloatingAttachToElement(3)

  clay_clip_to_none* = ClayFloatingClipToElement(0)
  clay_clip_to_attached_parent* = ClayFloatingClipToElement(1)

  clay_transition_state_idle* = ClayTransitionState(0)
  clay_transition_state_entering* = ClayTransitionState(1)
  clay_transition_state_transitioning* = ClayTransitionState(2)
  clay_transition_state_exiting* = ClayTransitionState(3)

  clay_transition_property_none* = ClayTransitionProperty(0)
  clay_transition_property_x* = ClayTransitionProperty(1)
  clay_transition_property_y* = ClayTransitionProperty(2)
  clay_transition_property_position* = ClayTransitionProperty(3)
  clay_transition_property_width* = ClayTransitionProperty(4)
  clay_transition_property_height* = ClayTransitionProperty(8)
  clay_transition_property_dimensions* = ClayTransitionProperty(12)
  clay_transition_property_bounding_box* = ClayTransitionProperty(15)
  clay_transition_property_background_color* = ClayTransitionProperty(16)
  clay_transition_property_overlay_color* = ClayTransitionProperty(32)
  clay_transition_property_corner_radius* = ClayTransitionProperty(64)
  clay_transition_property_border_color* = ClayTransitionProperty(128)
  clay_transition_property_border_width* = ClayTransitionProperty(256)
  clay_transition_property_border* = ClayTransitionProperty(384)

  clay_transition_enter_skip_on_first_parent_frame* = ClayTransitionEnterTriggerType(0)
  clay_transition_enter_trigger_on_first_parent_frame* = ClayTransitionEnterTriggerType(1)
  clay_transition_exit_skip_when_parent_exits* = ClayTransitionExitTriggerType(0)
  clay_transition_exit_trigger_when_parent_exits* = ClayTransitionExitTriggerType(1)
  clay_transition_disable_interactions_while_transitioning_position* = ClayTransitionInteractionHandlingType(0)
  clay_transition_allow_interactions_while_transitioning_position* = ClayTransitionInteractionHandlingType(1)
  clay_exit_transition_ordering_underneath_siblings* = ClayExitTransitionSiblingOrdering(0)
  clay_exit_transition_ordering_natural_order* = ClayExitTransitionSiblingOrdering(1)
  clay_exit_transition_ordering_above_siblings* = ClayExitTransitionSiblingOrdering(2)

  clay_render_command_type_none* = ClayRenderCommandType(0)
  clay_render_command_type_rectangle* = ClayRenderCommandType(1)
  clay_render_command_type_border* = ClayRenderCommandType(2)
  clay_render_command_type_text* = ClayRenderCommandType(3)
  clay_render_command_type_image* = ClayRenderCommandType(4)
  clay_render_command_type_scissor_start* = ClayRenderCommandType(5)
  clay_render_command_type_scissor_end* = ClayRenderCommandType(6)
  clay_render_command_type_overlay_color_start* = ClayRenderCommandType(7)
  clay_render_command_type_overlay_color_end* = ClayRenderCommandType(8)
  clay_render_command_type_custom* = ClayRenderCommandType(9)

  clay_pointer_data_pressed_this_frame* = ClayPointerDataInteractionState(0)
  clay_pointer_data_pressed* = ClayPointerDataInteractionState(1)
  clay_pointer_data_released_this_frame* = ClayPointerDataInteractionState(2)
  clay_pointer_data_released* = ClayPointerDataInteractionState(3)

  clay_error_type_text_measurement_function_not_provided* = ClayErrorType(0)
  clay_error_type_arena_capacity_exceeded* = ClayErrorType(1)
  clay_error_type_elements_capacity_exceeded* = ClayErrorType(2)
  clay_error_type_text_measurement_capacity_exceeded* = ClayErrorType(3)
  clay_error_type_duplicate_id* = ClayErrorType(4)
  clay_error_type_floating_container_parent_not_found* = ClayErrorType(5)
  clay_error_type_percentage_over_1* = ClayErrorType(6)
  clay_error_type_internal_error* = ClayErrorType(7)
  clay_error_type_unbalanced_open_close* = ClayErrorType(8)
  clay_error_type_hash_map_capacity_exceeded* = ClayErrorType(9)

var clay_layout_default* {.importc: "CLAY_LAYOUT_DEFAULT", header: "clay.h".}: ClayLayoutConfig

proc clay_min_memory_size*(): uint32
  {.importc: "Clay_MinMemorySize", header: "clay.h".}
proc clay_create_arena_with_capacity_and_memory*(capacity: csize_t; memory: pointer): ClayArena
  {.importc: "Clay_CreateArenaWithCapacityAndMemory", header: "clay.h".}
proc clay_set_pointer_state*(position: ClayVector2; pointer_down: bool)
  {.importc: "Clay_SetPointerState", header: "clay.h".}
proc clay_get_pointer_state*(): ClayPointerData
  {.importc: "Clay_GetPointerState", header: "clay.h".}
proc clay_initialize*(arena: ClayArena; layout_dimensions: ClayDimensions;
    error_handler: ClayErrorHandler): ptr ClayContext
  {.importc: "Clay_Initialize", header: "clay.h".}
proc clay_get_current_context*(): ptr ClayContext
  {.importc: "Clay_GetCurrentContext", header: "clay.h".}
proc clay_set_current_context*(context: ptr ClayContext)
  {.importc: "Clay_SetCurrentContext", header: "clay.h".}
proc clay_update_scroll_containers*(enable_drag_scrolling: bool; scroll_delta: ClayVector2;
    delta_time: cfloat) {.importc: "Clay_UpdateScrollContainers", header: "clay.h".}
proc clay_get_scroll_offset*(): ClayVector2
  {.importc: "Clay_GetScrollOffset", header: "clay.h".}
proc clay_set_layout_dimensions*(dimensions: ClayDimensions)
  {.importc: "Clay_SetLayoutDimensions", header: "clay.h".}
proc clay_get_layout_dimensions*(): ClayDimensions
  {.importc: "Clay_GetLayoutDimensions", header: "clay.h".}
proc clay_begin_layout*() {.importc: "Clay_BeginLayout", header: "clay.h".}
proc clay_end_layout*(delta_time: cfloat): ClayRenderCommandArray
  {.importc: "Clay_EndLayout", header: "clay.h".}
proc clay_get_open_element_id*(): uint32
  {.importc: "Clay_GetOpenElementId", header: "clay.h".}
proc clay_get_element_id*(id_string: ClayString): ClayElementId
  {.importc: "Clay_GetElementId", header: "clay.h".}
proc clay_get_element_id_with_index*(id_string: ClayString; index: uint32): ClayElementId
  {.importc: "Clay_GetElementIdWithIndex", header: "clay.h".}
proc clay_hash_string*(key: ClayString; seed: uint32): ClayElementId
  {.importc: "Clay__HashString", header: "clay.h".}
proc clay_hash_string_with_offset*(key: ClayString; offset, seed: uint32): ClayElementId
  {.importc: "Clay__HashStringWithOffset", header: "clay.h".}
proc clay_get_element_data*(id: ClayElementId): ClayElementData
  {.importc: "Clay_GetElementData", header: "clay.h".}
proc clay_hovered*(): bool {.importc: "Clay_Hovered", header: "clay.h".}
proc clay_on_hover*(on_hover_function: ClayHoverProc; user_data: pointer)
  {.importc: "Clay_OnHover", header: "clay.h".}
proc clay_pointer_over*(id: ClayElementId): bool
  {.importc: "Clay_PointerOver", header: "clay.h".}
proc clay_get_pointer_over_ids*(): ClayElementIdArray
  {.importc: "Clay_GetPointerOverIds", header: "clay.h".}
proc clay_get_scroll_container_data*(id: ClayElementId): ClayScrollContainerData
  {.importc: "Clay_GetScrollContainerData", header: "clay.h".}
proc clay_set_measure_text_function*(measure_text_function: ClayMeasureTextProc; user_data: pointer)
  {.importc: "Clay_SetMeasureTextFunction", header: "clay.h".}
proc clay_set_query_scroll_offset_function*(query_scroll_offset_function: ClayQueryScrollOffsetProc;
    user_data: pointer) {.importc: "Clay_SetQueryScrollOffsetFunction", header: "clay.h".}
proc clay_render_command_array_get*(array: ptr ClayRenderCommandArray; index: int32): ptr ClayRenderCommand
  {.importc: "Clay_RenderCommandArray_Get", header: "clay.h".}
proc clay_set_debug_mode_enabled*(enabled: bool)
  {.importc: "Clay_SetDebugModeEnabled", header: "clay.h".}
proc clay_is_debug_mode_enabled*(): bool
  {.importc: "Clay_IsDebugModeEnabled", header: "clay.h".}
proc clay_set_culling_enabled*(enabled: bool)
  {.importc: "Clay_SetCullingEnabled", header: "clay.h".}
proc clay_get_max_element_count*(): int32
  {.importc: "Clay_GetMaxElementCount", header: "clay.h".}
proc clay_set_max_element_count*(max_element_count: int32)
  {.importc: "Clay_SetMaxElementCount", header: "clay.h".}
proc clay_get_max_measure_text_cache_word_count*(): int32
  {.importc: "Clay_GetMaxMeasureTextCacheWordCount", header: "clay.h".}
proc clay_set_max_measure_text_cache_word_count*(max_count: int32)
  {.importc: "Clay_SetMaxMeasureTextCacheWordCount", header: "clay.h".}
proc clay_reset_measure_text_cache*()
  {.importc: "Clay_ResetMeasureTextCache", header: "clay.h".}
proc clay_ease_out*(arguments: ClayTransitionCallbackArguments): bool
  {.cdecl, importc: "Clay_EaseOut", header: "clay.h".}

proc clay_has_exiting_transitions*(): bool
  {.importc: "clay_nim_has_exiting_transitions".}

# Internal functions used by the declarative macro layer. These are the
# functions wrapped by Clay's CLAY, CLAY_AUTO_ID, and CLAY_TEXT macros.
proc clay_open_element*() {.importc: "Clay__OpenElement", header: "clay.h".}
proc clay_open_element_with_id*(id: ClayElementId)
  {.importc: "Clay__OpenElementWithId", header: "clay.h".}
proc clay_configure_open_element*(declaration: ClayElementDeclaration)
  {.importc: "Clay__ConfigureOpenElement", header: "clay.h".}
proc clay_configure_open_element_ptr*(declaration: ptr ClayElementDeclaration)
  {.importc: "Clay__ConfigureOpenElementPtr", header: "clay.h".}
proc clay_close_element*() {.importc: "Clay__CloseElement", header: "clay.h".}
proc clay_open_text_element*(text: ClayString; config: ClayTextElementConfig)
  {.importc: "Clay__OpenTextElement", header: "clay.h".}

var clay_active_string_cache: ptr ClayStringCache

proc clay_string_cache_add_generation(cache: var ClayStringCache) {.inline.} =
  inc cache.next_frame_number
  cache.generations.add(ClayStringGeneration(frame_number: cache.next_frame_number))

proc clay_string_cache_retain_latest(cache: var ClayStringCache) =
  if cache.generations.len <= 1:
    return

  let retained_generation = cache.generations[^1]
  let reclaimed_count = cache.generations.len - 1
  cache.generations.setLen(1)
  cache.generations[0] = retained_generation
  if reclaimed_count > 1:
    echo "Clay string cache: reclaimed ", reclaimed_count, " generations"

proc clay_string_cache_begin*(cache: var ClayStringCache) =
  let has_exiting_transitions = clay_has_exiting_transitions()
  if has_exiting_transitions != cache.last_exiting_transitions:
    echo "Clay string cache: exiting transitions = ", has_exiting_transitions
    cache.last_exiting_transitions = has_exiting_transitions

  if not has_exiting_transitions:
    clay_string_cache_retain_latest(cache)
  clay_string_cache_add_generation(cache)
  clay_active_string_cache = addr cache

proc clay_string_cache_end*() {.inline.} =
  clay_active_string_cache = nil

proc clay_string_cache_deinit*(cache: var ClayStringCache) =
  if cache.generations.len > 0:
    echo "Clay string cache: reclaimed ", cache.generations.len, " generations at shutdown"
  cache.generations.setLen(0)
  cache.next_frame_number = 0
  cache.last_exiting_transitions = false
  if clay_active_string_cache == addr cache:
    clay_active_string_cache = nil

proc clay_string_cache_generation_count*(cache: ClayStringCache): int {.inline.} =
  cache.generations.len

proc clay_string_cache_current_generation*(cache: ClayStringCache): uint64 {.inline.} =
  if cache.generations.len == 0:
    0
  else:
    cache.generations[^1].frame_number

proc clay_string*(cache: var ClayStringCache; value: string): ClayString {.inline.} =
  if cache.generations.len == 0:
    clay_string_cache_add_generation(cache)
  cache.generations[^1].strings.add(value)
  let stored = addr cache.generations[^1].strings[^1]
  ClayString(is_statically_allocated: false, length: stored[].len.int32,
    chars: stored[].cstring)

proc clay_string*(cache: var ClayStringCache; value: cstring): ClayString {.inline.} =
  clay_string(cache, $value)

proc clay_string*(value: cstring): ClayString {.inline.} =
  if clay_active_string_cache != nil:
    return clay_string(clay_active_string_cache[], value)
  ClayString(is_statically_allocated: false, length: value.len.int32, chars: value)

proc clay_string*(value: ClayString): ClayString {.inline.} = value

proc clay_string*(value: string): ClayString {.inline.} =
  if clay_active_string_cache != nil:
    return clay_string(clay_active_string_cache[], value)
  ClayString(is_statically_allocated: false, length: value.len.int32, chars: value.cstring)

proc clay_string*(chars: cstring; length: SomeInteger;
    is_statically_allocated = false): ClayString {.inline.} =
  ClayString(is_statically_allocated: is_statically_allocated,
    length: int32(length), chars: chars)

template clay_string*(value: static[string]): ClayString =
  ClayString(is_statically_allocated: true, length: value.len.int32, chars: value.cstring)

proc clay_string_slice*(value: string): ClayStringSlice {.inline.} =
  if clay_active_string_cache != nil:
    let stored = clay_string(clay_active_string_cache[], value)
    return ClayStringSlice(length: stored.length, chars: stored.chars,
      base_chars: stored.chars)
  let chars = value.cstring
  ClayStringSlice(length: value.len.int32, chars: chars, base_chars: chars)

proc clay_string_slice*(chars: cstring; length: SomeInteger;
    base_chars: cstring = nil): ClayStringSlice {.inline.} =
  ClayStringSlice(length: int32(length), chars: chars,
    base_chars: if base_chars == nil: chars else: base_chars)

template clay_string_slice*(value: static[string]): ClayStringSlice =
  let chars = value.cstring
  ClayStringSlice(length: value.len.int32, chars: chars, base_chars: chars)

proc clay_id*(value: ClayString): ClayElementId {.inline.} = clay_get_element_id(value)
proc clay_id*(value: ClayElementId): ClayElementId {.inline.} = value
proc clay_id*(value: string): ClayElementId {.inline.} = clay_id(clay_string(value))
proc clay_id*(value: cstring): ClayElementId {.inline.} = clay_id(clay_string(value))
template clay_id*(value: static[string]): ClayElementId = clay_id(clay_string(value))

proc clay_id_with_index*(value: ClayString; index: uint32): ClayElementId {.inline.} =
  clay_get_element_id_with_index(value, index)
proc clay_id_with_index*(value: string; index: uint32): ClayElementId {.inline.} =
  clay_id_with_index(clay_string(value), index)
proc clay_id_with_index*(value: cstring; index: uint32): ClayElementId {.inline.} =
  clay_id_with_index(clay_string(value), index)
template clay_id_with_index*(value: static[string]; index: uint32): ClayElementId =
  clay_id_with_index(clay_string(value), index)

proc clay_id_local*(value: ClayString): ClayElementId {.inline.} =
  clay_hash_string(value, clay_get_open_element_id())

proc clay_id_with_index_local*(value: ClayString; index: uint32): ClayElementId {.inline.} =
  clay_hash_string_with_offset(value, index, clay_get_open_element_id())

proc clay_color*(r, g, b, a: SomeNumber): ClayColor {.inline.} =
  ClayColor(r: cfloat(r), g: cfloat(g), b: cfloat(b), a: cfloat(a))

proc clay_dimensions*(width, height: SomeNumber): ClayDimensions {.inline.} =
  ClayDimensions(width: cfloat(width), height: cfloat(height))

proc clay_vector2*(x, y: SomeNumber): ClayVector2 {.inline.} =
  ClayVector2(x: cfloat(x), y: cfloat(y))

proc clay_corner_radius*(radius: SomeNumber): ClayCornerRadius {.inline.} =
  ClayCornerRadius(top_left: cfloat(radius), top_right: cfloat(radius),
    bottom_left: cfloat(radius), bottom_right: cfloat(radius))

proc clay_padding*(left, right, top, bottom: SomeInteger): ClayPadding {.inline.} =
  ClayPadding(left: uint16(left), right: uint16(right), top: uint16(top), bottom: uint16(bottom))

proc clay_padding_all*(value: SomeInteger): ClayPadding {.inline.} =
  clay_padding(value, value, value, value)

proc clay_border_width*(left, right, top, bottom, between_children: SomeInteger): ClayBorderWidth {.inline.} =
  ClayBorderWidth(left: uint16(left), right: uint16(right), top: uint16(top),
    bottom: uint16(bottom), between_children: uint16(between_children))

proc clay_border_all*(value: SomeInteger): ClayBorderWidth {.inline.} =
  clay_border_width(value, value, value, value, value)

proc clay_border_outside*(value: SomeInteger): ClayBorderWidth {.inline.} =
  clay_border_width(value, value, value, value, 0)

proc clay_sizing_fit*(minimum, maximum: SomeNumber): ClaySizingAxis {.inline.} =
  ClaySizingAxis(size: ClaySizingAxisSize(min_max: ClaySizingMinMax(
    min: cfloat(minimum), max: cfloat(maximum))), kind: clay_sizing_type_fit)

proc clay_sizing_fit*(minimum: SomeNumber = 0): ClaySizingAxis {.inline.} =
  clay_sizing_fit(minimum, 0)

proc clay_sizing_grow*(minimum, maximum: SomeNumber): ClaySizingAxis {.inline.} =
  ClaySizingAxis(size: ClaySizingAxisSize(min_max: ClaySizingMinMax(
    min: cfloat(minimum), max: cfloat(maximum))), kind: clay_sizing_type_grow)

proc clay_sizing_grow*(minimum: SomeNumber = 0): ClaySizingAxis {.inline.} =
  clay_sizing_grow(minimum, 0)

proc clay_sizing_fixed*(value: SomeNumber): ClaySizingAxis {.inline.} =
  ClaySizingAxis(size: ClaySizingAxisSize(min_max: ClaySizingMinMax(
    min: cfloat(value), max: cfloat(value))), kind: clay_sizing_type_fixed)

proc clay_sizing_percent*(value: SomeNumber): ClaySizingAxis {.inline.} =
  ClaySizingAxis(size: ClaySizingAxisSize(percent: cfloat(value)), kind: clay_sizing_type_percent)

proc clay_sizing*(width, height: ClaySizingAxis): ClaySizing {.inline.} =
  ClaySizing(width: width, height: height)

proc clay_child_alignment*(x: ClayLayoutAlignmentX = clay_align_x_left;
    y: ClayLayoutAlignmentY = clay_align_y_top): ClayChildAlignment {.inline.} =
  ClayChildAlignment(x: x, y: y)

proc clay_layout*(sizing: ClaySizing = ClaySizing(); padding: ClayPadding = ClayPadding();
    child_gap: SomeInteger = 0; child_alignment: ClayChildAlignment = ClayChildAlignment();
    layout_direction: ClayLayoutDirection = clay_left_to_right): ClayLayoutConfig {.inline.} =
  ClayLayoutConfig(sizing: sizing, padding: padding, child_gap: uint16(child_gap),
    child_alignment: child_alignment, layout_direction: layout_direction)

proc clay_declaration*(layout: ClayLayoutConfig = ClayLayoutConfig();
    background_color: ClayColor = ClayColor(); overlay_color: ClayColor = ClayColor();
    corner_radius: ClayCornerRadius = ClayCornerRadius();
    aspect_ratio: ClayAspectRatioElementConfig = ClayAspectRatioElementConfig();
    image: ClayImageElementConfig = ClayImageElementConfig();
    floating: ClayFloatingElementConfig = ClayFloatingElementConfig();
    custom: ClayCustomElementConfig = ClayCustomElementConfig();
    clip: ClayClipElementConfig = ClayClipElementConfig();
    border: ClayBorderElementConfig = ClayBorderElementConfig();
    transition: ClayTransitionElementConfig = ClayTransitionElementConfig();
    user_data: pointer = nil): ClayElementDeclaration {.inline.} =
  ClayElementDeclaration(layout: layout, background_color: background_color,
    overlay_color: overlay_color, corner_radius: corner_radius,
    aspect_ratio: aspect_ratio, image: image, floating: floating, custom: custom,
    clip: clip, border: border, transition: transition, user_data: user_data)

proc clay_text_config*(text_color: ClayColor = ClayColor(); font_id: SomeInteger = 0;
    font_size: SomeInteger = 0; letter_spacing: SomeInteger = 0;
    line_height: SomeInteger = 0; wrap_mode: ClayTextElementConfigWrapMode = clay_text_wrap_words;
    text_alignment: ClayTextAlignment = clay_text_align_left; user_data: pointer = nil): ClayTextElementConfig {.inline.} =
  ClayTextElementConfig(user_data: user_data, text_color: text_color,
    font_id: uint16(font_id), font_size: uint16(font_size),
    letter_spacing: uint16(letter_spacing), line_height: uint16(line_height),
    wrap_mode: wrap_mode, text_alignment: text_alignment)

# Short names keep the declarative DSL readable when this module is imported
# unqualified. The clay_* forms remain available for collision-free code.
proc rgba*(r, g, b, a: SomeNumber): ClayColor {.inline.} = clay_color(r, g, b, a)
proc dimensions*(width, height: SomeNumber): ClayDimensions {.inline.} = clay_dimensions(width, height)
proc vector2*(x, y: SomeNumber): ClayVector2 {.inline.} = clay_vector2(x, y)
proc corner_radius*(radius: SomeNumber): ClayCornerRadius {.inline.} = clay_corner_radius(radius)
proc padding_all*(value: SomeInteger): ClayPadding {.inline.} = clay_padding_all(value)
proc border_all*(value: SomeInteger): ClayBorderWidth {.inline.} = clay_border_all(value)
proc border_outside*(value: SomeInteger): ClayBorderWidth {.inline.} = clay_border_outside(value)
proc fit*(): ClaySizingAxis {.inline.} = clay_sizing_fit()
proc fit*(minimum: SomeNumber): ClaySizingAxis {.inline.} = clay_sizing_fit(minimum)
proc fit*(minimum, maximum: SomeNumber): ClaySizingAxis {.inline.} = clay_sizing_fit(minimum, maximum)
proc grow*(): ClaySizingAxis {.inline.} = clay_sizing_grow()
proc grow*(minimum: SomeNumber): ClaySizingAxis {.inline.} = clay_sizing_grow(minimum)
proc grow*(minimum, maximum: SomeNumber): ClaySizingAxis {.inline.} = clay_sizing_grow(minimum, maximum)
proc fixed*(value: SomeNumber): ClaySizingAxis {.inline.} = clay_sizing_fixed(value)
proc percent*(value: SomeNumber): ClaySizingAxis {.inline.} = clay_sizing_percent(value)
proc sizing*(width, height: ClaySizingAxis): ClaySizing {.inline.} = clay_sizing(width, height)
proc child_alignment*(x: ClayLayoutAlignmentX = clay_align_x_left;
    y: ClayLayoutAlignmentY = clay_align_y_top): ClayChildAlignment {.inline.} =
  clay_child_alignment(x, y)
proc layout*(sizing: ClaySizing = ClaySizing(); padding: ClayPadding = ClayPadding();
    child_gap: SomeInteger = 0; child_alignment: ClayChildAlignment = ClayChildAlignment();
    layout_direction: ClayLayoutDirection = clay_left_to_right): ClayLayoutConfig {.inline.} =
  clay_layout(sizing, padding, child_gap, child_alignment, layout_direction)
proc declaration*(layout: ClayLayoutConfig = ClayLayoutConfig();
    background_color: ClayColor = ClayColor(); overlay_color: ClayColor = ClayColor();
    corner_radius: ClayCornerRadius = ClayCornerRadius();
    aspect_ratio: ClayAspectRatioElementConfig = ClayAspectRatioElementConfig();
    image: ClayImageElementConfig = ClayImageElementConfig();
    floating: ClayFloatingElementConfig = ClayFloatingElementConfig();
    custom: ClayCustomElementConfig = ClayCustomElementConfig();
    clip: ClayClipElementConfig = ClayClipElementConfig();
    border: ClayBorderElementConfig = ClayBorderElementConfig();
    transition: ClayTransitionElementConfig = ClayTransitionElementConfig();
    user_data: pointer = nil): ClayElementDeclaration {.inline.} =
  clay_declaration(layout, background_color, overlay_color, corner_radius,
    aspect_ratio, image, floating, custom, clip, border, transition, user_data)
proc text_config*(text_color: ClayColor = ClayColor(); font_id: SomeInteger = 0;
    font_size: SomeInteger = 0; letter_spacing: SomeInteger = 0;
    line_height: SomeInteger = 0; wrap_mode: ClayTextElementConfigWrapMode = clay_text_wrap_words;
    text_alignment: ClayTextAlignment = clay_text_align_left; user_data: pointer = nil): ClayTextElementConfig {.inline.} =
  clay_text_config(text_color, font_id, font_size, letter_spacing, line_height,
    wrap_mode, text_alignment, user_data)

proc clay_element_id_array_get*(array: ClayElementIdArray; index: int): var ClayElementId =
  cast[ptr UncheckedArray[ClayElementId]](array.internal_array)[index]

iterator items*(array: ClayElementIdArray): var ClayElementId =
  for index in 0 ..< array.length:
    yield cast[ptr UncheckedArray[ClayElementId]](array.internal_array)[index]

proc clay_render_command_array_get*(array: ClayRenderCommandArray; index: int): var ClayRenderCommand =
  cast[ptr UncheckedArray[ClayRenderCommand]](array.internal_array)[index]

iterator items*(array: ClayRenderCommandArray): var ClayRenderCommand =
  for index in 0 ..< array.length:
    yield cast[ptr UncheckedArray[ClayRenderCommand]](array.internal_array)[index]

template clay_element_scope*(id: ClayElementId; declaration: ClayElementDeclaration;
    body: untyped) =
  clay_open_element_with_id(id)
  clay_configure_open_element(declaration)
  try:
    body
  finally:
    clay_close_element()

template clay_text_scope*(text: ClayString; config: ClayTextElementConfig) =
  clay_open_text_element(text, config)

const
  clay_element_config_fields = [
    "layout", "background_color", "overlay_color", "corner_radius",
    "aspect_ratio", "image", "floating", "custom", "clip", "border",
    "transition", "user_data"]
  clay_layout_config_fields = [
    "sizing", "padding", "child_gap", "child_alignment", "layout_direction"]
  clay_sizing_fields = ["width", "height"]
  clay_child_alignment_fields = ["x", "y"]
  clay_text_config_fields = [
    "user_data", "text_color", "font_id", "font_size", "letter_spacing",
    "line_height", "wrap_mode", "text_alignment"]
  clay_aspect_ratio_fields = ["aspect_ratio"]
  clay_image_fields = ["image_data"]
  clay_floating_fields = [
    "offset", "expand", "parent_id", "z_index", "attach_points",
    "pointer_capture_mode", "attach_to", "clip_to"]
  clay_attach_points_fields = ["element", "parent"]
  clay_custom_fields = ["custom_data"]
  clay_clip_fields = ["horizontal", "vertical", "child_offset"]
  clay_border_element_fields = ["color", "width"]
  clay_border_width_fields = ["left", "right", "top", "bottom", "between_children"]
  clay_transition_fields = [
    "handler", "duration", "properties", "interaction_handling", "enter", "exit"]
  clay_transition_enter_fields = ["set_initial_state", "trigger"]
  clay_transition_exit_fields = ["set_final_state", "trigger", "sibling_ordering"]

proc clay_field_names(name: string): seq[string] {.compileTime.} =
  case name
  of "layout": @clay_layout_config_fields
  of "sizing": @clay_sizing_fields
  of "child_alignment": @clay_child_alignment_fields
  of "aspect_ratio": @clay_aspect_ratio_fields
  of "image": @clay_image_fields
  of "floating": @clay_floating_fields
  of "attach_points": @clay_attach_points_fields
  of "custom": @clay_custom_fields
  of "clip": @clay_clip_fields
  of "border": @clay_border_element_fields
  of "width": @clay_border_width_fields
  of "transition": @clay_transition_fields
  of "enter": @clay_transition_enter_fields
  of "exit": @clay_transition_exit_fields
  else: @[]

proc clay_dot_field(base, path: NimNode): NimNode {.compileTime.} =
  if path.kind == nnkIdent:
    return newDotExpr(base, path)
  if path.kind == nnkDotExpr:
    return newDotExpr(clay_dot_field(base, path[0]), path[1])
  error("Clay configuration field must be an identifier or dotted field", path)

proc clay_configure_node(body, base: NimNode; allowed: seq[string];
    strict: bool; assignments: var seq[NimNode]; remaining: var seq[NimNode]) {.compileTime.} =
  for statement in body:
    if statement.kind == nnkAsgn:
      let field_name = if statement[0].kind == nnkIdent:
        $statement[0]
      elif statement[0].kind == nnkDotExpr:
        $statement[0][0]
      else:
        error("Clay configuration assignment needs a field name", statement)
      if field_name notin allowed:
        error("Unknown Clay configuration field: " & field_name, statement[0])
      assignments.add(newTree(nnkAsgn, clay_dot_field(base, statement[0]), statement[1]))
    elif statement.kind == nnkCall and statement.len == 2 and
        statement[1].kind == nnkStmtList and statement[0].kind == nnkIdent and
        $statement[0] in allowed:
      let field_name = $statement[0]
      let nested_base = newDotExpr(base, statement[0])
      let nested_allowed = clay_field_names(field_name)
      if nested_allowed.len == 0:
        error("Clay field does not accept a configuration block: " & field_name, statement)
      clay_configure_node(statement[1], nested_base, nested_allowed, true,
        assignments, remaining)
    elif strict:
      error("Expected Clay configuration assignment, got " & $statement.kind, statement)
    else:
      remaining.add(statement)

macro element*(id: untyped; body: untyped): untyped =
  if body.kind != nnkStmtList:
    result = quote do:
      clay_element_scope(clay_id(`id`), `body`):
        discard
    return
  let declaration = gen_sym(nsk_var, "clay_declaration")
  var assignments: seq[NimNode] = @[]
  var children: seq[NimNode] = @[]
  clay_configure_node(body, declaration, @clay_element_config_fields,
    false, assignments, children)
  let child_body = newStmtList(children)
  var statements = newStmtList()
  statements.add(quote do:
    var `declaration`: ClayElementDeclaration)
  statements.add(quote do:
    `declaration` = ClayElementDeclaration())
  for assignment in assignments:
    statements.add(assignment)
  statements.add(quote do:
    clay_element_scope(clay_id(`id`), `declaration`):
      `child_body`)
  result = newTree(nnkBlockStmt, newEmptyNode(), statements)

macro element*(id: untyped; declaration: untyped; body: untyped): untyped =
  result = quote do:
    clay_element_scope(clay_id(`id`), `declaration`):
      `body`

macro element_auto*(body: untyped): untyped =
  if body.kind != nnkStmtList:
    result = quote do:
      clay_open_element()
      clay_configure_open_element(`body`)
      clay_close_element()
    return
  let declaration = gen_sym(nsk_var, "clay_declaration")
  var assignments: seq[NimNode] = @[]
  var children: seq[NimNode] = @[]
  clay_configure_node(body, declaration, @clay_element_config_fields,
    false, assignments, children)
  let child_body = newStmtList(children)
  var statements = newStmtList()
  statements.add(quote do:
    var `declaration`: ClayElementDeclaration)
  statements.add(quote do:
    `declaration` = ClayElementDeclaration())
  for assignment in assignments:
    statements.add(assignment)
  statements.add(quote do:
    clay_open_element()
    clay_configure_open_element(`declaration`)
    try:
      `child_body`
    finally:
      clay_close_element())
  result = newTree(nnkBlockStmt, newEmptyNode(), statements)

macro element_auto*(declaration: untyped; body: untyped): untyped =
  result = quote do:
    clay_open_element()
    clay_configure_open_element(`declaration`)
    try:
      `body`
    finally:
      clay_close_element()

macro text*(value: untyped; body: untyped): untyped =
  if body.kind != nnkStmtList:
    result = quote do:
      clay_text_scope(clay_string(`value`), `body`)
    return
  let config = gen_sym(nsk_var, "clay_text_config")
  var assignments: seq[NimNode] = @[]
  var ignored: seq[NimNode] = @[]
  clay_configure_node(body, config, @clay_text_config_fields,
    true, assignments, ignored)
  var statements = newStmtList()
  statements.add(quote do:
    var `config`: ClayTextElementConfig)
  statements.add(quote do:
    `config` = ClayTextElementConfig())
  for assignment in assignments:
    statements.add(assignment)
  statements.add(quote do:
    clay_text_scope(clay_string(`value`), `config`))
  result = newTree(nnkBlockStmt, newEmptyNode(), statements)

macro text*(value: untyped): untyped =
  result = quote do:
    clay_text_scope(clay_string(`value`), ClayTextElementConfig())

macro text*(value: untyped; config: untyped; body: untyped): untyped =
  result = quote do:
    clay_text_scope(clay_string(`value`), `config`)

macro clay_frame*(cache: untyped; delta_time: untyped; body: untyped): untyped =
  result = quote do:
    block:
      var clay_commands: ClayRenderCommandArray
      clay_string_cache_begin(`cache`)
      clay_begin_layout()
      try:
        `body`
      finally:
        clay_commands = clay_end_layout(`delta_time`)
        clay_string_cache_end()
      clay_commands

macro clay*(cache: untyped; delta_time: untyped; body: untyped): untyped =
  result = quote do:
    clay_frame(`cache`, `delta_time`):
      `body`

proc clay_id_local*(value: cstring): ClayElementId {.inline.} = clay_id_local(clay_string(value))
proc clay_id_local*(value: string): ClayElementId {.inline.} = clay_id_local(clay_string(value))
template clay_id_local*(value: static[string]): ClayElementId = clay_id_local(clay_string(value))
proc clay_id_with_index_local*(value: cstring; index: uint32): ClayElementId {.inline.} =
  clay_id_with_index_local(clay_string(value), index)
proc clay_id_with_index_local*(value: string; index: uint32): ClayElementId {.inline.} =
  clay_id_with_index_local(clay_string(value), index)
template clay_id_with_index_local*(value: static[string]; index: uint32): ClayElementId =
  clay_id_with_index_local(clay_string(value), index)
