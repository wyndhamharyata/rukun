package main

import "core:fmt"
import "core:strings"
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
	new_task: kit.Text_Input,
	search:   kit.Text_Input,
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

	filter_tasks(kit.to_input_text(&tasks_page.search))
}

// Adds the New task field's task at the top of the list. The first #name that names a space puts
// the task in that space. The title drops every such #name. Returns false when the title has nothing left.
add_task :: proc() -> bool {
	space := find_space("keluarga")
	is_picked := false
	words: [dynamic]string
	defer delete(words)

	for word in strings.fields(kit.to_input_text(&tasks_page.new_task), context.temp_allocator) {
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
	kit.set_input_text(&tasks_page.new_task, "")
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

TASK_COLUMNS := [?]kit.Column {
	{id = "done", title = "", width = 40, min_width = 40},
	{id = "title", title = "Title"},
	{id = "space", title = "Space", width = 140},
	{id = "assignee", title = "Assignee", width = 150},
	{id = "due", title = "Due", width = 100},
}

build_tasks_page :: proc() {
	if ui.col("tasks", {width = ui.fill(), height = ui.fill(), padding = {24, 40, 24, 0}}) {
		page := ui.current_parent()
		if tasks_page.new_task.is_submitted && add_task() do ui.set_scroll(find_task_list(page), 0)

		if ui.row(
			"header",
			{width = ui.fill(), height = ui.points(36), align = .Center, gap = 8},
		) {
			kit.heading("Tasks")
			kit.text_field("new_task", &tasks_page.new_task, "New task #space", style = NEW_TASK_STYLE)

			kit.text_field("search", &tasks_page.search, "Search", style = SEARCH_STYLE)
			if tasks_page.search.is_changed {
				filter_tasks(kit.to_input_text(&tasks_page.search))
				ui.set_scroll(find_task_list(page), 0)
			}
		}

		ui.space(16)
		if len(tasks_page.shown) == 0 {
			empty := ui.Style {
				width   = ui.fill(),
				height  = ui.fill(),
				align   = .Center,
				justify = .Center,
			}
			if ui.col("empty", empty) do kit.text("No tasks match", kit.with_opacity(kit.colors.base_content, 0.7), width = ui.fit_text())
			return
		}

		shown := tasks_page.shown[:]

		if first, last, ok := kit.table("list", TASK_COLUMNS[:], len(shown)); ok {
			for index in shown[first:last] do build_task_row(&rukun.tasks[index])
		}
	}
}

// The box that scrolls the task table's rows.
find_task_list :: proc(page: ^ui.Box) -> ^ui.Box {
	table := ui.find_box("list", page)

	return ui.find_box("rows", table) if table != nil else nil
}

build_task_row :: proc(task: ^Task) {
	if kit.list_row(task.id, &tasks_page.selected) {
		ui.current_parent().label = task.title
		dim := kit.with_opacity(kit.colors.base_content, 0.7)
		if kit.cell("done") do task_checkbox(task)
		if kit.cell("title") do kit.text(task.title, dim if task.done else {})
		if kit.cell("space") do kit.text(fmt.tprintf("#%s", task.space), dim)
		if kit.cell("assignee") {
			member := find_member(task.assignee)
			avatar(member, 20)
			kit.text(member.name, dim)
		}
		if kit.cell("due") do kit.text(to_date_text(task.due), dim)
	}
}
