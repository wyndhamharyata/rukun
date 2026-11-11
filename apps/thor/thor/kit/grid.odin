package kit

import "../ui"
import "core:math"

// Fits as many min_width tiles into a row as it can, then widens them to fill it. Scrolls like a list.
// A tile's height is row_height plus height_per_width times its width: 46 and 1 for square art over text.
@(deferred_out = _end_grid)
grid :: proc(
	id: string,
	count: int,
	min_width, row_height: f32,
	gap: f32 = 16,
	height_per_width: f32 = 0,
) -> (
	first, last: int,
	tile: [2]f32,
	ok: bool,
) {
	// The width the grid had last frame. Before it has one, the tiles take min_width.
	last_box := ui.find_box(id, ui.current_parent())
	width := last_box.size.x if last_box != nil else 0
	columns := max(1, int((width + gap) / (min_width + gap)))
	tile.x = min_width
	if width > 0 do tile.x = math.floor((width - gap * f32(columns - 1)) / f32(columns))
	tile.y = row_height + math.round(height_per_width * tile.x)

	row_count := (count + columns - 1) / columns
	first_row, last_row, _ := _begin_list(id, row_count, tile.y, {gap = gap}, 40, false)
	ui.push_parent(ui.box("tiles", {width = ui.fill(), axis = .X, gap = gap, flags = {.Wrap_Children}}))

	return first_row * columns, min(count, last_row * columns), tile, true
}

_end_grid :: proc(first, last: int, tile: [2]f32, ok: bool) {
	ui.pop_parent()
	_end_list(first, last, ok)
}
