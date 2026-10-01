# The Experiments page (#382) draws a CHOICE flag (#508) as a dropdown, and picking from it writes the
# store. Driven through the OptionButton's own item_selected, the signal a click emits, so a row that
# draws but is wired to nothing goes red.
extends GdUnitTestSuite


func before_test() -> void:
	Experiments.reset_for_test()


func _option_for(tool: Node, title: String) -> OptionButton:
	for row in tool.get_children():
		var label := row.get_child(0) as Label if row.get_child_count() > 0 else null
		if label != null and label.text == title:
			return row.get_child(1) as OptionButton
	return null


func test_a_choice_flag_is_a_dropdown_that_writes_the_store() -> void:
	var tool := ExperimentsTool.new()
	add_child(tool)
	var flag := Experiments.Flag.GAS_STYLE
	var option := _option_for(tool, Experiments.title_of(flag))
	assert_object(option).override_failure_message("no dropdown row for %s" % Experiments.title_of(flag)).is_not_null()
	assert_int(option.item_count).is_equal(Experiments.options_of(flag).size())
	assert_int(option.selected).is_equal(Experiments.choice_of(flag))
	var pick := (Experiments.choice_of(flag) + 1) % Experiments.options_of(flag).size()
	option.select(pick)
	option.item_selected.emit(pick)
	assert_int(Experiments.choice_of(flag)).is_equal(pick)
	tool.free()
	await await_idle_frame()


func test_a_toggle_flag_stays_a_checkbox() -> void:
	var tool := ExperimentsTool.new()
	add_child(tool)
	var toggle := Experiments.Flag.GAS_OVER_UNITS
	assert_object(_option_for(tool, Experiments.title_of(toggle))).is_null()
	tool.free()
	await await_idle_frame()
