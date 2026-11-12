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
	// A Gaussian blur of the rounded rect, as wide as softness.
	Shadow = 3,
}

// Must match Instance in shaders.metal.
Instance :: struct {
	rect:          [4]f32,
	uv:            [4]f32,
	color:         [4]f32,
	border_color:  [4]f32,
	clip:          [4]f32,
	// Top left, top right, bottom right, bottom left.
	corner_radius: [4]f32,
	border_width:  f32,
	softness:      f32,
	kind:          Kind,
	// Scales every layer's alpha, as the instance's own colors carry its fade.
	layer_opacity: f32,
	end_color:     [4]f32,
	gradient:      [2]f32,
	// Spins a Solid rect about its center, in radians, clockwise on screen.
	rotation:      f32,
	gradient_kind: Gradient_Kind,
	// The color under a glyph. With linear blending it keeps the text's weight, as Ghostty does.
	under_color:   [4]f32,
	// push sets them from its layers.
	layer_first:   u32,
	layer_count:   u32,
	_:             [2]u32,
}

MAX_LAYERS :: 4

Layer_Kind :: enum u32 {
	None,
	Gradient,
	Texture,
	Surface,
}

// One layer of a Solid instance, drawn over its color in order. Must match Layer in shaders.metal.
Layer_Data :: struct {
	kind:     Layer_Kind,
	// Normal, Multiply, Screen, Overlay, Soft_Light, as ui.Blend.
	blend:    u32,
	is_tiled: b32,
	// A texture's opacity, or a surface's depth in pixels.
	amount:   f32,
	// A gradient's start color, or a surface's light color.
	from:     [4]f32,
	to:       [4]f32,
	// A gradient's stops in xy and angle in radians in z, or a surface's light angle in z.
	shape:    [4]f32,
	// The image region that fills the box, or one tile's size in pixels in xy.
	uv:       [4]f32,
}

#assert(size_of(Layer_Data) == 80)

Layer :: struct {
	data:    Layer_Data,
	texture: ^MTL.Texture,
}

// With no flags, the gradient runs top to bottom from color to end_color, easing in and out.
Gradient_Kind :: bit_set[Gradient_Flag; u32]

Gradient_Flag :: enum u32 {
	// Left to right instead of top to bottom.
	Across,
	// At a steady rate, as a color ramp needs.
	Linear,
}

#assert(size_of(Instance) == 176)

_Batch :: struct {
	texture:     ^MTL.Texture,
	first_index: int,
	count:       int,
	// Erases beneath its instances so glass behind the window shows through.
	is_clear:       bool,
	// Layer i of each instance reads texture i.
	layer_textures: [MAX_LAYERS]^MTL.Texture,
}

_FRAMES_IN_FLIGHT :: 3
_MAX_INSTANCE_COUNT :: 64 * 1024
INITIAL_INSTANCE_COUNT :: 8 * 1024
_QUAD_VERTEX_COUNT :: 4
_BYTES_PER_PIXEL :: 4

// A window draws into it. It keeps the last frame so a matching frame can skip drawing.
Surface :: struct {
	layer:              ^CA.MetalLayer,
	buffers:            [_FRAMES_IN_FLIGHT]^MTL.Buffer,
	command_buffers:    [_FRAMES_IN_FLIGHT]^MTL.CommandBuffer,
	frame_index:        int,
	size_pixels:        [2]f32,
	shown_instances:    [dynamic]Instance,
	shown_batches:      [dynamic]_Batch,
	shown_layers:       [dynamic]Layer_Data,
	shown_size_pixels:  [2]f32,
	shown_upload_count: int,
	shown_color_flags:  u32,
}

_state: struct {
	device:        ^MTL.Device,
	queue:         ^MTL.CommandQueue,
	// Indexed [is_linear][is_clear].
	pipelines:     [2][2]^MTL.RenderPipelineState,
	color_flags:   u32,
	sampler:       ^MTL.SamplerState,
	tile_sampler:  ^MTL.SamplerState,
	white_texture: ^MTL.Texture,
	// The instances and batches of the current frame, for the target in use.
	instances:     [dynamic]Instance,
	batches:       [dynamic]_Batch,
	layers:        [dynamic]Layer_Data,
	upload_count:  int,
	surface:       ^Surface,
}

_shader_source := #load("shaders.metal", string)

// layer may be nil when there is no screen. Call use_surface to draw into the surface.
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

// Frees the target once the GPU finishes its frames.
destroy_surface :: proc(target: ^Surface) {
	for command_buffer in target.command_buffers {
		if command_buffer == nil do continue

		command_buffer->waitUntilCompleted()
		command_buffer->release()
	}
	for buffer in target.buffers do buffer->release()
	delete(target.shown_instances)
	delete(target.shown_batches)
	delete(target.shown_layers)
	if _state.surface == target do _state.surface = nil
	free(target)
}

// Every window shares one renderer. Later calls, such as from each headless run, do nothing.
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

	// The shaders emit premultiplied color. A clear pipeline keeps only the color under each shape
	// that the shape leaves uncovered. An sRGB target blends in linear light.
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
	sampler_descriptor->setSAddressMode(.Repeat)
	sampler_descriptor->setTAddressMode(.Repeat)
	_state.tile_sampler = device->newSamplerState(sampler_descriptor)

	white := [4]u8{255, 255, 255, 255}
	_state.white_texture = make_texture({1, 1}, .RGBA8Unorm)
	upload_texture(_state.white_texture, {0, 0, 1, 1}, raw_data(white[:]), _BYTES_PER_PIXEL)
}

make_texture :: proc(size_pixels: [2]int, format: MTL.PixelFormat) -> ^MTL.Texture {
	// Image threads have no autorelease pool of their own, and Metal autoreleases the descriptor.
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

// is_linear blends in linear light; is_p3 writes Display P3 for a layer in that space.
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
	clear(&_state.layers)
}

// One instance with the textures it draws with. ui keeps these to redraw a box's last frame.
Pushed :: struct {
	instance: Instance,
	texture:  ^MTL.Texture,
	layers:   [MAX_LAYERS]Layer,
}

pushed_count :: proc() -> int {
	return len(_state.instances)
}

// Appends every instance from index first on, with its texture.
read_pushed :: proc(first: int, into: ^[dynamic]Pushed) {
	for batch in _state.batches {
		if batch.is_clear do continue
		for index in max(first, batch.first_index) ..< batch.first_index + batch.count {
			instance := _state.instances[index]
			pushed := Pushed{instance = instance, texture = batch.texture}
			for &layer, slot in pushed.layers[:instance.layer_count] {
				layer = {_state.layers[int(instance.layer_first) + slot], batch.layer_textures[slot]}
			}
			append(into, pushed)
		}
	}
}

push :: proc(instance: Instance, texture: ^MTL.Texture = nil, layers: []Layer = nil) {
	if len(_state.instances) >= _MAX_INSTANCE_COUNT do return

	instance := instance
	instance.layer_first, instance.layer_count = u32(len(_state.layers)), u32(len(layers))
	layer_textures: [MAX_LAYERS]^MTL.Texture
	for layer, slot in layers {
		append(&_state.layers, layer.data)
		layer_textures[slot] = layer.texture
	}

	texture := texture if texture != nil else _state.white_texture
	batch_count := len(_state.batches)
	last := &_state.batches[batch_count - 1] if batch_count > 0 else nil
	is_after_clear := last != nil && last.is_clear
	is_same_texture := last != nil && last.texture == texture
	// A batch's layer textures are free until an instance with layers takes them.
	is_same_layers := last != nil && (layer_textures == {} || last.layer_textures == {} || last.layer_textures == layer_textures)
	can_join := !is_after_clear && is_same_layers && (is_same_texture || (last != nil && instance.kind == .Solid))

	if can_join {
		last.count += 1
		if layer_textures != {} do last.layer_textures = layer_textures
	} else {
		append(&_state.batches, _Batch{texture, len(_state.instances), 1, false, layer_textures})
	}

	append(&_state.instances, instance)
}

// Erases a rounded rect of the frame so far, in pixels.
push_clear :: proc(rect: [4]f32, corner_radius: [4]f32, clip: [4]f32) {
	if len(_state.instances) >= _MAX_INSTANCE_COUNT do return

	append(&_state.batches, _Batch{_state.white_texture, len(_state.instances), 1, true, {}})
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
	encoder->setFragmentBuffer(buffer, NS.UInteger(_to_layer_offset() if len(_state.layers) > 0 else 0), 2)

	viewport := _state.surface.size_pixels
	encoder->setVertexBytes(([^]byte)(&viewport)[:size_of(viewport)], 1)
	encoder->setFragmentSamplerState(_state.sampler, 0)
	encoder->setFragmentSamplerState(_state.tile_sampler, 1)

	is_clearing := false
	for batch in _state.batches {
		if batch.is_clear != is_clearing {
			is_clearing = batch.is_clear
			encoder->setRenderPipelineState(_state.pipelines[is_linear][1 if is_clearing else 0])
		}
		encoder->setFragmentTexture(batch.texture, 0)
		for texture, slot in batch.layer_textures {
			encoder->setFragmentTexture(texture if texture != nil else _state.white_texture, NS.UInteger(1 + slot))
		}
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

// For headless snapshots: draws the last frame into memory, as BGRA with premultiplied alpha.
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

// Layers follow the instances in the same buffer, at an offset any Mac can bind.
_to_layer_offset :: proc() -> int {
	LAYER_ALIGNMENT :: 256
	return (len(_state.instances) * size_of(Instance) + LAYER_ALIGNMENT - 1) / LAYER_ALIGNMENT * LAYER_ALIGNMENT
}

_is_same_as_shown :: proc(target: ^Surface, upload_count: int) -> bool {
	batch_bytes := mem.slice_to_bytes(_state.batches[:])
	instance_bytes := mem.slice_to_bytes(_state.instances[:])
	is_same_size := target.size_pixels == target.shown_size_pixels && _state.color_flags == target.shown_color_flags
	is_unchanged := upload_count == target.shown_upload_count
	is_same_batches := mem.compare(batch_bytes, mem.slice_to_bytes(target.shown_batches[:])) == 0
	is_same_instances :=
		mem.compare(instance_bytes, mem.slice_to_bytes(target.shown_instances[:])) == 0
	is_same_layers := mem.compare(mem.slice_to_bytes(_state.layers[:]), mem.slice_to_bytes(target.shown_layers[:])) == 0

	return is_same_size && is_unchanged && is_same_batches && is_same_instances && is_same_layers
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
	instance_bytes := len(_state.instances) * size_of(Instance)
	layer_bytes := len(_state.layers) * size_of(Layer_Data)
	needed_bytes := _to_layer_offset() + layer_bytes

	if int(buffer->length()) < needed_bytes {
		capacity := int(buffer->length())
		for capacity < needed_bytes do capacity *= 2
		buffer->release()
		buffer = _state.device->newBufferWithLength(NS.UInteger(capacity), {})
		target.buffers[slot] = buffer
	}

	intrinsics.mem_copy_non_overlapping(buffer->contentsPointer(), raw_data(_state.instances), instance_bytes)
	if layer_bytes > 0 {
		layers_at := rawptr(uintptr(buffer->contentsPointer()) + uintptr(_to_layer_offset()))
		intrinsics.mem_copy_non_overlapping(layers_at, raw_data(_state.layers), layer_bytes)
	}

	if drawable == nil do return

	command_buffer := _state.queue->commandBuffer()
	_encode_pass(command_buffer, drawable->texture(), buffer)
	command_buffer->presentDrawable(drawable)
	command_buffer->commit()
	command_buffer->retain()
	target.command_buffers[slot] = command_buffer

	_state.instances, target.shown_instances = target.shown_instances, _state.instances
	_state.batches, target.shown_batches = target.shown_batches, _state.batches
	_state.layers, target.shown_layers = target.shown_layers, _state.layers
	// A frame drawn during a resize has the drawable's old size, and the layer stretches it.
	texture := drawable->texture()
	target.shown_size_pixels = {f32(texture->width()), f32(texture->height())}
	target.shown_upload_count = upload_count
	target.shown_color_flags = _state.color_flags
}
