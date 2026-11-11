package font

import "../mac"
import "../render"
import "base:intrinsics"
import "core:math"
import MTL "vendor:darwin/Metal"

_Atlas_Entry :: struct {
	region: [4]int,
	offset: [2]f32,
}

_Atlas :: struct {
	texture:    ^MTL.Texture,
	size:       int,
	glyphs:     map[[3]u64]_Atlas_Entry,
	pen:        [2]int,
	row_height: int,
}

_ATLAS_SIZE :: 4096

// Holds about 900 emoji at 13 points on a 2x screen. The texture waits for the first one.
_COLOR_ATLAS_SIZE :: 1024

_BYTES_PER_COLOR_PIXEL :: 4

_SUBPIXEL_STEPS :: 4

Color_Proc :: #type proc(utf16_index: int, data: rawptr) -> [4]f32

draw :: proc(
	shaped: ^Shaped_Text,
	origin_pixels: [2]f32,
	color: [4]f32,
	clip_pixels: [4]f32,
	color_of: Color_Proc,
	data: rawptr,
	opacity: f32,
	// The colour under the text, for linear blending's weight correction.
	under: [4]f32 = {},
) {
	for line in shaped.lines {
		baseline_y := math.round(origin_pixels.y + line.baseline_y_pixels)
		is_line_outside :=
			baseline_y - shaped.size_pixels.y > clip_pixels.w ||
			baseline_y + shaped.size_pixels.y < clip_pixels.y

		if is_line_outside do continue

		for glyph in line.glyphs {
			pen_x := origin_pixels.x + glyph.x_pixels
			whole_x := math.floor(pen_x)
			is_color := _state.is_color_font[glyph.font_index]
			// A colour glyph is a picture, so it stays on whole pixels.
			subpixel := 0 if is_color else int((pen_x - whole_x) * _SUBPIXEL_STEPS)
			atlas := &_state.color_atlas if is_color else &_state.atlas
			entry := _find_glyph(atlas, glyph.font_index, glyph.glyph, subpixel, is_color)
			region := entry.region

			if region.z == 0 do continue

			left := whole_x + entry.offset.x
			top := baseline_y + entry.offset.y
			rect := [4]f32{left, top, left + f32(region.z), top + f32(region.w)}
			is_glyph_outside := rect.z < clip_pixels.x || rect.x > clip_pixels.z

			if is_glyph_outside do continue

			uv :=
				[4]f32 {
					f32(region.x),
					f32(region.y),
					f32(region.x + region.z),
					f32(region.y + region.w),
				} /
				f32(atlas.size)

			if is_color {
				render.push(
					{
						rect = rect,
						uv = uv,
						color = {1, 1, 1, opacity},
						clip = clip_pixels,
						kind = .Image,
					},
					atlas.texture,
				)
				continue
			}

			glyph_color := color_of(glyph.utf16_index, data) if color_of != nil else color
			glyph_color.a *= opacity

			render.push(
				{rect = rect, uv = uv, color = glyph_color, clip = clip_pixels, kind = .Glyph, under_color = under},
				atlas.texture,
			)
		}
	}
}

_find_glyph :: proc(
	atlas: ^_Atlas,
	font_index: u16,
	glyph: mac.Glyph,
	subpixel: int,
	is_color: bool,
) -> _Atlas_Entry {
	key := [3]u64{u64(font_index), u64(glyph), u64(subpixel)}

	if entry, ok := atlas.glyphs[key]; ok do return entry

	if atlas.texture == nil {
		atlas.texture = render.make_texture({_COLOR_ATLAS_SIZE, _COLOR_ATLAS_SIZE}, .BGRA8Unorm)
		atlas.size = _COLOR_ATLAS_SIZE
	}

	entry := _rasterize(atlas, _state.fonts[font_index], glyph, subpixel, is_color)
	atlas.glyphs[key] = entry

	return entry
}

_rasterize :: proc(
	atlas: ^_Atlas,
	ct_font: mac.Font_Ref,
	glyph: mac.Glyph,
	subpixel: int,
	is_color: bool,
) -> _Atlas_Entry {
	glyph := glyph
	bounds: mac.Rect

	mac.CTFontGetBoundingRectsForGlyphs(ct_font, 0, &glyph, &bounds, 1)

	has_ink := bounds.size.width > 0 && bounds.size.height > 0

	if !has_ink do return {}

	left := int(math.floor(bounds.origin.x)) - 1
	bottom := int(math.floor(bounds.origin.y)) - 1
	width := int(math.ceil(bounds.origin.x + bounds.size.width)) - left + 2
	height := int(math.ceil(bounds.origin.y + bounds.size.height)) - bottom + 1

	region, ok := _allocate(atlas, width, height)

	if !ok do return {}

	BITS_PER_COMPONENT :: 8
	bytes_per_row := width * _BYTES_PER_COLOR_PIXEL if is_color else width
	pixels := make([]u8, bytes_per_row * height, context.temp_allocator)
	space :=
		mac.CGColorSpaceCreateWithName(mac.kCGColorSpaceSRGB) if is_color else mac.CGColorSpaceCreateDeviceGray()
	defer mac.CGColorSpaceRelease(space)
	// BGRA with premultiplied alpha, as image's textures hold.
	color_info := u32(mac.IMAGE_ALPHA_PREMULTIPLIED_FIRST | mac.BITMAP_BYTE_ORDER_32_LITTLE)
	bitmap_context := mac.CGBitmapContextCreate(
		raw_data(pixels),
		uint(width),
		uint(height),
		BITS_PER_COMPONENT,
		uint(bytes_per_row),
		space,
		color_info if is_color else mac.IMAGE_ALPHA_NONE,
	)
	defer mac.CGContextRelease(bitmap_context)

	mac.CGContextSetAllowsFontSubpixelPositioning(bitmap_context, true)
	mac.CGContextSetShouldSubpixelPositionFonts(bitmap_context, true)
	mac.CGContextSetAllowsFontSubpixelQuantization(bitmap_context, false)
	mac.CGContextSetShouldSubpixelQuantizeFonts(bitmap_context, false)
	mac.CGContextSetGrayFillColor(bitmap_context, 1, 1)

	position := mac.Point{f64(-left) + f64(subpixel) / _SUBPIXEL_STEPS, f64(-bottom)}

	mac.CTFontDrawGlyphs(ct_font, &glyph, &position, 1, bitmap_context)
	render.upload_texture(atlas.texture, region, raw_data(pixels), bytes_per_row)

	// CoreGraphics counts y up from the bottom of the bitmap. The screen counts down from the top.
	return _Atlas_Entry{region, {f32(left), -f32(height + bottom)}}
}

_allocate :: proc(atlas: ^_Atlas, width, height: int) -> ([4]int, bool) {
	if width > atlas.size || height > atlas.size do return {}, false

	if atlas.pen.x + width > atlas.size {
		atlas.pen = {0, atlas.pen.y + atlas.row_height}
		atlas.row_height = 0
	}

	if atlas.pen.y + height > atlas.size {
		clear(&atlas.glyphs)
		atlas.pen = {0, 0}
		atlas.row_height = 0
		_state.is_atlas_reset = true
	}

	region := [4]int{atlas.pen.x, atlas.pen.y, width, height}
	atlas.pen.x += width
	atlas.row_height = max(atlas.row_height, height)

	return region, true
}
