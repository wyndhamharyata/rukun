package main

import "core:fmt"
import "thor/kit"
import "thor/ui"

build_sidebar :: proc() {
	style := ui.Style {
		width      = ui.points(220),
		padding    = {12, 52, 12, 12},
		height     = ui.fill(),
		gap        = 2,
		background = kit.to_color(SIDEBAR_COLOR),
		flags      = {.Scroll, .Clip},
	}

	if ui.col("sidebar", style) {
		if kit.list_row("tasks", &state.section, "Tasks", .Nav) {
			if ui.here().is_activated do state.note = ""
		}

		gap(4)
		kit.divider()
		gap(4)

		for space in rukun.spaces {
			label := fmt.tprintf("#%s", space.name)
			if kit.list_row(space.id, &state.section, label, .Nav) {
				if ui.here().is_activated do state.note = ""
			}
		}
	}
}
