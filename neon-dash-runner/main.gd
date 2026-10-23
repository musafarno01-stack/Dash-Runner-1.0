extends Node2D

enum GameState { MENU, PLAYING, PAUSED, GAME_OVER }

const FLOOR_Y: float = 440.0
const PLAYER_X: float = 170.0
const PLAYER_WIDTH: float = 42.0
const PLAYER_HEIGHT: float = 62.0
const SAVE_PATH: String = "user://neon_dash.cfg"

var state: GameState = GameState.MENU
var obstacles: Array[Dictionary] = []
var coins: Array[Dictionary] = []

var player_bottom: float = FLOOR_Y
var vertical_speed: float = 0.0
var slide_timer: float = 0.0
var is_sliding: bool = false

var elapsed: float = 0.0
var score: int = 0
var coin_count: int = 0
var best_score: int = 0
var world_speed: float = 360.0
var spawn_timer: float = 1.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_load_best_score()
	queue_redraw()


func _process(delta: float) -> void:
	if state == GameState.PLAYING:
		_update_game(delta)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match state:
			GameState.MENU:
				if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
					_start_game()

			GameState.PLAYING:
				if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
					state = GameState.PAUSED
				elif event.keycode == KEY_SPACE or event.keycode == KEY_UP or event.keycode == KEY_W:
					_jump()
				elif event.keycode == KEY_DOWN or event.keycode == KEY_S or event.keycode == KEY_SHIFT:
					_begin_slide()

			GameState.PAUSED:
				if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
					state = GameState.PLAYING
				elif event.keycode == KEY_ENTER:
					_start_game()
				elif event.keycode == KEY_M:
					state = GameState.MENU

			GameState.GAME_OVER:
				if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
					_start_game()
				elif event.keycode == KEY_M or event.keycode == KEY_ESCAPE:
					state = GameState.MENU

	if event is InputEventScreenTouch and event.pressed:
		_handle_tap(event.position)
	elif event is InputEventMouseButton and event.pressed:
		_handle_tap(event.position)


func _handle_tap(position: Vector2) -> void:
	match state:
		GameState.MENU, GameState.GAME_OVER:
			_start_game()
		GameState.PAUSED:
			state = GameState.PLAYING
		GameState.PLAYING:
			if position.x > get_viewport_rect().size.x * 0.65:
				_begin_slide()
			else:
				_jump()


func _start_game() -> void:
	state = GameState.PLAYING
	obstacles.clear()
	coins.clear()
	elapsed = 0.0
	score = 0
	coin_count = 0
	world_speed = 360.0
	spawn_timer = 1.0
	player_bottom = FLOOR_Y
	vertical_speed = 0.0
	slide_timer = 0.0
	is_sliding = false


func _update_game(delta: float) -> void:
	elapsed += delta
	score = int(elapsed * 10.0) + coin_count * 25
	world_speed = minf(360.0 + elapsed * 5.0, 620.0)

	if player_bottom < FLOOR_Y:
		vertical_speed += 1500.0 * delta
		player_bottom += vertical_speed * delta
		if player_bottom >= FLOOR_Y:
			player_bottom = FLOOR_Y
			vertical_speed = 0.0

	if slide_timer > 0.0:
		slide_timer = maxf(0.0, slide_timer - delta)
		is_sliding = slide_timer > 0.0

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_items()
		spawn_timer = maxf(0.78, 1.45 - elapsed * 0.006) + rng.randf_range(0.0, 0.4)

	for i in range(obstacles.size() - 1, -1, -1):
		var obstacle: Dictionary = obstacles[i]
		obstacle["x"] = float(obstacle["x"]) - world_speed * delta
		obstacles[i] = obstacle
		if float(obstacle["x"]) < -100.0:
			obstacles.remove_at(i)

	for i in range(coins.size() - 1, -1, -1):
		var coin: Dictionary = coins[i]
		coin["x"] = float(coin["x"]) - world_speed * delta
		coins[i] = coin
		if float(coin["x"]) < -50.0:
			coins.remove_at(i)

	_check_collisions()


func _spawn_items() -> void:
	var spawn_x: float = get_viewport_rect().size.x + 60.0
	var overhead: bool = rng.randf() < 0.35
	obstacles.append({"x": spawn_x, "overhead": overhead})

	if rng.randf() < 0.72:
		coins.append({
			"x": spawn_x + rng.randf_range(100.0, 230.0),
			"y": rng.randf_range(300.0, 375.0)
		})


func _jump() -> void:
	if player_bottom >= FLOOR_Y and not is_sliding:
		vertical_speed = -650.0


func _begin_slide() -> void:
	if player_bottom >= FLOOR_Y:
		is_sliding = true
		slide_timer = 0.65


func _check_collisions() -> void:
	var player_height: float = 30.0 if is_sliding else PLAYER_HEIGHT
	var player_top: float = player_bottom - player_height
	var player_rect := Rect2(
		PLAYER_X - PLAYER_WIDTH / 2.0,
		player_top,
		PLAYER_WIDTH,
		player_height
	)

	for obstacle in obstacles:
		var obstacle_x: float = float(obstacle["x"])
		var hitbox: Rect2

		if bool(obstacle["overhead"]):
			# Standing players hit this; sliding players pass underneath.
			hitbox = Rect2(obstacle_x - 25.0, FLOOR_Y - 65.0, 50.0, 28.0)
		else:
			hitbox = Rect2(obstacle_x - 24.0, FLOOR_Y - 48.0, 48.0, 48.0)

		if player_rect.intersects(hitbox):
			_end_game()
			return

	for i in range(coins.size() - 1, -1, -1):
		var coin: Dictionary = coins[i]
		var coin_rect := Rect2(
			float(coin["x"]) - 14.0,
			float(coin["y"]) - 14.0,
			28.0,
			28.0
		)
		if player_rect.intersects(coin_rect):
			coin_count += 1
			coins.remove_at(i)


func _end_game() -> void:
	if state != GameState.PLAYING:
		return

	state = GameState.GAME_OVER
	score = int(elapsed * 10.0) + coin_count * 25

	if score > best_score:
		best_score = score
		_save_best_score()


func _load_best_score() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		best_score = int(config.get_value("scores", "best", 0))


func _save_best_score() -> void:
	var config := ConfigFile.new()
	config.set_value("scores", "best", best_score)
	config.save(SAVE_PATH)


func _draw() -> void:
	var screen_size: Vector2 = get_viewport_rect().size

	draw_rect(Rect2(Vector2.ZERO, screen_size), Color(0.025, 0.02, 0.08))

	# Simple procedural skyline.
	for i in range(12):
		var building_x: float = float(i) * 92.0
		var building_height: float = 70.0 + float((i * 37) % 100)
		draw_rect(
			Rect2(building_x, FLOOR_Y - building_height, 64.0, building_height),
			Color(0.07, 0.045, 0.17)
		)

	draw_line(
		Vector2(0.0, FLOOR_Y),
		Vector2(screen_size.x, FLOOR_Y),
		Color(0.0, 0.95, 1.0),
		3.0
	)

	for obstacle in obstacles:
		var x: float = float(obstacle["x"])

		if bool(obstacle["overhead"]):
			draw_rect(
				Rect2(x - 25.0, FLOOR_Y - 65.0, 50.0, 28.0),
				Color(1.0, 0.15, 0.55)
			)
			draw_line(
				Vector2(x - 25.0, FLOOR_Y - 35.0),
				Vector2(x - 25.0, FLOOR_Y - 18.0),
				Color(1.0, 0.15, 0.55),
				4.0
			)
			draw_line(
				Vector2(x + 25.0, FLOOR_Y - 35.0),
				Vector2(x + 25.0, FLOOR_Y - 18.0),
				Color(1.0, 0.15, 0.55),
				4.0
			)
		else:
			draw_colored_polygon(
				PackedVector2Array([
					Vector2(x - 24.0, FLOOR_Y),
					Vector2(x, FLOOR_Y - 48.0),
					Vector2(x + 24.0, FLOOR_Y)
				]),
				Color(1.0, 0.15, 0.55)
			)

	for coin in coins:
		var center := Vector2(float(coin["x"]), float(coin["y"]))
		draw_circle(center, 13.0, Color(1.0, 0.82, 0.15))
		draw_circle(center, 7.0, Color(0.12, 0.07, 0.2))

	var player_height: float = 30.0 if is_sliding else PLAYER_HEIGHT
	var player_top: float = player_bottom - player_height
	draw_rect(
		Rect2(PLAYER_X - PLAYER_WIDTH / 2.0, player_top, PLAYER_WIDTH, player_height),
		Color(0.0, 0.95, 1.0)
	)
	draw_rect(
		Rect2(PLAYER_X - 10.0, player_top + 12.0, 20.0, 8.0),
		Color(0.03, 0.03, 0.1)
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(24.0, 36.0),
		"Score: %d   Coins: %d   Best: %d" % [score, coin_count, best_score],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		22,
		Color.WHITE
	)

	match state:
		GameState.MENU:
			_draw_message(
				screen_size,
				"NEON DASH RUNNER",
				"Press ENTER or tap to play\nSPACE / UP: jump     DOWN: slide"
			)
		GameState.PAUSED:
			_draw_message(
				screen_size,
				"PAUSED",
				"P / ESC: resume     ENTER: restart     M: menu"
			)
		GameState.GAME_OVER:
			_draw_message(
				screen_size,
				"GAME OVER",
				"Score: %d     Coins: %d\nENTER / tap: replay     M: menu"
				% [score, coin_count]
			)


func _draw_message(screen_size: Vector2, title: String, subtitle: String) -> void:
	draw_rect(
		Rect2(Vector2.ZERO, screen_size),
		Color(0.015, 0.01, 0.06, 0.78)
	)

	var center_x: float = screen_size.x * 0.5
	draw_string(
		ThemeDB.fallback_font,
		Vector2(center_x - 220.0, 220.0),
		title,
		HORIZONTAL_ALIGNMENT_CENTER,
		440.0,
		38,
		Color(0.0, 0.95, 1.0)
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(center_x - 280.0, 275.0),
		subtitle,
		HORIZONTAL_ALIGNMENT_CENTER,
		560.0,
		19,
		Color.WHITE
	)
