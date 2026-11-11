package kit

import "../ui"

_LIST_EXTRA_ROWS :: 2

// Pass as row_height when rows differ in height; the list then measures each row.
MEASURED :: 0

_List :: struct {
	// Each row's measured height, 0 until built; only a MEASURED list keeps them.
	heights: [dynamic]f32,
	// Last frame's rows, from first onward.
	first:   int,
	keys:    [dynamic]u64,
}

// Builds only the rows on screen. With row_height MEASURED, every row needs an id.
// Inside a box that scrolls, the list fits its rows and does not scroll itself.
@(deferred_out = _end_list)
list :: proc(
	id: string,
	count: int,
	row_height: f32,
	changes: ui.Style = {},
	estimate: f32 = 40,
	starts_at_end := false,
) -> (
	first, last: int,
	ok: bool,
) {
	return _begin_list(id, count, row_height, changes, estimate, starts_at_end)
}

_begin_list :: proc(
	id: string,
	count: int,
	row_height: f32,
	changes: ui.Style,
	estimate: f32,
	starts_at_end: bool,
) -> (
	first, last: int,
	ok: bool,
) {
	is_in_scroll := false
	for parent := ui.current_parent(); parent != nil; parent = parent.parent {
		if .Scroll in parent.style.flags do is_in_scroll = true
	}

	base := ui.Style {
		width = ui.fill(),
	}
	if !is_in_scroll do base = {
		width  = ui.fill(),
		height = ui.fill(),
		flags  = {.Scroll, .Clip},
	}
	style := ui.merge(base, changes)
	style.axis = .Y
	gap := style.gap

	is_new := ui.find_box(id, ui.current_parent()) == nil
	box := ui.box(id, style)
	list := _window.lists[box._key] or_else nil

	if list == nil {
		list = new(_List)
		_window.lists[box._key] = list
	}

	// shortcut: heights are indexed by row number, so clear them once rows can move.
	if row_height == 0 && len(list.heights) != count do resize(&list.heights, count)

	height_of :: proc(list: ^_List, row_height, estimate: f32, index: int) -> f32 {
		if row_height > 0 do return row_height

		return list.heights[index] if list.heights[index] > 0 else estimate
	}

	scroller := box
	for scroller != nil && (.Scroll not_in scroller.style.flags) do scroller = scroller.parent

	// The rows box and the scroll box keep the places they had last frame.
	rows_box := ui.find_box("rows", box)
	is_placed := scroller != nil && rows_box != nil && scroller.size.y > 0
	visible_top, visible_bottom: f32

	if is_placed {
		visible_top = scroller.rect.y - rows_box.rect.y + scroller.scroll - scroller._placed_scroll
		visible_bottom = visible_top + scroller.size.y
	} else {
		ui.request_frame()
	}

	is_changed := false

	if row_height == 0 && is_placed {
		top: f32
		for index in 0 ..< min(list.first, count) {
			top += height_of(list, row_height, estimate, index) + gap
		}

		shift: f32

		for key, offset in list.keys {
			index := list.first + offset
			if index >= count do break

			height := height_of(list, row_height, estimate, index)
			row := ui._find_box_with_key(key) if key != 0 else nil

			if row != nil && row.size.y > 0 && row.size.y != height {
				// A row above the view grew taller, so the scroll follows it to keep the view still.
				if top < visible_top do shift += row.size.y - height
				list.heights[index] = row.size.y
				is_changed = true
			}

			top += height + gap
		}

		if is_changed {
			ui.request_frame()
			scroller.scroll += shift
			scroller._scroll_target += shift
			visible_top += shift
			visible_bottom += shift
		}
	}

	total: f32
	for index in 0 ..< count do total += height_of(list, row_height, estimate, index)
	if count > 1 do total += gap * f32(count - 1)

	if starts_at_end && scroller != nil {
		max_scroll := scroller.content_size.y - scroller.size.y
		is_at_end := scroller._placed_scroll >= max_scroll - 1

		if is_new || !is_placed || (is_changed && is_at_end) {
			ui.set_scroll(scroller, 1e9)
			visible_bottom = total
			visible_top = total - scroller.size.y
		}
	}

	// A scroll past the end, like set_scroll(box, 1e9), lands on the end after layout.
	if visible_bottom > total && visible_top > 0 {
		shift := min(visible_top, visible_bottom - total)
		visible_top -= shift
		visible_bottom -= shift
	}

	index := 0
	offset: f32

	for index < count {
		height := height_of(list, row_height, estimate, index)
		if offset + height > visible_top do break

		offset += height + gap
		index += 1
	}

	for _ in 0 ..< _LIST_EXTRA_ROWS {
		if index == 0 do break

		index -= 1
		offset -= height_of(list, row_height, estimate, index) + gap
	}

	first = index
	top := offset

	for index < count && offset < visible_bottom {
		offset += height_of(list, row_height, estimate, index) + gap
		index += 1
	}

	last = min(count, index + _LIST_EXTRA_ROWS)
	list.first = first

	for row in index ..< last do offset += height_of(list, row_height, estimate, row) + gap

	// A first row with no height yet grows upward, keeping the rows in view still.
	is_growing_up :=
		row_height == 0 && first < last && list.heights[first] == 0 && list.heights[last - 1] > 0
	padding := [4]f32{0, top, 0, 0}
	justify := ui.Align.Start

	if is_growing_up {
		padding = {0, 0, 0, total - (offset - gap)}
		justify = .End
	}

	ui.push_parent(box)
	rows := ui.box(
		"rows",
		{
			width = ui.fill(),
			height = ui.points(total),
			axis = .Y,
			gap = gap,
			padding = padding,
			justify = justify,
			flags = {.Arrow_Keys},
		},
	)
	ui.push_parent(rows)

	return first, last, true
}

_end_list :: proc(first, last: int, ok: bool) {
	rows := ui.current_parent()
	list := _window.lists[rows.parent._key]

	clear(&list.keys)
	for row := rows.first; row != nil; row = row.next do append(&list.keys, row._key)

	ui.pop_parent()
	ui.pop_parent()
}
