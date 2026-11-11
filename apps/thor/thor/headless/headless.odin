package headless

import "../app"
import "base:runtime"
import "../images"
import "../kit"
import "../platform"
import "../render"
import "../ui"
import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

DEFAULT_SIZE :: [2]f32{1000, 700}

// A pixel differs when a channel differs from the expected channel by more than this, out of 255.
PIXEL_TOLERANCE :: 8

Options :: struct {
	// In points. DEFAULT_SIZE when zero.
	size:       [2]f32,
	// Pixels per point. 2 when zero.
	scale:      f32,
	// 1 when zero.
	zoom:       f32,
	// .System keeps the app's kit.appearance. If that is .System too, the window is dark.
	appearance: platform.Appearance,
}

// An input acts on an element's id or label, the element, or a point in the main window.
Target :: union {
	string,
	^ui.Box,
	[2]f32,
}

_session: struct {
	kept_appearance: platform.Appearance,
	// The window that has the keyboard: the last window the test clicked, else the main window.
	key_window:      ^app.Window,
}

// Draws every app window into memory. It never uses the person's keyboard, mouse or clipboard.
// Call close when done. Only one app can run headless at a time.
open :: proc(frame: proc(), options: Options = {}) {
	_session = {
		kept_appearance = kit.appearance,
	}
	if options.appearance != .System do kit.appearance = options.appearance

	size := options.size if options.size != {} else DEFAULT_SIZE
	scale := options.scale if options.scale > 0 else 2
	zoom := options.zoom if options.zoom > 0 else 1
	app._open_headless({size = size}, frame, scale, zoom)
	app._settle_headless()
}

close :: proc() {
	app._close_headless()
	kit.appearance = _session.kept_appearance
}

// Runs frames until no window asks for one and no image loads. Each input and read calls it first.
settle :: proc() {
	app._settle_headless()
}

// Moves the clock by seconds and runs a frame each 1/60 s, so a toast fades or an image fades in.
wait :: proc(seconds: f32) {
	for _ in 0 ..< int(seconds / platform.HEADLESS_FRAME_SECONDS + 0.5) do platform.step_headless(nil)
}

click :: proc(target: Target, count := 1, loc := #caller_location) {
	_press(target, .Left, count, loc)
}

right_click :: proc(target: Target, loc := #caller_location) {
	_press(target, .Right, 1, loc)
}

// Presses on target, moves the pointer by points in steps, and releases the button.
drag :: proc(target: Target, by: [2]f32, loc := #caller_location) {
	settle()
	shown, position, ok := _to_input(target, loc)
	if !ok do return
	_session.key_window = shown
	window := shown._platform
	platform.step_headless(window, platform.Mouse_Move{position})
	settle()
	platform.step_headless(window, platform.Mouse_Press{position, .Left, {}, 1})
	DRAG_STEPS :: 4
	for step in 1 ..= DRAG_STEPS {
		platform.step_headless(window, platform.Mouse_Move{position + by * shown._zoom.shown * f32(step) / DRAG_STEPS})
	}
	platform.step_headless(window, platform.Mouse_Release{.Left})
	settle()
}

hover :: proc(target: Target, loc := #caller_location) {
	settle()
	shown, position, ok := _to_input(target, loc)
	if !ok do return
	platform.step_headless(shown._platform, platform.Mouse_Move{position})
	settle()
}

// Scrolls the box under target by points, as a trackpad does. A positive y shows what is below.
scroll :: proc(target: Target, points: [2]f32, loc := #caller_location) {
	settle()
	shown, position, ok := _to_input(target, loc)
	if !ok do return
	platform.step_headless(shown._platform, platform.Mouse_Move{position})
	delta := -points * shown._zoom.shown
	platform.step_headless(shown._platform, platform.Scroll{delta = delta, is_precise = true, is_start = true})
	settle()
}

// Presses a key in the key window. A text field gets text or a command, such as deleteBackward:.
press :: proc(key: platform.Key, modifiers: platform.Modifiers = {}) {
	settle()
	shown := _to_key_window()
	is_typing := platform.is_text_input(shown._platform) && .Command not_in modifiers && .Control not_in modifiers
	text := platform.to_key_text(key, .Shift in modifiers)
	if is_typing {
		platform.step_headless(shown._platform, _to_typing(key, modifiers, text))
	} else {
		platform.step_headless(shown._platform, platform.Key_Press{key, text, modifiers})
	}
	settle()
}

// Types text into the text field that has the keyboard.
type_text :: proc(text: string, loc := #caller_location) {
	settle()
	shown := _to_key_window()
	if !platform.is_text_input(shown._platform) {
		log.errorf("headless: no text field has the keyboard for %q. Click a text field first.", text, location = loc)
		return
	}
	platform.step_headless(shown._platform, platform.Text_Insert{text})
	settle()
}

// Closes the window, as its close button does.
close_window :: proc(id: string) {
	settle()
	app.close_window(id)
	settle()
}

// Returns nil and fails the test when no element or more than one element matches.
find :: proc(target: Target, loc := #caller_location) -> ^ui.Box {
	settle()
	switch value in target {
	case ^ui.Box:
		return value
	case [2]f32:
		log.errorf("headless: find takes an id, a label or an element, not a point.", location = loc)
	case string:
		found := find_all(value)
		switch len(found) {
		case 1:
			return found[0]
		case 0:
			list := strings.builder_make(context.temp_allocator)
			for shown in _open_windows() do strings.write_string(&list, tree(window = shown.id))
			log.errorf("headless: no element has the id or label %q. The windows have:\n%s", value, strings.to_string(list), location = loc)
		case:
			list := strings.builder_make(context.temp_allocator)
			for box in found do fmt.sbprintf(&list, "\n  %s", _to_line(box, true))
			log.errorf("headless: %d elements have the id or label %q. Pick one with find_all(%q)[index]:%s", len(found), value, value, strings.to_string(list), location = loc)
		}
	}

	return nil
}

// Matches the id first, then the label, in every open window, in build order. Uses temp_allocator.
find_all :: proc(id_or_label: string) -> []^ui.Box {
	settle()
	found := make([dynamic]^ui.Box, context.temp_allocator)
	for shown in _open_windows() {
		for root in _to_roots(shown) do _find_with_id(root, id_or_label, &found)
	}
	if len(found) > 0 do return found[:]

	for shown in _open_windows() {
		for root in _to_roots(shown) do _find_labelled(root, id_or_label, &found)
	}

	return found[:]
}

// One line per element, with its role, label, value and state, indented under its parent.
// Layout boxes and the insides of a control do not show.
tree :: proc(with_rects := false, window := app.MAIN_WINDOW) -> string {
	settle()
	builder := strings.builder_make(context.temp_allocator)
	shown := _find_window(window)
	if shown == nil {
		fmt.sbprintf(&builder, "no window %q is open\n", window)
		return strings.to_string(builder)
	}

	size := shown._platform.size_points
	look := "dark" if app._theme.is_dark else "light"
	name := "window" if window == app.MAIN_WINDOW else fmt.tprintf("window %q", window)
	fmt.sbprintf(&builder, "%s %.0f×%.0f %s %.0f%%\n", name, size.x, size.y, look, shown._zoom.shown * 100)
	found := make([dynamic]ui.Accessible, context.temp_allocator)
	roots := _to_roots(shown)
	ui._list_accessible(roots[:], &found)
	for item in found {
		for _ in 0 ..= item.depth do strings.write_string(&builder, "  ")
		strings.write_string(&builder, _to_line(item.box, with_rects))
		strings.write_byte(&builder, '\n')
	}

	return strings.to_string(builder)
}

// Writes a window as a PNG.
snapshot :: proc(path: string, window := app.MAIN_WINDOW) -> bool {
	settle()
	if !app._use_headless_window(window) do return false
	pixels, size := render.read_pixels(context.temp_allocator)

	return images.write_png(path, pixels, size)
}

// Compares tree(with_rects, window) with snapshots/<name>.txt beside the test file.
// It writes the file and passes when the file is missing or THOR_UPDATE_SNAPSHOTS=1.
expect_tree :: proc(
	t: ^testing.T,
	name: string,
	with_rects := false,
	window := app.MAIN_WINDOW,
	loc := #caller_location,
) -> bool {
	actual := tree(with_rects, window)
	path := _to_snapshot_path(name, ".txt", loc)
	if _is_writing(path) {
		_ = os.write_entire_file(path, actual)
		log.infof("headless: wrote %s", path)
		return true
	}

	expected, error := os.read_entire_file(path, context.temp_allocator)
	if error != nil {
		log.errorf("headless: can't read %s: %v", path, error, location = loc)
		return false
	}
	if string(expected) == actual do return true

	actual_path := _to_snapshot_path(name, ".actual.txt", loc)
	_ = os.write_entire_file(actual_path, actual)
	log.errorf("headless: the tree differs from %s. The new tree is in %s:\n%s", path, actual_path, _to_line_diff(string(expected), actual), location = loc)

	return false
}

// Compares a window with snapshots/<name>.png, with the same file rules as expect_tree.
// On a difference, it writes <name>.actual.png and <name>.diff.png, with the changed pixels red.
expect_snapshot :: proc(t: ^testing.T, name: string, window := app.MAIN_WINDOW, loc := #caller_location) -> bool {
	settle()
	if !app._use_headless_window(window) {
		log.errorf("headless: no window %q is open", window, location = loc)
		return false
	}
	actual, size := render.read_pixels(context.temp_allocator)
	path := _to_snapshot_path(name, ".png", loc)
	if _is_writing(path) {
		if !images.write_png(path, actual, size) {
			log.errorf("headless: can't write %s", path, location = loc)
			return false
		}
		log.infof("headless: wrote %s", path)
		return true
	}

	expected, expected_size, ok := images.read_png(path)
	if !ok {
		log.errorf("headless: can't read %s", path, location = loc)
		return false
	}

	actual_path := _to_snapshot_path(name, ".actual.png", loc)
	if expected_size != size {
		images.write_png(actual_path, actual, size)
		log.errorf("headless: %s is %v pixels, and the window is %v (see %s)", path, expected_size, size, actual_path, location = loc)
		return false
	}

	diff := make([]u8, len(actual), context.temp_allocator)
	differing := _to_diff(expected, actual, diff)
	if differing == 0 do return true

	diff_path := _to_snapshot_path(name, ".diff.png", loc)
	images.write_png(actual_path, actual, size)
	images.write_png(diff_path, diff, size)
	log.errorf("headless: %d pixels differ from %s (see %s and %s)", differing, path, actual_path, diff_path, location = loc)

	return false
}

_press :: proc(target: Target, button: platform.Mouse_Button, count: int, loc: runtime.Source_Code_Location) {
	settle()
	shown, position, ok := _to_input(target, loc)
	if !ok do return
	_session.key_window = shown
	// The pointer moves first, as a person's pointer does, so a press over a text field focuses it.
	platform.step_headless(shown._platform, platform.Mouse_Move{position})
	settle()
	for click_count in 1 ..= count {
		platform.step_headless(shown._platform, platform.Mouse_Press{position, button, {}, click_count})
		platform.step_headless(shown._platform, platform.Mouse_Release{button})
	}
	settle()
}

// The target's window, and the middle of the target's visible part, in that window's own points.
_to_input :: proc(
	target: Target,
	loc: runtime.Source_Code_Location,
) -> (
	shown: ^app.Window,
	position: [2]f32,
	ok: bool,
) {
	if value, is_point := target.([2]f32); is_point {
		shown = _find_window(app.MAIN_WINDOW)
		return shown, value * shown._zoom.shown, shown != nil
	}

	box := find(target, loc)
	if box == nil do return

	visible := ui._to_shown_rect(box)
	if visible.z <= visible.x || visible.w <= visible.y {
		log.errorf("headless: %s is off screen, so the test can't point at it", _to_line(box, false), location = loc)
		return
	}
	shown = _window_of(box)
	if shown == nil do return

	middle := [2]f32{(visible.x + visible.z) / 2, (visible.y + visible.w) / 2}

	return shown, middle * shown._zoom.shown, true
}

_open_windows :: proc() -> []^app.Window {
	shown := make([dynamic]^app.Window, context.temp_allocator)
	for window in app._windows {
		if !window._platform.is_closed do append(&shown, window)
	}

	return shown[:]
}

_find_window :: proc(id: string) -> ^app.Window {
	for window in _open_windows() {
		if window.id == id do return window
	}

	return nil
}

_to_key_window :: proc() -> ^app.Window {
	for window in _open_windows() {
		if window == _session.key_window do return window
	}

	return _find_window(app.MAIN_WINDOW)
}

_to_roots :: proc(window: ^app.Window) -> [2]^ui.Box {
	return {window._ui.root, window._ui.overlay_root}
}

_window_of :: proc(box: ^ui.Box) -> ^app.Window {
	root := box
	for root.parent != nil do root = root.parent
	for window in _open_windows() {
		if root == window._ui.root || root == window._ui.overlay_root do return window
	}

	return nil
}

_find_labelled :: proc(box: ^ui.Box, label: string, found: ^[dynamic]^ui.Box) {
	for child := box.first; child != nil; child = child.next {
		role, child_label := ui._to_role(child)
		if role != .None && child_label == label do append(found, child)
		if !ui._is_control(role) do _find_labelled(child, label, found)
	}
}

_find_with_id :: proc(box: ^ui.Box, id: string, found: ^[dynamic]^ui.Box) {
	for child := box.first; child != nil; child = child.next {
		if child.id == id do append(found, child)
		_find_with_id(child, id, found)
	}
}

// One element as the tree shows it: `button "Save" focused`.
_to_line :: proc(box: ^ui.Box, with_rects: bool) -> string {
	role, label := ui._to_role(box)
	builder := strings.builder_make(context.temp_allocator)
	strings.write_string(&builder, strings.to_lower(fmt.tprint(role), context.temp_allocator))
	fmt.sbprintf(&builder, " %q", label)
	if box.value != "" do fmt.sbprintf(&builder, " value %q", box.value)
	if box.is_on do strings.write_string(&builder, " on")
	shown := _window_of(box)
	if shown != nil && box._key != 0 && box._key == shown._ui.focused_key do strings.write_string(&builder, " focused")
	if role == .Button && .Clickable not_in box.style.flags do strings.write_string(&builder, " disabled")
	if with_rects {
		rect := box.rect
		fmt.sbprintf(&builder, " %.0f,%.0f %.0f×%.0f", rect.x, rect.y, rect.z - rect.x, rect.w - rect.y)
	}

	return strings.to_string(builder)
}

_to_typing :: proc(key: platform.Key, modifiers: platform.Modifiers, text: string) -> platform.Event {
	is_shifted := .Shift in modifiers
	#partial switch key {
	case .Return, .Enter:
		return platform.Text_Command{"insertNewline:"}
	case .Tab:
		return platform.Text_Command{"insertBacktab:" if is_shifted else "insertTab:"}
	case .Escape:
		return platform.Text_Command{"cancelOperation:"}
	case .Delete:
		return platform.Text_Command{"deleteWordBackward:" if .Option in modifiers else "deleteBackward:"}
	case .Forward_Delete:
		return platform.Text_Command{"deleteForward:"}
	case .Left:
		return platform.Text_Command{"moveLeftAndModifySelection:" if is_shifted else "moveLeft:"}
	case .Right:
		return platform.Text_Command{"moveRightAndModifySelection:" if is_shifted else "moveRight:"}
	case .Up:
		return platform.Text_Command{"moveUpAndModifySelection:" if is_shifted else "moveUp:"}
	case .Down:
		return platform.Text_Command{"moveDownAndModifySelection:" if is_shifted else "moveDown:"}
	case .Home:
		return platform.Text_Command{"moveToBeginningOfDocument:"}
	case .End:
		return platform.Text_Command{"moveToEndOfDocument:"}
	}
	if text == "" do return nil

	return platform.Text_Insert{text}
}

_to_snapshot_path :: proc(name, extension: string, loc: runtime.Source_Code_Location) -> string {
	folder := strings.concatenate({filepath.dir(loc.file_path), "/snapshots"}, context.temp_allocator)
	if !os.exists(folder) do _ = os.make_directory(folder)

	return strings.concatenate({folder, "/", name, extension}, context.temp_allocator)
}

_is_writing :: proc(path: string) -> bool {
	return !os.exists(path) || os.get_env("THOR_UPDATE_SNAPSHOTS", context.temp_allocator) == "1"
}

// Counts the pixels that differ. In diff, it paints them red and the rest as a dim copy of actual.
_to_diff :: proc(expected, actual, diff: []u8) -> (differing: int) {
	for index := 0; index < len(actual); index += 4 {
		is_different := false
		for channel in 0 ..< 4 {
			if abs(int(expected[index + channel]) - int(actual[index + channel])) > PIXEL_TOLERANCE do is_different = true
		}
		if is_different {
			differing += 1
			// BGRA: red, opaque.
			diff[index], diff[index + 1], diff[index + 2], diff[index + 3] = 0, 0, 255, 255
		} else {
			for channel in 0 ..< 4 do diff[index + channel] = actual[index + channel] / 4
			diff[index + 3] = 255
		}
	}

	return
}

// Lines only in expected get -, lines only in actual get +, in order. Skips the longest common run.
_to_line_diff :: proc(expected, actual: string) -> string {
	old := strings.split_lines(expected, context.temp_allocator)
	new := strings.split_lines(actual, context.temp_allocator)
	// common[i][j]: the length of the longest common run of old[i:] and new[j:].
	width := len(new) + 1
	common := make([]int, (len(old) + 1) * width, context.temp_allocator)
	#reverse for _, i in old {
		#reverse for _, j in new {
			at := i * width + j
			common[at] = common[at + width + 1] + 1 if old[i] == new[j] else max(common[at + width], common[at + 1])
		}
	}

	builder := strings.builder_make(context.temp_allocator)
	i, j := 0, 0
	for i < len(old) || j < len(new) {
		switch {
		case i < len(old) && j < len(new) && old[i] == new[j]:
			i += 1
			j += 1
		case i < len(old) && (j == len(new) || common[(i + 1) * width + j] >= common[i * width + j + 1]):
			fmt.sbprintf(&builder, "- %s\n", old[i])
			i += 1
		case:
			fmt.sbprintf(&builder, "+ %s\n", new[j])
			j += 1
		}
	}

	return strings.to_string(builder)
}
