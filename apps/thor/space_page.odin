package main

import "core:fmt"
import "thor/app"
import "thor/dev"
import "thor/kit"
import "thor/ui"

// A guess at an item's height before it is measured: a name line and two lines of text.
ITEM_ESTIMATE :: 60

build_space_page :: proc(space: ^Space) {
	if ui.col("space", {width = ui.fill(), height = ui.fill(), padding = {24, 40, 24, 0}}) {
		page := ui.current_parent()

		if ui.row("header", {width = ui.fill(), height = ui.points(36), align = .Center}) {
			kit.heading(fmt.tprintf("#%s", space.name))
		}

		gap(8)
		dev.bench_scroll(ui.find_box(space.id, page))
		items := space.items
		changes := ui.Style {
			gap     = 16,
			padding = {0, 16, 0, 16},
		}

		// The list's id is the space's, so each space opens at its end.
		if first, last, ok := kit.list(
			space.id,
			len(items),
			0,
			changes,
			ITEM_ESTIMATE,
			starts_at_end = true,
		); ok {
			for &item in items[first:last] do build_item(&item)
		}
	}
}

build_item :: proc(item: ^Item) {
	if ui.row(item.id, {width = ui.fill(), gap = 12}) {
		author := find_member(item.author)
		avatar(author, 28)

		if ui.col("body", {width = ui.fill(), max_size = {640, 0}, gap = 4}) {
			if ui.row("by", {align = .Center, gap = 8}) {
				kit.text(
					author.name,
					weight = .Semibold,
					width = ui.fit_text(),
					line_height = BODY_LINE,
				)
				time := to_time_text(item.time)
				kit.text(
					time,
					kit.colors.faint,
					12,
					width = ui.fit_text(),
					line_height = SMALL_LINE,
				)
			}

			switch item.kind {
			case "message":
				build_message(item)
			case "task":
				build_task_card(find_task(item.task))
			case "list":
				build_list_card(item)
			case "note":
				build_note_card(find_note(item.note))
			}
		}
	}
}

build_message :: proc(item: ^Item) {
	if ui.col("message", {width = ui.fill(), gap = 8}) {
		kit.paragraph(item.text, line_height = BODY_LINE)

		if item.photo != "" {
			path := app.resource_path(fmt.tprintf("photos/%s", item.photo))
			style := ui.Style {
				width         = ui.points(240),
				height        = ui.points(180),
				corner_radius = 8,
			}
			kit.image(path, style, is_fading = false)
		}
	}
}

to_card_style :: proc(changes: ui.Style) -> ui.Style {
	card := ui.Style {
		width         = ui.points(360),
		corner_radius = 8,
		background    = kit.to_color(CARD_COLOR),
		border_width  = 1,
		border_color  = kit.colors.line,
	}

	return ui.merge(card, changes)
}

build_task_card :: proc(task: ^Task) {
	style := to_card_style(
		{height = ui.points(40), align = .Center, gap = 10, padding = {12, 0, 12, 0}},
	)

	if ui.row("task", style) {
		task_checkbox(task)
		kit.text(task.title, kit.colors.dim if task.done else {})
		avatar(find_member(task.assignee), 20)
	}
}

build_list_card :: proc(item: ^Item) {
	if ui.col("list", to_card_style({padding = 12})) {
		kit.text(item.title, weight = .Semibold, line_height = BODY_LINE)
		gap(6)

		for &entry, index in item.entries do entry_row(fmt.tprint(index), &entry)
	}
}

build_note_card :: proc(note: ^Note) {
	style := to_card_style(
		{
			height = ui.points(56),
			axis = .Y,
			justify = .Center,
			gap = 2,
			padding = {12, 0, 12, 0},
			hover_background = kit.colors.hover,
			flags = {.Clickable},
		},
	)
	card := ui.box("note", style)
	if ui.signal(card).is_clicked do open_note(note.id)

	if ui.scope(card) {
		kit.text(note.title, weight = .Semibold)
		if len(note.body) > 0 do kit.text(note.body[0], kit.colors.dim, 12)
	}
}
