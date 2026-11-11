package platform

import NS "core:sys/darwin/Foundation"

// Auto, the zero value, inherits the parent box's cursor.
Cursor :: enum {
	Auto,
	Arrow,
	I_Beam,
	Pointing_Hand,
	Resize_Left_Right,
	Resize_Up_Down,
	Not_Allowed,
}

@(objc_class = "NSCursor")
_NS_Cursor :: struct {
	using _: NS.Object,
}

set_cursor :: proc(cursor: Cursor) {
	if _headless.is_on do return

	shape: ^NS.Object
	switch cursor {
	case .Auto, .Arrow:
		shape = objc_send(^NS.Object, _NS_Cursor, "arrowCursor")
	case .I_Beam:
		shape = objc_send(^NS.Object, _NS_Cursor, "IBeamCursor")
	case .Pointing_Hand:
		shape = objc_send(^NS.Object, _NS_Cursor, "pointingHandCursor")
	case .Resize_Left_Right:
		shape = objc_send(^NS.Object, _NS_Cursor, "resizeLeftRightCursor")
	case .Resize_Up_Down:
		shape = objc_send(^NS.Object, _NS_Cursor, "resizeUpDownCursor")
	case .Not_Allowed:
		shape = objc_send(^NS.Object, _NS_Cursor, "operationNotAllowedCursor")
	}
	objc_send(nil, shape, "set")
}
