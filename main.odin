package main

import "base:builtin"
import "base:runtime"

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

import SDL "vendor:sdl2"
import IMG "vendor:sdl2/image"
import SDL_TTF "vendor:sdl2/ttf"

main :: proc() {
	when ODIN_DEBUG {
		// setup debug logging
		logger := log.create_console_logger()
		context.logger = logger

		// setup tracking allocator for making sure all memory is cleaned up
		default_allocator := context.allocator
		tracking_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking_allocator, default_allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)

		reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
			err := false

			for _, value in a.allocation_map {
				fmt.printfln("%v: Leaked %v bytes", value.location, value.size)
				err = true
			}

			mem.tracking_allocator_clear(a)

			return err
		}

		defer reset_tracking_allocator(&tracking_allocator)
	}

	init_sdl()
	// all quits and destroys
	defer clean_sdl()

	// poll for queued events each game loop
	event: SDL.Event

	NOW := SDL.GetPerformanceCounter()
	LAST: u64
	delta_time: f64

	textures_atlas := loadTexture("./spritesheet.png", state.renderer)
	defer SDL.DestroyTexture(textures_atlas)

	for x in 0 ..< BOARD_WIDTH {
		for y in 0 ..< BOARD_HEIGHT {
			idx := point_to_index({x, y})
			symbol := rand.choice_enum(Symbol)

			state.game_board[idx] = {
				symbol = symbol,
			}
		}
	}

	game_loop: for {
		if SDL.PollEvent(&event) {
			if end_game(&event) do break game_loop

			handle_events(&event)
		}

		LAST = NOW
		NOW = SDL.GetPerformanceCounter()
		delta_time = f64((NOW - LAST) * 1000 / SDL.GetPerformanceFrequency())

		for cell, idx in state.game_board {
			point := index_to_point(idx)
			src_rect: SDL.Rect = {32, 0, 32, 32}
			dest_rect: SDL.Rect = {
				c.int(point.x * CELL_SIZE),
				c.int(point.y * CELL_SIZE),
				c.int(CELL_SIZE),
				c.int(CELL_SIZE),
			}
			color := symbol_to_color(cell.symbol)
			SDL.SetTextureColorMod(textures_atlas, color.r, color.g, color.b)
			SDL.RenderCopy(state.renderer, textures_atlas, &src_rect, &dest_rect)
		}
		{ 	// draw board cursor
			src_rect: SDL.Rect = {0, 0, 32, 32}
			dest_rect_left: SDL.Rect = {
				c.int(state.board_cursor.x * CELL_SIZE),
				c.int(state.board_cursor.y * CELL_SIZE),
				c.int(CELL_SIZE),
				c.int(CELL_SIZE),
			}
			dest_rect_right: SDL.Rect = {
				c.int(
					state.board_cursor.x == BOARD_WIDTH - 1 \
					? 0 \
					: (state.board_cursor.x + 1) * CELL_SIZE,
				),
				c.int(state.board_cursor.y * CELL_SIZE),
				c.int(CELL_SIZE),
				c.int(CELL_SIZE),
			}
			color := Color{255, 255, 255, 255}
			SDL.SetTextureColorMod(textures_atlas, color.r, color.g, color.b)
			SDL.RenderCopy(state.renderer, textures_atlas, &src_rect, &dest_rect_left)
			SDL.RenderCopyEx(
				state.renderer,
				textures_atlas,
				&src_rect,
				&dest_rect_right,
				0,
				nil,
				SDL.RendererFlip.HORIZONTAL,
			)
		}

		// END update and render

		draw_scene()
	}
}

CELL_SIZE :: 64
BOARD_WIDTH :: 10
BOARD_HEIGHT :: 15

Point :: distinct [2]int

point_to_index :: proc(point: Point) -> int {
	return (point.y * BOARD_WIDTH) + point.x
}

index_to_point :: proc(index: int) -> (point: Point) {
	point.x = index %% BOARD_WIDTH
	point.y = index / BOARD_WIDTH

	return
}

RENDER_FLAGS :: SDL.RENDERER_ACCELERATED
WINDOW_FLAGS :: SDL.WINDOW_SHOWN | SDL.WINDOW_RESIZABLE


// State

State :: struct {
	window:       ^SDL.Window,
	window_w:     i32,
	window_h:     i32,
	renderer:     ^SDL.Renderer,
	font:         ^SDL_TTF.Font,
	font_size:    i32,

	//
	view:         View,

	//
	game_board:   Board,
	board_cursor: Point,
}

Board :: [BOARD_WIDTH * BOARD_HEIGHT]Cell

Cell :: struct {
	symbol:    Symbol,
	animating: Animating,
}

Animating :: enum {
	Down,
	Left,
	Right,
	None,
}

Symbol :: enum {
	SymbolA,
	SymbolB,
	SymbolC,
	SymbolD,
}

Color :: distinct [4]u8

symbol_to_color :: proc(symbol: Symbol) -> (color: Color) {
	switch symbol {
	case .SymbolA:
		color = {255, 0, 0, 255}
	case .SymbolB:
		color = {0, 255, 0, 255}
	case .SymbolC:
		color = {0, 0, 255, 255}
	case .SymbolD:
		color = {128, 0, 128, 255}
	}

	return
}

View :: enum {
	GameMatch,
}

state := State {
	window_w  = 1024,
	window_h  = 960,
	font_size = 28,
	view      = .GameMatch,
}


handle_events :: proc(event: ^SDL.Event) {

	if event.type == SDL.EventType.WINDOWEVENT {
		if (event.window.windowID == SDL.GetWindowID(state.window)) {
			if event.window.event == SDL.WindowEventID.RESIZED {
				state.window_w = event.window.data1
				state.window_h = event.window.data2
			}
		}
	}

	mouse_x: c.int = 0
	mouse_y: c.int = 0
	mouse_state := SDL.GetMouseState(&mouse_x, &mouse_y)
	clicking := c.int(mouse_state) & SDL.BUTTON(SDL.BUTTON_LEFT) != 0


	if event.type == SDL.EventType.KEYUP {
		delete_key(&keys_down, event.key.keysym.sym)
		return
	}

	if event.type != SDL.EventType.KEYDOWN do return

	keycode := event.key.keysym.sym

	if keycode in keys_down do return

	keys_down[keycode] = {}

	#partial switch keycode 
	{
	case .SPACE:
		left_index := point_to_index(state.board_cursor)
		right_index := point_to_index(board_cursor_right(state.board_cursor))

		slice.swap(state.game_board[:], left_index, right_index)
	case .W:
		if state.board_cursor.y > 0 {
			state.board_cursor.y -= 1
		}
	case .A:
		if state.board_cursor.x == 0 {
			state.board_cursor.x = BOARD_WIDTH - 1
		} else {
			state.board_cursor.x -= 1
		}
	case .S:
		if state.board_cursor.y < BOARD_HEIGHT - 1 {
			state.board_cursor.y += 1
		}
	case .D:
		if state.board_cursor.x == BOARD_WIDTH - 1 {
			state.board_cursor.x = 0
		} else {
			state.board_cursor.x += 1
		}
	}
}

keys_down: map[SDL.Keycode]struct {}

board_cursor_right :: proc(cursor_left: Point) -> Point {
	cursor_right := cursor_left

	if cursor_left.x == BOARD_WIDTH - 1 {
		cursor_right.x = 0
	} else {
		cursor_right.x += 1
	}

	return cursor_right
}

// SDL stuff

draw_scene :: proc() {
	// actual flipping / presentation of the copy
	// read comments here :: https://wiki.libsdl.org/SDL_RenderCopy
	SDL.RenderPresent(state.renderer)

	// make sure our background is black
	// RenderClear colors the entire screen whatever color is set here
	SDL.SetRenderDrawColor(state.renderer, 0, 0, 0, 100)

	// clear the old scene from the renderer
	// clear after presentation so we remain free to call RenderCopy() throughout our update code / wherever it makes the most sense
	SDL.RenderClear(state.renderer)

}


init_sdl :: proc() {
	// initialize SDL
	sdl_init_error := SDL.Init(SDL.INIT_VIDEO)
	assert(sdl_init_error != -1, SDL.GetErrorString())

	// Window
	state.window = SDL.CreateWindow(
		"Yggdrasil",
		SDL.WINDOWPOS_CENTERED,
		SDL.WINDOWPOS_CENTERED,
		state.window_w,
		state.window_h,
		WINDOW_FLAGS,
	)
	assert(state.window != nil, SDL.GetErrorString())

	// Renderer
	// This is used throughout the program to render everything.
	// You only require ONE renderer for the entire program.
	state.renderer = SDL.CreateRenderer(state.window, -1, RENDER_FLAGS)
	assert(state.renderer != nil, SDL.GetErrorString())

	ttf_init_error := SDL_TTF.Init()
	assert(ttf_init_error != -1, SDL.GetErrorString())
	state.font = SDL_TTF.OpenFont("LiberationMono-Regular.ttf", state.font_size)
	assert(state.font != nil, SDL.GetErrorString())
}

clean_sdl :: proc() {
	SDL_TTF.Quit()
	SDL.Quit()
	SDL.DestroyWindow(state.window)
	SDL.DestroyRenderer(state.renderer)
}


// check for a quit event
// this is an example of using a Named Result - "exit".
// with named results we can just put "return" at the end of the function
// and the value of our named return-variable will be returned.
end_game :: proc(event: ^SDL.Event) -> (exit: bool) {
	exit = false

	// Quit event is clicking on the X on the window
	if event.type == SDL.EventType.QUIT || event.key.keysym.scancode == .ESCAPE {
		exit = true
	}

	return
}


loadTexture :: proc(path: string, renderer: ^SDL.Renderer) -> ^SDL.Texture {
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
		new_texture = SDL.CreateTextureFromSurface(renderer, loadedSurface)
		if (new_texture == nil) {
			fmt.printf("Unable to create texture from %s! SDL Error: %s\n", path, SDL.GetError())
		}

		//Get rid of old loaded surface
		SDL.FreeSurface(loadedSurface)
	}

	return new_texture
}
