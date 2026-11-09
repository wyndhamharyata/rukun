package main

import "core:fmt"
import "thor/kit"
import "thor/ui"

build_sidebar :: proc() {
	style := ui.Style {
		width      = ui.points(220),
		padding    = {12, 52, 12, 12},
		gap        = 2,
		background = kit.to_color(SIDEBAR_COLOR),
	}

	if ui.scroll("sidebar", style) {
		if kit.nav_row("tasks", "Tasks", &state.section) do state.note = ""

		gap(4)
		kit.divider()
		gap(4)

		for space in rukun.spaces {
			label := fmt.tprintf("#%s", space.name)
			if kit.nav_row(space.id, label, &state.section) do state.note = ""
		}
	}
}
