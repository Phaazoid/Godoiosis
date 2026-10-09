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
# swirl, and both list the shared ones. Asked of the built page, not of the table.
func test_a_page_lists_only_its_falls_rows() -> void:
	var snow := _label_texts(Weather.Kind.SNOW)
	var rain := _label_texts(Weather.Kind.RAIN)
	assert_object(WeatherLook.for_kind(Weather.Kind.SNOW)).override_failure_message(
			"fixture: snow has no look file").is_not_null()
	for row: Dictionary in WeatherLook.ROWS:
		var label: String = row["label"]
		var on_snow: bool = not row.has("fall") or row["fall"] == WeatherLook.Fall.SNOW
		var on_rain: bool = not row.has("fall") or row["fall"] == WeatherLook.Fall.RAIN
		assert_bool(snow.has(label)).override_failure_message("snow page, row '%s'" % label).is_equal(on_snow)
		assert_bool(rain.has(label)).override_failure_message("rain page, row '%s'" % label).is_equal(on_rain)


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
