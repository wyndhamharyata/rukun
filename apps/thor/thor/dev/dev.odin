package dev

import "../images"
import "../platform"
import "../ui"
import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

DEFAULT_BENCH_SECONDS :: 20

BENCH_DELAY_SECONDS :: 1

BENCH_POINTS_PER_SECOND :: 1500


TEST_TYPING_DELAY_SECONDS :: 1

FRAME_TIME_WIDTH_POINTS :: 110

FRAME_TIME_RIGHT_MARGIN_POINTS :: 10

// Tests drive and read a window through THOR_ settings, never taking the screen.
// THOR_CAPTURE runs headless and writes the PNG THOR_CAPTURE_SECONDS of app time after settling.
capture_path: string
capture_seconds: f32
is_bench: bool
bench_seconds: f64
is_startup_mark: bool
is_showing_frames: bool
is_background: bool
// THOR_KEEP_FRAME, set by watch.sh, reopens the window where it last was.
is_keeping_frame: bool
window_size_points: [2]f32
// THOR_ZOOM sets the zoom at open without saving it; 0 means unset.
forced_zoom: f32
// THOR_APPEARANCE=light or dark overrides the app's appearance.
forced_appearance: platform.Appearance
// Tests set this instead of the person's accessibility settings.
forced_preferences: Maybe(platform.Preferences)
test_typing: string
started_at: time.Tick
build_durations: [dynamic]time.Duration
frame_starts: [dynamic]time.Tick

_is_started: bool
_frame_start: time.Tick
_first_frame_end: time.Tick
_bench_start: time.Tick
_bench_from: f32
_bench_direction: f32
_is_startup_marked: bool

start :: proc() {
	if _is_started do return

	_is_started = true
	capture_path = os.get_env("THOR_CAPTURE", context.allocator)
	is_bench = os.get_env("THOR_BENCH", context.temp_allocator) == "1"
	bench_seconds =
		strconv.parse_f64(
			os.get_env("THOR_BENCH_SECONDS", context.temp_allocator),
		) or_else DEFAULT_BENCH_SECONDS
	is_startup_mark = os.get_env("THOR_STARTUP_MARK", context.temp_allocator) == "1"
	is_keeping_frame = os.get_env("THOR_KEEP_FRAME", context.temp_allocator) == "1"
	is_inspecting = os.get_env("THOR_INSPECT", context.temp_allocator) == "1"
	is_showing_frames = os.get_env("THOR_FRAMES", context.temp_allocator) == "1"
	is_background = is_bench || os.get_env("THOR_BACKGROUND", context.temp_allocator) == "1"
	test_typing = os.get_env("THOR_TYPE", context.allocator)
	forced_zoom = f32(strconv.parse_f64(os.get_env("THOR_ZOOM", context.temp_allocator)) or_else 0)
	switch os.get_env("THOR_APPEARANCE", context.temp_allocator) {
	case "light":
		forced_appearance = .Light
	case "dark":
		forced_appearance = .Dark
	}
	started_at = time.tick_now()

	capture_seconds = f32(
		strconv.parse_f64(os.get_env("THOR_CAPTURE_SECONDS", context.temp_allocator)) or_else 0,
	)

	size_text := os.get_env("THOR_WINDOW", context.temp_allocator)
	width_text, _, height_text := strings.partition(size_text, "x")
	width, is_width := strconv.parse_f64(width_text)
	height, is_height := strconv.parse_f64(height_text)
	if is_width && is_height do window_size_points = {f32(width), f32(height)}
}

apply_test_typing :: proc() {
	seconds_since_start := time.duration_seconds(time.tick_since(started_at))
	is_typing_due := test_typing != "" && seconds_since_start > TEST_TYPING_DELAY_SECONDS

	if !is_typing_due do return

	has_context := platform.type_for_test(test_typing)
	fmt.eprintfln("typed %q. The input view has an input context: %v", test_typing, has_context)
	test_typing = ""
}

begin_frame :: proc(start: time.Tick) {
	_frame_start = start
	if is_bench do append(&frame_starts, start)
}

// Call it each frame for THOR_BENCH. Time sets the place so slow frames keep the speed.
bench_scroll :: proc(box: ^ui.Box) {
	if !is_bench || box == nil || _first_frame_end == {} do return

	max_scroll := box.content_size.y - box.size.y
	if max_scroll <= 0 do return

	since_first := time.duration_seconds(time.tick_diff(_first_frame_end, _frame_start))
	if since_first < BENCH_DELAY_SECONDS do return

	if _bench_start == {} {
		_bench_start = _frame_start
		_bench_from = box.scroll
		_bench_direction = 1 if box.scroll < max_scroll / 2 else -1
	}

	seconds := f32(time.duration_seconds(time.tick_diff(_bench_start, _frame_start)))
	position := _bench_from + _bench_direction * seconds * BENCH_POINTS_PER_SECOND
	ui.set_scroll(box, _to_bounced(position, max_scroll))
}

// Folds a position into 0..max_scroll so the scroll turns back at each end.
_to_bounced :: proc(position, max_scroll: f32) -> f32 {
	period := 2 * max_scroll
	folded := math.mod(position, period)
	if folded < 0 do folded += period

	return folded if folded <= max_scroll else period - folded
}

// THOR_STARTUP_MARK prints first-frame once the layout needs no further frame.
mark_startup :: proc(is_layout_settled: bool) {
	if !is_startup_mark || _is_startup_marked || !is_layout_settled do return

	_is_startup_marked = true
	fmt.println("first-frame")
}

finish_frame :: proc(start: time.Tick) -> (is_bench_done: bool) {
	if !is_bench do clear(&build_durations)
	append(&build_durations, time.tick_since(start))
	if _first_frame_end == {} do _first_frame_end = time.tick_now()

	is_bench_done =
		is_bench &&
		_bench_start != {} &&
		time.duration_seconds(time.tick_diff(_bench_start, start)) >= bench_seconds

	return is_bench_done
}

build_frame_time :: proc(color: [4]f32) {
	count := len(build_durations)
	if count == 0 || !is_showing_frames do return

	last_ms := time.duration_milliseconds(build_durations[count - 1])
	root := ui.current_parent()

	ui.box(
		"",
		{
			width = ui.points(FRAME_TIME_WIDTH_POINTS),
			height = ui.points(20),
			position = {
				root.style.width.value - FRAME_TIME_WIDTH_POINTS - FRAME_TIME_RIGHT_MARGIN_POINTS,
				8,
			},
			text_align = .End,
			text_color = color,
			font_size = 11,
			flags = {.Floating},
		},
		fmt.tprintf("frame %.2f ms", last_ms),
	)
}

finish_bench :: proc() {
	first := 0
	for time.tick_diff(_bench_start, frame_starts[first]) < 0 do first += 1

	starts := frame_starts[first:]
	builds := build_durations[first:]

	for start in starts {
		microseconds := time.duration_microseconds(time.tick_diff(_bench_start, start))
		fmt.printfln("frame %d", i64(microseconds))
	}

	slice.sort(builds)
	gaps: [dynamic]time.Duration

	for index in 1 ..< len(starts) {
		append(&gaps, time.tick_diff(starts[index - 1], starts[index]))
	}

	slice.sort(gaps[:])

	fmt.printfln(
		"build per frame ms: p50 %.2f p99 %.2f max %.2f",
		_to_percentile_ms(builds, 0.5),
		_to_percentile_ms(builds, 0.99),
		_to_percentile_ms(builds, 1),
	)

	ready, total := images.list_counts()
	fmt.printfln("images on the GPU %d, known %d", ready, total)

	fmt.printfln(
		"gap between frames ms: p50 %.2f p99 %.2f max %.2f",
		_to_percentile_ms(gaps[:], 0.5),
		_to_percentile_ms(gaps[:], 0.99),
		_to_percentile_ms(gaps[:], 1),
	)
	fmt.println("done")

	platform.quit()
}

_to_percentile_ms :: proc(sorted: []time.Duration, fraction: f64) -> f64 {
	return time.duration_milliseconds(sorted[int(math.floor(f64(len(sorted) - 1) * fraction))])
}
