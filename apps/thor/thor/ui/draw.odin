package ui

import "../font"
import "../platform"
import "../render"
import "core:math"

// Blends premultiplied colors so fading to a translucent color never brightens or darkens.
_mix :: proc(a, b: [4]f32, fraction: f32) -> [4]f32 {
	if b.a == 0 do return a

	from := [4]f32{a.r * a.a, a.g * a.a, a.b * a.a, a.a}
	to := [4]f32{b.r * b.a, b.g * b.a, b.b * b.a, b.a}
	mixed := from + (to - from) * fraction
	if mixed.a == 0 do return {}

	return {mixed.r / mixed.a, mixed.g / mixed.a, mixed.b / mixed.a, mixed.a}
}

_Ghost :: struct {
	pushed:      [dynamic]render.Pushed,
	opacity:     _Animated_Value,
	drawn_frame: int,
}

// under is the color behind the box, which its text must read against.
_draw :: proc(box: ^Box, clip: [4]f32, parent_opacity: f32, under: [4]f32) {
	if .Fade_Out not_in box.style.flags || box._key == 0 {
		_draw_box(box, clip, parent_opacity, under)
		return
	}

	first := render.pushed_count()
	_draw_box(box, clip, parent_opacity, under)
	if box._key not_in _state.ghosts do _state.ghosts[box._key] = {}
	ghost := &_state.ghosts[box._key]
	clear(&ghost.pushed)
	render.read_pushed(first, &ghost.pushed)
	ghost.opacity = {value = 1}
	ghost.drawn_frame = _state.frame_index
}

// shortcut: a fading copy can outlive its image texture after the image cache frees it. Keep
// the texture alive in the copy if that shows.
_draw_ghosts :: proc() {
	gone := make([dynamic]u64, context.temp_allocator)
	for key, &ghost in _state.ghosts {
		if ghost.drawn_frame == _state.frame_index do continue

		ghost.opacity.value, ghost.opacity.velocity = _spring(ghost.opacity.value, ghost.opacity.velocity, 0, _FADE_MOTION)
		if ghost.opacity.value <= 0 {
			append(&gone, key)
			continue
		}
		for pushed in ghost.pushed {
			faded := pushed.instance
			faded.color.a *= ghost.opacity.value
			faded.border_color.a *= ghost.opacity.value
			faded.end_color.a *= ghost.opacity.value
			render.push(faded, pushed.texture)
		}
	}
	for key in gone {
		delete(_state.ghosts[key].pushed)
		delete_key(&_state.ghosts, key)
	}
}

// A glass box clears what is under it so the window's glass shows through, tinted by its background.
// With no glass to show, it paints its tint, or the window color, opaque.
_apply_glass :: proc(box: ^Box, background: [4]f32, rect, rect_pixels, clip_pixels: [4]f32) -> (paint, under: [4]f32) {
	if !_is_glass_shown {
		paint = background if background.a > 0 else _glass_fallback
		paint.a = 1
		return paint, paint
	}

	render.push_clear(rect_pixels, box.style.corner_radius * _state.pixels_per_point, clip_pixels)
	area := platform.Glass_Area{_to_window_points(rect), box.style.corner_radius * _state.zoom, box.style.glass, background}
	append(&_state.glass_areas, area)

	return {}, _glass_fallback
}

_draw_box :: proc(box: ^Box, clip: [4]f32, parent_opacity: f32, under: [4]f32) {
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

	inner_under: [4]f32
	if style.glass != .None {
		paint, glass_under := _apply_glass(box, background, rect, rect_pixels, clip_pixels)
		background = paint
		inner_under = _lay_over(glass_under, under)
	} else {
		inner_under = _lay_over(background, under) if background.a > 0 else under
	}
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

	if box.shaped != nil do _draw_text(box, rect, clip_pixels, opacity, inner_under)
	_drawing_under = inner_under
	if box.draw != nil do box.draw(box, rect_pixels, clip_pixels, opacity)

	child_clip := _intersect(clip, rect) if .Clip in style.flags else clip

	// A floating, filled child (like a segmented control's pill) becomes the color under
	// any later child whose middle it covers.
	covers: [8]struct {
		rect:  [4]f32,
		color: [4]f32,
	}
	cover_count := 0
	for child := box.first; child != nil; child = child.next {
		child_under := inner_under
		middle := [2]f32{(child.rect.x + child.rect.z) / 2, (child.rect.y + child.rect.w) / 2}
		for cover in covers[:cover_count] {
			is_inside := middle.x >= cover.rect.x && middle.x < cover.rect.z && middle.y >= cover.rect.y && middle.y < cover.rect.w
			if is_inside do child_under = cover.color
		}
		_draw(child, child_clip, opacity, child_under)
		if .Floating in child.style.flags && child.style.background.a > 0 && cover_count < len(covers) {
			covers[cover_count] = {child.rect, _lay_over(child.style.background, inner_under)}
			cover_count += 1
		}
	}

	// Forced focus reaches inside components, but only the box holding focus draws the ring.
	is_forced_focus := box.forced == .Focus && .Clickable in style.flags
	is_focused := is_forced_focus || (box.forced == .None && box._key != 0 && box._key == _state.focused_key)
	if is_focused && .No_Focus_Ring not_in style.flags {
		// In tight groups like list rows or segmented controls, the ring draws inside the box.
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

// Whole pixels keep edges sharp at any zoom, and a box keeps at least one pixel so a hairline shows.
_to_whole_pixels :: proc(rect: [4]f32) -> [4]f32 {
	whole := [4]f32{math.round(rect.x), math.round(rect.y), math.round(rect.z), math.round(rect.w)}
	if rect.z > rect.x && whole.z <= whole.x do whole.z = whole.x + 1
	if rect.w > rect.y && whole.w <= whole.y do whole.w = whole.y + 1

	return whole
}

// Borders are whole pixels, at least one, as in CSS.
_to_border_pixels :: proc(points, pixels_per_point: f32) -> f32 {
	if points <= 0 do return 0

	return max(1, math.floor(points * pixels_per_point + 0.001))
}

_to_faded_color :: proc(color: [4]f32, opacity: f32) -> [4]f32 {
	return {color.r, color.g, color.b, color.a * opacity}
}

_draw_text :: proc(box: ^Box, rect: [4]f32, clip_pixels: [4]f32, opacity: f32, under: [4]f32) {
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
		_to_readable(style.text_color if style.text_color.a > 0 else _default_text_color, under, _min_contrast),
		_intersect(clip_pixels, inner * pixels_per_point),
		box.color_of,
		box.data,
		opacity,
		under,
	)
}
