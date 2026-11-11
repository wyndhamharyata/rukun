package platform

import "base:intrinsics"
import "base:runtime"
import "core:strings"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"

objc_send :: intrinsics.objc_send

// Odin 2026-10 builds objc_send calls only in a program that looks up a class by name.
@(init)
_find_class_for_objc_send :: proc "contextless" () {
	_ = intrinsics.objc_find_class("NSObject")
}

Frame_Proc :: proc() -> bool

Window_Kind :: enum {
	Normal,
	// Floats over every app's windows and leaves the keyboard with the app in front.
	Panel,
}

Native_Window :: struct {
	ns_window:          ^NS.Window,
	blur_view:          ^NS.View,
	drawable:           ^CA.MetalDrawable,
	device:             ^MTL.Device,
	layer:              ^CA.MetalLayer,
	size_points:        [2]f32,
	pixels_per_point:   f32,
	kind:               Window_Kind,
	// Its close button, ⌘W or close_window sets it. A closed window runs no more frames.
	is_closed:          bool,
	view:               ^NS.View,
	input_view:         ^NS.View,
	display_link:       ^Display_Link,
	// The window's delegate, and its display link's and timers' target.
	target:             ^_Target,
	timer:              ^NS.Timer,
	// macOS stops the display link of a covered window, so a timer runs its frames.
	frame_timer:        ^NS.Timer,
	is_link_running:    bool,
	is_frame_requested: bool,
	is_screen_changed:  bool,
	is_look_changed:    bool,
	is_frame_restored:  bool,
	// _release freed its AppKit objects. The struct stays until forget_window.
	is_released:        bool,
	is_forgotten:       bool,
	on_frame:           Frame_Proc,
	events:             [dynamic]Event,
	event_arena:        [2]runtime.Arena,
	event_arena_index:  int,
	is_text_input:      bool,
	marked_byte_count:  int,
	caret_rect:         [4]f32,
	accessibility:      _Accessibility,
	glass:              _Window_Glass,
}

_state: struct {
	app:           ^NS.Application,
	// The menus' and the appearance notifications' target.
	target:        ^_Target,
	windows:       [dynamic]^Native_Window,
	// The window whose frame runs, which the calls without a window act on.
	current:       ^Native_Window,
	is_background: bool,
	is_quitting:   bool,
	odin_context:  runtime.Context,
}

@(objc_class = "CAMetalDisplayLink")
Display_Link :: struct {
	using _: NS.Object,
}

@(objc_class = "ThorTarget", objc_superclass = NS.Object, objc_implement)
_Target :: struct {
	using _: NS.Object,
}

_find_by_target :: proc "contextless" (target: ^_Target) -> ^Native_Window {
	for window in _state.windows {
		if window.target == target && !window.is_released do return window
	}

	return nil
}

@(objc_type = _Target, objc_implement, objc_name = "metalDisplayLink", objc_selector = "metalDisplayLink:needsUpdate:")
Target_metalDisplayLink :: proc "c" (self: ^_Target, link: NS.id, update: ^NS.Object) {
	context = _state.odin_context
	window := _find_by_target(self)
	if window == nil || window.is_closed do return

	window.drawable = objc_send(^CA.MetalDrawable, update, "drawable")
	_run_frame(window)
	window.drawable = nil
}

@(objc_type = _Target, objc_implement, objc_name = "frameTimerFired", objc_selector = "frameTimerFired:")
Target_frameTimerFired :: proc "c" (self: ^_Target, timer: NS.id) {
	context = _state.odin_context
	if window := _find_by_target(self); window != nil && !window.is_closed do _run_frame(window)
}

@(objc_type = _Target, objc_implement, objc_name = "timerFired", objc_selector = "timerFired:")
Target_timerFired :: proc "c" (self: ^_Target, timer: NS.id) {
	window := _find_by_target(self)
	if window == nil do return

	window.timer = nil
	_request_frame_of(window)
}

@(objc_type = _Target, objc_implement, objc_name = "windowDidResize", objc_selector = "windowDidResize:")
Target_windowDidResize :: proc "c" (self: ^_Target, notification: NS.id) {
	if window := _find_by_target(self); window != nil do _request_frame_of(window)
}

@(objc_type = _Target, objc_implement, objc_name = "windowDidChangeScreen", objc_selector = "windowDidChangeScreen:")
Target_windowDidChangeScreen :: proc "c" (self: ^_Target, notification: NS.id) {
	window := _find_by_target(self)
	if window == nil do return

	window.is_screen_changed = true
	_request_frame_of(window)
}

@(objc_type = _Target, objc_implement, objc_name = "windowDidChangeOcclusionState", objc_selector = "windowDidChangeOcclusionState:")
Target_windowDidChangeOcclusionState :: proc "c" (self: ^_Target, notification: NS.id) {
	window := _find_by_target(self)
	if window == nil || window.is_closed do return

	_stop_frames(window)
	_request_frame_of(window)
}

// The menu bar's Edit and View items send their shortcut as a key press to the window in front.
@(objc_type = _Target, objc_implement, objc_name = "menuKey", objc_selector = "menuKey:")
Target_menuKey :: proc "c" (self: ^_Target, item: ^NS.MenuItem) {
	context = _state.odin_context
	window := _find_key_window()
	if window == nil do return

	key := objc_send(^NS.String, item, "keyEquivalent")->odinString()
	key_code := Key(objc_send(NS.Integer, item, "tag"))
	append(&window.events, Key_Press{key_code, strings.clone(key, _event_allocator(window)), {.Command}})
	_request_frame_of(window)
}

@(objc_type = _Target, objc_implement, objc_name = "menuQuit", objc_selector = "menuQuit:")
Target_menuQuit :: proc "c" (self: ^_Target, item: NS.id) {
	context = _state.odin_context
	quit()
}

// Element frames are in screen points, so a moved window needs new ones.
@(objc_type = _Target, objc_implement, objc_name = "windowDidMove", objc_selector = "windowDidMove:")
Target_windowDidMove :: proc "c" (self: ^_Target, notification: NS.id) {
	window := _find_by_target(self)
	if window != nil && window.accessibility.is_wanted do _request_frame_of(window)
}

@(objc_type = _Target, objc_implement, objc_name = "appearanceChanged", objc_selector = "appearanceChanged:")
Target_appearanceChanged :: proc "c" (self: ^_Target, notification: NS.id) {
	for window in _state.windows do window.is_look_changed = true
	_request_every_frame()
}

@(objc_type = _Target, objc_implement, objc_name = "windowShouldClose", objc_selector = "windowShouldClose:")
Target_windowShouldClose :: proc "c" (self: ^_Target, sender: NS.id) -> NS.BOOL {
	context = _state.odin_context
	if window := _find_by_target(self); window != nil do _mark_closed(window)

	return true
}

foreign import objc_runtime "system:Foundation.framework"

@(default_calling_convention = "c")
foreign objc_runtime {
	objc_msgSendSuper :: proc(super: ^_Objc_Super, selector: NS.SEL) ---
	sel_getName :: proc(selector: NS.SEL) -> cstring ---
	objc_getProtocol :: proc(name: cstring) -> rawptr ---
	class_addProtocol :: proc(class: rawptr, protocol: rawptr) -> NS.BOOL ---
}

OCCLUSION_VISIBLE :: 1 << 1

// The window whose frame runs, or the first open one between frames.
current_window :: proc "contextless" () -> ^Native_Window {
	if _state.current != nil do return _state.current

	for window in _state.windows {
		if !window.is_closed do return window
	}

	return nil
}

// The calls without a window act on this window until its frame ends or until the next call.
use_window :: proc "contextless" (window: ^Native_Window) {
	_state.current = window
}

// Brings an open window in front: a panel without bringing the app in front.
bring_to_front :: proc(window: ^Native_Window) {
	if _headless.is_on || window.is_closed do return

	if window.kind == .Panel {
		objc_send(nil, window.ns_window, "orderFrontRegardless")
		return
	}
	window.ns_window->makeKeyAndOrderFront(nil)
	_state.app->activate()
}

// True while the window whose frame runs has the keyboard. Always with no screen.
is_key_window :: proc() -> bool {
	window := current_window()
	if _headless.is_on || window == nil do return true

	return !window.is_closed && bool(window.ns_window->keyWindow())
}

// Asks for a frame of the window whose frame runs.
request_frame :: proc "contextless" () {
	if window := current_window(); window != nil do _request_frame_of(window)
}

_request_every_frame :: proc "contextless" () {
	for window in _state.windows do _request_frame_of(window)
}

_request_frame_of :: proc "contextless" (window: ^Native_Window) {
	window.is_frame_requested = true
	if window.is_link_running || window.is_closed || _headless.is_on do return

	window.is_link_running = true

	is_visible := objc_send(NS.UInteger, window.ns_window, "occlusionState") & OCCLUSION_VISIBLE != 0

	if !_state.is_background && is_visible {
		objc_send(nil, window.display_link, "setPaused:", NS.BOOL(false))
		return
	}

	FRAME_SECONDS :: 1.0 / 60
	COVERED_FRAME_SECONDS :: 1.0

	window.frame_timer = _start_timer(
		window.target,
		FRAME_SECONDS if _state.is_background else COVERED_FRAME_SECONDS,
		intrinsics.objc_find_selector("frameTimerFired:"),
		true,
	)
}

_start_timer :: proc "contextless" (
	target: ^_Target,
	seconds: f64,
	selector: NS.SEL,
	is_repeating: bool,
) -> ^NS.Timer {
	timer := objc_send(
		^NS.Timer,
		NS.Timer,
		"timerWithTimeInterval:target:selector:userInfo:repeats:",
		NS.TimeInterval(seconds),
		target,
		selector,
		rawptr(nil),
		NS.BOOL(is_repeating),
	)

	main_run_loop := objc_send(^NS.RunLoop, NS.RunLoop, "mainRunLoop")
	objc_send(nil, main_run_loop, "addTimer:forMode:", timer, NS.RunLoopCommonModes)

	return timer
}

_run_frame :: proc(window: ^Native_Window) {
	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->drain()

	_state.current = window
	defer _state.current = nil

	is_resized := _apply_window_size(window)
	if window.is_screen_changed do append(&window.events, Screen_Change{})
	if window.is_look_changed do append(&window.events, Appearance_Change{})
	window.is_screen_changed = false
	window.is_look_changed = false
	had_input := len(window.events) > 0

	window.is_frame_requested = false
	is_frame_wanted := window.on_frame() || window.is_frame_requested || is_resized

	_clear_events(window)
	// The other windows read the same app state, and the input can change it.
	if had_input {
		for other in _state.windows {
			if other != window do _request_frame_of(other)
		}
	}

	if is_frame_wanted || !window.is_link_running do return

	_stop_frames(window)
}

_clear_events :: proc(window: ^Native_Window) {
	clear(&window.events)
	window.event_arena_index = 1 - window.event_arena_index
	runtime.arena_free_all(&window.event_arena[window.event_arena_index])
}

_stop_frames :: proc "contextless" (window: ^Native_Window) {
	window.is_link_running = false

	if window.frame_timer != nil {
		objc_send(nil, window.frame_timer, "invalidate")
		window.frame_timer = nil
	} else if window.display_link != nil {
		objc_send(nil, window.display_link, "setPaused:", NS.BOOL(true))
	}
}

// Reads events until quit runs or the last Normal window closes.
run :: proc() {
	for !_state.is_quitting && _has_normal_window() {
		pool := NS.AutoreleasePool.alloc()->init()
		event := _state.app->nextEventMatchingMask(
			NS.EventMaskAny,
			NS.Date.distantFuture(),
			NS.DefaultRunLoopMode,
			true,
		)

		if event != nil && !_apply_event(event) do _state.app->sendEvent(event)
		_release_closed()

		pool->drain()
	}
}

_has_normal_window :: proc() -> bool {
	for window in _state.windows {
		if window.kind == .Normal && !window.is_closed do return true
	}

	return false
}

// Asks for a frame of the window whose frame runs, seconds from now.
request_frame_after :: proc(seconds: f64) {
	// With no window, the test moves the clock and runs the frames.
	if _headless.is_on do return

	window := current_window()
	if window == nil || window.is_closed do return

	delay_seconds := max(0, seconds)
	fire_date := objc_send(
		^NS.Date,
		NS.Date,
		"dateWithTimeIntervalSinceNow:",
		NS.TimeInterval(delay_seconds),
	)

	if window.timer != nil {
		pending := objc_send(^NS.Date, window.timer, "fireDate")

		if objc_send(NS.TimeInterval, pending, "timeIntervalSinceDate:", fire_date) <= 0 do return

		objc_send(nil, window.timer, "invalidate")
	}

	window.timer = _start_timer(window.target, delay_seconds, intrinsics.objc_find_selector("timerFired:"), false)
}

// Asks every window for a frame. Worker threads call it.
wake :: proc "contextless" () {
	if _headless.is_on || _state.app == nil do return

	// Worker threads have no autorelease pool for the event.
	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->drain()

	event := NS.Event.otherEventWithType(.ApplicationDefined, {0, 0}, {}, 0, 0, nil, 0, 0, 0)
	_state.app->postEvent(event, true)
}

quit :: proc() {
	_state.is_quitting = true
	wake()
}

// Works as the close button does: frames stop, and the struct stays until forget_window.
close_window :: proc(window: ^Native_Window) {
	if window.is_closed do return

	_mark_closed(window)
	if window.ns_window != nil do objc_send(nil, window.ns_window, "close")
}

// The owner no longer holds the window, so _release_closed can free it.
forget_window :: proc(window: ^Native_Window) {
	window.is_forgotten = true
}

_mark_closed :: proc(window: ^Native_Window) {
	window.is_closed = true
	if !_headless.is_on {
		_stop_frames(window)
		if window.timer != nil do objc_send(nil, window.timer, "invalidate")
		window.timer = nil
	}
	// What the other windows show may depend on this one being open.
	_request_every_frame()
}

// Call it between events, never inside a window's own callbacks.
_release_closed :: proc() {
	for index := len(_state.windows) - 1; index >= 0; index -= 1 {
		window := _state.windows[index]
		if window.is_closed && !window.is_released do _release(window)
		if !window.is_forgotten do continue

		ordered_remove(&_state.windows, index)
		delete(window.events)
		for &arena in window.event_arena do runtime.arena_destroy(&arena)
		free(window)
	}
}

_release :: proc(window: ^Native_Window) {
	window.is_released = true
	if _headless.is_on do return

	objc_send(nil, window.display_link, "invalidate")
	_release_accessibility(window)
	_release_glass(window)
	window.ns_window->setDelegate(nil)
	window.ns_window->release()
	window.target->release()
	window.display_link = nil
	window.ns_window = nil
}

// The window of ours that has the keyboard, else the current one.
_find_key_window :: proc "contextless" () -> ^Native_Window {
	if !_headless.is_on && _state.app != nil {
		key := _state.app->keyWindow()
		for window in _state.windows {
			if window.ns_window == key && !window.is_closed do return window
		}
	}

	return current_window()
}

_find_by_ns_window :: proc "contextless" (ns_window: ^NS.Window) -> ^Native_Window {
	for window in _state.windows {
		if window.ns_window == ns_window && !window.is_closed do return window
	}

	return nil
}
