package platform

import "base:intrinsics"
import "core:path/filepath"
import "core:strings"
import "core:time"
import NS "core:sys/darwin/Foundation"

_PLAIN_TEXT_TYPE :: "public.utf8-plain-text"

@(objc_class = "NSDateFormatter")
Date_Formatter :: struct {
	using _: NS.Object,
}

@(objc_class = "NSCalendar")
_NS_Calendar :: struct {
	using _: NS.Object,
}

@(objc_class = "NSTimeZone")
Time_Zone :: struct {
	using _: NS.Object,
}

@(objc_class = "NSPasteboard")
Pasteboard :: struct {
	using _: NS.Object,
}

// The .app's Resources folder, or resources/ beside the executable when running from a build.
resource_folder :: proc() -> string {
	@(static) folder: string
	if folder != "" do return folder

	bundle := NS.Bundle.mainBundle()
	if strings.has_suffix(bundle->bundlePath()->odinString(), ".app") {
		folder = strings.clone(bundle->resourcePath()->odinString())
		return folder
	}

	// macOS treats a folder named like the executable, such as gallery/gallery from odin test,
	// as an old-style bundle with its own Resources folder, so use the executable's path.
	executable := objc_send(^NS.String, bundle, "executablePath")->odinString()
	folder = strings.concatenate({filepath.dir(executable), "/resources"})

	return folder
}

// A number kept in the app's defaults across launches.
read_setting :: proc(key: string) -> (value: f64, ok: bool) {
	if _headless.is_on do return 0, false

	defaults := NS.UserDefaults.standardUserDefaults()
	name := NS.String.alloc()->initWithOdinString(key)
	defer name->release()

	if objc_send(NS.id, defaults, "objectForKey:", name) == nil do return 0, false

	return f64(objc_send(NS.Float, defaults, "doubleForKey:", name)), true
}

save_setting :: proc(key: string, value: f64) {
	if _headless.is_on do return

	defaults := NS.UserDefaults.standardUserDefaults()
	name := NS.String.alloc()->initWithOdinString(key)
	defer name->release()

	objc_send(nil, defaults, "setDouble:forKey:", NS.Float(value), name)
}

read_clipboard :: proc() -> string {
	if _headless.is_on do return strings.clone(_headless.clipboard, context.temp_allocator)

	board := objc_send(^Pasteboard, Pasteboard, "generalPasteboard")
	text := objc_send(^NS.String, board, "stringForType:", NS.AT(_PLAIN_TEXT_TYPE))

	if text == nil do return ""

	return strings.clone(text->odinString(), context.temp_allocator)
}

_date_formatters: map[string]^Date_Formatter

format_date :: proc(unix_ms: f64, template: string) -> string {
	formatter := _date_formatters[template] or_else nil

	if formatter == nil {
		formatter = objc_send(
			^Date_Formatter,
			objc_send(^Date_Formatter, Date_Formatter, "alloc"),
			"init",
		)

		ns_template := NS.String.alloc()->initWithOdinString(template)
		defer ns_template->release()
		objc_send(nil, formatter, "setLocalizedDateFormatFromTemplate:", ns_template)

		_date_formatters[strings.clone(template)] = formatter
	}

	date := objc_send(
		^NS.Object,
		NS.Date,
		"dateWithTimeIntervalSince1970:",
		NS.TimeInterval(unix_ms / 1000),
	)
	text := objc_send(^NS.String, formatter, "stringFromDate:", date)

	return strings.clone(text->odinString(), context.temp_allocator)
}

read_local_offset_seconds :: proc() -> int {
	zone := objc_send(^Time_Zone, Time_Zone, "localTimeZone")

	return int(objc_send(NS.Integer, zone, "secondsFromGMT"))
}

set_clipboard :: proc(text: string) {
	if _headless.is_on {
		delete(_headless.clipboard)
		_headless.clipboard = strings.clone(text)
		return
	}

	board := objc_send(^Pasteboard, Pasteboard, "generalPasteboard")

	objc_send(NS.Integer, board, "clearContents")

	ns_text := NS.String.alloc()->initWithOdinString(text)
	defer ns_text->release()
	objc_send(NS.BOOL, board, "setString:forType:", ns_text, NS.AT(_PLAIN_TEXT_TYPE))
}

// The date used with no screen, so a calendar draws the same every run.
HEADLESS_TODAY :: [3]int{2026, 11, 10}

// Today in the person's time zone, as year, month, and day.
read_today :: proc() -> [3]int {
	if _headless.is_on do return HEADLESS_TODAY

	local := time.time_add(time.now(), time.Duration(read_local_offset_seconds()) * time.Second)
	year, month, day := time.date(local)

	return {year, int(month), day}
}

// The region's first weekday: 1 for Sunday, 2 for Monday; Sunday with no screen.
read_first_weekday :: proc() -> int {
	if _headless.is_on do return 1

	calendar := objc_send(^NS.Object, _NS_Calendar, "currentCalendar")

	return int(objc_send(NS.UInteger, calendar, "firstWeekday"))
}
