package main

import "core:math/rand"
import rl "vendor:raylib"

CELL_SIZE :: 24

DifficultyLevel :: struct {
	board_size: [2]i32,
	bomb_count: i32,
	name:       string,
}

difficulty_levels := [?]DifficultyLevel {
	{board_size = {9, 9}, bomb_count = 10, name = "Easy"},
	{board_size = {16, 16}, bomb_count = 40, name = "Medium"},
	{board_size = {30, 16}, bomb_count = 99, name = "Hard"},
}
difficulty: int = 0

state: enum {
	Undefined,
	Playing,
	Lost,
	Won,
}

CellState :: enum u8 {
	Initial,
	Opened,
	Flagged,
	Uncertain,
}

start_time: f32
last_time: f32

// column-major
board_cells: [32][32]CellState
board_bombs: [32][32]bool
board_numbers: [32][32]u8

cell_tex: rl.Texture2D
digits_tex: rl.Texture2D
faces_tex: rl.Texture2D
numbers_tex: rl.Texture2D

main :: proc() {
	rl.SetConfigFlags({.WINDOW_HIGHDPI})
	rl.InitWindow(get_window_size(difficulty_levels[difficulty]), "Minesweeper")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	rl.SetMouseScale(1, 1)

	cell_tex = create_icon_texture(#load("icons/cell.png"))
	digits_tex = create_icon_texture(#load("icons/digits.png"))
	faces_tex = create_icon_texture(#load("icons/faces.png"))
	numbers_tex = create_icon_texture(#load("icons/numbers.png"))

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground({192, 192, 192, 255})
		main_loop()
		rl.EndDrawing()
	}
}

create_icon_texture :: proc(png: []u8) -> rl.Texture2D {
	img := rl.LoadImageFromMemory(".png", raw_data(png), i32(len(png)))
	assert(rl.IsImageValid(img))
	tex := rl.LoadTextureFromImage(img)
	assert(rl.IsTextureValid(tex))
	rl.UnloadImage(img)
	return tex
}

get_window_size :: proc(level: DifficultyLevel) -> (i32, i32) {
	return level.board_size.x * CELL_SIZE + 14 * 2, level.board_size.y * CELL_SIZE + 6 * 2 + 62
}

set_difficulty :: proc(d: int) {
	difficulty = d
	rl.SetWindowSize(get_window_size(difficulty_levels[d]))
}

zero_game_state :: proc() {
	state = .Undefined
	start_time = 0
	last_time = 0
	board_cells = CellState.Initial // array op
	board_bombs = false // array op
	board_numbers = 0 // array op
}

start_game :: proc(click_i, click_j: int) {
	state = .Playing
	start_time = f32(rl.GetTime())
	last_time = start_time
	board_cells = CellState.Initial // array op

	bsize := cast([2]int)difficulty_levels[difficulty].board_size
	bomb_count := int(difficulty_levels[difficulty].bomb_count)

	for k in 0 ..< bomb_count {
		for _ in 0 ..= 99 {
			i := rand.int_max(bsize.x)
			j := rand.int_max(bsize.y)
			if !board_bombs[i][j] && !(i == click_i && j == click_j) {
				board_bombs[i][j] = true
				break
			}
		}
	}

	for i in 0 ..< bsize.x {
		for j in 0 ..< bsize.y {
			n: u8
			if i > 0 && j > 0 do n += u8(board_bombs[i - 1][j - 1])
			if j > 0 do n += u8(board_bombs[i][j - 1])
			if i > 0 do n += u8(board_bombs[i - 1][j])
			if j + 1 < bsize.y do n += u8(board_bombs[i][j + 1])
			if i + 1 < bsize.x do n += u8(board_bombs[i + 1][j])
			if i > 0 && j + 1 < bsize.y do n += u8(board_bombs[i - 1][j + 1])
			if i + 1 < bsize.x && j > 0 do n += u8(board_bombs[i + 1][j - 1])
			if i + 1 < bsize.x && j + 1 < bsize.y do n += u8(board_bombs[i + 1][j + 1])
			board_numbers[i][j] = n
		}
	}
}

main_loop :: proc() {
	ww, wh := get_window_size(difficulty_levels[difficulty])
	bsize := cast([2]int)difficulty_levels[difficulty].board_size

	mouse_pos := rl.GetMousePosition()
	dt := rl.GetFrameTime()
	if state == .Playing {
		last_time = f32(rl.GetTime())
	}

	field := rl.Rectangle{10 + 4, 56 + 4, f32(bsize.x) * CELL_SIZE, f32(bsize.y) * CELL_SIZE}
	trying_to_open_cell := false
	check_if_should_win := false

	for i in 0 ..< bsize.x {
		for j in 0 ..< bsize.y {
			r := rl.Rectangle {
				field.x + CELL_SIZE * f32(i),
				field.y + CELL_SIZE * f32(j),
				CELL_SIZE,
				CELL_SIZE,
			}
			hovered := !(state == .Won || state == .Lost) && rl.CheckCollisionPointRec(mouse_pos, r)
			clicked := hovered && rl.IsMouseButtonReleased(.LEFT)
			clicked_right := hovered && rl.IsMouseButtonPressed(.RIGHT)

			if hovered && rl.IsMouseButtonDown(.LEFT) && board_cells[i][j] != .Opened {
				trying_to_open_cell = true
			}

			if state == .Undefined && (clicked || clicked_right) {
				start_game(i, j)
			}

			if clicked && board_cells[i][j] != .Flagged {
				if !board_bombs[i][j] {
					if board_numbers[i][j] == 0 {
						floodfill_click(i, j)
					} else {
						board_cells[i][j] = .Opened
					}
					check_if_should_win = true
				} else {
					board_cells[i][j] = .Opened
					state = .Lost
				}
			} else if clicked_right {
				switch board_cells[i][j] {
				case .Opened: // ignored
				case .Initial:
					board_cells[i][j] = .Flagged
				case .Flagged:
					board_cells[i][j] = .Uncertain
				case .Uncertain:
					board_cells[i][j] = .Initial
				}
			}
		}
	}

	if check_if_should_win {
		got_non_opened_cells: bool
		for i in 0 ..< bsize.x {
			for j in 0 ..< bsize.y {
				if board_cells[i][j] != .Opened && !board_bombs[i][j] {
					got_non_opened_cells = true
					break
				}
			}
		}
		if !got_non_opened_cells {
			for i in 0 ..< bsize.x {
				for j in 0 ..< bsize.y {
					if board_bombs[i][j] {
						board_cells[i][j] = .Flagged
					}
				}
			}
			state = .Won
		}
	}

	flag_count: int
	for i in 0 ..< bsize.x {
		for j in 0 ..< bsize.y {
			if board_cells[i][j] == .Flagged {
				flag_count += 1
			}
		}
	}

	face := rl.Rectangle{(f32(ww) - 32) / 2, 14, 32, 32}
	face_hovered := rl.CheckCollisionPointRec(mouse_pos, face)
	face_pressed := face_hovered && rl.IsMouseButtonDown(.LEFT)
	face_clicked := face_hovered && rl.IsMouseButtonReleased(.LEFT)

	if face_clicked {
		zero_game_state()
	}

	show_levels := (state == .Undefined)
	levels: [3]rl.Rectangle
	for &r, i in levels {
		r = {14 + f32(i) * 24, 18, 24, 24}
	}
	for r, i in levels {
		hovered := rl.CheckCollisionPointRec(mouse_pos, r)
		clicked := hovered && rl.IsMouseButtonPressed(.LEFT)
		if clicked && show_levels {
			set_difficulty(i)
			break
		}
	}

	bomb_count := int(difficulty_levels[difficulty].bomb_count)

	Indicator :: struct {
		num:  int,
		rect: rl.Rectangle,
	}
	indicators := [2]Indicator { 	//
		{num = bomb_count - flag_count},
		{num = int(last_time - start_time)},
	}

	// --- drawing ---

	DrawEmbossedRect({0, 0, f32(ww), f32(wh)}, 4, false) // window frame
	top := DrawEmbossedRect({10, 10, f32(ww) - 20, 40}, 2, true)
	face = DrawEmbossedRect(face, 2, face_pressed)
	face_idx: f32 = 0
	if state == .Won {
		face_idx = 2
	} else if state == .Lost {
		face_idx = 3
	} else if trying_to_open_cell {
		face_idx = 1
	}
	rl.DrawTexturePro(faces_tex, {0, face_idx * 56, 56, 56}, face, {}, 0, rl.WHITE)

	if !show_levels {
		indicators[0].rect = DrawEmbossedRect({top.x + 5, top.y + 6, 41, 25}, 1, true)
		rl.DrawRectangleRec(indicators[0].rect, rl.BLACK)
	}
	indicators[1].rect = DrawEmbossedRect({top.x + top.width - 5 - 41, top.y + 6, 41, 25}, 1, true)
	rl.DrawRectangleRec(indicators[1].rect, rl.BLACK)

	if show_levels {
		for r, i in levels {
			if difficulty != i {
				DrawEmbossedRect(r, 1, false)
			}
			rl.DrawTexturePro(numbers_tex, {0, f32(i) * 64, 64, 64}, r, {}, 0, rl.WHITE)
		}
	}

	for indicator, i in indicators {
		if show_levels && i == 0 do continue

		a, nonneg := abs(indicator.num), indicator.num >= 0
		digits := [3]int{nonneg ? (a / 100) % 10 : 10, (a / 10) % 10, a % 10}
		rs := rl.Rectangle{0, 0, 24, 44}
		rd := indicator.rect
		rd.x += 1
		rd.width = rd.height * (rs.width / rs.height)
		for dgt in digits {
			rs.y = f32(dgt) * rs.height
			rl.DrawTexturePro(digits_tex, rs, rd, {}, 0, rl.WHITE)
			rd.x += rd.width
		}
	}

	DrawEmbossedRect({field.x - 4, field.y - 4, field.width + 8, field.height + 8}, 4, true)

	for i in 1 ..< bsize.x {
		rl.DrawLineV(
			{field.x + CELL_SIZE * f32(i), field.y},
			{field.x + CELL_SIZE * f32(i), field.y + field.height},
			rl.DARKGRAY,
		)
	}
	for j in 1 ..< bsize.y {
		rl.DrawLineV(
			{field.x, field.y + CELL_SIZE * f32(j)},
			{field.x + field.width, field.y + CELL_SIZE * f32(j)},
			rl.DARKGRAY,
		)
	}

	for i in 0 ..< bsize.x {
		for j in 0 ..< bsize.y {
			r := rl.Rectangle {
				field.x + CELL_SIZE * f32(i),
				field.y + CELL_SIZE * f32(j),
				CELL_SIZE,
				CELL_SIZE,
			}
			hovered := !(state == .Won || state == .Lost) && rl.CheckCollisionPointRec(mouse_pos, r)
			pressed := hovered && rl.IsMouseButtonDown(.LEFT)

			if state == .Lost && board_bombs[i][j] {
				if board_cells[i][j] == .Opened {
					rl.DrawRectangleRec(r, rl.RED)
				}
				rd := rl.Rectangle{0, 2 * 64, 64, 64}
				rl.DrawTexturePro(cell_tex, rd, r, {}, 0, rl.WHITE)
				if board_cells[i][j] == .Flagged {
					r := rl.Rectangle{r.x + 2, r.y + 2, r.width - 4, r.height - 4}
					rl.DrawLineEx({r.x, r.y}, {r.x + r.width, r.y + r.height}, 2, rl.RED)
					rl.DrawLineEx({r.x + r.width, r.y}, {r.x, r.y + r.height}, 2, rl.RED)
				}
			} else {
				if board_cells[i][j] != .Opened {
					r = DrawEmbossedRect(r, pressed ? 3 : 2, false)
				}
				switch board_cells[i][j] {
				case .Initial: // nothing
				case .Opened:
					if board_numbers[i][j] > 0 {
						rd := rl.Rectangle{0, f32(board_numbers[i][j] - 1) * 64, 64, 64}
						rl.DrawTexturePro(numbers_tex, rd, r, {}, 0, rl.WHITE)
					}
				case .Flagged:
					rd := rl.Rectangle{0, 0, 64, 64}
					rl.DrawTexturePro(cell_tex, rd, r, {}, 0, rl.WHITE)
				case .Uncertain:
					rd := rl.Rectangle{0, 64, 64, 64}
					rl.DrawTexturePro(cell_tex, rd, r, {}, 0, rl.WHITE)
				}
			}
		}
	}
}

floodfill_click :: proc(click_i, click_j: int) {
	board_cells[click_i][click_j] = .Opened
	if board_numbers[click_i][click_j] > 0 {return}

	bsize := cast([2]int)difficulty_levels[difficulty].board_size

	for i in click_i - 1 ..= click_i + 1 {
		for j in click_j - 1 ..= click_j + 1 {
			if !(i == click_i && j == click_j) && (i >= 0 && j >= 0 && i < bsize.x && j < bsize.y) {
				if board_cells[i][j] != .Opened {
					floodfill_click(i, j)
				}
			}
		}
	}
}

DrawEmbossedRect :: proc(r: rl.Rectangle, b: f32, pressed: bool) -> rl.Rectangle {
	dim :: rl.Color{128, 128, 128, 255}
	lite :: rl.Color{255, 255, 255, 255}
	color1 := pressed ? dim : lite
	color2 := pressed ? lite : dim
	// left
	rl.DrawTriangle({r.x, r.y}, {r.x, r.y + r.height}, {r.x + b, r.y + r.height - b}, color1)
	rl.DrawTriangle({r.x, r.y}, {r.x + b, r.y + r.height - b}, {r.x + b, r.y + b}, color1)
	// top
	rl.DrawTriangle({r.x, r.y}, {r.x + b, r.y + b}, {r.x + r.width - b, r.y + b}, color1)
	rl.DrawTriangle({r.x, r.y}, {r.x + r.width - b, r.y + b}, {r.x + r.width, r.y}, color1)
	// right
	rl.DrawTriangle(
		{r.x + r.width, r.y},
		{r.x + r.width - b, r.y + b},
		{r.x + r.width - b, r.y + r.height - b},
		color2,
	)
	rl.DrawTriangle(
		{r.x + r.width, r.y},
		{r.x + r.width - b, r.y + r.height - b},
		{r.x + r.width, r.y + r.height},
		color2,
	)
	// bottom
	rl.DrawTriangle(
		{r.x, r.y + r.height},
		{r.x + r.width - b, r.y + r.height - b}, // swapped orientation
		{r.x + b, r.y + r.height - b},
		color2,
	)
	rl.DrawTriangle(
		{r.x, r.y + r.height},
		{r.x + r.width, r.y + r.height}, // swapped orientation
		{r.x + r.width - b, r.y + r.height - b},
		color2,
	)
	return {r.x + b, r.y + b, r.width - b * 2, r.height - b * 2}
}
