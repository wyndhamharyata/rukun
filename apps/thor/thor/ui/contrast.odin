package ui

import "core:math"

// app sets it each frame: kit.min_contrast, or at least 4.5 with Increase contrast.
_min_contrast: f32 = 3
// The colour under the box being drawn, for the draw procedures that colour icons.
_drawing_under: [4]f32
// app sets them each frame. No glass shows with no screen or with Reduce transparency.
_is_glass_shown: bool
_glass_fallback: [4]f32

// The colour as the person sees it on under.
_lay_over :: proc(top, under: [4]f32) -> [4]f32 {
	if under.a == 0 do return top

	alpha := top.a + under.a * (1 - top.a)
	if alpha == 0 do return {}
	rgb := (top.rgb * top.a + under.rgb * under.a * (1 - top.a)) / alpha

	return {rgb.r, rgb.g, rgb.b, alpha}
}

_to_luminance :: proc(color: [4]f32) -> f32 {
	linear :: proc(channel: f32) -> f32 {
		return channel / 12.92 if channel <= 0.04045 else math.pow((channel + 0.055) / 1.055, 2.4)
	}

	return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
}

// WCAG's contrast ratio between two colours, from 1 to 21. It ignores alpha.
_to_contrast_ratio :: proc(first, second: [4]f32) -> f32 {
	a, b := _to_luminance(first), _to_luminance(second)

	return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

// A colour that reads too faintly on under stays lighter or darker than under, and moves by the
// smallest step that meets minimum, so its hue stays. When its side cannot reach minimum, it turns
// black or white: a step across would give a muddy grey.
_to_readable :: proc(color, under: [4]f32, minimum: f32) -> [4]f32 {
	if under.a < 0.5 || color.a == 0 do return color

	shown := _lay_over(color, under)
	if _to_contrast_ratio(shown, under) >= minimum do return color

	white, black := [4]f32{1, 1, 1, 1}, [4]f32{0, 0, 0, 1}
	is_lighter := _to_luminance(shown) > _to_luminance(under)
	target := white if is_lighter else black
	if _to_contrast_ratio(target, under) < minimum do return black if is_lighter else white

	low, high: f32 = 0, 1
	for _ in 0 ..< 12 {
		middle := (low + high) / 2
		if _to_contrast_ratio(shown + (target - shown) * middle, under) >= minimum {
			high = middle
		} else {
			low = middle
		}
	}
	readable := shown + (target - shown) * high
	readable.a = 1

	return readable
}
