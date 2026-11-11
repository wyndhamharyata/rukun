package kit

import "../platform"
import "../ui"
import "core:fmt"

_RESIZE_GRAB_POINTS :: 8
_RESIZE_KEY_STEP_POINTS :: 10

_TABLE_HEADER_POINTS :: 28
_TABLE_MIN_COLUMN_POINTS :: 60
_CELL_PADDING_POINTS :: 12
// The same height as a list_row.
_TABLE_ROW_POINTS :: 34

// The box that owns the size: Before for a left sidebar, After for a right one.
Side :: enum {
	Before,
	After,
}

// Sets size^, the pane's width (.X) or height (.Y) in points, by a drag or an arrow key with focus.
resize_handle :: proc(id: string, size: ^f32, range: [2]f32, axis := ui.Axis.X, side := Side.Before) -> ui.Signal {
	is_across := axis == .X
	line := ui.box(
		id,
		{
			width = ui.points(1) if is_across else ui.fill(),
			height = ui.fill() if is_across else ui.points(1),
		},
	)
	offset: f32 = -(_RESIZE_GRAB_POINTS - 1) / 2.0
	grab_look := ui.Style {
		width    = ui.points(_RESIZE_GRAB_POINTS) if is_across else ui.fill(),
		height   = ui.fill() if is_across else ui.points(_RESIZE_GRAB_POINTS),
		position = {offset, 0} if is_across else {0, offset},
		cursor   = .Resize_Left_Right if is_across else .Resize_Up_Down,
		// Focus shows in the line's colour.
		flags    = {.Floating, .Clickable, .No_Focus_Ring},
	}
	ui.push_parent(line)
	grab := ui.box("grab", grab_look)
	ui.pop_parent()

	signal := ui.signal(grab)
	sign: f32 = 1 if side == .Before else -1
	_drag(grab, signal, size, axis, sign)
	if signal.is_focused && grab.forced == .None {
		keys := [2]platform.Key{.Left, .Right} if is_across else {.Up, .Down}
		for key, index in keys {
			if !ui.is_key_pressed(key) || ui.is_key_taken(key) do continue

			size^ += _RESIZE_KEY_STEP_POINTS * sign * (-1 if index == 0 else 1)
			ui._state.taken_keys += {int(key)}
		}
	}
	size^ = clamp(size^, range[0], range[1])

	is_active := signal.is_held || signal.is_focused || grab._hot_fraction > 0.5
	line.style.background = colors.primary if is_active else to_faded(colors.base_content, LINE_OPACITY)
	grab.role, grab.label, grab.value = .Splitter, id, fmt.tprintf("%.0f", size^)

	return signal
}

// While the person holds the box, size^ follows the pointer along axis from where the press began.
_drag :: proc(box: ^ui.Box, signal: ui.Signal, size: ^f32, axis: ui.Axis, sign: f32) {
	if box.forced != .None do return
	if !signal.is_held {
		if _window.drag._key == box._key do _window.drag = {}
		return
	}

	if _window.drag._key != box._key do _window.drag = {box._key, size^}
	side := ui._axis_index(axis)
	dragged := _window.drag.start + (ui.mouse_position()[side] - ui.interaction().start[side]) * sign
	if dragged != size^ {
		size^ = dragged
		// The boxes before this one used the old size.
		ui.request_frame()
	}
}

Column :: struct {
	// The id that cell takes and Sort.column keeps.
	id:        string,
	title:     string,
	// In points. A drag on the header edge sets it. Zero takes the space the other columns leave.
	width:     f32,
	// _TABLE_MIN_COLUMN_POINTS when zero.
	min_width: f32,
}

Sort :: struct {
	// The id of the column the rows sort by.
	column:        string,
	is_descending: bool,
	// True on the frame a header click changed it, so the app sorts its rows again.
	is_changed:    bool,
}

_Placed_Column :: struct {
	id:       string,
	title:    string,
	x, width: f32,
}

// Each row is a list_row of cells. The app sorts its rows when sort.is_changed.
@(deferred_out = _end_table)
table :: proc(
	id: string,
	columns: []Column,
	count: int,
	sort: ^Sort = nil,
	row_height: f32 = _TABLE_ROW_POINTS,
) -> (
	first, last: int,
	ok: bool,
) {
	if sort != nil do sort.is_changed = false
	// The width of the last frame. On the first frame, the columns take their own widths.
	last_box := ui.find_box(id, ui.current_parent())
	placed := _place_columns(columns, last_box.size.x if last_box != nil else 0)

	ui.push_parent(ui.box(id, {width = ui.fill(), height = ui.fill(), axis = .Y}))
	if ui.scope(ui.box("header", {width = ui.fill(), height = ui.points(_TABLE_HEADER_POINTS)})) {
		for column in placed do _build_column_title(column, sort)
		for index in 0 ..< len(placed) - 1 do _build_column_edge(&columns[index], placed[index])
	}
	divider()
	_window.columns = placed

	return _begin_list("rows", count, row_height, {}, 40, false)
}

_end_table :: proc(first, last: int, ok: bool) {
	_end_list(first, last, ok)
	ui.pop_parent()
	_window.columns = nil
}

// Kit places the cell under the column with this id, in any build order.
@(deferred_none = ui.pop_parent)
cell :: proc(column_id: string) -> bool {
	placed: _Placed_Column
	for candidate in _window.columns {
		if candidate.id == column_id do placed = candidate
	}
	if placed.width == 0 do ui._warn(ui.current_parent(), "the table has no column with the id \"%s\".", column_id)

	look := ui.Style {
		width    = ui.points(placed.width),
		height   = ui.fill(),
		axis     = .X,
		align    = .Center,
		gap      = 8,
		padding  = {_CELL_PADDING_POINTS, 0, _CELL_PADDING_POINTS, 0},
		position = {placed.x, 0},
		flags    = {.Floating, .Clip},
	}
	ui.push_parent(ui.box("", look))

	return true
}

// In the temp allocator. Columns of zero width share the space that the others leave.
_place_columns :: proc(columns: []Column, width: f32) -> []_Placed_Column {
	fixed: f32
	fill_count := 0
	for column in columns {
		if column.width > 0 do fixed += column.width
		else do fill_count += 1
	}
	fill_width := max(0, width - fixed) / f32(max(1, fill_count))

	placed := make([]_Placed_Column, len(columns), context.temp_allocator)
	x: f32
	for column, index in columns {
		least := column.min_width if column.min_width > 0 else _TABLE_MIN_COLUMN_POINTS
		column_width := max(column.width if column.width > 0 else fill_width, least)
		placed[index] = {column.id, column.title, x, column_width}
		x += column_width
	}

	return placed
}

_build_column_title :: proc(column: _Placed_Column, sort: ^Sort) {
	is_sorted := sort != nil && sort.column == column.id
	look := ui.Style {
		width            = ui.points(column.width),
		height           = ui.fill(),
		axis             = .X,
		align            = .Center,
		gap              = 4,
		padding          = {_CELL_PADDING_POINTS, 0, _CELL_PADDING_POINTS, 0},
		position         = {column.x, 0},
		corner_radius    = shape.radius_field - _FIELD_INSET_RADIUS,
		hover_background = to_faded(colors.base_content, HOVER_OPACITY) if sort != nil else {},
		press_background = to_faded(colors.base_content, SELECTED_OPACITY) if sort != nil else {},
		flags            = {.Floating, .Clickable} if sort != nil else {.Floating},
	}
	title := ui.box(column.id, look)
	// A title that does not sort gets the Text role from its text.
	if sort != nil do title.role, title.label, title.is_on = .Button, column.title, is_sorted
	if is_sorted do title.value = "descending" if sort.is_descending else "ascending"

	if ui.signal(title).is_activated && sort != nil {
		if is_sorted {
			sort.is_descending = !sort.is_descending
		} else {
			sort.column = column.id
			sort.is_descending = false
		}
		sort.is_changed = true
		ui.request_frame()
	}

	color := colors.base_content if is_sorted else to_faded(colors.base_content, 0.7)
	if ui.scope(title) {
		ui.box("", {height = ui.fit_text(), text_color = color, font_size = 12, font_weight = .Semibold, flags = {.Truncate_Text}}, column.title)
		if is_sorted do icon_box("chevron.down" if sort.is_descending else "chevron.up", 9, color)
	}
}

_build_column_edge :: proc(column: ^Column, placed: _Placed_Column) {
	look := ui.Style {
		width    = ui.points(_RESIZE_GRAB_POINTS),
		height   = ui.fill(),
		justify  = .Center,
		position = {placed.x + placed.width - _RESIZE_GRAB_POINTS / 2, 0},
		cursor   = .Resize_Left_Right,
		flags    = {.Floating, .Clickable, .No_Focus_Ring},
	}
	edge := ui.box(fmt.tprintf("%s_edge", placed.id), look)
	signal := ui.signal(edge)
	if column.width == 0 && signal.is_held do column.width = placed.width
	_drag(edge, signal, &column.width, .X, 1)
	least := column.min_width if column.min_width > 0 else _TABLE_MIN_COLUMN_POINTS
	if column.width != 0 do column.width = max(column.width, least)
	edge.role, edge.label, edge.value = .Splitter, edge.id, fmt.tprintf("%.0f", placed.width)

	is_active := signal.is_held || edge._hot_fraction > 0.5
	if ui.scope(edge) {
		line := colors.primary if is_active else to_faded(colors.base_content, LINE_OPACITY)
		ui.box("", {width = ui.points(1), height = ui.fill(), background = line})
	}
}
