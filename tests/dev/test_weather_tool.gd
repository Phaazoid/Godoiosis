# The Weather page (#1260). Its rows are WeatherLook.ROWS, declared beside the fields they name, so the
# law here is that every field has exactly one row and every row a field -- a look value with no row is
# a feel value with no knob, which the tuning rule forbids. And the wire: dragging a row's slider moves
# the very look the mirror draws from (the no-placebo law, tests/dev/test_moods_tool.gd's shape).
extends GdUnitTestSuite


func _exported(resource: Resource) -> Array[String]:
	var names: Array[String] = []
	for prop in resource.get_property_list():
		if DevWidgets.is_exported(prop):
			names.append(String(prop.name))
	return names


func test_every_look_field_has_one_row_and_every_row_a_field() -> void:
	var fields := _exported(WeatherLook.new())
	var rows: Array[String] = []
	for row: Dictionary in WeatherLook.ROWS:
		rows.append(row["prop"])
		assert_bool(fields.has(row["prop"])).override_failure_message(
				"row '%s' names no field" % row["prop"]).is_true()
		assert_str(row.get("tip", "")).override_failure_message("row '%s' has no tooltip" % row["prop"]).is_not_empty()
	for field in fields:
		assert_int(rows.count(field)).override_failure_message(
				"field '%s' has %d rows on the Weather page" % [field, rows.count(field)]).is_equal(1)


func test_a_slider_moves_the_look_the_mirror_draws_from() -> void:
	var look := WeatherLook.for_kind(Weather.Kind.RAIN)
	assert_object(look).override_failure_message("fixture: rain has no look file").is_not_null()
	var was := look.fall_speed
	var page := WeatherTool.new()
	add_child(page)
	auto_free(page)
	page.init(null)
	page._show(Weather.Kind.RAIN)
	var slider := _slider_after(page, "Fall speed")
	assert_object(slider).override_failure_message("the page drew no Fall speed slider").is_not_null()
	var target := was + 3.0
	slider.value = target
	await await_idle_frame()
	await await_idle_frame()
	var landed := WeatherLook.for_kind(Weather.Kind.RAIN).fall_speed
	look.fall_speed = was
	assert_float(landed).override_failure_message("the slider moved and the look did not").is_equal_approx(target, 0.01)
	assert_bool(page.has_unsaved_changes()).override_failure_message("an edit left Save unmarked").is_true()


# The slider in the row whose label reads `label`.
func _slider_after(root: Node, label: String) -> Range:
	for node in root.find_children("*", "Label", true, false):
		if (node as Label).text != label:
			continue
		for sibling in node.get_parent().get_children():
			if sibling is HSlider:
				return sibling
	return null


# A look draws only the rows of what it drops (#1269): a snow page lists no splashes, a rain page no
# swirl, a fog page (#1285) neither and no fall speed, an aurora page (#1298) its curtains and the storm's
# strike rows, a sand page (#1302) the flake, cover, drift, grit and fog rows, an ash page the flake,
# cover, cap, drift and mote rows, and all list the shared ones. Asked of the built page, not of the table.
func test_a_page_lists_only_its_falls_rows() -> void:
	var pages := {
		WeatherLook.Fall.SNOW: _label_texts(Weather.Kind.SNOW),
		WeatherLook.Fall.RAIN: _label_texts(Weather.Kind.RAIN),
		WeatherLook.Fall.FOG: _label_texts(Weather.Kind.FOG),
		WeatherLook.Fall.AURORA: _label_texts(Weather.Kind.AURORA),
		WeatherLook.Fall.SAND: _label_texts(Weather.Kind.SANDSTORM),
		WeatherLook.Fall.ASH: _label_texts(Weather.Kind.ASHFALL),
	}
	for kind: Weather.Kind in [Weather.Kind.SNOW, Weather.Kind.FOG, Weather.Kind.AURORA, Weather.Kind.SANDSTORM,
			Weather.Kind.ASHFALL]:
		assert_object(WeatherLook.for_kind(kind)).override_failure_message(
				"fixture: %s has no look file" % Weather.name_of(kind)).is_not_null()
	for row: Dictionary in WeatherLook.ROWS:
		var label: String = row["label"]
		for fall: WeatherLook.Fall in pages:
			var shown: bool = not row.has("fall") or (row["fall"] is Array and (row["fall"] as Array).has(fall)) \
					or (row["fall"] is int and row["fall"] == fall)
			assert_bool((pages[fall] as Array[String]).has(label)).override_failure_message(
					"%s page, row '%s'" % [WeatherLook.Fall.keys()[fall], label]).is_equal(shown)


# Every fall is one the Draws as row offers, in order (#1302): its options are a literal, and a picked
# index is stored as the fall, so a fall added without its option would be unpickable on the page.
func test_the_draws_as_row_offers_every_fall_in_order() -> void:
	var names: Array = []
	for key: String in WeatherLook.Fall.keys():
		names.append(key.capitalize())
	assert_array(WeatherLook.ROWS[0]["options"]).is_equal(names)
	assert_str(WeatherLook.ROWS[0]["prop"]).is_equal("fall")


# The bolt colour's picker lists Elemental.Element's members in order (#1298): its options are a literal
# a const table can hold, and a picked index is stored as the element, so the two must not drift apart.
func test_the_bolt_colour_picker_lists_every_element_in_order() -> void:
	var names: Array = []
	for key: String in Elemental.Element.keys():
		names.append(key.capitalize())
	assert_array(WeatherLook.ELEMENT_NAMES).is_equal(names)


func _label_texts(kind: Weather.Kind) -> Array[String]:
	var page := WeatherTool.new()
	add_child(page)
	page.init(null)
	page._show(kind)
	var texts: Array[String] = []
	for node in page.find_children("*", "Control", true, false):
		if node is Label:
			texts.append((node as Label).text)
		elif node is Button:   # a checkbox row carries its label as its own text
			texts.append((node as Button).text)
	page.free()
	return texts


# The wind's strengths are on the page too (#1286), each look's every field one row, the weather's law.
func test_every_wind_look_field_has_one_row_and_every_row_a_field() -> void:
	var fields := _exported(WindLook.new())
	var rows: Array[String] = []
	for row: Dictionary in WindLook.ROWS:
		rows.append(row["prop"])
		assert_bool(fields.has(row["prop"])).override_failure_message(
				"wind row '%s' names no field" % row["prop"]).is_true()
		assert_str(row.get("tip", "")).override_failure_message("wind row '%s' has no tooltip" % row["prop"]).is_not_empty()
	for field in fields:
		assert_int(rows.count(field)).override_failure_message(
				"wind field '%s' has %d rows on the Weather page" % [field, rows.count(field)]).is_equal(1)


# Every strength but calm has a look file and a picker entry, and its slider moves the look the board
# blows with.
func test_a_wind_slider_moves_the_look_the_board_blows_with() -> void:
	for kind: Wind.Kind in Wind.Kind.values():
		if kind != Wind.Kind.CALM:
			assert_object(WindLook.for_kind(kind)).override_failure_message(
					"Wind.Kind.%s has no look file" % Wind.name_of(kind)).is_not_null()
	var look := WindLook.for_kind(Wind.Kind.GALE)
	var was := look.speed
	var page := WeatherTool.new()
	add_child(page)
	auto_free(page)
	page.init(null)
	page._show_wind(Wind.Kind.GALE)
	assert_str(page._picker.get_item_text(page._picker.selected)).is_equal("Wind: Gale")
	var slider := _slider_after(page, "Wind speed")
	assert_object(slider).override_failure_message("the page drew no Wind speed slider").is_not_null()
	var target := was + 1.0
	slider.value = target
	await await_idle_frame()
	await await_idle_frame()
	var landed := WindLook.for_kind(Wind.Kind.GALE).speed
	look.speed = was
	assert_float(landed).override_failure_message("the slider moved and the wind did not").is_equal_approx(target, 0.01)
	assert_bool(page.has_unsaved_changes()).override_failure_message("an edit left Save unmarked").is_true()
