package images

import "../mac"

// pixels are BGRA with premultiplied alpha, as the renderer makes them.
write_png :: proc(path: string, pixels: []u8, size: [2]int) -> bool {
	assert(len(pixels) == size.x * size.y * _BYTES_PER_PIXEL, "write_png takes 4 bytes a pixel")

	space := mac.CGColorSpaceCreateWithName(mac.kCGColorSpaceSRGB)
	defer mac.CGColorSpaceRelease(space)
	bitmap_context := mac.CGBitmapContextCreate(
		raw_data(pixels),
		uint(size.x),
		uint(size.y),
		_BITS_PER_CHANNEL,
		uint(size.x * _BYTES_PER_PIXEL),
		space,
		mac.IMAGE_ALPHA_PREMULTIPLIED_FIRST | mac.BITMAP_BYTE_ORDER_32_LITTLE,
	)
	if bitmap_context == nil do return false
	defer mac.CGContextRelease(bitmap_context)

	picture := mac.CGBitmapContextCreateImage(bitmap_context)
	if picture == nil do return false
	defer mac.CGImageRelease(picture)

	url := mac.CFURLCreateFromFileSystemRepresentation(nil, raw_data(path), len(path), false)
	defer mac.CFRelease(url)
	kind := mac.to_cf_string("public.png")
	defer mac.CFRelease(kind)

	destination := mac.CGImageDestinationCreateWithURL(url, kind, 1, nil)
	if destination == nil do return false
	defer mac.CFRelease(destination)

	mac.CGImageDestinationAddImage(destination, picture, nil)

	return bool(mac.CGImageDestinationFinalize(destination))
}

// It returns pixels in the write_png layout, from the temp allocator.
read_png :: proc(path: string) -> (pixels: []u8, size: [2]int, ok: bool) {
	url := mac.CFURLCreateFromFileSystemRepresentation(nil, raw_data(path), len(path), false)
	defer mac.CFRelease(url)

	source := mac.CGImageSourceCreateWithURL(url, nil)
	if source == nil do return
	defer mac.CFRelease(source)

	picture := mac.CGImageSourceCreateImageAtIndex(source, 0, nil)
	if picture == nil do return
	defer mac.CGImageRelease(picture)

	size = {int(mac.CGImageGetWidth(picture)), int(mac.CGImageGetHeight(picture))}
	pixels = make([]u8, size.x * size.y * _BYTES_PER_PIXEL, context.temp_allocator)

	space := mac.CGColorSpaceCreateWithName(mac.kCGColorSpaceSRGB)
	defer mac.CGColorSpaceRelease(space)
	bitmap_context := mac.CGBitmapContextCreate(
		raw_data(pixels),
		uint(size.x),
		uint(size.y),
		_BITS_PER_CHANNEL,
		uint(size.x * _BYTES_PER_PIXEL),
		space,
		mac.IMAGE_ALPHA_PREMULTIPLIED_FIRST | mac.BITMAP_BYTE_ORDER_32_LITTLE,
	)
	if bitmap_context == nil do return
	defer mac.CGContextRelease(bitmap_context)
	mac.CGContextDrawImage(bitmap_context, {{0, 0}, {f64(size.x), f64(size.y)}}, picture)

	return pixels, size, true
}
