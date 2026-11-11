package main

import "base:runtime"
import "core:strings"
import "core:testing"
import "thor/headless"
import "thor/kit"

@(test)
a_new_task_takes_its_space_from_a_tag :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator()
	load_rukun()
	rumah := find_space("rumah")
	item_count := len(rumah.items)

	kit.set_input_text(&tasks_page.new_task, "Beli galon #rumah  besok")
	testing.expect(t, add_task())

	task := rukun.tasks[0]
	testing.expect_value(t, task.title, "Beli galon besok")
	testing.expect_value(t, task.space, "rumah")
	testing.expect_value(t, task.assignee, USER)
	testing.expect_value(t, task.due, now_text()[:10])
	testing.expect_value(t, tasks_page.selected, task.id)
	testing.expect_value(t, len(tasks_page.shown), len(rukun.tasks))
	testing.expect_value(t, kit.to_input_text(&tasks_page.new_task), "")
	testing.expect_value(t, len(rumah.items), item_count + 1)
	testing.expect_value(t, rumah.items[item_count].task, task.id)
}

@(test)
a_new_task_with_no_space_goes_to_keluarga_and_needs_a_title :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator()
	load_rukun()

	kit.set_input_text(&tasks_page.new_task, "Telepon Oma #nowhere")
	testing.expect(t, add_task())
	testing.expect_value(t, rukun.tasks[0].space, "keluarga")
	testing.expect_value(t, rukun.tasks[0].title, "Telepon Oma #nowhere")

	count := len(rukun.tasks)
	kit.set_input_text(&tasks_page.new_task, "#rumah #kucing")
	testing.expect(t, !add_task(), "tags alone leave no title")
	testing.expect_value(t, len(rukun.tasks), count)
}

@(test)
a_sent_message_goes_at_the_end_of_its_space :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator()
	load_rukun()
	space := find_space("kucing")

	kit.set_input_text(&composer, "  ")
	testing.expect(t, !send_message(space), "spaces alone send nothing")

	kit.set_input_text(&composer, " Mochi sudah makan. ")
	testing.expect(t, send_message(space))

	message := space.items[len(space.items) - 1]
	testing.expect_value(t, message.text, "Mochi sudah makan.")
	testing.expect_value(t, message.author, USER)
	testing.expect_value(t, kit.to_input_text(&composer), "")
}

@(test)
each_page_shows_what_it_did :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator()
	for section in ([]string{"tasks", "keluarga", "liburan"}) {
		load_rukun()
		state.section = section
		headless.open(frame, {size = {1100, 720}})
		headless.expect_tree(t, section)
		headless.close()
	}
}

@(test)
a_task_typed_and_entered_shows_at_the_top :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator()
	load_rukun()
	state.section = "tasks"
	headless.open(frame, {size = {1100, 720}})
	defer headless.close()
	kit.set_input_text(&tasks_page.new_task, "")
	count := len(rukun.tasks)

	headless.click("New task #space")
	headless.type_text("Beli galon #rumah")
	headless.press(.Return)

	testing.expect_value(t, len(rukun.tasks), count + 1)
	testing.expect_value(t, rukun.tasks[0].title, "Beli galon")
	testing.expect_value(t, kit.to_input_text(&tasks_page.new_task), "")
	testing.expect(t, strings.contains(headless.tree(), "text \"Beli galon\""), "the task shows in the list")
}
