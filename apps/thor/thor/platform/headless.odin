package platform

import "core:strings"
import NS "core:sys/darwin/Foundation"
import "core:time"
import MTL "vendor:darwin/Metal"

HEADLESS_FRAME_SECONDS :: 1.0 / 60

HEADLESS_START :: time.Tick{1_000_000_000_000}

// macOS's default accent, which a window with no screen takes in place of the person's.
HEADLESS_ACCENT :: [4]f32{0x0a / 255.0, 0x84 / 255.0, 1, 1}

_headless: struct {
	// stop_headless keeps it, because the renderer starts only once, with this device.
	device:    ^MTL.Device,
	is_on:     bool,
	now:       time.Tick,
	is_dark:   bool,
	scale:     f32,
	clipboard: string,
}

// The time thor's animations read. With no window, a clock that moves only as frames run.
now :: proc "contextless" () -> time.Tick {
	return _headless.now if _headless.is_on else time.tick_now()
}

is_headless :: proc "contextless" () -> bool {
	return _headless.is_on
}

// For headless and THOR_CAPTURE: new windows never show, and step_headless runs frames in memory.
// is_dark replaces the system's appearance. The person's clipboard and settings stay untouched.
start_headless :: proc(pixels_per_point: f32, is_dark: bool) {
	if _headless.device == nil do _headless.device = MTL.CreateSystemDefaultDevice()
	_headless.is_on = true
	// The same start every run, so what reads the clock, such as a spinner, draws the same.
	_headless.now = HEADLESS_START
	_headless.is_dark = is_dark
	_headless.scale = pixels_per_point
	_state.odin_context = context
}

// Frees every window and stops running with no screen.
stop_headless :: proc() {
	for window in _state.windows {
		window.is_closed = true
		window.is_forgotten = true
	}
	_release_closed()
	_state.current = nil
	delete(_headless.clipboard)
	_headless = {
		device = _headless.device,
	}
}

// Moves the clock HEADLESS_FRAME_SECONDS and runs every open window. input gets the events.
step_headless :: proc(input: ^Native_Window, events: ..Event) -> bool {
	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->drain()

	frame := HEADLESS_FRAME_SECONDS * f64(time.Second)
	_headless.now = time.tick_add(_headless.now, time.Duration(frame))
	if input != nil && !input.is_closed {
		for event in events do append(&input.events, _to_kept_event(event, input))
	}

	is_wanted := false
	// A frame may open a window, which runs from the next step.
	count := len(_state.windows)
	for index in 0 ..< count {
		window := _state.windows[index]
		if window.is_closed do continue

		_state.current = window
		window.is_frame_requested = false
		if window.is_look_changed do append(&window.events, Appearance_Change{})
		window.is_look_changed = false
		is_wanted = window.on_frame() || window.is_frame_requested || is_wanted
		_clear_events(window)
	}
	_state.current = nil
	_release_closed()

	return is_wanted
}

// True while keys arrive as text and commands for a text field. nil means the current window.
is_text_input :: proc(window: ^Native_Window = nil) -> bool {
	shown := window if window != nil else current_window()

	return shown != nil && shown.is_text_input
}

// Copies the event's text into the window's event arena, the same as for AppKit events.
_to_kept_event :: proc(event: Event, window: ^Native_Window) -> Event {
	allocator := _event_allocator(window)
	#partial switch value in event {
	case Key_Press:
		kept := value
		kept.characters = strings.clone(value.characters, allocator)
		return kept
	case Text_Insert:
		return Text_Insert{strings.clone(value.text, allocator)}
	case Text_Command:
		return Text_Command{strings.clone(value.name, allocator)}
	}

	return event
}
