package images

import "../platform"
import "core:hash"
import "core:math"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import MTL "vendor:darwin/Metal"

MAX_IMAGE_BYTES :: 64 * 1024 * 1024

WORKER_COUNT :: 6

FAILED_RETRY_WAIT :: 30 * time.Second

FADE_IN_SECONDS :: 0.25

_CROP_KEY_STEPS :: 100
_CROP_ASPECT_SHIFT :: 40
_CROP_FOCUS_SHIFT :: 52

_Phase :: enum {
	Waiting,
	Loading,
	Ready,
	Failed,
}

_Entry :: struct {
	phase:            _Phase,
	url:              string,
	size_pixels:      int,
	texture:          ^MTL.Texture,
	last_drawn_frame: int,
	ready_time:       time.Tick,
	failed_time:      time.Tick,
	family:           u64,
	had_stand_in:     bool,
	color:            Color,
	crop:             Crop,
	bytes:            int,
}

Crop :: struct {
	aspect:  f32,
	focus_y: f32,
}

Color :: struct {
	rgb:       [3]f32,
	vividness: f32,
}

// Runs on a worker thread and returns the path of a file that holds the image at the URL.
Fetch_Proc :: #type proc(url: string) -> (path: string, ok: bool)

// Returns the part of a URL that names the image at any size, so one loaded size can replace another.
Family_Proc :: #type proc(url: string) -> string

_Job :: struct {
	key:         u64,
	url:         string,
	size_pixels: int,
	crop:        Crop,
	texture:     ^MTL.Texture,
	color:       Color,
}

_state: struct {
	is_started:    bool,
	fetch:         Fetch_Proc,
	to_family:     Family_Proc,
	entries:       map[u64]^_Entry,
	waiting:       [dynamic]u64,
	loading_count: int,
	pool:          thread.Pool,
	mutex:         sync.Mutex,
	finished:      [dynamic]^_Job,
	families:      map[u64]u64,
	frame_index:   int,
	is_animating:  bool,
}

start :: proc(fetch: Fetch_Proc = nil, to_family: Family_Proc = nil) {
	_state.fetch = fetch
	_state.to_family = to_family
	if _state.is_started do return

	_state.is_started = true
	thread.pool_init(&_state.pool, context.allocator, WORKER_COUNT)
	thread.pool_start(&_state.pool)
}

begin_frame :: proc() {
	_state.frame_index += 1
	_state.is_animating = false

	_take_finished()
	for _ in thread.pool_pop_done(&_state.pool) {}
	_start_waiting()
	_unload_extra()
}

is_animating :: proc() -> bool {
	return _state.is_animating
}

// True while an image the frame asked for is still loading.
is_loading :: proc() -> bool {
	return _state.loading_count > 0 || len(_state.waiting) > 0
}

// The image cropped to fill size_pixels, with the region of the texture that fills it.
watch_filling :: proc(url: string, size_pixels: [2]f32) -> (texture: ^MTL.Texture, uv: [4]f32, opacity: f32) {
	if size_pixels.x <= 0 || size_pixels.y <= 0 do return
	// The cache keys on the crop, so the aspect snaps to quarter steps.
	aspect := math.floor(size_pixels.x / size_pixels.y * 4 + 0.01) / 4
	texture, opacity = watch(url, int(math.ceil(max(size_pixels.x, size_pixels.y))), {aspect, 0.5})
	if texture == nil do return

	box_ratio := size_pixels.x / size_pixels.y
	texture_ratio := f32(texture->width()) / f32(texture->height())
	switch {
	case abs(box_ratio - texture_ratio) < 0.01:
		uv = {0, 0, 1, 1}
	case texture_ratio > box_ratio:
		width := box_ratio / texture_ratio
		uv = {(1 - width) / 2, 0, (1 + width) / 2, 1}
	case:
		height := texture_ratio / box_ratio
		uv = {0, (1 - height) / 2, 1, (1 + height) / 2}
	}

	return
}

watch :: proc(
	url: string,
	size_pixels: int,
	crop := Crop{},
) -> (
	texture: ^MTL.Texture,
	opacity: f32,
) {
	crop_key :=
		(u64(crop.aspect * _CROP_KEY_STEPS) << _CROP_ASPECT_SHIFT) |
		(u64(crop.focus_y * _CROP_KEY_STEPS) << _CROP_FOCUS_SHIFT)
	key := hash.fnv64a(transmute([]u8)url) ~ u64(size_pixels) ~ crop_key
	entry, ok := _state.entries[key]

	if !ok {
		entry = new(_Entry)
		entry.url = strings.clone(url)
		entry.size_pixels = size_pixels
		entry.crop = crop
		entry.family = _to_family(url)
		_state.entries[key] = entry
	}

	entry.last_drawn_frame = _state.frame_index

	stand_in: ^_Entry
	has_stand_in: bool
	if entry.phase != .Ready do stand_in, has_stand_in = _find_stand_in(entry.family, key, crop)

	if has_stand_in {
		entry.had_stand_in = true
		stand_in.last_drawn_frame = _state.frame_index
		if entry.phase == .Waiting do append(&_state.waiting, key)

		return stand_in.texture, 1
	}

	switch entry.phase {
	case .Waiting:
		append(&_state.waiting, key)
	case .Loading:
	case .Failed:
		if time.tick_diff(entry.failed_time, platform.now()) > FAILED_RETRY_WAIT do entry.phase = .Waiting
	case .Ready:
		if entry.had_stand_in do return entry.texture, 1

		seconds := f32(time.duration_seconds(time.tick_diff(entry.ready_time, platform.now())))
		opacity = min(1, seconds / FADE_IN_SECONDS)
		if opacity < 1 do _state.is_animating = true

		return entry.texture, opacity
	}

	return nil, 0
}

_to_family :: proc(url: string) -> u64 {
	family := url
	has_family := !strings.has_prefix(url, "/") && _state.to_family != nil
	if has_family do family = _state.to_family(url)

	return hash.fnv64a(transmute([]u8)family)
}

_find_stand_in :: proc(family, key: u64, crop: Crop) -> (^_Entry, bool) {
	stand_in_key, ok := _state.families[family]
	if !ok || stand_in_key == key do return nil, false

	stand_in := _state.entries[stand_in_key]
	if stand_in.crop != crop do return nil, false

	return stand_in, true
}

_start_waiting :: proc() {
	#reverse for key in _state.waiting {
		if _state.loading_count >= WORKER_COUNT do break

		entry := _state.entries[key] or_else nil
		is_wanted := entry != nil && entry.phase == .Waiting && _is_on_screen(entry)
		if !is_wanted do continue

		entry.phase = .Loading
		_state.loading_count += 1

		job := new(_Job)
		job^ = _Job {
			key         = key,
			url         = strings.clone(entry.url),
			size_pixels = entry.size_pixels,
			crop        = entry.crop,
		}
		thread.pool_add_task(&_state.pool, context.allocator, _fetch_image, job)
	}

	clear(&_state.waiting)
}

_take_finished :: proc() {
	sync.guard(&_state.mutex)

	for job in _state.finished {
		_state.loading_count -= 1
		entry := _state.entries[job.key]

		if job.texture == nil {
			entry.phase = .Failed
			entry.failed_time = platform.now()
		} else {
			entry.phase = .Ready
			entry.texture = job.texture
			entry.bytes = int(job.texture->width() * job.texture->height()) * _BYTES_PER_PIXEL
			entry.color = job.color
			entry.ready_time = platform.now()
			_state.families[entry.family] = job.key
		}

		delete(job.url)
		free(job)
	}

	clear(&_state.finished)
}

_unload_extra :: proc() {
	ready_bytes := 0
	for _, entry in _state.entries do if entry.phase == .Ready do ready_bytes += entry.bytes

	if ready_bytes <= MAX_IMAGE_BYTES do return

	Candidate :: struct {
		key:              u64,
		last_drawn_frame: int,
	}
	candidates := make([dynamic]Candidate, context.temp_allocator)

	for key, entry in _state.entries {
		if entry.phase == .Ready && !_is_on_screen(entry) {
			append(&candidates, Candidate{key, entry.last_drawn_frame})
		}
	}

	slice.sort_by(
		candidates[:],
		proc(a, b: Candidate) -> bool {return a.last_drawn_frame < b.last_drawn_frame},
	)

	for candidate in candidates {
		if ready_bytes <= MAX_IMAGE_BYTES do break

		entry := _state.entries[candidate.key]
		ready_bytes -= entry.bytes

		if _state.families[entry.family] == candidate.key {
			delete_key(&_state.families, entry.family)
		}

		// A command buffer keeps the textures it draws alive until the GPU finishes.
		entry.texture->release()
		delete(entry.url)
		free(entry)
		delete_key(&_state.entries, candidate.key)
	}
}

_is_on_screen :: proc(entry: ^_Entry) -> bool {
	return entry.last_drawn_frame >= _state.frame_index - 1
}

list_counts :: proc() -> (ready, total: int) {
	for _, entry in _state.entries do if entry.phase == .Ready do ready += 1

	return ready, len(_state.entries)
}

find_color :: proc(url: string) -> (Color, bool) {
	key, ok := _state.families[_to_family(url)]
	if !ok do return {}, false

	return _state.entries[key].color, true
}
