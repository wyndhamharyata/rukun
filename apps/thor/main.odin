package main

import "core:encoding/json"
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

SIDEBAR_WIDTH :: 220

WINDOW_COLOR :: 0x121214ff

SIDEBAR_COLOR :: 0x161618ff

rukun: struct {
	members: []Member,
	spaces:  []Space,
	tasks:   []Task,
	notes:   []Note,
}

main :: proc() {
	error := json.unmarshal_string(#load("../../data/rukun.json", string), &rukun)
	assert(error == nil, "rukun.json does not parse")

	start_tasks_page()
	app.run({title = "Rukun", size = {1100, 720}, min_size = {900, 600}}, frame)
}

// The sidebar is an empty box until phase 4 builds it.
frame :: proc() {
	root := ui.current_parent()
	root.style.axis = .X
	root.style.background = kit.to_color(WINDOW_COLOR)

	ui.box(
		"sidebar",
		{
			width = ui.points(SIDEBAR_WIDTH),
			height = ui.fill(),
			background = kit.to_color(SIDEBAR_COLOR),
		},
	)
	build_tasks_page()
}

find_member :: proc(id: string) -> Member {
	for member in rukun.members do if member.id == id do return member

	return {}
}
