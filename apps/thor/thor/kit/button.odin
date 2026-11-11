package kit

import "../ui"

Button_Size :: enum {
	Medium,
	Small,
	Large,
}

// Press goes one step past hover. A colour fill darkens; a grey fill moves towards the text colour.
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

// icon is an SF Symbol name. With no label, the button is a square and Auto means Ghost, not Solid.
// A zero icon_color takes the label's colour. A disabled button fades and takes no clicks.
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
	box.role, box.label = .Button, label if !is_icon_only else id
	color := hover_text if !is_disabled && box._hot_fraction > 0.5 else look.text_color

	if ui.scope(box) {
		if icon != "" do icon_box(icon, symbol_size, icon_color if icon_color.a > 0 && !is_disabled else color)
		if !is_icon_only {
			ui.box("", {text_color = color, font_size = metrics.font_size, font_weight = .Semibold}, label)
		}
	}

	return ui.signal(box)
}
