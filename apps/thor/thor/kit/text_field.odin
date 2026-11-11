package kit

import "../font"
import "../platform"
import "../ui"
import "core:slice"

_TEXT_FIELD_FONT_SIZE :: 13

_FOCUS_BORDER_ALPHA :: 3 * SOFT_OPACITY

// Focuses the input the next time kit builds it.
focus_input :: proc(input: ^Text_Input) {
	_take_keyboard(input)
	_window.focus_request = input
}

// True while a text field or editor in this window has the keyboard, so app shortcuts wait.
has_focused_input :: proc() -> bool {
	_, is_focused := _find_focused_input()

	return is_focused
}

// Routes the frame's typing to the focused input; app calls it as each frame begins.
_apply_text_events :: proc(events: []platform.Event) {
	for input in _window.inputs {
		input.is_changed = false
		input.is_submitted = false
		input.is_cancelled = false
		input.step = 0
	}

	for event in events {
		if _, is_press := event.(platform.Mouse_Press); is_press {
			_focus_hovered_input()
			continue
		}
		if input, is_focused := _find_focused_input(); is_focused do _apply_input_event(input, event)
	}

	for input in _window.inputs do input._is_hovered = false
}

// A press gives the keyboard to the input under it and takes it from the rest.
_focus_hovered_input :: proc() {
	for input in _window.inputs {
		if input._is_hovered {
			focus_input(input)
		} else if !input.is_keeping_focus {
			input.is_focused = false
		}
	}
}

// app calls it as each frame ends, so macOS can place the input method's window at the caret.
_finish_text_fields :: proc() {
	platform.set_text_input(has_focused_input(), _window.caret_rect)
}

// Return sets input.is_submitted, Escape sets input.is_cancelled. style.font_size sizes the text.
text_field :: proc(
	id: string,
	input: ^Text_Input,
	placeholder: string,
	icon := "",
	tone := Tone.Base,
	width := ui.Size{.Fill, 1},
	style: ui.Style = {},
) -> ui.Signal {
	if !slice.contains(_window.inputs[:], input) do append(&_window.inputs, input)
	input._is_multiline = false

	is_focused := input.is_focused if ui.forced_state == .None else ui.forced_state == .Focus
	base := ui.Style {
		width            = width,
		height           = ui.points(30),
		axis             = .X,
		align            = .Center,
		gap              = 7,
		padding          = {9, 0, 9, 0},
		corner_radius    = shape.radius_field,
		background       = with_opacity(colors.base_content, HOVER_OPACITY),
		hover_background = with_opacity(colors.base_content, HOVER_OPACITY if is_focused else SELECTED_OPACITY),
		font_size        = _TEXT_FIELD_FONT_SIZE,
		cursor           = .I_Beam,
		flags            = {.Clickable, .No_Focus_Ring},
	}
	merged := ui.merge(base, style)
	// A tone, such as .Error for an invalid field, shows in the border whether focused or not.
	tone_color, _ := tone_colors(tone)
	merged.border_width = shape.border if is_focused || tone != .Base else 0
	merged.border_color = tone_color if tone != .Base else with_opacity(colors.primary, _FOCUS_BORDER_ALPHA)
	box := ui.box(id, merged)
	box.role, box.label, box.value = .Text_Field, placeholder, to_input_text(input)

	signal := ui.signal(box)
	// A press focuses the input under the pointer, never one only forced to look hovered.
	input._is_hovered = signal.is_hovered && box.forced == .None
	if box.forced == .None do _follow_input_focus(input, box, signal.is_focused)

	text_look := ui.Style {
		width     = ui.fill(),
		height    = ui.fit_text(),
		font_size = merged.font_size,
	}
	shown, marked := _to_shown_line(input, 0, is_focused)
	shaped := font.shape_text(shown, ui._read_font(text_look))
	pixels := ui.to_pixels(1)

	if ui.scope(box) {
		if icon != "" do icon_box(icon, merged.font_size, with_opacity(colors.base_content, 0.5))

		line := ui.box("line", {width = ui.fill(), height = ui.fit_children(), axis = .Y, flags = {.Clip}})
		ui.push_parent(line)
		defer ui.pop_parent()

		selection := _to_selection(input)
		if is_focused && selection[0] != selection[1] && len(shaped.lines) > 0 {
			left := font.caret_x(shaped.lines[0], font.to_utf16_index(shown, selection[0])) / pixels
			right := font.caret_x(shaped.lines[0], font.to_utf16_index(shown, selection[1])) / pixels
			ui.box("", {width = ui.points(right - left), height = ui.fill(), background = with_opacity(colors.primary, SOFT_OPACITY), position = {left, 0}, flags = {.Floating}})
		}

		text_look.text_color = colors.base_content
		if shown == "" do text_look.text_color = with_opacity(colors.base_content, 0.5)
		text := ui.box("text", text_look, placeholder if shown == "" else shown)

		if marked[0] >= 0 && len(shaped.lines) > 0 {
			left := font.caret_x(shaped.lines[0], font.to_utf16_index(shown, marked[0])) / pixels
			right := font.caret_x(shaped.lines[0], font.to_utf16_index(shown, marked[1])) / pixels
			ui.box("", {width = ui.points(right - left), height = ui.points(1), background = colors.base_content, position = {left, text.rect.w - text.rect.y - 1}, flags = {.Floating}})
		}

		if is_focused {
			at := input.caret + (marked[1] - marked[0] if marked[0] >= 0 else 0)
			left: f32
			if len(shaped.lines) > 0 do left = font.caret_x(shaped.lines[0], font.to_utf16_index(shown, at)) / pixels
			height := text.rect.w - text.rect.y
			ui.box("", {width = ui.points(1.5), height = ui.points(height), background = colors.primary, position = {left, 0}, flags = {.Floating}})
			// Only real focus moves the input method window, never a forced state.
			if input.is_focused {
				_window.caret_rect = ui._to_window_points([4]f32{line.rect.x + left, line.rect.y, line.rect.x + left + 2, line.rect.y + height})
			}
		}

		// After the first press, only a drag moves the caret, so keys can move it during a hold.
		_, is_press := ui._pressed_at()
		if signal.is_held && box.forced == .None && (is_press || signal.is_dragged) {
			offset := 0
			if len(shaped.lines) > 0 {
				x := (ui.mouse_position().x - line.rect.x) * pixels
				offset = font.to_byte_index(shown, font.index_at_x(shaped.lines[0], x))
			}
			_apply_field_pointer(input, min(offset, len(input.text)))
		}
	}

	signal.is_changed = input.is_changed
	return signal
}

// One press places the caret, two select a word, three select all; a drag extends in that unit.
_apply_field_pointer :: proc(input: ^Text_Input, offset: int) {
	_, is_press := ui._pressed_at()
	if is_press {
		count, is_shifted := 1, false
		for event in platform.list_events() {
			if press, ok := event.(platform.Mouse_Press); ok {
				count = clamp(press.click_count, 1, 3)
				is_shifted = .Shift in press.modifiers
			}
		}
		input._drag_unit = count
		switch {
		case is_shifted:
			input.caret = offset
		case count == 2:
			input.anchor, input.caret = _to_word_range(input, offset)
		case count == 3:
			input.anchor, input.caret = 0, len(input.text)
		case:
			input.anchor, input.caret = offset, offset
		}
		input._drag_origin = _to_selection(input)
	} else if input._drag_unit == 1 {
		input.caret = offset
	} else if input._drag_unit == 2 {
		start, end := _to_word_range(input, offset)
		origin := input._drag_origin
		if offset < origin[0] {
			input.anchor, input.caret = origin[1], start
		} else {
			input.anchor, input.caret = origin[0], max(end, origin[1])
		}
	}
	input._moved_at = platform.now()
	ui.request_frame()
}
