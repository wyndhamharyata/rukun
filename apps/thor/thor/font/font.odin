package font

import "../mac"
import "../render"
import "base:intrinsics"
import "core:hash"
import "core:math"
import NS "core:sys/darwin/Foundation"

@(objc_class = "NSFont")
NS_Font :: struct {
	using _: NS.Object,
}

// Auto, the zero value, is Regular.
Weight :: enum {
	Auto,
	Regular,
	Medium,
	Semibold,
	Bold,
}

// NSFontWeight values, from NSFontDescriptor.h.
_weight_values := [Weight]f64 {
	.Auto     = 0,
	.Regular  = 0,
	.Medium   = 0.23,
	.Semibold = 0.3,
	.Bold     = 0.4,
}

// SF Pro, or SF Mono, whose letters are all as wide. Auto, the zero value, is System.
Family :: enum {
	Auto,
	System,
	Mono,
}

Font :: struct {
	ct_font:            mac.Font_Ref,
	size_pixels:        f32,
	ascent_pixels:      f32,
	descent_pixels:     f32,
	line_height_pixels: f32,
}

Placed_Glyph :: struct {
	font_index:  u16,
	glyph:       mac.Glyph,
	x_pixels:    f32,
	// A UTF-16 index, as CoreText counts.
	utf16_index: int,
}

Shaped_Line :: struct {
	glyphs:            []Placed_Glyph,
	width_pixels:      f32,
	baseline_y_pixels: f32,
	utf16_range:       [2]int,
}

Shaped_Text :: struct {
	lines:           []Shaped_Line,
	size_pixels:     [2]f32,
	last_used_frame: int,
}

_UNUSED_FRAME_COUNT :: 120

_state: struct {
	fonts:          [dynamic]mac.Font_Ref,
	font_indices:   map[uint]u16,
	system_fonts:   map[[3]u32]Font,
	shaped:         map[u64]^Shaped_Text,
	// Whether each font in fonts draws in colour. Its glyphs go to the colour atlas.
	is_color_font:  [dynamic]bool,
	atlas:          _Atlas,
	color_atlas:    _Atlas,
	frame_index:    int,
	is_atlas_reset: bool,
}

// Starts the atlas once, so glyphs already in it stay valid when headless runs start again.
start :: proc() {
	if _state.atlas.texture != nil do return

	_state.atlas = {
		texture = render.make_texture({_ATLAS_SIZE, _ATLAS_SIZE}, .R8Unorm),
		size    = _ATLAS_SIZE,
	}
}

system_font :: proc(weight: Weight, size_pixels: f32, family := Family.System) -> Font {
	weight := .Regular if weight == .Auto else weight
	family := .System if family == .Auto else family
	size_quarter_pixels := u32(size_pixels * 4)
	key := [3]u32{u32(weight), size_quarter_pixels, u32(family)}

	if font, ok := _state.system_fonts[key]; ok do return font

	ns_font: ^NS_Font
	switch family {
	case .Auto, .System:
		ns_font = intrinsics.objc_send(^NS_Font, NS_Font, "systemFontOfSize:weight:", NS.Float(size_pixels), NS.Float(_weight_values[weight]))
	case .Mono:
		ns_font = intrinsics.objc_send(^NS_Font, NS_Font, "monospacedSystemFontOfSize:weight:", NS.Float(size_pixels), NS.Float(_weight_values[weight]))
	}

	// NSFont and CTFont are the same object.
	ct_font := mac.Font_Ref(mac.CFRetain(mac.Type_Ref(ns_font)))
	ascent := f32(mac.CTFontGetAscent(ct_font))
	descent := f32(mac.CTFontGetDescent(ct_font))
	leading := f32(mac.CTFontGetLeading(ct_font))
	font := Font{ct_font, size_pixels, ascent, descent, math.ceil(ascent + descent + leading)}

	_state.system_fonts[key] = font

	return font
}

_intern_font :: proc(ct_font: mac.Font_Ref) -> u16 {
	key := mac.CFHash(mac.Type_Ref(ct_font))

	if index, ok := _state.font_indices[key]; ok do return index

	mac.CFRetain(mac.Type_Ref(ct_font))
	index := u16(len(_state.fonts))
	append(&_state.fonts, ct_font)
	is_color := mac.CTFontGetSymbolicTraits(ct_font) & mac.FONT_TRAIT_COLOR_GLYPHS != 0
	append(&_state.is_color_font, is_color)
	_state.font_indices[key] = index

	return index
}

begin_frame :: proc() {
	_state.frame_index += 1
	_state.is_atlas_reset = false

	if _state.frame_index % _UNUSED_FRAME_COUNT != 0 do return

	for key, shaped in _state.shaped {
		if _state.frame_index - shaped.last_used_frame < _UNUSED_FRAME_COUNT do continue

		_free_shaped(shaped)
		delete_key(&_state.shaped, key)
	}
}

is_redraw_needed :: proc() -> bool {
	return _state.is_atlas_reset
}

_free_shaped :: proc(shaped: ^Shaped_Text) {
	for line in shaped.lines do delete(line.glyphs)
	delete(shaped.lines)
	free(shaped)
}

Overflow :: enum {
	Wrap,
	Truncate,
}

// kCTLineTruncationEnd
_TRUNCATE_END :: 1

shape_text :: proc(
	text: string,
	font: Font,
	max_width_pixels: f32 = 0,
	overflow := Overflow.Wrap,
	// 0 uses the font's own line height.
	line_height_pixels: f32 = 0,
) -> ^Shaped_Text {
	line_height := line_height_pixels if line_height_pixels > 0 else font.line_height_pixels
	key :=
		hash.fnv64a(transmute([]u8)text) ~
		(u64(mac.CFHash(mac.Type_Ref(font.ct_font))) * 31) ~
		(u64(max_width_pixels) << 40) ~
		(u64(overflow) << 62) ~
		(u64(line_height_pixels) * 0x9e3779b97f4a7c15)

	if shaped, ok := _state.shaped[key]; ok {
		shaped.last_used_frame = _state.frame_index
		return shaped
	}

	shaped := new(Shaped_Text)
	shaped.last_used_frame = _state.frame_index
	_state.shaped[key] = shaped

	cf_text := mac.to_cf_string(text) if len(text) > 0 else nil

	if cf_text == nil {
		shaped.size_pixels = {0, line_height}
		return shaped
	}

	defer mac.CFRelease(cf_text)
	keys := []mac.Type_Ref{mac.Type_Ref(mac.kCTFontAttributeName)}
	values := []mac.Type_Ref{mac.Type_Ref(font.ct_font)}
	attributes := mac.make_dictionary(keys, values)
	defer mac.CFRelease(attributes)
	attributed := mac.CFAttributedStringCreate(nil, cf_text, attributes)
	defer mac.CFRelease(attributed)

	lines: [dynamic]Shaped_Line
	is_wrapped := max_width_pixels > 0 && overflow == .Wrap

	if !is_wrapped {
		ct_line := mac.CTLineCreateWithAttributedString(attributed)
		defer mac.CFRelease(ct_line)

		// macOS truncates nothing narrower than its ellipsis: it returns no line at all.
		is_fitting := f32(mac.CTLineGetTypographicBounds(ct_line, nil, nil, nil)) <= max_width_pixels
		if max_width_pixels <= 0 || is_fitting {
			append(&lines, _to_shaped_line(ct_line, font, 0, line_height))
		} else if line := _make_truncated_line(ct_line, attributes, max_width_pixels);
		   line != nil {
			append(&lines, _to_shaped_line(line, font, 0, line_height))
			mac.CFRelease(line)
		}
	} else {
		typesetter := mac.CTTypesetterCreateWithAttributedString(attributed)
		defer mac.CFRelease(typesetter)
		utf16_count := mac.CFStringGetLength(cf_text)

		for start := 0; start < utf16_count; {
			count := mac.CTTypesetterSuggestLineBreak(typesetter, start, f64(max_width_pixels))
			if count <= 0 do break

			ct_line := mac.CTTypesetterCreateLine(typesetter, {start, count})
			top_y := f32(len(lines)) * line_height
			append(&lines, _to_shaped_line(ct_line, font, top_y, line_height))
			mac.CFRelease(ct_line)
			start += count
		}
	}

	width: f32
	for line in lines do width = max(width, line.width_pixels)

	shaped.lines = lines[:]
	shaped.size_pixels = {width, f32(len(lines)) * line_height}

	return shaped
}

_make_truncated_line :: proc(
	ct_line: mac.Line_Ref,
	attributes: mac.Dictionary_Ref,
	max_width_pixels: f32,
) -> mac.Line_Ref {
	ellipsis := mac.to_cf_string("…")
	defer mac.CFRelease(ellipsis)
	ellipsis_attributed := mac.CFAttributedStringCreate(nil, ellipsis, attributes)
	defer mac.CFRelease(ellipsis_attributed)
	ellipsis_line := mac.CTLineCreateWithAttributedString(ellipsis_attributed)
	defer mac.CFRelease(ellipsis_line)

	return mac.CTLineCreateTruncatedLine(
		ct_line,
		f64(max_width_pixels),
		_TRUNCATE_END,
		ellipsis_line,
	)
}

_to_shaped_line :: proc(
	ct_line: mac.Line_Ref,
	font: Font,
	top_y, line_height: f32,
) -> Shaped_Line {
	ascent, descent, leading: f64
	width := f32(mac.CTLineGetTypographicBounds(ct_line, &ascent, &descent, &leading))
	string_range := mac.CTLineGetStringRange(ct_line)
	runs := mac.CTLineGetGlyphRuns(ct_line)
	glyphs: [dynamic]Placed_Glyph

	for run_index in 0 ..< mac.CFArrayGetCount(runs) {
		run := mac.Run_Ref(mac.CFArrayGetValueAtIndex(runs, run_index))
		count := mac.CTRunGetGlyphCount(run)
		run_font := mac.Font_Ref(
			mac.CFDictionaryGetValue(
				mac.CTRunGetAttributes(run),
				mac.Type_Ref(mac.kCTFontAttributeName),
			),
		)
		font_index := _intern_font(run_font)

		ids := make([]mac.Glyph, count, context.temp_allocator)
		positions := make([]mac.Point, count, context.temp_allocator)
		indices := make([]mac.Index, count, context.temp_allocator)

		mac.CTRunGetGlyphs(run, {0, 0}, raw_data(ids))
		mac.CTRunGetPositions(run, {0, 0}, raw_data(positions))
		mac.CTRunGetStringIndices(run, {0, 0}, raw_data(indices))

		for index in 0 ..< count {
			append(
				&glyphs,
				Placed_Glyph{font_index, ids[index], f32(positions[index].x), indices[index]},
			)
		}
	}

	leading_pixels := line_height - font.ascent_pixels - font.descent_pixels
	baseline_y := top_y + math.round(leading_pixels / 2 + font.ascent_pixels)
	utf16_range := [2]int{string_range.location, string_range.location + string_range.length}

	return Shaped_Line{glyphs[:], width, baseline_y, utf16_range}
}

// In pixels from the line start. An index past the last character gives the line end.
caret_x :: proc(line: Shaped_Line, utf16_index: int) -> f32 {
	for glyph in line.glyphs {
		if glyph.utf16_index >= utf16_index do return glyph.x_pixels
	}

	return line.width_pixels
}

// The UTF-16 index of the caret place on the line nearest x_pixels.
// shortcut: it reads glyphs left to right only. Use CoreText hit testing for right-to-left text.
index_at_x :: proc(line: Shaped_Line, x_pixels: f32) -> int {
	for glyph, index in line.glyphs {
		next := line.glyphs[index + 1].x_pixels if index + 1 < len(line.glyphs) else line.width_pixels
		if x_pixels < (glyph.x_pixels + next) / 2 do return glyph.utf16_index
	}

	return line.utf16_range[1]
}

// The UTF-16 index, as CoreText counts, of a byte offset into text.
to_utf16_index :: proc(text: string, byte_index: int) -> int {
	count := 0
	for letter, at in text {
		if at >= byte_index do break
		count += 2 if letter > 0xffff else 1
	}

	return count
}

// The byte offset into text of a UTF-16 index, as CoreText counts.
to_byte_index :: proc(text: string, utf16_index: int) -> int {
	count := 0
	for letter, at in text {
		if count >= utf16_index do return at
		count += 2 if letter > 0xffff else 1
	}

	return len(text)
}
