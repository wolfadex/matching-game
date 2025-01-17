package renderer

import SDL "vendor:sdl2"
import IMG "vendor:sdl2/image"
import SDL_TTF "vendor:sdl2/ttf"

import "core:log"
import "core:strings"
import "core:fmt"

GraphicsContext :: struct {
    window:     ^SDL.Window,
	window_w:   i32,
	window_h:   i32,
	sdl_renderer:   ^SDL.Renderer,
	font:       ^SDL_TTF.Font,
	font_size:  i32,
}

RENDER_FLAGS :: SDL.RENDERER_ACCELERATED
WINDOW_FLAGS :: SDL.WINDOW_SHOWN | SDL.WINDOW_RESIZABLE


init :: proc(width: i32 = 1024, height: i32 = 960, font_size: i32 = 28) -> (ctx: GraphicsContext) {
    set_env()

    ctx.window_w = width
   	ctx.window_h = height
   	ctx.font_size = font_size

    // initialize SDL
	sdl_init_error := SDL.Init(SDL.INIT_VIDEO)
	assert(sdl_init_error != -1, SDL.GetErrorString())

	// Window
	ctx.window = SDL.CreateWindow(
		"Yggdrasil",
		SDL.WINDOWPOS_CENTERED,
		SDL.WINDOWPOS_CENTERED,
		ctx.window_w,
		ctx.window_h,
		WINDOW_FLAGS,
	)
	assert(ctx.window != nil, SDL.GetErrorString())

	// Renderer
	// This is used throughout the program to render everything.
	// You only require ONE renderer for the entire program.
	ctx.sdl_renderer = SDL.CreateRenderer(ctx.window, -1, RENDER_FLAGS)
	assert(ctx.sdl_renderer != nil, SDL.GetErrorString())

	ttf_init_error := SDL_TTF.Init()
	assert(ttf_init_error != -1, SDL.GetErrorString())
	ctx.font = SDL_TTF.OpenFont("LiberationMono-Regular.ttf", ctx.font_size)
	assert(ctx.font != nil, SDL.GetErrorString())

	return
}

cleanup :: proc(ctx: ^GraphicsContext) {
	SDL_TTF.Quit()
	SDL.Quit()
	SDL.DestroyWindow(ctx.window)
	SDL.DestroyRenderer(ctx.sdl_renderer)
}

load_texture :: proc(path: string, ctx: ^GraphicsContext) -> ^SDL.Texture {
	//The final texture
	new_texture: ^SDL.Texture

	//Load image at specified path
	loadedSurface: ^SDL.Surface = IMG.Load(
		strings.clone_to_cstring(path, allocator = context.temp_allocator),
	)
	if (loadedSurface == nil) {
		fmt.printf("Unable to load image %s! SDL_image Error: %s\n", path, IMG.GetError())
	} else {
		//Create texture from surface pixels
		new_texture = SDL.CreateTextureFromSurface(ctx.sdl_renderer, loadedSurface)
		if (new_texture == nil) {
			fmt.printf("Unable to create texture from %s! SDL Error: %s\n", path, SDL.GetError())
		}

		//Get rid of old loaded surface
		SDL.FreeSurface(loadedSurface)
	}

	return new_texture
}

draw_scene :: proc(ctx: ^GraphicsContext) {
	// actual flipping / presentation of the copy
	// read comments here :: https://wiki.libsdl.org/SDL_RenderCopy
	SDL.RenderPresent(ctx.sdl_renderer)

	// make sure our background is black
	// RenderClear colors the entire screen whatever color is set here
	SDL.SetRenderDrawColor(ctx.sdl_renderer, 0, 0, 0, 100)

	// clear the old scene from the renderer
	// clear after presentation so we remain free to call RenderCopy() throughout our update code / wherever it makes the most sense
	SDL.RenderClear(ctx.sdl_renderer)

}