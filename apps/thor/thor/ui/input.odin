package ui

import "../platform"
import "core:math/linalg"
import "core:slice"
import "core:time"

SWIPE_DECIDE_POINTS :: 4

SWIPE_SIDEWAYS_RATIO :: 1.5

// A press held still this long is a long press.
LONG_PRESS_SECONDS :: 0.5

// A press that moves this far is a drag.
DRAG_THRESHOLD_POINTS :: 3

// The device that started an interaction.
Device :: enum {
	None,
	Mouse,
	Touch,
	Pen,
	Keyboard,
	// VoiceOver, Voice Control or Switch Control asked the element to act.
	Assistive,
}

// A press by the pointer, a finger or a pen, until its release. ui keeps one at a time.
Interaction :: struct {
	is_held:         bool,
	device:          Device,
	// Where and when the press began, in points.
	start:           [2]f32,
	started_at:      time.Tick,
	// 1, 2, or 3 for a single, double, or triple press.
	count:           int,
	is_long_pressed: bool,
	is_dragged:      bool,
	_key:            u64,
}

// Controls and displays return one. Unused fields stay zero. Never name a field after a mouse.
Signal :: struct {
	// The box itself: a popover's anchor, a test's target, or its rect.
	box:             ^Box,
	// Pointer or pen over it or inside it; a finger never hovers.
	is_hovered:      bool,
	// Pressed and not yet released.
	is_held:         bool,
	is_focused:      bool,
	// Its action fired this frame: a click, tap, or Return/Space while focused.
	is_activated:    bool,
	// 1, 2, or 3 for a single, double, or triple click or tap; 0 from the keyboard or an assistive app.
	count:           int,
	// A right click, Control-click, two-finger click or touch long press, for a context menu.
	is_secondary:    bool,
	// Held still for LONG_PRESS_SECONDS, true on the frame it passes that mark.
	is_long_pressed: bool,
	// Held and moved past DRAG_THRESHOLD_POINTS, with the distance from the press start in points.
	is_dragged:      bool,
	drag:            [2]f32,
	// The edited value changed this frame; the component sets it, never ui.
	is_changed:      bool,
	// The device behind this frame's interaction with it.
	device:          Device,
}

_apply_events :: proc(events: []platform.Event) {
	for item in events {
		switch event in item {
		case platform.Mouse_Move:
			_state.mouse = event.position / _state.zoom
			interaction := &_state.interaction
			is_far := linalg.length(_state.mouse - interaction.start) > DRAG_THRESHOLD_POINTS
			if interaction.is_held && is_far do interaction.is_dragged = true
		case platform.Mouse_Press:
			_state.mouse = event.position / _state.zoom
			_state.pressed_at = _state.mouse
			_state.is_pressed = true

			if event.button == .Right || .Control in event.modifiers {
				_state.secondary_key = _state.hot_key
				_state.secondary_device = .Mouse
				_state.is_secondary_press = true
				continue
			}

			_state.focused_key = 0
			_state.active_key = _state.hot_key
			_state.interaction = {
				is_held    = true,
				device     = .Mouse,
				start      = _state.mouse,
				started_at = platform.now(),
				count      = event.click_count,
				_key       = _state.hot_key,
			}
			// Ask for a frame at the moment the press becomes a long press.
			if _state.hot_key != 0 do platform.request_frame_after(LONG_PRESS_SECONDS)
		case platform.Mouse_Release:
			if _state.is_secondary_press {
				_state.is_secondary_press = false
				continue
			}

			if _state.active_key != 0 && _state.active_key == _state.hot_key {
				_state.activated_key = _state.active_key
				_state.activated_count = _state.interaction.count
				_state.activated_device = _state.interaction.device
			}

			_state.active_key = 0
			_state.interaction.is_held = false
		case platform.Mouse_Exit:
			_state.mouse = {-1, -1}
		case platform.Scroll:
			_apply_scroll(event)
		case platform.Key_Press:
			if int(event.key) < 128 do _state.pressed_keys += {int(event.key)}
			_apply_focus_key(event)
		case platform.Text_Command:
			// A text field's Tab arrives through the input method.
			is_tab_kept := _is_tab_kept()
			if event.name == "insertTab:" && !is_tab_kept do _move_focus(1)
			if event.name == "insertBacktab:" && !is_tab_kept do _move_focus(-1)
			// Escape in a text field also arrives through the input method.
			if event.name == "cancelOperation:" do _state.pressed_keys += {int(platform.Key.Escape)}
		case platform.Accessibility_Action:
			_apply_accessibility_action(event)
		case platform.Text_Insert, platform.Text_Marked, platform.Screen_Change, platform.Appearance_Change:
		}
	}

	interaction := &_state.interaction
	held_seconds := time.duration_seconds(time.tick_diff(interaction.started_at, platform.now()))
	is_long := interaction.is_held && !interaction.is_long_pressed && !interaction.is_dragged
	if is_long && held_seconds >= LONG_PRESS_SECONDS {
		interaction.is_long_pressed = true
		_state.long_pressed_key = interaction._key
	}
}

_apply_scroll :: proc(event: platform.Scroll) {
	delta := event.delta / _state.zoom if event.is_precise else event.delta * POINTS_PER_LINE

	if event.is_start {
		_state.swipe_axis = nil
		_state.undecided_swipe_points = {}
	}

	if event.is_precise {
		axis, is_known := _state.swipe_axis.?

		if !is_known {
			_state.undecided_swipe_points += delta

			undecided := _state.undecided_swipe_points
			if abs(undecided.x) + abs(undecided.y) < SWIPE_DECIDE_POINTS do return

			axis = .X if abs(undecided.x) > abs(undecided.y) * SWIPE_SIDEWAYS_RATIO else .Y
			_state.swipe_axis = axis
			delta = undecided
		}

		delta[1 - _axis_index(axis)] = 0
	}

	for side in 0 ..< 2 {
		box, ok := _state.boxes[_state.scroll_keys[side]]
		is_scrolled := ok && delta[side] != 0

		if !is_scrolled do continue

		// Boxes built before the next layout read the scroll, so keep it inside the last content.
		max_scroll := max(0, box.content_size[side] - box.size[side])
		box._scroll_target = clamp(box._scroll_target - delta[side], 0, max_scroll)
		// macOS already supplies the glide after a trackpad flick.
		if event.is_precise do box.scroll = box._scroll_target
	}
}

// This box's input for the frame: hover, press, activation, focus, and drag.
signal :: proc(box: ^Box) -> Signal {
	if box.forced != .None {
		return {
			box = box,
			is_hovered = box.forced == .Hover || box.forced == .Press,
			is_held = box.forced == .Press,
			is_focused = box.forced == .Focus,
		}
	}

	key := box._key
	if key == 0 do return {box = box}

	signal := Signal {
		box             = box,
		is_hovered      = slice.contains(_state.hover_chain[:], key),
		is_held         = key == _state.active_key,
		is_focused      = key == _state.focused_key,
		is_activated    = key == _state.activated_key,
		is_secondary    = key == _state.secondary_key,
		is_long_pressed = key == _state.long_pressed_key,
	}
	if signal.is_activated {
		signal.count = _state.activated_count
		signal.device = _state.activated_device
	}
	if signal.is_secondary && signal.device == .None do signal.device = _state.secondary_device
	if signal.is_held {
		signal.is_dragged = _state.interaction.is_dragged
		signal.drag = _state.mouse - _state.interaction.start
		signal.device = _state.interaction.device
	}

	return signal
}

// The current container's Signal; call it inside the container's if.
here :: proc() -> Signal {
	return signal(current_parent())
}

// The whole current or last press, for a custom component that needs more than a Signal.
interaction :: proc() -> Interaction {
	return _state.interaction
}

// Pointer position in points from the window's top left; {-1, -1} when outside.
mouse_position :: proc() -> [2]f32 {
	return _state.mouse
}

_is_inside :: proc(point: [2]f32, rect: [4]f32) -> bool {
	return point.x >= rect.x && point.x < rect.z && point.y >= rect.y && point.y < rect.w
}

_apply_mouse_to_boxes :: proc() {
	_state.hot_key = 0
	_state.pointer_box = nil
	_state.scroll_keys = {}
	_state.cursor = .Arrow
	modal := _find_modal()
	if modal == nil do _visit_hot(_state.root, .Arrow)
	// The overlay layer covers the window, so only the boxes on it are under the mouse.
	for child := modal if modal != nil else _state.overlay_root.first; child != nil; child = child.next do _visit_hot(child, .Arrow)

	// Like CSS, the deepest box under the pointer and every box around it count as hovered.
	clear(&_state.hover_chain)
	for at := _state.pointer_box; at != nil; at = at.parent {
		if at._key != 0 do append(&_state.hover_chain, at._key)
	}

	for _, box in _state.boxes {
		if box.forced != .None {
			box._hot_fraction = 1 if box.forced == .Hover || box.forced == .Press else 0
			box._active_fraction = 1 if box.forced == .Press else 0
			continue
		}

		is_hot :=
			box._key == _state.hot_key && (_state.active_key == 0 || _state.active_key == box._key)

		box._hot_fraction = _approach(box._hot_fraction, 1 if is_hot else 0, HOT_RATE_PER_SECOND)
		box._active_fraction = _approach(
			box._active_fraction,
			1 if box._key == _state.active_key else 0,
			HOT_RATE_PER_SECOND,
		)
	}
}

// The last box under the mouse draws on top, so its cursor, or its parent's, wins.
_visit_hot :: proc(box: ^Box, parent_cursor: platform.Cursor) {
	flags := box.style.flags
	is_under_mouse := _is_inside(_state.mouse, _intersect(box.rect, box.clip))
	is_clipped_away := !is_under_mouse && .Clip in flags
	is_kept_under_mouse := is_under_mouse && box._key != 0
	is_hoverable := (.Clickable in flags || .Hoverable in flags) && box.forced == .None

	if is_clipped_away do return

	cursor := box.style.cursor if box.style.cursor != .Auto else parent_cursor
	if is_under_mouse {
		_state.cursor = cursor
		_state.pointer_box = box
	}

	if is_kept_under_mouse {
		if is_hoverable do _state.hot_key = box._key
		if .Scroll in flags do _state.scroll_keys[_axis_index(box.style.axis)] = box._key
	}

	for child := box.first; child != nil; child = child.next do _visit_hot(child, cursor)
}
