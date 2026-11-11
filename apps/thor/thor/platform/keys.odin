package platform

// macOS's key code plus one, on a US layout, so 0 is None. Unnamed keys still arrive: to_key(105).
Key :: enum u16 {
	None           = 0,
	A              = 1,
	S              = 2,
	D              = 3,
	F              = 4,
	H              = 5,
	G              = 6,
	Z              = 7,
	X              = 8,
	C              = 9,
	V              = 10,
	B              = 12,
	Q              = 13,
	W              = 14,
	E              = 15,
	R              = 16,
	Y              = 17,
	T              = 18,
	Digit_1        = 19,
	Digit_2        = 20,
	Digit_3        = 21,
	Digit_4        = 22,
	Digit_6        = 23,
	Digit_5        = 24,
	Equal          = 25,
	Digit_9        = 26,
	Digit_7        = 27,
	Minus          = 28,
	Digit_8        = 29,
	Digit_0        = 30,
	Right_Bracket  = 31,
	O              = 32,
	U              = 33,
	Left_Bracket   = 34,
	I              = 35,
	P              = 36,
	Return         = 37,
	L              = 38,
	J              = 39,
	Quote          = 40,
	K              = 41,
	Semicolon      = 42,
	Backslash      = 43,
	Comma          = 44,
	Slash          = 45,
	N              = 46,
	M              = 47,
	Period         = 48,
	Tab            = 49,
	Space          = 50,
	Grave          = 51,
	Delete         = 52,
	Escape         = 54,
	Enter          = 77,
	Home           = 116,
	Page_Up        = 117,
	Forward_Delete = 118,
	End            = 120,
	Page_Down      = 122,
	Left           = 124,
	Right          = 125,
	Down           = 126,
	Up             = 127,
}

to_key :: proc "contextless" (code: u16) -> Key {
	return Key(code + 1)
}

// The text a key types with no modifier, or with Shift. Empty for a key that types none.
to_key_text :: proc(key: Key, is_shifted: bool) -> string {
	#partial switch key {
	case .Return, .Enter:
		return "\r"
	case .Tab:
		return "\t"
	case .Space:
		return " "
	case .Escape:
		return "\x1b"
	case .Delete:
		return "\x7f"
	}

	@(static, rodata) LETTERS := [?]struct {
		key:           Key,
		plain, shifted: string,
	} {
		{.A, "a", "A"}, {.B, "b", "B"}, {.C, "c", "C"}, {.D, "d", "D"}, {.E, "e", "E"},
		{.F, "f", "F"}, {.G, "g", "G"}, {.H, "h", "H"}, {.I, "i", "I"}, {.J, "j", "J"},
		{.K, "k", "K"}, {.L, "l", "L"}, {.M, "m", "M"}, {.N, "n", "N"}, {.O, "o", "O"},
		{.P, "p", "P"}, {.Q, "q", "Q"}, {.R, "r", "R"}, {.S, "s", "S"}, {.T, "t", "T"},
		{.U, "u", "U"}, {.V, "v", "V"}, {.W, "w", "W"}, {.X, "x", "X"}, {.Y, "y", "Y"},
		{.Z, "z", "Z"}, {.Digit_0, "0", ")"}, {.Digit_1, "1", "!"}, {.Digit_2, "2", "@"},
		{.Digit_3, "3", "#"}, {.Digit_4, "4", "$"}, {.Digit_5, "5", "%"}, {.Digit_6, "6", "^"},
		{.Digit_7, "7", "&"}, {.Digit_8, "8", "*"}, {.Digit_9, "9", "("}, {.Equal, "=", "+"},
		{.Minus, "-", "_"}, {.Comma, ",", "<"}, {.Period, ".", ">"}, {.Slash, "/", "?"},
		{.Semicolon, ";", ":"}, {.Quote, "'", "\""}, {.Left_Bracket, "[", "{"},
		{.Right_Bracket, "]", "}"}, {.Backslash, "\\", "|"}, {.Grave, "`", "~"},
	}
	for letter in LETTERS {
		if letter.key == key do return letter.shifted if is_shifted else letter.plain
	}

	return ""
}
