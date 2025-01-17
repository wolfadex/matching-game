package renderer

import "core:fmt"
import "core:math"

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"

import SDL "vendor:sdl2"


OsGrpahicsContext :: struct {
	swapchain:      ^CA.MetalLayer,
	command_queue:  ^MTL.CommandQueue,
	pipeline_state: ^MTL.RenderPipelineState,
	// position_buffer: ^MTL.Buffer,
	// color_buffer:    ^MTL.Buffer,
	device:         ^MTL.Device,
}


set_env :: proc() {
	SDL.SetHint(SDL.HINT_RENDER_DRIVER, "metal")
	SDL.setenv("METAL_DEVICE_WRAPPER_TYPE", "1", 0)
}

Error :: union {
	^NS.Error,
}


carl :: proc(ctx: ^GraphicsContext) -> (os_ctx: OsGrpahicsContext, error: Error) {
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

	compile_options := NS.new(MTL.CompileOptions)
	defer compile_options->release()


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
		compile_options,
	)

	if library_err != nil {
		return os_ctx, library_err
	}

	vertex_program := program_library->newFunctionWithName(NS.AT("vertex_main"))
	fragment_program := program_library->newFunctionWithName(NS.AT("fragment_main"))
	assert(vertex_program != nil)
	assert(fragment_program != nil)


	pipeline_state_descriptor := NS.new(MTL.RenderPipelineDescriptor)
	pipeline_state_descriptor->colorAttachments()->object(0)->setPixelFormat(.BGRA8Unorm_sRGB)
	pipeline_state_descriptor->setVertexFunction(vertex_program)
	pipeline_state_descriptor->setFragmentFunction(fragment_program)

	pipe_state, pipeline_err := os_ctx.device->newRenderPipelineState(pipeline_state_descriptor)

	if pipeline_err != nil {
		return os_ctx, pipeline_err
	}

	os_ctx.pipeline_state = pipe_state
	return
}

barl :: proc(
	os_ctx: ^OsGrpahicsContext,
	shapes: []Triangle,
	clear_color: Color = {0.25, 0.5, 1.0, 1.0},
) {
	positions: [dynamic]Point
	colors: [dynamic]Color
	defer delete(positions)
	defer delete(colors)

	for shape in shapes {
		append(&positions, ..shape.points)
		append(&colors, ..shape.colors)
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


	command_buffer := os_ctx.command_queue->commandBuffer()
	render_encoder := command_buffer->renderCommandEncoderWithDescriptor(pass)

	render_encoder->setRenderPipelineState(os_ctx.pipeline_state)
	render_encoder->setVertexBuffer(position_buffer, 0, 0)
	render_encoder->setVertexBuffer(color_buffer, 0, 1)
	render_encoder->drawPrimitives(.Triangle, 0, 6)

	render_encoder->endEncoding()

	command_buffer->presentDrawable(drawable)
	command_buffer->commit()
}

// https://z4gon.github.io/blog/metal-render-pipeline-part-11-3d-perspective-projection-matrix
project_perspective :: proc(
	point: [4][4]f64,
	fieldOfView: f64,
	aspectRatio: f64,
	farClippingDistance: f64,
	nearClippingDistance: f64,
) -> [4][4]f64 {

	pers: [4][4]f64 = {
		{1 / (aspectRatio * math.tan(fieldOfView / 2)), 0, 0, 0},
		{0, 2 / math.tan(fieldOfView / 2), 0, 0},
		{
			0,
			0,
			-((farClippingDistance + nearClippingDistance) /
				(farClippingDistance - nearClippingDistance)),
			-((2 * farClippingDistance * nearClippingDistance) /
				(farClippingDistance - nearClippingDistance)),
		},
		{0, 0, -1, 0},
	}

	return point * pers
}

identity_matrix: [4][4]f64 : {{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}}
