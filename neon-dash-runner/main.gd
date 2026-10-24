extends Node2D

enum WeatherType { SUNNY, CLOUDY, RAINY, THUNDER, SNOW }

# Current Selected City Weather Data
var current_city: String = "Kohat"
var current_temp: int = 32
var weather_type: WeatherType = WeatherType.SUNNY
var weather_condition_text: String = "Mostly Sunny"
var humidity: int = 42
var wind_speed: float = 12.5
var uv_index: int = 6
var air_quality: String = "Good (45 µg/m³)"
var visibility: float = 10.0

# Search & Interaction State
var is_searching: bool = false
var search_query: String = ""
var scroll_offset: float = 0.0
var max_scroll: float = 300.0

# Hourly Forecast Data
var hourly_forecast = [
	{"time": "Now", "temp": 32, "icon": "☀️"},
	{"time": "1 PM", "temp": 34, "icon": "☀️"},
	{"time": "2 PM", "temp": 35, "icon": "🌤️"},
	{"time": "3 PM", "temp": 34, "icon": "⛅"},
	{"time": "4 PM", "temp": 32, "icon": "⛅"},
	{"time": "5 PM", "temp": 30, "icon": "🌥️"},
	{"time": "6 PM", "temp": 28, "icon": "🌙"},
	{"time": "7 PM", "temp": 26, "icon": "🌙"}
]

# 7-Day Forecast Data
var weekly_forecast = [
	{"day": "Today", "cond": "Sunny", "low": 24, "high": 35},
	{"day": "Sun", "cond": "Partly Cloudy", "low": 22, "high": 33},
	{"day": "Mon", "cond": "Scattered Showers", "low": 20, "high": 29},
	{"day": "Tue", "cond": "Thunderstorm", "low": 19, "high": 27},
	{"day": "Wed", "cond": "Sunny", "low": 21, "high": 32},
	{"day": "Thu", "cond": "Clear", "low": 23, "high": 34},
	{"day": "Fri", "cond": "Sunny", "low": 24, "high": 36}
]

# Visual animation timers
var anim_timer: float = 0.0
var raindrops: Array[Dictionary] = []
var clouds: Array[Dictionary] = []


func _ready() -> void:
	_init_particles()
	queue_redraw()


func _init_particles() -> void:
	for i in range(15):
		clouds.append({
			"x": randf_range(-100.0, 900.0),
			"y": randf_range(40.0, 220.0),
			"speed": randf_range(8.0, 20.0),
			"size": randf_range(40.0, 90.0)
		})
	for i in range(40):
		raindrops.append({
			"x": randf_range(0.0, 800.0),
			"y": randf_range(0.0, 600.0),
			"speed": randf_range(400.0, 700.0),
			"length": randf_range(12.0, 25.0)
		})


func _process(delta: float) -> void:
	anim_timer += delta

	# Move clouds
	for c in clouds:
		c["x"] += c["speed"] * delta
		if c["x"] > 900.0:
			c["x"] = -120.0

	# Move rain if rainy
	if weather_type == WeatherType.RAINY or weather_type == WeatherType.THUNDER:
		for r in raindrops:
			r["y"] += r["speed"] * delta
			if r["y"] > 600.0:
				r["y"] = -30.0
				r["x"] = randf_range(0.0, 800.0)

	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if is_searching:
			if event.keycode == KEY_BACKSPACE and search_query.length() > 0:
				search_query = search_query.left(search_query.length() - 1)
			elif event.keycode == KEY_ENTER or event.keycode == KEY_RETURN:
				_lookup_city(search_query)
				is_searching = false
				search_query = ""
			elif event.alt_pressed == false and event.ctrl_pressed == false and event.unicode > 31:
				search_query += char(event.unicode)
		else:
			if event.keycode == KEY_S:
				is_location_enabled = not is_location_enabled
				_trigger_notification("Location Services " + ("Enabled" if is_location_enabled else "Disabled"))

	if event is InputEventScreenTouch and event.pressed:
		_handle_click(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(event.position)


var is_location_enabled: bool = true
var notification_text: String = ""
var notification_timer: float = 0.0


func _trigger_notification(msg: String) -> void:
	notification_text = msg
	notification_timer = 3.5


func _lookup_city(city_name: String) -> void:
	if city_name.strip_edges() == "":
		return
	current_city = city_name.capitalize()
	
	# Mock data randomization based on city name for realism
	var hash_val = current_city.hash() % 5
	match hash_val:
		0:
			weather_type = WeatherType.SUNNY
			weather_condition_text = "Sunny & Clear"
			current_temp = randi_range(28, 38)
			humidity = 35
		1:
			weather_type = WeatherType.CLOUDY
			weather_condition_text = "Partly Cloudy"
			current_temp = randi_range(22, 29)
			humidity = 60
		2:
			weather_type = WeatherType.RAINY
			weather_condition_text = "Light Showers"
			current_temp = randi_range(17, 24)
			humidity = 88
		3:
			weather_type = WeatherType.THUNDER
			weather_condition_text = "Thunderstorm"
			current_temp = randi_range(16, 22)
			humidity = 92
		4:
			weather_type = WeatherType.SNOW
			weather_condition_text = "Light Snow"
			current_temp = randi_range(-4, 3)
			humidity = 75

	_trigger_notification("Weather updated for " + current_city)


func _handle_click(pos: Vector2) -> void:
	var screen_size = get_viewport_rect().size

	# Search Bar Click
	var search_rect = Rect2(40.0, 20.0, screen_size.x - 80.0, 48.0)
	if search_rect.has_point(pos):
		is_searching = true
		return

	# Quick City Pill Buttons
	var cities = ["Kohat", "Islamabad", "Peshawar", "Manila", "London", "New York"]
	var start_x = 40.0
	for c in cities:
		var pill_rect = Rect2(start_x, 80.0, 95.0, 34.0)
		if pill_rect.has_point(pos):
			_lookup_city(c)
			is_searching = false
			return
		start_x += 105.0


func _draw() -> void:
	var screen_size = get_viewport_rect().size

	# 1. Dynamic Background Gradient based on Weather
	var top_color = Color(0.12, 0.45, 0.85) # Sunny Blue
	var bot_color = Color(0.25, 0.65, 0.95)
	
	match weather_type:
		WeatherType.CLOUDY:
			top_color = Color(0.28, 0.42, 0.58)
			bot_color = Color(0.48, 0.62, 0.78)
		WeatherType.RAINY:
			top_color = Color(0.15, 0.25, 0.38)
			bot_color = Color(0.28, 0.42, 0.55)
		WeatherType.THUNDER:
			top_color = Color(0.08, 0.10, 0.18)
			bot_color = Color(0.18, 0.22, 0.32)
		WeatherType.SNOW:
			top_color = Color(0.32, 0.48, 0.65)
			bot_color = Color(0.55, 0.72, 0.88)

	draw_rect(Rect2(Vector2.ZERO, screen_size), top_color)

	# 2. Render Animated Clouds for Cloudy/Rainy
	if weather_type != WeatherType.SUNNY:
		for c in clouds:
			draw_circle(Vector2(c["x"], c["y"]), c["size"], Color(1.0, 1.0, 1.0, 0.25))
			draw_circle(Vector2(c["x"] + 30.0, c["y"] + 10.0), c["size"] * 0.8, Color(1.0, 1.0, 1.0, 0.2))

	# 3. Render Rain if applicable
	if weather_type == WeatherType.RAINY or weather_type == WeatherType.THUNDER:
		for r in raindrops:
			draw_line(Vector2(r["x"], r["y"]), Vector2(r["x"] - 2.0, r["y"] + r["length"]), Color(0.7, 0.85, 1.0, 0.6), 1.5)

	# 4. Google Weather Search Bar UI
	var search_bg = Rect2(40.0, 20.0, screen_size.x - 80.0, 48.0)
	draw_rect(search_bg, Color(1.0, 1.0, 1.0, 0.92), true)
	draw_rect(search_bg, Color(0.8, 0.85, 0.9, 1.0), false, 1.5)
	
	var search_display = "🔍 Search city (e.g., London, Tokyo)..." if search_query == "" else "🔍 " + search_query + ("_" if int(anim_timer * 2.0) % 2 == 0 else "")
	draw_string(ThemeDB.fallback_font, Vector2(65.0, 50.0), search_display, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.2, 0.2, 0.2))

	# 5. Quick City Selector Pills
	var cities = ["Kohat", "Islamabad", "Peshawar", "Manila", "London", "New York"]
	var start_x = 40.0
	for c in cities:
		var pill = Rect2(start_x, 80.0, 95.0, 34.0)
		var is_selected = (c.to_lower() == current_city.to_lower())
		draw_rect(pill, Color(1.0, 1.0, 1.0, 0.4 if not is_selected else 0.9), true)
		draw_string(ThemeDB.fallback_font, Vector2(start_x + 12.0, 102.0), c, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.1, 0.1, 0.1) if is_selected else Color(1.0, 1.0, 1.0))
		start_x += 105.0

	# 6. Main Weather Hero Card (Google Style Glassmorphism)
	var hero_card = Rect2(40.0, 130.0, screen_size.x - 80.0, 180.0)
	draw_rect(hero_card, Color(0.0, 0.0, 0.0, 0.22), true)
	draw_rect(hero_card, Color(1.0, 1.0, 1.0, 0.3), false, 1.5)

	# City Name & Status
	draw_string(ThemeDB.fallback_font, Vector2(65.0, 170.0), current_city + ", Pakistan" if current_city == "Kohat" else current_city, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, Color(1.0, 1.0, 1.0))
	draw_string(ThemeDB.fallback_font, Vector2(65.0, 195.0), weather_condition_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.9, 0.95, 1.0))

	# Big Temperature Number
	draw_string(ThemeDB.fallback_font, Vector2(65.0, 265.0), "%d°C" % current_temp, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 56, Color(1.0, 1.0, 1.0))

	# Weather Icon Graphic on right side of Hero Card
	var icon_symbol = "☀️"
	match weather_type:
		WeatherType.CLOUDY: icon_symbol = "⛅"
		WeatherType.RAINY: icon_symbol = "🌧️"
		WeatherType.THUNDER: icon_symbol = "⛈️"
		WeatherType.SNOW: icon_symbol = "❄️"
	draw_string(ThemeDB.fallback_font, Vector2(screen_size.x - 140.0, 235.0), icon_symbol, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 64, Color(1.0, 1.0, 1.0))

	# 7. Hourly Forecast Strip
	var hourly_y = 330.0
	draw_string(ThemeDB.fallback_font, Vector2(40.0, hourly_y), "HOURLY FORECAST", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.9, 0.95, 1.0, 0.8))
	
	var h_card = Rect2(40.0, hourly_y + 15.0, screen_size.x - 80.0, 90.0)
	draw_rect(h_card, Color(0.0, 0.0, 0.0, 0.2), true)
	
	var h_x = 60.0
	for h in hourly_forecast:
		draw_string(ThemeDB.fallback_font, Vector2(h_x, hourly_y + 42.0), h["time"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.8, 0.9, 1.0))
		draw_string(ThemeDB.fallback_font, Vector2(h_x + 2.0, hourly_y + 68.0), h["icon"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(1.0, 1.0, 1.0))
		draw_string(ThemeDB.fallback_font, Vector2(h_x, hourly_y + 92.0), "%d°" % h["temp"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(1.0, 1.0, 1.0))
		h_x += 75.0

	# 8. Detailed Weather Metrics Grid (Humidity, Wind, UV, AQI)
	var grid_y = 450.0
	var col_w = (screen_size.x - 95.0) * 0.5
	
	_draw_metric_card(Rect2(40.0, grid_y, col_w, 75.0), "💧 HUMIDITY", "%d%%" % humidity, "The dew point is 18° right now.")
	_draw_metric_card(Rect2(55.0 + col_w, grid_y, col_w, 75.0), "💨 WIND", "%.1f km/h" % wind_speed, "Light breeze from Northwest.")
	_draw_metric_card(Rect2(40.0, grid_y + 88.0, col_w, 75.0), "☀️ UV INDEX", "%d of 10" % uv_index, "Low sun protection recommended.")
	_draw_metric_card(Rect2(55.0 + col_w, grid_y + 88.0, col_w, 75.0), "🍃 AIR QUALITY", air_quality, "Air quality is satisfactory.")

	# 9. Notification Toast Banner
	if notification_timer > 0.0:
		notification_timer -= get_process_delta_time()
		var toast_rect = Rect2(40.0, screen_size.y - 70.0, screen_size.x - 80.0, 44.0)
		draw_rect(toast_rect, Color(0.1, 0.12, 0.18, 0.95), true)
		draw_rect(toast_rect, Color(0.0, 0.85, 1.0, 1.0), false, 1.5)
		draw_string(ThemeDB.fallback_font, Vector2(60.0, screen_size.y - 42.0), "🔔 " + notification_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(1.0, 1.0, 1.0))


func _draw_metric_card(rect: Rect2, title: String, val: String, subtitle: String) -> void:
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.2), true)
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.15), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 14.0, rect.position.y + 22.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.85, 0.9, 1.0, 0.8))
	draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 14.0, rect.position.y + 48.0), val, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(1.0, 1.0, 1.0))
	draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 14.0, rect.position.y + 64.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(0.75, 0.85, 0.95, 0.7))
