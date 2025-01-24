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

CELL_SIZE :: 2
BOARD_WIDTH :: 20 // columns, aka sides of the "circle"
BOARD_HEIGHT :: 15 // rows
ROTATION_DEG :: f32(360 / BOARD_WIDTH)
THETA :: ROTATION_DEG / 2
ROTATION_TIME :: 50 // ms

RADIUS :=
	f32(CELL_SIZE) /
	2 *
	linalg.sin(linalg.to_radians(90 - THETA)) /
	linalg.sin(linalg.to_radians(THETA))


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
	log.debug(RADIUS)
	ctx := renderer.init()
	state.graphics_ctx = &ctx
	defer renderer.cleanup(state.graphics_ctx)

	// poll for queued events each game loop
	event: SDL.Event

	NOW := SDL.GetPerformanceCounter()
	LAST: u64
	delta_time: f64

	// textures_atlas := renderer.load_texture("./spritesheet.png", state.graphics_ctx)
	// defer SDL.DestroyTexture(textures_atlas)

	for x in 0 ..< BOARD_WIDTH {
		for y in 0 ..< BOARD_HEIGHT {
			idx := point_to_index({x, y})
			symbol := rand.choice_enum(Symbol)

			state.game_board[idx] = {
				symbol = symbol,
			}
		}
	}

	os_ctx, _ := renderer.os_init(state.graphics_ctx)
	state.os_graphics_ctx = &os_ctx
	defer renderer.os_cleanup(state.os_graphics_ctx)

	SDL.ShowWindow(state.graphics_ctx.window)
	game_loop: for {
		if SDL.PollEvent(&event) {
			if end_game(&event) do break game_loop

			handle_events(&event)
		}

		LAST = NOW
		NOW = SDL.GetPerformanceCounter()
		delta_time = f64((NOW - LAST) * 1000 / SDL.GetPerformanceFrequency())

		switch rot in state.camera {
		case f32:
		case [3]f32:
			t := rot[2] + f32(delta_time)
			if t >= ROTATION_TIME {
				state.camera = rot[1]
			} else {
				state.camera = ([3]f32){rot[0], rot[1], t}
			}
		}

		// tiles + cursor
		tris: [BOARD_WIDTH * BOARD_HEIGHT * 2 + 8]renderer.Triangle
		tri_offset: int

		camera := linalg.matrix4_infinite_perspective_f32(
			fovy = 90,
			// aspect = 16 / 9,
			aspect = f32(state.graphics_ctx.window_w / state.graphics_ctx.window_h),
			near = 0.0,
		)
		camera_rotation: f32

		switch rot in state.camera {
		case f32:
			camera_rotation = rot
		case [3]f32:
			camera_rotation = linalg.lerp(rot[0], rot[1], rot[2] / ROTATION_TIME)
		}

		camera *= linalg.matrix4_translate_f32({0, -15, -20})
		camera *= linalg.matrix4_rotate_f32(linalg.to_radians(camera_rotation), {0, 1, 0})

		make_quad :: proc(
			tris: []renderer.Triangle,
			x_offset: int,
			tris_offset: int,
			corners: [4]renderer.Point,
			color: renderer.Color,
			camera: linalg.Matrix4f32,
		) {
			//   p0 +------+ p3
			//      |      |
			//      |      |
			//   p1 +------+ p2
			cam_pts: [4]renderer.Point

			// apply camera
			for pt, idx in corners {
				cam_pts[idx] = linalg.matrix_mul_vector(camera, pt)
			}
			tris[tris_offset] = {
				points = {cam_pts[0], cam_pts[1], cam_pts[2]},
				colors = {color, color, color},
			}
			tris[tris_offset + 1] = {
				points = {cam_pts[0], cam_pts[2], cam_pts[3]},
				colors = {color, color, color},
			}
		}

		// DRAW CELLS
		for cell, idx in state.game_board {
			point := index_to_point(idx)
			color := symbol_to_color(cell.symbol)

			x_left: f32 = CELL_SIZE / -2
			x_right: f32 = CELL_SIZE / 2
			y_bottom := f32(point.y * CELL_SIZE)
			y_top := y_bottom + CELL_SIZE

			cursor_left_idx := point_to_index(state.cursor.left)
			cursor_right_idx := point_to_index(state.cursor.right)

			local_radius :=
				idx == cursor_left_idx || idx == cursor_right_idx ? RADIUS * 1.1 : RADIUS

			//     p7 +------+ p4
			//       /|     /|
			//   p0 +-+----+ | p3
			//      | |p6  | |
			//      | +----+-+ p5
			//      |/     |/
			//   p1 +------+ p2
			p0: renderer.Point = {x_left, y_top, local_radius, 1}
			p1: renderer.Point = {x_left, y_bottom, local_radius, 1}
			p2: renderer.Point = {x_right, y_bottom, local_radius, 1}
			p3: renderer.Point = {x_right, y_top, local_radius, 1}
			p4: renderer.Point = {x_right, y_top, local_radius - CELL_SIZE, 1}
			p5: renderer.Point = {x_right, y_bottom, local_radius - CELL_SIZE, 1}
			p6: renderer.Point = {x_left, y_bottom, local_radius - CELL_SIZE, 1}
			p7: renderer.Point = {x_left, y_top, local_radius - CELL_SIZE, 1}

			// FRONT
			quad_1: [4]renderer.Point = {p0, p1, p2, p3}
			// TOP
			// quad_2: [4]renderer.Point = {p7, p0, p3, p4}
			// BOTTOM
			// quad_3: [4]renderer.Point = {p1, p6, p5, p2}
			// LEFT
			// quad_4: [4]renderer.Point = {p7, p6, p1, p0}
			// RIGHT
			// quad_5: [4]renderer.Point = {p3, p2, p5, p4}
			// BACK
			// quad_6: [4]renderer.Point = {p4, p5, p6, p7}

			rot_deg := f32(point.x * (360 / BOARD_WIDTH))
			rot_mat := linalg.matrix4_rotate_f32(linalg.to_radians(rot_deg), {0, 1, 0})

			for pt, idx in quad_1 {
				quad_1[idx] = pt * rot_mat
			}
			// for pt, idx in quad_2 {
			// 	quad_2[idx] = pt * rot_mat
			// }
			// for pt, idx in quad_3 {
			//             quad_3[idx] = pt * rot_mat
			// }
			// for pt, idx in quad_4 {
			// 	quad_4[idx] = pt * rot_mat
			// }
			// for pt, idx in quad_5 {
			// 	quad_5[idx] = pt * rot_mat
			// }
			// for pt, idx in quad_6 {
			// 	quad_6[idx] = pt * rot_mat
			// }

			make_quad(tris[:], point.x, tri_offset, quad_1, color, camera)
			tri_offset += 2
			// make_quad(tris[:], point.x, tri_offset, quad_2, color, camera)
			// tri_offset += 2
			// make_quad(tris[:], point.x, tri_offset, quad_3, color, camera)
			// tri_offset += 2
			// make_quad(tris[:], point.x, tri_offset, quad_4, color, camera)
			// tri_offset += 2
			// make_quad(tris[:], point.x, tri_offset, quad_5, color, camera)
			// tri_offset += 2
			// make_quad(tris[:], point.x, tri_offset, quad_6, color, camera)
			// tri_offset += 2
		}

		{ 	// DRAW CURSOR
			x_left: f32 = CELL_SIZE / -2
			x_right: f32 = CELL_SIZE / 2
			y_bottom_right := f32(state.cursor.left.y * CELL_SIZE)
			y_top_right := y_bottom_right + CELL_SIZE
			y_bottom_left := f32(state.cursor.right.y * CELL_SIZE)
			y_top_left := y_bottom_left + CELL_SIZE

			//   ulo +------------------------+ uro
			//       | uli +------------+ uri |
			//       |     |            |     |
			//       | lli +------------+ lri |
			//   llo +------------------------+ lro
			//
			// quads:
			//   ulo,uli,uri,uro - upper portion
			//   ulo,llo,lli,uli - left portion
			//   lli,llo,lro,lri - lower portion
			//   uri,lri,lro,uro - right portion

			outer_offset: f32 = 0.2
			rot_left_deg := f32(state.cursor.left.x * (360 / BOARD_WIDTH))
			rot_left_mat := linalg.matrix4_rotate_f32(linalg.to_radians(rot_left_deg), {0, 1, 0})
			rot_right_deg := f32(state.cursor.right.x * (360 / BOARD_WIDTH))
			rot_right_mat := linalg.matrix4_rotate_f32(linalg.to_radians(rot_right_deg), {0, 1, 0})

			upper_left_inner: renderer.Point = {x_left, y_top_left, RADIUS, 1}
			upper_left_outer: renderer.Point =
				upper_left_inner + {-outer_offset, outer_offset, 0, 0}
			lower_left_inner: renderer.Point = {x_left, y_bottom_left, RADIUS, 1}
			lower_left_outer: renderer.Point =
				lower_left_inner + {-outer_offset, -outer_offset, 0, 0}
			lower_right_inner: renderer.Point = {x_right, y_bottom_right, RADIUS, 1}
			lower_right_outer: renderer.Point =
				lower_right_inner + {outer_offset, -outer_offset, 0, 0}
			upper_right_inner: renderer.Point = {x_right, y_top_right, RADIUS, 1}
			upper_right_outer: renderer.Point =
				upper_right_inner + {outer_offset, outer_offset, 0, 0}

			// upper_left_inner *= rot_left_mat
			// lower_left_inner *= rot_left_mat
			// upper_right_inner *= rot_left_mat
			// lower_right_inner *= rot_left_mat

			white: renderer.Color = {1, 1, 1, 1}

			upper: [4]renderer.Point = {
				upper_left_outer * rot_right_mat,
				upper_left_inner * rot_right_mat,
				upper_right_inner * rot_left_mat,
				upper_right_outer * rot_left_mat,
			}
			left: [4]renderer.Point = {
				upper_left_outer * rot_right_mat,
				lower_left_outer * rot_right_mat,
				lower_left_inner * rot_right_mat,
				upper_left_inner * rot_right_mat,
			}
			bottom: [4]renderer.Point = {
				lower_left_inner * rot_right_mat,
				lower_left_outer * rot_right_mat,
				lower_right_outer * rot_left_mat,
				lower_right_inner * rot_left_mat,
			}
			right: [4]renderer.Point = {
				upper_right_inner * rot_left_mat,
				lower_right_inner * rot_left_mat,
				lower_right_outer * rot_left_mat,
				upper_right_outer * rot_left_mat,
			}

			make_quad(tris[:], state.cursor.left.x, tri_offset, upper, white, camera)
			make_quad(tris[:], state.cursor.left.x, tri_offset + 2, left, white, camera)
			make_quad(tris[:], state.cursor.left.x, tri_offset + 4, bottom, white, camera)
			make_quad(tris[:], state.cursor.left.x, tri_offset + 6, right, white, camera)
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
		// 		state.graphics_ctx.sdl_renderer,
		// 		textures_atlas,
		// 		&src_rect,
		// 		&dest_rect_left,
		// 	)
		// 	SDL.RenderCopyEx(
		// 		state.graphics_ctx.sdl_renderer,
		// 		textures_atlas,
		// 		&src_rect,
		// 		&dest_rect_right,
		// 		0,
		// 		nil,
		// 		SDL.RendererFlip.HORIZONTAL,
		// 	)
		// }

		// // END update and render

		// renderer.draw_scene(state.graphics_ctx)

		renderer.render(state.graphics_ctx, state.os_graphics_ctx, tris[:], {0, 0, 0, 1})
	}

	delete(keys_down)
}

Point2d :: distinct [2]int

point_to_index :: proc(point: Point2d) -> int {
	return (point.y * BOARD_WIDTH) + point.x
}

index_to_point :: proc(index: int) -> (point: Point2d) {
	point.x = index %% BOARD_WIDTH
	point.y = index / BOARD_WIDTH

	return
}

RENDER_FLAGS :: SDL.RENDERER_ACCELERATED
WINDOW_FLAGS :: SDL.WINDOW_SHOWN | SDL.WINDOW_RESIZABLE


// State

State :: struct {
	graphics_ctx:    ^renderer.GraphicsContext,
	os_graphics_ctx: ^renderer.OsGrpahicsContext,

	//
	view:            View,

	//
	game_board:      Board,
	cursor:          struct {
		left:  Point2d,
		right: Point2d,
	},
	camera:          union #no_nil {
		f32,
		[3]f32,
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
	cursor = {left = {0, 0}, right = {1, 0}},
	camera = ROTATION_DEG / 2,
}


handle_events :: proc(event: ^SDL.Event) {

	if event.type == SDL.EventType.WINDOWEVENT {
		if (event.window.windowID == SDL.GetWindowID(state.graphics_ctx.window)) {
			if event.window.event == SDL.WindowEventID.RESIZED {
				state.graphics_ctx.window_w = event.window.data1
				state.graphics_ctx.window_h = event.window.data2
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
		cursor_move_by(&state.cursor.left, {0, 1})
		cursor_move_by(&state.cursor.right, {0, 1})
	case .A:
		cursor_move_by(&state.cursor.left, {1, 0})
		cursor_move_by(&state.cursor.right, {1, 0})

		switch rot in state.camera {
		case f32:
			state.camera = ([3]f32){rot, rot + ROTATION_DEG, 0}
		case [3]f32:
			state.camera = ([3]f32){rot[0], rot[1] + ROTATION_DEG, rot[2]}
		}
	case .S:
		cursor_move_by(&state.cursor.left, {0, -1})
		cursor_move_by(&state.cursor.right, {0, -1})
	case .D:
		cursor_move_by(&state.cursor.left, {-1, 0})
		cursor_move_by(&state.cursor.right, {-1, 0})

		switch rot in state.camera {
		case f32:
			state.camera = ([3]f32){rot, rot - ROTATION_DEG, 0}
		case [3]f32:
			state.camera = ([3]f32){rot[0], rot[1] - ROTATION_DEG, rot[2]}
		}
	}
}

keys_down: map[SDL.Keycode]struct {}

cursor_move_by :: proc(cursor: ^Point2d, amount: Point2d) {
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
