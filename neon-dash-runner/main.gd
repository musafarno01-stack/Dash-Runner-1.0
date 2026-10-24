extends Control

var city_input: LineEdit
var city_title_label: Label
var temp_label: Label
var condition_label: Label
var humidity_val_label: Label
var wind_val_label: Label
var uv_val_label: Label
var aqi_val_label: Label
var http_request: HTTPRequest

var current_city: String = "Kohat"


func _ready() -> void:
	# Configure root node as full rect container
	anchor_right = 1.0
	anchor_bottom = 1.0
	
	# Apply professional Google Weather background gradient panel
	var bg_panel = Panel.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.45, 0.88) # Google Weather Sky Blue
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(bg_panel)

	# Main Vertical Scroll/Layout Container
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	# 1. Search Bar (LineEdit)
	city_input = LineEdit.new()
	city_input.placeholder_text = "🔍 Search city (e.g., London, Manila, Kohat)..."
	city_input.custom_minimum_size = Vector2(0, 52)
	var search_style = StyleBoxFlat.new()
	search_style.bg_color = Color(1, 1, 1, 0.95)
	search_style.corner_radius_top_left = 26
	search_style.corner_radius_top_right = 26
	search_style.corner_radius_bottom_left = 26
	search_style.corner_radius_bottom_right = 26
	search_style.content_margin_left = 20
	city_input.add_theme_stylebox_override("normal", search_style)
	city_input.add_theme_stylebox_override("focus", search_style)
	city_input.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	city_input.add_theme_color_override("font_placeholder_color", Color(0.4, 0.4, 0.4))
	city_input.text_submitted.connect(_on_search_submitted)
	vbox.add_child(city_input)

	# 2. Quick Location Pills Row
	var pills_hbox = HBoxContainer.new()
	pills_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(pills_hbox)

	for c in ["Kohat", "Peshawar", "Islamabad", "London"]:
		var btn = Button.new()
		btn.text = c
		btn.custom_minimum_size = Vector2(80, 36)
		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(1, 1, 1, 0.3)
		btn_style.corner_radius_top_left = 18
		btn_style.corner_radius_top_right = 18
		btn_style.corner_radius_bottom_left = 18
		btn_style.corner_radius_bottom_right = 18
		btn.add_theme_stylebox_override("normal", btn_style)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.pressed.connect(func(): _fetch_weather(c))
		pills_hbox.add_child(btn)

	# 3. Main Weather Hero Card (Glassmorphism Panel)
	var hero_panel = Panel.new()
	hero_panel.custom_minimum_size = Vector2(0, 190)
	var hero_style = StyleBoxFlat.new()
	hero_style.bg_color = Color(0, 0, 0, 0.22)
	hero_style.corner_radius_top_left = 20
	hero_style.corner_radius_top_right = 20
	hero_style.corner_radius_bottom_left = 20
	hero_style.corner_radius_bottom_right = 20
	hero_style.content_margin_left = 24
	hero_style.content_margin_top = 20
	hero_panel.add_theme_stylebox_override("panel", hero_style)
	vbox.add_child(hero_panel)

	var hero_vbox = VBoxContainer.new()
	hero_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hero_panel.add_child(hero_vbox)

	city_title_label = Label.new()
	city_title_label.text = "Kohat, PK"
	city_title_label.add_theme_font_size_override("font_size", 28)
	city_title_label.add_theme_color_override("font_color", Color.WHITE)
	hero_vbox.add_child(city_title_label)

	condition_label = Label.new()
	condition_label.text = "Sunny & Clear"
	condition_label.add_theme_font_size_override("font_size", 16)
	condition_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	hero_vbox.add_child(condition_label)

	temp_label = Label.new()
	temp_label.text = "32°C"
	temp_label.add_theme_font_size_override("font_size", 54)
	temp_label.add_theme_color_override("font_color", Color.WHITE)
	hero_vbox.add_child(temp_label)

	# 4. Metrics Grid (2x2 Cards)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid)

	humidity_val_label = _create_metric_card(grid, "💧 HUMIDITY", "42%")
	wind_val_label = _create_metric_card(grid, "💨 WIND", "12.5 km/h")
	uv_val_label = _create_metric_card(grid, "☀️ UV INDEX", "5 of 10")
	aqi_val_label = _create_metric_card(grid, "🍃 AIR QUALITY", "Good (42)")

	# Setup HTTP Request for Live Weather
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

	# Fetch initial location weather
	_fetch_weather("Kohat")


func _create_metric_card(parent: Control, title: String, initial_val: String) -> Label:
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(180, 85)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.2)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.content_margin_left = 16
	style.content_margin_top = 14
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.8))
	vbox.add_child(title_lbl)

	var val_lbl = Label.new()
	val_lbl.text = initial_val
	val_lbl.add_theme_font_size_override("font_size", 18)
	val_lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(val_lbl)

	return val_lbl


func _on_search_submitted(new_text: String) -> void:
	if new_text.strip_edges() != "":
		_fetch_weather(new_text)
		city_input.release_focus()


func _fetch_weather(city_name: String) -> void:
	current_city = city_name.capitalize()
	city_title_label.text = current_city + ", PK"
	condition_label.text = "Fetching live weather..."
	
	var url = "https://wttr.in/%s?format=j1" % city_name.uri_encode()
	http_request.request(url)


func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data = json.get_data()
			if data and data is Dictionary and data.has("current_condition"):
				var cond = data["current_condition"][0]
				var t = cond.get("temp_C", "30")
				var desc = cond["weatherDesc"][0].get("value", "Clear")
				var hum = cond.get("humidity", "40")
				var wind = cond.get("windspeedKmph", "10")

				temp_label.text = str(t) + "°C"
				condition_label.text = str(desc)
				humidity_val_label.text = str(hum) + "%"
				wind_val_label.text = str(wind) + " km/h"
