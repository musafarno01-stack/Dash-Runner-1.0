extends Node2D

enum WeatherType { SUNNY, CLOUDY, RAINY, THUNDER, SNOW }

# Live Selected City State
var current_city: String = "Kohat"
var current_temp: int = 32
var weather_condition_text: String = "Sunny & Clear"
var humidity: int = 42
var wind_speed: float = 12.5
var uv_index: int = 5
var air_quality: String = "Good"

var is_searching: bool = false
var search_query: String = ""
var anim_timer: float = 0.0
var http_request: HTTPRequest

var raindrops: Array[Dictionary] = []
var clouds: Array[Dictionary] = []

var hourly_forecast = [
	{"time": "Now", "temp": 32, "icon": "☀️"},
	{"time": "1 PM", "temp": 34, "icon": "☀️"},
	{"time": "2 PM", "temp": 35, "icon": "🌤️"},
	{"time": "3 PM", "temp": 34, "icon": "⛅"},
	{"time": "4 PM", "temp": 32, "icon": "⛅"},
	{"time": "5 PM", "temp": 30, "icon": "🌥️"}
]


func _ready() -> void:
	# Initialize HTTP Request node for live weather fetching
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_weather_request_completed)

	_init_particles()
	
	# Automatically fetch weather for current default location (Kohat)
	_fetch_weather_data("Kohat")
	queue_redraw()


func _init_particles() -> void:
	clouds.clear()
	raindrops.clear()
	for i in range(10):
		clouds.append({
			"x": randf_range(-100.0, 500.0),
			"y": randf_range(30.0, 180.0),
			"speed": randf_range(5.0, 15.0),
			"size": randf_range(30.0, 60.0)
		})
	for i in range(30):
		raindrops.append({
			"x": randf_range(0.0, 500.0),
			"y": randf_range(0.0, 950.0),
			"speed": randf_range(400.0, 700.0),
			"length": randf_range(12.0, 22.0)
		})


func _fetch_weather_data(city_name: String) -> void:
	current_city = city_name.capitalize()
	var url = "https://wttr.in/%s?format=j1" % city_name.uri_encode()
	var error = http_request.request(url)
	if error != OK:
		print("Failed to dispatch weather request.")


func _on_weather_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(body.get_string_from_utf8())
		if parse_result == OK:
			var data = json.get_data()
			if data and data is Dictionary:
				if data.has("current_condition") and data["current_condition"].size() > 0:
					var cond = data["current_condition"][0]
					current_temp = int(cond.get("temp_C", "32"))
					wind_speed = float(cond.get("windspeedKmph", "12"))
					humidity = int(cond.get("humidity", "45"))
					
					if cond.has("weatherDesc") and cond["weatherDesc"].size() > 0:
						weather_condition_text = str(cond["weatherDesc"][0].get("value", "Clear"))
				queue_redraw()


func _process(delta: float) -> void:
	anim_timer += delta

	for c in clouds:
		c["x"] += c["speed"] * delta
		if c["x"] > 520.0:
			c["x"] = -100.0

	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if is_searching:
			if event.keycode == KEY_BACKSPACE and search_query.length() > 0:
				search_query = search_query.left(search_query.length() - 1)
			elif event.keycode == KEY_ENTER or event.keycode == KEY_RETURN:
				_fetch_weather_data(search_query)
				is_searching = false
				search_query = ""
			elif event.unicode > 31:
				search_query += char(event.unicode)

	if event is InputEventScreenTouch and event.pressed:
		_handle_click(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(event.position)


func _handle_click(pos: Vector2) -> void:
	var screen_w = get_viewport_rect().size.x

	# Search bar touch area
	if Rect2(20.0, 20.0, screen_w - 40.0, 48.0).has_point(pos):
		is_searching = true
		return

	# Quick City Pill Buttons (Kohat is set as primary location shortcut)
	var cities = ["Kohat", "Peshawar", "Islamabad", "London", "Tokyo"]
	var start_x = 20.0
	for c in cities:
		var pill_rect = Rect2(start_x, 80.0, 78.0, 32.0)
		if pill_rect.has_point(pos):
			_fetch_weather_data(c)
			is_searching = false
			return
		start_x += 84.0


func _draw() -> void:
	var size = get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return

	# Background Sky Gradient
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.45, 0.85))

	# Sun Graphic
	var sun_center = Vector2(size.x - 70.0, 175.0)
	draw_circle(sun_center, 42.0, Color(1.0, 0.9, 0.4, 0.9))

	var font = ThemeDB.fallback_font
	if not font:
		return

	# Search Bar UI
	var search_rect = Rect2(20.0, 20.0, size.x - 40.0, 48.0)
	draw_rect(search_rect, Color(1.0, 1.0, 1.0, 0.94), true)
	draw_rect(search_rect, Color(0.75, 0.8, 0.88), false, 1.5)

	var display_search = "📍 Search location or city..." if search_query == "" else "🔍 " + search_query + ("|" if int(anim_timer * 2.0) % 2 == 0 else "")
	draw_string(font, Vector2(38.0, 50.0), display_search, HORIZONTAL_ALIGNMENT_LEFT, size.x - 70.0, 15, Color(0.2, 0.2, 0.25))

	# Quick Location Pills (Kohat is first)
	var cities = ["Kohat", "Peshawar", "Islamabad", "London", "Tokyo"]
	var start_x = 20.0
	for c in cities:
		var pill = Rect2(start_x, 80.0, 78.0, 32.0)
		var is_selected = (c.to_lower() == current_city.to_lower())
		draw_rect(pill, Color(1.0, 1.0, 1.0, 0.95 if is_selected else 0.32), true)
		draw_string(font, Vector2(start_x + 8.0, 101.0), c, HORIZONTAL_ALIGNMENT_LEFT, 70.0, 12, Color(0.1, 0.1, 0.1) if is_selected else Color(1.0, 1.0, 1.0))
		start_x += 84.0

	# Hero Weather Display Card
	var hero_rect = Rect2(20.0, 130.0, size.x - 40.0, 200.0)
	draw_rect(hero_rect, Color(0.0, 0.0, 0.0, 0.22), true)
	draw_rect(hero_rect, Color(1.0, 1.0, 1.0, 0.28), false, 1.5)

	draw_string(font, Vector2(42.0, 175.0), current_city + ", PK" if current_city == "Kohat" else current_city, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, Color.WHITE)
	draw_string(font, Vector2(42.0, 202.0), weather_condition_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.9, 0.95, 1.0))
	draw_string(font, Vector2(42.0, 285.0), "%d°C" % current_temp, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 62, Color.WHITE)

	# Hourly Forecast Strip Card
	var hourly_rect = Rect2(20.0, 350.0, size.x - 40.0, 115.0)
	draw_rect(hourly_rect, Color(0.0, 0.0, 0.0, 0.2), true)
	draw_string(font, Vector2(35.0, 376.0), "HOURLY FORECAST", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.88, 0.92, 1.0, 0.8))

	var h_x = 35.0
	for h in hourly_forecast:
		draw_string(font, Vector2(h_x, 402.0), h["time"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.8, 0.9, 1.0))
		draw_string(font, Vector2(h_x + 2.0, 428.0), h["icon"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color.WHITE)
		draw_string(font, Vector2(h_x + 2.0, 448.0), "%d°" % h["temp"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color.WHITE)
		h_x += 58.0

	# Metrics Grid Cards
	var card_w = (size.x - 52.0) * 0.5
	_draw_metric_card(Rect2(20.0, 480.0, card_w, 82.0), "💧 HUMIDITY", "%d%%" % humidity, "Normal levels")
	_draw_metric_card(Rect2(32.0 + card_w, 480.0, card_w, 82.0), "💨 WIND", "%.1f km/h" % wind_speed, "Breeze active")
	_draw_metric_card(Rect2(20.0, 574.0, card_w, 82.0), "☀️ UV INDEX", "%d of 10" % uv_index, "Low risk")
	_draw_metric_card(Rect2(32.0 + card_w, 574.0, card_w, 82.0), "🍃 AIR QUALITY", air_quality, "Satisfactory")


func _draw_metric_card(rect: Rect2, title: String, val: String, sub: String) -> void:
	var font = ThemeDB.fallback_font
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.2), true)
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.18), false, 1.0)
	if font:
		draw_string(font, Vector2(rect.position.x + 12.0, rect.position.y + 22.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(0.8, 0.9, 1.0, 0.8))
		draw_string(font, Vector2(rect.position.x + 12.0, rect.position.y + 48.0), val, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color.WHITE)
		draw_string(font, Vector2(rect.position.x + 12.0, rect.position.y + 68.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(0.75, 0.85, 0.95, 0.7))
