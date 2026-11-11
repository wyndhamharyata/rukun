package platform

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

@(objc_class = "NSVisualEffectView")
Visual_Effect_View :: struct {
	using _: NS.View,
}

@(objc_class = "CALayer")
Layer :: struct {
	using _: NS.Object,
}

@(objc_class = "ThorBlurView", objc_superclass = Visual_Effect_View, objc_implement)
Blur_View :: struct {
	using _: Visual_Effect_View,
}

set_background :: proc(color: [4]f32) {
	if _headless.is_on do return

	ns_color := objc_send(
		^NS.Color,
		NS.Color,
		"colorWithSRGBRed:green:blue:alpha:",
		NS.Float(color.r),
		NS.Float(color.g),
		NS.Float(color.b),
		NS.Float(color.a),
	)

	window := current_window()
	if window == nil do return

	objc_send(
		nil,
		window.layer,
		"setBackgroundColor:",
		objc_send(rawptr, ns_color, "CGColor"),
	)
}

_Objc_Super :: struct {
	receiver:    ^Blur_View,
	super_class: NS.Class,
}

// AppKit puts back its tint and saturation layers each time it updates the blur.
@(objc_type = Blur_View, objc_implement, objc_name = "updateLayer")
Blur_View_updateLayer :: proc "c" (self: ^Blur_View) {
	super := _Objc_Super{self, NS.Class(intrinsics.objc_find_class("NSVisualEffectView"))}
	objc_msgSendSuper(&super, NS.SEL(intrinsics.objc_find_selector("updateLayer")))
	_remove_layer_background(objc_send(^Layer, self, "layer"))
}

_remove_layer_background :: proc "c" (layer: ^Layer) {
	if layer == nil do return
	for window in _state.windows {
		if rawptr(layer) == rawptr(window.layer) do return
	}

	objc_send(nil, layer, "setBackgroundColor:", rawptr(nil))

	class_name := objc_send(^NS.String, layer, "className")

	// CAChameleonLayer tints the blur with the desktop colour.
	if objc_send(NS.BOOL, class_name, "isEqualToString:", NS.AT("CAChameleonLayer")) {
		objc_send(nil, layer, "setHidden:", NS.BOOL(true))
		return
	}

	filters := objc_send(^NS.Array, layer, "filters")

	if filters != nil {
		kept := NS.MutableArray.alloc()->init()

		for index in 0 ..< filters->count() {
			filter := filters->object(index)
			description := objc_send(^NS.String, filter, "description")

			// The blur raises saturation with a filter named "colorSaturate".
			if objc_send(NS.BOOL, description, "containsString:", NS.AT("colorSaturate")) do continue

			objc_send(nil, kept, "addObject:", filter)
		}

		objc_send(nil, layer, "setFilters:", kept)
		kept->release()
	}

	sublayers := objc_send(^NS.Array, layer, "sublayers")

	if sublayers == nil do return

	for index in 0 ..< sublayers->count() {
		_remove_layer_background(cast(^Layer)sublayers->object(index))
	}
}
