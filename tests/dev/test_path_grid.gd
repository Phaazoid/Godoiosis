# The stamp grid's Paths mode (#1056): a single-target swing authored as an ordered path of tiles.
#
# What is worth pinning is what a glance at the panel cannot confirm: that a path is stored in the
# order it was CLICKED (the stamp beside it sorts, and a path must not), that a tile may be visited
# twice, that a path tile is always a stamp tile in both directions, and that the pair of fields is
# never announced half-written. Every case builds its own shape (tests never read authored content).
# Whether the grid LOOKS right is not something a headless suite can see; the PR says so.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const SAVE_PATH := "user://__test_path_shape.tres"

var _box: VBoxContainer


func before_test() -> void:
	_box = VBoxContainer.new()
	add_child(_box)


func after_test() -> void:
	remove_child(_box)
	_box.free()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


# The grid exactly as the Attack Editor draws it: the shape's stamp, captioned by the attack, with
# the two path fields named.
func _draw(shape: AttackShape) -> AttackShape:
	var attack := WeaponAttackData.new()
	attack.attack_shape = shape
	DevWidgets.add_cell_grid(_box, "Stamp", shape, "stamp", attack, "path_cells", "path_lengths")
	return shape


func _grid() -> GridContainer:
	return _first(_box, "GridContainer") as GridContainer


func _picker() -> OptionButton:
	return _first(_box, "OptionButton") as OptionButton


func _first(node: Node, klass: String) -> Node:
	for child in node.get_children():
		if child.is_class(klass):
			return child
		var deeper := _first(child, klass)
		if deeper != null:
			return deeper
	return null


func _button(text: String) -> Button:
	return _button_in(_box, text)


func _button_in(node: Node, text: String) -> Button:
	for child in node.get_children():
		var button := child as Button
		if button != null and button.text == text:
			return button
		var deeper := _button_in(child, text)
		if deeper != null:
			return deeper
	return null


func _cell(offset: Vector2i) -> Button:
	var grid := _grid()
	var half := (grid.columns - 1) / 2
	return grid.get_child((offset.y + half) * grid.columns + (offset.x + half)) as Button


# A click, the way a player makes one: it FLIPS the toggle, and the widget decides what that means.
func _click(offset: Vector2i) -> void:
	var cell := _cell(offset)
	cell.button_pressed = not cell.button_pressed


func _paths_mode() -> void:
	_button("Paths").button_pressed = true


func _stamp_mode() -> void:
	_button("Stamp").button_pressed = true


# --- a path is written in CLICK order ----------------------------------------------------------

func test_the_first_click_in_paths_mode_starts_path_one_on_that_tile() -> void:
	var shape := _draw(P.shape([Vector2i(0, -1), Vector2i(0, -2)] as Array[Vector2i]))
	_paths_mode()
	_click(Vector2i(0, -1))
	assert_int(shape.path_count()).is_equal(1)
	assert_array(shape.path_at(0)).contains_exactly([Vector2i(0, -1)])


func test_the_path_is_stored_in_click_order_and_never_sorted() -> void:
	# The stamp beside it sorts to reading order so its .tres stays stable. A path must not: its
	# order IS what it says. Reading order here would be (0,-2), (0,-1), (1,-1).
	var shape := _draw(P.shape([] as Array[Vector2i]))
	_paths_mode()
	_click(Vector2i(0, -1))
	_click(Vector2i(0, -2))
	_click(Vector2i(1, -1))
	assert_array(shape.path_at(0)).override_failure_message(
		"the path was reordered -- the swing would hit its tiles in an order nobody drew"
	).contains_exactly([Vector2i(0, -1), Vector2i(0, -2), Vector2i(1, -1)])


func test_a_tile_may_be_visited_twice() -> void:
	# Dev ruling, 2026-09-22.
	var shape := _draw(P.shape([] as Array[Vector2i]))
	_paths_mode()
	_click(Vector2i(0, -1))
	_click(Vector2i(0, -2))
	_click(Vector2i(0, -1))
	assert_array(shape.path_at(0)).contains_exactly([Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -1)])
	assert_int(shape.stamp.count(Vector2i(0, -1))).override_failure_message(
		"a revisit painted the tile into the stamp twice").is_equal(1)


func test_a_path_click_paints_an_empty_tile_into_the_stamp() -> void:
	var shape := _draw(P.shape([Vector2i(0, -1)] as Array[Vector2i]))
	_paths_mode()
	_click(Vector2i(1, -1))
	assert_array(shape.stamp).contains([Vector2i(1, -1)])
	assert_bool(_cell(Vector2i(1, -1)).button_pressed).override_failure_message(
		"the tile joined the stamp but its cell does not show as filled").is_true()


func test_a_path_click_on_a_painted_tile_leaves_it_painted() -> void:
	# The click flips the toggle off; in Paths mode that must not reach the stamp.
	var shape := _draw(P.shape([Vector2i(0, -1)] as Array[Vector2i]))
	_paths_mode()
	_click(Vector2i(0, -1))
	assert_array(shape.stamp).contains([Vector2i(0, -1)])
	assert_bool(_cell(Vector2i(0, -1)).button_pressed).is_true()


# --- more than one path -------------------------------------------------------------------------

func test_new_path_starts_a_second_swing() -> void:
	var shape := _draw(P.shape([] as Array[Vector2i]))
	_paths_mode()
	_click(Vector2i(0, -1))
	_button("+ New path").pressed.emit()
	_click(Vector2i(1, -1))
	_click(Vector2i(1, -2))
	assert_int(shape.path_count()).is_equal(2)
	assert_array(shape.path_at(0)).contains_exactly([Vector2i(0, -1)])
	assert_array(shape.path_at(1)).contains_exactly([Vector2i(1, -1), Vector2i(1, -2)])


func test_a_new_path_is_not_stored_until_its_first_tile() -> void:
	# An empty path is a malformed pair (path_fault), so the pending row lives in the widget only.
	var shape := _draw(P.shape([] as Array[Vector2i]))
	_paths_mode()
	_click(Vector2i(0, -1))
	_button("+ New path").pressed.emit()
	assert_int(shape.path_count()).is_equal(1)
	assert_str(shape.path_fault()).is_equal("")


func test_picking_a_path_sends_the_next_click_to_it() -> void:
	var shape := _draw(P.pathed([Vector2i(0, -1), Vector2i(1, -1)] as Array[Vector2i],
		[[Vector2i(0, -1)] as Array[Vector2i], [Vector2i(1, -1)] as Array[Vector2i]] as Array[Array]))
	_paths_mode()
	_picker().item_selected.emit(1)
	_click(Vector2i(1, -2))
	assert_array(shape.path_at(0)).contains_exactly([Vector2i(0, -1)])
	assert_array(shape.path_at(1)).contains_exactly([Vector2i(1, -1), Vector2i(1, -2)])


func test_undo_step_pops_the_last_tile() -> void:
	var shape := _draw(P.shape([] as Array[Vector2i]))
	_paths_mode()
	_click(Vector2i(0, -1))
	_click(Vector2i(0, -2))
	_button("Undo step").pressed.emit()
	assert_array(shape.path_at(0)).contains_exactly([Vector2i(0, -1)])
	assert_array(shape.stamp).override_failure_message(
		"undoing a step un-painted the tile -- it is still one of the shape's tiles").contains([Vector2i(0, -2)])


func test_undoing_the_only_tile_removes_the_path() -> void:
	var shape := _draw(P.shape([] as Array[Vector2i]))
	_paths_mode()
	_click(Vector2i(0, -1))
	_button("Undo step").pressed.emit()
	assert_int(shape.path_count()).is_equal(0)
	assert_str(shape.path_fault()).is_equal("")


func test_delete_path_removes_the_selected_path_only() -> void:
	var shape := _draw(P.pathed([Vector2i(0, -1), Vector2i(1, -1)] as Array[Vector2i],
		[[Vector2i(0, -1)] as Array[Vector2i], [Vector2i(1, -1)] as Array[Vector2i]] as Array[Array]))
	_paths_mode()
	_picker().item_selected.emit(0)
	_button("Delete path").pressed.emit()
	assert_int(shape.path_count()).is_equal(1)
	assert_array(shape.path_at(0)).contains_exactly([Vector2i(1, -1)])


# --- a path tile is always a stamp tile ---------------------------------------------------------

func test_unpainting_a_tile_takes_it_out_of_every_path() -> void:
	var shape := _draw(P.pathed([Vector2i(0, -1), Vector2i(0, -2)] as Array[Vector2i], [
		[Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -1)] as Array[Vector2i],
		[Vector2i(0, -2)] as Array[Vector2i],
	] as Array[Array]))
	_click(Vector2i(0, -2))   # Stamp mode: un-paint
	assert_array(shape.stamp).not_contains([Vector2i(0, -2)])
	assert_int(shape.path_count()).override_failure_message(
		"a path left with no tiles survived the un-paint").is_equal(1)
	assert_array(shape.path_at(0)).override_failure_message(
		"the un-painted tile is still on a path, so the shape now points outside itself"
	).contains_exactly([Vector2i(0, -1), Vector2i(0, -1)])
	assert_str(shape.path_fault()).is_equal("")


func test_the_coordinate_line_is_read_only_while_paths_exist() -> void:
	# It applies per keystroke, and a half-typed pair passes through "0,-" on its way to "0,-2":
	# with paths present that transient un-paint would drop their visits for good.
	_draw(P.shape([] as Array[Vector2i]))
	var line := _first(_box, "LineEdit") as LineEdit
	assert_bool(line.editable).is_true()
	_paths_mode()
	_click(Vector2i(0, -1))
	assert_bool(line.editable).is_false()
	_button("Undo step").pressed.emit()
	assert_bool(line.editable).is_true()


# --- the pair is never half-written -------------------------------------------------------------

func test_every_announcement_sees_a_sound_pair() -> void:
	# A listener on `changed` reads both fields. Two separate writes would fire it between them,
	# and it would read cells that its lengths do not describe.
	var shape := _draw(P.shape([] as Array[Vector2i]))
	var faults: Array[String] = []
	shape.changed.connect(func() -> void:
		faults.append(shape.path_fault()))
	_paths_mode()
	_click(Vector2i(0, -1))
	_click(Vector2i(1, -2))
	_button("+ New path").pressed.emit()
	_click(Vector2i(0, -2))
	_button("Undo step").pressed.emit()
	_stamp_mode()
	_click(Vector2i(0, -1))
	assert_int(faults.size()).is_greater(0)
	for fault in faults:
		assert_str(fault).override_failure_message(
			"a listener was told about a half-written path pair: %s" % fault).is_equal("")


# --- what the grid shows -------------------------------------------------------------------------

func test_a_tile_shows_its_steps_on_the_selected_path() -> void:
	_draw(P.pathed([Vector2i(0, -1), Vector2i(0, -2)] as Array[Vector2i],
		[[Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -1)] as Array[Vector2i]] as Array[Array]))
	_paths_mode()
	assert_str(_cell(Vector2i(0, -1)).text).is_equal("1,3")
	assert_str(_cell(Vector2i(0, -2)).text).is_equal("2")
	_stamp_mode()
	assert_str(_cell(Vector2i(0, -1)).text).override_failure_message(
		"Stamp mode still shows path steps").is_equal("")


func test_a_tile_only_another_path_visits_shows_a_dot() -> void:
	_draw(P.pathed([Vector2i(0, -1), Vector2i(1, -1)] as Array[Vector2i],
		[[Vector2i(0, -1)] as Array[Vector2i], [Vector2i(1, -1)] as Array[Vector2i]] as Array[Array]))
	_paths_mode()
	_picker().item_selected.emit(0)
	assert_str(_cell(Vector2i(0, -1)).text).is_equal("1")
	assert_str(_cell(Vector2i(1, -1)).text).is_equal(".")


func test_the_tooltip_names_every_visit() -> void:
	_draw(P.pathed([Vector2i(0, -1)] as Array[Vector2i], [
		[Vector2i(0, -1)] as Array[Vector2i],
		[Vector2i(0, -1), Vector2i(0, -1)] as Array[Vector2i],
	] as Array[Array]))
	_paths_mode()
	var tip := _cell(Vector2i(0, -1)).tooltip_text
	assert_str(tip).contains("Path 1: step 1")
	assert_str(tip).contains("Path 2: step 1, 2")


func test_the_path_controls_keep_their_own_tip_inside_a_tipped_row() -> void:
	# The Attack Editor tips every row the grid adds with the SHAPE's tip, afterwards. The path
	# controls must keep the path field's own text, or hovering them explains the wrong thing.
	_draw(P.shape([] as Array[Vector2i]))
	DevWidgets._tip_rows_from(_box, 0, "THE SHAPE ROW'S TIP")
	var paths := _button("Paths")
	assert_str(paths.tooltip_text).is_not_equal("THE SHAPE ROW'S TIP")
	assert_str(paths.tooltip_text).is_equal(DevWidgets.property_tip(AttackShape.new(), "path_cells"))
	assert_str(_cell(Vector2i.ZERO).tooltip_text).override_failure_message(
		"the opt-out leaked: an ordinary cell lost the row's tip").is_equal("THE SHAPE ROW'S TIP")


func test_a_grid_drawn_without_the_path_fields_has_no_paths_mode() -> void:
	# The reflective editor draws any declared grid field with no path fields named, and must get
	# exactly the widget it always had.
	var attack := WeaponAttackData.new()
	attack.attack_shape = P.shape([Vector2i(0, -1)] as Array[Vector2i])
	DevWidgets.add_cell_grid(_box, "Stamp", attack.attack_shape, "stamp", attack)
	assert_object(_button("Paths")).is_null()
	assert_object(_picker()).is_null()


# --- it saves -------------------------------------------------------------------------------------

func test_a_shape_with_paths_saves_and_reloads_them() -> void:
	var shape := P.pathed([Vector2i(0, -1), Vector2i(0, -2)] as Array[Vector2i], [
		[Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -1)] as Array[Vector2i],
		[Vector2i(0, -2)] as Array[Vector2i],
	] as Array[Array])
	assert_bool(DevWidgets.save_over(shape, SAVE_PATH, null)).is_true()
	var back := ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as AttackShape
	assert_int(back.path_count()).is_equal(2)
	assert_array(back.path_at(0)).contains_exactly([Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -1)])
	assert_array(back.path_at(1)).contains_exactly([Vector2i(0, -2)])


func test_a_shape_with_paths_resaves_byte_identical() -> void:
	# The writer's fixed point: a second save of an unchanged shape must not move a byte, or every
	# Update of a pathed shape hands the dev a modified file he did not edit.
	var shape := P.pathed([Vector2i(0, -1)] as Array[Vector2i],
		[[Vector2i(0, -1), Vector2i(0, -1)] as Array[Vector2i]] as Array[Array])
	assert_bool(DevWidgets.save_over(shape, SAVE_PATH, null)).is_true()
	var first := FileAccess.get_file_as_string(SAVE_PATH)
	assert_bool(DevWidgets.save_over(shape, SAVE_PATH, null)).is_true()
	assert_str(FileAccess.get_file_as_string(SAVE_PATH)).is_equal(first)
