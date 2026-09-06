# The clickable stamp grid in the dev tools' reflective editor (#804).
#
# The grid is the one row that is not a single control, so what is worth pinning is the behaviour a
# glance at the panel cannot confirm: that the size DERIVES from the stamp rather than being stored,
# that shrinking refuses rather than dropping authored cells, that a click reaches the RESOURCE, and
# that the coordinate line and the grid stay two renders of one store.
#
# Everything here builds its own pattern (dev, 2026-09-06 -- tests never read authored content).
# What a headless suite cannot see is whether it LOOKS right; the PR says so out loud.
extends GdUnitTestSuite

const P := preload("res://tests/support/pattern_fixtures.gd")

var _box: VBoxContainer


func before_test() -> void:
	_box = VBoxContainer.new()
	add_child(_box)


func after_test() -> void:
	remove_child(_box)
	_box.free()


func _draw(pattern: AttackPattern) -> void:
	DevWidgets.build_resource_editor(_box, pattern, func(): pass)


func _grid() -> GridContainer:
	return _find(_box, "GridContainer") as GridContainer


func _find(node: Node, klass: String) -> Node:
	for child in node.get_children():
		if child.is_class(klass):
			return child
		var deeper := _find(child, klass)
		if deeper != null:
			return deeper
	return null


func _line() -> LineEdit:
	return _find(_box, "LineEdit") as LineEdit


# The cell at a stamp offset, by its position in the row-major grid.
func _cell(offset: Vector2i) -> Button:
	var grid := _grid()
	var half := (grid.columns - 1) / 2
	return grid.get_child((offset.y + half) * grid.columns + (offset.x + half)) as Button


func _label_row(text: String) -> Node:
	for label in _all_labels(_box, []):
		if (label as Label).text == text:
			return label.get_parent()
	return null


func _all_labels(node: Node, found: Array[Node]) -> Array[Node]:
	for child in node.get_children():
		if child is Label:
			found.append(child)
		_all_labels(child, found)
	return found


func _label_texts() -> PackedStringArray:
	var texts: PackedStringArray = []
	for label in _all_labels(_box, []):
		texts.append((label as Label).text)
	return texts


func _button_with(node: Node, text: String) -> Button:
	for child in node.get_children():
		var button := child as Button
		if button != null and button.text == text:
			return button
		var deeper := _button_with(child, text)
		if deeper != null:
			return deeper
	return null


# --- the size derives, and is the widget's own view ----------------------------------------

func test_the_grid_spans_the_stamp_plus_nothing_it_does_not_need() -> void:
	# A stamp reaching 3 forward needs 3 rings, so 7 across. Derived, never stored: nothing on the
	# pattern says 7.
	_draw(P.line(3))
	assert_int(_grid().columns).is_equal(7)


func test_a_small_stamp_still_gets_a_ring_to_click_into() -> void:
	# The centre alone would fit in 1x1, which would leave nowhere to author.
	_draw(P.point(2))
	assert_int(_grid().columns).is_equal(DevWidgets.GRID_MIN_SPAN)


func test_the_grid_is_always_odd_so_it_has_a_centre() -> void:
	for length in [1, 2, 3, 4, 5]:
		var box := VBoxContainer.new()
		add_child(box)
		DevWidgets.build_resource_editor(box, P.line(length), func(): pass)
		var grid := _find(box, "GridContainer") as GridContainer
		assert_int(grid.columns % 2).override_failure_message(
			"a %d-long line drew a %d-wide grid, which has no centre" % [length, grid.columns]).is_equal(1)
		remove_child(box)
		box.free()


func test_growing_walks_odd_sizes_and_stops_at_the_cap() -> void:
	_draw(P.point(2))
	var plus := _button_with(_box, "+")
	var span := _grid().columns
	while not plus.disabled:
		plus.emit_signal("pressed")
		assert_int(_grid().columns).is_equal(span + DevWidgets.GRID_STEP)
		span = _grid().columns
	assert_int(span).is_equal(DevWidgets.GRID_MAX_SPAN)


func test_shrinking_below_an_occupied_cell_is_refused() -> void:
	# A 3-long line needs all 7 columns. Minus must be dead rather than dropping the far cell.
	_draw(P.line(3))
	var minus := _button_with(_box, "-")
	assert_bool(minus.disabled).override_failure_message(
		"minus was live on a grid that is exactly as wide as its stamp").is_true()
	assert_int(_grid().columns).is_equal(7)


func test_a_grid_grown_past_its_stamp_can_shrink_back() -> void:
	_draw(P.line(1))
	var plus := _button_with(_box, "+")
	var minus := _button_with(_box, "-")
	var grown := _grid().columns
	plus.emit_signal("pressed")
	assert_int(_grid().columns).is_equal(grown + DevWidgets.GRID_STEP)
	assert_bool(minus.disabled).is_false()
	minus.emit_signal("pressed")
	assert_int(_grid().columns).is_equal(grown)


# --- a click reaches the resource ------------------------------------------------------------

func test_clicking_an_empty_cell_writes_it_through_to_the_resource() -> void:
	var pattern := P.point(2)
	_draw(pattern)
	_cell(Vector2i(1, -1)).button_pressed = true
	assert_array(pattern.stamp).contains([Vector2i(1, -1)])


func test_clicking_a_filled_cell_clears_it() -> void:
	var pattern := P.line(1)   # one cell, at 0,-1
	_draw(pattern)
	assert_bool(_cell(Vector2i(0, -1)).button_pressed).is_true()
	_cell(Vector2i(0, -1)).button_pressed = false
	assert_array(pattern.stamp).is_empty()


func test_the_centre_is_authorable_like_any_other_cell() -> void:
	# Ruling 4: the attacker's own cell may be in the blast.
	var pattern := P.line(1)
	_draw(pattern)
	_cell(Vector2i.ZERO).button_pressed = true
	assert_array(pattern.stamp).contains([Vector2i.ZERO])


func test_the_stored_order_is_reading_order_whatever_order_cells_were_clicked() -> void:
	# So the .tres a save writes is stable rather than following the gesture.
	var pattern := P.stamped(0, [])
	_draw(pattern)
	_cell(Vector2i(1, 1)).button_pressed = true
	_cell(Vector2i(-1, -1)).button_pressed = true
	_cell(Vector2i(1, -1)).button_pressed = true
	assert_array(pattern.stamp).contains_exactly([Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1)])


# --- the centre reads as the centre ----------------------------------------------------------

func test_the_centre_is_marked_whether_filled_or_not() -> void:
	var pattern := P.line(1)
	_draw(pattern)
	var centre := _cell(Vector2i.ZERO)
	var plain := _cell(Vector2i(1, 0))
	var empty_centre_edge: int = (centre.get_theme_stylebox("normal") as StyleBoxFlat).border_width_left
	var plain_edge: int = (plain.get_theme_stylebox("normal") as StyleBoxFlat).border_width_left
	assert_int(empty_centre_edge).override_failure_message(
		"an unfilled centre is indistinguishable from an ordinary empty cell").is_greater(plain_edge)
	centre.button_pressed = true
	var filled_centre_edge: int = (centre.get_theme_stylebox("normal") as StyleBoxFlat).border_width_left
	assert_int(filled_centre_edge).override_failure_message(
		"a filled centre lost its marking").is_equal(empty_centre_edge)


func test_a_filled_cell_looks_different_from_an_empty_one() -> void:
	var pattern := P.line(1)
	_draw(pattern)
	var filled: Color = (_cell(Vector2i(0, -1)).get_theme_stylebox("normal") as StyleBoxFlat).bg_color
	var empty: Color = (_cell(Vector2i(1, 0)).get_theme_stylebox("normal") as StyleBoxFlat).bg_color
	assert_bool(filled == empty).override_failure_message(
		"filled and empty cells paint the same colour").is_false()


func test_the_cells_are_out_of_the_focus_chain() -> void:
	# A 15x15 grid is 225 tab stops between two spinboxes.
	_draw(P.line(2))
	for child in _grid().get_children():
		assert_int((child as Button).focus_mode).is_equal(Control.FOCUS_NONE)


# --- the coordinate line and the grid are two renders of one store ---------------------------

func test_the_coordinate_line_follows_a_click() -> void:
	var pattern := P.stamped(0, [])
	_draw(pattern)
	_cell(Vector2i(0, -1)).button_pressed = true
	assert_str(_line().text).is_equal("0,-1")


func test_typing_in_the_line_fills_the_grid() -> void:
	var pattern := P.stamped(0, [])
	_draw(pattern)
	_line().text = "0,-1 1,-1"
	_line().emit_signal("text_changed", _line().text)
	assert_array(pattern.stamp).contains_exactly_in_any_order([Vector2i(0, -1), Vector2i(1, -1)])
	assert_bool(_cell(Vector2i(0, -1)).button_pressed).is_true()
	assert_bool(_cell(Vector2i(1, -1)).button_pressed).is_true()


func test_typing_never_shrinks_the_grid_mid_edit() -> void:
	# Deleting a digit briefly parses to a smaller stamp; a grid that re-derived would collapse and
	# re-expand on the next keystroke.
	_draw(P.line(3))
	assert_int(_grid().columns).is_equal(7)
	_line().emit_signal("text_changed", "0,-1")
	assert_int(_grid().columns).is_equal(7)


# --- the caption names the anchor, live ------------------------------------------------------

func test_the_caption_follows_the_anchor() -> void:
	# The pattern answers what its own centre means, and the caption tracks max_range through the
	# editor's own write path -- the wire, not the string.
	var pattern := P.line(2)   # max_range 0: self-anchored
	_draw(pattern)
	assert_array(_label_texts()).contains([pattern.grid_caption("stamp")])
	var self_anchored := pattern.grid_caption("stamp")

	var row := _label_row("Max Range")
	var spin := row.get_child(1) as SpinBox
	spin.value = 2

	assert_str(pattern.grid_caption("stamp")).is_not_equal(self_anchored)
	assert_array(_label_texts()).override_failure_message(
		"the caption still claims the centre is the attacker after the range moved off 0").contains(
		[pattern.grid_caption("stamp")])


# --- only a DECLARED stamp gets a grid -------------------------------------------------------

func test_an_undeclared_cell_array_is_not_given_a_centred_grid() -> void:
	# ScenarioUnitEntry.watch_cells is an Array[Vector2i] of ABSOLUTE board cells. A grid centred on
	# 0,0 would be a lie about it, so the declaration is what opts a field in -- never the type.
	var pattern := AttackPattern.new()
	assert_bool(DevWidgets._is_grid_field(pattern, "stamp")).is_true()
	assert_bool(DevWidgets._is_grid_field(pattern, "max_range")).is_false()
	assert_bool(DevWidgets._is_grid_field(ScenarioUnitEntry.new(), "watch_cells")).override_failure_message(
		"an absolute-cell array was offered a centred grid").is_false()


func test_a_typed_arrays_element_is_reported_as_a_type_id_not_a_class_name() -> void:
	# The #803 bug this ticket found: get_property_list reports Array[Vector2i] as "6:", so a
	# comparison against "Vector2i" matched nothing and the coordinate row never drew. Asked of the
	# real property dictionaries, so the next engine renaming the hint reds here rather than in play.
	assert_bool(_is_cell_array(AttackPattern.new(), "stamp")).override_failure_message(
		"the stamp is not recognised as a cell array -- its row will not draw at all").is_true()
	assert_bool(_is_cell_array(ScenarioUnitEntry.new(), "watch_cells")).is_true()
	assert_bool(_is_cell_array(AttackPattern.new(), "max_range")).is_false()


func _is_cell_array(resource: Resource, prop_name: String) -> bool:
	for prop in resource.get_property_list():
		if prop.name == prop_name:
			return DevWidgets._is_cell_array(prop)
	return false
