package kit

import "../ui"
import "core:fmt"

_POPOVER_GAP_POINTS :: 4
_POPOVER_MIN_WIDTH_POINTS :: 160

// A string anchor is an element id anywhere in the window. A point suits a right-click menu.
Anchor :: union {
	^ui.Box,
	string,
	[2]f32,
}

_Popover :: struct {
	// The popover that kit builds now, so a menu_item in it can close it.
	is_open:             ^bool,
	box:                 ^ui.Box,
	anchor:              ^ui.Box,
	is_focusing_first:   bool,
	// The popover whose items had focus last frame, so its close gives focus back to its anchor.
	focused_popover_key: u64,
}

// Opens below anchor, or above it with no room below, and stays inside the window.
// Escape, a menu_item or a click outside it and anchor closes it. A focused anchor passes focus in.
@(deferred_out = _end_popover)
popover :: proc(id: string, is_open: ^bool, anchor: Anchor, width: f32 = 0) -> bool {
	return _begin_popover(id, is_open, anchor, width)
}

@(deferred_out = _end_popover)
menu_button :: proc(
	id: string,
	label: string,
	is_open: ^bool,
	icon := "",
	tone := Tone.Base,
	variant := Variant.Auto,
	width: f32 = 0,
) -> bool {
	trigger := button(id, label, icon, tone, variant)
	if trigger.is_activated do is_open^ = !is_open^

	return _begin_popover(fmt.tprintf("%s_menu", id), is_open, trigger.box, width)
}

_begin_popover :: proc(id: string, is_open: ^bool, anchor: Anchor, width: f32) -> bool {
	if !is_open^ do return false

	anchor_box, anchor_rect, has_anchor := _to_anchor(anchor)
	if !has_anchor {
		is_open^ = false
		return false
	}

	last := ui.find_box(id, ui._state.overlay_root)
	if last != nil && _is_dismissed(last.rect, anchor_rect) {
		is_open^ = false
		if last._key == _window.popover.focused_popover_key && anchor_box != nil do ui.focus(anchor_box)
		return false
	}

	window := ui.window_size()
	size := last.size if last != nil else {}
	gap: f32 = _POPOVER_GAP_POINTS if anchor_rect.w > anchor_rect.y else 0
	position := [2]f32{anchor_rect.x, anchor_rect.w + gap}
	if size.y > 0 {
		above := anchor_rect.y - gap - size.y
		if position.y + size.y > window.y - MENU_MARGIN_POINTS && above >= MENU_MARGIN_POINTS do position.y = above
		position.x = clamp(position.x, MENU_MARGIN_POINTS, max(MENU_MARGIN_POINTS, window.x - size.x - MENU_MARGIN_POINTS))
		position.y = clamp(position.y, MENU_MARGIN_POINTS, max(MENU_MARGIN_POINTS, window.y - size.y - MENU_MARGIN_POINTS))
	}

	ui.push_parent(ui._state.overlay_root)
	if size.y > 0 {
		shadow := ui.Style {
			width         = ui.points(size.x),
			height        = ui.points(size.y),
			corner_radius = shape.radius_box + 2,
			background    = colors.shadow,
			softness      = 24,
			position      = position + {0, 8},
			flags         = {.Floating, .Fade_In, .Fade_Out},
		}
		ui.box(fmt.tprintf("%s_shadow", id), shadow)
	}
	panel := ui.Style {
		width         = ui.points(width) if width > 0 else ui.fit_children(),
		min_size      = {0 if width > 0 else max(_POPOVER_MIN_WIDTH_POINTS, anchor_rect.z - anchor_rect.x), 0},
		axis          = .Y,
		gap           = 1,
		padding       = 5,
		corner_radius = shape.radius_box,
		background    = colors.popover,
		border_width  = shape.border,
		border_color  = colors.line,
		position      = position,
		// The panel stays hidden until kit measures it, so it never shows in the wrong place.
		fade          = 0 if size.y > 0 else 1,
		flags         = {.Floating, .Hoverable, .Arrow_Keys, .Fade_In, .Fade_Out},
	}
	box := ui.box(id, panel)
	box.role, box.label = .Popover, id
	ui.pop_parent()
	ui.push_parent(box)
	if size.y == 0 do ui.request_frame()

	_window.popover.is_open = is_open
	_window.popover.box = box
	_window.popover.anchor = anchor_box
	_window.popover.is_focusing_first = last == nil && anchor_box != nil && ui.signal(anchor_box).is_focused

	return true
}

_end_popover :: proc(ok: bool) {
	if !ok do return

	box := _window.popover.box
	if _window.popover.is_focusing_first {
		if first := _find_first_clickable(box); first != nil do ui.focus(first)
	}

	if _has_focus_inside(box) {
		_window.popover.focused_popover_key = box._key
	} else if _window.popover.focused_popover_key == box._key {
		_window.popover.focused_popover_key = 0
	}

	ui.pop_parent()
	_window.popover = {focused_popover_key = _window.popover.focused_popover_key}
}

// Closes the popover that kit builds now, and gives focus back to its anchor if its items had it.
_close_popover :: proc() {
	if _window.popover.is_open == nil do return

	_window.popover.is_open^ = false
	if _window.popover.focused_popover_key == _window.popover.box._key && _window.popover.anchor != nil do ui.focus(_window.popover.anchor)
}

_to_anchor :: proc(anchor: Anchor) -> (box: ^ui.Box, rect: [4]f32, ok: bool) {
	switch value in anchor {
	case ^ui.Box:
		if value != nil do return value, value.rect, true
	case string:
		found := ui._find_box_by_id(value)
		if found != nil do return found, found.rect, true
		ui._warn(ui.current_parent(), "kit found no popover anchor \"%s\" this frame or the last.", value)
	case [2]f32:
		return nil, {value.x, value.y, value.x, value.y}, true
	}

	return nil, {}, false
}

_is_dismissed :: proc(popover_rect, anchor_rect: [4]f32) -> bool {
	if ui.is_key_pressed(.Escape) {
		_window.escape_frame = ui._state.frame_index
		return true
	}

	press, is_pressed := ui._pressed_at()
	// A point anchor is the press that opened the popover, which must not close it again.
	around_anchor := anchor_rect + {-1, -1, 1, 1}

	return is_pressed && !_is_point_in(popover_rect, press) && !_is_point_in(around_anchor, press)
}

_is_point_in :: proc(rect: [4]f32, point: [2]f32) -> bool {
	return point.x >= rect.x && point.x < rect.z && point.y >= rect.y && point.y < rect.w
}

_find_first_clickable :: proc(box: ^ui.Box) -> ^ui.Box {
	for child := box.first; child != nil; child = child.next {
		if .Clickable in child.style.flags && child._key != 0 do return child
		if found := _find_first_clickable(child); found != nil do return found
	}

	return nil
}

_has_focus_inside :: proc(box: ^ui.Box) -> bool {
	for child := box.first; child != nil; child = child.next {
		if ui.signal(child).is_focused || _has_focus_inside(child) do return true
	}

	return false
}
