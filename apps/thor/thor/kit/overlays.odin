package kit

import "../platform"
import "../ui"
import "core:math"
import "core:time"

_TOOLTIP_DELAY_SECONDS :: 0.8
_TOOLTIP_GAP_POINTS :: 6

_DIALOG_PADDING_POINTS :: 20

_Tooltip :: struct {
	// The element the pointer rests on, and since when.
	_key:         u64,
	rested_at:    time.Tick,
	// A press or a key hides it until the pointer leaves.
	is_dismissed: bool,
	shown_frame:  int,
}

// The anchor must take the pointer: a control, or a box with .Hoverable.
tooltip :: proc(anchor: Anchor, text: string) {
	anchor_box, anchor_rect, ok := _to_anchor(anchor)
	// A point has nothing for the pointer to rest on.
	if !ok || anchor_box == nil do return

	if !ui.signal(anchor_box).is_hovered {
		if _window.tooltip._key == anchor_box._key do _window.tooltip._key = 0
		return
	}

	now := platform.now()
	frame := ui._state.frame_index
	if _window.tooltip._key != anchor_box._key {
		is_switching := _window.tooltip.shown_frame > 0 && _window.tooltip.shown_frame >= frame - 1
		_window.tooltip = {
			_key        = anchor_box._key,
			rested_at   = now,
			shown_frame = _window.tooltip.shown_frame,
		}
		if is_switching do _window.tooltip.rested_at = time.tick_add(now, -time.Duration(_TOOLTIP_DELAY_SECONDS * f64(time.Second)))
	}
	if ui._state.is_pressed || ui._state.pressed_keys != {} do _window.tooltip.is_dismissed = true
	if _window.tooltip.is_dismissed do return

	waited := time.duration_seconds(time.tick_diff(_window.tooltip.rested_at, now))
	if waited < _TOOLTIP_DELAY_SECONDS {
		ui.request_frame_after(_TOOLTIP_DELAY_SECONDS - waited)
		return
	}
	_window.tooltip.shown_frame = frame

	last := ui.find_box("tooltip", ui._state.overlay_root)
	size := last.size if last != nil else {}
	window := ui.window_size()
	position := [2]f32{math.round((anchor_rect.x + anchor_rect.z - size.x) / 2), anchor_rect.w + _TOOLTIP_GAP_POINTS}
	if position.y + size.y > window.y - MENU_MARGIN_POINTS do position.y = anchor_rect.y - _TOOLTIP_GAP_POINTS - size.y
	position.x = clamp(position.x, MENU_MARGIN_POINTS, max(MENU_MARGIN_POINTS, window.x - size.x - MENU_MARGIN_POINTS))

	look := ui.Style {
		padding       = {8, 4, 8, 4},
		corner_radius = shape.radius_field - _FIELD_INSET_RADIUS,
		background    = colors.popover,
		border_width  = shape.border,
		border_color  = to_faded(colors.base_content, LINE_OPACITY),
		text_color    = colors.base_content,
		font_size     = 12,
		position      = position,
		// Kit hides it until the first layout, so it never shows in the wrong place.
		fade          = 0 if size.y > 0 else 1,
		flags         = {.Floating},
	}
	ui.push_parent(ui._state.overlay_root)
	box := ui.box("tooltip", look, text)
	box.role, box.label = .Tooltip, text
	ui.pop_parent()
	if size.y == 0 do ui.request_frame()
}

_Dialog :: struct {
	// The box that had keyboard focus when the dialog opened, which gets it back when it closes.
	return_focus: u64,
	panel:        ^ui.Box,
	is_open:      ^bool,
	is_new:       bool,
}

// Escape sets is_open^ to false. A click on the dimmed page does not.
// shortcut: kit keeps the focus of one dialog to give back, add a stack for a dialog over a dialog.
@(deferred_out = _end_dialog)
dialog :: proc(id: string, is_open: ^bool, width: f32 = 400) -> bool {
	return _begin_dialog(id, is_open, width, _DIALOG_PADDING_POINTS, 12, -1)
}

// top is in points from the window's top. A negative top puts the panel in the middle.
_begin_dialog :: proc(id: string, is_open: ^bool, width, padding, gap, top: f32) -> bool {
	last := ui.find_box(id, ui._state.overlay_root)
	if !is_open^ {
		// The dialog closed this frame: focus goes back to where it was.
		if last != nil && _window.dialog.return_focus != 0 {
			if returned := ui._find_box_with_key(_window.dialog.return_focus); returned != nil do ui.focus(returned)
			_window.dialog.return_focus = 0
		}
		return false
	}
	if last == nil do _window.dialog.return_focus = ui._state.focused_key

	window := ui.window_size()
	backdrop_look := ui.Style {
		width      = ui.points(window.x),
		height     = ui.points(window.y),
		background = colors.shadow,
		flags      = {.Floating, .Modal, .Hoverable},
	}
	ui.push_parent(ui._state.overlay_root)
	backdrop := ui.box(id, backdrop_look)
	ui.pop_parent()

	last_panel := ui.find_box("panel", backdrop)
	size := last_panel.size if last_panel != nil else {}
	position := [2]f32{math.round((window.x - size.x) / 2), math.round(max(0, window.y - size.y) / 2)}
	if top >= 0 do position.y = top

	ui.push_parent(backdrop)
	if size.y > 0 {
		shadow := ui.Style {
			width         = ui.points(size.x),
			height        = ui.points(size.y),
			corner_radius = shape.radius_box + 2,
			background    = colors.shadow,
			softness      = 40,
			position      = position + {0, 12},
			flags         = {.Floating},
		}
		ui.box("shadow", shadow)
	}
	panel_look := ui.Style {
		width         = ui.points(width),
		height        = ui.fit_children(),
		axis          = .Y,
		gap           = gap,
		padding       = padding,
		corner_radius = shape.radius_box,
		background    = colors.popover,
		border_width  = shape.border,
		border_color  = to_faded(colors.base_content, LINE_OPACITY),
		position      = position,
		// Kit hides it until the first layout, so it never shows in the wrong place.
		fade          = 0 if size.y > 0 else 1,
		flags         = {.Floating},
	}
	panel := ui.box("panel", panel_look)
	panel.role, panel.label = .Dialog, id
	ui.pop_parent()
	ui.push_parent(panel)
	if size.y == 0 do ui.request_frame()

	_window.dialog.panel = panel
	_window.dialog.is_open = is_open
	_window.dialog.is_new = last == nil

	return true
}

_end_dialog :: proc(ok: bool) {
	if !ok do return

	if _window.dialog.is_new {
		if first := _find_first_clickable(_window.dialog.panel); first != nil do ui.focus(first)
	}
	// Escape that closed a popover in the dialog leaves the dialog open.
	if ui.is_key_pressed(.Escape) && _window.escape_frame != ui._state.frame_index {
		_window.dialog.is_open^ = false
		ui.request_frame()
	}
	ui.pop_parent()
}
