package kit

import "../platform"
import "../ui"
import "core:fmt"
import "core:math"

_TOGGLE_SIZE_POINTS :: [2]f32{26, 15}
_TOGGLE_KNOB_INSET_POINTS :: 1

_CHECKBOX_POINTS :: 16
_RADIO_POINTS :: 16
_RADIO_DOT_POINTS :: 6
_CHIP_HEIGHT_POINTS :: 24

_SEGMENT_INSET_POINTS :: 2

// The control keeps id and shows label and icon: a select, segmented, combobox, menu or palette.
Option :: struct {
	id:          string,
	label:       string,
	icon:        string,
	// A shortcut or a note that shows faint at the right of a menu or palette row.
	hint:        string,
	is_disabled: bool,
}

// Flips is_on^ on a click on the box or label, or on Return or Space, and sets is_changed.
// A style corner_radius of half the width makes a round checkbox.
checkbox :: proc(id: string, is_on: ^bool, label := "", tone := Tone.Primary, style: ui.Style = {}) -> ui.Signal {
	return _build_toggle(id, is_on, label, .Checkbox, tone, style)
}

// A switch, for a setting that takes effect at once. It flips is_on^ as checkbox does.
toggle :: proc(id: string, is_on: ^bool, label := "", tone := Tone.Primary, style: ui.Style = {}) -> ui.Signal {
	return _build_toggle(id, is_on, label, .Toggle, tone, style)
}

// A pill with the label inside, in its tone's colour when on. It flips is_on^ as a checkbox does.
toggle_chip :: proc(id: string, is_on: ^bool, label: string, tone := Tone.Primary) -> ui.Signal {
	look, _ := _tone_style(tone if is_on^ else .Base, .Soft if is_on^ else .Solid)
	if !is_on^ do look.text_color = with_opacity(colors.base_content, 0.7)
	look.width = ui.fit_text()
	look.height = ui.points(_CHIP_HEIGHT_POINTS)
	look.padding = {10, 0, 10, 0}
	look.corner_radius = _CHIP_HEIGHT_POINTS / 2
	look.font_size = 12
	look.font_weight = .Semibold
	look.flags = {.Clickable}

	chip := ui.box(id, look, label)
	signal := _flip_on_activation(ui.signal(chip), is_on)
	chip.role, chip.label, chip.is_on = .Toggle, label, is_on^

	return signal
}

_build_toggle :: proc(id: string, is_on: ^bool, label: string, role: ui.Role, tone: Tone, style: ui.Style) -> ui.Signal {
	if label == "" {
		box := ui.box(id, {flags = {.Clickable}})
		box.role, box.label = role, id
		signal := _flip_on_activation(ui.signal(box), is_on)
		box.is_on = is_on^
		_style_toggle(box, is_on^, role, tone, signal, style)
		return signal
	}

	row := ui.box(id, {axis = .X, align = .Center, gap = 8, flags = {.Clickable}})
	row.role, row.label = role, label
	signal := _flip_on_activation(ui.signal(row), is_on)
	row.is_on = is_on^
	if ui.scope(row) {
		_style_toggle(ui.box("control", {}), is_on^, role, tone, signal, style)
		ui.box("", {text_color = colors.base_content, font_size = 13}, label)
	}

	return signal
}

_flip_on_activation :: proc(signal: ui.Signal, is_on: ^bool) -> ui.Signal {
	signal := signal
	if signal.is_activated {
		is_on^ = !is_on^
		signal.is_changed = true
		// Boxes that kit built before this one read the old value.
		ui.request_frame()
	}

	return signal
}

// state is the signal of the element that takes the clicks.
_style_toggle :: proc(box: ^ui.Box, is_on: bool, role: ui.Role, tone: Tone, state: ui.Signal, style: ui.Style) {
	color, content := tone_colors(tone)
	fill := color
	if state.is_held {
		fill = _to_darker(color, _FILL_PRESS_DARKEN)
	} else if state.is_hovered {
		fill = _to_darker(color, _FILL_HOVER_DARKEN)
	}

	#partial switch role {
	case .Checkbox:
		border := with_opacity(colors.base_content, 0.5)
		if state.is_held {
			border = colors.base_content
		} else if state.is_hovered {
			border = with_opacity(colors.base_content, 0.7)
		}
		look := ui.Style {
			width         = ui.points(_CHECKBOX_POINTS),
			height        = ui.points(_CHECKBOX_POINTS),
			align         = .Center,
			justify       = .Center,
			corner_radius = shape.radius_selector,
			border_width  = 0 if is_on else 1.5,
			border_color  = border,
			background    = fill if is_on else {},
		}
		box.style = ui.merge(ui.merge(box.style, look), style)
		if !is_on do return

		check_size := math.round(box.style.width.value * 0.625)
		if ui.scope(box) do icon_box("checkmark", check_size, content)
	case .Toggle:
		size := _TOGGLE_SIZE_POINTS
		track := with_opacity(colors.base_content, TRACK_OPACITY)
		if state.is_held {
			track = with_opacity(colors.base_content, TRACK_OPACITY + SELECTED_OPACITY)
		} else if state.is_hovered {
			track = with_opacity(colors.base_content, TRACK_OPACITY + HOVER_OPACITY)
		}
		look := ui.Style {
			width         = ui.points(size.x),
			height        = ui.points(size.y),
			corner_radius = size.y / 2,
			background    = fill if is_on else track,
		}
		box.style = ui.merge(ui.merge(box.style, look), style)

		// Base fills the track with base_content, and a white knob does not show on it.
		knob := colors.base_100 if is_on && tone == .Base else [4]f32{1, 1, 1, 1}
		knob_size := size.y - 2 * _TOGGLE_KNOB_INSET_POINTS
		travel := size.x - 2 * _TOGGLE_KNOB_INSET_POINTS - knob_size
		fraction := ui.animate(fmt.tprintf("%x knob", box._key), 1 if is_on else 0, motion.fast)
		position := [2]f32{_TOGGLE_KNOB_INSET_POINTS + fraction * travel, _TOGGLE_KNOB_INSET_POINTS}
		if ui.scope(box) {
			ui.box("", {width = ui.points(knob_size), height = ui.points(knob_size), corner_radius = knob_size / 2, background = {0, 0, 0, 0.3}, softness = 1.5, position = position + {0, 0.5}, flags = {.Floating}})
			ui.box("", {width = ui.points(knob_size), height = ui.points(knob_size), corner_radius = knob_size / 2, background = knob, position = position, flags = {.Floating}})
		}
	}
}

// Sets selected^ to id on a click. selected^ keeps the id string, so the id must outlive the frame.
// In a box with .Arrow_Keys, Tab enters at the selected radio, and the arrows move and select.
radio :: proc(id: string, selected: ^string, label := "", tone := Tone.Primary, style: ui.Style = {}) -> ui.Signal {
	look := ui.Style{flags = {.Clickable}}
	if label != "" do look = {axis = .X, align = .Center, gap = 8, flags = {.Clickable}}
	box := ui.box(id, look)
	box.role, box.label = .Radio, label if label != "" else id
	signal := _select_on_activation(ui.signal(box), selected, id)
	box.is_on = selected^ == id
	if box.is_on do _enter_group_at(box)
	if label == "" {
		_style_radio(box, box.is_on, tone, signal, style)
	} else if ui.scope(box) {
		_style_radio(ui.box("dot", {}), box.is_on, tone, signal, style)
		ui.box("", {text_color = colors.base_content, font_size = 13}, label)
	}

	return signal
}

// Sets selected^ to id on a click, or when the arrows move focus onto the element in a group.
_select_on_activation :: proc(signal: ui.Signal, selected: ^string, id: string) -> ui.Signal {
	signal := signal
	if (signal.is_activated || _is_arrowed_to(signal)) && selected^ != id {
		selected^ = id
		signal.is_changed = true
		ui.request_frame()
	}

	return signal
}

_style_radio :: proc(box: ^ui.Box, is_on: bool, tone: Tone, state: ui.Signal, style: ui.Style) {
	color, content := tone_colors(tone)
	fill := color
	border := with_opacity(colors.base_content, 0.5)
	if state.is_held {
		fill = _to_darker(color, _FILL_PRESS_DARKEN)
		border = colors.base_content
	} else if state.is_hovered {
		fill = _to_darker(color, _FILL_HOVER_DARKEN)
		border = with_opacity(colors.base_content, 0.7)
	}
	look := ui.Style {
		width         = ui.points(_RADIO_POINTS),
		height        = ui.points(_RADIO_POINTS),
		align         = .Center,
		justify       = .Center,
		corner_radius = _RADIO_POINTS / 2,
		border_width  = 0 if is_on else 1.5,
		border_color  = border,
		background    = fill if is_on else {},
	}
	box.style = ui.merge(ui.merge(box.style, look), style)
	if !is_on do return

	dot := ui.Style {
		width         = ui.points(_RADIO_DOT_POINTS),
		height        = ui.points(_RADIO_DOT_POINTS),
		corner_radius = _RADIO_DOT_POINTS / 2,
		background    = content,
	}
	if ui.scope(box) do ui.box("", dot)
}

_to_option_label :: proc(options: []Option, id: string) -> string {
	for option in options {
		if option.id == id do return option.label
	}

	return ""
}

// Also for tabs. selected^ keeps the option's id string, so the ids must outlive the frame.
// A zero width fits the options. Sets is_changed on the frame selected^ changes.
segmented :: proc(id: string, selected: ^string, options: []Option, tone := Tone.Base, width := ui.Size{}) -> ui.Signal {
	track_look := ui.Style {
		width         = width if width != {} else ui.fit_children(),
		height        = ui.points(_BUTTON_HEIGHT_POINTS),
		axis          = .X,
		padding       = _SEGMENT_INSET_POINTS,
		corner_radius = shape.radius_field,
		background    = with_opacity(colors.base_content, HOVER_OPACITY),
		flags         = {.Arrow_Keys},
	}
	track := ui.box(id, track_look)
	is_changed := false
	color, content := tone_colors(tone)

	if ui.scope(track) {
		// The selection is a pill that springs to the picked segment's place in the last frame.
		// Before that place exists, the segment fills itself.
		picked := ui._find_box_with_key(ui._to_key(selected^, track._seed))
		has_pill := picked != nil && picked.rect.z > picked.rect.x
		if has_pill {
			pill := ui.Style {
				width         = ui.points(picked.rect.z - picked.rect.x),
				height        = ui.points(picked.rect.w - picked.rect.y),
				position      = {picked.rect.x - track.rect.x, picked.rect.y - track.rect.y},
				corner_radius = shape.radius_field - _SEGMENT_INSET_POINTS,
				background    = colors.popover if tone == .Base else color,
				border_width  = shape.border if tone == .Base else 0,
				border_color  = colors.line,
				motion        = motion.normal,
				flags         = {.Floating},
			}
			ui.box("selection_pill", pill)
		}
		for option in options {
			look := ui.Style {
				width            = ui.fill() if width != {} else ui.fit_children(),
				height           = ui.fill(),
				axis             = .X,
				align            = .Center,
				justify          = .Center,
				gap              = 6,
				padding          = {12, 0, 12, 0},
				corner_radius    = shape.radius_field - _SEGMENT_INSET_POINTS,
				hover_background = with_opacity(colors.base_content, HOVER_OPACITY),
				press_background = with_opacity(colors.base_content, SELECTED_OPACITY),
				flags            = {} if option.is_disabled else {.Clickable},
			}
			segment := ui.box(option.id, look)
			signal := ui.signal(segment)
			if !option.is_disabled {
				signal = _select_on_activation(signal, selected, option.id)
				is_changed ||= signal.is_changed
			}

			is_on := selected^ == option.id
			segment.role, segment.label, segment.is_on = .Tab, option.label, is_on
			text_color := with_opacity(colors.base_content, 0.7)
			if segment._hot_fraction > 0.5 do text_color = colors.base_content
			if option.is_disabled do text_color = with_opacity(colors.base_content, 0.35)
			if is_on {
				_enter_group_at(segment)
				text_color = colors.base_content if tone == .Base else content
				// Base raises the selected segment as a card, and a tone fills it.
				if !has_pill && tone == .Base {
					segment.style.background = colors.popover
					segment.style.border_width = shape.border
					segment.style.border_color = colors.line
				} else if !has_pill {
					segment.style.background = color
				}
				segment.style.hover_background = segment.style.background
				segment.style.press_background = segment.style.background
			}

			if ui.scope(segment) {
				if option.icon != "" do icon_box(option.icon, 13, text_color)
				ui.box("", {text_color = text_color, font_size = 13, font_weight = .Medium}, option.label)
			}
		}
	}

	signal := ui.signal(track)
	signal.is_changed = is_changed

	return signal
}

// True on the frame the arrow keys moved keyboard focus onto the box, in a group with .Arrow_Keys.
_is_arrowed_to :: proc(signal: ui.Signal) -> bool {
	if !signal.is_focused do return false

	for key in ([]platform.Key{.Left, .Right, .Up, .Down}) {
		if ui.is_key_taken(key) do return true
	}

	return false
}

// Makes Tab enter the box's .Arrow_Keys group at this box, while focus is outside the group.
_enter_group_at :: proc(box: ^ui.Box) {
	for group := box.parent; group != nil; group = group.parent {
		if .Arrow_Keys not_in group.style.flags do continue

		index, is_focused := ui._find_focused()
		is_inside := is_focused && ui._state.focus_order[index].group == group._key
		if !is_inside do ui._state.group_focus[group._key] = box._key
		return
	}
}
