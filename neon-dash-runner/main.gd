extends Node2D

enum GameState { MENU, PLAYING, PAUSED, GAME_OVER }

const FLOOR_Y: float = 440.0
const PLAYER_X: float = 170.0
const PLAYER_WIDTH: float = 38.0
const PLAYER_HEIGHT: float = 58.0
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
var world_speed: float = 400.0
var spawn_timer: float = 1.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Audio variables
var sound_enabled: bool = true
var audio_player: AudioStreamPlayer
var synth_generator: AudioStreamGenerator
var playback: AudioStreamGeneratorPlayback


func _ready() -> void:
	rng.randomize()
	_load_best_score()
	_setup_audio()
	queue_redraw()


func _setup_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	synth_generator = AudioStreamGenerator.new()
	synth_generator.mix_rate = 22050
	synth_generator.buffer_length = 0.1
	audio_player.stream = synth_generator
	add_child(audio_player)
	audio_player.play()
	playback = audio_player.get_stream_playback()


func _play_tone(freq: float, duration: float, type: String = "sine") -> void:
	if not sound_enabled or not playback:
		return
	# Simple procedural sound synthesizer to avoid missing audio files
	var frames_to_generate = int(22050 * duration)
	for i in range(frames_to_generate):
		if playback.get_frames_available() < 1:
			break
		var t = float(i) / 22050.0
		var sample = sin(t * freq * TAU)
		if type == "square":
			sample = 1.0 if sample > 0 else -1.0
		elif type == "noise":
			sample = randf_range(-1.0, 1.0)
		# Apply quick fade out envelope
		sample *= max(0.0, 1.0 - (float(i) / frames_to_generate))
		playback.push_frame(Vector2(sample * 0.15, sample * 0.15))


func _process(delta: float) -> void:
	if state == GameState.PLAYING:
		_update_game(delta)
	
	# Background glowing particle drift
	for i in range(particles.size() - 1, -1, -1):
		var p = particles[i]
		p["x"] -= (world_speed * 0.45 + p["speed_offset"]) * delta
		if p["x"] < -20.0:
			particles.remove_at(i)
			
	if state == GameState.PLAYING and randf() < 0.35:
		particles.append({
			"x": 980.0,
			"y": randf_range(40.0, FLOOR_Y - 20.0),
			"radius": randf_range(1.5, 3.5),
			"speed_offset": randf_range(15.0, 60.0),
			"alpha": randf_range(0.2, 0.7)
		})

	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match state:
			GameState.MENU:
				if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
					_start_game()
				elif event.keycode == KEY_M:
					_toggle_sound()

			GameState.PLAYING:
				if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
					state = GameState.PAUSED
				elif event.keycode == KEY_M:
					_toggle_sound()
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
					_toggle_sound()

			GameState.GAME_OVER:
				if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
					_start_game()
				elif event.keycode == KEY_M:
					_toggle_sound()

	if event is InputEventScreenTouch and event.pressed:
		_handle_tap(event.position)
	elif event is InputEventMouseButton and event.pressed:
		_handle_tap(event.position)


func _toggle_sound() -> void:
	sound_enabled = not sound_enabled
	_play_tone(600.0, 0.1)


func _handle_tap(pos: Vector2) -> void:
	# Check if tap was near top-right corner (Mute button toggle zone)
	if pos.x > 840.0 and pos.y < 60.0:
		_toggle_sound()
		return

	match state:
		GameState.MENU, GameState.GAME_OVER:
			_start_game()
		GameState.PAUSED:
			state = GameState.PLAYING
		GameState.PLAYING:
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
	world_speed = 400.0
	spawn_timer = 0.8
	player_bottom = FLOOR_Y
	vertical_speed = 0.0
	slide_timer = 0.0
	is_sliding = false
	jumps_remaining = 2
	_play_tone(440.0, 0.15)


func _update_game(delta: float) -> void:
	elapsed += delta
	score = int(elapsed * 15.0) + coin_count * 35
	world_speed = minf(400.0 + elapsed * 7.0, 720.0)

	# Physics & Gravity with responsive jump arc
	if player_bottom < FLOOR_Y:
		vertical_speed += 1850.0 * delta
		player_bottom += vertical_speed * delta
		if player_bottom >= FLOOR_Y:
			player_bottom = FLOOR_Y
			vertical_speed = 0.0
			jumps_remaining = 2

	if slide_timer > 0.0:
		slide_timer = maxf(0.0, slide_timer - delta)
		is_sliding = slide_timer > 0.0

	# Progressive Spawner
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_items()
		spawn_timer = maxf(0.6, 1.25 - elapsed * 0.008) + rng.randf_range(0.0, 0.3)

	# Obstacles update
	for i in range(obstacles.size() - 1, -1, -1):
		var obs: Dictionary = obstacles[i]
		obs["x"] = float(obs["x"]) - world_speed * delta
		obstacles[i] = obs
		if float(obs["x"]) < -120.0:
			obstacles.remove_at(i)

	# Coins update
	for i in range(coins.size() - 1, -1, -1):
		var coin: Dictionary = coins[i]
		coin["x"] = float(coin["x"]) - world_speed * delta
		coins[i] = coin
		if float(coin["x"]) < -50.0:
			coins.remove_at(i)

	_check_collisions()


func _spawn_items() -> void:
	var spawn_x: float = get_viewport_rect().size.x + 90.0
	var overhead: bool = rng.randf() < 0.42
	obstacles.append({"x": spawn_x, "overhead": overhead})

	if rng.randf() < 0.78:
		coins.append({
			"x": spawn_x + rng.randf_range(110.0, 250.0),
			"y": rng.randf_range(260.0, 360.0)
		})


func _jump() -> void:
	if is_sliding:
		return
	if player_bottom >= FLOOR_Y:
		vertical_speed = -720.0
		jumps_remaining = 1
		_play_tone(520.0, 0.1)
	elif jumps_remaining > 0:
		vertical_speed = -640.0
		jumps_remaining -= 1
		_play_tone(680.0, 0.1)


func _begin_slide() -> void:
	if player_bottom >= FLOOR_Y:
		is_sliding = true
		slide_timer = 0.52
		vertical_speed = 0.0
		_play_tone(300.0, 0.1)


func _check_collisions() -> void:
	var player_height: float = 28.0 if is_sliding else PLAYER_HEIGHT
	var player_top: float = player_bottom - player_height
	var player_rect := Rect2(
		PLAYER_X - PLAYER_WIDTH / 2.0 + 4.0,
		player_top + 4.0,
		PLAYER_WIDTH - 8.0,
		player_height - 8.0
	)

	for obs in obstacles:
		var obs_x: float = float(obs["x"])
		var hitbox: Rect2

		if bool(obs["overhead"]):
			# High barrier: requires sliding underneath
			hitbox = Rect2(obs_x - 26.0, FLOOR_Y - 70.0, 52.0, 28.0)
		else:
			# Low obstacle: requires jumping over
			hitbox = Rect2(obs_x - 22.0, FLOOR_Y - 48.0, 44.0, 48.0)

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
			_play_tone(880.0, 0.08)


func _end_game() -> void:
	if state != GameState.PLAYING:
		return

	state = GameState.GAME_OVER
	score = int(elapsed * 15.0) + coin_count * 35
	_play_tone(150.0, 0.3, "square")

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

	# 1. Cyberpunk Dark Background
	draw_rect(Rect2(Vector2.ZERO, screen_size), Color(0.018, 0.012, 0.06))

	# 2. Glowing background dust particles
	for p in particles:
		draw_circle(Vector2(p["x"], p["y"]), p["radius"], Color(0.5, 0.85, 1.0, p["alpha"]))

	# 3. Layered Skyline Buildings
	for i in range(15):
		var building_x: float = float(i) * 80.0
		var b_height: float = 90.0 + float((i * 47) % 130)
		draw_rect(
			Rect2(building_x, FLOOR_Y - b_height, 58.0, b_height),
			Color(0.045, 0.03, 0.12)
		)

	# 4. Neon Floor Grid & Glow Line
	draw_line(
		Vector2(0.0, FLOOR_Y),
		Vector2(screen_size.x, FLOOR_Y),
		Color(0.0, 0.95, 1.0),
		4.0
	)
	draw_line(
		Vector2(0.0, FLOOR_Y + 2.0),
		Vector2(screen_size.x, FLOOR_Y + 2.0),
		Color(0.0, 0.4, 0.8, 0.35),
		10.0
	)

	# 5. Draw Obstacles (Neon Magenta with warning stripes)
	for obs in obstacles:
		var x: float = float(obs["x"])

		if bool(obs["overhead"]):
			draw_rect(
				Rect2(x - 26.0, FLOOR_Y - 70.0, 52.0, 28.0),
				Color(1.0, 0.08, 0.48)
			)
			draw_line(
				Vector2(x - 26.0, FLOOR_Y - 42.0),
				Vector2(x - 26.0, FLOOR_Y - 14.0),
				Color(1.0, 0.08, 0.48),
				4.0
			)
			draw_line(
				Vector2(x + 26.0, FLOOR_Y - 42.0),
				Vector2(x + 26.0, FLOOR_Y - 14.0),
				Color(1.0, 0.08, 0.48),
				4.0
			)
		else:
			draw_colored_polygon(
				PackedVector2Array([
					Vector2(x - 24.0, FLOOR_Y),
					Vector2(x, FLOOR_Y - 48.0),
					Vector2(x + 24.0, FLOOR_Y)
				]),
				Color(1.0, 0.08, 0.48)
			)

	# 6. Draw Collectible Coins (Golden Rings)
	for coin in coins:
		var center := Vector2(float(coin["x"]), float(coin["y"]))
		draw_circle(center, 14.0, Color(1.0, 0.85, 0.15))
		draw_circle(center, 7.0, Color(0.08, 0.04, 0.12))

	# 7. Draw Upgraded Visual Player Character
	var player_height: float = 28.0 if is_sliding else PLAYER_HEIGHT
	var player_top: float = player_bottom - player_height
	var player_rect = Rect2(PLAYER_X - PLAYER_WIDTH / 2.0, player_top, PLAYER_WIDTH, player_height)
	
	# Outer Neon Cyan Body Shell
	draw_rect(player_rect, Color(0.0, 0.92, 1.0))
	# Inner Dark Cyber Core Plate
	draw_rect(
		Rect2(PLAYER_X - PLAYER_WIDTH / 2.0 + 6.0, player_top + 8.0, PLAYER_WIDTH - 12.0, player_height - 16.0),
		Color(0.02, 0.05, 0.12)
	)
	# Glowing Neon Visor / Eye Strip
	if not is_sliding:
		draw_rect(
			Rect2(PLAYER_X - 6.0, player_top + 12.0, 18.0, 6.0),
			Color(1.0, 0.9, 0.2)
		)

	# 8. HUD & Sound Button Indicator
	draw_string(
		ThemeDB.fallback_font,
		Vector2(24.0, 38.0),
		"SCORE: %d    COINS: %d    BEST: %d" % [score, coin_count, best_score],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		20,
		Color(0.9, 0.95, 1.0)
	)

	var sound_status_text = "SOUND: ON (M)" if sound_enabled else "SOUND: OFF (M)"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(screen_size.x - 200.0, 38.0),
		sound_status_text,
		HORIZONTAL_ALIGNMENT_RIGHT,
		-1.0,
		16,
		Color(0.7, 0.8, 1.0)
	)

	# State Overlay Screens
	match state:
		GameState.MENU:
			_draw_message(
				screen_size,
				"NEON DASH RUNNER",
				"TAP or ENTER to Play\nLeft Side: Jump (Double Jump)  |  Right Side: Slide\nPress M or Top-Right to Toggle Audio"
			)
		GameState.PAUSED:
			_draw_message(
				screen_size,
				"GAME PAUSED",
				"P / ESC: Resume    |    ENTER: Restart    |    M: Toggle Sound"
			)
		GameState.GAME_OVER:
			_draw_message(
				screen_size,
				"GAME OVER",
				"Final Score: %d    Coins Collected: %d\nENTER / TAP to Play Again    |    M: Toggle Sound"
				% [score, coin_count]
			)


func _draw_message(screen_size: Vector2, title: String, subtitle: String) -> void:
	draw_rect(
		Rect2(Vector2.ZERO, screen_size),
		Color(0.01, 0.005, 0.05, 0.85)
	)

	var center_x: float = screen_size.x * 0.5
	draw_string(
		ThemeDB.fallback_font,
		Vector2(center_x - 250.0, 200.0),
		title,
		HORIZONTAL_ALIGNMENT_CENTER,
		500.0,
		40,
		Color(0.0, 0.95, 1.0)
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(center_x - 340.0, 260.0),
		subtitle,
		HORIZONTAL_ALIGNMENT_CENTER,
		680.0,
		18,
		Color.WHITE
	)
