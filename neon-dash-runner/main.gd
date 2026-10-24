
extends Control

const DEFAULT_CITY := "London"
const WEATHER_URL := "https://wttr.in/%s?format=j1"

var city_label: Label
var temp_label: Label
var condition_label: Label
var humidity_label: Label
var wind_label: Label
var search_bar: LineEdit
var hourly_container: HBoxContainer
var http_request: HTTPRequest

var current_request_id: int = 0
var current_city: String = ""

func _ready() -> void:
	print("Weather app started")

	# Make the root Control fill the screen.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

	http_request = HTTPRequest.new()
	http_request.timeout = 20.0
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

	_fetch_weather(DEFAULT_CITY)


func _exit_tree() -> void:
	if is_instance_valid(http_request):
		http_request.cancel_request()


func _build_ui() -> void:
	# Background.
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.07, 0.10, 0.17)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)

	# Main scrolling layout.
	var margin := MarginContainer.new()
	margin.name = "MainMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)

	# App title.
	var title := Label.new()
	title.text = "WEATHER"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	content.add_child(title)

	# Search.
	search_bar = LineEdit.new()
	search_bar.placeholder_text = "Enter a city..."
	search_bar.custom_minimum_size.y = 48
	search_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_bar.text_submitted.connect(_on_search_submitted)
	content.add_child(search_bar)

	var search_button := Button.new()
	search_button.text = "Search Weather"
	search_button.custom_minimum_size.y = 44
	search_button.pressed.connect(
		func() -> void:
			_fetch_weather(search_bar.text)
	)
	content.add_child(search_button)

	# Popular cities.
	var cities_title := Label.new()
	cities_title.text = "Popular cities"
	cities_title.add_theme_color_override("font_color", Color(0.75, 0.80, 0.90))
	content.add_child(cities_title)

	var cities_scroll := ScrollContainer.new()
	cities_scroll.custom_minimum_size.y = 46
	cities_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(cities_scroll)

	var cities_row := HBoxContainer.new()
	cities_row.add_theme_constant_override("separation", 8)
	cities_scroll.add_child(cities_row)

	for city in ["London", "Islamabad", "New York", "Tokyo", "Paris", "Sydney"]:
		var button := Button.new()
		button.text = city
		button.pressed.connect(_on_city_button_pressed.bind(city))
		cities_row.add_child(button)

	# Current weather.
	city_label = Label.new()
	city_label.text = "Loading weather..."
	city_label.add_theme_font_size_override("font_size", 27)
	city_label.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(city_label)

	temp_label = Label.new()
	temp_label.text = "--°C"
	temp_label.add_theme_font_size_override("font_size", 60)
	temp_label.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(temp_label)

	condition_label = Label.new()
	condition_label.text = "Connecting to weather service..."
	condition_label.add_theme_font_size_override("font_size", 17)
	condition_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92))
	content.add_child(condition_label)

	# Metric cards.
	var metrics := GridContainer.new()
	metrics.columns = 2
	metrics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.add_theme_constant_override("h_separation", 10)
	metrics.add_theme_constant_override("v_separation", 10)
	content.add_child(metrics)

	humidity_label = _make_metric(metrics, "Humidity", "--%")
	wind_label = _make_metric(metrics, "Wind speed", "-- km/h")

	# Hourly forecast.
	var forecast_title := Label.new()
	forecast_title.text = "Hourly forecast"
	forecast_title.add_theme_font_size_override("font_size", 19)
	forecast_title.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(forecast_title)

	var forecast_scroll := ScrollContainer.new()
	forecast_scroll.custom_minimum_size.y = 100
	forecast_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(forecast_scroll)

	hourly_container = HBoxContainer.new()
	hourly_container.add_theme_constant_override("separation", 16)
	forecast_scroll.add_child(hourly_container)

	_show_forecast_unavailable()


func _make_metric(parent: Control, heading: String, initial: String) -> Label:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(130, 76)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.18, 0.28)
	style.set_corner_radius_all(12)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var column := VBoxContainer.new()
	panel.add_child(column)

	var heading_label := Label.new()
	heading_label.text = heading
	heading_label.add_theme_color_override("font_color", Color(0.70, 0.77, 0.88))
	column.add_child(heading_label)

	var value_label := Label.new()
	value_label.text = initial
	value_label.add_theme_font_size_override("font_size", 19)
	value_label.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(value_label)

	return value_label


func _on_search_submitted(text: String) -> void:
	_fetch_weather(text)


func _on_city_button_pressed(city: String) -> void:
	search_bar.text = city
	_fetch_weather(city)


func _fetch_weather(city: String) -> void:
	var cleaned := city.strip_edges()

	# Invalidate earlier responses before processing the new search.
	current_request_id += 1
	var request_id := current_request_id

	if is_instance_valid(http_request):
		http_request.cancel_request()

	if cleaned.is_empty():
		_reset_weather("Please enter a city name")
		return

	current_city = cleaned
	city_label.text = cleaned
	condition_label.text = "Loading weather..."
	temp_label.text = "--°C"
	humidity_label.text = "--%"
	wind_label.text = "-- km/h"
	_show_forecast_unavailable()

	var url := WEATHER_URL % cleaned.uri_encode()
	var error := http_request.request(url)

	if error != OK and request_id == current_request_id:
		_reset_weather("Could not start the weather request")


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	var response_id := current_request_id

	if result != HTTPRequest.RESULT_SUCCESS:
		_reset_weather("Network error. Check your connection.")
		return

	if response_code != 200:
		_reset_weather("Weather service returned HTTP %d" % response_code)
		return

	var json := JSON.new()
	var parse_error := json.parse(body.get_string_from_utf8())

	if parse_error != OK:
		_reset_weather("Could not read weather data")
		return

	var data: Variant = json.get_data()

	if not data is Dictionary:
		_reset_weather("Invalid weather data")
		return

	var current: Array = data.get("current_condition", [])
	if current.is_empty() or not current[0] is Dictionary:
		_reset_weather("Weather data is incomplete")
		return

	var weather: Dictionary = current[0]

	if response_id != current_request_id:
		return

	var temp: Variant = weather.get("temp_C", "")
	temp_label.text = str(temp) + "°C" if str(temp).is_valid_float() else "--°C"

	var humidity: Variant = weather.get("humidity", "")
	humidity_label.text = str(humidity) + "%" if str(humidity).is_valid_int() else "--%"

	var wind: Variant = weather.get("windspeedKmph", "")
	wind_label.text = str(wind) + " km/h" if str(wind).is_valid_float() else "-- km/h"

	var description := "Unknown conditions"
	var descriptions: Array = weather.get("weatherDesc", [])

	if not descriptions.is_empty() and descriptions[0] is Dictionary:
		description = str(descriptions[0].get("value", description))

	city_label.text = current_city
	condition_label.text = description

	var days: Array = data.get("weather", [])
	if not days.is_empty() and days[0] is Dictionary:
		_populate_forecast(days[0].get("hourly", []))
	else:
		_show_forecast_unavailable()


func _reset_weather(message: String) -> void:
	city_label.text = current_city if not current_city.is_empty() else "Weather"
	temp_label.text = "--°C"
	humidity_label.text = "--%"
	wind_label.text = "-- km/h"
	condition_label.text = message
	_show_forecast_unavailable()


func _show_forecast_unavailable() -> void:
	if not is_instance_valid(hourly_container):
		return

	for child in hourly_container.get_children():
		hourly_container.remove_child(child)
		child.queue_free()

	var label := Label.new()
	label.text = "Forecast unavailable"
	label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92))
	hourly_container.add_child(label)


func _populate_forecast(entries: Array) -> void:
	_show_forecast_unavailable()

	# Remove the placeholder before adding forecast entries.
	for child in hourly_container.get_children():
		hourly_container.remove_child(child)
		child.queue_free()

	for entry in entries:
		if not entry is Dictionary:
			continue

		var raw_time := str(entry.get("time", ""))
		if not raw_time.is_valid_int():
			continue

		var time_value := int(raw_time)
		if time_value < 0 or time_value > 2400:
			continue

		var hours := int(time_value / 100)
		var minutes := time_value % 100

		if time_value == 2400:
			hours = 0
			minutes = 0
		elif hours > 23 or minutes > 59:
			continue

		var card := VBoxContainer.new()
		card.custom_minimum_size.x = 62
		hourly_container.add_child(card)

		var time_label := Label.new()
		time_label.text = "%02d:%02d" % [hours, minutes]
		card.add_child(time_label)

		var description := ""
		var descriptions: Array = entry.get("weatherDesc", [])
		if not descriptions.is_empty() and descriptions[0] is Dictionary:
			description = str(descriptions[0].get("value", "")).to_lower()

		var icon := Label.new()
		if "rain" in description:
			icon.text = "🌧️"
		elif "snow" in description:
			icon.text = "❄️"
		elif "thunder" in description:
			icon.text = "⚡"
		elif "cloud" in description or "overcast" in description:
			icon.text = "☁️"
		elif "clear" in description or "sun" in description:
			icon.text = "☀️"
		else:
			icon.text = "🌤️"
		card.add_child(icon)

		var temperature: Variant = entry.get("tempC", "")
		var temperature_label := Label.new()
		temperature_label.text = str(temperature) + "°" if str(temperature).is_valid_float() else "--°"
		card.add_child(temperature_label)

	if hourly_container.get_child_count() == 0:
		_show_forecast_unavailable()
