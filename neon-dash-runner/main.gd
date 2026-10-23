extends Node2D

enum GameState { MENU, PLAYING, PAUSED, GAME_OVER }

const FLOOR_Y: float = 440.0
const PLAYER_X: float = 170.0
const PLAYER_WIDTH: float = 34.0
const PLAYER_HEIGHT: float = 58.0
const SAVE_PATH: String = "user://neon_dash.cfg"

var state: GameState = GameState.MENU
var obstacles: Array[Dictionary] = []
var coins: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var player_sparks: Array[Dictionary] = []

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

# Audio System
var sound_enabled: bool = true
var audio_player: AudioStreamPlayer
var synth_generator: AudioStreamGenerator
var playback: AudioStreamGeneratorPlayback
var sound_freq: float = 0.0
var sound_timer_val: float = 0.0


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


func _trigger_sound(freq: float, duration: float) -> void:
	if not sound_enabled:
		return
	sound_freq = freq
	sound_timer_val = duration


func _process(delta: float) -> void:
	# Audio buffer generation
	if playback:
		var frames = playback.get_frames_available()
		for i in range(frames):
			var sample = 0.0
			if sound_enabled and sound_timer_val > 0.0:
				var t = Time.get_ticks_msec() * 0.001
				sample = sin(t * sound_freq * TAU) * 0.15
				sound_timer_val -= 1.0 / 22050.0
			playback.push_frame(Vector2(sample, sample))

	# Zero-lag input polling
	if state == GameState.PLAYING:
		if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_up") or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
			_jump()
		elif Input.is_action_just_pressed("ui_down") or Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
			_begin_slide()

		_update_game(delta)
		anim_frame += delta * (world_speed * 0.035)

		# Generate Thruster / Exhaust particles
		if randf() < 0.6:
			var px = PLAYER_X - 18.0 if not is_sliding else PLAYER_X - 26.0
			var py = (player_bottom - PLAYER_HEIGHT + 28.0) if not is_sliding else (player_bottom - 12.0)
			player_sparks.append({
				"x": px,
				"y": py + randf_range(-4.0, 4.0),
				"vx": -randf_range(120.0, 220.0),
				"vy": randf_range(-30.0, 30.0),
				"life": randf_range(0.15, 0.35)
			})

	# Particle updates
	for i in range(player_sparks.size() - 1, -1, -1):
		var spark = player_sparks[i]
		spark["x"] += spark["vx"] * delta
		spark["y"] += spark["vy"] * delta
		spark["life"] -= delta
		if spark["life"] <= 0.0:
			player_sparks.remove_at(i)

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
		if event.keycode == KEY_M:
			_toggle_sound()
		elif state == GameState.MENU or state == GameState.GAME_OVER:
			if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				_start_game()
		elif state == GameState.PAUSED:
			if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
				state = GameState.PLAYING
			elif event.keycode == KEY_ENTER:
				_start_game()

	if event is InputEventScreenTouch and event.pressed:
		_handle_click_or_tap(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click_or_tap(event.position)


func _toggle_sound() -> void:
	sound_enabled = not sound_enabled
	if sound_enabled:
		_trigger_sound(600.0, 0.12)


func _handle_click_or_tap(pos: Vector2) -> void:
	var screen_size: Vector2 = get_viewport_rect().size

	var sound_btn_rect = Rect2(screen_size.x - 170.0, 12.0, 150.0, 36.0)
	if sound_btn_rect.has_point(pos):
		_toggle_sound()
		return

	match state:
		GameState.MENU:
			_start_game()

		GameState.GAME_OVER:
			var btn_rect = Rect2(screen_size.x * 0.5 - 110.0, 300.0, 220.0, 52.0)
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
	player_sparks.clear()
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
	_trigger_sound(500.0, 0.15)


func _update_game(delta: float) -> void:
	elapsed += delta
	score = int(elapsed * 12.0) + coin_count * 30
	
	var target_speed = 380.0 + (elapsed * 4.0)
	world_speed = minf(target_speed, 600.0)

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

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_items()
		spawn_timer = maxf(1.0, 1.75 - elapsed * 0.003) + rng.randf_range(0.0, 0.4)

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
	var spawn_x: float = get_viewport_rect().size.x + 120.0
	var obs_type: int = rng.randi() % 3
	obstacles.append({"x": spawn_x, "type": obs_type})

	if rng.randf() < 0.75:
		coins.append({
			"x": spawn_x + rng.randf_range(130.0, 270.0),
			"y": rng.randf_range(260.0, 340.0)
		})


func _jump() -> void:
	if is_sliding:
		return
	if player_bottom >= FLOOR_Y:
		vertical_speed = -950.0
		jumps_remaining = 1
		_trigger_sound(650.0, 0.1)
	elif jumps_remaining > 0:
		vertical_speed = -820.0
		jumps_remaining -= 1
		_trigger_sound(850.0, 0.1)


func _begin_slide() -> void:
	if player_bottom >= FLOOR_Y:
		is_sliding = true
		slide_timer = 0.55
		vertical_speed = 0.0
		_trigger_sound(300.0, 0.1)


func _check_collisions() -> void:
	var player_height: float = 26.0 if is_sliding else PLAYER_HEIGHT
	var player_top: float = player_bottom - player_height
	var player_rect := Rect2(
		PLAYER_X - PLAYER_WIDTH / 2.0 + 4.0,
		player_top + 4.0,
		PLAYER_WIDTH - 8.0,
		player_height - 8.0
	)

	for obs in obstacles:
		var obs_x: float = float(obs["x"])
		var type: int = int(obs["type"])
		var hitbox: Rect2

		match type:
			0: # Fire Pit
				hitbox = Rect2(obs_x - 18.0, FLOOR_Y - 34.0, 36.0, 34.0)
			1: # Drone
				hitbox = Rect2(obs_x - 26.0, FLOOR_Y - 76.0, 52.0, 24.0)
			2: # Desert Cactus
				hitbox = Rect2(obs_x - 20.0, FLOOR_Y - 52.0, 40.0, 52.0)

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
			_trigger_sound(950.0, 0.08)


func _end_game() -> void:
	if state != GameState.PLAYING:
		return

	state = GameState.GAME_OVER
	score = int(elapsed * 12.0) + coin_count * 30
	_trigger_sound(180.0, 0.3)

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

	# Dynamic Atmosphere Background
	var bg_color = Color(0.015, 0.01, 0.05)
	if score > 350:
		bg_color = Color(0.025, 0.008, 0.04)
	if score > 800:
		bg_color = Color(0.04, 0.01, 0.02)

	draw_rect(Rect2(Vector2.ZERO, screen_size), bg_color)

	# Atmospheric Background Dust
	for p in particles:
		draw_circle(Vector2(p["x"], p["y"]), p["radius"], Color(0.6, 0.85, 1.0, p["alpha"]))

	# City Skyline
	for i in range(16):
		var building_x: float = float(i) * 78.0
		var b_height: float = 95.0 + float((i * 43) % 135)
		draw_rect(
			Rect2(building_x, FLOOR_Y - b_height, 56.0, b_height),
			Color(0.04, 0.025, 0.11)
		)

	# Floor Road Base
	draw_line(Vector2(0.0, FLOOR_Y), Vector2(screen_size.x, FLOOR_Y), Color(0.0, 0.95, 1.0), 4.0)
	draw_line(Vector2(0.0, FLOOR_Y + 2.0), Vector2(screen_size.x, FLOOR_Y + 2.0), Color(0.0, 0.45, 0.85, 0.4), 12.0)

	# Thruster Trail Particles
	for spark in player_sparks:
		draw_circle(Vector2(spark["x"], spark["y"]), spark["life"] * 12.0, Color(0.0, 0.9, 1.0, spark["life"] * 3.0))

	# -------------------------------------------------------------
	# HIGH-DETAIL PROFESSIONAL OBSTACLES
	# -------------------------------------------------------------
	for obs in obstacles:
		var x: float = float(obs["x"])
		var type: int = int(obs["type"])

		match type:
			0: # 🔥 Animated Fire Pit Hazard
				# Steel Pit Base & Grate
				draw_rect(Rect2(x - 24.0, FLOOR_Y - 6.0, 48.0, 6.0), Color(0.2, 0.22, 0.26))
				draw_rect(Rect2(x - 20.0, FLOOR_Y - 10.0, 40.0, 4.0), Color(0.35, 0.38, 0.42))
				
				# Outer Flame Layer
				var f_anim = sin(anim_frame * 15.0) * 4.0
				draw_colored_polygon(
					PackedVector2Array([
						Vector2(x - 20.0, FLOOR_Y - 6.0),
						Vector2(x - 10.0, FLOOR_Y - 34.0 + f_anim),
						Vector2(x, FLOOR_Y - 18.0),
						Vector2(x + 10.0, FLOOR_Y - 38.0 - f_anim),
						Vector2(x + 20.0, FLOOR_Y - 6.0)
					]),
					Color(1.0, 0.25, 0.05)
				)
				# Inner Core Flame Layer
				draw_colored_polygon(
					PackedVector2Array([
						Vector2(x - 12.0, FLOOR_Y - 6.0),
						Vector2(x - 4.0, FLOOR_Y - 24.0 - f_anim),
						Vector2(x + 4.0, FLOOR_Y - 26.0 + f_anim),
						Vector2(x + 12.0, FLOOR_Y - 6.0)
					]),
					Color(1.0, 0.85, 0.1)
				)

			1: # 🛸 High-Tech Cyber Drone
				# Anti-gravity rotors
				draw_rect(Rect2(x - 30.0, FLOOR_Y - 80.0, 10.0, 4.0), Color(0.5, 0.55, 0.6))
				draw_rect(Rect2(x + 20.0, FLOOR_Y - 80.0, 10.0, 4.0), Color(0.5, 0.55, 0.6))
				# Drone Body Frame
				draw_rect(Rect2(x - 24.0, FLOOR_Y - 76.0, 48.0, 16.0), Color(0.12, 0.15, 0.22))
				draw_rect(Rect2(x - 18.0, FLOOR_Y - 72.0, 36.0, 8.0), Color(0.25, 0.3, 0.4))
				# Red Lens & Warning Beacons
				draw_circle(Vector2(x, FLOOR_Y - 68.0), 4.0, Color(1.0, 0.1, 0.2))
				draw_circle(Vector2(x - 20.0, FLOOR_Y - 74.0), 2.0, Color(1.0, 0.8, 0.0))
				draw_circle(Vector2(x + 20.0, FLOOR_Y - 74.0), 2.0, Color(1.0, 0.8, 0.0))
				# Vertical Shimmering Laser
				draw_line(Vector2(x, FLOOR_Y - 60.0), Vector2(x, FLOOR_Y), Color(1.0, 0.0, 0.35, 0.7), 4.0)
				draw_line(Vector2(x, FLOOR_Y - 60.0), Vector2(x, FLOOR_Y), Color(1.0, 0.8, 0.9, 0.9), 1.5)

			2: # 🌵 Realistic Shaded Desert Cactus
				# Main Center Stem
				draw_rect(Rect2(x - 10.0, FLOOR_Y - 54.0, 20.0, 54.0), Color(0.1, 0.55, 0.25))
				draw_rect(Rect2(x - 6.0, FLOOR_Y - 52.0, 4.0, 50.0), Color(0.2, 0.7, 0.35)) # Highlight ridge
				# Left Arm
				draw_rect(Rect2(x - 22.0, FLOOR_Y - 36.0, 14.0, 8.0), Color(0.1, 0.55, 0.25))
				draw_rect(Rect2(x - 22.0, FLOOR_Y - 48.0, 8.0, 16.0), Color(0.1, 0.55, 0.25))
				# Right Arm
				draw_rect(Rect2(x + 8.0, FLOOR_Y - 28.0, 14.0, 8.0), Color(0.1, 0.55, 0.25))
				draw_rect(Rect2(x + 14.0, FLOOR_Y - 42.0, 8.0, 18.0), Color(0.1, 0.55, 0.25))
				# Hazard Spikes
				draw_line(Vector2(x - 10.0, FLOOR_Y - 40.0), Vector2(x - 14.0, FLOOR_Y - 42.0), Color(1.0, 0.9, 0.4), 1.5)
				draw_line(Vector2(x + 10.0, FLOOR_Y - 20.0), Vector2(x + 14.0, FLOOR_Y - 22.0), Color(1.0, 0.9, 0.4), 1.5)

	# Gold Coins
	for coin in coins:
		var center := Vector2(float(coin["x"]), float(coin["y"]))
		draw_circle(center, 14.0, Color(1.0, 0.85, 0.15))
		draw_circle(center, 7.0, Color(0.08, 0.04, 0.12))

	# -------------------------------------------------------------
	# 🤖 HIGHLY DETAILED ARTICULATED ROBOT PLAYER
	# -------------------------------------------------------------
	var player_height: float = 26.0 if is_sliding else PLAYER_HEIGHT
	var player_top: float = player_bottom - player_height

	if not is_sliding:
		# Kinematic Sine Limb Motion
		var leg_phase = sin(anim_frame * 14.0)
		var arm_phase = cos(anim_frame * 14.0)

		# Back Leg (Knee Joint)
		var b_knee = Vector2(PLAYER_X - 6.0 - leg_phase * 6.0, player_top + 44.0)
		var b_foot = Vector2(PLAYER_X - 10.0 - leg_phase * 10.0, FLOOR_Y)
		draw_line(Vector2(PLAYER_X - 2.0, player_top + 32.0), b_knee, Color(0.5, 0.6, 0.7), 4.0)
		draw_line(b_knee, b_foot, Color(0.4, 0.5, 0.6), 3.5)

		# Back Arm (Elbow Joint)
		var b_elbow = Vector2(PLAYER_X + 6.0 + arm_phase * 6.0, player_top + 26.0)
		draw_line(Vector2(PLAYER_X, player_top + 18.0), b_elbow, Color(0.5, 0.6, 0.7), 3.0)

		# Main Torso & Armor Plates
		draw_rect(Rect2(PLAYER_X - 12.0, player_top + 14.0, 24.0, 22.0), Color(0.12, 0.18, 0.3))
		draw_rect(Rect2(PLAYER_X - 9.0, player_top + 16.0, 18.0, 18.0), Color(0.2, 0.28, 0.42))
		# Arc Reactor Chest Core
		draw_circle(Vector2(PLAYER_X, player_top + 25.0), 6.0, Color(0.0, 0.9, 1.0))
		draw_circle(Vector2(PLAYER_X, player_top + 25.0), 3.0, Color(1.0, 1.0, 1.0))

		# Head, Helmet & Visor
		draw_rect(Rect2(PLAYER_X - 10.0, player_top + 2.0, 20.0, 13.0), Color(0.8, 0.88, 0.95))
		# Visor Eye & Glint
		draw_rect(Rect2(PLAYER_X - 6.0, player_top + 5.0, 14.0, 4.0), Color(0.0, 1.0, 0.95))
		draw_rect(Rect2(PLAYER_X + 2.0, player_top + 5.0, 3.0, 4.0), Color(1.0, 1.0, 1.0))
		# Antenna
		draw_line(Vector2(PLAYER_X, player_top + 2.0), Vector2(PLAYER_X, player_top - 6.0), Color(0.8, 0.88, 0.95), 2.0)
		draw_circle(Vector2(PLAYER_X, player_top - 7.0), 3.0, Color(1.0, 0.1, 0.4))

		# Front Arm
		var f_elbow = Vector2(PLAYER_X - 8.0 - arm_phase * 6.0, player_top + 26.0)
		draw_line(Vector2(PLAYER_X, player_top + 18.0), f_elbow, Color(0.8, 0.88, 0.95), 3.0)

		# Front Leg
		var f_knee = Vector2(PLAYER_X + 6.0 + leg_phase * 6.0, player_top + 44.0)
		var f_foot = Vector2(PLAYER_X + 10.0 + leg_phase * 10.0, FLOOR_Y)
		draw_line(Vector2(PLAYER_X + 2.0, player_top + 32.0), f_knee, Color(0.8, 0.88, 0.95), 4.0)
		draw_line(f_knee, f_foot, Color(0.7, 0.8, 0.9), 3.5)

	else:
		# Aerodynamic Sliding Pose
		draw_rect(Rect2(PLAYER_X - 20.0, player_top + 8.0, 34.0, 16.0), Color(0.12, 0.18, 0.3))
		draw_rect(Rect2(PLAYER_X + 2.0, player_top + 2.0, 16.0, 12.0), Color(0.8, 0.88, 0.95))
		draw_rect(Rect2(PLAYER_X + 6.0, player_top + 5.0, 10.0, 3.0), Color(0.0, 1.0, 0.95))
		draw_rect(Rect2(PLAYER_X - 26.0, player_top + 16.0, 14.0, 6.0), Color(0.5, 0.6, 0.7))

	# HUD
	draw_string(
		ThemeDB.fallback_font,
		Vector2(24.0, 36.0),
		"SCORE: %d    COINS: %d    BEST: %d" % [score, coin_count, best_score],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		20,
		Color(0.9, 0.95, 1.0)
	)

	# Sound Button UI
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

	# Overlays
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
