package main

import "base:runtime"
import "core:testing"
import "thor/kit"

@(test)
a_new_task_takes_its_space_from_a_tag :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator()
	load_rukun()
	rumah := find_space("rumah")
	item_count := len(rumah.items)

	kit.set_field_text(&tasks_page.new_task, "Beli galon #rumah  besok")
	testing.expect(t, add_task())

	task := rukun.tasks[0]
	testing.expect_value(t, task.title, "Beli galon besok")
	testing.expect_value(t, task.space, "rumah")
	testing.expect_value(t, task.assignee, USER)
	testing.expect_value(t, task.due, now_text()[:10])
	testing.expect_value(t, tasks_page.selected, task.id)
	testing.expect_value(t, len(tasks_page.shown), len(rukun.tasks))
	testing.expect_value(t, kit.to_field_text(&tasks_page.new_task), "")
	testing.expect_value(t, len(rumah.items), item_count + 1)
	testing.expect_value(t, rumah.items[item_count].task, task.id)
}

@(test)
a_new_task_with_no_space_goes_to_keluarga_and_needs_a_title :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator()
	load_rukun()

	kit.set_field_text(&tasks_page.new_task, "Telepon Oma #nowhere")
	testing.expect(t, add_task())
	testing.expect_value(t, rukun.tasks[0].space, "keluarga")
	testing.expect_value(t, rukun.tasks[0].title, "Telepon Oma #nowhere")

	count := len(rukun.tasks)
	kit.set_field_text(&tasks_page.new_task, "#rumah #kucing")
	testing.expect(t, !add_task(), "tags alone leave no title")
	testing.expect_value(t, len(rukun.tasks), count)
}

@(test)
a_sent_message_goes_at_the_end_of_its_space :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator()
	load_rukun()
	space := find_space("kucing")

	kit.set_field_text(&composer, "  ")
	testing.expect(t, !send_message(space), "spaces alone send nothing")

	kit.set_field_text(&composer, " Mochi sudah makan. ")
	testing.expect(t, send_message(space))

	message := space.items[len(space.items) - 1]
	testing.expect_value(t, message.text, "Mochi sudah makan.")
	testing.expect_value(t, message.author, USER)
	testing.expect_value(t, kit.to_field_text(&composer), "")
}
