package app

import "../dev"
import "../font"
import "../icon"
import "../images"
import "../kit"
import "../platform"
import "../render"
import "../ui"
import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"

Window_Kind :: platform.Window_Kind

Config :: struct {
	title:           string,
	size:            [2]f32,
	min_size:        [2]f32,
	// Shows the desktop through the window, blurred. kit.colors.base_100 needs alpha below 1.
	is_blurred:      bool,
	kind:            Window_Kind,
	// For a window per document. Its frame reads it from current_window().data.
	data:            rawptr,
}

FRAME_TIME_COLOR :: [4]f32{0.5, 0.5, 0.5, 1}

// The id of the window app.run and app.open_main_window open.
MAIN_WINDOW :: "main"

Window :: struct {
	id:             string,
	kind:           Window_Kind,
	data:           rawptr,
	// In points at the zoom, as ui.window_size gives them.
	size_points:    [2]f32,
	_platform:      ^platform.Native_Window,
	_target:        ^render.Surface,
	_ui:            ui.Context,
	_kit:           kit._Window_State,
	_frame:         proc(),
	_on_frame:      platform.Frame_Proc,
	_zoom:          _Zoom,
	// The window's own temp allocator, so another window's frame never frees its boxes.
	_temp:          runtime.Arena,
	_is_blurred:    bool,
	_background:    [4]f32,
	_is_inspecting: bool,
	_is_outlining:  bool,
	// The window's size in points at the zoom, at the last build.
	_layout_size:   [2]f32,
	// True in the first of two builds, which lays out the boxes and draws nothing.
	_is_unseen:     bool,
	_last_frame:    time.Tick,
	_frame_start:   time.Tick,
}

// Belongs to the current window, the window whose frame the app builds now.
native_window: ^platform.Native_Window

zoom: f32 = 1

// Frames drawn, in every window.
frame_count: int

_windows: [dynamic]^Window
_current: ^Window
_has_menu: bool

// Runs until the app quits. Without fetch_image, kit.image and images.watch read files only.
// to_image_family names the family of a URL, so a larger loaded size shows while the URL loads.
run :: proc(
	config: Config,
	frame: proc(),
	fetch_image: images.Fetch_Proc = nil,
	to_image_family: images.Family_Proc = nil,
) {
	dev.start()
	if dev.capture_path != "" {
		_capture(config, frame, fetch_image, to_image_family)
		return
	}

	_open(MAIN_WINDOW, config, frame, _run_frame, dev.forced_zoom, fetch_image, to_image_family)
	platform.run()
}

// For an app whose frame proc calls begin_frame and end_frame, and that runs platform.run itself.
// fetch_image and to_image_family work as in run.
open_main_window :: proc(
	config: Config,
	frame: platform.Frame_Proc,
	fetch_image: images.Fetch_Proc = nil,
	to_image_family: images.Family_Proc = nil,
) {
	dev.start()
	_open(MAIN_WINDOW, config, nil, frame, dev.forced_zoom, fetch_image, to_image_family)
}

// Brings an open window to the front. Call it on an event, such as a click, not in every frame.
open_window :: proc(id: string, config: Config, frame: proc()) {
	if shown := _find_window(id); shown != nil {
		platform.bring_to_front(shown._platform)
		return
	}

	kept := _current
	_open(id, config, frame, _run_frame, 0)
	_use(kept)
}

// Closes the window, as its close button does. The app quits when its last Normal window closes.
close_window :: proc(id: string) {
	if shown := _find_window(id); shown != nil do platform.close_window(shown._platform)
}

is_window_open :: proc(id: string) -> bool {
	return _find_window(id) != nil
}

// The window whose frame the app builds now.
current_window :: proc() -> ^Window {
	return _current
}

_find_window :: proc(id: string) -> ^Window {
	for shown in _windows {
		if shown.id == id && !shown._platform.is_closed do return shown
	}

	return nil
}

_open :: proc(
	id: string,
	config: Config,
	frame: proc(),
	on_frame: platform.Frame_Proc,
	zoom_wanted: f32,
	// App-wide. Only the first window uses them.
	fetch_image: images.Fetch_Proc = nil,
	to_image_family: images.Family_Proc = nil,
) -> ^Window {
	opened := new(Window)
	opened^ = {
		id          = strings.clone(id),
		kind        = config.kind,
		data        = config.data,
		_frame      = frame,
		_on_frame   = on_frame,
		_is_blurred = config.is_blurred,
	}

	size := config.size
	if id == MAIN_WINDOW && dev.window_size_points != {} do size = dev.window_size_points
	is_behind := dev.is_background && !dev.is_bench
	// A measured run ignores the saved place, as it ignores the saved zoom.
	is_measured := dev.is_bench || dev.is_startup_mark
	frame_name := "" if is_measured else fmt.tprintf("thor window %s", id)
	opened._platform = platform.open_window(
		config.title,
		size,
		config.min_size,
		_run_settled,
		is_behind,
		config.is_blurred,
		frame_name,
		config.kind,
	)
	append(&_windows, opened)

	is_first := len(_windows) == 1
	_use(opened)
	// The pointer starts outside the window.
	ui._reset()
	if is_first {
		if dev.forced_appearance != .System do kit.appearance = dev.forced_appearance
		_theme = {}
		_apply_theme(nil)
		render.start(native_window.device)
		font.start()
		icon.start()
		images.start(fetch_image, to_image_family)
	}
	opened._target = render.make_surface(native_window.layer)
	render.use_surface(opened._target)
	_start_zoom(config.min_size, zoom_wanted)
	opened._last_frame = platform.now()

	if !_has_menu && !platform.is_headless() {
		platform.install_menu(config.title, len(zoom_steps) > 0)
		_has_menu = true
	}

	return opened
}

// Makes the window the one ui, kit, render and the globals here act on.
_use :: proc(shown: ^Window) {
	if _current != nil {
		_current._is_inspecting = dev.is_inspecting
		_current._is_outlining = dev.is_outlining
	}
	_current = shown
	if shown == nil do return

	native_window = shown._platform
	zoom = shown._zoom.shown
	platform.use_window(shown._platform)
	render.use_surface(shown._target)
	ui._use_context(&shown._ui)
	kit._use_window_state(&shown._kit)
	dev.is_inspecting = shown._is_inspecting
	dev.is_outlining = shown._is_outlining
}

_find_by_platform :: proc(target: ^platform.Native_Window) -> ^Window {
	for shown in _windows {
		if shown._platform == target do return shown
	}

	return nil
}

// Skips the current window, which runs its frame now.
_remove_closed :: proc() {
	for index := len(_windows) - 1; index >= 0; index -= 1 {
		closed := _windows[index]
		if !closed._platform.is_closed || closed == _current do continue

		ordered_remove(&_windows, index)
		_destroy(closed)
	}
}

_destroy :: proc(closed: ^Window) {
	ui._destroy_context(&closed._ui)
	kit._destroy_window_state(&closed._kit)
	if closed._target != nil do render.destroy_surface(closed._target)
	runtime.arena_destroy(&closed._temp)
	platform.forget_window(closed._platform)
	delete(closed.id)
	free(closed)
}

_run_frame :: proc() -> bool {
	begin_frame()
	_current._frame()
	dev.build_frame_time(FRAME_TIME_COLOR)

	return end_frame()
}

// bundle.sh copies resources/ into the .app. Without a .app, the binary reads resources/ beside it.
resource_path :: proc(name: string) -> string {
	return strings.concatenate({platform.resource_folder(), "/", name}, context.temp_allocator)
}

HEADLESS_SETTLE_FRAMES :: 120
HEADLESS_LOAD_WAIT :: 5 * time.Second

// For the headless package and THOR_CAPTURE. platform.step_headless runs each frame, in memory.
// is_dark replaces the system's appearance. Later windows have no screen either.
_open_headless :: proc(
	config: Config,
	frame: proc(),
	scale: f32 = 2,
	zoom: f32 = 1,
	is_dark := true,
	fetch_image: images.Fetch_Proc = nil,
	to_image_family: images.Family_Proc = nil,
) {
	platform.start_headless(scale, is_dark)
	_open(MAIN_WINDOW, config, frame, _run_frame, zoom, fetch_image, to_image_family)
}

_close_headless :: proc() {
	_use(nil)
	for shown in _windows do _destroy(shown)
	clear(&_windows)
	platform.stop_headless()
	native_window = nil
	zoom = 1
	render.use_surface(nil)
}

// Runs frames until no window asks for one and no image is loading, or until it reaches a limit.
_settle_headless :: proc() {
	load_deadline := time.tick_add(time.tick_now(), HEADLESS_LOAD_WAIT)
	for frame := 0; frame < HEADLESS_SETTLE_FRAMES; {
		is_wanted := platform.step_headless(nil)
		if images.is_loading() && time.tick_diff(time.tick_now(), load_deadline) > 0 {
			time.sleep(time.Millisecond)
			continue
		}
		if !is_wanted do return
		frame += 1
	}
}

// Between headless frames, makes read_pixels and the globals here read the window with this id.
_use_headless_window :: proc(id: string) -> bool {
	shown := _find_window(id)
	if shown == nil do return false

	_use(shown)

	return true
}

// THOR_CAPTURE: writes a PNG after the app settles and its clock moves THOR_CAPTURE_SECONDS more.
_capture :: proc(config: Config, frame: proc(), fetch_image: images.Fetch_Proc, to_image_family: images.Family_Proc) {
	shown := config
	if dev.window_size_points != {} do shown.size = dev.window_size_points
	at := dev.forced_zoom if dev.forced_zoom > 0 else 1
	_open_headless(shown, frame, zoom = at, fetch_image = fetch_image, to_image_family = to_image_family)
	defer _close_headless()

	_settle_headless()
	for _ in 0 ..< int(dev.capture_seconds / platform.HEADLESS_FRAME_SECONDS) do platform.step_headless(nil)

	_use_headless_window(MAIN_WINDOW)
	pixels, size := render.read_pixels(context.temp_allocator)
	if !images.write_png(dev.capture_path, pixels, size) {
		fmt.eprintfln("app: can't write the capture to %s", dev.capture_path)
		return
	}
	fmt.printfln("captured %dx%d to %s", size.x, size.y, dev.capture_path)
}

// When the window size or zoom changes, it builds the frame twice and draws only the second build.
// So a box size from the last frame, read in a build, always matches this frame on the screen.
_run_settled :: proc() -> bool {
	shown := _find_by_platform(platform.current_window())
	if shown == nil do return false

	_use(shown)
	_remove_closed()
	context.temp_allocator = runtime.arena_allocator(&shown._temp)
	_apply_zoom_events(platform.list_events())

	layout_size := native_window.size_points / zoom
	if layout_size == shown._layout_size do return shown._on_frame()

	shown._layout_size = layout_size
	shown._is_unseen = true
	shown._on_frame()
	shown._is_unseen = false
	// The first build used the events. The app can also read them, so the second build gets none.
	clear(&native_window.events)

	return shown._on_frame()
}

begin_frame :: proc() -> (frame_seconds: f32) {
	shown := _current
	free_all(context.temp_allocator)
	if shown.id == MAIN_WINDOW do dev.apply_test_typing()

	start := platform.now()
	frame_seconds = f32(time.duration_seconds(time.tick_diff(shown._last_frame, start)))
	shown._last_frame = start
	shown._frame_start = start
	if !shown._is_unseen do dev.begin_frame(start)

	render.begin_frame(native_window.size_points * native_window.pixels_per_point)
	font.begin_frame()
	images.begin_frame()
	icon.begin_frame()
	events := platform.list_events()
	_apply_theme(events)
	if shown._background != kit.colors.base_100 {
		platform.set_background(kit.colors.base_100)
		shown._background = kit.colors.base_100
	}
	ui._begin_frame(native_window.size_points, native_window.pixels_per_point, zoom, frame_seconds, events)
	shown.size_points = ui.window_size()
	ui._default_text_color = kit.colors.base_content
	ui._is_glass_shown = !platform.is_headless() && !ui.preferences().is_reducing_transparency
	ui._glass_fallback = kit.colors.base_100
	// A window with a screen is in Display P3. Snapshots stay in sRGB.
	render.set_color_mode(kit.is_blending_linear, !platform.is_headless())
	ui._min_contrast = max(kit.min_contrast, 4.5) if ui.preferences().is_increasing_contrast else kit.min_contrast
	ui._focus_ring_color = kit.to_faded(kit.colors.primary, kit._FOCUS_BORDER_ALPHA)
	kit._apply_text_events(events)
	dev.apply_inspector_keys(events)

	// The capture reads the boxes only, so an opaque window paints its colour in the root box too.
	if !shown._is_blurred do ui.current_parent().style.background = kit.colors.base_100

	return frame_seconds
}

// Returns true while the window needs another frame.
end_frame :: proc() -> bool {
	shown := _current
	dev.build_inspector()
	ui._end_frame()
	dev.read_inspector_tree()
	if shown._is_unseen do return true

	if native_window.accessibility.is_wanted do _update_accessibility()
	platform.set_glass(native_window, ui._state.glass_areas[:])
	kit._finish_text_fields()
	// AppKit puts the arrow back at the window's edges, so set the shape again each frame.
	if ui.mouse_position().x >= 0 do platform.set_cursor(ui._cursor())
	frame_count += 1

	is_bench_done := dev.finish_frame(shown._frame_start)

	render.end_frame(native_window.drawable)
	dev.mark_startup(!ui._is_frame_requested())
	if is_bench_done do dev.finish_bench()

	return(
		dev.is_bench ||
		ui._is_frame_wanted() ||
		font.is_redraw_needed() ||
		icon.is_redraw_needed() ||
		images.is_animating() \
	)
}
