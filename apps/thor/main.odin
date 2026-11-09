package main

import "core:encoding/json"
import "thor/app"
import "thor/kit"
import "thor/ui"

Album :: struct {
	id, title, artist: string,
	year:              int,
	cover:             string,
}

Song :: struct {
	id, title, artist, album, album_id: string,
	track, seconds:                     int,
}

SIDEBAR_WIDTH :: 220

PLAYER_HEIGHT :: 72

WINDOW_COLOR :: 0x121214ff

SIDEBAR_COLOR :: 0x161618ff

BAR_COLOR :: 0x1b1b1eff

library: struct {
	albums: []Album,
	songs:  []Song,
}

main :: proc() {
	error := json.unmarshal_string(#load("../../data/library.json", string), &library)
	assert(error == nil, "library.json does not parse")

	start_songs_page()
	app.run({title = "Library", size = {1100, 720}, min_size = {900, 600}}, frame)
}

// The sidebar and the player bar are empty boxes until phase 4 builds them.
frame :: proc() {
	root := ui.current_parent()
	root.style.axis = .Y
	root.style.background = kit.to_color(WINDOW_COLOR)

	top := ui.box("top", {width = ui.fill(), height = ui.fill(), axis = .X})

	if ui.scope(top) {
		ui.box(
			"sidebar",
			{
				width = ui.points(SIDEBAR_WIDTH),
				height = ui.fill(),
				background = kit.to_color(SIDEBAR_COLOR),
			},
		)
		build_songs_page()
	}

	ui.box(
		"player bar",
		{
			width = ui.fill(),
			height = ui.points(PLAYER_HEIGHT),
			background = kit.to_color(BAR_COLOR),
		},
	)
}
