package platform

import "base:intrinsics"
import "core:fmt"
import NS "core:sys/darwin/Foundation"

_COMMAND_MASK :: NS.UInteger(1 << 20)
_OPTION_MASK :: NS.UInteger(1 << 19)

// Edit and View items turn a typed or clicked shortcut into a key press, for text fields and zoom.
install_menu :: proc(app_name: string, has_zoom: bool) {
	bar := NS.Menu.alloc()->init()

	app_menu := _add_menu(bar, app_name)
	_add_item(app_menu, fmt.tprintf("Hide %s", app_name), intrinsics.objc_find_selector("hide:"), "h")
	others := _add_item(app_menu, "Hide Others", intrinsics.objc_find_selector("hideOtherApplications:"), "h")
	objc_send(nil, others, "setKeyEquivalentModifierMask:", _COMMAND_MASK | _OPTION_MASK)
	_add_item(app_menu, "Show All", intrinsics.objc_find_selector("unhideAllApplications:"), "")
	NS.Menu_addItem(app_menu, NS.MenuItem_separatorItem())
	quit := _add_item(app_menu, fmt.tprintf("Quit %s", app_name), intrinsics.objc_find_selector("menuQuit:"), "q")
	NS.MenuItem_setTarget(quit, _state.target)

	edit := _add_menu(bar, "Edit")
	_add_key_item(edit, "Undo", "z", .Z)
	// An upper-case key equivalent adds Shift, so this is ⇧⌘Z.
	_add_key_item(edit, "Redo", "Z", .Z)
	NS.Menu_addItem(edit, NS.MenuItem_separatorItem())
	_add_key_item(edit, "Cut", "x", .X)
	_add_key_item(edit, "Copy", "c", .C)
	_add_key_item(edit, "Paste", "v", .V)
	_add_key_item(edit, "Select All", "a", .A)

	if has_zoom {
		view := _add_menu(bar, "View")
		_add_key_item(view, "Actual Size", "0", .Digit_0)
		_add_key_item(view, "Zoom In", "=", .Equal)
		_add_key_item(view, "Zoom Out", "-", .Minus)
	}

	window := _add_menu(bar, "Window")
	_add_item(window, "Minimize", intrinsics.objc_find_selector("performMiniaturize:"), "m")
	_add_item(window, "Close", intrinsics.objc_find_selector("performClose:"), "w")

	_state.app->setMainMenu(bar)
	objc_send(nil, _state.app, "setWindowsMenu:", window)
}

_add_menu :: proc(bar: ^NS.Menu, title: string) -> ^NS.Menu {
	name := NS.String.alloc()->initWithOdinString(title)
	item := NS.MenuItem.alloc()->init()
	menu := NS.Menu.alloc()->initWithTitle(name)
	NS.Menu_addItem(bar, item)
	NS.Menu_setSubmenu(bar, menu, item)

	return menu
}

// With no target, the action goes to the key window or the app, which know hide: and performClose:.
_add_item :: proc(menu: ^NS.Menu, title: string, action: NS.SEL, key: string) -> ^NS.MenuItem {
	name := NS.String.alloc()->initWithOdinString(title)
	key_name := NS.String.alloc()->initWithOdinString(key)
	item := NS.MenuItem.alloc()->initWithTitle(name, action, key_name)
	NS.Menu_addItem(menu, item)

	return item
}

_add_key_item :: proc(menu: ^NS.Menu, title, key: string, key_code: Key) {
	item := _add_item(menu, title, intrinsics.objc_find_selector("menuKey:"), key)
	NS.MenuItem_setTarget(item, _state.target)
	objc_send(nil, item, "setTag:", NS.Integer(key_code))
}
