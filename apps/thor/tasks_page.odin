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

NEW_TASK_STYLE :: ui.Style {
	width         = {.Points, 280},
	height        = {.Points, 28},
	padding       = {10, 0, 10, 0},
	corner_radius = 6,
}

tasks_page: struct {
	new_task: kit.Text_Field,
	search:   kit.Text_Field,
	// Each task's title and assignee's name in lower case, for the search.
	lowered:  [][2]string,
	shown:    [dynamic]int,
	selected: string,
}

start_tasks_page :: proc() {
	for pair in tasks_page.lowered do delete(pair[0])
	for pair in tasks_page.lowered do delete(pair[1])
	delete(tasks_page.lowered)
	tasks_page.lowered = make([][2]string, len(rukun.tasks))

	for task, index in rukun.tasks {
		name := find_member(task.assignee).name
		tasks_page.lowered[index] = {strings.to_lower(task.title), strings.to_lower(name)}
	}

	filter_tasks(kit.to_field_text(&tasks_page.search))
}

// Adds the New task field's task at the top of the list. The first #name that names a space puts
// the task there, and every such #name leaves the title. Returns false when no title is left.
add_task :: proc() -> bool {
	space := find_space("keluarga")
	is_picked := false
	words: [dynamic]string
	defer delete(words)

	for word in strings.fields(kit.to_field_text(&tasks_page.new_task), context.temp_allocator) {
		named := find_space(word[1:]) if strings.has_prefix(word, "#") else nil

		if named == nil {
			append(&words, word)
		} else if !is_picked {
			space = named
			is_picked = true
		}
	}

	if len(words) == 0 do return false

	now := now_text()
	task := Task {
		id       = make_id("t"),
		title    = strings.join(words[:], " "),
		space    = space.id,
		assignee = USER,
		due      = now[:10],
	}
	inject_at(&rukun.tasks, 0, task)
	append(
		&space.items,
		Item{id = make_id("i"), author = USER, time = now, kind = "task", task = task.id},
	)

	tasks_page.selected = task.id
	kit.set_field_text(&tasks_page.new_task, "")
	start_tasks_page()

	return true
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
		if tasks_page.new_task.is_submitted && add_task() do ui.set_scroll(ui.find_box("list", page), 0)

		if ui.row(
			"header",
			{width = ui.fill(), height = ui.points(36), align = .Center, gap = 8},
		) {
			kit.heading("Tasks")
			kit.text_field(
				&tasks_page.new_task,
				"new task",
				"New task #space",
				style = NEW_TASK_STYLE,
			)

			kit.text_field(&tasks_page.search, "search", "Search", style = SEARCH_STYLE)
			if tasks_page.search.is_changed {
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
			if ui.col("empty", empty) do kit.text("No tasks match", kit.to_faded(kit.colors.base_content, 0.7), width = ui.fit_text())
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
		kit.text("Title", kit.to_faded(kit.colors.base_content, 0.5), 12, .Semibold, ui.fill(5))
		kit.text("Space", kit.to_faded(kit.colors.base_content, 0.5), 12, .Semibold, ui.fill(2))
		kit.text("Assignee", kit.to_faded(kit.colors.base_content, 0.5), 12, .Semibold, ui.fill(2))
		kit.text("Due", kit.to_faded(kit.colors.base_content, 0.5), 12, .Semibold, ui.points(88), .End)
	}
}

build_task_row :: proc(task: ^Task) {
	if kit.list_row(task.id, &tasks_page.selected, {gap = 16}) {
		task_checkbox(task)
		kit.text(task.title, kit.to_faded(kit.colors.base_content, 0.7) if task.done else {}, width = ui.fill(5))
		kit.text(fmt.tprintf("#%s", task.space), kit.to_faded(kit.colors.base_content, 0.7), width = ui.fill(2))

		if ui.row("assignee", {width = ui.fill(2), align = .Center, gap = 8}) {
			member := find_member(task.assignee)
			avatar(member, 20)
			kit.text(member.name, kit.to_faded(kit.colors.base_content, 0.7))
		}

		kit.text(to_date_text(task.due), kit.to_faded(kit.colors.base_content, 0.7), width = ui.points(88), align = .End)
	}
}
