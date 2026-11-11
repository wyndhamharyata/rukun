package images

import "../mac"
import "../platform"
import "../render"
import "base:runtime"
import "core:math"
import "core:strings"
import "core:sync"
import "core:thread"
import MTL "vendor:darwin/Metal"

_BYTES_PER_PIXEL :: 4
_BITS_PER_CHANNEL :: 8
_WORKER_TEMP_BYTES :: 256 * 1024

_fetch_image :: proc(task: thread.Task) {
	job := cast(^_Job)task.data
	temp := &runtime.global_default_temp_allocator_data

	// Odin's temp allocator keeps its first block for good. Its default block is 4 MB.
	if temp.arena.curr_block == nil {
		runtime.default_temp_allocator_init(temp, _WORKER_TEMP_BYTES, context.allocator)
	}

	defer {
		sync.guard(&_state.mutex)
		append(&_state.finished, job)
		platform.wake()
	}
	defer free_all(context.temp_allocator)

	path := job.url

	if !strings.has_prefix(path, "/") {
		if _state.fetch == nil do return

		is_fetched: bool
		path, is_fetched = _state.fetch(job.url)
		if !is_fetched do return
	}

	job.texture, job.color = _read_texture(path, job.size_pixels, job.crop)
}

_read_texture :: proc(path: string, size_pixels: int, crop: Crop) -> (^MTL.Texture, Color) {
	url := mac.CFURLCreateFromFileSystemRepresentation(nil, raw_data(path), len(path), false)
	defer mac.CFRelease(url)

	source := mac.CGImageSourceCreateWithURL(url, nil)
	if source == nil do return nil, {}
	defer mac.CFRelease(source)

	max_size_pixels := i32(size_pixels)
	size_number := mac.CFNumberCreate(nil, mac.NUMBER_INT32, &max_size_pixels)
	defer mac.CFRelease(size_number)

	keys := []mac.Type_Ref {
		mac.kCGImageSourceCreateThumbnailFromImageAlways,
		mac.kCGImageSourceThumbnailMaxPixelSize,
		mac.kCGImageSourceCreateThumbnailWithTransform,
	}
	values := []mac.Type_Ref{mac.kCFBooleanTrue, size_number, mac.kCFBooleanTrue}
	options := mac.make_dictionary(keys, values)
	defer mac.CFRelease(options)

	thumbnail := mac.CGImageSourceCreateThumbnailAtIndex(source, 0, options)
	if thumbnail == nil do return nil, {}
	defer mac.CGImageRelease(thumbnail)

	image := _to_cropped(thumbnail, crop)
	defer if image != thumbnail do mac.CGImageRelease(image)

	width := int(mac.CGImageGetWidth(image))
	height := int(mac.CGImageGetHeight(image))
	pixels := make([]u8, width * height * _BYTES_PER_PIXEL, context.temp_allocator)

	space := mac.CGColorSpaceCreateWithName(mac.kCGColorSpaceSRGB)
	defer mac.CGColorSpaceRelease(space)
	bitmap_context := mac.CGBitmapContextCreate(
		raw_data(pixels),
		uint(width),
		uint(height),
		_BITS_PER_CHANNEL,
		uint(width * _BYTES_PER_PIXEL),
		space,
		mac.IMAGE_ALPHA_PREMULTIPLIED_FIRST | mac.BITMAP_BYTE_ORDER_32_LITTLE,
	)
	defer mac.CGContextRelease(bitmap_context)
	mac.CGContextDrawImage(bitmap_context, {{0, 0}, {f64(width), f64(height)}}, image)

	texture := render.make_texture({width, height}, .BGRA8Unorm)
	render.upload_texture(
		texture,
		{0, 0, width, height},
		raw_data(pixels),
		width * _BYTES_PER_PIXEL,
	)

	return texture, _to_color(pixels)
}

_to_cropped :: proc(image: mac.Image_Ref, crop: Crop) -> mac.Image_Ref {
	width := f64(mac.CGImageGetWidth(image))
	height := f64(mac.CGImageGetHeight(image))
	aspect := f64(crop.aspect)
	if aspect <= 0 || height <= 0 do return image

	rect := mac.Rect{{0, 0}, {width, height}}

	switch {
	case width / height > aspect * 1.01:
		rect.size.width = math.round(height * aspect)
		rect.origin.x = math.round((width - rect.size.width) / 2)
	case width / height < aspect * 0.99:
		rect.size.height = math.round(width / aspect)
		rect.origin.y = math.round((height - rect.size.height) * f64(crop.focus_y))
	case:
		return image
	}

	cropped := mac.CGImageCreateWithImageInRect(image, rect)

	return cropped if cropped != nil else image
}
