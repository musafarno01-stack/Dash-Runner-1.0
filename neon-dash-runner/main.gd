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
var particles: Array[Dictionary] = []

var player_bottom: float = FLOOR_Y
var vertical_speed: float = 0.0
var slide_timer: float = 0.0
var is_sliding: bool = false
var jumps_remaining: int = 2

var elapsed: float = 0.0
var score: int = 0
var coin_count: int = 0
var best_score: int = 0
var world_speed: float = 380.0
var spawn_timer: float = 1.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_load_best_score()
	queue_redraw()


func _process(delta: float) -> void:
	if state == GameState.PLAYING:
		_update_game(delta)
	
	# Update background particle juice
	for i in range(particles.size() - 1, -1, -1):
		var p = particles[i]
		p["x"] -= (world_speed * 0.4 + p["speed_offset"]) * delta
		if p["x"] < -20.0:
			particles.remove_at(i)
			
	# Spawn background dust particles continuously during gameplay
	if state == GameState.PLAYING and randf() < 0.3:
		particles.append({
			"x": 980.0,
			"y": randf_range(50.0, FLOOR_Y - 20.0),
			"radius": randf_range(1.5, 3.5),
			"speed_offset": randf_range(10.0, 50.0),
			"alpha": randf_range(0.2, 0.6)
		})

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


func _handle_tap(pos: Vector2) -> void:
	match state:
		GameState.MENU, GameState.GAME_OVER:
			_start_game()
		GameState.PAUSED:
			state = GameState.PLAYING
		GameState.PLAYING:
			# Mobile Friendly Layout: Left half of screen jumps/double jumps, Right half slides
			if pos.x > get_viewport_rect().size.x * 0.55:
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
	world_speed = 380.0
	spawn_timer = 0.8
	player_bottom = FLOOR_Y
	vertical_speed = 0.0
	slide_timer = 0.0
	is_sliding = false
	jumps_remaining = 2


func _update_game(delta: float) -> void:
	elapsed += delta
	score = int(elapsed * 12.0) + coin_count * 30
	world_speed = minf(380.0 + elapsed * 6.5, 680.0)

	# Physics & Gravity
	if player_bottom < FLOOR_Y:
		vertical_speed += 1700.0 * delta
		player_bottom += vertical_speed * delta
		if player_bottom >= FLOOR_Y:
			player_bottom = FLOOR_Y
			vertical_speed = 0.0
			jumps_remaining = 2

	if slide_timer > 0.0:
		slide_timer = maxf(0.0, slide_timer - delta)
		is_sliding = slide_timer > 0.0

	# Procedural Item Spawning with progressive scaling
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_items()
		spawn_timer = maxf(0.65, 1.3 - elapsed * 0.007) + rng.randf_range(0.0, 0.35)

	# Update Obstacles
	for i in range(obstacles.size() - 1, -1, -1):
		var obs: Dictionary = obstacles[i]
		obs["x"] = float(obs["x"]) - world_speed * delta
		obstacles[i] = obs
		if float(obs["x"]) < -120.0:
			obstacles.remove_at(i)

	# Update Coins
	for i in range(coins.size() - 1, -1, -1):
		var coin: Dictionary = coins[i]
		coin["x"] = float(coin["x"]) - world_speed * delta
		coins[i] = coin
		if float(coin["x"]) < -50.0:
			coins.remove_at(i)

	_check_collisions()


func _spawn_items() -> void:
	var spawn_x: float = get_viewport_rect().size.x + 80.0
	var overhead: bool = rng.randf() < 0.4
	obstacles.append({"x": spawn_x, "overhead": overhead})

	if rng.randf() < 0.75:
		coins.append({
			"x": spawn_x + rng.randf_range(110.0, 240.0),
			"y": rng.randf_range(280.0, 370.0)
		})


func _jump() -> void:
	if is_sliding:
		return
	if player_bottom >= FLOOR_Y:
		vertical_speed = -680.0
		jumps_remaining = 1
	elif jumps_remaining > 0:
		vertical_speed = -600.0
		jumps_remaining -= 1


func _begin_slide() -> void:
	if player_bottom >= FLOOR_Y:
		is_sliding = true
		slide_timer = 0.55
		vertical_speed = 0.0


func _check_collisions() -> void:
	var player_height: float = 30.0 if is_sliding else PLAYER_HEIGHT
	var player_top: float = player_bottom - player_height
	var player_rect := Rect2(
		PLAYER_X - PLAYER_WIDTH / 2.0,
		player_top,
		PLAYER_WIDTH,
		player_height
	)

	for obs in obstacles:
		var obs_x: float = float(obs["x"])
		var hitbox: Rect2

		if bool(obs["overhead"]):
			hitbox = Rect2(obs_x - 26.0, FLOOR_Y - 68.0, 52.0, 28.0)
		else:
			hitbox = Rect2(obs_x - 24.0, FLOOR_Y - 50.0, 48.0, 50.0)

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
	score = int(elapsed * 12.0) + coin_count * 30

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

	# Deep Cyberpunk Background Gradient Simulation via Rects
	draw_rect(Rect2(Vector2.ZERO, screen_size), Color(0.02, 0.015, 0.07))

	# Draw background glowing dust particles
	for p in particles:
		draw_circle(Vector2(p["x"], p["y"]), p["radius"], Color(0.6, 0.8, 1.0, p["alpha"]))

	# Procedural Skyline Backdrop
	for i in range(14):
		var building_x: float = float(i) * 85.0
		var building_height: float = 80.0 + float((i * 41) % 120)
		draw_rect(
			Rect2(building_x, FLOOR_Y - building_height, 60.0, building_height),
			Color(0.05, 0.035, 0.14)
		)

	# Neon Floor Grid Line with Glow Effect
	draw_line(
		Vector2(0.0, FLOOR_Y),
		Vector2(screen_size.x, FLOOR_Y),
		Color(0.0, 0.95, 1.0),
		4.0
	)
	draw_line(
		Vector2(0.0, FLOOR_Y + 2.0),
		Vector2(screen_size.x, FLOOR_Y + 2.0),
		Color(0.0, 0.5, 0.8, 0.3),
		8.0
	)

	# Draw Obstacles (Cyber Neon Pink)
	for obs in obstacles:
		var x: float = float(obs["x"])

		if bool(obs["overhead"]):
			draw_rect(
				Rect2(x - 26.0, FLOOR_Y - 68.0, 52.0, 28.0),
				Color(1.0, 0.1, 0.5)
			)
			draw_line(
				Vector2(x - 26.0, FLOOR_Y - 40.0),
				Vector2(x - 26.0, FLOOR_Y - 15.0),
				Color(1.0, 0.1, 0.5),
				4.0
			)
			draw_line(
				Vector2(x + 26.0, FLOOR_Y - 40.0),
				Vector2(x + 26.0, FLOOR_Y - 15.0),
				Color(1.0, 0.1, 0.5),
				4.0
			)
		else:
			draw_colored_polygon(
				PackedVector2Array([
					Vector2(x - 24.0, FLOOR_Y),
					Vector2(x, FLOOR_Y - 50.0),
					Vector2(x + 24.0, FLOOR_Y)
				]),
				Color(1.0, 0.1, 0.5)
			)

	# Draw Coins (Glowing Gold)
	for coin in coins:
		var center := Vector2(float(coin["x"]), float(coin["y"]))
		draw_circle(center, 14.0, Color(1.0, 0.85, 0.2))
		draw_circle(center, 8.0, Color(0.1, 0.05, 0.15))

	# Draw Player (Cyan Runner Box with Visor Details)
	var player_height: float = 30.0 if is_sliding else PLAYER_HEIGHT
	var player_top: float = player_bottom - player_height
	draw_rect(
		Rect2(PLAYER_X - PLAYER_WIDTH / 2.0, player_top, PLAYER_WIDTH, player_height),
		Color(0.0, 0.95, 1.0)
	)
	draw_rect(
		Rect2(PLAYER_X - 8.0, player_top + 10.0, 22.0, 8.0),
		Color(0.02, 0.02, 0.08)
	)

	# HUD Score Display
	draw_string(
		ThemeDB.fallback_font,
		Vector2(24.0, 38.0),
		"SCORE: %d    COINS: %d    BEST: %d" % [score, coin_count, best_score],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		20,
		Color(0.9, 0.95, 1.0)
	)

	# State Overlays
	match state:
		GameState.MENU:
			_draw_message(
				screen_size,
				"NEON DASH RUNNER",
				"TAP or ENTER to Play\nLeft Side: Jump (Double Jump supported)  |  Right Side: Slide"
			)
		GameState.PAUSED:
			_draw_message(
				screen_size,
				"GAME PAUSED",
				"P / ESC: Resume    |    ENTER: Restart    |    M: Menu"
			)
		GameState.GAME_OVER:
			_draw_message(
				screen_size,
				"GAME OVER",
				"Final Score: %d    Coins Collected: %d\nENTER / TAP to Play Again    |    M: Menu"
				% [score, coin_count]
			)


func _draw_message(screen_size: Vector2, title: String, subtitle: String) -> void:
	draw_rect(
		Rect2(Vector2.ZERO, screen_size),
		Color(0.01, 0.005, 0.05, 0.82)
	)

	var center_x: float = screen_size.x * 0.5
	draw_string(
		ThemeDB.fallback_font,
		Vector2(center_x - 240.0, 210.0),
		title,
		HORIZONTAL_ALIGNMENT_CENTER,
		480.0,
		40,
		Color(0.0, 0.95, 1.0)
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(center_x - 320.0, 270.0),
		subtitle,
		HORIZONTAL_ALIGNMENT_CENTER,
		640.0,
		18,
		Color.WHITE
	)
