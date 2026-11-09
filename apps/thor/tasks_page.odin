package main

import "core:fmt"
import "core:strconv"
import "core:strings"
import "thor/font"
import "thor/image"
import "thor/kit"
import "thor/platform"
import "thor/render"
import "thor/ui"

ROW_HEIGHT :: 34

EXTRA_ROWS :: 2

AVATAR_SIZE :: 20

CHECKBOX_SIZE :: 16

SELECTED_ROW_COLOR :: 0x0a84ff2e

EMPTY_IMAGE_COLOR :: 0x2a2a2fff

tasks_page: struct {
	search:   kit.Text_Field,
	// Each task's title and assignee's name in lower case, for the search.
	lowered:  [][2]string,
	shown:    [dynamic]int,
	selected: string,
}

start_tasks_page :: proc() {
	kit.register_text_field(&tasks_page.search)
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
	field := &tasks_page.search
	kit.apply_text_events(platform.list_events())
	if field.is_changed do filter_tasks(kit.to_field_text(field))

	page := ui.box(
		"tasks",
		{width = ui.fill(), height = ui.fill(), axis = .Y, padding = {24, 40, 24, 0}},
	)

	if ui.scope(page) {
		header := ui.box(
			"header",
			{width = ui.fill(), height = ui.points(36), axis = .X, align = .Center},
		)

		if ui.scope(header) {
			cell("Tasks", ui.fill(), kit.colors.text, font_size = 28, weight = .Bold)

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
			ui.box("", {width = ui.points(CHECKBOX_SIZE), height = ui.points(1)})
			cell("Title", ui.fill(5), kit.colors.faint, font_size = 12, weight = .Semibold)
			cell("Space", ui.fill(2), kit.colors.faint, font_size = 12, weight = .Semibold)
			cell("Assignee", ui.fill(2), kit.colors.faint, font_size = 12, weight = .Semibold)
			cell("Due", ui.points(88), kit.colors.faint, .End, 12, .Semibold)
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
		if ui.scope(list) do build_task_rows(list)
	}

	kit.finish_text_fields()
}

build_task_rows :: proc(list: ^ui.Box) {
	shown := tasks_page.shown[:]

	if len(shown) == 0 {
		empty := ui.box(
			"",
			{width = ui.fill(), height = ui.points(list.size.y - 12), axis = .X, align = .Center},
		)
		if ui.scope(empty) do cell("No tasks match", ui.fill(), kit.colors.dim, .Center)
		return
	}

	first := max(0, int(list.scroll / ROW_HEIGHT) - EXTRA_ROWS)
	last := min(len(shown) - 1, int((list.scroll + list.size.y) / ROW_HEIGHT) + EXTRA_ROWS)

	if first > 0 do ui.box("", {width = ui.fill(), height = ui.points(f32(first) * ROW_HEIGHT)})

	for index in first ..= last {
		task := &rukun.tasks[shown[index]]
		if task_row(task) do tasks_page.selected = task.id
	}

	if last < len(shown) - 1 {
		ui.box(
			"",
			{width = ui.fill(), height = ui.points(f32(len(shown) - 1 - last) * ROW_HEIGHT)},
		)
	}
}

task_row :: proc(task: ^Task) -> bool {
	is_selected := task.id == tasks_page.selected
	selected_color := kit.to_color(SELECTED_ROW_COLOR)

	row := ui.box(
		task.id,
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
		if checkbox("done", task.done) do task.done = !task.done
		cell(task.title, ui.fill(5), kit.colors.dim if task.done else kit.colors.text)
		cell(fmt.tprintf("#%s", task.space), ui.fill(2), kit.colors.dim)

		member := find_member(task.assignee)
		assignee := ui.box(
			"",
			{
				width = ui.fill(2),
				height = ui.points(AVATAR_SIZE),
				axis = .X,
				align = .Center,
				gap = 8,
			},
		)

		if ui.scope(assignee) {
			avatar(member, AVATAR_SIZE)
			cell(member.name, ui.fill(), kit.colors.dim)
		}

		cell(to_date_text(task.due), ui.points(88), kit.colors.dim, .End)
	}

	return ui.signal(row).is_clicked
}

// A circle: a ring when open, filled with a checkmark when done.
checkbox :: proc(id: string, is_done: bool) -> bool {
	inset: f32 = 3
	box := ui.box(
		id,
		{
			width = ui.points(CHECKBOX_SIZE),
			height = ui.points(CHECKBOX_SIZE),
			axis = .X,
			align = .Center,
			padding = {inset, 0, inset, 0},
			corner_radius = CHECKBOX_SIZE / 2,
			background = kit.colors.accent if is_done else {},
			border_width = 0 if is_done else 1.5,
			border_color = kit.colors.faint,
			flags = {.Clickable},
		},
	)

	if is_done {
		if ui.scope(box) do kit.icon_box("", "checkmark", CHECKBOX_SIZE - 2 * inset, kit.colors.white)
	}

	return ui.signal(box).is_clicked
}

Avatar_Paint :: struct {
	path:        string,
	size_pixels: int,
}

avatar :: proc(member: Member, size: f32) {
	box := ui.box(
		"",
		{
			width = ui.points(size),
			height = ui.points(size),
			corner_radius = size / 2,
			background = kit.to_color(EMPTY_IMAGE_COLOR),
		},
	)
	paint := new(Avatar_Paint, context.temp_allocator)
	paint^ = {fmt.tprintf("%s/avatars/%s", DATA_FOLDER, member.avatar), int(ui.to_pixels(size))}
	box.data = paint
	box.draw = draw_avatar
}

draw_avatar :: proc(box: ^ui.Box, rect, clip: [4]f32, opacity: f32) {
	paint := cast(^Avatar_Paint)box.data
	texture, _ := image.watch(paint.path, paint.size_pixels)
	if texture == nil do return

	render.push(
		{
			rect = rect,
			uv = {0, 0, 1, 1},
			color = kit.to_faded(kit.colors.white, opacity),
			corner_radius = (rect.z - rect.x) / 2,
			clip = clip,
			kind = .Image,
		},
		texture,
	)
}

to_date_text :: proc(date: string) -> string {
	MONTHS := [12]string {
		"Jan",
		"Feb",
		"Mar",
		"Apr",
		"May",
		"Jun",
		"Jul",
		"Aug",
		"Sep",
		"Oct",
		"Nov",
		"Dec",
	}

	month := strconv.parse_int(date[5:7]) or_else 1
	day := strconv.parse_int(date[8:10]) or_else 1

	return fmt.tprintf("%d %s %s", day, MONTHS[month - 1], date[:4])
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
