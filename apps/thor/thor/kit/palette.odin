package kit

import "../ui"
import "core:fmt"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

_PALETTE_WIDTH_POINTS :: 560
_PALETTE_ROW_POINTS :: 32
_PALETTE_SHOWN_ROWS :: 8
// The palette's top, as a share of the window's height.
_PALETTE_TOP_SHARE :: 0.18

_Palette :: struct {
	input:       Text_Input,
	highlighted: int,
}

// The combobox whose menu is open, by its field's key.
_Search :: struct {
	_key:        u64,
	highlighted: int,
}

// Ignores case. 4: text starts with typed. 3: a word of text starts with it. 2: it is in text.
// 1: its letters are in text in that order. 0: no match. An empty typed scores 1.
to_match_score :: proc(text, typed: string) -> int {
	if typed == "" do return 1

	lower := strings.to_lower(text, context.temp_allocator)
	wanted := strings.to_lower(typed, context.temp_allocator)
	at := strings.index(lower, wanted)
	if at == 0 do return 4
	if at > 0 {
		for start := at; start >= 0; {
			if !_is_word_byte(lower[start - 1]) do return 3

			next := strings.index(lower[start + 1:], wanted)
			if next < 0 do break
			start += 1 + next
		}
		return 2
	}

	rest := wanted
	for letter in lower {
		if rest == "" do break
		first, size := utf8.decode_rune_in_string(rest)
		if letter == first do rest = rest[size:]
	}

	return 1 if rest == "" else 0
}

_is_word_byte :: proc(byte: u8) -> bool {
	return (byte >= 'a' && byte <= 'z') || (byte >= '0' && byte <= '9') || byte >= 0x80
}

// Indexes of the matches, best first, stable among equals. In the temp allocator.
_rank :: proc(texts: []string, typed: string) -> []int {
	Scored :: struct {
		index, score: int,
	}
	found := make([dynamic]Scored, context.temp_allocator)
	for text, index in texts {
		if score := to_match_score(text, typed); score > 0 do append(&found, Scored{index, score})
	}
	slice.stable_sort_by(found[:], proc(a, b: Scored) -> bool {return a.score > b.score})

	ranked := make([]int, len(found), context.temp_allocator)
	for &index, place in ranked do index = found[place].index

	return ranked
}

// Returns the id of the option the person runs, on that frame. Disabled options do not show.
command_palette :: proc(
	id: string,
	is_open: ^bool,
	options: []Option,
	placeholder := "Type a command",
	empty_text := "No commands match",
) -> (
	picked: string,
) {
	state := &_window.palette
	field := &state.input
	if is_open^ {
		// A press outside the palette closes it, as one outside a popover does.
		last := ui.find_box(id, ui._state.overlay_root)
		panel := ui.find_box("panel", last) if last != nil else nil
		press, is_pressed := ui._pressed_at()
		if panel != nil && is_pressed && !_is_point_in(panel.rect, press) do is_open^ = false
	}

	top := ui.window_size().y * _PALETTE_TOP_SHARE
	if !_begin_dialog(id, is_open, _PALETTE_WIDTH_POINTS, 6, 4, top) {
		if len(field.text) > 0 do set_input_text(field, "")
		state.highlighted = 0
		return ""
	}
	defer _end_dialog(true)

	field.is_taking_up_down = true
	field_look := ui.Style {
		height     = ui.points(36),
		background = {},
		font_size  = 15,
	}
	text_field("search", field, placeholder, "magnifyingglass", style = field_look)
	if field.is_changed do state.highlighted = 0

	shown := make([dynamic]Option, 0, len(options), context.temp_allocator)
	for option in options do if !option.is_disabled do append(&shown, option)
	labels := make([]string, len(shown), context.temp_allocator)
	for option, index in shown do labels[index] = option.label
	ranked := _rank(labels, to_input_text(field))
	if len(ranked) == 0 {
		ui.box("", {width = ui.fill(), padding = {12, 8, 12, 8}, text_color = to_faded(colors.base_content, 0.5)}, empty_text)
		return ""
	}
	state.highlighted = clamp(state.highlighted + field.step, 0, len(ranked) - 1)

	divider()
	list_look := ui.Style {
		width    = ui.fill(),
		height   = ui.fit_children(),
		max_size = {0, _PALETTE_SHOWN_ROWS * (_PALETTE_ROW_POINTS + 1)},
		gap      = 1,
		flags    = {.Scroll, .Clip},
	}
	if ui.col("results", list_look) {
		list := ui.current_parent()
		for index, place in ranked {
			option := shown[index]
			if _build_command_row(option, place == state.highlighted) do picked = option.id
		}
		if field.step != 0 do _scroll_to_row(list, state.highlighted)
	}
	if field.is_submitted do picked = shown[ranked[state.highlighted]].id
	if picked != "" {
		is_open^ = false
		ui.request_frame()
	}

	return picked
}

_build_command_row :: proc(command: Option, is_highlighted: bool) -> bool {
	look := ui.Style {
		width            = ui.fill(),
		height           = ui.points(_PALETTE_ROW_POINTS),
		axis             = .X,
		align            = .Center,
		gap              = 10,
		padding          = {10, 0, 10, 0},
		corner_radius    = shape.radius_field - _FIELD_INSET_RADIUS,
		background       = colors.primary if is_highlighted else {},
		hover_background = colors.primary if is_highlighted else to_faded(colors.base_content, HOVER_OPACITY),
		press_background = _to_darker(colors.primary, _FILL_HOVER_DARKEN),
		flags            = {.Clickable, .No_Focus_Ring},
	}
	row := ui.box(command.id, look)
	row.role, row.label, row.is_on = .Menu_Item, command.label, is_highlighted
	color := colors.primary_content if is_highlighted else colors.base_content
	if ui.scope(row) {
		if command.icon != "" do icon_box(command.icon, 14, color if is_highlighted else to_faded(colors.base_content, 0.7))
		ui.box("", {width = ui.fill(), height = ui.fit_text(), text_color = color, font_size = 13, flags = {.Truncate_Text}}, command.label)
		if command.hint != "" {
			ui.box("", {width = ui.fit_text(), height = ui.fit_text(), text_color = to_faded(color, 0.6), font_size = 12}, command.hint)
		}
	}

	return ui.signal(row).is_activated
}

_scroll_to_row :: proc(list: ^ui.Box, index: int) {
	row_top := f32(index) * (_PALETTE_ROW_POINTS + 1)
	row_bottom := row_top + _PALETTE_ROW_POINTS
	height := list.size.y
	if row_top < list.scroll do ui.set_scroll(list, row_top)
	if row_bottom > list.scroll + height do ui.set_scroll(list, row_bottom - height)
}

// input holds the typed text. Without the keyboard, the field shows the label of selected^.
combobox :: proc(
	id: string,
	selected: ^string,
	input: ^Text_Input,
	options: []Option,
	placeholder := "",
	width := ui.Size{},
) -> ui.Signal {
	field := input
	field.is_taking_up_down = true
	selected_label := _to_option_label(options, selected^)
	if !field.is_focused && to_input_text(field) != selected_label do set_input_text(field, selected_label)

	signal := text_field(id, field, placeholder, "chevron.up.chevron.down" if width == {} else "", width = width if width != {} else ui.fill())
	box := signal.box
	state := &_window.search
	if field.is_focused && (field.is_changed || field.step != 0) && state._key != box._key {
		state^ = {
			_key = box._key,
		}
	}
	if field.is_cancelled && state._key == box._key do state^ = {}

	typed := to_input_text(field)
	labels := make([]string, len(options), context.temp_allocator)
	for option, index in options do labels[index] = option.label
	// While the field shows the selected label, list every option, as a menu does.
	ranked := _rank(labels, "" if typed == selected_label else typed)
	is_changed := false
	if state._key == box._key && len(ranked) > 0 {
		state.highlighted = clamp(state.highlighted + field.step, 0, len(ranked) - 1)
		is_open := true
		if popover(fmt.tprintf("%s_options", id), &is_open, box) {
			// The field keeps the keyboard.
			_window.popover.is_focusing_first = false
			for index, place in ranked {
				option := options[index]
				hint := "✓" if option.id == selected^ else ""
				item := menu_item(option.id, option.label, hint, is_selected = place == state.highlighted, is_disabled = option.is_disabled)
				if item.is_activated do is_changed = _pick_option(field, selected, option)
			}
		}
		highlighted := options[ranked[state.highlighted]]
		if field.is_submitted && !highlighted.is_disabled do is_changed = _pick_option(field, selected, highlighted)
		if !is_open || is_changed do state^ = {}
	}

	signal.is_changed = is_changed

	return signal
}

_pick_option :: proc(field: ^Text_Input, selected: ^string, option: Option) -> bool {
	set_input_text(field, option.label)
	is_changed := selected^ != option.id
	selected^ = option.id
	ui.request_frame()

	return is_changed
}
