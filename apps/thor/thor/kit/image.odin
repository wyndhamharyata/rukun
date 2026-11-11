package kit

import "../images"
import "../render"
import "../ui"
import "core:math"
import "core:path/filepath"
import MTL "vendor:darwin/Metal"

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
	size := [2]f32{rect.z - rect.x, rect.w - rect.y}
	if size.x <= 0 || size.y <= 0 do return

	// images.watch caches by crop, so the aspect snaps to quarter steps.
	aspect := math.floor(size.x / size.y * 4 + 0.01) / 4
	texture, fade := images.watch(paint.source, int(math.ceil(max(size.x, size.y))), {aspect, 0.5})
	if texture == nil do return
	if !paint.is_fading do fade = 1

	render.push(
		{
			rect = rect,
			uv = _to_fill_uv(size, texture),
			color = {1, 1, 1, opacity * fade},
			corner_radius = ui.to_pixels(box.style.corner_radius),
			clip = clip,
			kind = .Image,
		},
		texture,
	)
}

// The texture region that fills the box without stretching.
_to_fill_uv :: proc(size: [2]f32, texture: ^MTL.Texture) -> [4]f32 {
	box_ratio := size.x / size.y
	texture_ratio := f32(texture->width()) / f32(texture->height())
	if abs(box_ratio - texture_ratio) < 0.01 do return {0, 0, 1, 1}

	if texture_ratio > box_ratio {
		width := box_ratio / texture_ratio
		return {(1 - width) / 2, 0, (1 + width) / 2, 1}
	}

	height := texture_ratio / box_ratio
	return {0, (1 - height) / 2, 1, (1 + height) / 2}
}
