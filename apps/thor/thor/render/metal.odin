package render

import "base:intrinsics"
import "core:fmt"
import "core:mem"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"

Kind :: enum u32 {
	Solid = 0,
	Glyph = 1,
	Image = 2,
}

// This struct matches Instance in shaders.metal.
Instance :: struct {
	rect:          [4]f32,
	uv:            [4]f32,
	color:         [4]f32,
	border_color:  [4]f32,
	clip:          [4]f32,
	corner_radius: f32,
	border_width:  f32,
	softness:      f32,
	kind:          Kind,
	end_color:     [4]f32,
	gradient:      [2]f32,
	// Turns a Solid rect about its centre, in radians, clockwise on the screen.
	rotation:      f32,
	gradient_kind: Gradient_Kind,
	// Under a glyph: with linear blending, it keeps the text's weight as Ghostty does.
	under_color:   [4]f32,
}

// The zero value runs from color to end_color down the gradient fractions, with ease in and out.
Gradient_Kind :: bit_set[Gradient_Flag; u32]

Gradient_Flag :: enum u32 {
	// Left to right, in place of top to bottom.
	Across,
	// At a steady rate, as a colour ramp needs.
	Linear,
}

#assert(size_of(Instance) == 144)

_Batch :: struct {
	texture:     ^MTL.Texture,
	first_index: int,
	count:       int,
	// Erases what is under its instances, so glass behind the window shows through.
	is_clear:    bool,
}

_FRAMES_IN_FLIGHT :: 3
_MAX_INSTANCE_COUNT :: 64 * 1024
INITIAL_INSTANCE_COUNT :: 8 * 1024
_QUAD_VERTEX_COUNT :: 4
_BYTES_PER_PIXEL :: 4

// A window draws into it. It keeps the last frame, so a frame that matches it can skip drawing.
Surface :: struct {
	layer:              ^CA.MetalLayer,
	buffers:            [_FRAMES_IN_FLIGHT]^MTL.Buffer,
	command_buffers:    [_FRAMES_IN_FLIGHT]^MTL.CommandBuffer,
	frame_index:        int,
	size_pixels:        [2]f32,
	shown_instances:    [dynamic]Instance,
	shown_batches:      [dynamic]_Batch,
	shown_size_pixels:  [2]f32,
	shown_upload_count: int,
	shown_color_flags:  u32,
}

_state: struct {
	device:        ^MTL.Device,
	queue:         ^MTL.CommandQueue,
	// By [is linear][is clear].
	pipelines:     [2][2]^MTL.RenderPipelineState,
	color_flags:   u32,
	sampler:       ^MTL.SamplerState,
	white_texture: ^MTL.Texture,
	// The current frame, for the target in use.
	instances:     [dynamic]Instance,
	batches:       [dynamic]_Batch,
	upload_count:  int,
	surface:       ^Surface,
}

_shader_source := #load("shaders.metal", string)

// layer can be nil when there is no screen. Call use_surface to draw into the surface.
make_surface :: proc(layer: ^CA.MetalLayer) -> ^Surface {
	target := new(Surface)
	target.layer = layer
	for &buffer in target.buffers {
		buffer = _state.device->newBufferWithLength(INITIAL_INSTANCE_COUNT * size_of(Instance), {})
	}

	return target
}

use_surface :: proc(target: ^Surface) {
	_state.surface = target
}

// Frees the target after the GPU finishes its frames.
destroy_surface :: proc(target: ^Surface) {
	for command_buffer in target.command_buffers {
		if command_buffer == nil do continue

		command_buffer->waitUntilCompleted()
		command_buffer->release()
	}
	for buffer in target.buffers do buffer->release()
	delete(target.shown_instances)
	delete(target.shown_batches)
	if _state.surface == target do _state.surface = nil
	free(target)
}

// Every window shares the renderer. Later calls, such as from each headless run, do nothing.
start :: proc(device: ^MTL.Device) {
	if _state.device != nil do return

	_state.device = device
	_state.queue = device->newCommandQueue()

	library, library_error := device->newLibraryWithSource(
		NS.String.alloc()->initWithOdinString(_shader_source),
		nil,
	)

	if library == nil {
		fmt.panicf(
			"render: shaders do not compile: %s",
			library_error->localizedDescription()->odinString(),
		)
	}

	descriptor := MTL.RenderPipelineDescriptor.alloc()->init()
	descriptor->setVertexFunction(library->newFunctionWithName(NS.AT("vertex_main")))
	descriptor->setFragmentFunction(library->newFunctionWithName(NS.AT("fragment_main")))

	// The shaders return premultiplied colour. A clear pipeline keeps only the part of the colour
	// under each shape that the shape does not cover. An sRGB target blends in linear light.
	attachment := descriptor->colorAttachments()->object(0)
	attachment->setBlendingEnabled(true)
	attachment->setDestinationRGBBlendFactor(.OneMinusSourceAlpha)
	attachment->setDestinationAlphaBlendFactor(.OneMinusSourceAlpha)
	for is_linear in 0 ..< 2 {
		attachment->setPixelFormat(.BGRA8Unorm_sRGB if is_linear == 1 else .BGRA8Unorm)
		for is_clear in 0 ..< 2 {
			source := MTL.BlendFactor.Zero if is_clear == 1 else .One
			attachment->setSourceRGBBlendFactor(source)
			attachment->setSourceAlphaBlendFactor(source)
			pipeline, pipeline_error := device->newRenderPipelineStateWithDescriptor(descriptor)
			if pipeline == nil {
				fmt.panicf("render: no pipeline: %s", pipeline_error->localizedDescription()->odinString())
			}
			_state.pipelines[is_linear][is_clear] = pipeline
		}
	}

	sampler_descriptor := MTL.SamplerDescriptor.alloc()->init()
	sampler_descriptor->setMinFilter(.Linear)
	sampler_descriptor->setMagFilter(.Linear)
	_state.sampler = device->newSamplerState(sampler_descriptor)

	white := [4]u8{255, 255, 255, 255}
	_state.white_texture = make_texture({1, 1}, .RGBA8Unorm)
	upload_texture(_state.white_texture, {0, 0, 1, 1}, raw_data(white[:]), _BYTES_PER_PIXEL)
}

make_texture :: proc(size_pixels: [2]int, format: MTL.PixelFormat) -> ^MTL.Texture {
	// The image threads have no autorelease pool of their own. Metal autoreleases the descriptor.
	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->drain()

	descriptor := MTL.TextureDescriptor.texture2DDescriptorWithPixelFormat(
		format,
		NS.UInteger(size_pixels.x),
		NS.UInteger(size_pixels.y),
		false,
	)

	descriptor->setUsage({.ShaderRead})

	return _state.device->newTextureWithDescriptor(descriptor)
}

upload_texture :: proc(texture: ^MTL.Texture, region: [4]int, pixels: rawptr, bytes_per_row: int) {
	mtl_region := MTL.Region {
		{NS.Integer(region.x), NS.Integer(region.y), 0},
		{NS.Integer(region.z), NS.Integer(region.w), 1},
	}

	texture->replaceRegion(mtl_region, 0, pixels, NS.UInteger(bytes_per_row))
	intrinsics.atomic_add(&_state.upload_count, 1)
}

// is_linear blends in linear light. is_p3 writes Display P3 for a layer in that colour space.
set_color_mode :: proc(is_linear, is_p3: bool) {
	_state.color_flags = (1 if is_linear else 0) | (2 if is_p3 else 0)
}

_to_pixel_format :: proc() -> MTL.PixelFormat {
	return .BGRA8Unorm_sRGB if _state.color_flags & 1 != 0 else .BGRA8Unorm
}

begin_frame :: proc(size_pixels: [2]f32) {
	_state.surface.size_pixels = size_pixels
	layer := _state.surface.layer
	if layer != nil && layer->pixelFormat() != _to_pixel_format() do layer->setPixelFormat(_to_pixel_format())
	clear(&_state.instances)
	clear(&_state.batches)
}

// One instance with the texture it draws with, as ui keeps a box's last frame to draw it again.
Pushed :: struct {
	instance: Instance,
	texture:  ^MTL.Texture,
}

pushed_count :: proc() -> int {
	return len(_state.instances)
}

// Appends every instance pushed from index first on, with its texture.
read_pushed :: proc(first: int, into: ^[dynamic]Pushed) {
	for batch in _state.batches {
		if batch.is_clear do continue
		for index in max(first, batch.first_index) ..< batch.first_index + batch.count {
			append(into, Pushed{_state.instances[index], batch.texture})
		}
	}
}

push :: proc(instance: Instance, texture: ^MTL.Texture = nil) {
	if len(_state.instances) >= _MAX_INSTANCE_COUNT do return

	texture := texture if texture != nil else _state.white_texture
	batch_count := len(_state.batches)
	is_after_clear := batch_count > 0 && _state.batches[batch_count - 1].is_clear
	is_same_texture := batch_count > 0 && _state.batches[batch_count - 1].texture == texture
	can_join := !is_after_clear && (is_same_texture || (batch_count > 0 && instance.kind == .Solid))

	if can_join {
		_state.batches[batch_count - 1].count += 1
	} else {
		append(&_state.batches, _Batch{texture, len(_state.instances), 1, false})
	}

	append(&_state.instances, instance)
}

// Erases a rounded rect of what the frame drew so far, in pixels.
push_clear :: proc(rect: [4]f32, corner_radius: f32, clip: [4]f32) {
	if len(_state.instances) >= _MAX_INSTANCE_COUNT do return

	append(&_state.batches, _Batch{_state.white_texture, len(_state.instances), 1, true})
	append(&_state.instances, Instance{rect = rect, color = {0, 0, 0, 1}, corner_radius = corner_radius, clip = clip})
}

_encode_pass :: proc(
	command_buffer: ^MTL.CommandBuffer,
	target: ^MTL.Texture,
	buffer: ^MTL.Buffer,
) {
	pass := MTL.RenderPassDescriptor.renderPassDescriptor()
	color := pass->colorAttachments()->object(0)
	color->setTexture(target)
	color->setLoadAction(.Clear)
	color->setClearColor({0, 0, 0, 0})
	color->setStoreAction(.Store)

	encoder := command_buffer->renderCommandEncoderWithDescriptor(pass)
	is_linear := 1 if _state.color_flags & 1 != 0 else 0
	encoder->setRenderPipelineState(_state.pipelines[is_linear][0])
	flags := _state.color_flags
	encoder->setFragmentBytes(([^]byte)(&flags)[:size_of(flags)], 1)
	encoder->setVertexBuffer(buffer, 0, 0)
	encoder->setFragmentBuffer(buffer, 0, 0)

	viewport := _state.surface.size_pixels
	encoder->setVertexBytes(([^]byte)(&viewport)[:size_of(viewport)], 1)
	encoder->setFragmentSamplerState(_state.sampler, 0)

	is_clearing := false
	for batch in _state.batches {
		if batch.is_clear != is_clearing {
			is_clearing = batch.is_clear
			encoder->setRenderPipelineState(_state.pipelines[is_linear][1 if is_clearing else 0])
		}
		encoder->setFragmentTexture(batch.texture, 0)
		encoder->drawPrimitivesWithInstances(
			.TriangleStrip,
			0,
			_QUAD_VERTEX_COUNT,
			NS.UInteger(batch.count),
			NS.UInteger(batch.first_index),
		)
	}

	encoder->endEncoding()
}

// For headless snapshots: it draws the last frame into memory, BGRA with premultiplied alpha.
read_pixels :: proc(allocator := context.allocator) -> (pixels: []u8, size: [2]int) {
	target := _state.surface
	if target == nil || target.frame_index == 0 do return

	size = {int(target.size_pixels.x), int(target.size_pixels.y)}
	descriptor := MTL.TextureDescriptor.texture2DDescriptorWithPixelFormat(
		_to_pixel_format(),
		NS.UInteger(size.x),
		NS.UInteger(size.y),
		false,
	)

	descriptor->setUsage({.RenderTarget, .ShaderRead})
	descriptor->setStorageMode(.Shared)

	texture := _state.device->newTextureWithDescriptor(descriptor)
	defer texture->release()

	buffer := target.buffers[(target.frame_index - 1) % _FRAMES_IN_FLIGHT]
	command_buffer := _state.queue->commandBuffer()
	_encode_pass(command_buffer, texture, buffer)
	command_buffer->commit()
	command_buffer->waitUntilCompleted()

	pixels = make([]u8, size.x * size.y * _BYTES_PER_PIXEL, allocator)
	region := MTL.Region{{0, 0, 0}, {NS.Integer(size.x), NS.Integer(size.y), 1}}
	texture->getBytes(raw_data(pixels), NS.UInteger(size.x * _BYTES_PER_PIXEL), region, 0)

	return
}

_is_same_as_shown :: proc(target: ^Surface, upload_count: int) -> bool {
	batch_bytes := mem.slice_to_bytes(_state.batches[:])
	instance_bytes := mem.slice_to_bytes(_state.instances[:])
	is_same_size := target.size_pixels == target.shown_size_pixels && _state.color_flags == target.shown_color_flags
	is_unchanged := upload_count == target.shown_upload_count
	is_same_batches := mem.compare(batch_bytes, mem.slice_to_bytes(target.shown_batches[:])) == 0
	is_same_instances :=
		mem.compare(instance_bytes, mem.slice_to_bytes(target.shown_instances[:])) == 0

	return is_same_size && is_unchanged && is_same_batches && is_same_instances
}

end_frame :: proc(drawable: ^CA.MetalDrawable) {
	target := _state.surface
	upload_count := intrinsics.atomic_load(&_state.upload_count)

	if drawable != nil && _is_same_as_shown(target, upload_count) do return

	slot := target.frame_index % _FRAMES_IN_FLIGHT
	target.frame_index += 1

	if previous := target.command_buffers[slot]; previous != nil {
		previous->waitUntilCompleted()
		previous->release()
		target.command_buffers[slot] = nil
	}

	buffer := target.buffers[slot]
	needed_bytes := len(_state.instances) * size_of(Instance)

	if int(buffer->length()) < needed_bytes {
		capacity := int(buffer->length())
		for capacity < needed_bytes do capacity *= 2
		buffer->release()
		buffer = _state.device->newBufferWithLength(NS.UInteger(capacity), {})
		target.buffers[slot] = buffer
	}

	intrinsics.mem_copy_non_overlapping(
		buffer->contentsPointer(),
		raw_data(_state.instances),
		needed_bytes,
	)

	if drawable == nil do return

	command_buffer := _state.queue->commandBuffer()
	_encode_pass(command_buffer, drawable->texture(), buffer)
	command_buffer->presentDrawable(drawable)
	command_buffer->commit()
	command_buffer->retain()
	target.command_buffers[slot] = command_buffer

	_state.instances, target.shown_instances = target.shown_instances, _state.instances
	_state.batches, target.shown_batches = target.shown_batches, _state.batches
	// A frame drawn during a resize has the old size of the drawable. The layer stretches it.
	texture := drawable->texture()
	target.shown_size_pixels = {f32(texture->width()), f32(texture->height())}
	target.shown_upload_count = upload_count
	target.shown_color_flags = _state.color_flags
}
