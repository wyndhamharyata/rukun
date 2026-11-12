package ui

import "../platform"

// A box as VoiceOver and the headless tree see it. depth counts the elements around it.
Accessible :: struct {
	box:   ^Box,
	role:  Role,
	label: string,
	depth: int,
}

// Every box with a role or visible text, in build order. A control's label covers its insides,
// and text that repeats its parent's label, as a row's does, stays out.
_list_accessible :: proc(roots: []^Box, found: ^[dynamic]Accessible) {
	for root in roots {
		for child := root.first; child != nil; child = child.next do _add_accessible(child, 0, "", found)
	}
}

_add_accessible :: proc(box: ^Box, depth: int, parent_label: string, found: ^[dynamic]Accessible) {
	if !_is_shown(box) do return

	role, label := _to_role(box)
	if role == .Text && box.role == .None && label == parent_label do return
	if role != .None {
		append(found, Accessible{box, role, label, depth})
		if _is_control(role) do return
	}

	inner := depth + 1 if role != .None else depth
	inner_label := label if role != .None else parent_label
	for child := box.first; child != nil; child = child.next do _add_accessible(child, inner, inner_label, found)
}

_to_role :: proc(box: ^Box) -> (Role, string) {
	if box.role != .None do return box.role, box.label
	if box.text != "" do return .Text, box.text
	// VoiceOver pages through it, so a long list can build the rows it has not shown.
	if .Scroll in box.style.flags && box._key != 0 do return .Scroll_Area, box.label

	return .None, ""
}

_is_control :: proc(role: Role) -> bool {
	#partial switch role {
	case .Button, .Checkbox, .Toggle, .Text_Field, .Menu_Item, .Toast, .Slider, .Image, .Text, .Radio, .Tab, .Pop_Up, .Progress, .Tooltip:
		return true
	}

	return false
}

_is_shown :: proc(box: ^Box) -> bool {
	shown := _to_shown_rect(box)

	return box.style.fade < 1 && shown.z > shown.x && shown.w > shown.y
}

// The part of the box that its parents do not clip.
_to_shown_rect :: proc(box: ^Box) -> [4]f32 {
	return {max(box.rect.x, box.clip.x), max(box.rect.y, box.clip.y), min(box.rect.z, box.clip.z), min(box.rect.w, box.clip.w)}
}

// Runs an assistive app's action through the same state that a click or a key press sets.
_apply_accessibility_action :: proc(action: platform.Accessibility_Action) {
	box := _state.boxes[action.key] or_else nil
	if box == nil do return
	is_scroll := action.kind == .Scroll_Page_Back || action.kind == .Scroll_Page_Forward
	if (.Scroll if is_scroll else .Clickable) not_in box.style.flags do return

	switch action.kind {
	case .Press:
		_state.activated_key = box._key
		_state.activated_count = 0
		_state.activated_device = .Assistive
	case .Show_Menu:
		_state.secondary_key = box._key
		_state.secondary_device = .Assistive
	case .Focus:
		// A control inside a group, such as a row's checkbox, is no Tab stop, so focus stays.
		if _is_focus_stop(box._key) do focus(box)
	case .Increment, .Decrement:
		focus(box)
		keys := box.step_keys if box.step_keys != {} else {.Down, .Up}
		key := keys[1] if action.kind == .Increment else keys[0]
		_state.pressed_keys += {int(key)}
		_apply_focus_key({key = key})
	case .Scroll_Page_Back, .Scroll_Page_Forward:
		page := box.size[_axis_index(box.style.axis)]
		set_scroll(box, box._scroll_target + (page if action.kind == .Scroll_Page_Forward else -page))
	}
}

_is_focus_stop :: proc(key: u64) -> bool {
	for stop in _state.focus_order do if stop._key == key do return true

	return false
}
