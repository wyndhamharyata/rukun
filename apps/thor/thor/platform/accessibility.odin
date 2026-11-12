package platform

import "base:runtime"
import "core:hash"
import NS "core:sys/darwin/Foundation"

foreign import appkit "system:AppKit.framework"

@(default_calling_convention = "c")
foreign appkit {
	@(link_name = "NSAccessibilityPostNotification")
	_post_accessibility :: proc(element: rawptr, notification: ^NS.String) ---
	@(link_name = "NSAccessibilityPostNotificationWithUserInfo")
	_post_accessibility_with_info :: proc(element: rawptr, notification: ^NS.String, user_info: ^NS.Object) ---
}

// What a box is to a person, set by the kit component that built it. A box with text and no role
// counts as Text.
Role :: enum {
	None,
	Button,
	Checkbox,
	Toggle,
	Text_Field,
	Menu_Item,
	Row,
	Text,
	Image,
	Popover,
	Toast,
	Slider,
	Radio,
	Tab,
	Pop_Up,
	Progress,
	Tooltip,
	Dialog,
	Splitter,
	Scroll_Area,
}

// One element VoiceOver reads, in build order. parent is its parent's index, or -1.
Accessibility_Node :: struct {
	key:         u64,
	parent:      int,
	role:        Role,
	label:       string,
	value:       string,
	is_on:       bool,
	is_disabled: bool,
	// In the window's points, measured from its top left.
	rect:        [4]f32,
}

_Accessibility :: struct {
	// An assistive app asked for the elements, so each frame updates them from then on.
	is_wanted: bool,
	elements:  map[u64]^NS.Object,
	// A hash of what each element last showed, so a change posts a notification.
	shown:     map[u64]u64,
	// Every element in build order with its screen rect, for hit testing.
	placed:    [dynamic]_Placed_Element,
	top:       ^NS.Array,
	focused:   ^NS.Object,
	layout:    u64,
	// The box behind each element, so an action reaches it.
	info:      map[^NS.Object]_Element_Info,
}

_Element_Info :: struct {
	key:  u64,
	role: Role,
}

_Placed_Element :: struct {
	element: ^NS.Object,
	rect:    NS.Rect,
}

@(objc_class = "NSAccessibilityElement")
_NS_Accessibility_Element :: struct {
	using _: NS.Object,
}

// thor's elements. They pass VoiceOver's actions to ui as Accessibility_Action events.
@(objc_class = "ThorAccessibilityElement", objc_superclass = _NS_Accessibility_Element, objc_implement)
_Thor_Element :: struct {
	using _: _NS_Accessibility_Element,
}

_PRESSED :: bit_set[Role]{.Button, .Checkbox, .Toggle, .Menu_Item, .Row, .Radio, .Tab, .Pop_Up}
_STEPPED :: bit_set[Role]{.Slider, .Splitter}

// Each role offers only these actions, so VoiceOver never announces a press on text.
_ACTION_NAMES := [?]struct {
	name:  string,
	kind:  Accessibility_Action_Kind,
	roles: bit_set[Role],
} {
	{"AXPress", .Press, _PRESSED},
	{"AXIncrement", .Increment, _STEPPED},
	{"AXDecrement", .Decrement, _STEPPED},
	{"AXShowMenu", .Show_Menu, _PRESSED + _STEPPED + {.Text_Field, .Image}},
	{"AXScrollUpByPage", .Scroll_Page_Back, {.Scroll_Area}},
	{"AXScrollDownByPage", .Scroll_Page_Forward, {.Scroll_Area}},
	{"AXScrollLeftByPage", .Scroll_Page_Back, {.Scroll_Area}},
	{"AXScrollRightByPage", .Scroll_Page_Forward, {.Scroll_Area}},
}

// The page scrolls are not in AppKit's NSAccessibility protocol, so every action goes through
// the older pair of methods, which AppKit still asks first.
@(objc_type = _Thor_Element, objc_implement, objc_name = "accessibilityActionNames")
_Thor_Element_accessibilityActionNames :: proc "c" (self: ^_Thor_Element) -> ^NS.Array {
	context = runtime.default_context()
	_, info := _find_element(self)
	names := make([dynamic]^NS.Object, context.temp_allocator)
	for action in _ACTION_NAMES {
		if info.role in action.roles do append(&names, _to_ns_string(action.name))
	}

	return _to_ns_array(names[:])
}

@(objc_type = _Thor_Element, objc_implement, objc_name = "accessibilityPerformAction", objc_selector = "accessibilityPerformAction:")
_Thor_Element_accessibilityPerformAction :: proc "c" (self: ^_Thor_Element, name: ^NS.String) {
	context = runtime.default_context()
	_, info := _find_element(self)
	for action in _ACTION_NAMES {
		if info.role in action.roles && action.name == name->odinString() do _queue_action(self, action.kind)
	}
}

// ui's focus is the truth, so the getter reads it and the setter only asks ui to move it.
@(objc_type = _Thor_Element, objc_implement, objc_name = "isAccessibilityFocused")
_Thor_Element_isAccessibilityFocused :: proc "c" (self: ^_Thor_Element) -> NS.BOOL {
	window, _ := _find_element(self)

	return window != nil && window.accessibility.focused == self
}

@(objc_type = _Thor_Element, objc_implement, objc_name = "setAccessibilityFocused", objc_selector = "setAccessibilityFocused:")
_Thor_Element_setAccessibilityFocused :: proc "c" (self: ^_Thor_Element, is_focused: NS.BOOL) {
	if is_focused do _queue_action(self, .Focus)
}

_find_element :: proc "contextless" (element: ^_Thor_Element) -> (^Native_Window, _Element_Info) {
	for window in _state.windows {
		if window.is_closed do continue
		if info, ok := window.accessibility.info[element]; ok do return window, info
	}

	return nil, {}
}

_queue_action :: proc "contextless" (element: ^_Thor_Element, kind: Accessibility_Action_Kind) -> NS.BOOL {
	context = runtime.default_context()
	window, info := _find_element(element)
	if window == nil do return false

	append(&window.events, Accessibility_Action{info.key, kind})
	_request_frame_of(window)

	return true
}

// The view the window draws in; AppKit asks it for the elements VoiceOver reads.
@(objc_class = "ThorMetalView", objc_superclass = NS.View, objc_implement)
_Metal_View :: struct {
	using _: NS.View,
}

_find_by_view :: proc "contextless" (view: rawptr) -> ^Native_Window {
	for window in _state.windows {
		if (rawptr(window.view) == view || rawptr(window.input_view) == view) && !window.is_closed do return window
	}

	return nil
}

@(objc_type = _Metal_View, objc_implement, objc_name = "isAccessibilityElement")
_Metal_View_isAccessibilityElement :: proc "c" (self: ^_Metal_View) -> NS.BOOL {
	return false
}

@(objc_type = _Metal_View, objc_implement, objc_name = "accessibilityChildren")
_Metal_View_accessibilityChildren :: proc "c" (self: ^_Metal_View) -> ^NS.Array {
	window := _find_by_view(self)
	if window == nil do return nil

	// The first question starts the updates; the elements arrive with the next frame.
	if !window.accessibility.is_wanted {
		window.accessibility.is_wanted = true
		_request_frame_of(window)
	}

	return window.accessibility.top
}

@(objc_type = _Metal_View, objc_implement, objc_name = "accessibilityHitTest", objc_selector = "accessibilityHitTest:")
_Metal_View_accessibilityHitTest :: proc "c" (self: ^_Metal_View, point: NS.Point) -> ^NS.Object {
	window := _find_by_view(self)
	if window == nil do return self

	// Later elements are deeper or on top, so the last one under the point wins.
	found: ^NS.Object = self
	for placed in window.accessibility.placed {
		r := placed.rect
		if point.x >= r.origin.x && point.x < r.origin.x + r.size.width && point.y >= r.origin.y && point.y < r.origin.y + r.size.height {
			found = placed.element
		}
	}

	return found
}

@(objc_type = _Metal_View, objc_implement, objc_name = "accessibilityFocusedUIElement")
_Metal_View_accessibilityFocusedUIElement :: proc "c" (self: ^_Metal_View) -> ^NS.Object {
	return _to_focused_element(self)
}

_to_focused_element :: proc "contextless" (view: ^NS.View) -> ^NS.Object {
	window := _find_by_view(view)
	if window == nil || window.accessibility.focused == nil do return view

	return window.accessibility.focused
}

// app calls it after each frame once an assistive app has asked. focused_key is ui's focused box.
update_accessibility :: proc(window: ^Native_Window, nodes: []Accessibility_Node, focused_key: u64) {
	if _headless.is_on || window.ns_window == nil do return

	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->drain()
	state := &window.accessibility
	elements := make([]^NS.Object, len(nodes), context.temp_allocator)
	children := make([][dynamic]^NS.Object, len(nodes), context.temp_allocator)
	top := make([dynamic]^NS.Object, context.temp_allocator)
	seen := make(map[u64]bool, len(nodes), context.temp_allocator)
	layout: u64 = 14695981039346656037
	focused: ^NS.Object
	clear(&state.placed)

	for node, index in nodes {
		element, has_element := state.elements[node.key]
		if !has_element {
			element = objc_send(^NS.Object, objc_send(^NS.Object, _Thor_Element, "alloc"), "init")
			state.elements[node.key] = element
		}
		state.info[element] = {node.key, node.role}
		elements[index] = element
		seen[node.key] = true

		look := _hash_node(node)
		was, was_shown := state.shown[node.key]
		if !was_shown || was != look {
			_describe_element(element, node)
			if was_shown do _post_accessibility(element, NS.AT("AXValueChanged"))
			if !was_shown && node.role == .Toast do _announce(node.label)
			state.shown[node.key] = look
		}

		rect := _to_screen_rect(window, node.rect)
		objc_send(nil, element, "setAccessibilityFrame:", rect)
		append(&state.placed, _Placed_Element{element, rect})
		if node.parent >= 0 {
			objc_send(nil, element, "setAccessibilityParent:", elements[node.parent])
			append(&children[node.parent], element)
		} else {
			objc_send(nil, element, "setAccessibilityParent:", window.view)
			append(&top, element)
		}
		if node.key == focused_key && focused_key != 0 do focused = element
		layout = (layout ~ node.key ~ u64(node.parent + 1)) * 1099511628211
	}

	for list, index in children {
		objc_send(nil, elements[index], "setAccessibilityChildren:", _to_ns_array(list[:]))
	}
	if state.top != nil do state.top->release()
	state.top = _to_ns_array(top[:])
	objc_send(nil, state.top, "retain")

	if focused != state.focused {
		state.focused = focused
		if focused != nil do _post_accessibility(focused, NS.AT("AXFocusedUIElementChanged"))
	}

	gone := make([dynamic]u64, context.temp_allocator)
	for key in state.elements {
		if !seen[key] do append(&gone, key)
	}
	for key in gone {
		element := state.elements[key]
		_post_accessibility(element, NS.AT("AXUIElementDestroyed"))
		delete_key(&state.info, element)
		element->release()
		delete_key(&state.elements, key)
		delete_key(&state.shown, key)
	}

	if layout != state.layout {
		state.layout = layout
		_post_accessibility(window.view, NS.AT("AXLayoutChanged"))
	}
}

_hash_node :: proc(node: Accessibility_Node) -> u64 {
	look := hash.fnv64a(transmute([]u8)node.label) ~ (hash.fnv64a(transmute([]u8)node.value) * 31)
	return look ~ u64(node.role) << 40 ~ u64(node.is_on) << 48 ~ u64(node.is_disabled) << 49
}

_describe_element :: proc(element: ^NS.Object, node: Accessibility_Node) {
	role, subrole := _to_appkit_role(node.role)
	objc_send(nil, element, "setAccessibilityRole:", role)
	objc_send(nil, element, "setAccessibilitySubrole:", subrole)
	objc_send(nil, element, "setAccessibilityEnabled:", NS.BOOL(!node.is_disabled))

	#partial switch node.role {
	case .Text, .Toast, .Tooltip:
		// VoiceOver reads a static text's value, not its label.
		objc_send(nil, element, "setAccessibilityLabel:", rawptr(nil))
		objc_send(nil, element, "setAccessibilityValue:", _to_ns_string(node.label))
	case .Checkbox, .Toggle, .Radio, .Tab:
		objc_send(nil, element, "setAccessibilityLabel:", _to_ns_string(node.label))
		objc_send(nil, element, "setAccessibilityValue:", objc_send(^NS.Object, NS.Number, "numberWithBool:", NS.BOOL(node.is_on)))
	case:
		objc_send(nil, element, "setAccessibilityLabel:", _to_ns_string(node.label))
		value: rawptr = _to_ns_string(node.value) if node.value != "" else nil
		objc_send(nil, element, "setAccessibilityValue:", value)
		objc_send(nil, element, "setAccessibilitySelected:", NS.BOOL(node.is_on))
	}
}

_to_appkit_role :: proc(role: Role) -> (^NS.String, ^NS.String) {
	switch role {
	case .None:
		return NS.AT("AXGroup"), nil
	case .Button:
		return NS.AT("AXButton"), nil
	case .Checkbox:
		return NS.AT("AXCheckBox"), nil
	case .Toggle:
		return NS.AT("AXCheckBox"), NS.AT("AXSwitch")
	case .Text_Field:
		return NS.AT("AXTextField"), nil
	case .Menu_Item:
		return NS.AT("AXMenuItem"), nil
	case .Row:
		return NS.AT("AXRow"), nil
	case .Text, .Toast:
		return NS.AT("AXStaticText"), nil
	case .Image:
		return NS.AT("AXImage"), nil
	case .Popover:
		return NS.AT("AXPopover"), nil
	case .Slider:
		return NS.AT("AXSlider"), nil
	case .Radio:
		return NS.AT("AXRadioButton"), nil
	case .Tab:
		return NS.AT("AXRadioButton"), NS.AT("AXTabButton")
	case .Pop_Up:
		return NS.AT("AXPopUpButton"), nil
	case .Progress:
		return NS.AT("AXProgressIndicator"), nil
	case .Tooltip:
		return NS.AT("AXHelpTag"), nil
	case .Dialog:
		return NS.AT("AXGroup"), NS.AT("AXDialog")
	case .Splitter:
		return NS.AT("AXSplitter"), nil
	case .Scroll_Area:
		return NS.AT("AXScrollArea"), nil
	}

	return NS.AT("AXGroup"), nil
}

// A toast announces its text once, the way macOS announces a notification.
_announce :: proc(text: string) {
	HIGH_PRIORITY :: 90
	values := [2]^NS.Object{_to_ns_string(text), objc_send(^NS.Object, NS.Number, "numberWithInt:", i32(HIGH_PRIORITY))}
	keys := [2]^NS.Object{NS.AT("AXAnnouncementKey"), NS.AT("AXPriorityKey")}
	info := objc_send(^NS.Object, NS.Dictionary, "dictionaryWithObjects:forKeys:count:", &values[0], &keys[0], NS.UInteger(2))
	_post_accessibility_with_info(_state.app, NS.AT("AXAnnouncementRequested"), info)
}

_to_ns_string :: proc(text: string) -> ^NS.Object {
	return objc_send(^NS.Object, NS.String.alloc()->initWithOdinString(text), "autorelease")
}

_to_ns_array :: proc(objects: []^NS.Object) -> ^NS.Array {
	if len(objects) == 0 do return objc_send(^NS.Array, NS.Array, "array")

	return objc_send(^NS.Array, NS.Array.alloc()->initWithObjects(raw_data(objects), NS.UInteger(len(objects))), "autorelease")
}

_to_screen_rect :: proc(window: ^Native_Window, rect: [4]f32) -> NS.Rect {
	height := f64(window.size_points.y)
	in_window := NS.Rect {
		{NS.Float(rect.x), NS.Float(height - f64(rect.w))},
		{NS.Float(rect.z - rect.x), NS.Float(rect.w - rect.y)},
	}

	return objc_send(NS.Rect, window.ns_window, "convertRectToScreen:", in_window)
}

_release_accessibility :: proc(window: ^Native_Window) {
	state := &window.accessibility
	for _, element in state.elements do element->release()
	if state.top != nil do state.top->release()
	delete(state.elements)
	delete(state.shown)
	delete(state.placed)
	delete(state.info)
	state^ = {}
}
