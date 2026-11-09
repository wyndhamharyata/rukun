package main

import "core:fmt"
import "core:strings"
import "thor/dev"
import "thor/kit"
import "thor/ui"

SEARCH_STYLE :: ui.Style {
	width         = {.Points, 240},
	height        = {.Points, 28},
	padding       = {10, 0, 10, 0},
	corner_radius = 6,
}

tasks_page: struct {
	search:   kit.Text_Field,
	// Each task's title and assignee's name in lower case, for the search.
	lowered:  [][2]string,
	shown:    [dynamic]int,
	selected: string,
}

start_tasks_page :: proc() {
	tasks_page.lowered = make([][2]string, len(rukun.tasks))

	for task, index in rukun.tasks {
		name := find_member(task.assignee).name
		tasks_page.lowered[index] = {strings.to_lower(task.title), strings.to_lower(name)}
	}

	filter_tasks("")
}

filter_tasks :: proc(query: string) {
	clear(&tasks_page.shown)
	needle := strings.to_lower(query, context.temp_allocator)

	for lowered, index in tasks_page.lowered {
		is_match := strings.contains(lowered[0], needle) || strings.contains(lowered[1], needle)
		if is_match do append(&tasks_page.shown, index)
	}
}

build_tasks_page :: proc() {
	if ui.col("tasks", {width = ui.fill(), height = ui.fill(), padding = {24, 40, 24, 0}}) {
		page := ui.current_parent()

		if ui.row("header", {width = ui.fill(), height = ui.points(36), align = .Center}) {
			kit.heading("Tasks")

			if kit.text_field(&tasks_page.search, "search", "Search", style = SEARCH_STYLE) {
				filter_tasks(kit.to_field_text(&tasks_page.search))
				ui.set_scroll(ui.find_box("list", page), 0)
			}
		}

		gap(16)
		build_column_titles()
		kit.divider()

		if len(tasks_page.shown) == 0 {
			empty := ui.Style {
				width   = ui.fill(),
				height  = ui.fill(),
				align   = .Center,
				justify = .Center,
			}
			if ui.col("empty", empty) do kit.text("No tasks match", kit.colors.dim, width = ui.fit_text())
			return
		}

		dev.bench_scroll(ui.find_box("list", page))
		shown := tasks_page.shown[:]

		if first, last, ok := kit.list("list", len(shown), 34, {padding = {0, 0, 0, 12}}); ok {
			for index in shown[first:last] do build_task_row(&rukun.tasks[index])
		}
	}
}

// The header row is 27 high, so with the divider below it the two make 28.
build_column_titles :: proc() {
	style := ui.Style {
		width   = ui.fill(),
		height  = ui.points(27),
		align   = .Center,
		gap     = 16,
		padding = {12, 0, 12, 0},
	}

	if ui.row("columns", style) {
		ui.box("", {width = ui.points(16)})
		kit.text("Title", kit.colors.faint, 12, .Semibold, ui.fill(5))
		kit.text("Space", kit.colors.faint, 12, .Semibold, ui.fill(2))
		kit.text("Assignee", kit.colors.faint, 12, .Semibold, ui.fill(2))
		kit.text("Due", kit.colors.faint, 12, .Semibold, ui.points(88), .End)
	}
}

build_task_row :: proc(task: ^Task) {
	if kit.list_row(task.id, &tasks_page.selected, {gap = 16}) {
		task_checkbox(task)
		kit.text(task.title, kit.colors.dim if task.done else {}, width = ui.fill(5))
		kit.text(fmt.tprintf("#%s", task.space), kit.colors.dim, width = ui.fill(2))

		if ui.row("assignee", {width = ui.fill(2), align = .Center, gap = 8}) {
			member := find_member(task.assignee)
			avatar(member, 20)
			kit.text(member.name, kit.colors.dim)
		}

		kit.text(to_date_text(task.due), kit.colors.dim, width = ui.points(88), align = .End)
	}
}
