package icon

import "../mac"
import "../render"
import "base:intrinsics"
import "core:hash"
import "core:math"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

_objc_send :: intrinsics.objc_send

@(objc_class = "NSImageSymbolConfiguration")
Symbol_Configuration :: struct {
	using _: NS.Object,
}

@(objc_class = "NSGraphicsContext")
Graphics_Context :: struct {
	using _: NS.Object,
}

_ATLAS_SIZE_PIXELS :: 1024
_SIZE_STEPS_PER_PIXEL :: 4
_PADDING_PIXELS :: 1
_BYTES_PER_PIXEL :: 4
_BITS_PER_CHANNEL :: 8
// kCGImageAlphaPremultipliedLast, from CoreGraphics' CGImageAlphaInfo.
_ALPHA_PREMULTIPLIED_LAST :: 1
// NSFontWeightMedium.
_SYMBOL_WEIGHT :: 0.23
_SOURCE_OVER :: 2

_state: struct {
	atlas:      ^MTL.Texture,
	regions:    map[[2]u64][4]int,
	pen:        [2]int,
	row_height: int,
	is_full:    bool,
	is_fresh:   bool,
}

is_redraw_needed :: proc() -> bool {
	return _state.is_full && !_state.is_fresh
}

begin_frame :: proc() {
	_state.is_fresh = _state.is_full
	if !_state.is_full do return

	clear(&_state.regions)
	_state.pen = {}
	_state.row_height = 0
	_state.is_full = false
}

start :: proc() {
	if _state.atlas != nil do return

	_state.atlas = render.make_texture({_ATLAS_SIZE_PIXELS, _ATLAS_SIZE_PIXELS}, .R8Unorm)
}

draw :: proc(name: string, size_pixels: f32, rect, clip: [4]f32, color: [4]f32) {
	key := [2]u64{hash.fnv64a(transmute([]u8)name), u64(size_pixels * _SIZE_STEPS_PER_PIXEL)}
	region, ok := _state.regions[key]

	if !ok {
		region = _rasterize(name, size_pixels)
		if !_state.is_full do _state.regions[key] = region
	}

	if region.z == 0 do return

	width := f32(region.z)
	height := f32(region.w)
	left := math.round((rect.x + rect.z - width) / 2)
	top := math.round((rect.y + rect.w - height) / 2)
	uv :=
		[4]f32{f32(region.x), f32(region.y), f32(region.x + region.z), f32(region.y + region.w)} /
		_ATLAS_SIZE_PIXELS

	render.push(
		{
			rect = {left, top, left + width, top + height},
			uv = uv,
			color = color,
			clip = clip,
			kind = .Glyph,
		},
		_state.atlas,
	)
}

_rasterize :: proc(name: string, size_pixels: f32) -> [4]int {
	ns_name := NS.String.alloc()->initWithOdinString(name)
	defer ns_name->release()

	symbol := _objc_send(
		^NS.Image,
		NS.Image,
		"imageWithSystemSymbolName:accessibilityDescription:",
		ns_name,
		rawptr(nil),
	)

	if symbol == nil do return {}

	configuration := _objc_send(
		^Symbol_Configuration,
		Symbol_Configuration,
		"configurationWithPointSize:weight:",
		NS.Float(size_pixels),
		NS.Float(_SYMBOL_WEIGHT),
	)
	image := _objc_send(^NS.Image, symbol, "imageWithSymbolConfiguration:", configuration)

	size := _objc_send(NS.Size, image, "size")
	width := int(math.ceil(f64(size.width))) + 2 * _PADDING_PIXELS
	height := int(math.ceil(f64(size.height))) + 2 * _PADDING_PIXELS
	region, ok := _allocate(width, height)

	if !ok {
		_state.is_full = true
		return {}
	}

	pixels := make([]u8, width * height * _BYTES_PER_PIXEL, context.temp_allocator)
	space := mac.CGColorSpaceCreateDeviceRGB()
	defer mac.CGColorSpaceRelease(space)
	bitmap_context := mac.CGBitmapContextCreate(
		raw_data(pixels),
		uint(width),
		uint(height),
		_BITS_PER_CHANNEL,
		uint(width * _BYTES_PER_PIXEL),
		space,
		_ALPHA_PREMULTIPLIED_LAST,
	)
	defer mac.CGContextRelease(bitmap_context)

	graphics := _objc_send(
		^Graphics_Context,
		Graphics_Context,
		"graphicsContextWithCGContext:flipped:",
		rawptr(bitmap_context),
		NS.BOOL(false),
	)

	_objc_send(nil, Graphics_Context, "saveGraphicsState")
	_objc_send(nil, Graphics_Context, "setCurrentContext:", graphics)
	target := NS.Rect{{_PADDING_PIXELS, _PADDING_PIXELS}, size}
	_objc_send(
		nil,
		image,
		"drawInRect:fromRect:operation:fraction:",
		target,
		NS.Rect{},
		NS.UInteger(_SOURCE_OVER),
		NS.Float(1),
	)
	_objc_send(nil, Graphics_Context, "restoreGraphicsState")

	mask := make([]u8, width * height, context.temp_allocator)
	for index in 0 ..< width * height do mask[index] = pixels[index * _BYTES_PER_PIXEL + 3]

	render.upload_texture(_state.atlas, region, raw_data(mask), width)

	return region
}

_allocate :: proc(width, height: int) -> ([4]int, bool) {
	if _state.pen.x + width > _ATLAS_SIZE_PIXELS {
		_state.pen = {0, _state.pen.y + _state.row_height}
		_state.row_height = 0
	}

	if _state.pen.y + height > _ATLAS_SIZE_PIXELS do return {}, false

	region := [4]int{_state.pen.x, _state.pen.y, width, height}
	_state.pen.x += width
	_state.row_height = max(_state.row_height, height)

	return region, true
}
