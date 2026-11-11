package kit

import "../platform"
import "../render"
import "../ui"
import "core:fmt"
import "core:math"

_COLOR_KNOB_POINTS :: 14
_COLOR_STRIP_POINTS :: 14
_COLOR_KEY_STEP :: 0.02
_COLOR_HUE_KEY_STEP :: 3

// Keeps hue, saturation and brightness, so a gray, which has no hue, keeps the hue it had.
_Color_Picker :: struct {
	hsv:   [3]f32,
	// The color hsv was last read from or written to.
	rgb:   [3]f32,
	input: ^Text_Input,
}

_Color_Paint :: struct {
	hsv: [3]f32,
}

// Sets color^ but not its alpha, by drag, arrow keys, or a hex such as #3b82f6 on Return.
// width is in points. Sets is_changed on the frame color^ changes.
color_picker :: proc(id: string, color: ^[4]f32, width: f32 = 220) -> ui.Signal {
	box := ui.box(id, {width = ui.points(width), axis = .Y, gap = 10})
	is_new := box._key not_in _window.color_pickers
	if is_new do _window.color_pickers[box._key] = {input = new(Text_Input)}
	state := &_window.color_pickers[box._key]
	if is_new || state.rgb != color.rgb {
		state.hsv = _to_kept_hsv(color.rgb, state.hsv)
		state.rgb = color.rgb
	}
	hsv := state.hsv

	if ui.scope(box) {
		square := ui.box("square", {width = ui.fill(), height = ui.points(math.round(width * 0.66)), corner_radius = shape.radius_field - _FIELD_INSET_RADIUS, flags = {.Clickable}})
		square.role, square.label, square.value = .Slider, "saturation and brightness", fmt.tprintf("%.0f%% %.0f%%", hsv[1] * 100, hsv[2] * 100)
		_paint(square, hsv, _draw_color_square)
		signal := ui.signal(square)
		if ratio, is_held := _to_held_ratio(square, signal); is_held do hsv[1], hsv[2] = ratio.x, 1 - ratio.y
		hsv[1] += _to_arrow_step(signal, .Left, .Right) * _COLOR_KEY_STEP
		hsv[2] += _to_arrow_step(signal, .Down, .Up) * _COLOR_KEY_STEP

		strip := ui.box("hue", {width = ui.fill(), height = ui.points(_COLOR_STRIP_POINTS), corner_radius = _COLOR_STRIP_POINTS / 2, flags = {.Clickable}})
		strip.role, strip.label, strip.value = .Slider, "hue", fmt.tprintf("%.0f°", hsv[0])
		_paint(strip, hsv, _draw_hue_strip)
		strip_signal := ui.signal(strip)
		if ratio, is_held := _to_held_ratio(strip, strip_signal); is_held do hsv[0] = ratio.x * 360
		hsv[0] += _to_arrow_step(strip_signal, .Left, .Right) * _COLOR_HUE_KEY_STEP

		if ui.row("code", {width = ui.fill(), gap = 8, align = .Center}) {
			swatch := ui.Style {
				width         = ui.points(30),
				height        = ui.points(30),
				corner_radius = shape.radius_field,
				background    = {color.r, color.g, color.b, 1},
				border_width  = shape.border,
				border_color  = colors.line,
			}
			ui.box("", swatch)
			field := state.input
			hex := to_hex(color^)
			if !field.is_focused && to_input_text(field) != hex do set_input_text(field, hex)
			text_field("hex", field, "#000000")
			if field.is_submitted {
				if parsed, ok := to_color_from_hex(to_input_text(field)); ok do hsv = _to_kept_hsv(parsed.rgb, hsv)
			}
		}
	}

	hsv[0] = math.mod(hsv[0] + 360, 360)
	hsv[1] = clamp(hsv[1], 0, 1)
	hsv[2] = clamp(hsv[2], 0, 1)
	is_changed := hsv != state.hsv
	if is_changed {
		rgb := to_color_from_hsv(hsv[0], hsv[1], hsv[2]).rgb
		color.rgb = rgb
		state^ = {hsv, rgb, state.input}
		ui.request_frame()
	}

	signal := ui.signal(box)
	signal.is_changed = is_changed

	return signal
}

// A swatch of color^ that opens a color_picker in a popover. width is the picker's width in points.
color_well :: proc(id: string, color: ^[4]f32, width: f32 = 220) -> ui.Signal {
	look := ui.Style {
		width            = ui.points(44),
		height           = ui.points(_BUTTON_HEIGHT_POINTS),
		padding          = 4,
		corner_radius    = shape.radius_field,
		background       = with_opacity(colors.base_content, HOVER_OPACITY),
		hover_background = with_opacity(colors.base_content, _BUTTON_HOVER_ALPHA),
		press_background = with_opacity(colors.base_content, _BUTTON_PRESS_ALPHA),
		flags            = {.Clickable},
	}
	box := ui.box(id, look)
	box.role, box.label, box.value = .Pop_Up, id, to_hex(color^)
	trigger := ui.signal(box)
	if ui.scope(box) {
		ui.box("", {width = ui.fill(), height = ui.fill(), corner_radius = shape.radius_field - 4, background = color^})
	}

	is_open := _window.open_pop_up == box._key
	if trigger.is_activated do is_open = !is_open
	is_changed := false
	if popover(fmt.tprintf("%s_picker", id), &is_open, box) {
		if ui.col("padding", {padding = 6}) do is_changed = color_picker("picker", color, width).is_changed
	}

	if is_open {
		_window.open_pop_up = box._key
	} else if _window.open_pop_up == box._key {
		_window.open_pop_up = 0
	}

	signal := trigger
	signal.is_changed = is_changed

	return signal
}

// The color as #rrggbb, in the temp allocator.
to_hex :: proc(color: [4]f32) -> string {
	to_byte :: proc(channel: f32) -> int {return int(math.round(clamp(channel, 0, 1) * 255))}

	return fmt.tprintf("#%02x%02x%02x", to_byte(color.r), to_byte(color.g), to_byte(color.b))
}

// Hue in degrees, with saturation and brightness from 0 to 1.
to_hsv :: proc(rgb: [3]f32) -> [3]f32 {
	high := max(rgb.r, rgb.g, rgb.b)
	low := min(rgb.r, rgb.g, rgb.b)
	spread := high - low
	hue: f32
	switch {
	case spread == 0:
	case high == rgb.r:
		hue = 60 * math.mod((rgb.g - rgb.b) / spread + 6, 6)
	case high == rgb.g:
		hue = 60 * ((rgb.b - rgb.r) / spread + 2)
	case:
		hue = 60 * ((rgb.r - rgb.g) / spread + 4)
	}

	return {hue, spread / high if high > 0 else 0, high}
}

// A color from a hue in degrees and a saturation and brightness from 0 to 1.
to_color_from_hsv :: proc(hue, saturation, brightness: f32) -> [4]f32 {
	chroma := brightness * saturation
	sector := math.mod(hue, 360) / 60
	second := chroma * (1 - abs(math.mod(sector, 2) - 1))
	rgb: [3]f32
	switch int(sector) {
	case 0:
		rgb = {chroma, second, 0}
	case 1:
		rgb = {second, chroma, 0}
	case 2:
		rgb = {0, chroma, second}
	case 3:
		rgb = {0, second, chroma}
	case 4:
		rgb = {second, 0, chroma}
	case:
		rgb = {chroma, 0, second}
	}
	base := brightness - chroma

	return {rgb.r + base, rgb.g + base, rgb.b + base, 1}
}

// A gray has no hue and black has no saturation, so they keep those from kept.
_to_kept_hsv :: proc(rgb: [3]f32, kept: [3]f32) -> [3]f32 {
	hsv := to_hsv(rgb)
	if hsv[1] == 0 || hsv[2] == 0 do hsv[0] = kept[0]
	if hsv[2] == 0 do hsv[1] = kept[1]

	return hsv
}

_paint :: proc(box: ^ui.Box, hsv: [3]f32, draw: ui.Draw_Proc) {
	paint := new(_Color_Paint, context.temp_allocator)
	paint.hsv = hsv
	box.data = paint
	box.draw = draw
}

// Pointer position in the box from 0 to 1 on each axis, while the pointer holds it.
_to_held_ratio :: proc(box: ^ui.Box, signal: ui.Signal) -> (ratio: [2]f32, is_held: bool) {
	size := [2]f32{box.rect.z - box.rect.x, box.rect.w - box.rect.y}
	if !signal.is_held || box.forced != .None || size.x <= 0 || size.y <= 0 do return

	mouse := ui.mouse_position()

	return {clamp((mouse.x - box.rect.x) / size.x, 0, 1), clamp((mouse.y - box.rect.y) / size.y, 0, 1)}, true
}

// -1 for lower, 1 for higher, or 0, while the box has focus. It takes the key it uses.
_to_arrow_step :: proc(signal: ui.Signal, lower, higher: platform.Key) -> f32 {
	if !signal.is_focused || signal.box.forced != .None do return 0

	step: f32
	for key, index in ([2]platform.Key{lower, higher}) {
		if !ui.is_key_pressed(key) || ui.is_key_taken(key) do continue

		step += -1 if index == 0 else 1
		ui._state.taken_keys += {int(key)}
	}

	return step
}

_draw_color_square :: proc(box: ^ui.Box, rect, clip: [4]f32, opacity: f32) {
	hsv := (cast(^_Color_Paint)box.data).hsv
	radius := box.style.corner_radius * ui.to_pixels(1)
	hue := to_color_from_hsv(hsv[0], 1, 1)
	across := render.Gradient_Kind{.Across, .Linear}
	render.push({rect = rect, color = with_opacity({1, 1, 1, 1}, opacity), end_color = with_opacity(hue, opacity), gradient = {0, 1}, gradient_kind = across, corner_radius = radius, clip = clip})
	render.push({rect = rect, color = {}, end_color = {0, 0, 0, opacity}, gradient = {0, 1}, gradient_kind = {.Linear}, corner_radius = radius, clip = clip})

	center := [2]f32{rect.x + (rect.z - rect.x) * hsv[1], rect.y + (rect.w - rect.y) * (1 - hsv[2])}
	_draw_knob(center, to_color_from_hsv(hsv[0], hsv[1], hsv[2]), clip, opacity)
}

_draw_hue_strip :: proc(box: ^ui.Box, rect, clip: [4]f32, opacity: f32) {
	hsv := (cast(^_Color_Paint)box.data).hsv
	radius := (rect.w - rect.y) / 2
	segment := (rect.z - rect.x) / 6
	across := render.Gradient_Kind{.Across, .Linear}
	for index in 0 ..< 6 {
		left := rect.x + f32(index) * segment
		part := [4]f32{left, rect.y, left + segment, rect.w}
		gradient := [2]f32{0, 1}
		// End segments overlap their neighbors by the radius so only the strip's ends round.
		if index == 0 {
			part.z += radius
			gradient = {0, segment / (segment + radius)}
		} else if index == 5 {
			part.x -= radius
			gradient = {radius / (segment + radius), 1}
		}
		start := to_color_from_hsv(f32(index) * 60, 1, 1)
		end := to_color_from_hsv(f32(index + 1) * 60, 1, 1)
		corner := radius if index == 0 || index == 5 else 0
		render.push({rect = part, color = with_opacity(start, opacity), end_color = with_opacity(end, opacity), gradient = gradient, gradient_kind = across, corner_radius = corner, clip = clip})
	}

	center := [2]f32{rect.x + (rect.z - rect.x) * hsv[0] / 360, (rect.y + rect.w) / 2}
	_draw_knob(center, to_color_from_hsv(hsv[0], 1, 1), clip, opacity)
}

_draw_knob :: proc(center: [2]f32, fill: [4]f32, clip: [4]f32, opacity: f32) {
	size := ui.to_pixels(_COLOR_KNOB_POINTS)
	knob := [4]f32{center.x - size / 2, center.y - size / 2, center.x + size / 2, center.y + size / 2}
	render.push({rect = knob + {0, 1, 0, 1}, color = {0, 0, 0, 0.3 * opacity}, corner_radius = size / 2, softness = ui.to_pixels(2), clip = clip})
	render.push({rect = knob, color = with_opacity(fill, opacity), border_color = {1, 1, 1, opacity}, border_width = ui.to_pixels(2), corner_radius = size / 2, clip = clip})
}
