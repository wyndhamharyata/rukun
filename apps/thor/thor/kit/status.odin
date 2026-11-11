package kit

import "../platform"
import "../render"
import "../ui"
import "core:fmt"
import "core:math"
import "core:time"

_SPINNER_SPOKES :: 8
// Steps of the lit spoke per second: one turn takes 0.8 seconds.
_SPINNER_STEPS_PER_SECOND :: 10

_BADGE_HEIGHT_POINTS :: 18

// A filled track that shows ratio, from 0 to 1.
progress :: proc(ratio: f32, tone := Tone.Primary, width := ui.Size{.Fill, 1}) -> ui.Signal {
	shown := clamp(ratio, 0, 1)
	color, _ := tone_colors(tone)
	box := ui.box("", {width = width, height = ui.points(_BAR_TRACK_HEIGHT_POINTS)})
	paint := new(_Bar_Paint, context.temp_allocator)
	paint^ = {last_ratio = shown, color = color}
	box.draw = _draw_bar
	box.data = paint
	box.role, box.value = .Progress, fmt.tprintf("%.0f%%", shown * 100)

	return ui.signal(box)
}

_Spinner_Paint :: struct {
	lead:  int,
	color: [4]f32,
}

// It requests a frame each time a spoke lights, so build it only while the app waits.
spinner :: proc(size_points: f32 = 16, tone := Tone.Base) -> ui.Signal {
	box := ui.box("", {width = ui.points(size_points), height = ui.points(size_points)})
	steps := time.duration_seconds(time.tick_diff({}, platform.now())) * _SPINNER_STEPS_PER_SECOND
	ui.request_frame_after((math.floor(steps) + 1 - steps) / _SPINNER_STEPS_PER_SECOND)

	color, _ := tone_colors(tone)
	paint := new(_Spinner_Paint, context.temp_allocator)
	paint^ = {int(steps) % _SPINNER_SPOKES, color}
	box.draw = _draw_spinner
	box.data = paint
	box.role, box.value = .Progress, "busy"

	return ui.signal(box)
}

_draw_spinner :: proc(box: ^ui.Box, rect, clip: [4]f32, opacity: f32) {
	paint := cast(^_Spinner_Paint)box.data
	color := ui._to_readable(paint.color, ui._drawing_under, ui._min_contrast)
	size := min(rect.z - rect.x, rect.w - rect.y)
	center := [2]f32{(rect.x + rect.z) / 2, (rect.y + rect.w) / 2}
	length := size * 0.28
	thickness := max(1, size * 0.1)
	reach := size / 2 - length / 2

	for spoke in 0 ..< _SPINNER_SPOKES {
		// From the top, clockwise, as the lit spoke moves.
		angle := f32(spoke) * 2 * math.PI / _SPINNER_SPOKES - math.PI / 2
		age := (paint.lead - spoke + _SPINNER_SPOKES) % _SPINNER_SPOKES
		alpha := 1 - f32(age) * 0.75 / (_SPINNER_SPOKES - 1)
		middle := center + [2]f32{math.cos(angle), math.sin(angle)} * reach
		spoke_rect := [4]f32{middle.x - length / 2, middle.y - thickness / 2, middle.x + length / 2, middle.y + thickness / 2}
		render.push({rect = spoke_rect, color = with_opacity(color, alpha * opacity), corner_radius = thickness / 2, rotation = angle, clip = clip})
	}
}

// A short label in a pill: a count, a state, "New".
badge :: proc(label: string, tone := Tone.Base, variant := Variant.Soft) -> ui.Signal {
	look, _ := _tone_style(tone, variant)
	look.width = ui.fit_text()
	look.height = ui.points(_BADGE_HEIGHT_POINTS)
	look.padding = {6, 0, 6, 0}
	look.corner_radius = shape.radius_selector
	look.font_size = 11
	look.font_weight = .Semibold

	return ui.signal(ui.box("", look, label))
}
