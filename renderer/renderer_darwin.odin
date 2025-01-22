package renderer

import "core:fmt"
import "core:log"
import "core:math"

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"

import SDL "vendor:sdl2"


OsGrpahicsContext :: struct {
	swapchain:                 ^CA.MetalLayer,
	command_queue:             ^MTL.CommandQueue,
	pipeline_state:            ^MTL.RenderPipelineState,
	device:                    ^MTL.Device,
	depth_stencil_descriptor:  ^MTL.DepthStencilDescriptor,
	compile_options:           ^MTL.CompileOptions,
	vertex_program:            ^MTL.Function,
	fragment_program:          ^MTL.Function,
	pipeline_state_descriptor: ^MTL.RenderPipelineDescriptor,
	depth_texture:             ^MTL.Texture,
	depth_stencil_state:       ^MTL.DepthStencilState,
}


set_env :: proc() {
	SDL.SetHint(SDL.HINT_RENDER_DRIVER, "metal")
	SDL.setenv("METAL_DEVICE_WRAPPER_TYPE", "1", 0)
}

Error :: union {
	^NS.Error,
}


os_init :: proc(ctx: ^GraphicsContext) -> (os_ctx: OsGrpahicsContext, error: Error) {
	window_system_info: SDL.SysWMinfo
	SDL.GetVersion(&window_system_info.version)
	SDL.GetWindowWMInfo(ctx.window, &window_system_info)
	assert(window_system_info.subsystem == .COCOA)

	native_window := (^NS.Window)(window_system_info.info.cocoa.window)

	os_ctx.device = MTL.CreateSystemDefaultDevice()

	fmt.println(os_ctx.device->name()->odinString())

	os_ctx.swapchain = CA.MetalLayer.layer()
	os_ctx.swapchain->setDevice(os_ctx.device)
	os_ctx.swapchain->setPixelFormat(.BGRA8Unorm_sRGB)
	os_ctx.swapchain->setFramebufferOnly(true)
	os_ctx.swapchain->setFrame(native_window->frame())

	native_window->contentView()->setLayer(os_ctx.swapchain)
	native_window->setOpaque(true)
	native_window->setBackgroundColor(nil)

	os_ctx.command_queue = os_ctx.device->newCommandQueue()

	os_ctx.compile_options = NS.new(MTL.CompileOptions)

	program_source :: `
	using namespace metal;
	struct ColoredVertex {
		float4 position [[position]];
		float4 color;
	};
	vertex ColoredVertex vertex_main(constant float4 *position [[buffer(0)]],
	                                 constant float4 *color    [[buffer(1)]],
	                                 uint vid                  [[vertex_id]]) {
		ColoredVertex vert;
		vert.position = position[vid];
		vert.color    = color[vid];
		return vert;
	}
	fragment float4 fragment_main(ColoredVertex vert [[stage_in]]) {
		return vert.color;
	}
	`
	program_library, library_err := os_ctx.device->newLibraryWithSource(
		NS.AT(program_source),
		os_ctx.compile_options,
	)

	if library_err != nil {
		return os_ctx, library_err
	}

	os_ctx.vertex_program = program_library->newFunctionWithName(NS.AT("vertex_main"))
	os_ctx.fragment_program = program_library->newFunctionWithName(NS.AT("fragment_main"))
	assert(os_ctx.vertex_program != nil)
	assert(os_ctx.fragment_program != nil)


	os_ctx.pipeline_state_descriptor = MTL.RenderPipelineDescriptor.alloc()->init()
	os_ctx.pipeline_state_descriptor->setVertexFunction(os_ctx.vertex_program)
	os_ctx.pipeline_state_descriptor->setFragmentFunction(os_ctx.fragment_program)
	os_ctx.pipeline_state_descriptor->colorAttachments()->object(0)->setPixelFormat(
		.BGRA8Unorm_sRGB,
	)
	os_ctx.pipeline_state_descriptor->setDepthAttachmentPixelFormat(MTL.PixelFormat.Depth16Unorm)
	// os_ctx.pipeline_state_descriptor->setSampleCount(1)

	pipe_state, pipeline_err := os_ctx.device->newRenderPipelineState(
		os_ctx.pipeline_state_descriptor,
	)

	if pipeline_err != nil {
		return os_ctx, pipeline_err
	}

	os_ctx.pipeline_state = pipe_state

	os_ctx.depth_stencil_descriptor = MTL.DepthStencilDescriptor.alloc()->init()
	os_ctx.depth_stencil_descriptor->setDepthCompareFunction(MTL.CompareFunction.LessEqual)
	os_ctx.depth_stencil_descriptor->setDepthWriteEnabled(true)
	os_ctx.depth_stencil_state =
	os_ctx.device->newDepthStencilState(os_ctx.depth_stencil_descriptor)


	desc := MTL.TextureDescriptor.texture2DDescriptorWithPixelFormat(
		pixelFormat = .Depth16Unorm,
		width = NS.UInteger(ctx.window_w),
		height = NS.UInteger(ctx.window_h),
		mipmapped = false,
	)
	defer desc->release()

	desc->setUsage({.RenderTarget})
	desc->setStorageMode(.Private)

	if os_ctx.depth_texture != nil {
		os_ctx.depth_texture->release()
	}

	os_ctx.depth_texture = os_ctx.device->newTextureWithDescriptor(desc)

	return
}

os_cleanup :: proc(os_ctx: ^OsGrpahicsContext) {
	os_ctx.depth_texture->release()
	os_ctx.pipeline_state_descriptor->release()
	os_ctx.vertex_program->release()
	os_ctx.fragment_program->release()
	os_ctx.compile_options->release()
	os_ctx.device->release()
}

render :: proc(
	ctx: ^GraphicsContext,
	os_ctx: ^OsGrpahicsContext,
	shapes: []Triangle,
	clear_color: Color = {0.25, 0.5, 1.0, 1.0},
) {
	positions: [dynamic]Point
	colors: [dynamic]Color
	defer delete(positions)
	defer delete(colors)

	for shape in shapes {
		append(&positions, shape.points[0])
		append(&positions, shape.points[1])
		append(&positions, shape.points[2])
		append(&colors, shape.colors[0])
		append(&colors, shape.colors[1])
		append(&colors, shape.colors[2])
	}

	position_buffer := os_ctx.device->newBufferWithSlice(positions[:], {})
	color_buffer := os_ctx.device->newBufferWithSlice(colors[:], {})

	NS.scoped_autoreleasepool()

	drawable := os_ctx.swapchain->nextDrawable()
	assert(drawable != nil)

	pass := MTL.RenderPassDescriptor.renderPassDescriptor()
	color_attachment := pass->colorAttachments()->object(0)
	assert(color_attachment != nil)
	color_attachment->setClearColor(
		MTL.ClearColor {
			f64(clear_color.r),
			f64(clear_color.g),
			f64(clear_color.b),
			f64(clear_color.a),
		},
	)
	color_attachment->setLoadAction(.Clear)
	color_attachment->setStoreAction(.Store)
	color_attachment->setTexture(drawable->texture())

	if os_ctx.depth_texture == nil ||
	   os_ctx.depth_texture->width() != NS.UInteger(ctx.window_w) ||
	   os_ctx.depth_texture->height() != NS.UInteger(ctx.window_h) {
		desc := MTL.TextureDescriptor.texture2DDescriptorWithPixelFormat(
			pixelFormat = .Depth16Unorm,
			width = NS.UInteger(ctx.window_w),
			height = NS.UInteger(ctx.window_h),
			mipmapped = false,
		)
		defer desc->release()

		desc->setUsage({.RenderTarget})
		desc->setStorageMode(.Private)

		if os_ctx.depth_texture != nil {
			os_ctx.depth_texture->release()
		}

		os_ctx.depth_texture = os_ctx.device->newTextureWithDescriptor(desc)
	}

	depth_attachment := pass->depthAttachment()
	depth_attachment->setTexture(os_ctx.depth_texture)
	depth_attachment->setClearDepth(1.0)
	depth_attachment->setLoadAction(.Clear)
	depth_attachment->setStoreAction(.Store)

	command_buffer := os_ctx.command_queue->commandBuffer()
	render_encoder := command_buffer->renderCommandEncoderWithDescriptor(pass)

	render_encoder->setRenderPipelineState(os_ctx.pipeline_state)
	render_encoder->setDepthStencilState(os_ctx.depth_stencil_state)

	render_encoder->setVertexBuffer(position_buffer, 0, 0)
	render_encoder->setVertexBuffer(color_buffer, 0, 1)

	render_encoder->setCullMode(.Back)
	render_encoder->setFrontFacingWinding(.CounterClockwise)

	render_encoder->drawPrimitives(.Triangle, 0, NS.UInteger(len(positions)))

	render_encoder->endEncoding()

	command_buffer->presentDrawable(drawable)
	command_buffer->commit()
}
