package kit

import "../platform"
import "../ui"
import "core:strings"
import "core:time"

_TOAST_SECONDS :: 2.5

_TOAST_FADE_SECONDS :: 0.3

_TOAST_PADDING_POINTS :: 14

_TOAST_MARGIN_POINTS :: 12

_TOAST_ICON_POINTS :: 14

_Toast :: struct {
	text:     string,
	tone:     Tone,
	shown_at: time.Tick,
}

// A tone other than Base colours the edge, and Info, Success, Warning and Error add their icon.
show_toast :: proc(text: string, tone := Tone.Base) {
	delete(_window.toast.text)
	_window.toast.text = strings.clone(text)
	_window.toast.tone = tone
	_window.toast.shown_at = platform.now()
}

_TOAST_ICONS := [Tone]string {
	.Base      = "",
	.Primary   = "",
	.Secondary = "",
	.Accent    = "",
	.Neutral   = "",
	.Info      = "info.circle.fill",
	.Success   = "checkmark.circle.fill",
	.Warning   = "exclamationmark.triangle.fill",
	.Error     = "xmark.octagon.fill",
}

build_toast :: proc(bottom_margin_points: f32 = 0) {
	if _window.toast.text == "" do return

	seconds := f32(time.duration_seconds(time.tick_diff(_window.toast.shown_at, platform.now())))

	if seconds > _TOAST_SECONDS {
		delete(_window.toast.text)
		_window.toast.text = ""
		return
	}

	opacity := min(1, (_TOAST_SECONDS - seconds) / _TOAST_FADE_SECONDS)
	root := ui.current_parent()
	window_size := [2]f32{root.style.width.value, root.style.height.value}
	icon := _TOAST_ICONS[_window.toast.tone]
	gap: f32 = 8
	width := measure_text(_window.toast.text, SMALL_TEXT_POINTS) + 2 * _TOAST_PADDING_POINTS
	if icon != "" do width += _TOAST_ICON_POINTS + gap
	top := window_size.y - bottom_margin_points - _TOAST_MARGIN_POINTS - _BUTTON_HEIGHT_POINTS
	tone_color, _ := tone_colors(_window.toast.tone)
	edge := tone_color if _window.toast.tone != .Base else colors.line

	toast := ui.box(
		"toast",
		{
			width = ui.points(width),
			height = ui.points(_BUTTON_HEIGHT_POINTS),
			axis = .X,
			align = .Center,
			gap = gap,
			padding = {_TOAST_PADDING_POINTS, 0, _TOAST_PADDING_POINTS, 0},
			corner_radius = shape.radius_box,
			background = colors.popover,
			border_width = shape.border,
			border_color = edge,
			fade = 1 - opacity,
			position = {(window_size.x - width) / 2, top},
			flags = {.Floating},
		},
	)
	toast.role, toast.label = .Toast, _window.toast.text
	if ui.scope(toast) {
		if icon != "" do icon_box(icon, _TOAST_ICON_POINTS, tone_color)
		ui.box("", {text_color = colors.base_content, font_size = SMALL_TEXT_POINTS}, _window.toast.text)
	}
	// Request one frame when the fade starts, then every frame of the fade.
	fade_start: f32 = _TOAST_SECONDS - _TOAST_FADE_SECONDS
	if seconds < fade_start {
		ui.request_frame_after(f64(fade_start - seconds))
	} else {
		platform.request_frame()
	}
}
