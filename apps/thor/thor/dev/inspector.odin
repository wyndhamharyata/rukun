package dev

import "../kit"
import "../platform"
import "../ui"
import "core:fmt"
import "core:mem"
import "core:reflect"
import "core:strings"

INSPECTOR_WIDTH_POINTS :: 340
INSPECTOR_ROW_POINTS :: 20


_INSPECTOR_ID :: "thor_inspector"

_Inspected :: struct {
	path:  string,
	label: string,
	depth: int,
	rect:  [4]f32,
	clip:  [4]f32,
	style: ui.Style,
	text:  string,
}

is_inspecting: bool
is_outlining: bool

_inspector: struct {
	// read_inspector_tree copies each box's strings and frees them when it reads the next tree.
	boxes:    [dynamic]_Inspected,
	// The path of the box that the person selected in the list. It outlives the frame.
	selected: string,
	hovered:  int,
	// The inspector panel's rect last frame. The pointer in it points at the panel, not the app.
	panel:    [4]f32,
}

// Call with each frame's events, before the app builds its boxes.
apply_inspector_keys :: proc(events: []platform.Event) {
	for event in events {
		press := event.(platform.Key_Press) or_continue
		if press.modifiers != {.Command, .Option} do continue

		#partial switch press.key {
		case .I:
			is_inspecting = !is_inspecting
		case .O:
			if is_inspecting do is_outlining = !is_outlining
		}
		ui.request_frame()
	}
}

// Call it after the app builds its boxes, at the root.
build_inspector :: proc() {
	if !is_inspecting do return

	boxes := _inspector.boxes[:]
	mouse := ui.mouse_position()
	_inspector.hovered = -1
	if !_is_inside(_inspector.panel, mouse) {
		for box, index in boxes {
			if _is_inside(box.rect, mouse) && _is_inside(box.clip, mouse) do _inspector.hovered = index
		}
	}

	shown := _inspector.hovered
	if shown < 0 {
		for box, index in boxes {
			if box.path == _inspector.selected do shown = index
		}
	}

	layer := ui.Style {
		width  = ui.fill(),
		height = ui.fill(),
		axis   = .X,
		flags  = {.Floating},
	}
	if ui.overlay(_INSPECTOR_ID, layer) {
		if is_outlining {
			outline := kit.to_faded(kit.colors.primary, 0.35)
			for box in boxes do _mark(box, {}, outline)
		}
		if shown >= 0 do _mark(boxes[shown], kit.to_faded(kit.colors.primary, 0.18), kit.colors.primary)

		ui.box("", {width = ui.fill(), height = ui.fill()})
		panel := ui.Style {
			width        = ui.points(INSPECTOR_WIDTH_POINTS),
			height       = ui.fill(),
			axis         = .Y,
			padding      = {12, 12, 12, 12},
			gap          = 8,
			background   = kit.colors.base_200,
			border_width = 1,
			border_color = kit.to_faded(kit.colors.base_content, kit.LINE_OPACITY),
			flags        = {.Clickable},
		}
		if ui.col("panel", panel) {
			window := ui.window_size()
			kit.text(fmt.tprintf("zoom %.0f%%  window %.0f × %.0f", ui._state.zoom * 100, window.x, window.y), kit.to_faded(kit.colors.base_content, 0.7), 12)
			if shown >= 0 do _build_details(boxes[shown])
			kit.divider()
			_build_tree(boxes)
		}
	}
}

// Call it after ui._end_frame, so the next frame's inspector has each box's place and style.
read_inspector_tree :: proc() {
	if !is_inspecting do return

	for box in _inspector.boxes {
		delete(box.path)
		delete(box.label)
		delete(box.text)
	}
	clear(&_inspector.boxes)
	_inspector.panel = {}

	for root in ([]^ui.Box{ui._state.root, ui._state.overlay_root}) {
		for child := root.first; child != nil; child = child.next do _read_box(child, 0)
	}
}

_read_box :: proc(box: ^ui.Box, depth: int) {
	if box.id == _INSPECTOR_ID {
		if panel := ui.find_box("panel", box); panel != nil do _inspector.panel = panel.rect
		return
	}

	label := box.id
	if label == "" do label = fmt.tprintf("\"%s\"", ui._to_short(box.text)) if box.text != "" else "_"
	inspected := _Inspected {
		path  = strings.clone(ui._to_box_path(box)),
		label = strings.clone(label),
		depth = depth,
		rect  = box.rect,
		clip  = box.clip,
		style = box.style,
		text  = strings.clone(box.text),
	}
	append(&_inspector.boxes, inspected)

	for child := box.first; child != nil; child = child.next do _read_box(child, depth + 1)
}

// Marks the part of the box that its parents do not clip.
_mark :: proc(box: _Inspected, background, border: [4]f32) {
	rect := [4]f32 {
		max(box.rect.x, box.clip.x),
		max(box.rect.y, box.clip.y),
		min(box.rect.z, box.clip.z),
		min(box.rect.w, box.clip.w),
	}
	if rect.z <= rect.x || rect.w <= rect.y do return

	style := ui.Style {
		width        = ui.points(rect.z - rect.x),
		height       = ui.points(rect.w - rect.y),
		position     = {rect.x, rect.y},
		background   = background,
		border_width = 1,
		border_color = border,
		flags        = {.Floating},
	}
	ui.box("", style)
}

_build_details :: proc(box: _Inspected) {
	kit.text(box.path, is_wrapped = true)
	small :: proc(text: string) {kit.text(text, kit.to_faded(kit.colors.base_content, 0.7), 12)}

	rect := box.rect
	small(fmt.tprintf("x %.0f  y %.0f  w %.0f  h %.0f", rect.x, rect.y, rect.z - rect.x, rect.w - rect.y))
	small(fmt.tprintf("width %s  height %s", _to_size_text(box.style.width), _to_size_text(box.style.height)))

	style := box.style
	zero: ui.Style
	for field in reflect.struct_fields_zipped(ui.Style) {
		if field.name == "width" || field.name == "height" do continue
		value := mem.byte_slice(rawptr(uintptr(&style) + field.offset), field.type.size)
		if mem.compare(value, mem.byte_slice(rawptr(uintptr(&zero) + field.offset), field.type.size)) == 0 do continue

		data := rawptr(uintptr(&style) + field.offset)
		is_color :=
			field.type.id == typeid_of([4]f32) &&
			(strings.contains(field.name, "color") || strings.contains(field.name, "background"))
		if is_color {
			c := (cast(^[4]f32)data)^
			small(fmt.tprintf("%s #%02x%02x%02x%02x", field.name, u8(c.r * 255), u8(c.g * 255), u8(c.b * 255), u8(c.a * 255)))
		} else {
			value_text := fmt.tprintf("%v", any{data, field.type.id})
			small(fmt.tprintf("%s %s", field.name, strings.trim_prefix(value_text, "bit_set[Flag]")))
		}
	}
}

_to_size_text :: proc(size: ui.Size) -> string {
	switch size.kind {
	case .Points:
		return fmt.tprintf("points(%v)", size.value)
	case .Fill:
		return fmt.tprintf("fill(%v)", size.value)
	case .Children:
		return "fit children"
	case .Text:
		return "fit text"
	case .Fit:
		return "fit"
	}
	return "?"
}

_build_tree :: proc(boxes: []_Inspected) {
	if first, last, ok := kit.list("tree", len(boxes), INSPECTOR_ROW_POINTS); ok {
		for box, offset in boxes[first:last] {
			index := first + offset
			is_marked := index == _inspector.hovered || box.path == _inspector.selected
			row := ui.Style {
				width            = ui.fill(),
				height           = ui.points(INSPECTOR_ROW_POINTS),
				axis             = .X,
				align            = .Center,
				padding          = {4 + f32(box.depth) * 12, 0, 4, 0},
				corner_radius    = 4,
				background       = kit.to_faded(kit.colors.primary, kit.SOFT_OPACITY) if is_marked else {},
				hover_background = kit.to_faded(kit.colors.base_content, kit.HOVER_OPACITY),
				flags            = {.Clickable},
			}
			box_row := ui.box(fmt.tprint(index), row)
			if ui.signal(box_row).is_activated {
				delete(_inspector.selected)
				_inspector.selected = strings.clone(box.path)
			}
			if ui.scope(box_row) do kit.text(box.label, kit.colors.base_content if is_marked else kit.to_faded(kit.colors.base_content, 0.7), 12)
		}
	}
}

_is_inside :: proc(rect: [4]f32, point: [2]f32) -> bool {
	return point.x >= rect.x && point.x < rect.z && point.y >= rect.y && point.y < rect.w
}
