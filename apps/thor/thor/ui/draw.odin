package ui

import "../font"
import "../render"
import "core:math"

// Blends in premultiplied colour, so a fade to a translucent colour gets no brighter or darker.
_mix :: proc(a, b: [4]f32, fraction: f32) -> [4]f32 {
	if b.a == 0 do return a

	from := [4]f32{a.r * a.a, a.g * a.a, a.b * a.a, a.a}
	to := [4]f32{b.r * b.a, b.g * b.a, b.b * b.a, b.a}
	mixed := from + (to - from) * fraction
	if mixed.a == 0 do return {}

	return {mixed.r / mixed.a, mixed.g / mixed.a, mixed.b / mixed.a, mixed.a}
}

_draw :: proc(box: ^Box, clip: [4]f32, parent_opacity: f32) {
	style := box.style
	opacity := parent_opacity * (1 - style.fade)

	if opacity <= 0 do return

	rect := box.rect
	pixels_per_point := _state.pixels_per_point
	rect_pixels := _to_whole_pixels(rect * pixels_per_point)
	clip_pixels := _to_whole_pixels(clip * pixels_per_point)
	is_outside := rect.x > clip.z || rect.z < clip.x || rect.y > clip.w || rect.w < clip.y

	if is_outside && .Clip in style.flags do return

	background := _mix(
		_mix(style.background, style.hover_background, box._hot_fraction),
		style.press_background,
		box._active_fraction,
	)

	has_gradient := style.gradient.y > style.gradient.x
	has_fill := background.a > 0 || style.border_width > 0 || has_gradient

	if has_fill {
		render.push(
			{
				end_color = _to_faded_color(style.end_background, opacity),
				gradient = style.gradient,
				rect = rect_pixels,
				color = _to_faded_color(background, opacity),
				border_color = _to_faded_color(style.border_color, opacity),
				border_width = _to_border_pixels(style.border_width, pixels_per_point),
				corner_radius = style.corner_radius * pixels_per_point,
				softness = style.softness * pixels_per_point,
				clip = clip_pixels,
			},
		)
	}

	if box.shaped != nil do _draw_text(box, rect, clip_pixels, opacity)
	if box.draw != nil do box.draw(box, rect_pixels, clip_pixels, opacity)

	child_clip := _intersect(clip, rect) if .Clip in style.flags else clip

	for child := box.first; child != nil; child = child.next do _draw(child, child_clip, opacity)

	// Forced focus reaches the boxes inside a component. Only the box that takes focus shows it.
	is_forced_focus := box.forced == .Focus && .Clickable in style.flags
	is_focused := is_forced_focus || (box.forced == .None && box._key != 0 && box._key == _state.focused_key)
	if is_focused && .No_Focus_Ring not_in style.flags {
		// In a tight group, such as list rows or a segmented control, the ring goes inside the box.
		is_tight := false
		for group := box.parent; group != nil; group = group.parent {
			if .Arrow_Keys not_in group.style.flags do continue

			is_tight = group.style.gap < FOCUS_RING_GAP_POINTS + FOCUS_RING_POINTS
			break
		}
		outset := (FOCUS_RING_GAP_POINTS + FOCUS_RING_POINTS) * pixels_per_point if !is_tight else 0
		render.push(
			{
				rect = rect_pixels + {-outset, -outset, outset, outset},
				border_color = _to_faded_color(_focus_ring_color, opacity),
				border_width = _to_border_pixels(FOCUS_RING_POINTS, pixels_per_point),
				corner_radius = style.corner_radius * pixels_per_point + outset,
				clip = clip_pixels,
			},
		)
	}
}

// Whole pixels keep edges sharp at any zoom. A box keeps at least one pixel, so a hairline shows.
_to_whole_pixels :: proc(rect: [4]f32) -> [4]f32 {
	whole := [4]f32{math.round(rect.x), math.round(rect.y), math.round(rect.z), math.round(rect.w)}
	if rect.z > rect.x && whole.z <= whole.x do whole.z = whole.x + 1
	if rect.w > rect.y && whole.w <= whole.y do whole.w = whole.y + 1

	return whole
}

// A border is whole pixels, at least one, as in CSS.
_to_border_pixels :: proc(points, pixels_per_point: f32) -> f32 {
	if points <= 0 do return 0

	return max(1, math.floor(points * pixels_per_point + 0.001))
}

_to_faded_color :: proc(color: [4]f32, opacity: f32) -> [4]f32 {
	return {color.r, color.g, color.b, color.a * opacity}
}

_draw_text :: proc(box: ^Box, rect: [4]f32, clip_pixels: [4]f32, opacity: f32) {
	style := box.style
	pixels_per_point := _state.pixels_per_point
	inner := [4]f32 {
		rect.x + style.padding.x,
		rect.y + style.padding.y,
		rect.z - style.padding.z,
		rect.w - style.padding.w,
	}
	text_size := box.shaped.size_pixels / pixels_per_point
	left := inner.x

	switch style.text_align {
	case .Auto, .Start:
	case .Center:
		left += (inner.z - inner.x - text_size.x) / 2
	case .End:
		left = inner.z - text_size.x
	}

	left -= style.text_offset

	top := inner.y + (inner.w - inner.y - text_size.y) / 2
	origin := [2]f32{math.round(left * pixels_per_point), math.round(top * pixels_per_point)}

	font.draw(
		box.shaped,
		origin,
		style.text_color if style.text_color.a > 0 else _default_text_color,
		_intersect(clip_pixels, inner * pixels_per_point),
		box.color_of,
		box.data,
		opacity,
	)
}
