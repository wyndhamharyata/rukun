package platform

import "base:intrinsics"
import "core:strings"
import NS "core:sys/darwin/Foundation"

Appearance :: enum {
	// Follows the appearance set in System Settings.
	System,
	Dark,
	Light,
}

@(objc_class = "NSAppearance")
_NS_Appearance :: struct {
	using _: NS.Object,
}

@(objc_class = "NSColorSpace")
_NS_Color_Space :: struct {
	using _: NS.Object,
}

@(objc_class = "NSDistributedNotificationCenter")
_NS_Distributed_Center :: struct {
	using _: NS.Object,
}

// Sets the look of the menus, the title bar and the input method's windows. System follows macOS.
set_appearance :: proc(appearance: Appearance) {
	if _headless.is_on do return

	look: ^NS.Object
	switch appearance {
	case .System:
	case .Dark:
		look = objc_send(^NS.Object, _NS_Appearance, "appearanceNamed:", NS.AT("NSAppearanceNameDarkAqua"))
	case .Light:
		look = objc_send(^NS.Object, _NS_Appearance, "appearanceNamed:", NS.AT("NSAppearanceNameAqua"))
	}
	objc_send(nil, _state.app, "setAppearance:", look)
}

is_dark_appearance :: proc() -> bool {
	if _headless.is_on do return _headless.is_dark

	look := objc_send(^NS.Object, _state.app, "effectiveAppearance")
	name := objc_send(^NS.String, look, "name")->odinString()

	return strings.contains(name, "Dark")
}

// The accent colour chosen in System Settings, in the app's appearance.
read_accent_color :: proc() -> [4]f32 {
	if _headless.is_on do return HEADLESS_ACCENT

	// The accent has a light and a dark shade; the current drawing appearance picks one.
	objc_send(nil, _NS_Appearance, "setCurrentAppearance:", objc_send(^NS.Object, _state.app, "effectiveAppearance"))
	accent := objc_send(^NS.Color, NS.Color, "controlAccentColor")
	srgb := objc_send(^NS.Object, _NS_Color_Space, "sRGBColorSpace")
	color := objc_send(^NS.Color, accent, "colorUsingColorSpace:", srgb)

	return {
		f32(objc_send(NS.Float, color, "redComponent")),
		f32(objc_send(NS.Float, color, "greenComponent")),
		f32(objc_send(NS.Float, color, "blueComponent")),
		f32(objc_send(NS.Float, color, "alphaComponent")),
	}
}

// macOS posts these when the appearance or the accent changes in System Settings.
_watch_appearance :: proc() {
	selector := intrinsics.objc_find_selector("appearanceChanged:")
	shared := objc_send(^NS.Object, _NS_Distributed_Center, "defaultCenter")
	objc_send(nil, shared, "addObserver:selector:name:object:", _state.target, selector, NS.AT("AppleInterfaceThemeChangedNotification"), rawptr(nil))
	local := objc_send(^NS.Object, NS.NotificationCenter, "defaultCenter")
	objc_send(nil, local, "addObserver:selector:name:object:", _state.target, selector, NS.AT("NSSystemColorsDidChangeNotification"), rawptr(nil))
}
