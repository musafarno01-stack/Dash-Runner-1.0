extends Control

# UI Node References
var city_label: Label
var temp_label: Label
var condition_label: Label
var humidity_label: Label
var wind_label: Label
var search_bar: LineEdit
var hourly_container: HBoxContainer
var http_request: HTTPRequest

# Request management & concurrency tracking
var current_requested_city: String = ""
var current_request_id: int = 0
var active_callback: Callable = Callable()

const DEFAULT_CITY = "London"

func _ready() -> void:
	_build_ui()
	
	# Configure HTTPRequest with a timeout for reliability
	http_request = HTTPRequest.new()
	http_request.timeout = 15.0
	add_child(http_request)
	
	# Fetch initial weather data
	_fetch_weather(DEFAULT_CITY)

func _exit_tree() -> void:
	# Lifecycle safeguard: cancel requests and disconnect signals when node is removed
	if is_instance_valid(http_request):
		http_request.cancel_request()

		if active_callback.is_valid():
			if http_request.request_completed.is_connected(active_callback):
				http_request.request_completed.disconnect(active_callback)

	active_callback = Callable()

func _build_ui() -> void:
	# 1. Add styled background panel FIRST so it sits behind everything else
	var bg = Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.15, 0.22) # Sleek modern dark blue-gray
	bg.add_theme_stylebox_override("panel", bg_style)
	add_child(bg)

	# Root layout setup added AFTER background with compact mobile margins
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	# Vertical ScrollContainer managed correctly by MarginContainer container layout
	var root_scroll = ScrollContainer.new()
	root_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root_scroll)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_scroll.add_child(main_vbox)

	# Search Bar
	search_bar = LineEdit.new()
	search_bar.placeholder_text = "Search city (e.g., London, Tokyo)..."
	search_bar.text_submitted.connect(_on_search_submitted)
	main_vbox.add_child(search_bar)

	# Quick City Shortcuts wrapped in a horizontal ScrollContainer for mobile screens
	var shortcuts_scroll = ScrollContainer.new()
	shortcuts_scroll.custom_minimum_size.height = 38
	main_vbox.add_child(shortcuts_scroll)

	var shortcuts_hbox = HBoxContainer.new()
	shortcuts_hbox.add_theme_constant_override("separation", 6)
	shortcuts_scroll.add_child(shortcuts_hbox)
	
	var cities = ["London", "Islamabad", "New York", "Tokyo", "Paris", "Sydney"]
	for c in cities:
		var btn = Button.new()
		btn.text = c
		btn.pressed.connect(func(): _fetch_weather(c))
		shortcuts_hbox.add_child(btn)

	# Main Weather Overview Display with explicit high-contrast font colors
	var info_vbox = VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 2)
	main_vbox.add_child(info_vbox)

	city_label = Label.new()
	city_label.text = "Loading..."
	city_label.add_theme_font_size_override("font_size", 24)
	city_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	info_vbox.add_child(city_label)

	temp_label = Label.new()
	temp_label.text = "--°C"
	temp_label.add_theme_font_size_override("font_size", 42)
	temp_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	info_vbox.add_child(temp_label)

	condition_label = Label.new()
	condition_label.text = "Fetching data..."
	condition_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	info_vbox.add_child(condition_label)

	# Metrics Grid Container optimized with slightly reduced minimum card width for narrow viewports
	var metrics_grid = GridContainer.new()
	metrics_grid.columns = 2
	metrics_grid.add_theme_constant_override("h_separation", 8)
	metrics_grid.add_theme_constant_override("v_separation", 8)
	main_vbox.add_child(metrics_grid)

	humidity_label = _create_metric_card(metrics_grid, "Humidity", "--%")
	wind_label = _create_metric_card(metrics_grid, "Wind Speed", "-- km/h")

	# Hourly Forecast Section Header
	var hourly_title = Label.new()
	hourly_title.text = "Hourly Forecast (Today)"
	hourly_title.add_theme_font_size_override("font_size", 14)
	hourly_title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	main_vbox.add_child(hourly_title)

	# Scrollable container for dynamic hourly items
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.height = 90
	main_vbox.add_child(scroll)

	hourly_container = HBoxContainer.new()
	hourly_container.add_theme_constant_override("separation", 8)
	scroll.add_child(hourly_container)

func _create_metric_card(parent: Node, title: String, initial_val: String) -> Label:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(95, 48) # Optimized compact width for very narrow viewports
	parent.add_child(panel)

	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 10)
	title_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	vbox.add_child(title_lbl)

	var val_lbl = Label.new()
	val_lbl.text = initial_val
	val_lbl.add_theme_font_size_override("font_size", 15)
	val_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	vbox.add_child(val_lbl)

	return val_lbl

func _on_search_submitted(new_text: String) -> void:
	_fetch_weather(new_text)

func _fetch_weather(city: String) -> void:
	var cleaned_city = city.strip_edges()

	# Invalidate any earlier request first.
	current_request_id += 1
	http_request.cancel_request()

	if active_callback.is_valid():
		if http_request.request_completed.is_connected(active_callback):
			http_request.request_completed.disconnect(active_callback)
		active_callback = Callable()

	if cleaned_city.is_empty():
		_reset_ui_on_error("", "Please enter a city name")
		return

	var request_id = current_request_id

	active_callback = _on_weather_data_received.bind(request_id)
	http_request.request_completed.connect(active_callback, CONNECT_ONE_SHOT)

	current_requested_city = cleaned_city
	city_label.text = cleaned_city
	condition_label.text = "Loading weather..."

	var url = "https://wttr.in/%s?format=j1" % cleaned_city.uri_encode()
	var error = http_request.request(url)

	if error != OK and request_id == current_request_id:
		if http_request.request_completed.is_connected(active_callback):
			http_request.request_completed.disconnect(active_callback)
		active_callback = Callable()
		_reset_ui_on_error(cleaned_city, "Could not start request")

func _on_weather_data_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request_id: int) -> void:
	# Ignore old responses
	if request_id != current_request_id:
		return

	# Clear callback for the current request
	active_callback = Callable()

	if result == HTTPRequest.RESULT_CANCELED:
		return

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_reset_ui_on_error(current_requested_city, "Unable to load weather")
		return

	var json = JSON.new()
	var parse_error = json.parse(body.get_string_from_utf8())
	if parse_error != OK:
		_reset_ui_on_error(current_requested_city, "Data parsing error")
		return

	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		_reset_ui_on_error(current_requested_city, "Invalid data format")
		return

	# Strict nested dictionary validation for current_condition
	var current_cond = {}
	if data.has("current_condition") and typeof(data["current_condition"]) == TYPE_ARRAY and data["current_condition"].size() > 0:
		var first_elem = data["current_condition"][0]
		if typeof(first_elem) == TYPE_DICTIONARY:
			current_cond = first_elem
			
	if current_cond.is_empty():
		_reset_ui_on_error(current_requested_city, "Incomplete weather data")
		return

	# Strict realistic range validation for current temperature (-100°C to 70°C)
	var temp_val = current_cond.get("temp_C", null)
	if _is_valid_number(temp_val) and float(temp_val) >= -100.0 and float(temp_val) <= 70.0:
		temp_label.text = str(temp_val) + "°C"
	else:
		temp_label.text = "--°C"

	# Strict realistic range validation for humidity (0% to 100%)
	var hum_val = current_cond.get("humidity", null)
	if _is_valid_number(hum_val) and float(hum_val) >= 0.0 and float(hum_val) <= 100.0:
		humidity_label.text = str(hum_val) + "%"
	else:
		humidity_label.text = "--%"

	# Strict realistic range validation for wind speed (non-negative, upper bound 500 km/h)
	var wind_val = current_cond.get("windspeedKmph", null)
	if _is_valid_number(wind_val) and float(wind_val) >= 0.0 and float(wind_val) <= 500.0:
		wind_label.text = str(wind_val) + " km/h"
	else:
		wind_label.text = "-- km/h"

	# Strict type-validated and non-empty weather description lookup
	var desc = "Unknown"
	if current_cond.has("weatherDesc") and typeof(current_cond["weatherDesc"]) == TYPE_ARRAY and current_cond["weatherDesc"].size() > 0:
		var desc_elem = current_cond["weatherDesc"][0]
		if typeof(desc_elem) == TYPE_DICTIONARY:
			var raw_desc = desc_elem.get("value", "Unknown")
			if typeof(raw_desc) == TYPE_STRING and not raw_desc.strip_edges().is_empty():
				desc = raw_desc.strip_edges()
	condition_label.text = desc

	# Strict nested validation and parsing for hourly forecast blocks
	var forecast_populated = false
	if data.has("weather") and typeof(data["weather"]) == TYPE_ARRAY and data["weather"].size() > 0:
		var weather_elem = data["weather"][0]
		if typeof(weather_elem) == TYPE_DICTIONARY:
			if weather_elem.has("hourly") and typeof(weather_elem["hourly"]) == TYPE_ARRAY:
				_populate_live_hourly_forecast(weather_elem["hourly"])
				forecast_populated = true
				
	if not forecast_populated:
		_populate_live_hourly_forecast([])

func _is_valid_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return is_finite(float(value))

	if typeof(value) == TYPE_STRING:
		var cleaned = value.strip_edges()
		if cleaned.is_valid_float():
			return is_finite(cleaned.to_float())

	return false

func _reset_ui_on_error(city: String, error_message: String) -> void:
	city_label.text = city if city != "" else "Error"
	condition_label.text = error_message
	temp_label.text = "--°C"
	humidity_label.text = "--%"
	wind_label.text = "-- km/h"
	_populate_live_hourly_forecast([])

func _populate_live_hourly_forecast(hourly_array: Array) -> void:
	# Immediate removal of existing children to prevent frame-lagged child counts
	for child in hourly_container.get_children():
		hourly_container.remove_child(child)
		child.queue_free()

	for entry in hourly_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		
		# Improved hourly forecast time validation
		var raw_time_val = entry.get("time", -1)
		var formatted_time = ""
		
		if typeof(raw_time_val) in [TYPE_INT, TYPE_STRING]:
			var raw_time_str = str(raw_time_val).strip_edges()
			if raw_time_str.is_valid_int():
				var time_int = raw_time_str.to_int()
				if time_int == 2400:
					formatted_time = "00:00"
				elif time_int >= 0 and time_int < 2400:
					var hours = int(time_int / 100)
					var minutes = time_int % 100

					if hours <= 23 and minutes <= 59:
						formatted_time = "%02d:%02d" % [hours, minutes]

		# Skip entry entirely if time formatting fails validation
		if formatted_time.is_empty():
			continue

		var card = VBoxContainer.new()
		card.custom_minimum_size = Vector2(60, 70)

		var time_lbl = Label.new()
		time_lbl.text = formatted_time
		time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		time_lbl.add_theme_font_size_override("font_size", 10)
		time_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		card.add_child(time_lbl)

		var icon_lbl = Label.new()
		icon_lbl.text = _get_weather_emoji(entry)
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(icon_lbl)

		# Strict numeric validation using _is_valid_number helper for forecast temperatures
		var temp_val = entry.get("tempC", null)
		var display_temp = "--"
		if _is_valid_number(temp_val) and float(temp_val) >= -100.0 and float(temp_val) <= 70.0:
			display_temp = str(temp_val)

		var temp_lbl = Label.new()
		temp_lbl.text = display_temp + "°"
		temp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		temp_lbl.add_theme_font_size_override("font_size", 12)
		temp_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		card.add_child(temp_lbl)

		hourly_container.add_child(card)

	# Fallback check if all items in the array were skipped or the array was empty
	if hourly_container.get_child_count() == 0:
		var msg_lbl = Label.new()
		msg_lbl.text = "Hourly forecast unavailable"
		msg_lbl.add_theme_font_size_override("font_size", 12)
		msg_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
		hourly_container.add_child(msg_lbl)

func _get_weather_emoji(hourly_entry: Dictionary) -> String:
	var desc = ""
	if hourly_entry.has("weatherDesc") and typeof(hourly_entry["weatherDesc"]) == TYPE_ARRAY and hourly_entry["weatherDesc"].size() > 0:
		var desc_elem = hourly_entry["weatherDesc"][0]
		if typeof(desc_elem) == TYPE_DICTIONARY:
			var raw_desc = desc_elem.get("value", "")
			if typeof(raw_desc) == TYPE_STRING and not raw_desc.strip_edges().is_empty():
				desc = raw_desc.strip_edges().to_lower()
	
	if "sun" in desc or "clear" in desc:
		return "☀️"
	elif "cloud" in desc or "overcast" in desc:
		return "☁️"
	elif "rain" in desc or "shower" in desc:
		return "🌧️"
	elif "snow" in desc:
		return "❄️"
	elif "thunder" in desc:
		return "⚡"
	
	return "🌤️"
