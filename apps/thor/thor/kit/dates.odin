package kit

import "../platform"
import "../ui"
import "core:fmt"
import "core:time"

_CALENDAR_DAY_POINTS :: 30
_CALENDAR_GAP_POINTS :: 2
_CALENDAR_WEEKS :: 6

// The zero value means no date.
Date :: struct {
	year, month, day: int,
}

_Calendars :: struct {
	// The month each calendar shows, by its box's key, as its first day.
	months:    map[u64]Date,
	// The calendar with this key gives keyboard focus to focus_day as kit builds the day.
	focus_key: u64,
	focus_day: Date,
}

// Today, in the person's time zone.
today :: proc() -> Date {
	day := platform.read_today()

	return {day[0], day[1], day[2]}
}

add_days :: proc(date: Date, days: int) -> Date {
	moment, _ := time.components_to_time(date.year, date.month, date.day, 12, 0, 0)
	year, month, day := time.date(time.time_add(moment, time.Duration(days) * 24 * time.Hour))

	return {year, int(month), day}
}

// Clamps the day to the last day of a shorter month.
add_months :: proc(date: Date, months: int) -> Date {
	index := date.year * 12 + date.month - 1 + months
	year, month := index / 12, index % 12 + 1

	return {year, month, min(date.day, days_in_month(year, month))}
}

days_in_month :: proc(year, month: int) -> int {
	switch month {
	case 2:
		is_leap := year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
		return 29 if is_leap else 28
	case 4, 6, 9, 11:
		return 30
	}

	return 31
}

// The day as macOS writes it in the person's language, from a template such as "yMMMd".
// shortcut: noon UTC is the wrong day in zones beyond ±12 hours; format in UTC if an app needs it.
format_day :: proc(date: Date, template: string) -> string {
	moment, _ := time.components_to_time(date.year, date.month, date.day, 12, 0, 0)

	return platform.format_date(f64(time.to_unix_nanoseconds(moment)) / 1e6, template)
}

// 1 for Sunday to 7 for Saturday.
_to_weekday :: proc(date: Date) -> int {
	moment, _ := time.components_to_time(date.year, date.month, date.day, 12, 0, 0)

	return int(time.weekday(moment)) + 1
}

// Weeks start on the person's first weekday. Left and Right move a day, Up and Down a week.
// Page Up and Page Down move a month. Return picks. Sets is_changed on the frame date^ changes.
calendar :: proc(id: string, date: ^Date) -> ui.Signal {
	width: f32 = 7 * _CALENDAR_DAY_POINTS + 6 * _CALENDAR_GAP_POINTS
	box := ui.box(id, {width = ui.points(width), axis = .Y, gap = 6})
	state := &_window.calendars
	shown := state.months[box._key] or_else {}
	if shown == {} do shown = date^ if date^ != {} else today()
	shown.day = 1
	is_changed := false

	if ui.scope(box) {
		if ui.row("month", {width = ui.fill(), align = .Center, gap = 2, padding = {4, 0, 0, 0}}) {
			text(format_day(shown, "yMMMM"), font_size = 13, weight = .Semibold)
			if button("previous_month", icon = "chevron.left", icon_size = 12).is_activated do shown = add_months(shown, -1)
			if button("next_month", icon = "chevron.right", icon_size = 12).is_activated do shown = add_months(shown, 1)
		}

		start := add_days(shown, -((_to_weekday(shown) - platform.read_first_weekday() + 7) % 7))
		if ui.row("weekdays", {gap = _CALENDAR_GAP_POINTS}) {
			for column in 0 ..< 7 {
				name := format_day(add_days(start, column), "EEEEEE")
				text(name, to_faded(colors.base_content, 0.5), 11, .Semibold, ui.points(_CALENDAR_DAY_POINTS), .Center)
			}
		}

		days := ui.box("days", {width = ui.points(width), axis = .X, gap = _CALENDAR_GAP_POINTS, flags = {.Wrap_Children, .Arrow_Keys}})
		today_date := today()
		if ui.scope(days) {
			for index in 0 ..< 7 * _CALENDAR_WEEKS {
				day := add_days(start, index)
				picked, moved := _build_day(box, day, date^, shown, today_date)
				if picked {
					if date^ != day do is_changed = true
					date^ = day
					shown = {day.year, day.month, 1}
					ui.request_frame()
				}
				if moved != {} {
					state.focus_key = box._key
					state.focus_day = moved
					shown = {moved.year, moved.month, 1}
					ui.request_frame()
				}
			}
		}
	}

	state.months[box._key] = shown
	signal := ui.signal(box)
	signal.is_changed = is_changed

	return signal
}

// is_picked is true on a click. moved is the day a key moves focus to, else zero.
_build_day :: proc(calendar_box: ^ui.Box, day, picked, shown, today_date: Date) -> (is_picked: bool, moved: Date) {
	is_on := day == picked
	is_in_month := day.month == shown.month
	text_color := colors.base_content
	switch {
	case is_on:
		text_color = colors.primary_content
	case day == today_date:
		text_color = colors.primary
	case !is_in_month:
		text_color = to_faded(colors.base_content, 0.35)
	}
	look := ui.Style {
		width            = ui.points(_CALENDAR_DAY_POINTS),
		height           = ui.points(_CALENDAR_DAY_POINTS),
		text_align       = .Center,
		corner_radius    = _CALENDAR_DAY_POINTS / 2,
		background       = colors.primary if is_on else {},
		hover_background = colors.primary if is_on else to_faded(colors.base_content, HOVER_OPACITY),
		press_background = _to_darker(colors.primary, _FILL_HOVER_DARKEN) if is_on else to_faded(colors.base_content, SELECTED_OPACITY),
		text_color       = text_color,
		font_size        = 13,
		font_weight      = .Semibold if day == today_date else .Regular,
		flags            = {.Clickable},
	}
	name := fmt.tprintf("%04d-%02d-%02d", day.year, day.month, day.day)
	cell := ui.box(name, look, fmt.tprint(day.day))
	cell.role, cell.label, cell.is_on = .Button, name, is_on
	signal := ui.signal(cell)

	// Tab enters the days at the picked one, or today.
	if is_on || (picked == {} && day == today_date) do _enter_group_at(cell)
	state := &_window.calendars
	if state.focus_key == calendar_box._key && state.focus_day == day {
		ui.focus(cell)
		state.focus_key = 0
	}

	if signal.is_focused && cell.forced == .None {
		Move :: struct {
			key:          platform.Key,
			days, months: int,
		}
		for move in ([]Move{{.Up, -7, 0}, {.Down, 7, 0}, {.Page_Up, 0, -1}, {.Page_Down, 0, 1}}) {
			if !ui.is_key_pressed(move.key) || ui.is_key_taken(move.key) do continue

			moved = add_months(add_days(day, move.days), move.months)
			ui._state.taken_keys += {int(move.key)}
		}
	}

	return signal.is_activated, moved
}

// Shows date^ in the person's short format, or placeholder. Picking a day closes the calendar.
date_picker :: proc(id: string, date: ^Date, placeholder := "No date") -> ui.Signal {
	look, _ := _tone_style(.Base, .Solid)
	look.width = ui.fit_children()
	look.height = ui.points(_BUTTON_HEIGHT_POINTS)
	look.axis = .X
	look.align = .Center
	look.gap = 8
	look.padding = {10, 0, 12, 0}
	look.corner_radius = shape.radius_field
	look.flags = {.Clickable}
	box := ui.box(id, look)
	shown := format_day(date^, "yMMMd") if date^ != {} else placeholder
	box.role, box.label = .Pop_Up, id
	if date^ != {} do box.value = shown
	trigger := ui.signal(box)

	if ui.scope(box) {
		icon_box("calendar", 12, to_faded(look.text_color, 0.7))
		color := look.text_color if date^ != {} else to_faded(look.text_color, 0.5)
		ui.box("", {text_color = color, font_size = 13, font_weight = .Medium}, shown)
	}

	is_open := _window.open_pop_up == box._key
	if trigger.is_activated do is_open = !is_open
	is_changed := false
	if popover(fmt.tprintf("%s_calendar", id), &is_open, box) {
		if ui.col("padding", {padding = 6}) {
			// When the keyboard opens it, focus goes to the picked day, or today.
			if _window.popover.is_focusing_first {
				_window.popover.is_focusing_first = false
				_window.calendars.focus_key = ui._to_key("calendar", ui.current_parent()._seed)
				_window.calendars.focus_day = date^ if date^ != {} else today()
			}
			if calendar("calendar", date).is_changed {
				is_changed = true
				is_open = false
			}
		}
	}

	if is_open {
		_window.open_pop_up = box._key
	} else if _window.open_pop_up == box._key {
		_window.open_pop_up = 0
	}

	signal := trigger
	signal.is_changed = is_changed

	return signal
}
