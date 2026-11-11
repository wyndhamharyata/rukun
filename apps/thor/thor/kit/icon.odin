package kit

import "../icon"
import "../ui"

_Icon_Paint :: struct {
	name:        string,
	size_points: f32,
	color:       [4]f32,
}

_draw_icon :: proc(box: ^ui.Box, rect, clip: [4]f32, opacity: f32) {
	paint := cast(^_Icon_Paint)box.data
	color := to_faded(paint.color, opacity)
	icon.draw(paint.name, ui.to_pixels(paint.size_points), rect, clip, color)
}

// An SF Symbol, size_points tall, in the middle of its box. style can make the box larger.
icon_box :: proc(symbol: string, size_points: f32, color: [4]f32, style: ui.Style = {}) -> ui.Signal {
	return ui.signal(_icon_box("", symbol, size_points, color, style))
}

// The id lets a component click the icon.
_icon_box :: proc(id, symbol: string, size_points: f32, color: [4]f32, style: ui.Style = {}) -> ^ui.Box {
	style := style
	box_size := size_points + style.padding.x + style.padding.z
	if _is_size_unset(style.width) do style.width = ui.points(box_size)
	if _is_size_unset(style.height) do style.height = ui.points(box_size)

	box := ui.box(id, style)
	paint := new(_Icon_Paint, context.temp_allocator)
	paint^ = {symbol, size_points, color}
	box.draw = _draw_icon
	box.data = paint

	return box
}

_is_size_unset :: proc(size: ui.Size) -> bool {
	return size == {}
}
