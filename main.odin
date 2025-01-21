package main

import "base:builtin"
import "base:runtime"

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:mem"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

import SDL "vendor:sdl2"
import IMG "vendor:sdl2/image"
import SDL_TTF "vendor:sdl2/ttf"

import "./renderer"

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

	ctx := renderer.init()
	state.grpahics_ctx = &ctx
	defer renderer.cleanup(state.grpahics_ctx)

	// poll for queued events each game loop
	event: SDL.Event

	NOW := SDL.GetPerformanceCounter()
	LAST: u64
	delta_time: f64

	textures_atlas := renderer.load_texture("./spritesheet.png", state.grpahics_ctx)
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

	os_ctx, _ := renderer.carl(state.grpahics_ctx)
	state.os_graphics_ctx = &os_ctx

	SDL.ShowWindow(state.grpahics_ctx.window)
	game_loop: for {
		if SDL.PollEvent(&event) {
			if end_game(&event) do break game_loop

			handle_events(&event)
		}

		LAST = NOW
		NOW = SDL.GetPerformanceCounter()
		delta_time = f64((NOW - LAST) * 1000 / SDL.GetPerformanceFrequency())

		tris: [BOARD_WIDTH * BOARD_HEIGHT * 2]renderer.Triangle
		// = {
		// 	{
		// 		points = {{-0.5, 0.48, 0, 1}, {-0.5, -0.5, 0, 1}, {0.48, -0.5, 0, 1}},
		// 		colors = {{1, 0, 0, 1}, {0, 1, 0, 1}, {0, 0, 1, 1}},
		// 	},
		// 	{
		// 		points = {{-0.48, 0.5, 0, 1}, {0.5, -0.48, 0, 1}, {0.5, 0.5, 0, 1}},
		// 		colors = {{1, 0, 0, 1}, {0, 0, 1, 1}, {0, 1, 0, 1}},
		// 	},
		// }

		tri_offset: int

		for cell, idx in state.game_board {
			point := index_to_point(idx)
			color := symbol_to_color(cell.symbol)

			camera := linalg.matrix4_infinite_perspective_f32(
				fovy = 90,
				// aspect = 16 / 9,
				aspect = f32(state.grpahics_ctx.window_w / state.grpahics_ctx.window_h),
				near = 0.0,
				// flip_z_axis = false,
			)
			// camera *= linalg.matrix4_translate_f32({-32, -32, 0})

			x_left := f32(point.x * CELL_SIZE)
			x_right := x_left + CELL_SIZE
			y_bottom := f32(point.y * CELL_SIZE)
			y_top := y_bottom + CELL_SIZE
			// log.debug("cell real", idx, point, x_left, y_top, x_right, y_bottom)

			p1 := linalg.matrix_mul_vector(camera, ([4]f32)({x_left, y_top, -20, 1})) / 2
			p2 := linalg.matrix_mul_vector(camera, ([4]f32)({x_left, y_bottom, -20, 1})) / 2
			p3 := linalg.matrix_mul_vector(camera, ([4]f32)({x_right, y_bottom, -20, 1})) / 2
			p4 := linalg.matrix_mul_vector(camera, ([4]f32)({x_right, y_top, -20, 1})) / 2
			log.debug("cell scaled", idx)
			log.debug("tris 0", tri_offset, tris[tri_offset], tris[0])
			tris[tri_offset] = {
				points = {p1, p2, p3},
				colors = {color, color, color},
			}
			log.debug("tris 1", tri_offset, tris[tri_offset], tris[0])
			tris[tri_offset + 1] = {
				points = {p1, p3, p4},
				colors = {color, color, color},
			}

			tri_offset += 2
			// src_rect: SDL.Rect = {32, 0, 32, 32}
			// dest_rect: SDL.Rect = {
			// 	c.int(point.x * CELL_SIZE),
			// 	c.int(point.y * CELL_SIZE),
			// 	c.int(CELL_SIZE),
			// 	c.int(CELL_SIZE),
			// }
			// SDL.SetTextureColorMod(textures_atlas, color.r, color.g, color.b)
			// SDL.RenderCopy(state.grpahics_ctx.sdl_renderer, textures_atlas, &src_rect, &dest_rect)
		}
		// { 	// draw board cursor
		// 	src_rect: SDL.Rect = {0, 0, 32, 32}
		// 	dest_rect_left: SDL.Rect = {
		// 		c.int(state.cursor.left.x * CELL_SIZE),
		// 		c.int(state.cursor.left.y * CELL_SIZE),
		// 		c.int(CELL_SIZE),
		// 		c.int(CELL_SIZE),
		// 	}
		// 	dest_rect_right: SDL.Rect = {
		// 		c.int(state.cursor.right.x * CELL_SIZE),
		// 		c.int(state.cursor.right.y * CELL_SIZE),
		// 		c.int(CELL_SIZE),
		// 		c.int(CELL_SIZE),
		// 	}
		// 	color := Color{255, 255, 255, 255}
		// 	SDL.SetTextureColorMod(textures_atlas, color.r, color.g, color.b)
		// 	SDL.RenderCopy(
		// 		state.grpahics_ctx.sdl_renderer,
		// 		textures_atlas,
		// 		&src_rect,
		// 		&dest_rect_left,
		// 	)
		// 	SDL.RenderCopyEx(
		// 		state.grpahics_ctx.sdl_renderer,
		// 		textures_atlas,
		// 		&src_rect,
		// 		&dest_rect_right,
		// 		0,
		// 		nil,
		// 		SDL.RendererFlip.HORIZONTAL,
		// 	)
		// }

		// // END update and render

		// renderer.draw_scene(state.grpahics_ctx)

		renderer.barl(state.os_graphics_ctx, tris[:], {0, 0, 0, 1})
	}

	delete(keys_down)
}

CELL_SIZE :: 2
// BOARD_WIDTH :: 10
// BOARD_HEIGHT :: 15
BOARD_WIDTH :: 2
BOARD_HEIGHT :: 1

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
	grpahics_ctx:    ^renderer.GraphicsContext,
	os_graphics_ctx: ^renderer.OsGrpahicsContext,

	//
	view:            View,

	//
	game_board:      Board,
	cursor:          struct {
		left:  Point,
		right: Point,
	},
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


symbol_to_color :: proc(symbol: Symbol) -> (color: renderer.Color) {
	switch symbol {
	case .SymbolA:
		color = {1, 0, 0, 1}
	case .SymbolB:
		color = {0, 1, 0, 1}
	case .SymbolC:
		color = {0, 0, 1, 1}
	case .SymbolD:
		color = {0.5, 0, 0.5, 1}
	}

	return
}

View :: enum {
	GameMatch,
}

state := State {
	view = .GameMatch,
	cursor = {left = {0, BOARD_HEIGHT - 1}, right = {1, BOARD_HEIGHT - 1}},
}


handle_events :: proc(event: ^SDL.Event) {

	if event.type == SDL.EventType.WINDOWEVENT {
		if (event.window.windowID == SDL.GetWindowID(state.grpahics_ctx.window)) {
			if event.window.event == SDL.WindowEventID.RESIZED {
				state.grpahics_ctx.window_w = event.window.data1
				state.grpahics_ctx.window_h = event.window.data2
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
		left_index := point_to_index(state.cursor.left)
		right_index := point_to_index(state.cursor.right)

		slice.swap(state.game_board[:], left_index, right_index)
	case .W:
		cursor_move_by(&state.cursor.left, {0, -1})
		cursor_move_by(&state.cursor.right, {0, -1})
	case .A:
		cursor_move_by(&state.cursor.left, {-1, 0})
		cursor_move_by(&state.cursor.right, {-1, 0})
	case .S:
		cursor_move_by(&state.cursor.left, {0, 1})
		cursor_move_by(&state.cursor.right, {0, 1})
	case .D:
		cursor_move_by(&state.cursor.left, {1, 0})
		cursor_move_by(&state.cursor.right, {1, 0})
	}
}

keys_down: map[SDL.Keycode]struct {}

cursor_move_by :: proc(cursor: ^Point, amount: Point) {
	next_pos := cursor^ + amount

	if next_pos.x < 0 {
		for next_pos.x < 0 {
			next_pos.x = BOARD_WIDTH + next_pos.x
		}
	} else if next_pos.x >= BOARD_WIDTH {
		for next_pos.x >= BOARD_WIDTH {
			next_pos.x = next_pos.x - BOARD_WIDTH
		}
	}

	if next_pos.y < 0 {
		next_pos.y = 0
	} else if next_pos.y >= BOARD_HEIGHT {
		next_pos.y = BOARD_HEIGHT - 1
	}

	cursor^ = next_pos
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
