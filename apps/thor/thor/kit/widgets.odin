package kit

import "../font"
import "../platform"
import "../render"
import "../ui"
import "core:fmt"
import "core:strings"
import "core:time"

_Bar_Paint :: struct {
	first_ratio, last_ratio: f32,
	// A zero colour fills with base_content.
	color:                   [4]f32,
}

_BAR_TRACK_HEIGHT_POINTS :: 4

_draw_bar :: proc(box: ^ui.Box, rect, clip: [4]f32, opacity: f32) {
	paint := cast(^_Bar_Paint)box.data
	track_height := ui.to_pixels(_BAR_TRACK_HEIGHT_POINTS)
	top := (rect.y + rect.w - track_height) / 2
	track := [4]f32{rect.x, top, rect.z, top + track_height}
	track_width := track.z - track.x
	filled := track
	filled.x = track.x + track_width * clamp(paint.first_ratio, 0, 1)
	filled.z = track.x + track_width * clamp(paint.last_ratio, 0, 1)
	radius := track_height / 2

	render.push(
		{
			rect = track,
			color = with_opacity(colors.base_content, TRACK_OPACITY * opacity),
			corner_radius = radius,
			clip = clip,
		},
	)
	render.push(
		{
			rect = filled,
			color = with_opacity(paint.color if paint.color.a > 0 else colors.base_content, opacity),
			corner_radius = radius,
			clip = clip,
		},
	)
}

// The width in points of text on one line in the system font.
measure_text :: proc(text: string, font_size: f32, weight := font.Weight.Regular) -> f32 {
	if text == "" do return 0

	return(
		font.shape_text(text, font.system_font(weight, ui.to_pixels(font_size))).size_pixels.x /
		ui.to_pixels(1) \
	)
}

// A horizontal line, 1 point high, across the parent.
divider :: proc(style: ui.Style = {}) -> ui.Signal {
	look := ui.Style {
		width      = ui.fill(),
		height     = ui.points(1),
		background = colors.line,
	}

	return ui.signal(ui.box("", ui.merge(look, style)))
}

_SLIDE_POINTS_PER_SECOND :: 40

_SLIDE_REST_SECONDS :: 0.3

_slide_start_seconds: map[string]f64

// One line of text. Under the pointer, it slides to show the part that does not fit.
scrolling_text :: proc(
	id, text: string,
	color: [4]f32,
	font_size: f32,
	weight := font.Weight.Regular,
	is_clickable := false,
	is_hovered: Maybe(bool) = nil,
	width := ui.Size{.Fill, 1},
) -> ui.Signal {
	flags: ui.Flags = {.Truncate_Text}
	if is_clickable do flags += {.Clickable}
	if is_hovered == nil && !is_clickable do flags += {.Hoverable}

	box := ui.box(
		id,
		{
			width = width,
			height = ui.fit_text(),
			text_color = color,
			font_size = font_size,
			font_weight = weight,
			flags = flags,
		},
		text,
	)

	key := fmt.tprint(id, text)

	is_under_pointer := is_hovered.? or_else ui.signal(box).is_hovered

	if !is_under_pointer {
		stored_key, _ := delete_key(&_slide_start_seconds, key)
		delete(stored_key)
		return ui.signal(box)
	}

	now_seconds := time.duration_seconds(time.tick_diff({}, platform.now()))
	if key not_in _slide_start_seconds do _slide_start_seconds[strings.clone(key)] = now_seconds

	rested_seconds := now_seconds - _slide_start_seconds[key] - _SLIDE_REST_SECONDS

	if rested_seconds < 0 {
		ui.request_frame_after(-rested_seconds)
		return ui.signal(box)
	}

	overflow := measure_text(text, font_size, weight) - (box.rect.z - box.rect.x)
	if overflow <= 0 do return ui.signal(box)

	box.style.flags -= {.Truncate_Text}
	box.style.text_offset = min(overflow, f32(rested_seconds) * _SLIDE_POINTS_PER_SECOND)
	if box.style.text_offset < overflow do ui.request_frame()

	return ui.signal(box)
}
