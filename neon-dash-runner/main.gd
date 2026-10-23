extends Node2D

enum GameState { MENU, PLAYING, PAUSED, GAME_OVER }

const FLOOR_Y: float = 440.0
const PLAYER_X: float = 170.0
const PLAYER_WIDTH: float = 34.0
const PLAYER_HEIGHT: float = 56.0
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
var anim_frame: float = 0.0

var elapsed: float = 0.0
var score: int = 0
var coin_count: int = 0
var best_score: int = 0
var world_speed: float = 380.0
var spawn_timer: float = 1.3
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Audio system
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
	synth_generator.buffer_length = 0.15
	audio_player.stream = synth_generator
	add_child(audio_player)
	audio_player.play()
	playback = audio_player.get_stream_playback()


func _play_tone(freq: float, duration: float, type: String = "sine") -> void:
	if not sound_enabled or not playback:
		return
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
		sample *= max(0.0, 1.0 - (float(i) / frames_to_generate))
		playback.push_frame(Vector2(sample * 0.18, sample * 0.18))


func _process(delta: float) -> void:
	if state == GameState.PLAYING:
		_update_game(delta)
		anim_frame += delta * (world_speed * 0.035)

	# Background atmosphere dust particles
	for i in range(particles.size() - 1, -1, -1):
		var p = particles[i]
		p["x"] -= (world_speed * 0.35 + p["speed_offset"]) * delta
		if p["x"] < -20.0:
			particles.remove_at(i)
			
	if state == GameState.PLAYING and randf() < 0.35:
		particles.append({
			"x": 980.0,
			"y": randf_range(30.0, FLOOR_Y - 20.0),
			"radius": randf_range(1.0, 3.0),
			"speed_offset": randf_range(10.0, 45.0),
			"alpha": randf_range(0.2, 0.6)
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
		_handle_click_or_tap(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click_or_tap(event.position)


func _toggle_sound() -> void:
	sound_enabled = not sound_enabled
	if sound_enabled:
		_play_tone(650.0, 0.1)


func _handle_click_or_tap(pos: Vector2) -> void:
	var screen_size: Vector2 = get_viewport_rect().size

	# Audio Toggle HUD Button Hitbox
	var sound_btn_rect = Rect2(screen_size.x - 170.0, 12.0, 150.0, 36.0)
	if sound_btn_rect.has_point(pos):
		_toggle_sound()
		return

	match state:
		GameState.MENU:
			_start_game()

		GameState.GAME_OVER:
			var btn_rect = Rect2(screen_size.x * 0.5 - 110.0, 310.0, 220.0, 52.0)
			if btn_rect.has_point(pos) or pos.y > 80:
				_start_game()

		GameState.PAUSED:
			state = GameState.PLAYING

		GameState.PLAYING:
			if pos.x > screen_size.x * 0.55:
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
	spawn_timer = 1.3
	player_bottom = FLOOR_Y
	vertical_speed = 0.0
	slide_timer = 0.0
	is_sliding = false
	jumps_remaining = 2
	anim_frame = 0.0
	_play_tone(540.0, 0.15)


func _update_game(delta: float) -> void:
	elapsed += delta
	score = int(elapsed * 12.0) + coin_count * 30
	
	# Balanced, smooth speed scaling with comfortable plateaus
	var target_speed = 380.0 + (elapsed * 4.5)
	world_speed = minf(target_speed, 620.0)

	# Responsive jump physics
	if player_bottom < FLOOR_Y:
		vertical_speed += 1750.0 * delta
		player_bottom += vertical_speed * delta
		if player_bottom >= FLOOR_Y:
			player_bottom = FLOOR_Y
			vertical_speed = 0.0
			jumps_remaining = 2

	if slide_timer > 0.0:
		slide_timer = maxf(0.0, slide_timer - delta)
		is_sliding = slide_timer > 0.0

	# Progressive spawner timing with safe spacing gaps
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_items()
		spawn_timer = maxf(0.95, 1.7 - elapsed * 0.004) + rng.randf_range(0.0, 0.4)

	for i in range(obstacles.size() - 1, -1, -1):
		var obs: Dictionary = obstacles[i]
		obs["x"] = float(obs["x"]) - world_speed * delta
		obstacles[i] = obs
		if float(obs["x"]) < -140.0:
			obstacles.remove_at(i)

	for i in range(coins.size() - 1, -1, -1):
		var coin: Dictionary = coins[i]
		coin["x"] = float(coin["x"]) - world_speed * delta
		coins[i] = coin
		if float(coin["x"]) < -50.0:
			coins.remove_at(i)

	_check_collisions()


func _spawn_items() -> void:
	var spawn_x: float = get_viewport_rect().size.x + 110.0
	var obs_type: int = rng.randi() % 3  # 0: Fire Pit, 1: Overhead Laser Drone, 2: Cyber-Citrus Vine Plant
	obstacles.append({"x": spawn_x, "type": obs_type})

	if rng.randf() < 0.75:
		coins.append({
			"x": spawn_x + rng.randf_range(130.0, 270.0),
			"y": rng.randf_range(270.0, 350.0)
		})


func _jump() -> void:
	if is_sliding:
		return
	if player_bottom >= FLOOR_Y:
		vertical_speed = -860.0
		jumps_remaining = 1
		_play_tone(600.0, 0.1)
	elif jumps_remaining > 0:
		vertical_speed = -760.0
		jumps_remaining -= 1
		_play_tone(800.0, 0.1)


func _begin_slide() -> void:
	if player_bottom >= FLOOR_Y:
		is_sliding = true
		slide_timer = 0.55
		vertical_speed = 0.0
		_play_tone(300.0, 0.1)


func _check_collisions() -> void:
	var player_height: float = 26.0 if is_sliding else PLAYER_HEIGHT
	var player_top: float = player_bottom - player_height
	var player_rect := Rect2(
		PLAYER_X - PLAYER_WIDTH / 2.0 + 5.0,
		player_top + 5.0,
		PLAYER_WIDTH - 10.0,
		player_height - 10.0
	)

	for obs in obstacles:
		var obs_x: float = float(obs["x"])
		var type: int = int(obs["type"])
		var hitbox: Rect2

		match type:
			0: # Fire Pit (Jump over)
				hitbox = Rect2(obs_x - 20.0, FLOOR_Y - 36.0, 40.0, 36.0)
			1: # Overhead Laser Drone (Slide under)
				hitbox = Rect2(obs_x - 28.0, FLOOR_Y - 76.0, 56.0, 26.0)
			2: # Cyber-Citrus Plant / Vine (Precise jump)
				hitbox = Rect2(obs_x - 18.0, FLOOR_Y - 50.0, 36.0, 50.0)

		if player_rect.intersects(hitbox):
			_end_game()
			return

	for i in range(coins.size() - 1, -1, -1):
		var coin: Dictionary = coins[i]
		var coin_rect := Rect2(
			float(coin["x"]) - 18.0,
			float(coin["y"]) - 18.0,
			36.0,
			36.0
		)
		if player_rect.intersects(coin_rect):
			coin_count += 1
			coins.remove_at(i)
			_play_tone(920.0, 0.08)


func _end_game() -> void:
	if state != GameState.PLAYING:
		return

	state = GameState.GAME_OVER
	score = int(elapsed * 12.0) + coin_count * 30
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

	# Dynamic background shifting theme
	var bg_color = Color(0.015, 0.01, 0.05)
	if score > 350:
		bg_color = Color(0.025, 0.008, 0.04)
	if score > 800:
		bg_color = Color(0.04, 0.01, 0.02)

	draw_rect(Rect2(Vector2.ZERO, screen_size), bg_color)

	# Atmospheric particles
	for p in particles:
		draw_circle(Vector2(p["x"], p["y"]), p["radius"], Color(0.6, 0.85, 1.0, p["alpha"]))

	# Skyline Background Towers
	for i in range(16):
		var building_x: float = float(i) * 78.0
		var b_height: float = 95.0 + float((i * 43) % 135)
		draw_rect(
			Rect2(building_x, FLOOR_Y - b_height, 56.0, b_height),
			Color(0.04, 0.025, 0.11)
		)

		# Building windows glow
		if i % 2 == 0:
			draw_rect(Rect2(building_x + 12.0, FLOOR_Y - b_height + 20.0, 10.0, b_height - 40.0), Color(0.06, 0.04, 0.16))

	# Floor road base
	draw_line(Vector2(0.0, FLOOR_Y), Vector2(screen_size.x, FLOOR_Y), Color(0.0, 0.95, 1.0), 4.0)
	draw_line(Vector2(0.0, FLOOR_Y + 2.0), Vector2(screen_size.x, FLOOR_Y + 2.0), Color(0.0, 0.45, 0.85, 0.4), 12.0)

	# Draw Professional Obstacles
	for obs in obstacles:
		var x: float = float(obs["x"])
		var type: int = int(obs["type"])

		match type:
			0: # 🔥 Fire Pit Hazard
				draw_rect(Rect2(x - 22.0, FLOOR_Y - 10.0, 44.0, 10.0), Color(0.2, 0.1, 0.1))
				draw_colored_polygon(
					PackedVector2Array([
						Vector2(x - 20.0, FLOOR_Y),
						Vector2(x - 10.0, FLOOR_Y - 32.0),
						Vector2(x, FLOOR_Y - 15.0),
						Vector2(x + 10.0, FLOOR_Y - 38.0),
						Vector2(x + 20.0, FLOOR_Y)
					]),
					Color(1.0, 0.35, 0.05)
				)
				draw_colored_polygon(
					PackedVector2Array([
						Vector2(x - 10.0, FLOOR_Y),
						Vector2(x, FLOOR_Y - 24.0),
						Vector2(x + 10.0, FLOOR_Y)
					]),
					Color(1.0, 0.85, 0.1)
				)

			1: # 🛸 Overhead Laser Drone
				draw_rect(Rect2(x - 28.0, FLOOR_Y - 76.0, 56.0, 16.0), Color(0.15, 0.15, 0.22))
				draw_rect(Rect2(x - 12.0, FLOOR_Y - 82.0, 24.0, 6.0), Color(0.9, 0.1, 0.2)) # Core lens
				# Glowing laser beam downwards
				draw_line(Vector2(x, FLOOR_Y - 60.0), Vector2(x, FLOOR_Y), Color(1.0, 0.0, 0.3, 0.6), 3.0)

			2: # 🍋 Cyber-Citrus Vine Plant
				# Plant stem & bulbous glowing citrus fruit pods
				draw_line(Vector2(x, FLOOR_Y), Vector2(x, FLOOR_Y - 44.0), Color(0.1, 0.7, 0.3), 5.0)
				draw_circle(Vector2(x, FLOOR_Y - 36.0), 16.0, Color(0.95, 0.85, 0.1))
				draw_circle(Vector2(x - 12.0, FLOOR_Y - 22.0), 11.0, Color(0.1, 0.8, 0.4))
				draw_circle(Vector2(x + 12.0, FLOOR_Y - 26.0), 11.0, Color(0.1, 0.8, 0.4))

	# Draw Gold Coins
	for coin in coins:
		var center := Vector2(float(coin["x"]), float(coin["y"]))
		draw_circle(center, 14.0, Color(1.0, 0.85, 0.15))
		draw_circle(center, 7.0, Color(0.08, 0.04, 0.12))

	# 🤖 Professional Robot Character Rendering (Real Head, Torso, Arms, Legs)
	var player_height: float = 26.0 if is_sliding else PLAYER_HEIGHT
	var player_top: float = player_bottom - player_height

	if not is_sliding:
		# Running Leg Animation Cycle using sine waves
		var leg_offset = sin(anim_frame * 12.0) * 8.0

		# Back Leg
		draw_line(Vector2(PLAYER_X - 4.0, player_top + 36.0), Vector2(PLAYER_X - 10.0 - leg_offset, FLOOR_Y), Color(0.65, 0.75, 0.85), 4.0)
		# Back Arm
		draw_line(Vector2(PLAYER_X, player_top + 20.0), Vector2(PLAYER_X + 10.0 + leg_offset, player_top + 34.0), Color(0.65, 0.75, 0.85), 3.0)

		# Torso / Chassis Armor
		draw_rect(Rect2(PLAYER_X - 12.0, player_top + 16.0, 24.0, 22.0), Color(0.15, 0.22, 0.35))
		# Glowing Arc Reactor Core
		draw_circle(Vector2(PLAYER_X, player_top + 27.0), 5.0, Color(0.0, 0.9, 1.0))

		# Head & Helmet
		draw_rect(Rect2(PLAYER_X - 11.0, player_top + 2.0, 22.0, 15.0), Color(0.8, 0.88, 0.95))
		# LED Visor Eye (Cyan Glow)
		draw_rect(Rect2(PLAYER_X - 7.0, player_top + 6.0, 15.0, 4.0), Color(0.0, 1.0, 0.95))
		# Head Antenna
		draw_line(Vector2(PLAYER_X, player_top + 2.0), Vector2(PLAYER_X, player_top - 6.0), Color(0.8, 0.88, 0.95), 2.0)
		draw_circle(Vector2(PLAYER_X, player_top - 7.0), 3.0, Color(1.0, 0.1, 0.4))

		# Front Arm
		draw_line(Vector2(PLAYER_X, player_top + 20.0), Vector2(PLAYER_X - 10.0 + leg_offset, player_top + 34.0), Color(0.8, 0.88, 0.95), 3.0)
		# Front Leg
		draw_line(Vector2(PLAYER_X + 4.0, player_top + 36.0), Vector2(PLAYER_X + 10.0 + leg_offset, FLOOR_Y), Color(0.8, 0.88, 0.95), 4.0)

	else:
		# Sliding Robot Pose (Aerodynamic tuck)
		draw_rect(Rect2(PLAYER_X - 18.0, player_top + 10.0, 32.0, 16.0), Color(0.15, 0.22, 0.35))
		draw_rect(Rect2(PLAYER_X + 2.0, player_top + 2.0, 16.0, 12.0), Color(0.8, 0.88, 0.95))
		draw_rect(Rect2(PLAYER_X + 6.0, player_top + 5.0, 10.0, 3.0), Color(0.0, 1.0, 0.95))
		# Trailing slide legs
		draw_rect(Rect2(PLAYER_X - 24.0, player_top + 18.0, 12.0, 6.0), Color(0.65, 0.75, 0.85))

	# HUD Header Score Display
	draw_string(
		ThemeDB.fallback_font,
		Vector2(24.0, 36.0),
		"SCORE: %d    COINS: %d    BEST: %d" % [score, coin_count, best_score],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		20,
		Color(0.9, 0.95, 1.0)
	)

	# Sound Toggle Button UI
	var sound_btn_rect = Rect2(screen_size.x - 170.0, 12.0, 150.0, 34.0)
	draw_rect(sound_btn_rect, Color(0.08, 0.12, 0.25, 0.85))
	draw_rect(sound_btn_rect, Color(0.0, 0.9, 1.0), false, 2.0)
	var sound_text = "🔊 SOUND: ON" if sound_enabled else "🔇 SOUND: OFF"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(screen_size.x - 160.0, 34.0),
		sound_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		14,
		Color(1.0, 1.0, 1.0)
	)

	# State Overlays
	match state:
		GameState.MENU:
			_draw_overlay(screen_size, "NEON DASH RUNNER", "START GAME")
		GameState.PAUSED:
			_draw_overlay(screen_size, "GAME PAUSED", "RESUME")
		GameState.GAME_OVER:
			_draw_overlay(screen_size, "GAME OVER", "TRY AGAIN", "Final Score: %d   |   Coins: %d" % [score, coin_count])


func _draw_overlay(screen_size: Vector2, title: String, btn_label: String, subtext: String = "") -> void:
	draw_rect(Rect2(Vector2.ZERO, screen_size), Color(0.01, 0.005, 0.05, 0.85))

	var center_x: float = screen_size.x * 0.5
	
	draw_string(
		ThemeDB.fallback_font,
		Vector2(center_x - 250.0, 180.0),
		title,
		HORIZONTAL_ALIGNMENT_CENTER,
		500.0,
		42,
		Color(0.0, 0.95, 1.0)
	)

	if subtext != "":
		draw_string(
			ThemeDB.fallback_font,
			Vector2(center_x - 250.0, 235.0),
			subtext,
			HORIZONTAL_ALIGNMENT_CENTER,
			500.0,
			20,
			Color(0.9, 0.9, 1.0)
		)

	# Interactive Button
	var btn_rect = Rect2(center_x - 110.0, 300.0, 220.0, 52.0)
	draw_rect(btn_rect, Color(0.0, 0.8, 0.9, 0.9))
	draw_rect(btn_rect, Color(1.0, 1.0, 1.0), false, 2.0)
	
	draw_string(
		ThemeDB.fallback_font,
		Vector2(center_x - 100.0, 335.0),
		btn_label,
		HORIZONTAL_ALIGNMENT_CENTER,
		200.0,
		22,
		Color(0.02, 0.02, 0.08)
	)
