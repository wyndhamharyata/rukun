package platform

import "base:intrinsics"
import "core:strings"
import NS "core:sys/darwin/Foundation"
import "core:unicode/utf8"

// Keys go to a 1-point view per window. As first responder, the Metal view gets a 0 by 0 drawable.
@(objc_class = "ThorInputView", objc_superclass = NS.View, objc_implement)
Input_View :: struct {
	using _: NS.View,
}

_find_by_input_view :: proc "contextless" (view: ^Input_View) -> ^Native_Window {
	for window in _state.windows {
		if rawptr(window.input_view) == rawptr(view) && !window.is_closed do return window
	}

	return nil
}

@(objc_type = Input_View, objc_implement, objc_name = "acceptsFirstResponder")
Input_View_acceptsFirstResponder :: proc "c" (self: ^Input_View) -> NS.BOOL {
	window := _find_by_input_view(self)

	return NS.BOOL(window != nil && window.is_text_input)
}

// The input view is first responder while a text field has the keyboard, so AppKit asks it too.
@(objc_type = Input_View, objc_implement, objc_name = "accessibilityFocusedUIElement")
Input_View_accessibilityFocusedUIElement :: proc "c" (self: ^Input_View) -> ^NS.Object {
	return _to_focused_element(self)
}

@(objc_type = Input_View, objc_implement, objc_name = "keyDown", objc_selector = "keyDown:")
Input_View_keyDown :: proc "c" (self: ^Input_View, event: ^NS.Event) {
	object := cast(^NS.Object)event
	events := NS.Array.alloc()->initWithObjects(&object, 1)

	objc_send(nil, self, "interpretKeyEvents:", events)
	events->release()
}

_to_odin_text :: proc "c" (text: ^NS.Object, window: ^Native_Window) -> string {
	context = _state.odin_context
	plain := text

	if objc_send(NS.BOOL, text, "respondsToSelector:", intrinsics.objc_find_selector("string")) {
		plain = objc_send(^NS.Object, text, "string")
	}

	return strings.clone((cast(^NS.String)plain)->odinString(), _event_allocator(window))
}

@(objc_type = Input_View, objc_implement, objc_name = "insertTextPlain", objc_selector = "insertText:")
Input_View_insertTextPlain :: proc "c" (self: ^Input_View, text: ^NS.Object) {
	context = _state.odin_context
	window := _find_by_input_view(self)
	if window == nil do return

	window.marked_byte_count = 0
	append(&window.events, Text_Insert{_to_odin_text(text, window)})
	_request_frame_of(window)
}

@(objc_type = Input_View, objc_implement, objc_name = "insertText", objc_selector = "insertText:replacementRange:")
Input_View_insertText :: proc "c" (self: ^Input_View, text: ^NS.Object, replacement: NS.Range) {
	Input_View_insertTextPlain(self, text)
}

@(objc_type = Input_View, objc_implement, objc_name = "setMarkedText", objc_selector = "setMarkedText:selectedRange:replacementRange:")
Input_View_setMarkedText :: proc "c" (
	self: ^Input_View,
	text: ^NS.Object,
	selected, replacement: NS.Range,
) {
	context = _state.odin_context
	window := _find_by_input_view(self)
	if window == nil do return

	marked := _to_odin_text(text, window)
	window.marked_byte_count = len(marked)
	append(&window.events, Text_Marked{marked})
	_request_frame_of(window)
}

@(objc_type = Input_View, objc_implement, objc_name = "unmarkText")
Input_View_unmarkText :: proc "c" (self: ^Input_View) {
	context = _state.odin_context
	window := _find_by_input_view(self)
	if window == nil do return

	window.marked_byte_count = 0
	append(&window.events, Text_Marked{})
	_request_frame_of(window)
}

@(objc_type = Input_View, objc_implement, objc_name = "hasMarkedText")
Input_View_hasMarkedText :: proc "c" (self: ^Input_View) -> NS.BOOL {
	window := _find_by_input_view(self)

	return window != nil && window.marked_byte_count > 0
}

_NOT_FOUND :: NS.UInteger(max(int))

@(objc_type = Input_View, objc_implement, objc_name = "markedRange")
Input_View_markedRange :: proc "c" (self: ^Input_View) -> NS.Range {
	window := _find_by_input_view(self)
	if window == nil || window.marked_byte_count == 0 do return {_NOT_FOUND, 0}

	return {0, NS.UInteger(window.marked_byte_count)}
}

@(objc_type = Input_View, objc_implement, objc_name = "selectedRange")
Input_View_selectedRange :: proc "c" (self: ^Input_View) -> NS.Range {
	return {_NOT_FOUND, 0}
}

@(objc_type = Input_View, objc_implement, objc_name = "validAttributesForMarkedText")
Input_View_validAttributesForMarkedText :: proc "c" (self: ^Input_View) -> ^NS.Array {
	return objc_send(^NS.Array, NS.Array, "array")
}

@(objc_type = Input_View, objc_implement, objc_name = "attributedSubstringForProposedRange", objc_selector = "attributedSubstringForProposedRange:actualRange:")
Input_View_attributedSubstringForProposedRange :: proc "c" (
	self: ^Input_View,
	range: NS.Range,
	actual: ^NS.Range,
) -> ^NS.Object {
	return nil
}

@(objc_type = Input_View, objc_implement, objc_name = "characterIndexForPoint", objc_selector = "characterIndexForPoint:")
Input_View_characterIndexForPoint :: proc "c" (self: ^Input_View, point: NS.Point) -> NS.UInteger {
	return _NOT_FOUND
}

@(objc_type = Input_View, objc_implement, objc_name = "firstRectForCharacterRange", objc_selector = "firstRectForCharacterRange:actualRange:")
Input_View_firstRectForCharacterRange :: proc "c" (
	self: ^Input_View,
	range: NS.Range,
	actual: ^NS.Range,
) -> NS.Rect {
	window := _find_by_input_view(self)
	if window == nil do return {}

	caret := window.caret_rect
	height := f64(window.size_points.y)
	in_window := NS.Rect {
		{NS.Float(caret.x), NS.Float(height - f64(caret.w))},
		{NS.Float(caret.z - caret.x), NS.Float(caret.w - caret.y)},
	}

	return objc_send(NS.Rect, window.ns_window, "convertRectToScreen:", in_window)
}

@(objc_type = Input_View, objc_implement, objc_name = "doCommandBySelector", objc_selector = "doCommandBySelector:")
Input_View_doCommandBySelector :: proc "c" (self: ^Input_View, selector: NS.SEL) {
	context = _state.odin_context
	window := _find_by_input_view(self)
	if window == nil do return

	name := string(sel_getName(selector))
	append(&window.events, Text_Command{strings.clone(name, _event_allocator(window))})
	_request_frame_of(window)
}

// Acts on the window whose frame runs. While on, a panel takes the keyboard from the app in front.
set_text_input :: proc(is_on: bool, caret_rect: [4]f32) {
	window := current_window()
	if window == nil do return

	window.caret_rect = caret_rect
	if is_on == window.is_text_input do return

	window.is_text_input = is_on
	if _headless.is_on do return

	if is_on {
		if window.kind == .Panel do objc_send(nil, window.ns_window, "makeKeyWindow")
		objc_send(NS.BOOL, window.ns_window, "makeFirstResponder:", window.input_view)
	} else {
		window.marked_byte_count = 0
		objc_send(
			nil,
			objc_send(^NS.Object, window.input_view, "inputContext"),
			"discardMarkedText",
		)
		objc_send(NS.BOOL, window.ns_window, "makeFirstResponder:", rawptr(nil))
	}
}

type_for_test :: proc(text: string) -> bool {
	window := current_window()
	input_context := objc_send(^NS.Object, window.input_view, "inputContext")
	has_context := input_context != nil

	if has_context do objc_send(nil, input_context, "activate")

	window_number := objc_send(NS.Integer, window.ns_window, "windowNumber")

	for character in text {
		buffer, size := utf8.encode_rune(character)
		ns_character := NS.String.alloc()->initWithOdinString(string(buffer[:size]))
		defer ns_character->release()

		event := objc_send(
			^NS.Event,
			NS.Event,
			"keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:",
			NS.UInteger(NS.EventType.KeyDown),
			NS.Point{},
			NS.UInteger(0),
			NS.TimeInterval(0),
			window_number,
			rawptr(nil),
			ns_character,
			ns_character,
			NS.BOOL(false),
			u16(0),
		)

		objc_send(nil, window.input_view, "keyDown:", event)
	}

	return has_context
}
