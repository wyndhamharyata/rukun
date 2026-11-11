package app

import "../dev"
import "../platform"
import "../ui"
import "core:fmt"

// The zooms ⌘+ and ⌘− step through. nil leaves the keys to the app.
zoom_steps := []f32{0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3}

// The setting name for the main window's zoom. Another window adds its id after it.
_ZOOM_SETTING :: "thor zoom"

_Zoom :: struct {
	// The zoom the person asked for. A screen too small for it shows a smaller one.
	wanted:   f32,
	shown:    f32,
	min_size: [2]f32,
	is_saved: bool,
}

// Zooms the current window and saves the zoom, unless the min size would not fit the screen.
set_zoom :: proc(wanted: f32) {
	state := &_current._zoom
	screen := platform.read_screen_size_points()
	if wanted > zoom && _to_fitting_zoom(wanted, zoom_steps, state.min_size, screen) < wanted do return

	state.wanted = wanted
	if state.is_saved do platform.save_setting(_to_zoom_setting(_current.id), f64(wanted))
	_fit_zoom()
	ui.request_frame()
}

_to_zoom_setting :: proc(id: string) -> string {
	return _ZOOM_SETTING if id == MAIN_WINDOW else fmt.tprintf("%s %s", _ZOOM_SETTING, id)
}

// Uses wanted, or the zoom the person saved when wanted is 0.
_start_zoom :: proc(min_size: [2]f32, wanted: f32) {
	state := &_current._zoom
	state.min_size = min_size
	state.wanted = 1
	// A measured, captured or headless run neither reads nor saves the person's zoom.
	state.is_saved = wanted == 0 && !dev.is_bench && !dev.is_startup_mark && !platform.is_headless()

	if wanted > 0 {
		state.wanted = wanted
	} else if saved, ok := platform.read_setting(_to_zoom_setting(_current.id)); ok && saved > 0 && state.is_saved {
		state.wanted = f32(saved)
	}
	_fit_zoom()
}

_apply_zoom_events :: proc(events: []platform.Event) {
	for event in events {
		#partial switch input in event {
		case platform.Screen_Change:
			_fit_zoom()
		case platform.Key_Press:
			if len(zoom_steps) == 0 || input.modifiers - {.Shift} != {.Command} do continue

			switch input.characters {
			case "=", "+":
				set_zoom(_to_zoom_step(zoom, zoom_steps, 1))
			case "-":
				set_zoom(_to_zoom_step(zoom, zoom_steps, -1))
			case "0":
				set_zoom(1)
			}
		}
	}
}

_fit_zoom :: proc() {
	state := &_current._zoom
	zoom = _to_fitting_zoom(state.wanted, zoom_steps, state.min_size, platform.read_screen_size_points())
	state.shown = zoom
	platform.set_min_size(state.min_size * zoom)
}

// wanted, or the largest step below it at which the smallest window fits the screen.
_to_fitting_zoom :: proc(wanted: f32, steps: []f32, min_size, screen: [2]f32) -> f32 {
	shown := wanted
	for index := len(steps) - 1; index >= 0; index -= 1 {
		size := min_size * shown
		if size.x <= screen.x && size.y <= screen.y do break

		shown = min(shown, steps[index])
	}

	return shown
}

// Returns the step that is offset steps from the step nearest zoom. It stops at the first and last.
_to_zoom_step :: proc(zoom: f32, steps: []f32, offset: int) -> f32 {
	nearest := 0
	for step, index in steps {
		if abs(step - zoom) < abs(steps[nearest] - zoom) do nearest = index
	}

	return steps[clamp(nearest + offset, 0, len(steps) - 1)]
}
