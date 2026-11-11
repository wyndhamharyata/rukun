package kit

import "../platform"
import "core:strings"
import "core:time"

// Typing or backward deletes within this many seconds merge into one undo.
_HISTORY_MERGE_SECONDS :: 1
_HISTORY_LIMIT :: 500

// At byte at, inserted replaces removed. before and after are the selection as {anchor, caret}.
_Edit :: struct {
	at:        int,
	removed:   string,
	inserted:  string,
	before:    [2]int,
	after:     [2]int,
	is_typing: bool,
	time:      time.Tick,
}

// What ⌘Z undoes and ⇧⌘Z redoes in a text field or editor.
_History :: struct {
	undo, redo: [dynamic]_Edit,
}

// Records the change for undo, merging runs of typing or backward deletes. Returns the new caret.
_replace_text :: proc(
	history: ^_History,
	text: ^[dynamic]u8,
	start, end: int,
	inserted: string,
	before: [2]int,
	is_typing: bool,
) -> int {
	_clear_edits(&history.redo)
	caret := start + len(inserted)
	after := [2]int{caret, caret}
	removed := string(text[start:end])
	now := platform.now()

	is_joined := false
	if is_typing && len(history.undo) > 0 {
		last := &history.undo[len(history.undo) - 1]
		is_recent := last.is_typing && time.duration_seconds(time.tick_diff(last.time, now)) < _HISTORY_MERGE_SECONDS
		switch {
		case is_recent && removed == "" && last.removed == "" && start == last.at + len(last.inserted):
			joined := strings.concatenate({last.inserted, inserted})
			delete(last.inserted)
			last.inserted = joined
			is_joined = true
		case is_recent && inserted == "" && last.inserted == "" && end == last.at:
			joined := strings.concatenate({removed, last.removed})
			delete(last.removed)
			last.removed = joined
			last.at = start
			is_joined = true
		}
		if is_joined {
			last.after = after
			last.time = now
		}
	}
	if !is_joined {
		append(&history.undo, _Edit{start, strings.clone(removed), strings.clone(inserted), before, after, is_typing, now})
		if len(history.undo) > _HISTORY_LIMIT {
			_free_edit(history.undo[0])
			ordered_remove(&history.undo, 0)
		}
	}

	remove_range(text, start, end)
	inject_at(text, start, ..transmute([]u8)inserted)

	return caret
}

// Undoes one step and returns the selection from before it, or false with nothing to undo.
_undo :: proc(history: ^_History, text: ^[dynamic]u8) -> (selection: [2]int, ok: bool) {
	edit := pop_safe(&history.undo) or_return
	remove_range(text, edit.at, edit.at + len(edit.inserted))
	inject_at(text, edit.at, ..transmute([]u8)edit.removed)
	append(&history.redo, edit)

	return edit.before, true
}

// Redoes one step and returns the selection from after it.
_redo :: proc(history: ^_History, text: ^[dynamic]u8) -> (selection: [2]int, ok: bool) {
	edit := pop_safe(&history.redo) or_return
	remove_range(text, edit.at, edit.at + len(edit.removed))
	inject_at(text, edit.at, ..transmute([]u8)edit.inserted)
	append(&history.undo, edit)

	return edit.after, true
}

_clear_edits :: proc(edits: ^[dynamic]_Edit) {
	for edit in edits do _free_edit(edit)
	clear(edits)
}

_free_edit :: proc(edit: _Edit) {
	delete(edit.removed)
	delete(edit.inserted)
}

_destroy_history :: proc(history: ^_History) {
	_clear_edits(&history.undo)
	_clear_edits(&history.redo)
	delete(history.undo)
	delete(history.redo)
}
