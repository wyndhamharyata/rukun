package kit

// Each window has its own state, and _window points to the one in use.
_Window_State :: struct {
	popover:       _Popover,
	// The frame a popover closed on Escape, so the dialog it is in stays open.
	escape_frame:  int,
	// The box key of the open select, date picker or color well, so the app keeps only the value.
	open_pop_up:   u64,
	tooltip:       _Tooltip,
	dialog:        _Dialog,
	toast:         _Toast,
	// The inputs of every text field and editor in the window, the app's and kit's own.
	inputs:        [dynamic]^Text_Input,
	caret_rect:    [4]f32,
	// Inputs share ui's keyboard focus, and this input takes it as kit next builds it.
	focus_request: ^Text_Input,
	lists:         map[u64]^_List,
	// What a held handle was when the press began.
	drag:          struct {
		_key:  u64,
		start: f32,
	},
	// The columns of the table that kit builds now, for its cells.
	columns:       []_Placed_Column,
	palette:       _Palette,
	search:        _Search,
	calendars:     _Calendars,
	color_pickers: map[u64]_Color_Picker,
}

_default_window: _Window_State
_window: ^_Window_State

@(init)
_start_window :: proc "contextless" () {
	_window = &_default_window
}

// Makes the window's state the one components read, until the next call.
_use_window_state :: proc(state: ^_Window_State) {
	_window = state
}

// If state is in use, _window goes back to _default_window.
_destroy_window_state :: proc(state: ^_Window_State) {
	delete(state.toast.text)
	delete(state.inputs)
	destroy_input(&state.palette.input)
	delete(state.calendars.months)
	for _, picker in state.color_pickers {
		destroy_input(picker.input)
		free(picker.input)
	}
	delete(state.color_pickers)
	for _, list in state.lists {
		delete(list.heights)
		delete(list.keys)
		free(list)
	}
	delete(state.lists)
	state^ = {}
	if _window == state do _window = &_default_window
}
