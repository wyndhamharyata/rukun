package ui

import "../font"
import "../platform"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:mem"
import "core:reflect"
import "core:strings"

// Auto, the zero value, lays out the children as a row.
Axis :: enum {
	Auto,
	X,
	Y,
}

_axis_index :: proc "contextless" (axis: Axis) -> int {
	return 1 if axis == .Y else 0
}

// Fit, the zero value, takes the size of the box's text, or of its children if it has no text.
Size_Kind :: enum {
	Fit,
	Points,
	Text,
	Children,
	Fill,
}

Size :: struct {
	kind:  Size_Kind,
	value: f32,
}

// A fixed size in points.
points :: proc "contextless" (value: f32) -> Size {return {.Points, value}}

// Along the parent's axis, a share of the space left, by weight. Across it, all of the parent.
fill :: proc "contextless" (weight: f32 = 1) -> Size {return {.Fill, weight}}

// The children's size, with their gaps and the padding.
fit_children :: proc "contextless" () -> Size {return {.Children, 0}}

// The text's size, with the padding.
fit_text :: proc "contextless" () -> Size {return {.Text, 0}}

// Auto, the zero value, is the start.
Align :: enum {
	Auto,
	Start,
	Center,
	End,
}

Flag :: enum {
	Clickable,
	Hoverable,
	Scroll,
	Clip,
	Floating,
	Wrap_Text,
	Truncate_Text,
	Wrap_Children,
	// Its .Clickable children are one Tab stop, and the arrow keys move between them.
	Arrow_Keys,
	// The box shows keyboard focus in its own way, as a text field does.
	No_Focus_Ring,
	// With focus, the box takes Tab and Shift-Tab as text. Ctrl-Tab still moves focus.
	Keeps_Tab,
	// On an overlay: boxes under it take no pointer input. Focus stays in it and later overlays.
	Modal,
	// Fades in, in _FADE_MOTION, on the first frame the box exists.
	Fade_In,
	// When the app stops building the box, its last frame stays and fades out in _FADE_MOTION.
	Fade_Out,
}

Flags :: bit_set[Flag]

Style :: struct {
	width, height:    Size,
	axis:             Axis,
	padding:          [4]f32,
	gap:              f32,
	// On the cross axis. justify places the children on the main axis.
	align:            Align,
	justify:          Align,
	text_align:       Align,
	text_offset:      f32,
	background:       [4]f32,
	softness:         f32,
	end_background:   [4]f32,
	gradient:         [2]f32,
	hover_background: [4]f32,
	press_background: [4]f32,
	border_color:     [4]f32,
	border_width:     f32,
	corner_radius:    f32,
	text_color:       [4]f32,
	font_weight:      font.Weight,
	font_size:        f32,
	font_family:      font.Family,
	// In points. 0 uses the font's own.
	line_height:      f32,
	fade:             f32,
	position:         [2]f32,
	// A non-zero motion springs the box from its old place in its parent, and its size in points.
	motion:           Motion,
	// The system's glass behind the box, tinted with its background.
	glass:            Glass,
	// 0 means no limit.
	min_size:         [2]f32,
	max_size:         [2]f32,
	// The pointer shape over the box and over the children that set no cursor.
	cursor:           platform.Cursor,
	flags:            Flags,
}

Draw_Proc :: proc(box: ^Box, rect_pixels, clip_pixels: [4]f32, opacity: f32)

Box :: struct {
	// For warnings only. It can be a temporary string, so it is valid for this frame only.
	id:               string,
	// The hash outlives the frame, because _find_box_by_id reads boxes from the last frame.
	_id_hash:         u64,
	_key:             u64,
	// The key of the box, or of its nearest parent with an id. Child keys use it as the hash seed.
	_seed:            u64,
	parent:           ^Box,
	first, last:      ^Box,
	next:             ^Box,
	style:            Style,
	text:             string,
	draw:             Draw_Proc,
	color_of:         font.Color_Proc,
	data:             rawptr,
	_last_built_frame: int,
	size:             [2]f32,
	rect:             [4]f32,
	clip:             [4]f32,
	content_size:     [2]f32,
	shaped:           ^font.Shaped_Text,
	forced:           Forced_State,
	_hot_fraction:    f32,
	_active_fraction: f32,
	scroll:           f32,
	_scroll_target:   f32,
	// The scroll of the last layout. Events and set_scroll change scroll before the next layout.
	_placed_scroll:   f32,
	// The kit component that builds the box sets it.
	role:             Role,
	// A button's label, a field's placeholder, an icon button's id.
	label:            string,
	// x and y of its place in its parent, then width and height, while style.motion springs them.
	_motion:          [4]_Animated_Value,
	_appear:          _Animated_Value,
	_was_built_last_frame: bool,
	// A field's text, a slider's percent.
	value:            string,
	// Checked, on, selected or current.
	is_on:            bool,
}

Role :: platform.Role

// An id names what an element is for. Labels such as "Save" change with the language.
// Capitals alone do not count, because data ids such as "i.Kv8JsA" or a UUID have them too.
_is_text_like_id :: proc(id: string) -> bool {
	is_word := len(id) > 1 && id[0] >= 'A' && id[0] <= 'Z'
	for letter, index in id {
		if letter == ' ' || letter > 0x7f do return true
		if index > 0 && (letter < 'a' || letter > 'z') do is_word = false
	}

	return is_word
}

_Animated_Value :: struct {
	value:             f32,
	velocity:          f32,
	_last_built_frame: int,
}

// A spring that settles on its target in about duration seconds. The zero Motion arrives at once,
// as every Motion does when the person reduces motion.
Motion :: struct {
	duration: f32,
	// 0 settles with no overshoot. 0.3 overshoots a little.
	bounce:   f32,
}

// Not style.motion: an overlay that fades must still follow its anchor at once.
_FADE_MOTION :: Motion{duration = 0.15}

// A stiff spring stays stable at 240 steps a second, even when a frame takes 1/30 s.
_SPRING_STEP_SECONDS :: 1.0 / 240

HOT_RATE_PER_SECOND :: 20

POINTS_PER_LINE :: 40

_SETTLED_FRACTION :: 0.002

_MAX_FRAME_SECONDS :: 1.0 / 30

_NO_CLIP :: [4]f32{0, 0, 1e9, 1e9}

// For text with no text_color. app sets it from kit's theme each frame.
_default_text_color := [4]f32{0.95, 0.95, 0.96, 1}

Forced_State :: enum {
	None,
	Rest,
	Hover,
	Press,
	Focus,
}

// Boxes built while it is not .None show that state at once and ignore the mouse, as in a gallery.
forced_state: Forced_State

// The state of one window. Each window has its own, and _state points to the one in use.
Context :: struct {
	boxes:                  map[u64]^Box,
	values:                 map[u64]_Animated_Value,
	// The last frame of each box with .Fade_Out, by its key.
	ghosts:                 map[u64]_Ghost,
	// The boxes with glass in the frame drawn last, which app passes to platform.
	glass_areas:            [dynamic]platform.Glass_Area,
	root:                   ^Box,
	overlay_root:           ^Box,
	parents:                [dynamic]^Box,
	frame_index:            int,
	pixels_per_point:       f32,
	zoom:                   f32,
	window_size:            [2]f32,
	frame_seconds:          f32,
	mouse:                  [2]f32,
	hot_key:                u64,
	active_key:             u64,
	// The deepest box under the pointer, and the keys of that box and of every box around it.
	pointer_box:            ^Box,
	hover_chain:            [dynamic]u64,
	interaction:            Interaction,
	scroll_keys:            [2]u64,
	swipe_axis:             Maybe(Axis),
	undecided_swipe_points: [2]f32,
	activated_key:          u64,
	activated_count:        int,
	activated_device:       Device,
	secondary_key:          u64,
	is_secondary_press:     bool,
	long_pressed_key:       u64,
	pressed_at:             [2]f32,
	is_pressed:             bool,
	cursor:                 platform.Cursor,
	focused_key:            u64,
	is_focus_moved:         bool,
	focus_order:            [dynamic]_Focus_Stop,
	// The last focused box of each group. Tab enters the group again at that box.
	group_focus:            map[u64]u64,
	taken_keys:             bit_set[0 ..< 128],
	pressed_keys:           bit_set[0 ..< 128],
	is_animating:           bool,
	is_frame_requested:     bool,
	// Hashes of the warnings printed, so each prints once.
	warned:                 map[u64]bool,
}

_default_context: Context
_state: ^Context

@(init)
_start_context :: proc "contextless" () {
	_state = &_default_context
}

// Boxes and input use this context until the next call.
_use_context :: proc(ui_context: ^Context) {
	_state = ui_context
}

_destroy_context :: proc(ui_context: ^Context) {
	delete(ui_context.glass_areas)
	for _, ghost in ui_context.ghosts do delete(ghost.pushed)
	delete(ui_context.ghosts)
	for _, box in ui_context.boxes do free(box)
	delete(ui_context.boxes)
	delete(ui_context.values)
	delete(ui_context.parents)
	delete(ui_context.focus_order)
	delete(ui_context.hover_chain)
	delete(ui_context.group_focus)
	delete(ui_context.warned)
	ui_context^ = {}
	if _state == ui_context do _state = &_default_context
}

_begin_frame :: proc(
	window_size_points: [2]f32,
	pixels_per_point, zoom, frame_seconds: f32,
	events: []platform.Event,
) {
	_state.frame_index += 1
	_state.zoom = zoom
	_state.window_size = window_size_points / zoom
	_state.pixels_per_point = pixels_per_point * zoom
	_state.frame_seconds = min(frame_seconds, _MAX_FRAME_SECONDS)
	_state.activated_key = 0
	_state.activated_count = 0
	_state.activated_device = .None
	_state.secondary_key = 0
	_state.long_pressed_key = 0
	_state.taken_keys = {}
	_state.pressed_keys = {}
	_state.is_pressed = false
	_state.is_animating = false
	_state.is_frame_requested = false

	_apply_events(events)

	clear(&_state.parents)
	window := Style {
		width  = points(_state.window_size.x),
		height = points(_state.window_size.y),
	}
	_state.root = _make_box(0, window)
	_state.overlay_root = _make_box(0, window)
	_state.overlay_root._seed = _OVERLAY_SEED
	append(&_state.parents, _state.root)
}

_OVERLAY_SEED :: 0x6f7665726c6179

// The modal box and the overlays after it take the input.
_find_modal :: proc() -> ^Box {
	modal: ^Box
	for child := _state.overlay_root.first; child != nil; child = child.next {
		if .Modal in child.style.flags do modal = child
	}

	return modal
}

// It draws last, takes the mouse first, and no box around the call clips or scrolls it.
// style.position is in the window's points.
@(deferred_none = pop_parent)
overlay :: proc(id: string, style: Style) -> bool {
	floating := style
	floating.flags += {.Floating}
	push_parent(_state.overlay_root)
	layer_box := box(id, floating)
	pop_parent()
	push_parent(layer_box)

	return true
}

// The search covers every container, so give the box an id that no other box uses.
_find_box_by_id :: proc(id: string) -> ^Box {
	id_hash := hash.fnv64a(transmute([]u8)id)
	found: ^Box
	for _, candidate in _state.boxes {
		if candidate._id_hash != id_hash || candidate._last_built_frame < _state.frame_index - 1 do continue
		if found != nil {
			// Map order picks the match, so the caller gets either box from one frame to the next.
			_warn(candidate, "two boxes have the id \"%s\", so a lookup by it finds either one. Give each box its own id.", id)
			return found
		}
		found = candidate
	}

	return found
}

// Where the person pressed either mouse button this frame.
_pressed_at :: proc() -> ([2]f32, bool) {
	return _state.pressed_at, _state.is_pressed
}

// The pointer shape that the box under the mouse asks for.
_cursor :: proc() -> platform.Cursor {
	return _state.cursor
}

Preferences :: platform.Preferences

Glass :: platform.Glass
Glass_Area :: platform.Glass_Area

// app sets it at launch and when System Settings changes. It is the same for every window.
_preferences: Preferences

// The person's display settings for accessibility, which motion, contrast and glass follow.
preferences :: proc() -> Preferences {
	return _preferences
}

// In points at the current zoom, so zooming in makes it smaller. Lay out by it, never by the zoom.
window_size :: proc() -> [2]f32 {
	return _state.window_size
}

// True while a spring, fade or scroll still moves.
is_animating :: proc() -> bool {
	return _state.is_animating
}

// Use it when a value changes after you build the boxes that read it.
request_frame :: proc() {
	_state.is_frame_requested = true
}

// Asks for a frame seconds from now, as a clock or a delay needs.
request_frame_after :: proc(seconds: f64) {
	platform.request_frame_after(seconds)
}

_is_frame_requested :: proc() -> bool {
	return _state.is_frame_requested
}

_is_frame_wanted :: proc() -> bool {
	return _state.is_animating || _state.is_frame_requested
}

_to_key :: proc(id: string, seed: u64) -> u64 {
	// 0x100000001b3 is the FNV-1a 64-bit prime. 0xcbf29ce484222325 is its offset basis.
	return hash.fnv64a(transmute([]u8)id, seed * 0x100000001b3 + 0xcbf29ce484222325)
}

// The box that the boxes built now go into.
current_parent :: proc() -> ^Box {
	return _state.parents[len(_state.parents) - 1]
}

// Adds a box to the current parent. Its id keeps its state between frames, and "" keeps none.
box :: proc(id: string, style: Style, text: string = "") -> ^Box {
	parent := current_parent()
	key := _to_key(id, parent._seed) if id != "" else 0

	cached, is_cached := _state.boxes[key]
	if is_cached && key != 0 && cached._last_built_frame == _state.frame_index {
		_warn(
			parent,
			"two children have the id \"%s\". The second one keeps no state, so it gets no clicks, scroll or animation. Give each child its own id.",
			id,
		)
		key = 0
	}
	if id != "" && _is_text_like_id(id) {
		_warn(parent, "the id \"%s\" looks like a label. Use snake_case, such as sort_menu.", id)
	}
	was_built_last_frame := key != 0 && is_cached && cached._last_built_frame == _state.frame_index - 1
	box := _make_box(key, style)
	box._was_built_last_frame = was_built_last_frame
	if key != 0 && style.motion != {} do _spring_size(box)
	if key != 0 && .Fade_In in style.flags {
		appear := &box._appear
		if !was_built_last_frame do appear^ = {}
		appear.value, appear.velocity = _spring(appear.value, appear.velocity, 1, _FADE_MOTION)
		box.style.fade = 1 - (1 - box.style.fade) * appear.value
	}
	box.id = id
	box._id_hash = hash.fnv64a(transmute([]u8)id) if id != "" else 0

	box._seed = key if key != 0 else parent._seed
	box.text = text
	box.parent = parent

	if parent.last == nil {
		parent.first = box
	} else {
		parent.last.next = box
	}
	parent.last = box

	return box
}

_make_box :: proc(key: u64, style: Style) -> ^Box {
	box, is_cached := _state.boxes[key]

	if key == 0 {
		box = new(Box, context.temp_allocator)
	} else if !is_cached {
		box = new(Box)
		box._key = key
		_state.boxes[key] = box
	}

	box.style = style
	box.first = nil
	box.last = nil
	box.next = nil
	box.text = ""
	box.shaped = nil
	box.draw = nil
	box.color_of = nil
	box.data = nil
	box.role = .None
	box.label = ""
	box.value = ""
	box.is_on = false
	box.forced = forced_state
	box._last_built_frame = _state.frame_index

	return box
}

// Makes box the parent of the boxes built in the if block.
@(deferred_none = pop_parent)
scope :: proc(box: ^Box) -> bool {
	push_parent(box)
	return true
}

// A box that lays out the children built in the if block from left to right.
@(deferred_none = pop_parent)
row :: proc(id: string, style: Style = {}) -> bool {
	style := style
	style.axis = .X
	push_parent(box(id, style))
	return true
}

// A box that lays out the children built in the if block from top to bottom.
@(deferred_none = pop_parent)
col :: proc(id: string, style: Style = {}) -> bool {
	style := style
	style.axis = .Y
	push_parent(box(id, style))
	return true
}

// changes replaces each field it sets, and adds its flags, so a caller sets only what differs.
// shortcut: a zero field cannot set a value back to zero, such as axis .X or weight .Regular.
merge :: proc(base, changes: Style) -> Style {
	merged, changes := base, changes

	for field in reflect.struct_fields_zipped(Style) {
		from := mem.byte_slice(rawptr(uintptr(&changes) + field.offset), field.type.size)
		if mem.check_zero(from) do continue

		mem.copy(rawptr(uintptr(&merged) + field.offset), raw_data(from), field.type.size)
	}

	merged.flags = base.flags + changes.flags

	return merged
}

// Makes box the parent of the boxes built next, until pop_parent. scope does both.
push_parent :: proc(box: ^Box) {
	append(&_state.parents, box)
}

// Ends the last push_parent.
pop_parent :: proc() {
	pop(&_state.parents)
}

// The box with this id in parent, from this frame or the last, or nil.
find_box :: proc(id: string, parent: ^Box) -> ^Box {
	return _state.boxes[_to_key(id, parent._seed)] or_else nil
}

_find_box_with_key :: proc(key: u64) -> ^Box {
	return _state.boxes[key] or_else nil
}

// Layout keeps the scroll inside the content, so a large value scrolls to the end.
set_scroll :: proc(box: ^Box, scroll: f32) {
	if box == nil do return

	box.scroll = scroll
	box._scroll_target = scroll
}

// Springs a value toward target with motion. The id keeps the value between frames.
animate :: proc(id: string, target: f32, motion: Motion) -> f32 {
	key := _to_key(id, 0)
	value, ok := _state.values[key]

	if !ok do value.value = target

	value.value, value.velocity = _spring(value.value, value.velocity, target, motion)
	value._last_built_frame = _state.frame_index
	_state.values[key] = value

	return value.value
}

// ω is 2π / duration and the damping ratio is 1 − bounce.
_spring :: proc(value, velocity, target: f32, motion: Motion) -> (f32, f32) {
	if motion.duration <= 0 || _preferences.is_reducing_motion do return target, 0

	omega := 2 * math.PI / motion.duration
	damping := 1 - motion.bounce
	x, v := value, velocity
	for left := _state.frame_seconds; left > 0; left -= _SPRING_STEP_SECONDS {
		step := min(left, _SPRING_STEP_SECONDS)
		v += (-omega * omega * (x - target) - 2 * damping * omega * v) * step
		x += v * step
	}

	scale := max(1, abs(target))
	if abs(target - x) < _SETTLED_FRACTION * scale && abs(v) < _SETTLED_FRACTION * scale * omega do return target, 0

	_state.is_animating = true

	return x, v
}

// shortcut: only a size in points springs, as a fill or fit size is known only after layout. Spring
// the resolved size in layout if an app needs it.
_spring_size :: proc(box: ^Box) {
	for axis in 0 ..< 2 {
		size := &box.style.width if axis == 0 else &box.style.height
		if size.kind != .Points do continue

		spring := &box._motion[2 + axis]
		if !box._was_built_last_frame do spring^ = {value = size.value}
		spring.value, spring.velocity = _spring(spring.value, spring.velocity, size.value, box.style.motion)
		size.value = spring.value
	}
}

// Springs each box with a motion from its old place to its new one, and moves its children with it.
_spring_places :: proc(box: ^Box) {
	if box._key != 0 && box.style.motion != {} {
		target := _to_place_in_parent(box)
		x, y := &box._motion[0], &box._motion[1]
		if !box._was_built_last_frame {
			x^ = {value = target.x}
			y^ = {value = target.y}
		}
		x.value, x.velocity = _spring(x.value, x.velocity, target.x, box.style.motion)
		y.value, y.velocity = _spring(y.value, y.velocity, target.y, box.style.motion)
		delta := [2]f32{x.value, y.value} - target
		if delta != {} do _move_subtree(box, delta)
	}

	for child := box.first; child != nil; child = child.next do _spring_places(child)
}

// Measured in the parent's content, so a scroll or a parent that moves springs nothing.
_to_place_in_parent :: proc(box: ^Box) -> [2]f32 {
	place := [2]f32{box.rect.x, box.rect.y}
	parent := box.parent
	if parent == nil do return place

	place -= {parent.rect.x, parent.rect.y}
	if .Scroll in parent.style.flags do place[_axis_index(parent.style.axis)] += parent._placed_scroll

	return place
}

// Moves the box and every box in it. The clips follow the boxes that clip, as _place sets them.
_move_subtree :: proc(box: ^Box, delta: [2]f32) {
	box.rect += {delta.x, delta.y, delta.x, delta.y}
	child_clip := _intersect(box.clip, box.rect) if .Clip in box.style.flags else box.clip
	for child := box.first; child != nil; child = child.next {
		child.clip = child_clip
		_move_subtree(child, delta)
	}
}

_approach :: proc(value, target, rate: f32) -> f32 {
	if _preferences.is_reducing_motion do return target

	next := value + (target - value) * (1 - math.exp(-_state.frame_seconds * rate))

	if abs(target - next) < _SETTLED_FRACTION * max(1, abs(target)) do return target

	_state.is_animating = true

	return next
}

_end_frame :: proc() {
	_remove_unbuilt()
	window_clip := [4]f32{0, 0, _state.window_size.x, _state.window_size.y}
	for root in ([]^Box{_state.root, _state.overlay_root}) {
		_measure(root)
		_resolve(root)
		_place(root, {0, 0}, window_clip)
		_spring_places(root)
	}
	_finish_focus()
	_apply_mouse_to_boxes()
	clear(&_state.glass_areas)
	_draw(_state.root, _NO_CLIP, 1, {})
	_draw(_state.overlay_root, _NO_CLIP, 1, {})
	_draw_ghosts()
}

// Headless runs call it to start from the state of a new window.
_reset :: proc() {
	for _, ghost in _state.ghosts do delete(ghost.pushed)
	clear(&_state.ghosts)
	for _, box in _state.boxes do free(box)
	clear(&_state.boxes)
	clear(&_state.values)
	clear(&_state.parents)
	clear(&_state.focus_order)
	clear(&_state.group_focus)
	clear(&_state.hover_chain)
	kept := _state^
	_state^ = {
		boxes       = kept.boxes,
		values      = kept.values,
		parents     = kept.parents,
		focus_order = kept.focus_order,
		group_focus = kept.group_focus,
		hover_chain = kept.hover_chain,
		warned      = kept.warned,
		frame_index = kept.frame_index,
		mouse       = {-1, -1},
	}
	forced_state = .None
}

_remove_unbuilt :: proc() {
	for key, box in _state.boxes {
		if box._last_built_frame == _state.frame_index do continue

		free(box)
		delete_key(&_state.boxes, key)
	}

	for key, value in _state.values {
		if value._last_built_frame != _state.frame_index do delete_key(&_state.values, key)
	}
}

// Points to pixels on the window's screen.
to_pixels :: proc(points: f32) -> f32 {
	return points * _state.pixels_per_point
}

// Zoom scales the boxes. AppKit places views in the window's own points.
_to_window_points :: proc(rect: [4]f32) -> [4]f32 {
	return rect * _state.zoom
}

_warn :: proc(box: ^Box, format: string, args: ..any) {
	path := _to_box_path(box)
	// Hash the format, not the message, because the numbers change as the window resizes.
	key := hash.fnv64a(transmute([]u8)path) ~ hash.fnv64a(transmute([]u8)format)
	if _state.warned[key] do return

	_state.warned[key] = true
	fmt.eprintfln("thor: %s: %s", path, fmt.tprintf(format, ..args))
}

// "page > header > \"Title\"": each box's id, or its text when it has none, from the window down.
_to_box_path :: proc(box: ^Box) -> string {
	names: [dynamic]string
	names.allocator = context.temp_allocator

	for at := box; at != nil && at != _state.root; at = at.parent {
		name := at.id
		if name == "" {
			name = fmt.tprintf("\"%s\"", _to_short(at.text)) if at.text != "" else "_"
		}
		inject_at(&names, 0, name)
	}
	if len(names) == 0 do return "window"

	return strings.join(names[:], " > ", context.temp_allocator)
}

_to_short :: proc(text: string) -> string {
	count := 0
	for _, index in text {
		if count == 24 do return fmt.tprintf("%s…", text[:index])
		count += 1
	}
	return text
}
