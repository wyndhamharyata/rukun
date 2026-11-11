package app

import "../platform"
import "../ui"

_update_accessibility :: proc() {
	platform.update_accessibility(native_window, _to_accessibility_nodes(), ui._state.focused_key)
}

// The current window's elements as VoiceOver reads them, in the temp allocator.
_to_accessibility_nodes :: proc() -> []platform.Accessibility_Node {
	found := make([dynamic]ui.Accessible, context.temp_allocator)
	ui._list_accessible({ui._state.root, ui._state.overlay_root}, &found)
	nodes := make([]platform.Accessibility_Node, len(found), context.temp_allocator)
	// The node of each depth above the current one, and how many children each node has so far.
	path := make([dynamic]int, context.temp_allocator)
	child_counts := make([]u64, len(found) + 1, context.temp_allocator)

	for item, index in found {
		resize(&path, item.depth)
		parent := path[item.depth - 1] if item.depth > 0 else -1
		box := item.box
		key := box._key
		// A box with no id gets a key from its parent and its place among the parent's children.
		if key == 0 {
			parent_key := nodes[parent].key if parent >= 0 else 0
			child_counts[parent + 1] += 1
			key = (parent_key ~ 0x9e3779b97f4a7c15) * 1099511628211 + child_counts[parent + 1]
		}
		nodes[index] = {
			key         = key,
			parent      = parent,
			role        = item.role,
			label       = item.label,
			value       = box.value,
			is_on       = box.is_on,
			is_disabled = item.role == .Button && .Clickable not_in box.style.flags,
			rect        = ui._to_window_points(ui._to_shown_rect(box)),
		}
		append(&path, index)
	}

	return nodes
}
