package platform

import NS "core:sys/darwin/Foundation"

Glass :: enum {
	None,
	Regular,
	// More transparent than Regular.
	Clear,
}

// A glass box's rect in window points from the top left; tint is its background.
Glass_Area :: struct {
	rect:          [4]f32,
	corner_radius: f32,
	glass:         Glass,
	tint:          [4]f32,
}

@(objc_class = "NSGlassEffectView")
_NS_Glass_View :: struct {
	using _: NS.View,
}

@(objc_class = "NSGlassEffectContainerView")
_NS_Glass_Container :: struct {
	using _: NS.View,
}

_Window_Glass :: struct {
	areas:     [dynamic]Glass_Area,
	// It merges glass views that touch, as the system's do.
	container: ^NS.View,
	views:     [dynamic]^NS.View,
	// The last set_background color, which the layer shows while no glass is open.
	background: [4]f32,
}

// app calls it after each frame with the frame's glass areas. Views change only on a change.
set_glass :: proc(window: ^Native_Window, areas: []Glass_Area) {
	if _headless.is_on || window.ns_window == nil do return

	state := &window.glass
	if len(areas) == len(state.areas) {
		is_same := true
		for area, index in areas do is_same &&= area == state.areas[index]
		if is_same do return
	}

	had_glass := len(state.areas) > 0
	clear(&state.areas)
	append(&state.areas, ..areas)

	if state.container == nil && len(areas) > 0 {
		content := objc_send(^NS.View, window.ns_window, "contentView")
		bounds := objc_send(NS.Rect, content, "bounds")
		state.container = objc_send(^NS.View, objc_send(^NS.View, _NS_Glass_Container, "alloc"), "initWithFrame:", bounds)
		objc_send(nil, state.container, "setAutoresizingMask:", NS.UInteger(SIZE_WITH_SUPERVIEW))
		inside := objc_send(^NS.View, objc_send(^NS.View, NS.View, "alloc"), "initWithFrame:", bounds)
		objc_send(nil, inside, "setAutoresizingMask:", NS.UInteger(SIZE_WITH_SUPERVIEW))
		objc_send(nil, state.container, "setContentView:", inside)
		inside->release()
		WINDOW_BELOW :: -1
		objc_send(nil, content, "addSubview:positioned:relativeTo:", state.container, NS.Integer(WINDOW_BELOW), window.view)
	}

	for len(state.views) > len(areas) {
		view := pop(&state.views)
		objc_send(nil, view, "removeFromSuperview")
		view->release()
	}
	for len(state.views) < len(areas) {
		view := objc_send(^NS.View, objc_send(^NS.View, _NS_Glass_View, "alloc"), "initWithFrame:", NS.Rect{})
		objc_send(nil, objc_send(^NS.View, state.container, "contentView"), "addSubview:", view)
		append(&state.views, view)
	}

	height := f64(window.size_points.y)
	for area, index in areas {
		view := state.views[index]
		r := area.rect
		frame := NS.Rect{{NS.Float(r.x), NS.Float(height - f64(r.w))}, {NS.Float(r.z - r.x), NS.Float(r.w - r.y)}}
		objc_send(nil, view, "setFrame:", frame)
		objc_send(nil, view, "setCornerRadius:", NS.Float(area.corner_radius))
		objc_send(nil, view, "setStyle:", NS.Integer(1 if area.glass == .Clear else 0))
		tint: ^NS.Color = nil
		if area.tint.a > 0 do tint = _to_ns_color(area.tint)
		objc_send(nil, view, "setTintColor:", tint)
	}

	// Glass shows the desktop only through a window and a layer with nothing painted behind.
	has_glass := len(areas) > 0
	if has_glass != had_glass {
		is_see_through := has_glass || window.blur_view != nil
		window.ns_window->setOpaque(!is_see_through)
		background := objc_send(^NS.Color, NS.Color, "blackColor")
		if is_see_through do background = objc_send(^NS.Color, NS.Color, "clearColor")
		window.ns_window->setBackgroundColor(background)
		_show_background(window)
	}
}

_show_background :: proc(window: ^Native_Window) {
	color: rawptr
	if len(window.glass.areas) == 0 do color = objc_send(rawptr, _to_ns_color(window.glass.background), "CGColor")
	objc_send(nil, window.layer, "setBackgroundColor:", color)
}

_to_ns_color :: proc(color: [4]f32) -> ^NS.Color {
	return objc_send(
		^NS.Color,
		NS.Color,
		"colorWithSRGBRed:green:blue:alpha:",
		NS.Float(color.r),
		NS.Float(color.g),
		NS.Float(color.b),
		NS.Float(color.a),
	)
}

_release_glass :: proc(window: ^Native_Window) {
	state := &window.glass
	for view in state.views do view->release()
	if state.container != nil do state.container->release()
	delete(state.views)
	delete(state.areas)
	state^ = {}
}
