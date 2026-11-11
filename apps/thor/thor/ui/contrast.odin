package ui

import "core:math"

// app sets this each frame: kit.min_contrast, or at least 4.5 with Increase contrast.
_min_contrast: f32 = 3
// The color behind the box being drawn, for draw procs that tint icons.
_drawing_under: [4]f32
// app sets these each frame. No glass shows with no screen or with Reduce transparency.
_is_glass_shown: bool
_glass_fallback: [4]f32

// What top looks like once laid over under.
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

// WCAG contrast ratio of two colors, 1 to 21; ignores alpha.
_to_contrast_ratio :: proc(first, second: [4]f32) -> f32 {
	a, b := _to_luminance(first), _to_luminance(second)

	return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

// Nudges a faint color lighter or darker than under by the smallest step that meets minimum,
// keeping its hue. When its own side can't reach minimum, it flips to black or white:
// stepping across would land on muddy gray.
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
