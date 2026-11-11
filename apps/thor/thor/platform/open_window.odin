package platform

import "../mac"
import "base:intrinsics"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"

TITLE_HIDDEN :: 1
MATERIAL_SELECTION :: 4
// NSVisualEffectStateActive keeps the blur visible when the window is not key.
BLUR_ALWAYS_ACTIVE :: 1
SIZE_WITH_SUPERVIEW :: 2 | 16
// NSWindowCollectionBehaviorTransient | IgnoresCycle, so Spaces, Mission Control and ⌘` skip it.
TRANSIENT_WINDOW :: (1 << 3) | (1 << 6)

// Joins every Space, floats over full-screen apps, and stays out of ⌘`.
PANEL_BEHAVIOR :: NS.WindowCollectionBehavior{.CanJoinAllSpaces, .FullScreenAuxiliary, .IgnoresCycle}

// NSTrackingMouseEnteredAndExited | MouseMoved | ActiveAlways | InVisibleRect.
// A window that is not key, such as a panel, still gets pointer events.
TRACKING_OPTIONS :: 0x01 | 0x02 | 0x80 | 0x200

@(objc_class = "NSTrackingArea")
_Tracking_Area :: struct {
	using _: NS.Object,
}

// The first call sets up the app. is_background makes an accessory app, which AeroSpace skips.
// Each later window opens a little below and right of the window in front.
open_window :: proc(
	title: string,
	size_points, min_size_points: [2]f32,
	on_frame: Frame_Proc,
	is_background: bool,
	is_blurred := false,
	// AppKit saves the frame under this name on each move or resize, and restores it next launch.
	frame_name := "",
	kind := Window_Kind.Normal,
) -> ^Native_Window {
	_state.odin_context = context
	window := new(Native_Window)
	window^ = {
		size_points = size_points,
		kind        = kind,
		on_frame    = on_frame,
	}
	if _headless.is_on {
		window.device = _headless.device
		window.pixels_per_point = _headless.scale
		append(&_state.windows, window)
		return window
	}

	if _state.app == nil {
		_state.is_background = is_background
		_state.app = NS.Application.sharedApplication()
		_state.app->setActivationPolicy(.Accessory if is_background else .Regular)
		// run reads events instead of NSApplication's run, so this sends finishLaunching itself.
		objc_send(nil, _state.app, "finishLaunching")
		_state.target = objc_send(^_Target, objc_send(^_Target, _Target, "alloc"), "init")
		_watch_appearance()
	}
	in_front := _find_key_window()

	content_rect := NS.Rect{{0, 0}, {NS.Float(size_points.x), NS.Float(size_points.y)}}
	window.ns_window = _make_ns_window(title, content_rect, min_size_points, is_blurred, kind)
	content := objc_send(
		^NS.View,
		objc_send(^NS.View, NS.View, "alloc"),
		"initWithFrame:",
		content_rect,
	)
	objc_send(nil, content, "setAutoresizingMask:", NS.UInteger(SIZE_WITH_SUPERVIEW))
	window.ns_window->setContentView(content)

	if is_blurred {
		window.blur_view = _make_blur_view(content_rect)
		content->addSubview(window.blur_view)
	}

	window.device = MTL.CreateSystemDefaultDevice()
	window.layer = _make_metal_layer(window.device)
	window.view = _make_metal_view(window.layer, content_rect)
	content->addSubview(window.view)
	tracking := objc_send(^_Tracking_Area, _Tracking_Area, "alloc")
	tracking = objc_send(^_Tracking_Area, tracking, "initWithRect:options:owner:userInfo:", NS.Rect{}, NS.UInteger(TRACKING_OPTIONS), window.view, rawptr(nil))
	objc_send(nil, window.view, "addTrackingArea:", tracking)
	objc_send(nil, tracking, "release")

	window.input_view = _make_input_view()
	content->addSubview(window.input_view)

	// Restores the frame after the views exist, so their autoresizing follows it.
	if frame_name != "" {
		ns_name := NS.String.alloc()->initWithOdinString(frame_name)
		defer ns_name->release()
		window.is_frame_restored = bool(objc_send(NS.BOOL, window.ns_window, "setFrameUsingName:", ns_name))
		objc_send(NS.BOOL, window.ns_window, "setFrameAutosaveName:", ns_name)
	}

	window.target = objc_send(^_Target, objc_send(^_Target, _Target, "alloc"), "init")
	window.ns_window->setDelegate(cast(^NS.WindowDelegate)window.target)
	window.display_link = _make_display_link(window.layer, window.target)
	append(&_state.windows, window)

	_apply_window_size(window)
	_show_window(window, in_front, is_background)

	return window
}

_make_ns_window :: proc(
	title: string,
	content_rect: NS.Rect,
	min_size_points: [2]f32,
	is_blurred: bool,
	kind: Window_Kind,
) -> ^NS.Window {
	ns_window: ^NS.Window
	ns_title := NS.String.alloc()->initWithOdinString(title)
	defer ns_title->release()

	switch kind {
	case .Normal:
		style := NS.WindowStyleMask{.Titled, .Closable, .Miniaturizable, .Resizable, .FullSizeContentView}
		ns_window = NS.Window.alloc()->initWithContentRect(content_rect, style, .Buffered, false)
		ns_window->setTitle(ns_title)
		ns_window->setTitlebarAppearsTransparent(true)
		objc_send(nil, ns_window, "setTitleVisibility:", NS.Integer(TITLE_HIDDEN))
	case .Panel:
		// A utility panel's small title bar, which sits over the content instead of on it.
		style := NS.WindowStyleMask{.Titled, .Closable, .Resizable, .UtilityWindow, .NonactivatingPanel}
		ns_window = objc_send(^NS.Window, NS.Panel, "alloc")->initWithContentRect(content_rect, style, .Buffered, false)
		ns_window->setTitle(ns_title)
		objc_send(nil, ns_window, "setFloatingPanel:", NS.BOOL(true))
		objc_send(nil, ns_window, "setHidesOnDeactivate:", NS.BOOL(false))
		objc_send(nil, ns_window, "setBecomesKeyOnlyIfNeeded:", NS.BOOL(true))
		objc_send(nil, ns_window, "setCollectionBehavior:", PANEL_BEHAVIOR)
	}

	objc_send(nil, ns_window, "setReleasedWhenClosed:", NS.BOOL(false))
	objc_send(nil, ns_window, "setAcceptsMouseMovedEvents:", NS.BOOL(true))
	objc_send(
		nil,
		ns_window,
		"setContentMinSize:",
		NS.Size{NS.Float(min_size_points.x), NS.Float(min_size_points.y)},
	)

	// An opaque window lets the window server skip the blur and the desktop behind it.
	ns_window->setOpaque(!is_blurred)
	background := objc_send(^NS.Color, NS.Color, "blackColor")
	if is_blurred do background = objc_send(^NS.Color, NS.Color, "clearColor")
	ns_window->setBackgroundColor(background)

	return ns_window
}

_make_blur_view :: proc(content_rect: NS.Rect) -> ^Blur_View {
	blur := objc_send(
		^Blur_View,
		objc_send(^Blur_View, Blur_View, "alloc"),
		"initWithFrame:",
		content_rect,
	)

	objc_send(nil, blur, "setMaterial:", NS.Integer(MATERIAL_SELECTION))
	objc_send(nil, blur, "setState:", NS.Integer(BLUR_ALWAYS_ACTIVE))
	objc_send(nil, blur, "setAutoresizingMask:", NS.UInteger(SIZE_WITH_SUPERVIEW))

	return blur
}

_make_metal_layer :: proc(device: ^MTL.Device) -> ^CA.MetalLayer {
	layer := CA.MetalLayer.layer()
	layer->setDevice(device)
	layer->setPixelFormat(.BGRA8Unorm)
	layer->setOpaque(false)
	layer->setFramebufferOnly(true)

	// render converts thor's sRGB colors to Display P3, so P3 colors show at full strength.
	p3 := mac.CGColorSpaceCreateWithName(mac.kCGColorSpaceDisplayP3)
	defer mac.CGColorSpaceRelease(p3)
	objc_send(nil, layer, "setColorspace:", rawptr(p3))

	return layer
}

_make_metal_view :: proc(layer: ^CA.MetalLayer, content_rect: NS.Rect) -> ^NS.View {
	view := objc_send(
		^NS.View,
		objc_send(^NS.View, _Metal_View, "alloc"),
		"initWithFrame:",
		content_rect,
	)

	view->setLayer(layer)
	view->setWantsLayer(true)
	objc_send(nil, view, "setAutoresizingMask:", NS.UInteger(SIZE_WITH_SUPERVIEW))

	return view
}

// AppKit gives a view an input method only when its class declares NSTextInputClient.
_make_input_view :: proc() -> ^NS.View {
	input_class := intrinsics.objc_find_class("ThorInputView")
	class_addProtocol(rawptr(input_class), objc_getProtocol("NSTextInputClient"))

	return objc_send(
		^NS.View,
		objc_send(^Input_View, Input_View, "alloc"),
		"initWithFrame:",
		NS.Rect{{0, 0}, {1, 1}},
	)
}

_make_display_link :: proc(layer: ^CA.MetalLayer, target: ^_Target) -> ^Display_Link {
	link := objc_send(
		^Display_Link,
		objc_send(^Display_Link, Display_Link, "alloc"),
		"initWithMetalLayer:",
		layer,
	)

	objc_send(nil, link, "setDelegate:", target)
	objc_send(nil, link, "setPreferredFrameLatency:", f32(1))
	objc_send(nil, link, "addToRunLoop:forMode:", NS.RunLoop.mainRunLoop(), NS.RunLoopCommonModes)
	objc_send(nil, link, "setPaused:", NS.BOOL(true))

	return link
}

_show_window :: proc(window: ^Native_Window, in_front: ^Native_Window, is_background: bool) {
	if !window.is_frame_restored {
		if in_front == nil || in_front.ns_window == nil {
			window.ns_window->center()
		} else {
			frame := in_front.ns_window->frame()
			top_left := NS.Point{frame.origin.x, frame.origin.y + frame.size.height}
			// The first call returns the next cascade position; the second moves the window there.
			next := objc_send(NS.Point, window.ns_window, "cascadeTopLeftFromPoint:", top_left)
			objc_send(NS.Point, window.ns_window, "cascadeTopLeftFromPoint:", next)
		}
	}

	switch {
	case window.kind == .Panel:
		// Shows the panel without bringing its app to the front.
		objc_send(nil, window.ns_window, "orderFrontRegardless")
	case is_background:
		objc_send(nil, window.ns_window, "setCollectionBehavior:", NS.UInteger(TRANSIENT_WINDOW))
		objc_send(nil, window.ns_window, "orderBack:", rawptr(nil))
	case:
		window.ns_window->makeKeyAndOrderFront(nil)
		_state.app->activate()
	}

	_request_frame_of(window)
}

_apply_window_size :: proc(window: ^Native_Window) -> bool {
	if _headless.is_on do return false

	bounds := window.view->bounds()
	pixels_per_point := f32(window.ns_window->backingScaleFactor())

	window.size_points = {f32(bounds.size.width), f32(bounds.size.height)}
	window.pixels_per_point = pixels_per_point
	size_pixels := NS.Size {
		bounds.size.width * NS.Float(pixels_per_point),
		bounds.size.height * NS.Float(pixels_per_point),
	}
	is_resized := window.layer->drawableSize() != size_pixels

	window.layer->setDrawableSize(size_pixels)
	objc_send(nil, window.layer, "setContentsScale:", NS.Float(pixels_per_point))

	return is_resized
}
