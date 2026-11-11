package kit

import "../font"
import "../ui"

// Truncates, or wraps at width with is_wrapped. A zero color takes the theme's text colour.
// A zero line_height takes the line height for font_size from line_heights.
text :: proc(
	value: string,
	color: [4]f32 = {},
	font_size: f32 = 13,
	weight := font.Weight.Regular,
	width := ui.Size{.Fill, 1},
	align := ui.Align.Start,
	line_height: f32 = 0,
	is_wrapped := false,
) -> ui.Signal {
	style := ui.Style {
		width       = width,
		height      = ui.fit_text(),
		text_color  = color,
		text_align  = align,
		font_size   = font_size,
		font_weight = weight,
		line_height = line_height if line_height > 0 else to_line_height(font_size),
		flags       = {.Wrap_Text} if is_wrapped else {.Truncate_Text},
	}

	return ui.signal(ui.box("", style, value))
}

heading :: proc(value: string) -> ui.Signal {
	return text(value, font_size = 28, weight = .Bold)
}
