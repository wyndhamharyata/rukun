package kit

import "../ui"

MENU_ITEM_HEIGHT_POINTS :: 26

MENU_MARGIN_POINTS :: 8

// tone colors the label, like .Error for Delete. is_selected fills the row as focus would.
menu_item :: proc(
	id, label: string,
	hint := "",
	tone := Tone.Base,
	is_selected := false,
	is_disabled := false,
) -> ui.Signal {
	item := ui.box(
		id,
		{
			width = ui.fill(),
			height = ui.points(MENU_ITEM_HEIGHT_POINTS),
			axis = .X,
			align = .Center,
			padding = {9, 0, 9, 0},
			corner_radius = shape.radius_field - _FIELD_INSET_RADIUS,
			background = colors.primary if is_selected else {},
			hover_background = colors.primary,
			press_background = _to_darker(colors.primary, _FILL_HOVER_DARKEN),
			flags = {.Clickable, .No_Focus_Ring},
		},
	)
	if is_disabled {
		item.style.hover_background, item.style.press_background = {}, {}
		item.style.flags = {}
	}
	item.role, item.label, item.is_on = .Menu_Item, label, is_selected
	signal := ui.signal(item)
	// A focused item fills with primary, as in a macOS menu.
	if signal.is_focused do item.style.background = colors.primary
	if signal.is_activated do _close_popover()

	color, _ := tone_colors(tone)
	text_color := color
	if is_disabled do text_color = with_opacity(colors.base_content, 0.35)
	is_filled := !is_disabled && (is_selected || signal.is_focused || item._hot_fraction > 0.5)
	if is_filled do text_color = colors.primary_content

	if ui.scope(item) {
		ui.box(
			"",
			{
				width = ui.fill(),
				height = ui.fit_text(),
				text_color = text_color,
				font_size = 13,
				flags = {.Truncate_Text},
			},
			label,
		)

		if hint != "" {
			ui.box(
				"",
				{
					width = ui.fit_text(),
					height = ui.fit_text(),
					text_color = text_color if is_filled else with_opacity(colors.base_content, 0.5),
					font_size = 12,
				},
				hint,
			)
		}
	}

	return signal
}

// A line between menu items.
menu_separator :: proc() {
	ui.box("", {width = ui.fill(), height = ui.points(1), background = colors.line})
}
