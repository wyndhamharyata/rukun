package kit

import "../ui"

_CARD_HOVER_LIGHTEN :: 0.06
_CARD_PRESS_LIGHTEN :: 0.1

// For a card or row that opens something; list_row selects. Inside the if, ui.here() is its Signal.
@(deferred_none = ui.pop_parent)
clickable :: proc(id: string, style: ui.Style = {}) -> bool {
	base := ui.Style {
		hover_background = to_faded(colors.base_content, HOVER_OPACITY),
		press_background = to_faded(colors.base_content, SELECTED_OPACITY),
		flags            = {.Clickable},
	}
	merged := ui.merge(base, style)
	// The row hover would show through a filled card, so hover mixes in the text colour.
	if style.background.a > 0 && style.hover_background == {} {
		merged.hover_background = mix_color(style.background, colors.base_content, _CARD_HOVER_LIGHTEN)
	}
	if style.background.a > 0 && style.press_background == {} {
		merged.press_background = mix_color(style.background, colors.base_content, _CARD_PRESS_LIGHTEN)
	}
	box := ui.box(id, merged)
	box.role, box.label = .Row, id
	ui.push_parent(box)

	return true
}
