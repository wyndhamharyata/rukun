package kit

import "../images"
import "../render"
import "../ui"
import "core:path/filepath"

_Image_Paint :: struct {
	source:    string,
	is_fading: bool,
}

// Crops to fill the box. source is a file path, or a URL fetched by app.run's fetch_image.
// Shows base_300 while the image decodes, then fades in. A zero width or height fills the parent.
image :: proc(source: string, style: ui.Style = {}, is_fading := true) -> ui.Signal {
	base := ui.Style {
		width      = ui.fill(),
		height     = ui.fill(),
		background = colors.base_300,
	}
	box := ui.box("", ui.merge(base, style))
	// The file name only, because the full path differs from one Mac to the next.
	box.role, box.label = .Image, filepath.base(source)
	paint := new(_Image_Paint, context.temp_allocator)
	paint^ = {source, is_fading}
	box.draw = _draw_image
	box.data = paint

	return ui.signal(box)
}

_draw_image :: proc(box: ^ui.Box, rect, clip: [4]f32, opacity: f32) {
	paint := cast(^_Image_Paint)box.data
	texture, uv, fade := images.watch_filling(paint.source, {rect.z - rect.x, rect.w - rect.y})
	if texture == nil do return
	if !paint.is_fading do fade = 1

	render.push(
		{
			rect = rect,
			uv = uv,
			color = {1, 1, 1, opacity * fade},
			corner_radius = box.style.corner_radius * ui.to_pixels(1),
			clip = clip,
			kind = .Image,
		},
		texture,
	)
}
