package kit

import "../font"
import "../platform"
import "../ui"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode"
import "core:unicode/utf8"

_EDITOR_PADDING_POINTS :: 8
_EDITOR_FONT_SIZE :: 13
_EDITOR_BLINK_SECONDS :: 0.5
// The width of the selection over a line break.
_EDITOR_EMPTY_SELECTION_POINTS :: 6
_EDITOR_GUTTER_GAP_POINTS :: 12

// The app keeps it outside its frame procedure. Kit owns the fields after step.
Text_Input :: struct {
	text:                 [dynamic]u8,
	// Byte offsets: where the selection began, and the caret. They are equal with no selection.
	anchor:               int,
	caret:                int,
	// The text that the input method composes. It shows at the caret until the person confirms it.
	marked:               string,
	is_focused:           bool,
	// True on the frame that the text changed, the person pressed Return in a field, or Escape.
	is_changed:           bool,
	is_submitted:         bool,
	is_cancelled:         bool,
	// A field that keeps the keyboard when the person clicks elsewhere.
	is_keeping_focus:     bool,
	// Up and Down set step to -1 or 1 for a list beside the field, and do not move the caret.
	is_taking_up_down:    bool,
	step:                 int,
	_history:             _History,
	_is_hovered:          bool,
	_is_multiline:        bool,
	// Byte offsets of the line starts. Kit builds them again after a change.
	_line_starts:         [dynamic]int,
	_is_line_stale:       bool,
	// The x, in pixels, that Up and Down keep while they move the caret.
	_goal_x:              f32,
	_has_goal:            bool,
	// Line and page moves wait for the build, which has the shapes of the lines.
	_moved_lines:         int,
	_moved_pages:         int,
	_is_moving_selection: bool,
	// The keyboard or typing moved the caret, so the view scrolls to it.
	_is_caret_moved:      bool,
	// When the caret last moved. It stays steady for a moment after a move.
	_moved_at:            time.Tick,
	// A drag selects by characters (1), words (2) or lines (3), from what the press selected.
	_drag_unit:           int,
	_drag_origin:         [2]int,
}

// A run of the text in one colour, from a highlighter that the app runs.
Span :: struct {
	range: [2]int,
	color: [4]f32,
}

_Line_Paint :: struct {
	shown:      string,
	line_start: int,
	// The range of the input method's text in shown. No span colours it.
	marked:     [2]int,
	is_ascii:   bool,
	spans:      []Span,
	color:      [4]f32,
}

// A line that kit built this frame. Clicks use it.
_Built_Line :: struct {
	index:   int,
	content: ^ui.Box,
	shaped:  ^font.Shaped_Text,
	shown:   string,
}

// The text of the input. Typing changes it, so copy it to keep it.
to_input_text :: proc(input: ^Text_Input) -> string {
	return string(input.text[:])
}

// ⌘Z cannot undo this change. The caret goes to the end of the text.
set_input_text :: proc(input: ^Text_Input, text: string) {
	_clear_edits(&input._history.undo)
	_clear_edits(&input._history.redo)
	clear(&input.text)
	append(&input.text, text)
	input.anchor, input.caret = len(input.text), len(input.text)
	input._is_line_stale = true
}

// Frees the input's text and history.
destroy_input :: proc(input: ^Text_Input) {
	delete(input.text)
	delete(input._line_starts)
	delete(input.marked)
	_destroy_history(&input._history)
	input^ = {}
}

// Tab types a tab, and Ctrl-Tab moves the focus on. A zero height in style fills the parent.
text_editor :: proc(
	id: string,
	input: ^Text_Input,
	spans: []Span = nil,
	is_monospace := false,
	has_line_numbers := false,
	style: ui.Style = {},
) -> ui.Signal {
	if !slice.contains(_window.inputs[:], input) do append(&_window.inputs, input)
	input._is_multiline = true

	is_focused := input.is_focused if ui.forced_state == .None else ui.forced_state == .Focus
	base := ui.Style {
		width            = ui.fill(),
		height           = ui.fill(),
		axis             = .Y,
		padding          = _EDITOR_PADDING_POINTS,
		corner_radius    = shape.radius_field,
		background       = with_opacity(colors.base_content, HOVER_OPACITY),
		hover_background = with_opacity(colors.base_content, HOVER_OPACITY),
		font_size        = _EDITOR_FONT_SIZE,
		font_family      = .Mono if is_monospace else .System,
		cursor           = .I_Beam,
		flags            = {.Clickable, .No_Focus_Ring, .Scroll, .Clip, .Keeps_Tab},
	}
	look := ui.merge(base, style)
	look.border_width = shape.border if is_focused else 0
	look.border_color = with_opacity(colors.primary, _FOCUS_BORDER_ALPHA)
	box := ui.box(id, look)
	box.role, box.label = .Text_Field, id
	box.value = to_input_text(input) if len(input.text) <= 200 else fmt.tprintf("%d bytes", len(input.text))

	signal := ui.signal(box)
	input._is_hovered = signal.is_hovered && box.forced == .None
	if box.forced == .None do _follow_input_focus(input, box, signal.is_focused)

	line_height := to_line_height(look.font_size)
	if line_height == 0 do line_height = math.ceil(look.font_size * 1.4)
	starts := _to_line_starts(input)
	gutter: f32
	if has_line_numbers {
		digits := strings.repeat("0", len(fmt.tprint(len(starts))), context.temp_allocator)
		gutter = _measure(digits, look) + _EDITOR_GUTTER_GAP_POINTS
	}
	text_width := max(0, box.size.x - look.padding.x - look.padding.z - gutter)
	text_look := ui.Style {
		width       = ui.fill(),
		height      = ui.fit_text(),
		min_size    = {0, line_height},
		font_size   = look.font_size,
		font_family = look.font_family,
		line_height = line_height,
		flags       = {.Wrap_Text},
	}
	shaper := _Shaper{ui._read_font(text_look), text_width, line_height}

	_resolve_vertical_move(input, shaper, box.size.y)

	built := make([dynamic]_Built_Line, context.temp_allocator)
	selection := _to_selection(input)
	if ui.scope(box) {
		if first, last, ok := list("lines", len(starts), MEASURED, {}, line_height); ok {
			for index in first ..< last {
				row := ui.box(fmt.tprint(index), {width = ui.fill(), axis = .X})
				ui.push_parent(row)
				if has_line_numbers {
					number_look := text_look
					number_look.width = ui.points(gutter)
					number_look.text_align = .End
					number_look.padding = {0, 0, _EDITOR_GUTTER_GAP_POINTS, 0}
					number_look.text_color = with_opacity(colors.base_content, 0.35)
					number_look.flags = {}
					ui.box("", number_look, fmt.tprint(index + 1))
				}
				append(&built, _build_line(input, index, shaper, text_look, spans, selection, is_focused))
				ui.pop_parent()
			}
		}
	}

	if signal.is_held && box.forced == .None do _apply_pointer(input, built[:], shaper)
	if input._is_caret_moved do _scroll_to_caret(input, box, built[:], shaper)

	if is_focused && input.is_focused && platform.is_key_window() {
		// The caret blinks, and shows steady for a moment after it moves.
		seconds := time.duration_seconds(time.tick_diff(input._moved_at, platform.now()))
		ui.request_frame_after(_EDITOR_BLINK_SECONDS - math.mod(seconds, _EDITOR_BLINK_SECONDS))
	}

	signal.is_changed = input.is_changed
	return signal
}

_Shaper :: struct {
	font:        font.Font,
	// In points. It is 0 before the first layout, and then no line wraps.
	width:       f32,
	line_height: f32,
}

_shape :: proc(shaper: _Shaper, text: string) -> ^font.Shaped_Text {
	pixels := ui.to_pixels(1)

	return font.shape_text(text, shaper.font, shaper.width * pixels, .Wrap, shaper.line_height * pixels)
}

_measure :: proc(text: string, look: ui.Style) -> f32 {
	shaped := font.shape_text(text, ui._read_font(look))

	return math.ceil(shaped.size_pixels.x / ui.to_pixels(1))
}

// The line's text with the input method's text at the caret, and the range of that text.
_to_shown_line :: proc(input: ^Text_Input, index: int, is_focused: bool) -> (shown: string, marked: [2]int) {
	start, end := _to_line_range(input, index)
	text := string(input.text[start:end])
	marked = {-1, -1}
	if !is_focused || input.marked == "" || input.caret < start || input.caret > end do return text, marked

	at := input.caret - start
	shown = strings.concatenate({text[:at], input.marked, text[at:]}, context.temp_allocator)

	return shown, {at, at + len(input.marked)}
}

_build_line :: proc(
	input: ^Text_Input,
	index: int,
	shaper: _Shaper,
	text_look: ui.Style,
	spans: []Span,
	selection: [2]int,
	is_focused: bool,
) -> _Built_Line {
	start, end := _to_line_range(input, index)
	shown, marked := _to_shown_line(input, index, is_focused)
	shaped := _shape(shaper, shown)
	pixels := ui.to_pixels(1)
	content := ui.box("content", {width = ui.fill(), axis = .Y})
	ui.push_parent(content)
	defer ui.pop_parent()

	// The selection goes under the text. A selection that runs past the line also covers its end.
	if selection[0] != selection[1] && selection[0] <= end && selection[1] >= start {
		from := font.to_utf16_index(shown, max(selection[0], start) - start)
		to := font.to_utf16_index(shown, min(selection[1], end) - start)
		runs_on := selection[1] > end
		color := with_opacity(colors.primary, SOFT_OPACITY if is_focused else HOVER_OPACITY)
		if len(shaped.lines) == 0 && runs_on {
			ui.box("", {width = ui.points(_EDITOR_EMPTY_SELECTION_POINTS), height = ui.points(shaper.line_height), background = color, flags = {.Floating}})
		}
		for line, visual in shaped.lines {
			if to < line.utf16_range[0] || from > line.utf16_range[1] do continue

			left := font.caret_x(line, max(from, line.utf16_range[0])) / pixels
			right := font.caret_x(line, min(to, line.utf16_range[1])) / pixels
			is_last := visual == len(shaped.lines) - 1
			if runs_on && is_last do right = max(right + _EDITOR_EMPTY_SELECTION_POINTS, left)
			if right <= left do continue

			top := f32(visual) * shaper.line_height
			ui.box("", {width = ui.points(right - left), height = ui.points(shaper.line_height), background = color, position = {left, top}, flags = {.Floating}})
		}
	}

	look := text_look
	paint := new(_Line_Paint, context.temp_allocator)
	paint^ = {
		shown      = shown,
		line_start = start,
		marked     = marked,
		is_ascii   = len(shown) == utf8.rune_count_in_string(shown),
		color      = colors.base_content,
	}
	for span in spans {
		if span.range[1] > start && span.range[0] < end {
			if paint.spans == nil do paint.spans = make([]Span, 0, context.temp_allocator)
			paint.spans = _append_span(paint.spans, span)
		}
	}
	text_box := ui.box("text", look, shown)
	if len(paint.spans) > 0 {
		text_box.color_of = _to_span_color
		text_box.data = paint
	}

	// A line under the input method's text.
	if marked[0] >= 0 {
		for line in shaped.lines {
			from := font.to_utf16_index(shown, marked[0])
			to := font.to_utf16_index(shown, marked[1])
			if to <= line.utf16_range[0] || from >= line.utf16_range[1] do continue
			left := font.caret_x(line, max(from, line.utf16_range[0])) / pixels
			right := font.caret_x(line, min(to, line.utf16_range[1])) / pixels
			top := line.baseline_y_pixels / pixels + 2
			ui.box("", {width = ui.points(right - left), height = ui.points(1), background = colors.base_content, position = {left, top}, flags = {.Floating}})
		}
	}

	is_caret_here := input.caret >= start && input.caret <= end
	if is_focused && is_caret_here && _is_caret_shown(input) {
		at := input.caret - start + (marked[1] - marked[0] if marked[0] >= 0 else 0)
		left, top := _to_caret_place(shaped, shown, at, shaper.line_height)
		ui.box("", {width = ui.points(1.5), height = ui.points(shaper.line_height), background = colors.primary, position = {left, top}, flags = {.Floating}})
		if input.is_focused {
			_window.caret_rect = ui._to_window_points([4]f32{content.rect.x + left, content.rect.y + top, content.rect.x + left + 2, content.rect.y + top + shaper.line_height})
		}
	}

	return {index, content, shaped, shown}
}

// Spans come in any order and can be many. Each line keeps only the spans it overlaps.
_append_span :: proc(spans: []Span, span: Span) -> []Span {
	grown := make([]Span, len(spans) + 1, context.temp_allocator)
	copy(grown, spans)
	grown[len(spans)] = span

	return grown
}

_to_span_color :: proc(utf16_index: int, data: rawptr) -> [4]f32 {
	paint := cast(^_Line_Paint)data
	at := utf16_index if paint.is_ascii else font.to_byte_index(paint.shown, utf16_index)
	if paint.marked[0] >= 0 {
		if at >= paint.marked[0] && at < paint.marked[1] do return paint.color
		if at >= paint.marked[1] do at -= paint.marked[1] - paint.marked[0]
	}
	offset := paint.line_start + at
	color := paint.color
	for span in paint.spans {
		if offset >= span.range[0] && offset < span.range[1] do color = span.color
	}

	return color
}

// The caret before byte at, in points from the top left. At a wrap, it starts the next line.
_to_caret_place :: proc(shaped: ^font.Shaped_Text, shown: string, at: int, line_height: f32) -> (left, top: f32) {
	if len(shaped.lines) == 0 do return 0, 0

	index := font.to_utf16_index(shown, at)
	visual := len(shaped.lines) - 1
	for line, place in shaped.lines {
		if index < line.utf16_range[1] {
			visual = place
			break
		}
	}

	return font.caret_x(shaped.lines[visual], index) / ui.to_pixels(1), f32(visual) * line_height
}

_is_caret_shown :: proc(input: ^Text_Input) -> bool {
	if !platform.is_key_window() do return false

	seconds := time.duration_seconds(time.tick_diff(input._moved_at, platform.now()))

	return int(seconds / _EDITOR_BLINK_SECONDS) % 2 == 0
}

// The byte offset of the caret place nearest point, among the lines that kit built this frame.
_to_offset_at :: proc(input: ^Text_Input, built: []_Built_Line, point: [2]f32, shaper: _Shaper) -> int {
	if len(built) == 0 do return len(input.text)

	line := built[len(built) - 1]
	for candidate in built {
		if point.y < candidate.content.rect.w {
			line = candidate
			break
		}
	}
	start, _ := _to_line_range(input, line.index)
	if len(line.shaped.lines) == 0 do return start

	local := point - {line.content.rect.x, line.content.rect.y}
	visual := clamp(int(local.y / shaper.line_height), 0, len(line.shaped.lines) - 1)
	if point.y < built[0].content.rect.y do visual = 0
	index := font.index_at_x(line.shaped.lines[visual], local.x * ui.to_pixels(1))

	return start + font.to_byte_index(line.shown, index)
}

_apply_pointer :: proc(input: ^Text_Input, built: []_Built_Line, shaper: _Shaper) {
	offset := _to_offset_at(input, built, ui.mouse_position(), shaper)
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
			line := _to_line_of(input, offset)
			input.anchor, input.caret = _to_line_range_with_break(input, line)
		case:
			input.anchor, input.caret = offset, offset
		}
		input._drag_origin = _to_selection(input)
	} else {
		origin := input._drag_origin
		unit_range := [2]int{offset, offset}
		switch input._drag_unit {
		case 2:
			unit_range[0], unit_range[1] = _to_word_range(input, offset)
		case 3:
			unit_range[0], unit_range[1] = _to_line_range_with_break(input, _to_line_of(input, offset))
		}
		if offset < origin[0] {
			input.anchor, input.caret = origin[1], unit_range[0]
		} else {
			input.anchor, input.caret = origin[0], max(unit_range[1], origin[1])
		}
	}
	input._has_goal = false
	input._moved_at = platform.now()
	// Kit built the selection above from the old one.
	ui.request_frame()
}

_scroll_to_caret :: proc(input: ^Text_Input, box: ^ui.Box, built: []_Built_Line, shaper: _Shaper) {
	input._is_caret_moved = false
	view_top := box.rect.y + box.style.padding.y
	view_bottom := box.rect.w - box.style.padding.w
	if view_bottom <= view_top do return

	line := _to_line_of(input, input.caret)
	for candidate in built {
		if candidate.index != line do continue

		start, _ := _to_line_range(input, line)
		_, top := _to_caret_place(candidate.shaped, candidate.shown, input.caret - start, shaper.line_height)
		caret_top := candidate.content.rect.y + top
		caret_bottom := caret_top + shaper.line_height
		if caret_top < view_top do ui.set_scroll(box, box.scroll - (view_top - caret_top))
		if caret_bottom > view_bottom do ui.set_scroll(box, box.scroll + (caret_bottom - view_bottom))
		ui.request_frame()
		return
	}

	// The line is off screen: put its estimated top in the middle of the view.
	list_box := ui.find_box("lines", box)
	estimated := f32(line) * shaper.line_height
	if list_box != nil {
		if kept := _window.lists[list_box._key] or_else nil; kept != nil {
			estimated = 0
			for height, index in kept.heights {
				if index >= line do break
				estimated += height if height > 0 else shaper.line_height
			}
		}
	}
	ui.set_scroll(box, estimated - (view_bottom - view_top) / 2)
	input._is_caret_moved = true
	ui.request_frame()
}

// Up, Down, Page Up and Page Down move the caret here, because they need the shapes of the lines.
_resolve_vertical_move :: proc(input: ^Text_Input, shaper: _Shaper, view_height: f32) {
	lines := input._moved_lines
	if input._moved_pages != 0 {
		page := max(1, int(view_height / shaper.line_height) - 1)
		lines += input._moved_pages * page
	}
	if lines == 0 do return

	input._moved_lines, input._moved_pages = 0, 0
	line := _to_line_of(input, input.caret)
	start, _ := _to_line_range(input, line)
	shown, _ := _to_shown_line(input, line, false)
	shaped := _shape(shaper, shown)
	pixels := ui.to_pixels(1)
	caret_left, caret_top := _to_caret_place(shaped, shown, input.caret - start, shaper.line_height)
	if !input._has_goal {
		input._goal_x = caret_left * pixels
		input._has_goal = true
	}
	visual := int(caret_top / shaper.line_height)

	step := 1 if lines > 0 else -1
	offset := input.caret
	for _ in 0 ..< abs(lines) {
		visual += step
		count := max(1, len(shaped.lines))
		if visual < 0 || visual >= count {
			line += step
			if line < 0 {
				offset = 0
				break
			}
			if line >= len(input._line_starts) {
				offset = len(input.text)
				break
			}
			shown, _ = _to_shown_line(input, line, false)
			shaped = _shape(shaper, shown)
			start, _ = _to_line_range(input, line)
			visual = 0 if step > 0 else max(0, len(shaped.lines) - 1)
		}
		if len(shaped.lines) == 0 {
			offset = start
		} else {
			index := font.index_at_x(shaped.lines[visual], input._goal_x)
			// The end of a wrapped line is the start of the next one. Stay on this line.
			if visual < len(shaped.lines) - 1 && index >= shaped.lines[visual].utf16_range[1] do index -= 1
			offset = start + font.to_byte_index(shown, index)
		}
	}

	input.caret = offset
	if !input._is_moving_selection do input.anchor = offset
	input._is_caret_moved = true
	input._moved_at = platform.now()
}

_follow_input_focus :: proc(input: ^Text_Input, box: ^ui.Box, has_ui_focus: bool) {
	switch {
	case _window.focus_request == input:
		ui.focus(box)
		_window.focus_request = nil
	case has_ui_focus && !input.is_focused:
		_take_keyboard(input)
		ui.request_frame()
	case !has_ui_focus && input.is_focused && !input.is_keeping_focus:
		input.is_focused = false
		delete(input.marked)
		input.marked = ""
		ui.request_frame()
	}
}

_take_keyboard :: proc(input: ^Text_Input) {
	for other in _window.inputs do other.is_focused = false
	input.is_focused = true
	input._moved_at = platform.now()
}

_find_focused_input :: proc() -> (^Text_Input, bool) {
	for input in _window.inputs do if input.is_focused do return input, true

	return nil, false
}

_to_line_starts :: proc(input: ^Text_Input) -> []int {
	if input._is_line_stale || len(input._line_starts) == 0 {
		clear(&input._line_starts)
		append(&input._line_starts, 0)
		for byte, at in input.text {
			if byte == '\n' do append(&input._line_starts, at + 1)
		}
		input._is_line_stale = false
	}

	return input._line_starts[:]
}

// The line's bytes, without its line break.
_to_line_range :: proc(input: ^Text_Input, line: int) -> (start, end: int) {
	starts := _to_line_starts(input)
	start = starts[line]
	end = starts[line + 1] - 1 if line + 1 < len(starts) else len(input.text)

	return
}

_to_line_range_with_break :: proc(input: ^Text_Input, line: int) -> (start, end: int) {
	starts := _to_line_starts(input)

	return starts[line], starts[line + 1] if line + 1 < len(starts) else len(input.text)
}

_to_line_of :: proc(input: ^Text_Input, offset: int) -> int {
	starts := _to_line_starts(input)
	index, _ := slice.binary_search(starts, offset)
	// binary_search gives the insert place. A start that equals offset begins the line.
	if index < len(starts) && starts[index] == offset do return index

	return max(0, index - 1)
}

_to_selection :: proc(input: ^Text_Input) -> [2]int {
	return {min(input.anchor, input.caret), max(input.anchor, input.caret)}
}

_is_word_rune :: proc(letter: rune) -> bool {
	return unicode.is_letter(letter) || unicode.is_digit(letter) || letter == '_'
}

_to_word_range :: proc(input: ^Text_Input, offset: int) -> (start, end: int) {
	text := to_input_text(input)
	start, end = offset, offset
	for start > 0 {
		letter, size := utf8.decode_last_rune_in_string(text[:start])
		if !_is_word_rune(letter) do break
		start -= size
	}
	for end < len(text) {
		letter, size := utf8.decode_rune_in_string(text[end:])
		if !_is_word_rune(letter) do break
		end += size
	}
	if start == end && end < len(text) {
		_, size := utf8.decode_rune_in_string(text[end:])
		end += size
	}

	return
}

_to_previous_word :: proc(input: ^Text_Input, offset: int) -> int {
	text := to_input_text(input)
	at := offset
	for at > 0 {
		letter, size := utf8.decode_last_rune_in_string(text[:at])
		if _is_word_rune(letter) do break
		at -= size
	}
	for at > 0 {
		letter, size := utf8.decode_last_rune_in_string(text[:at])
		if !_is_word_rune(letter) do break
		at -= size
	}

	return at
}

_to_next_word :: proc(input: ^Text_Input, offset: int) -> int {
	text := to_input_text(input)
	at := offset
	for at < len(text) {
		letter, size := utf8.decode_rune_in_string(text[at:])
		if _is_word_rune(letter) do break
		at += size
	}
	for at < len(text) {
		letter, size := utf8.decode_rune_in_string(text[at:])
		if !_is_word_rune(letter) do break
		at += size
	}

	return at
}

_to_previous_rune :: proc(input: ^Text_Input, offset: int) -> int {
	if offset <= 0 do return 0
	_, size := utf8.decode_last_rune(input.text[:offset])

	return offset - size
}

_to_next_rune :: proc(input: ^Text_Input, offset: int) -> int {
	if offset >= len(input.text) do return len(input.text)
	_, size := utf8.decode_rune(input.text[offset:])

	return offset + size
}

// Keeps the change in the undo history.
_edit :: proc(input: ^Text_Input, start, end: int, text: string, is_typing: bool) {
	before := [2]int{input.anchor, input.caret}
	caret := _replace_text(&input._history, &input.text, start, end, text, before, is_typing)
	input.anchor, input.caret = caret, caret
	_after_change(input)
}

_after_change :: proc(input: ^Text_Input) {
	input.is_changed = true
	input._is_line_stale = true
	input._has_goal = false
	input._is_caret_moved = true
	input._moved_at = platform.now()
}

_move_caret :: proc(input: ^Text_Input, offset: int, is_selecting: bool) {
	input.caret = clamp(offset, 0, len(input.text))
	if !is_selecting do input.anchor = input.caret
	input._has_goal = false
	input._is_caret_moved = true
	input._moved_at = platform.now()
}

_delete_toward :: proc(input: ^Text_Input, to: int) {
	selection := _to_selection(input)
	if selection[0] != selection[1] {
		_edit(input, selection[0], selection[1], "", false)
		return
	}
	_edit(input, min(input.caret, to), max(input.caret, to), "", true)
}

_apply_input_event :: proc(input: ^Text_Input, event: platform.Event) {
	selection := _to_selection(input)
	#partial switch typed in event {
	case platform.Text_Insert:
		delete(input.marked)
		input.marked = ""
		// Return comes as a command, never as text.
		if typed.text != "\r" && typed.text != "\n" do _edit(input, selection[0], selection[1], typed.text, true)
	case platform.Text_Marked:
		if selection[0] != selection[1] do _edit(input, selection[0], selection[1], "", false)
		delete(input.marked)
		input.marked = strings.clone(typed.text)
	case platform.Text_Command:
		_apply_input_command(input, typed.name)
	case platform.Key_Press:
		if .Command not_in typed.modifiers do return

		// ⌘ with an arrow comes as a key press, because the input method gets no ⌘ keys.
		is_selecting := .Shift in typed.modifiers
		line_start, line_end := _to_line_range(input, _to_line_of(input, input.caret))
		#partial switch typed.key {
		case .Left:
			_move_caret(input, line_start, is_selecting)
		case .Right:
			_move_caret(input, line_end, is_selecting)
		case .Up:
			_move_caret(input, 0, is_selecting)
		case .Down:
			_move_caret(input, len(input.text), is_selecting)
		}

		switch typed.characters {
		case "a":
			input.anchor, input.caret = 0, len(input.text)
		case "c", "x":
			if selection[0] == selection[1] do return
			platform.set_clipboard(string(input.text[selection[0]:selection[1]]))
			if typed.characters == "x" do _edit(input, selection[0], selection[1], "", false)
		case "v":
			pasted := platform.read_clipboard()
			// A field with one line joins the lines of the clipboard.
			if !input._is_multiline {
				lines, _ := strings.replace_all(strings.trim_space(pasted), "\n", " ", context.temp_allocator)
				pasted = lines
			}
			_edit(input, selection[0], selection[1], pasted, false)
		case "z", "Z":
			kept: [2]int
			ok: bool
			if typed.characters == "Z" {
				kept, ok = _redo(&input._history, &input.text)
			} else {
				kept, ok = _undo(&input._history, &input.text)
			}
			if !ok do return
			input.anchor, input.caret = kept[0], kept[1]
			_after_change(input)
		}
	}
}

_apply_input_command :: proc(input: ^Text_Input, name: string) {
	is_selecting := strings.has_suffix(name, "AndModifySelection:")
	base := strings.trim_suffix(strings.trim_suffix(name, ":"), "AndModifySelection")
	selection := _to_selection(input)
	has_selection := selection[0] != selection[1]
	line_start, line_end := _to_line_range(input, _to_line_of(input, input.caret))

	switch base {
	case "moveLeft", "moveBackward":
		_move_caret(input, selection[0] if has_selection && !is_selecting else _to_previous_rune(input, input.caret), is_selecting)
	case "moveRight", "moveForward":
		_move_caret(input, selection[1] if has_selection && !is_selecting else _to_next_rune(input, input.caret), is_selecting)
	case "moveWordLeft", "moveWordBackward":
		_move_caret(input, _to_previous_word(input, input.caret), is_selecting)
	case "moveWordRight", "moveWordForward":
		_move_caret(input, _to_next_word(input, input.caret), is_selecting)
	case "moveToBeginningOfLine", "moveToLeftEndOfLine", "moveToBeginningOfParagraph", "moveParagraphBackward":
		_move_caret(input, line_start, is_selecting)
	case "moveToEndOfLine", "moveToRightEndOfLine", "moveToEndOfParagraph", "moveParagraphForward":
		_move_caret(input, line_end, is_selecting)
	case "moveToBeginningOfDocument", "scrollToBeginningOfDocument":
		_move_caret(input, 0, is_selecting)
	case "moveToEndOfDocument", "scrollToEndOfDocument":
		_move_caret(input, len(input.text), is_selecting)
	case "moveUp", "moveDown", "pageUp", "pageDown", "scrollPageUp", "scrollPageDown":
		direction := -1 if base == "moveUp" || base == "pageUp" || base == "scrollPageUp" else 1
		switch {
		case input._is_multiline && (base == "moveUp" || base == "moveDown"):
			input._moved_lines += direction
			input._is_moving_selection = is_selecting
		case input._is_multiline:
			input._moved_pages += direction
			input._is_moving_selection = is_selecting
		case input.is_taking_up_down && !is_selecting && (base == "moveUp" || base == "moveDown"):
			input.step = direction
		case:
			_move_caret(input, 0 if direction < 0 else len(input.text), is_selecting)
		}
	case "deleteBackward":
		_delete_toward(input, _to_previous_rune(input, input.caret))
	case "deleteForward":
		_delete_toward(input, _to_next_rune(input, input.caret))
	case "deleteWordBackward":
		_delete_toward(input, _to_previous_word(input, input.caret))
	case "deleteWordForward":
		_delete_toward(input, _to_next_word(input, input.caret))
	case "deleteToBeginningOfLine":
		_delete_toward(input, line_start)
	case "deleteToEndOfLine", "deleteToEndOfParagraph":
		_delete_toward(input, line_end if input.caret < line_end else _to_next_rune(input, input.caret))
	case "insertNewline", "insertLineBreak", "insertParagraphSeparator":
		if input._is_multiline {
			_edit(input, selection[0], selection[1], "\n", true)
		} else {
			input.is_submitted = true
		}
	case "insertTab":
		if input._is_multiline do _edit(input, selection[0], selection[1], "\t", true)
	case "cancelOperation":
		if input._is_multiline do return
		input.is_cancelled = true
		input.is_focused = false
		ui.focus(nil)
	case "selectAll":
		input.anchor, input.caret = 0, len(input.text)
	}
}
