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


# The air a weather moves (#1324) gets a row per ambient substance, and dragging one moves the reading
# the board composes at once: the composition reads the very rules object this page edits.
func test_an_air_slider_moves_the_reading_the_board_composes() -> void:
	var sky := Weather.Kind.CLEAR
	for kind: Weather.Kind in Weather.Kind.values():
		if WeatherRules.for_kind(kind) != null:
			sky = kind
			break
	assert_int(sky).override_failure_message("fixture: no weather has a rules file").is_not_equal(Weather.Kind.CLEAR)
	var rules := WeatherRules.for_kind(sky)
	var was := rules.air.duplicate()
	var page := WeatherTool.new()
	add_child(page)
	auto_free(page)
	page.init(null)
	page._show(sky)
	var sliders := {}
	for id: String in Atmosphere.SUBSTANCES:
		var slider := _slider_after(page, "Air: " + SubstanceCatalog.name_of(id))
		assert_object(slider).override_failure_message("the page drew no air row for %s" % id).is_not_null()
		sliders[id] = slider
	var id: String = Atmosphere.SUBSTANCES[0]
	if sliders[id] == null:
		return
	var points := int(rules.air.get(id, 0)) + int(Atmosphere.STEP[id])
	(sliders[id] as Range).value = points
	await await_idle_frame()
	var none: Dictionary[String, int] = {}
	var landed := Atmosphere.percent_of(id, Atmosphere.effective(none, sky))
	rules.air = was
	assert_int(landed).override_failure_message("the air slider moved and the reading did not").is_equal(
			clampi(int(Atmosphere.NORMAL[id]) + points, 0, 100))
	assert_bool(page.has_unsaved_changes()).override_failure_message("an air edit left Save unmarked").is_true()


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


# The unsaved marker is per FILE (#1370): an edit lives on the cached look, so picking another weather
# or a wind must not clear it, and Save must name every file touched, not only the one on show. Nothing
# here writes to disk: the confirmation is read and never answered (test_unsaved_markers' discipline).
func test_an_edit_stays_marked_across_weathers_and_save_names_every_file() -> void:
	var snow := WeatherLook.for_kind(Weather.Kind.SNOW)
	var rain := WeatherLook.for_kind(Weather.Kind.RAIN)
	assert_bool(snow != null and rain != null).override_failure_message("fixture: rain or snow has no look file") \
			.is_true()
	var snow_was := snow.fall_speed
	var rain_was := rain.fall_speed
	var page := WeatherTool.new()
	add_child(page)
	auto_free(page)
	page.init(null)
	page._show(Weather.Kind.SNOW)
	_slider_after(page, "Fall speed").value = snow_was + 1.0
	page._show(Weather.Kind.RAIN)
	var kept := page.has_unsaved_changes() and page._save.text.ends_with("*")
	page._show_wind(Wind.Kind.GALE)
	var kept_on_wind := page.has_unsaved_changes()
	page._show(Weather.Kind.RAIN)
	_slider_after(page, "Fall speed").value = rain_was + 1.0
	var files := page.touched_files()
	page._on_save_pressed()
	var asked := ""
	for child in page.get_children():
		if child is ConfirmationDialog:
			asked = (child as ConfirmationDialog).dialog_text
			child.free()
	snow.fall_speed = snow_was
	rain.fall_speed = rain_was
	assert_bool(kept).override_failure_message("picking another weather cleared an unsaved snow edit").is_true()
	assert_bool(kept_on_wind).override_failure_message("picking a wind cleared an unsaved snow edit").is_true()
	assert_array(Array(files)).override_failure_message("touched: %s" % files).contains_exactly_in_any_order(
			[WeatherLook.path_of(Weather.Kind.SNOW), WeatherLook.path_of(Weather.Kind.RAIN)])
	for kind: Weather.Kind in [Weather.Kind.SNOW, Weather.Kind.RAIN]:
		assert_str(asked).override_failure_message("Save's confirmation leaves out %s:\n%s"
				% [Weather.name_of(kind), asked]).contains(WeatherLook.path_of(kind).trim_prefix("res://"))


# A rules edit re-resolves the open plan (#1370): its END OF TURN rows read the rules this page edits,
# as the Scenario page's weather picker already redraws them. Driven through the real Soaks with picker.
func test_a_soak_edit_redraws_the_open_plan() -> void:
	var sky := Weather.Kind.CLEAR
	for kind: Weather.Kind in Weather.Kind.values():
		if WeatherRules.for_kind(kind) != null:
			sky = kind
			break
	assert_int(sky).override_failure_message("fixture: no weather has a rules file").is_not_equal(Weather.Kind.CLEAR)
	var rules := WeatherRules.for_kind(sky)
	var was := rules.state
	var game := FakeGame.new()
	var page := WeatherTool.new()
	add_child(page)
	auto_free(page)
	page.init(game)
	page._show(sky)
	var picker := _option_after(page, "Soaks with")
	assert_object(picker).override_failure_message("the page drew no Soaks with picker").is_not_null()
	if picker == null:
		return
	var other := (int(was) + 1) % picker.item_count
	picker.select(other)
	picker.item_selected.emit(other)
	var landed := int(rules.state)
	rules.state = was
	assert_int(landed).override_failure_message("fixture: the picker did not write the rules").is_equal(other)
	assert_int(game.refreshed).override_failure_message("a soak edit left the open plan unresolved").is_greater(0)
	assert_bool(page.has_unsaved_changes()).override_failure_message("a soak edit left Save unmarked").is_true()


func _option_after(root: Node, label: String) -> OptionButton:
	for node in root.find_children("*", "Label", true, false):
		if (node as Label).text != label:
			continue
		for sibling in node.get_parent().get_children():
			if sibling is OptionButton:
				return sibling
	return null


# The two calls the page makes on game.gd after a rules write, counted.
class FakeGame:
	extends RefCounted
	var squad_manager := {"active_squad": null}
	var refreshed := 0

	func refresh_action_queue(_squad: Variant) -> void:
		refreshed += 1

	func refresh_mission_status() -> void:
		pass
