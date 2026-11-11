package kit

import "../platform"
import "../ui"

_TREE_INDENT_POINTS :: 16
TREE_ROW_POINTS :: 28
_TREE_CHEVRON_POINTS :: 14

_Row_Kind :: enum {
	List,
	Nav,
	Tree,
}

// Sets selected^ to id on a click or when the arrow keys focus it. Children go inside the if.
// selected^ keeps the id string, so the id must outlive the frame, such as an id from app data.
@(deferred_none = ui.pop_parent)
list_row :: proc(id: string, selected: ^string, label := "", style: ui.Style = {}) -> bool {
	return _build_row(id, selected, label, .List, 0, nil, style)
}

// Sets current^ to id on a click only; the arrow keys move focus but not current^.
@(deferred_none = ui.pop_parent)
nav_row :: proc(id: string, current: ^string, label := "", style: ui.Style = {}) -> bool {
	return _build_row(id, current, label, .Nav, 0, nil, style)
}

// Selects as list_row does. A leaf gives a nil is_open. The chevron, Right and Left set is_open^.
// The app flattens the open rows into a kit.list, so kit builds only the rows on the screen.
@(deferred_none = ui.pop_parent)
tree_row :: proc(id: string, selected: ^string, label := "", depth := 0, is_open: ^bool = nil, style: ui.Style = {}) -> bool {
	return _build_row(id, selected, label, .Tree, depth, is_open, style)
}

_build_row :: proc(id: string, selected: ^string, label: string, kind: _Row_Kind, depth: int, is_open: ^bool, style: ui.Style) -> bool {
	is_on := selected^ == id
	base := ui.Style {
		width            = ui.fill(),
		height           = ui.points(34),
		axis             = .X,
		align            = .Center,
		gap              = 12,
		padding          = {12, 0, 12, 0},
		corner_radius    = shape.radius_field - _FIELD_INSET_RADIUS,
		hover_background = to_faded(colors.base_content, HOVER_OPACITY),
		press_background = to_faded(colors.base_content, SELECTED_OPACITY),
		flags            = {.Clickable},
	}
	switch kind {
	case .List:
	case .Nav:
		base.height = ui.points(32)
		base.press_background = to_faded(colors.base_content, SELECTED_OPACITY)
	case .Tree:
		base.height = ui.points(TREE_ROW_POINTS)
		base.gap = 4
		base.padding = {6 + f32(depth) * _TREE_INDENT_POINTS, 0, 12, 0}
	}
	row := ui.box(id, ui.merge(base, style))
	row.role, row.label = .Row, label if label != "" else id
	signal := ui.signal(row)

	// A list's selection follows focus; a sidebar's follows only a click.
	is_selecting := signal.is_activated || (signal.is_focused && kind != .Nav)
	if is_selecting && !is_on {
		selected^ = id
		is_on = true
		ui.request_frame()
	}

	row.is_on = is_on
	if is_on {
		row.style.background = to_faded(colors.base_content, SELECTED_OPACITY) if kind == .Nav else to_faded(colors.primary, SOFT_OPACITY)
		row.style.hover_background = row.style.background
		row.style.press_background = row.style.background
	}

	ui.push_parent(row)
	if kind == .Tree do _build_disclosure(row, signal, is_open)
	if label != "" {
		label_look := ui.Style {
			width      = ui.fill(),
			height     = ui.fit_text(),
			text_color = colors.base_content,
			flags      = {.Truncate_Text},
		}
		if kind == .Nav {
			label_look.font_weight = .Medium
			if !is_on do label_look.text_color = to_faded(colors.base_content, 0.7)
		}
		ui.box("", label_look, label)
	}

	return true
}

_build_disclosure :: proc(row: ^ui.Box, signal: ui.Signal, is_open: ^bool) {
	if is_open == nil {
		ui.box("", {width = ui.points(_TREE_CHEVRON_POINTS)})
		return
	}

	if signal.is_focused && row.forced == .None {
		key := platform.Key.Left if is_open^ else .Right
		if ui.is_key_pressed(key) && !ui.is_key_taken(key) {
			is_open^ = !is_open^
			ui._state.taken_keys += {int(key)}
			ui.request_frame()
		}
	}

	row.value = "open" if is_open^ else "closed"
	look := ui.Style {
		width  = ui.points(_TREE_CHEVRON_POINTS),
		height = ui.points(_TREE_CHEVRON_POINTS),
		flags  = {.Clickable},
	}
	symbol := "chevron.down" if is_open^ else "chevron.right"
	chevron := _icon_box("disclosure", symbol, 9, to_faded(colors.base_content, 0.7), look)
	if ui.signal(chevron).is_activated {
		is_open^ = !is_open^
		ui.request_frame()
	}
}
