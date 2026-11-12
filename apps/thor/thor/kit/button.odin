package kit

import "../ui"

Button_Size :: enum {
	Medium,
	Small,
	Large,
}

// Press darkens one step past hover; a gray fill moves toward the text color instead.
_FILL_HOVER_DARKEN :: 0.15
_FILL_PRESS_DARKEN :: 0.3

_BUTTON_HOVER_ALPHA :: 0.14
_BUTTON_PRESS_ALPHA :: 0.2

_DISABLED_OPACITY :: 0.5

_Button_Metrics :: struct {
	height, font_size, icon_size, padding: f32,
}

_button_metrics := [Button_Size]_Button_Metrics {
	.Medium = {_BUTTON_HEIGHT_POINTS, 13, 12, 16},
	.Small  = {26, 12, 11, 12},
	.Large  = {40, 15, 14, 20},
}

// icon is an SF Symbol name. Without a label, the button is square and Auto uses Ghost style, and
// tooltip shows on hover and is what VoiceOver reads.
// A zero icon_color uses the label color. Disabled buttons fade and ignore clicks.
button :: proc(
	id: string,
	label := "",
	icon := "",
	tone := Tone.Base,
	variant := Variant.Auto,
	size := Button_Size.Medium,
	// Only for an icon with no label; 0 fits the icon to the button's height.
	icon_size: f32 = 0,
	icon_color: [4]f32 = {},
	is_disabled := false,
	style: ui.Style = {},
	tooltip := "",
) -> ui.Signal {
	metrics := _button_metrics[size]
	is_icon_only := label == ""
	shown_variant := variant
	if shown_variant == .Auto do shown_variant = .Ghost if is_icon_only else .Solid
	look, hover_text := _tone_style(tone, shown_variant)
	if is_disabled {
		look.background = with_opacity(look.background, _DISABLED_OPACITY)
		look.border_color = with_opacity(look.border_color, _DISABLED_OPACITY)
		look.hover_background, look.press_background = look.background, look.background
		look.text_color = with_opacity(colors.base_content, 0.5)
	}

	look.axis = .X
	look.align = .Center
	look.justify = .Center
	look.flags = {} if is_disabled else {.Clickable}
	symbol_size := metrics.icon_size
	if is_icon_only {
		symbol_size = icon_size if icon_size > 0 else metrics.height - 2 * ICON_BUTTON_PADDING_POINTS
		side := symbol_size + 2 * ICON_BUTTON_PADDING_POINTS
		look.width = ui.points(side)
		look.height = ui.points(side)
		look.corner_radius = shape.radius_field - _FIELD_INSET_RADIUS
	} else {
		// An icon needs less left padding to look even with the label's right edge.
		left_padding := metrics.padding - 2 if icon != "" else metrics.padding
		look.width = ui.fit_children()
		look.height = ui.points(metrics.height)
		look.gap = 6
		look.padding = {left_padding, 0, metrics.padding, 0}
		look.corner_radius = shape.radius_field * metrics.height / _BUTTON_HEIGHT_POINTS
	}
	box := ui.box(id, ui.merge(look, style))
	box.role, box.label = .Button, label if !is_icon_only else tooltip if tooltip != "" else id
	color := hover_text if !is_disabled && box._hot_fraction > 0.5 else look.text_color

	if ui.scope(box) {
		if icon != "" do icon_box(icon, symbol_size, icon_color if icon_color.a > 0 && !is_disabled else color)
		if !is_icon_only {
			ui.box("", {text_color = color, font_size = metrics.font_size, font_weight = .Semibold}, label)
		}
	}
	if tooltip != "" do _show_tooltip(box, tooltip)

	return ui.signal(box)
}
