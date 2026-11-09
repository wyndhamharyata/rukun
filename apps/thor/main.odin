package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "thor/app"
import "thor/kit"
import "thor/ui"

Member :: struct {
	id, name, avatar: string,
}

Entry :: struct {
	text: string,
	done: bool,
}

Item :: struct {
	id, author, time, kind, text, photo, task, note, title: string,
	entries:                                                []Entry,
}

Space :: struct {
	id, name: string,
	items:    []Item,
}

Task :: struct {
	id, title, space, assignee: string,
	done:                       bool,
	due:                        string,
}

Note :: struct {
	id, title, space:                  string,
	body:                              []string,
	checklist:                         []Entry,
	tasks, links, in_spaces, in_notes: []string,
}

// The line boxes of the spec's text styles, in points.
BODY_LINE :: 18
SMALL_LINE :: 16
SUBHEADING_LINE :: 20
HEADING_LINE :: 36

SIDEBAR_COLOR :: 0x161618ff

CARD_COLOR :: 0xffffff0a

rukun: struct {
	members: []Member,
	spaces:  []Space,
	tasks:   []Task,
	notes:   []Note,
}

state: struct {
	// "tasks", or the id of the space the sidebar shows as current.
	section: string,
	// The id of the open note, or "".
	note:    string,
}

main :: proc() {
	error := json.unmarshal_string(#load("../../data/rukun.json", string), &rukun)
	assert(error == nil, "rukun.json does not parse")

	kit.colors.window = kit.to_color(0x121214ff)
	state.section = os.get_env("TESTAPP_PAGE", context.allocator)
	if state.section == "" do state.section = "tasks"

	start_tasks_page()
	app.run({title = "Rukun", size = {1100, 720}, min_size = {900, 600}}, frame)
}

frame :: proc() {
	if ui.row("window", {width = ui.fill(), height = ui.fill()}) {
		build_sidebar()

		switch {
		case state.note != "":
			build_note_page(find_note(state.note))
		case state.section == "tasks":
			build_tasks_page()
		case:
			build_space_page(find_space(state.section))
		}
	}
}

open_note :: proc(id: string) {
	state.note = id
	state.section = find_note(id).space
}

open_space :: proc(id: string) {
	state.note = ""
	state.section = id
}

find_member :: proc(id: string) -> ^Member {
	for &member in rukun.members do if member.id == id do return &member
	return nil
}

find_space :: proc(id: string) -> ^Space {
	for &space in rukun.spaces do if space.id == id do return &space
	return nil
}

find_task :: proc(id: string) -> ^Task {
	for &task in rukun.tasks do if task.id == id do return &task
	return nil
}

find_note :: proc(id: string) -> ^Note {
	for &note in rukun.notes do if note.id == id do return &note
	return nil
}

avatar :: proc(member: ^Member, size: f32) {
	path := app.resource_path(fmt.tprintf("avatars/%s", member.avatar))
	style := ui.Style {
		width         = ui.points(size),
		height        = ui.points(size),
		corner_radius = size / 2,
	}
	kit.image(path, style, is_fading = false)
}

task_checkbox :: proc(task: ^Task) {
	kit.checkbox("done", &task.done, {corner_radius = 8})
}

// A checklist entry: a square checkbox and its text, in a row 24 high.
entry_row :: proc(id: string, entry: ^Entry) {
	if ui.row(id, {width = ui.fill(), height = ui.points(24), align = .Center, gap = 8}) {
		kit.checkbox("done", &entry.done, {width = ui.points(14), height = ui.points(14)})
		kit.text(entry.text, kit.colors.dim if entry.done else {})
	}
}

gap :: proc(points: f32) {
	ui.box("", {height = ui.points(points)})
}

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

// 2027-01-30 reads 30 Jan 2027.
to_date_text :: proc(date: string) -> string {
	month := strconv.parse_int(date[5:7]) or_else 1
	day := strconv.parse_int(date[8:10]) or_else 1

	return fmt.tprintf("%d %s %s", day, MONTHS[month - 1], date[:4])
}

// 2026-11-08T21:26 reads 8 Nov 2026, 21.26.
to_time_text :: proc(time: string) -> string {
	return fmt.tprintf("%s, %s.%s", to_date_text(time[:10]), time[11:13], time[14:16])
}
