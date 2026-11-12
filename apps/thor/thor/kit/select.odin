package kit

import "../platform"
import "../render"
import "../ui"
import "core:fmt"
import "core:math"

_SLIDER_KNOB_POINTS :: 16
_SLIDER_HEIGHT_POINTS :: 20
// The share of the range one key press moves when step is zero.
_SLIDER_KEY_SHARE :: 0.05

// selected^ stores an option id, so the ids must outlive the frame.
// A zero width fits the text. Sets is_changed on the frame selected^ changes.
select :: proc(
	id: string,
	selected: ^string,
	options: []Option,
	placeholder := "",
	tone := Tone.Base,
	width := ui.Size{},
) -> ui.Signal {
	look, _ := _tone_style(tone, .Solid)
	look.width = width if width != {} else ui.fit_children()
	look.height = ui.points(_BUTTON_HEIGHT_POINTS)
	look.axis = .X
	look.align = .Center
	look.gap = 8
	look.padding = {12, 0, 10, 0}
	look.corner_radius = shape.radius_field
	look.flags = {.Clickable}
	box := ui.box(id, look)
	shown := _to_option_label(options, selected^)
	// VoiceOver reads the placeholder, which names what the person picks.
	box.role, box.label, box.value = .Pop_Up, placeholder if placeholder != "" else id, shown
	trigger := ui.signal(box)

	shown_color := look.text_color
	if shown == "" do shown, shown_color = placeholder, with_opacity(look.text_color, 0.5)
	if ui.scope(box) {
		text_look := ui.Style {
			width       = ui.fill() if width != {} else ui.fit_text(),
			height      = ui.fit_text(),
			text_color  = shown_color,
			font_size   = 13,
			font_weight = .Medium,
			flags       = {.Truncate_Text},
		}
		ui.box("", text_look, shown)
		icon_box("chevron.up.chevron.down", 10, with_opacity(look.text_color, 0.7))
	}

	is_open := _window.open_pop_up == box._key
	if trigger.is_activated do is_open = !is_open
	is_changed := false
	if popover(fmt.tprintf("%s_options", id), &is_open, box) {
		// When the keyboard opens it, focus goes to the selected option, or else the first.
		is_focusing := _window.popover.is_focusing_first
		_window.popover.is_focusing_first = false
		for option in options {
			item := menu_item(option.id, option.label, "✓" if option.id == selected^ else "", is_disabled = option.is_disabled)
			if is_focusing && option.id == selected^ {
				ui.focus(item.box)
				is_focusing = false
			}
			if item.is_activated && option.id != selected^ {
				selected^ = option.id
				is_changed = true
				ui.request_frame()
			}
		}
		_window.popover.is_focusing_first = is_focusing
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

_Slider_Paint :: struct {
	ratio: f32,
	color: [4]f32,
}

// Arrows move value^ by step, or a twentieth of the range when step is 0; step also snaps drags.
// is_set_on_release reports is_changed only on release, for seek bars; value^ still follows the drag.
slider :: proc(
	id: string,
	value: ^f32,
	label := "",
	range := [2]f32{0, 1},
	step: f32 = 0,
	is_set_on_release := false,
	tone := Tone.Primary,
	width := ui.Size{.Fill, 1},
) -> ui.Signal {
	// The corners shape the focus ring only.
	look := ui.Style {
		width         = width,
		height        = ui.points(_SLIDER_HEIGHT_POINTS),
		corner_radius = _SLIDER_HEIGHT_POINTS / 2,
		flags         = {.Clickable},
	}
	if label != "" {
		row := ui.box("", {width = width, axis = .X, align = .Center, gap = 10})
		ui.push_parent(row)
		ui.box("", {text_color = colors.base_content, font_size = 13}, label)
		look.width = ui.fill()
	}
	defer if label != "" do ui.pop_parent()
	box := ui.box(id, look)
	box.role, box.label = .Slider, label if label != "" else id
	signal := ui.signal(box)
	span := range[1] - range[0]
	travel := box.rect.z - box.rect.x - _SLIDER_KNOB_POINTS
	was := value^

	// A keyboard click has no place on the track. A forced state from the gallery only looks held.
	is_live := box.forced == .None
	is_released := signal.is_activated && signal.count > 0
	if (signal.is_held || is_released) && is_live && travel > 0 {
		ratio := clamp((ui.mouse_position().x - box.rect.x - _SLIDER_KNOB_POINTS / 2) / travel, 0, 1)
		value^ = range[0] + ratio * span
		if step > 0 do value^ = range[0] + math.round((value^ - range[0]) / step) * step
	}

	is_keyed := false
	if signal.is_focused && is_live {
		key_step := step if step > 0 else span * _SLIDER_KEY_SHARE
		for key in ([]platform.Key{.Left, .Down, .Right, .Up}) {
			if !ui.is_key_pressed(key) || ui.is_key_taken(key) do continue

			value^ += -key_step if key == .Left || key == .Down else key_step
			is_keyed = true
			// The slider takes the key, so the app's arrow shortcuts wait while it is focused.
			ui._state.taken_keys += {int(key)}
		}
	}

	value^ = clamp(value^, min(range[0], range[1]), max(range[0], range[1]))
	if is_set_on_release {
		signal.is_changed = (is_released && is_live) || (is_keyed && value^ != was)
	} else {
		signal.is_changed = value^ != was
	}
	ratio := (value^ - range[0]) / span if span != 0 else 0
	color, _ := tone_colors(tone)
	paint := new(_Slider_Paint, context.temp_allocator)
	paint^ = {ratio, color}
	box.draw = _draw_slider
	box.data = paint
	box.value = fmt.tprintf("%.0f%%", ratio * 100)
	box.number, box.range = value^, range

	return signal
}

_draw_slider :: proc(box: ^ui.Box, rect, clip: [4]f32, opacity: f32) {
	paint := cast(^_Slider_Paint)box.data
	knob := ui.to_pixels(_SLIDER_KNOB_POINTS)
	track_height := ui.to_pixels(_BAR_TRACK_HEIGHT_POINTS)
	middle := (rect.y + rect.w) / 2
	x := rect.x + knob / 2 + (rect.z - rect.x - knob) * paint.ratio
	track := [4]f32{rect.x, middle - track_height / 2, rect.z, middle + track_height / 2}
	filled := track
	filled.z = x
	knob_rect := [4]f32{x - knob / 2, middle - knob / 2, x + knob / 2, middle + knob / 2}

	render.push({rect = track, color = with_opacity(colors.base_content, TRACK_OPACITY * opacity), corner_radius = track_height / 2, clip = clip})
	render.push({rect = filled, color = with_opacity(paint.color, opacity), corner_radius = track_height / 2, clip = clip})
	shadow_offset := ui.to_pixels(0.5)
	render.push({rect = knob_rect + {0, shadow_offset, 0, shadow_offset}, color = {0, 0, 0, 0.3 * opacity}, corner_radius = knob / 2, softness = ui.to_pixels(2), clip = clip})
	render.push({rect = knob_rect, color = {1, 1, 1, opacity}, corner_radius = knob / 2, clip = clip})
}
