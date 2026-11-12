package main

import "core:fmt"
import "thor/kit"
import "thor/ui"

build_note_page :: proc(note: ^Note) {
	// The scroll's id is the note's, so each note opens at its top.
	if ui.col(note.id, {width = ui.fill(), height = ui.fill(), padding = {24, 40, 24, 24}, flags = {.Scroll, .Clip}}) {
		if ui.col("content", {width = ui.fill(), max_size = {640, 0}}) {
			kit.text(note.title, font_size = 28, weight = .Bold)
			ui.space(16)

			if ui.col("body", {width = ui.fill(), gap = 12}) {
				for paragraph in note.body do kit.text(paragraph, is_wrapped = true)
			}

			if len(note.checklist) > 0 {
				build_section_title("Checklist")
				for &entry, index in note.checklist do entry_row(fmt.tprint(index), &entry)
			}

			if len(note.tasks) > 0 {
				build_section_title("Tasks")
				for id in note.tasks do build_note_task(find_task(id))
			}

			if len(note.links) > 0 {
				build_section_title("Links")
				for id in note.links {
					if link(fmt.tprintf("link %s", id), find_note(id).title) do open_note(id)
				}
			}

			if len(note.in_spaces) + len(note.in_notes) > 0 {
				build_section_title("Mentioned in")
				for id in note.in_spaces {
					if link(fmt.tprintf("space %s", id), fmt.tprintf("#%s", id)) do open_space(id)
				}
				for id in note.in_notes {
					if link(fmt.tprintf("note %s", id), find_note(id).title) do open_note(id)
				}
			}
		}
	}
}

build_section_title :: proc(title: string) {
	ui.space(24)
	kit.text(title, font_size = 15, weight = .Semibold)
	ui.space(8)
}

build_note_task :: proc(task: ^Task) {
	style := ui.Style {
		width   = ui.fill(),
		height  = ui.points(34),
		align   = .Center,
		gap     = 16,
		padding = {12, 0, 12, 0},
	}

	if ui.row(task.id, style) {
		task_checkbox(task)
		kit.text(task.title, kit.with_opacity(kit.colors.base_content, 0.7) if task.done else {})
		kit.text(to_date_text(task.due), kit.with_opacity(kit.colors.base_content, 0.7), width = ui.points(88), align = .End)
	}
}

link :: proc(id, label: string) -> bool {
	style := ui.Style {
		width      = ui.fill(),
		height     = ui.points(28),
		text_color = kit.colors.primary,
		flags      = {.Clickable, .Truncate_Text},
	}

	return ui.signal(ui.box(id, style, label)).is_activated
}
