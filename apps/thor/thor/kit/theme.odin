package kit

import "../platform"
import "../ui"
import "core:math"
import "core:strconv"

// {font size, line height} in points. Other font sizes keep the font's own line height.
line_heights := [][2]f32{{12, 16}, {13, 18}, {15, 20}, {28, 36}}

to_line_height :: proc(font_size: f32) -> f32 {
	for pair in line_heights {
		if pair[0] == font_size do return pair[1]
	}
	return 0
}

to_color :: proc "contextless" (hex: u32) -> [4]f32 {
	return {
		f32((hex >> 24) & 0xff) / 255,
		f32((hex >> 16) & 0xff) / 255,
		f32((hex >> 8) & 0xff) / 255,
		f32(hex & 0xff) / 255,
	}
}

// Takes #3b82f6 or 3b82f6. It returns false for any other text.
to_color_from_hex :: proc(hex: string) -> (color: [4]f32, ok: bool) {
	digits := hex[1:] if len(hex) > 0 && hex[0] == '#' else hex
	if len(digits) != 6 do return {}, false

	value := strconv.parse_u64_of_base(digits, 16) or_return

	return to_color(u32(value << 8) | 0xff), true
}

// Names from daisyUI. Each x_content is the colour of text and icons on a fill of x.
Colors :: struct {
	// base_100 is the window. base_200 and base_300 step lighter in Dark and darker in Light.
	base_100, base_200, base_300, base_content: [4]f32,
	primary, primary_content:                   [4]f32,
	secondary, secondary_content:               [4]f32,
	accent, accent_content:                     [4]f32,
	neutral, neutral_content:                   [4]f32,
	info, info_content:                         [4]f32,
	success, success_content:                   [4]f32,
	warning, warning_content:                   [4]f32,
	error, error_content:                       [4]f32,
	// Menus, popovers, toasts and the shadow under them. daisyUI has no names for these.
	popover, shadow:                            [4]f32,
}

// Which palette kit.colors takes. .System follows macOS, and changes with it.
appearance: platform.Appearance

// Change them in main before app.run. A zero primary takes the accent colour of System Settings.
dark_colors := Colors {
	base_100          = to_color(0x0e0e10ff),
	base_200          = to_color(0x1b1b1eff),
	base_300          = to_color(0x2a2a2fff),
	base_content      = to_color(0xf2f2f4ff),
	primary_content   = to_color(0xffffffff),
	secondary         = to_color(0x5e5ce6ff),
	secondary_content = to_color(0xffffffff),
	accent            = to_color(0xff375fff),
	accent_content    = to_color(0xffffffff),
	neutral           = to_color(0xaeaeb4ff),
	neutral_content   = to_color(0x1d1d1fff),
	info              = to_color(0x5ac8f5ff),
	info_content      = to_color(0x1d1d1fff),
	success           = to_color(0x32d74bff),
	success_content   = to_color(0x1d1d1fff),
	warning           = to_color(0xffd60aff),
	warning_content   = to_color(0x1d1d1fff),
	error             = to_color(0xff453aff),
	error_content     = to_color(0xffffffff),
	popover           = to_color(0x2c2c31f5),
	shadow            = {0, 0, 0, 0.45},
}

light_colors := Colors {
	base_100          = to_color(0xffffffff),
	base_200          = to_color(0xf2f2f4ff),
	base_300          = to_color(0xe8e8ecff),
	base_content      = to_color(0x1d1d1fff),
	primary_content   = to_color(0xffffffff),
	secondary         = to_color(0x5856d6ff),
	secondary_content = to_color(0xffffffff),
	accent            = to_color(0xff2d55ff),
	accent_content    = to_color(0xffffffff),
	neutral           = to_color(0x1d1d1fff),
	neutral_content   = to_color(0xffffffff),
	info              = to_color(0x55bef0ff),
	info_content      = to_color(0x1d1d1fff),
	success           = to_color(0x28cd41ff),
	success_content   = to_color(0x1d1d1fff),
	warning           = to_color(0xffcc00ff),
	warning_content   = to_color(0x1d1d1fff),
	error             = to_color(0xff3b30ff),
	error_content     = to_color(0xffffffff),
	popover           = to_color(0xfbfbfcf5),
	shadow            = {0, 0, 0, 0.16},
}

// Components read this copy of the palette in use, with its primary set.
colors := Colors{}

@(init)
_start_colors :: proc "contextless" () {
	colors = dark_colors
	colors.primary = DEFAULT_PRIMARY
}

DEFAULT_PRIMARY :: [4]f32{0x0a / 255.0, 0x84 / 255.0, 1, 1}

// Opacities of base_content for grey surfaces and lines, as daisyUI's base-content/10.
HOVER_OPACITY :: 0.07
SELECTED_OPACITY :: 0.1
LINE_OPACITY :: 0.12
TRACK_OPACITY :: 0.18

// Opacities of a tone behind a Soft control, at rest, hovered and pressed.
SOFT_OPACITY :: 0x2e / 255.0
_SOFT_HOVER_OPACITY :: 0x48 / 255.0
_SOFT_PRESS_OPACITY :: 0x60 / 255.0

// What a control means. Base is a plain grey control.
Tone :: enum {
	Base,
	Primary,
	Secondary,
	Accent,
	Neutral,
	Info,
	Success,
	Warning,
	Error,
}

// Auto lets the component choose: Solid for a button with a label, Ghost for an icon-only one.
Variant :: enum {
	Auto,
	Solid,
	Soft,
	Outline,
	Ghost,
}

tone_colors :: proc(tone: Tone) -> (color, content: [4]f32) {
	switch tone {
	case .Base:
		color, content = colors.base_content, colors.base_100
	case .Primary:
		color, content = colors.primary, colors.primary_content
	case .Secondary:
		color, content = colors.secondary, colors.secondary_content
	case .Accent:
		color, content = colors.accent, colors.accent_content
	case .Neutral:
		color, content = colors.neutral, colors.neutral_content
	case .Info:
		color, content = colors.info, colors.info_content
	case .Success:
		color, content = colors.success, colors.success_content
	case .Warning:
		color, content = colors.warning, colors.warning_content
	case .Error:
		color, content = colors.error, colors.error_content
	}

	return
}

_BASE_OUTLINE_OPACITY :: 0.25

// hover_text is the label colour on hover, as an Outline control fills with its tone then.
_tone_style :: proc(tone: Tone, variant: Variant) -> (style: ui.Style, hover_text: [4]f32) {
	color, content := tone_colors(tone)
	solid := ui.Style {
		background       = color,
		hover_background = _to_darker(color, _FILL_HOVER_DARKEN),
		press_background = _to_darker(color, _FILL_PRESS_DARKEN),
		text_color       = content,
	}
	// A solid Base control is the plain grey one, not a fill of base_content.
	if tone == .Base {
		solid = {
			background       = to_faded(color, HOVER_OPACITY),
			hover_background = to_faded(color, _BUTTON_HOVER_ALPHA),
			press_background = to_faded(color, _BUTTON_PRESS_ALPHA),
			text_color       = color,
		}
	}
	text := _to_readable(color)

	switch variant {
	case .Auto, .Solid:
		style = solid
	case .Soft:
		style = {
			background       = to_faded(color, SOFT_OPACITY),
			hover_background = to_faded(color, _SOFT_HOVER_OPACITY),
			press_background = to_faded(color, _SOFT_PRESS_OPACITY),
			text_color       = text,
		}
	case .Outline:
		style = solid
		style.background = {}
		style.border_width = shape.border
		style.border_color = to_faded(color, _BASE_OUTLINE_OPACITY) if tone == .Base else color
		style.text_color = text
		return style, solid.text_color
	case .Ghost:
		style = {
			hover_background = to_faded(colors.base_content, HOVER_OPACITY),
			press_background = to_faded(colors.base_content, SELECTED_OPACITY),
			text_color       = text,
		}
	}

	return style, style.text_color
}

_READABLE_CONTRAST :: 3
_READABLE_STEP :: 0.35

// A tone too light to read on the window, as yellow on white, moves a step towards base_content.
_to_readable :: proc(color: [4]f32) -> [4]f32 {
	if _to_contrast(color, colors.base_100) >= _READABLE_CONTRAST do return color

	readable := mix_color(color, colors.base_content, _READABLE_STEP)
	readable.a = color.a

	return readable
}

// WCAG's contrast ratio between two colours, from 1 to 21. It ignores alpha.
_to_contrast :: proc(first, second: [4]f32) -> f32 {
	luminance :: proc(color: [4]f32) -> f32 {
		linear :: proc(channel: f32) -> f32 {
			return channel / 12.92 if channel <= 0.04045 else math.pow((channel + 0.055) / 1.055, 2.4)
		}

		return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
	}

	a, b := luminance(first), luminance(second)

	return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

// Corners and borders, with daisyUI's names. One shape serves both appearances.
Shape :: struct {
	// Checkboxes.
	radius_selector: f32,
	// Buttons and text fields. Rows, menu items and icon buttons take _FIELD_INSET_RADIUS less.
	radius_field:    f32,
	// Popovers, menus and toasts.
	radius_box:      f32,
	border:          f32,
}

_FIELD_INSET_RADIUS :: 2

shape := Shape {
	radius_selector = 4,
	radius_field    = 8,
	radius_box      = 10,
	border          = 1,
}

to_faded :: proc(color: [4]f32, opacity: f32) -> [4]f32 {
	return {color.r, color.g, color.b, color.a * opacity}
}

SMALL_TEXT_POINTS :: 12.5

_BUTTON_HEIGHT_POINTS :: 32

ICON_BUTTON_PADDING_POINTS :: 4

// amount is the share of the way to black. The alpha stays the same.
_to_darker :: proc(color: [4]f32, amount: f32) -> [4]f32 {
	return {color.r * (1 - amount), color.g * (1 - amount), color.b * (1 - amount), color.a}
}

mix_color :: proc(from, to: [4]f32, amount: f32) -> [4]f32 {
	return from + (to - from) * amount
}
