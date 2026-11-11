package ui

import "../platform"

// Like macOS, only the keyboard moves focus. A click clears it; kit hands it to text fields.

FOCUS_RING_POINTS :: 2
FOCUS_RING_GAP_POINTS :: 1


// app sets this from the theme.
_focus_ring_color := [4]f32{0.04, 0.52, 1, 0.54}

_Focus_Stop :: struct {
	_key:  u64,
	// Key of the nearest enclosing .Arrow_Keys box, or 0.
	group: u64,
}

// Moves keyboard focus to the box; nil clears it.
focus :: proc(box: ^Box) {
	_state.focused_key = box._key if box != nil else 0
	_state.is_focus_moved = true
}

// True when the person pressed the key this frame.
is_key_pressed :: proc(key: platform.Key) -> bool {
	return int(key) < 128 && int(key) in _state.pressed_keys
}

// True when keyboard focus used this key this frame, so the app must skip its own handling.
is_key_taken :: proc(key: platform.Key) -> bool {
	return int(key) < 128 && int(key) in _state.taken_keys
}

_apply_focus_key :: proc(press: platform.Key_Press) {
	// Ctrl-Tab moves focus out of a box that keeps Tab, as macOS text views do.
	if press.key == .Tab && press.modifiers - {.Shift} == {.Control} {
		_move_focus(-1 if .Shift in press.modifiers else 1)
		_state.taken_keys += {int(press.key)}
		return
	}
	if press.modifiers & {.Command, .Control, .Option} != {} || int(press.key) >= 128 do return

	is_taken := false
	#partial switch press.key {
	case .Tab:
		_move_focus(-1 if .Shift in press.modifiers else 1)
		is_taken = true
	case .Up:
		is_taken = _move_in_group(-1, .Y)
	case .Left:
		is_taken = _move_in_group(-1, .X)
	case .Down:
		is_taken = _move_in_group(1, .Y)
	case .Right:
		is_taken = _move_in_group(1, .X)
	case .Return, .Enter:
		is_taken = _activate_focused()
	case .Space:
		// In a group such as a list the app gets Space, because focus already shows the selected row.
		index, ok := _find_focused()
		is_taken = ok && _state.focus_order[index].group == 0 && _activate_focused()
	case .Escape:
		is_taken = _state.focused_key != 0
		_state.focused_key = 0
	}

	if is_taken do _state.taken_keys += {int(press.key)}
}

_is_tab_kept :: proc() -> bool {
	box := _state.boxes[_state.focused_key] or_else nil

	return box != nil && .Keeps_Tab in box.style.flags
}

_find_focused :: proc() -> (index: int, ok: bool) {
	if _state.focused_key == 0 do return -1, false

	for stop, stop_index in _state.focus_order {
		if stop._key == _state.focused_key do return stop_index, true
	}

	return -1, false
}

_activate_focused :: proc() -> bool {
	if _, ok := _find_focused(); !ok do return false

	_state.activated_key = _state.focused_key
	_state.activated_count = 0
	_state.activated_device = .Keyboard

	return true
}

// The next Tab stop is a box outside any group, or a group at its last focused box.
_move_focus :: proc(direction: int) {
	order := _state.focus_order[:]
	stops := make([dynamic]int, context.temp_allocator)
	position := -1
	focused, has_focused := _find_focused()

	for stop, index in order {
		is_stop := stop.group == 0 || index == 0 || order[index - 1].group != stop.group
		if is_stop do append(&stops, index)

		is_current := has_focused && (index == focused || (stop.group != 0 && stop.group == order[focused].group))
		if is_current && position < 0 do position = len(stops) - 1
	}

	if len(stops) == 0 do return

	next: int
	if position < 0 {
		next = 0 if direction > 0 else len(stops) - 1
	} else {
		next = (position + direction + len(stops)) % len(stops)
	}

	target := order[stops[next]]
	if target.group != 0 {
		remembered := _state.group_focus[target.group]
		for stop in order[stops[next]:] {
			if stop.group != target.group do break
			if stop._key == remembered do target = stop
		}
	}

	_state.focused_key = target._key
	_state.is_focus_moved = true
}

_move_in_group :: proc(direction: int, axis: Axis) -> bool {
	index, ok := _find_focused()
	if !ok || _state.focus_order[index].group == 0 do return false

	group := _state.boxes[_state.focus_order[index].group] or_else nil
	if group == nil do return false
	// An Auto-axis group lays out as a row, so Left and Right move within it.
	group_axis := Axis.Y if group.style.axis == .Y else Axis.X
	if group_axis != axis do return false

	order := _state.focus_order[:]
	next := index + direction
	is_inside := next >= 0 && next < len(order) && order[next].group == order[index].group
	if is_inside {
		_state.focused_key = order[next]._key
		_state.is_focus_moved = true
	}

	return true
}

// After layout, rebuilds the Tab order and scrolls the focused box into view.
_finish_focus :: proc() {
	clear(&_state.focus_order)
	modal := _find_modal()
	if modal == nil do _read_focus_order(_state.root, 0)
	for child := modal if modal != nil else _state.overlay_root.first; child != nil; child = child.next do _read_focus_order(child, 0)

	index, ok := _find_focused()
	if !ok {
		_state.focused_key = 0
		return
	}

	group := _state.focus_order[index].group
	if group != 0 do _state.group_focus[group] = _state.focused_key

	if _state.is_focus_moved {
		_state.is_focus_moved = false
		_scroll_into_view(_state.boxes[_state.focused_key])
	}
}

_read_focus_order :: proc(box: ^Box, group: u64) {
	inner_group := box._key if .Arrow_Keys in box.style.flags else group
	is_focusable := .Clickable in box.style.flags && box._key != 0 && box.forced == .None

	if is_focusable {
		append(&_state.focus_order, _Focus_Stop{box._key, inner_group})
		// Inside a group, arrows move between its controls, never into the controls within them.
		if inner_group != 0 do return
	}

	for child := box.first; child != nil; child = child.next do _read_focus_order(child, inner_group)
}

_scroll_into_view :: proc(box: ^Box) {
	scroller := box.parent
	for scroller != nil && (.Scroll not_in scroller.style.flags) do scroller = scroller.parent
	if scroller == nil do return

	axis := _axis_index(scroller.style.axis)
	start := box.rect[axis] - scroller.rect[axis]
	end := box.rect[axis + 2] - scroller.rect[axis]
	shift: f32
	if start < 0 {
		shift = start
	} else if end > scroller.size[axis] {
		shift = min(end - scroller.size[axis], start)
	}
	if shift == 0 do return

	set_scroll(scroller, scroller.scroll + shift)
	request_frame()
}
