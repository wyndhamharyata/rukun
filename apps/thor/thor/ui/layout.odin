package ui

import "../font"
import "core:math"

_DEFAULT_FONT_SIZE_POINTS :: 13

_read_font :: proc(style: Style) -> font.Font {
	size := style.font_size if style.font_size > 0 else _DEFAULT_FONT_SIZE_POINTS

	return font.system_font(style.font_weight, size * _state.pixels_per_point, style.font_family)
}

_to_padding_size :: proc(style: Style) -> [2]f32 {
	return {style.padding.x + style.padding.z, style.padding.y + style.padding.w}
}

_main_axis :: proc "contextless" (style: Style) -> Axis {
	return .Y if style.axis == .Y else .X
}

_to_axis :: proc "contextless" (index: int) -> Axis {
	return .Y if index == 1 else .X
}

_to_align_offset :: proc(align: Align, free_space: f32) -> f32 {
	switch align {
	case .Auto, .Start:
	case .Center:
		return math.round(free_space / 2)
	case .End:
		return free_space
	}

	return 0
}

_measure :: proc(box: ^Box) {
	for child := box.first; child != nil; child = child.next do _measure(child)

	if .Wrap_Text in box.style.flags && _is_text_size(box, box.style.width) {
		_warn(box, "the box has .Wrap_Text, but its width fits the text, so the text never wraps. Give the box a width, such as ui.fill().")
	}

	if box.text != "" {
		line_height := box.style.line_height * _state.pixels_per_point
		box.shaped = font.shape_text(box.text, _read_font(box.style), line_height_pixels = line_height)
	}

	box.size = {_measure_axis(box, .X), _measure_axis(box, .Y)}
}

_measure_axis :: proc(box: ^Box, axis: Axis) -> f32 {
	size := box.style.width if axis == .X else box.style.height
	padding := _to_padding_size(box.style)[_axis_index(axis)]
	value: f32

	switch {
	case size.kind == .Points:
		value = size.value
	case _is_text_size(box, size):
		value = padding
		if box.shaped != nil {
			value += math.ceil(box.shaped.size_pixels[_axis_index(axis)] / _state.pixels_per_point)
		}
	case _is_children_size(box, size):
		value = _children_extent(box, axis) + padding
	}

	return _clamp_size(box.style, axis, value)
}

_is_text_size :: proc(box: ^Box, size: Size) -> bool {
	return size.kind == .Text || (size.kind == .Fit && box.text != "")
}

_is_children_size :: proc(box: ^Box, size: Size) -> bool {
	return size.kind == .Children || (size.kind == .Fit && box.text == "")
}

_clamp_size :: proc(style: Style, axis: Axis, value: f32) -> f32 {
	value := value
	if style.max_size[_axis_index(axis)] > 0 do value = min(value, style.max_size[_axis_index(axis)])

	return max(value, style.min_size[_axis_index(axis)])
}

_children_extent :: proc(box: ^Box, axis: Axis) -> f32 {
	total: f32
	count := 0

	for child := box.first; child != nil; child = child.next {
		if .Floating in child.style.flags do continue

		count += 1

		if axis == _main_axis(box.style) {
			total += child.size[_axis_index(axis)]
		} else {
			total = max(total, child.size[_axis_index(axis)])
		}
	}

	if axis == _main_axis(box.style) && count > 1 do total += box.style.gap * f32(count - 1)

	return total
}

_resolve :: proc(box: ^Box) {
	style := box.style
	padding := _to_padding_size(style)

	_resolve_children(box, box.size - padding)

	for child := box.first; child != nil; child = child.next do _resolve(child)

	if _is_children_size(box, style.width) && _main_axis(style) == .Y {
		box.size.x = _clamp_size(style, .X, _children_extent(box, .X) + padding.x)
	}

	if _is_children_size(box, style.height) {
		extent := _wrap_lines(box, nil) if _is_wrapping(box) else _children_extent(box, .Y)
		box.size.y = _clamp_size(style, .Y, extent + padding.y)
	}
}

_is_wrapping :: proc(box: ^Box) -> bool {
	return .Wrap_Children in box.style.flags && _main_axis(box.style) == .X
}

_wrap_lines :: proc(box: ^Box, clip: ^[4]f32) -> f32 {
	style := box.style
	inner_width := box.size.x - _to_padding_size(style).x
	line_top: f32
	line := box.first

	for line != nil {
		width, height: f32
		end := line
		count := 0

		for child := line; child != nil; child = child.next {
			if .Floating in child.style.flags {
				end = child.next
				continue
			}

			next_width := width + child.size.x + (style.gap if count > 0 else 0)
			is_line_full := count > 0 && next_width > inner_width

			if is_line_full do break

			width = next_width
			height = max(height, child.size.y)
			count += 1
			end = child.next
		}

		if clip != nil {
			pen := [2]f32{box.rect.x + style.padding.x, box.rect.y + style.padding.y + line_top}

			for child := line; child != end; child = child.next {
				if .Floating in child.style.flags {
					_place(child, {box.rect.x, box.rect.y} + child.style.position, clip^)
					continue
				}

				origin := pen
				origin.y += _to_align_offset(style.align, height - child.size.y)

				_place(child, origin, clip^)
				pen.x += child.size.x + style.gap
			}
		}

		line_top += height
		line = end
		if line != nil do line_top += style.gap
	}

	return line_top
}

_place :: proc(box: ^Box, origin: [2]f32, clip: [4]f32) {
	box.rect = {origin.x, origin.y, origin.x + box.size.x, origin.y + box.size.y}
	box.clip = clip

	style := box.style
	inner := box.size - _to_padding_size(style)
	main := _axis_index(style.axis)
	cross := 1 - main

	child_clip := _intersect(clip, box.rect) if .Clip in style.flags else clip
	extent := _children_extent(box, _main_axis(style))

	box.content_size = {0, 0}
	box.content_size[main] = extent + style.padding[main] + style.padding[main + 2]

	if .Scroll in style.flags {
		max_scroll := max(0, box.content_size[main] - box.size[main])
		box._scroll_target = clamp(box._scroll_target, 0, max_scroll)
		box.scroll = clamp(
			_approach(box.scroll, box._scroll_target, HOT_RATE_PER_SECOND),
			0,
			max_scroll,
		)
	}
	box._placed_scroll = box.scroll

	if _is_wrapping(box) {
		_wrap_lines(box, &child_clip)
		return
	}

	pen := [2]f32{box.rect.x + style.padding.x, box.rect.y + style.padding.y}
	if .Scroll in style.flags do pen[main] -= box.scroll
	if .Scroll not_in style.flags {
		pen[main] += _to_align_offset(style.justify, max(0, inner[main] - extent))
	}

	for child := box.first; child != nil; child = child.next {
		if .Floating in child.style.flags {
			_place(child, {box.rect.x, box.rect.y} + child.style.position, child_clip)
			continue
		}

		child_origin := pen
		child_origin[cross] += _to_align_offset(style.align, inner[cross] - child.size[cross])

		_place(child, child_origin, child_clip)
		pen[main] += child.size[main] + style.gap
	}
}

_resolve_children :: proc(box: ^Box, inner: [2]f32) {
	main := _axis_index(box.style.axis)
	cross := 1 - main
	used: f32
	fill_weight: f32
	count := 0

	for child := box.first; child != nil; child = child.next {
		if .Floating in child.style.flags {
			if child.style.width.kind == .Fill do child.size.x = _clamp_size(child.style, .X, inner.x)
			if child.style.height.kind == .Fill do child.size.y = _clamp_size(child.style, .Y, inner.y)
			continue
		}

		sizes := [2]Size{child.style.width, child.style.height}
		count += 1

		// A parent that fits its children has no space left for a fill child.
		box_sizes := [2]Size{box.style.width, box.style.height}
		is_fit := _is_children_size(box, box_sizes[main]) && box.style.min_size[main] == 0
		if is_fit && sizes[main].kind == .Fill {
			_warn(
				child,
				"the box fills the parent's %s, but the parent fits its children, so the box gets no space. Give the parent a size, or give this box one, such as ui.fit_text().",
				"width" if main == 0 else "height",
			)
		}

		if sizes[cross].kind == .Fill {
			child.size[cross] = _clamp_size(child.style, _to_axis(cross), inner[cross])
		}

		if sizes[main].kind == .Fill {
			fill_weight += sizes[main].value
		} else {
			used += child.size[main]
		}
	}

	if count > 1 do used += box.style.gap * f32(count - 1)

	leftover := max(0, inner[main] - used)
	extent: [2]f32
	if count > 1 do extent[main] = box.style.gap * f32(count - 1)

	for child := box.first; child != nil; child = child.next {
		sizes := [2]Size{child.style.width, child.style.height}
		is_fill :=
			.Floating not_in child.style.flags && sizes[main].kind == .Fill && fill_weight > 0
		is_fitted_text := .Wrap_Text in child.style.flags || .Truncate_Text in child.style.flags

		// shortcut: max_size leaves part of a fill child's share unused. Give it to the others if needed.
		if is_fill {
			share := math.floor(leftover * sizes[main].value / fill_weight)
			child.size[main] = _clamp_size(child.style, _to_axis(main), share)
		}
		if is_fitted_text do _fit_text_to_width(child)

		if .Floating not_in child.style.flags {
			extent[main] += child.size[main]
			extent[cross] = max(extent[cross], child.size[cross])
		}
	}

	// .Clip without .Scroll cuts the children on purpose. .Scroll holds them on its main axis only.
	is_held := (.Clip in box.style.flags && .Scroll not_in box.style.flags) || _is_wrapping(box)
	// A box that fits its children grows to them after this.
	excess := extent - inner
	if .Scroll in box.style.flags do excess[main] = 0
	if _is_children_size(box, box.style.width) do excess.x = 0
	if _is_children_size(box, box.style.height) do excess.y = 0
	overflow := max(excess.x, excess.y)
	// A layout that asked for another frame, as a list measuring its rows does, is not settled yet.
	if !is_held && count > 0 && overflow >= 1 && !_state.is_frame_requested {
		_warn(
			box,
			"the children overflow the box by %.0f points at %.0f%% zoom. Add .Scroll or .Clip, or make the children smaller.",
			overflow,
			_state.zoom * 100,
		)
	}
}

_fit_text_to_width :: proc(box: ^Box) {
	if box.text == "" do return

	padding := _to_padding_size(box.style)
	inner_width := box.size.x - padding.x
	overflow := font.Overflow.Truncate if .Truncate_Text in box.style.flags else font.Overflow.Wrap

	box.shaped = font.shape_text(
		box.text,
		_read_font(box.style),
		inner_width * _state.pixels_per_point,
		overflow,
		box.style.line_height * _state.pixels_per_point,
	)

	if _is_text_size(box, box.style.height) {
		height := math.ceil(box.shaped.size_pixels.y / _state.pixels_per_point) + padding.y
		box.size.y = _clamp_size(box.style, .Y, height)
	}
}

_intersect :: proc(a, b: [4]f32) -> [4]f32 {
	return {max(a.x, b.x), max(a.y, b.y), min(a.z, b.z), min(a.w, b.w)}
}
