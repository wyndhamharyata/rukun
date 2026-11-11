package platform

import "base:intrinsics"
import "base:runtime"
import "core:strings"
import NS "core:sys/darwin/Foundation"

Modifier :: enum {
	Shift,
	Control,
	Option,
	Command,
}

Modifiers :: bit_set[Modifier]

Mouse_Button :: enum {
	Left,
	Right,
	Middle,
}

Mouse_Move :: struct {
	position: [2]f32,
}

Mouse_Press :: struct {
	position:    [2]f32,
	button:      Mouse_Button,
	modifiers:   Modifiers,
	// 1 for the first press, 2 for the second press of a double click, and so on.
	click_count: int,
}

Mouse_Release :: struct {
	button: Mouse_Button,
}

Mouse_Exit :: struct {
}

Scroll :: struct {
	// Points for a trackpad, lines for a mouse wheel.
	delta:      [2]f32,
	is_precise: bool,
	is_start:   bool,
}

Key_Press :: struct {
	key:        Key,
	characters: string,
	modifiers:  Modifiers,
}

Text_Insert :: struct {
	text: string,
}

Text_Marked :: struct {
	text: string,
}

Text_Command :: struct {
	name: string,
}

Event :: union {
	Text_Insert,
	Text_Marked,
	Text_Command,
	Mouse_Move,
	Mouse_Press,
	Mouse_Release,
	Mouse_Exit,
	Scroll,
	Key_Press,
	Screen_Change,
	Appearance_Change,
}

// The appearance or accent color changed in System Settings.
Appearance_Change :: struct {}

// The window moved to another screen, which may be a different size.
Screen_Change :: struct {}

// Returns events for the window whose frame is running.
list_events :: proc() -> []Event {
	window := current_window()
	if window == nil do return nil

	return window.events[:]
}

_to_modifiers :: proc(event: ^NS.Event) -> Modifiers {
	flags := transmute(NS.UInteger)event->modifierFlags()
	modifiers: Modifiers

	if flags & (1 << 17) != 0 do modifiers += {.Shift}
	if flags & (1 << 18) != 0 do modifiers += {.Control}
	if flags & (1 << 19) != 0 do modifiers += {.Option}
	if flags & (1 << 20) != 0 do modifiers += {.Command}

	return modifiers
}

_read_position :: proc(event: ^NS.Event, window: ^Native_Window) -> [2]f32 {
	location := event->locationInWindow()

	if event->window() == nil {
		location = objc_send(NS.Point, window.ns_window, "convertPointFromScreen:", location)
	}

	return {f32(location.x), window.size_points.y - f32(location.y)}
}

_apply_event :: proc(event: ^NS.Event) -> bool {
	if event->type() == .ApplicationDefined {
		_request_every_frame()
		return true
	}

	event_window := event->window()
	window := _find_by_ns_window(event_window) if event_window != nil else _find_key_window()
	if window == nil do return false

	is_taken := false

	#partial switch event->type() {
	case .MouseMoved, .LeftMouseDragged, .RightMouseDragged, .OtherMouseDragged:
		append(&window.events, Mouse_Move{_read_position(event, window)})
	case .LeftMouseDown, .RightMouseDown, .OtherMouseDown:
		button := _to_button(event)

		click_count := int(objc_send(NS.Integer, event, "clickCount"))
		append(&window.events, Mouse_Press{_read_position(event, window), button, _to_modifiers(event), click_count})
	case .LeftMouseUp, .RightMouseUp, .OtherMouseUp:
		append(&window.events, Mouse_Release{_to_button(event)})
	case .AppKitDefined:
		// AppKit warns "Window move completed without beginning" on subtype 21 in this event loop,
		// even after sendEvent got subtype 20, the begin. Subtype 4 gives AppKit the new place.
		return event->subtype() == 21
	case .MouseExited:
		append(&window.events, Mouse_Exit{})
	case .ScrollWheel:
		// Phases 1 and 32 are NSEventPhaseBegan and NSEventPhaseMayBegin.
		phase := objc_send(NS.UInteger, event, "phase")

		append(
			&window.events,
			Scroll {
				is_start = phase == 1 || phase == 32,
				delta = {f32(event->scrollingDeltaX()), f32(event->scrollingDeltaY())},
				is_precise = bool(event->hasPreciseScrollingDeltas()),
			},
		)
	case .KeyDown:
		modifiers := _to_modifiers(event)

		// The menu bar gets its shortcuts first. Edit and View items send them back as key presses.
		if .Command in modifiers {
			bar := objc_send(^NS.Menu, _state.app, "mainMenu")
			if bar != nil && bool(objc_send(NS.BOOL, bar, "performKeyEquivalent:", event)) do return true
		}
		is_typing := window.is_text_input && .Command not_in modifiers && .Control not_in modifiers

		if is_typing {
			_request_frame_of(window)
			return false
		}

		characters := event->charactersIgnoringModifiers()->odinString()

		append(
			&window.events,
			Key_Press {
				key = to_key(event->keyCode()),
				characters = strings.clone(characters, _event_allocator(window)),
				modifiers = modifiers,
			},
		)
		is_taken = true
	case:
		return false
	}

	_request_frame_of(window)

	return is_taken
}

_event_allocator :: proc(window: ^Native_Window) -> runtime.Allocator {
	return runtime.arena_allocator(&window.event_arena[window.event_arena_index])
}

_to_button :: proc(event: ^NS.Event) -> Mouse_Button {
	switch event->buttonNumber() {
	case 0:
		return .Left
	case 1:
		return .Right
	}

	return .Middle
}
