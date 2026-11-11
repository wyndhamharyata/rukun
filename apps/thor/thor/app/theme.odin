package app

import "../kit"
import "../platform"
import "../ui"

_theme: struct {
	is_applied: bool,
	appearance: platform.Appearance,
	is_dark:    bool,
	primary:    [4]f32,
}

// Acts only on a change, so a color the app sets each frame, such as onlymuse's primary, stays.
_apply_theme :: proc(events: []platform.Event) {
	is_stale := !_theme.is_applied || kit.appearance != _theme.appearance
	for event in events {
		if _, ok := event.(platform.Appearance_Change); ok do is_stale = true
	}
	if !is_stale do return

	if !_theme.is_applied || kit.appearance != _theme.appearance do platform.set_appearance(kit.appearance)
	is_dark := kit.appearance == .Dark || (kit.appearance == .System && platform.is_dark_appearance())
	colors := _to_theme_colors(is_dark, platform.read_accent_color())
	is_same := _theme.is_applied && is_dark == _theme.is_dark && colors.primary == _theme.primary
	_theme = {true, kit.appearance, is_dark, colors.primary}
	if is_same do return

	// Each window sets its background from it as its next frame begins.
	kit.colors = colors
	ui.request_frame()
}

_to_theme_colors :: proc(is_dark: bool, system_accent: [4]f32) -> kit.Colors {
	colors := kit.dark_colors if is_dark else kit.light_colors
	if colors.primary.a == 0 do colors.primary = system_accent

	return colors
}
