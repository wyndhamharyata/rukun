package ui

// A box as VoiceOver and the headless tree see it. depth counts the elements around it.
Accessible :: struct {
	box:   ^Box,
	role:  Role,
	label: string,
	depth: int,
}

// Every box with a role or text that shows, in build order. A control's label covers its insides,
// and a text that repeats its parent's label, such as a row's, stays out.
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
