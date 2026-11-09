package main

import "core:fmt"
import "core:strings"
import "thor/font"
import "thor/kit"
import "thor/platform"
import "thor/ui"

ROW_HEIGHT :: 34

EXTRA_ROWS :: 2

SELECTED_ROW_COLOR :: 0x0a84ff2e

songs_page: struct {
	search:   kit.Text_Field,
	// Each song's title and artist in lower case, for the search.
	lowered:  [][2]string,
	shown:    [dynamic]int,
	selected: string,
}

start_songs_page :: proc() {
	kit.register_text_field(&songs_page.search)
	songs_page.lowered = make([][2]string, len(library.songs))

	for song, index in library.songs {
		songs_page.lowered[index] = {strings.to_lower(song.title), strings.to_lower(song.artist)}
	}

	filter_songs("")
}

filter_songs :: proc(query: string) {
	clear(&songs_page.shown)
	needle := strings.to_lower(query, context.temp_allocator)

	for lowered, index in songs_page.lowered {
		is_match := strings.contains(lowered[0], needle) || strings.contains(lowered[1], needle)
		if is_match do append(&songs_page.shown, index)
	}
}

build_songs_page :: proc() {
	field := &songs_page.search
	kit.apply_text_events(platform.list_events())
	if field.is_changed do filter_songs(kit.to_field_text(field))

	page := ui.box(
		"songs",
		{width = ui.fill(), height = ui.fill(), axis = .Y, padding = {24, 40, 24, 0}},
	)

	if ui.scope(page) {
		header := ui.box(
			"header",
			{width = ui.fill(), height = ui.points(36), axis = .X, align = .Center},
		)

		if ui.scope(header) {
			cell("Songs", ui.fill(), kit.colors.text, font_size = 28, weight = .Bold)

			search := ui.box("search", {width = ui.points(240), height = ui.points(28)})
			if ui.scope(search) do kit.build_text_field(field, "field", "Search", "", height = 28)
		}

		ui.box("", {width = ui.fill(), height = ui.points(16)})

		columns := ui.box(
			"columns",
			{
				width = ui.fill(),
				height = ui.points(27),
				axis = .X,
				align = .Center,
				gap = 16,
				padding = {12, 0, 12, 0},
			},
		)

		if ui.scope(columns) {
			cell("Title", ui.fill(4), kit.colors.faint, font_size = 12, weight = .Semibold)
			cell("Artist", ui.fill(3), kit.colors.faint, font_size = 12, weight = .Semibold)
			cell("Album", ui.fill(3), kit.colors.faint, font_size = 12, weight = .Semibold)
			cell("Time", ui.points(56), kit.colors.faint, .End, 12, .Semibold)
		}

		// ui draws a border on every side, so the bottom border is a box of its own.
		ui.box("", {width = ui.fill(), height = ui.points(1), background = kit.colors.line})

		list := ui.box(
			"list",
			{
				width = ui.fill(),
				height = ui.fill(),
				axis = .Y,
				padding = {0, 0, 0, 12},
				flags = {.Scroll, .Clip},
			},
		)

		if field.is_changed do ui.set_scroll(list, 0)
		// The list's height comes from the last frame. The first frame has none, so ask for one more.
		if list.size.y == 0 do platform.request_frame()
		if ui.scope(list) do build_song_rows(list)
	}

	kit.finish_text_fields()
}

build_song_rows :: proc(list: ^ui.Box) {
	shown := songs_page.shown[:]

	if len(shown) == 0 {
		empty := ui.box(
			"",
			{width = ui.fill(), height = ui.points(list.size.y - 12), axis = .X, align = .Center},
		)
		if ui.scope(empty) do cell("No songs match", ui.fill(), kit.colors.dim, .Center)
		return
	}

	first := max(0, int(list.scroll / ROW_HEIGHT) - EXTRA_ROWS)
	last := min(len(shown) - 1, int((list.scroll + list.size.y) / ROW_HEIGHT) + EXTRA_ROWS)

	if first > 0 do ui.box("", {width = ui.fill(), height = ui.points(f32(first) * ROW_HEIGHT)})

	for index in first ..= last {
		song := library.songs[shown[index]]
		if song_row(song) do songs_page.selected = song.id
	}

	if last < len(shown) - 1 {
		ui.box(
			"",
			{width = ui.fill(), height = ui.points(f32(len(shown) - 1 - last) * ROW_HEIGHT)},
		)
	}
}

song_row :: proc(song: Song) -> bool {
	is_selected := song.id == songs_page.selected
	selected_color := kit.to_color(SELECTED_ROW_COLOR)

	row := ui.box(
		song.id,
		{
			width = ui.fill(),
			height = ui.points(ROW_HEIGHT),
			axis = .X,
			align = .Center,
			gap = 16,
			padding = {12, 0, 12, 0},
			corner_radius = 6,
			background = selected_color if is_selected else {},
			hover_background = selected_color if is_selected else kit.colors.hover,
			flags = {.Clickable},
		},
	)

	if ui.scope(row) {
		cell(song.title, ui.fill(4), kit.colors.text)
		cell(song.artist, ui.fill(3), kit.colors.dim)
		cell(song.album, ui.fill(3), kit.colors.dim)
		time := fmt.tprintf("%d:%02d", song.seconds / 60, song.seconds % 60)
		cell(time, ui.points(56), kit.colors.dim, .End)
	}

	return ui.signal(row).is_clicked
}

cell :: proc(
	text: string,
	width: ui.Size,
	color: [4]f32,
	align := ui.Align.Start,
	font_size: f32 = 13,
	weight := font.Weight.Regular,
) {
	ui.box(
		"",
		{
			width = width,
			height = ui.fit_text(),
			text_align = align,
			text_color = color,
			font_size = font_size,
			font_weight = weight,
			flags = {.Truncate_Text},
		},
		text,
	)
}
