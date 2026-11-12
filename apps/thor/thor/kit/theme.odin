package kit

import "../platform"
import "../ui"
import "core:math"
import "core:strconv"

// {font size, line height} pairs in points; other sizes keep the font's own line height.
line_heights := [][2]f32{{12, 16}, {13, 18}, {15, 20}, {28, 36}}

// The line height for a font size in line_heights, or 0 for the font's own.
to_line_height :: proc(font_size: f32) -> f32 {
	for pair in line_heights {
		if pair[0] == font_size do return pair[1]
	}
	return 0
}

// A color from 0xRRGGBBAA.
to_color :: proc "contextless" (hex: u32) -> [4]f32 {
	return {
		f32((hex >> 24) & 0xff) / 255,
		f32((hex >> 16) & 0xff) / 255,
		f32((hex >> 8) & 0xff) / 255,
		f32(hex & 0xff) / 255,
	}
}

// Parses #3b82f6 or 3b82f6, and returns false for any other text.
to_color_from_hex :: proc(hex: string) -> (color: [4]f32, ok: bool) {
	digits := hex[1:] if len(hex) > 0 && hex[0] == '#' else hex
	if len(digits) != 6 do return {}, false

	value := strconv.parse_u64_of_base(digits, 16) or_return

	return to_color(u32(value << 8) | 0xff), true
}

// Names from daisyUI. Each x_content colors text and icons on a fill of x.
Colors :: struct {
	// base_100 is the window; base_200 and base_300 step lighter in Dark and darker in Light.
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
	// Borders, dividers, and table lines: base_content at 12%.
	line:                                       [4]f32,
}

// Which palette kit.colors uses. .System follows macOS and changes with it.
appearance: platform.Appearance

// Override in main before app.run. A zero primary takes the System Settings accent color.
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
	line              = {0xf2 / 255.0, 0xf2 / 255.0, 0xf4 / 255.0, 0.12},
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
	line              = {0x1d / 255.0, 0x1d / 255.0, 0x1f / 255.0, 0.12},
}

// The palette in use, with its primary set. Components read this copy.
colors := Colors{}

@(init)
_start_colors :: proc "contextless" () {
	colors = dark_colors
	colors.primary = DEFAULT_PRIMARY
}

DEFAULT_PRIMARY :: [4]f32{0x0a / 255.0, 0x84 / 255.0, 1, 1}

// base_content opacities for gray surfaces and lines, like daisyUI's base-content/10.
HOVER_OPACITY :: 0.07
SELECTED_OPACITY :: 0.1
TRACK_OPACITY :: 0.18

// Tone opacities behind a Soft control: resting, hovered, and pressed.
SOFT_OPACITY :: 0x2e / 255.0
_SOFT_HOVER_OPACITY :: 0x48 / 255.0
_SOFT_PRESS_OPACITY :: 0x60 / 255.0

// What a control means; Base is a plain gray control.
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

// The tone's color, and the color of text and icons on it.
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

// hover_text colors the label on hover, when an Outline control fills with its tone.
_tone_style :: proc(tone: Tone, variant: Variant) -> (style: ui.Style, hover_text: [4]f32) {
	color, content := tone_colors(tone)
	solid := ui.Style {
		background       = color,
		hover_background = _to_darker(color, _FILL_HOVER_DARKEN),
		press_background = _to_darker(color, _FILL_PRESS_DARKEN),
		text_color       = content,
	}
	// A solid Base control is the plain gray one, not a base_content fill.
	if tone == .Base {
		solid = {
			background       = with_opacity(color, HOVER_OPACITY),
			hover_background = with_opacity(color, _BUTTON_HOVER_ALPHA),
			press_background = with_opacity(color, _BUTTON_PRESS_ALPHA),
			text_color       = color,
		}
	}

	switch variant {
	case .Auto, .Solid:
		style = solid
	case .Soft:
		style = {
			background       = with_opacity(color, SOFT_OPACITY),
			hover_background = with_opacity(color, _SOFT_HOVER_OPACITY),
			press_background = with_opacity(color, _SOFT_PRESS_OPACITY),
			text_color       = color,
		}
	case .Outline:
		style = solid
		style.background = {}
		style.border_width = shape.border
		style.border_color = with_opacity(color, _BASE_OUTLINE_OPACITY) if tone == .Base else color
		style.text_color = color
		return style, solid.text_color
	case .Ghost:
		style = {
			hover_background = with_opacity(colors.base_content, HOVER_OPACITY),
			press_background = with_opacity(colors.base_content, SELECTED_OPACITY),
			text_color       = color,
		}
	}

	return style, style.text_color
}

// Blends in linear light with Ghostty's correction so text keeps its weight. Off by default: kit's
// tints came from daisyUI, which browsers blend in gamma, so they look fainter in Light and
// stronger in Dark.
is_blending_linear: bool

// A color from Display P3 values, as a designer picks on a Mac. On a P3 screen it can be more
// vivid than any sRGB color, so channels may fall below 0 or above 1.
to_color_from_p3 :: proc(red, green, blue: f32, alpha: f32 = 1) -> [4]f32 {
	linear :: proc(c: f32) -> f32 {
		a := abs(c)
		v := a / 12.92 if a <= 0.04045 else math.pow((a + 0.055) / 1.055, 2.4)
		return v if c >= 0 else -v
	}
	gamma :: proc(c: f32) -> f32 {
		a := abs(c)
		v := a * 12.92 if a <= 0.0031308 else 1.055 * math.pow(a, 1 / 2.4) - 0.055
		return v if c >= 0 else -v
	}
	r, g, b := linear(red), linear(green), linear(blue)
	// Converts linear Display P3 to linear sRGB, both D65.
	return {
		gamma(1.2249401 * r - 0.2249404 * g),
		gamma(-0.0420569 * r + 1.0420571 * g),
		gamma(-0.0196376 * r - 0.0786361 * g + 1.0982735 * b),
		alpha,
	}
}

// Least WCAG contrast for text and icons against the color under them. 3 is AA for large text;
// Increase Contrast raises it to at least 4.5, AA for body text.
min_contrast: f32 = 3

// Corner radii and borders, with daisyUI's names. One shape serves both appearances.
Shape :: struct {
	// Corner radius for checkboxes.
	radius_selector: f32,
	// Buttons and text fields; rows, menu items, and icon buttons take _FIELD_INSET_RADIUS less.
	radius_field:    f32,
	// Popovers, menus, and toasts.
	radius_box:      f32,
	border:          f32,
}

_FIELD_INSET_RADIUS :: 2

// fast for hovers and knobs, normal for moves, slow for large panels.
Motions :: struct {
	fast, normal, slow: ui.Motion,
}

motion := Motions {
	fast = {duration = 0.15},
	normal = {duration = 0.25},
	slow = {duration = 0.4, bounce = 0.15},
}

// The shadows under kit's menus and dialogs. Their color follows colors.shadow.
Shadows :: struct {
	menu, dialog: ui.Shadow,
}

shadows := Shadows {
	menu   = {offset = {0, 8}, blur = 12},
	dialog = {offset = {0, 12}, blur = 20},
}

shape := Shape {
	radius_selector = 4,
	radius_field    = 8,
	radius_box      = 10,
	border          = 1,
}

// The color with its alpha scaled by opacity.
with_opacity :: proc(color: [4]f32, opacity: f32) -> [4]f32 {
	return {color.r, color.g, color.b, color.a * opacity}
}

SMALL_TEXT_POINTS :: 12.5

_BUTTON_HEIGHT_POINTS :: 32

ICON_BUTTON_PADDING_POINTS :: 4

// Moves amount of the way to black; alpha stays the same.
_to_darker :: proc(color: [4]f32, amount: f32) -> [4]f32 {
	return {color.r * (1 - amount), color.g * (1 - amount), color.b * (1 - amount), color.a}
}

// Blends from to to: 0 gives from, 1 gives to.
mix_color :: proc(from, to: [4]f32, amount: f32) -> [4]f32 {
	return from + (to - from) * amount
}
