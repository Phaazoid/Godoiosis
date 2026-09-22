# The shape grid's two kinds (#1056, #1079): a shape is painted tiles OR paths, and in Paths mode a
# single-target swing is authored as arrows from tile to tile.
#
# What is worth pinning is what a glance at the panel cannot confirm: which mode the data opens in,
# that switching kind asks first and clears only on Yes, that a path is stored in the order it was
# CLICKED, that a tile may be revisited but never twice in a row, that a path click paints nothing,
# and that the path pair is never announced half-written. The arrows are asserted through
# PathArrows.segments() and centres(), never pixels. Every case builds its own shape (tests never
# read authored content). Whether the arrows LOOK right is not something a headless suite can see;
# the PR says so.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const SAVE_PATH := "user://__test_path_shape.tres"

const A := Vector2i(0, -1)
const B := Vector2i(0, -2)
const C := Vector2i(1, -1)

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


func _paths(list: Array) -> Array[Array]:
	var out: Array[Array] = []
	for path: Array in list:
		var typed: Array[Vector2i] = []
		typed.assign(path)
		out.append(typed)
	return out


func _grid() -> GridContainer:
	return _first(_box, "GridContainer") as GridContainer


func _picker() -> OptionButton:
	return _first(_box, "OptionButton") as OptionButton


func _line_row() -> Control:
	return _first(_box, "LineEdit").get_parent() as Control


func _arrows() -> PathArrows:
	for node in _box.find_children("*", "", true, false):
		if node is PathArrows:
			return node
	return null


func _dialogs() -> Array[ConfirmationDialog]:
	var out: Array[ConfirmationDialog] = []
	for node in _box.find_children("*", "ConfirmationDialog", true, false):
		var dialog := node as ConfirmationDialog
		if dialog.visible:
			out.append(dialog)
	return out


# Answers the question the last switch asked, the way the player would.
func _answer(yes: bool) -> void:
	var open := _dialogs()
	assert_int(open.size()).override_failure_message("no question was asked to answer").is_equal(1)
	if yes:
		open[0].confirmed.emit()
	open[0].hide()


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


func _lit(offset: Vector2i) -> bool:
	return _cell(offset).button_pressed


# A click, the way a player makes one: it FLIPS the toggle, and the widget decides what that means.
func _click(offset: Vector2i) -> void:
	var cell := _cell(offset)
	cell.button_pressed = not cell.button_pressed


func _press_paths() -> void:
	_button("Paths").button_pressed = true


func _press_stamp() -> void:
	_button("Stamp").button_pressed = true


func _showing_paths() -> bool:
	return _button("Paths").button_pressed and not _button("Stamp").button_pressed


func _showing_stamp() -> bool:
	return _button("Stamp").button_pressed and not _button("Paths").button_pressed


# --- the mode is read from the data -------------------------------------------------------------

func test_a_painted_shape_opens_in_stamp_mode() -> void:
	_draw(P.shape([A] as Array[Vector2i]))
	assert_bool(_showing_stamp()).is_true()
	assert_bool(_picker().get_parent().visible).override_failure_message(
		"the path row shows over a painted shape").is_false()
	assert_bool(_line_row().visible).is_true()
	assert_bool(_arrows().visible).is_false()


func test_a_path_shape_opens_in_paths_mode() -> void:
	_draw(P.pathed(_paths([[A, B]])))
	assert_bool(_showing_paths()).override_failure_message(
		"a shape with paths opened in Stamp mode -- its arrows are hidden until the toggle is found").is_true()
	assert_bool(_picker().get_parent().visible).is_true()
	assert_bool(_line_row().visible).override_failure_message(
		"the Cells line shows over a path shape, which has no painted tiles to type").is_false()
	assert_bool(_arrows().visible).is_true()


# --- switching kind asks first ----------------------------------------------------------------------

func test_switching_a_painted_shape_to_paths_asks_and_no_changes_nothing() -> void:
	var shape := _draw(P.shape([A, C] as Array[Vector2i]))
	_press_paths()
	assert_int(_dialogs().size()).is_equal(1)
	assert_str(_dialogs()[0].dialog_text).contains("2 painted tiles")
	assert_bool(_showing_stamp()).override_failure_message(
		"the toggle moved before the question was answered").is_true()
	_answer(false)
	assert_array(shape.stamp).override_failure_message(
		"answering No cleared the painted tiles").contains_exactly([A, C])
	assert_bool(_showing_stamp()).is_true()
	_click(C)   # still Stamp mode: the click un-paints
	assert_array(shape.stamp).contains_exactly([A])


func test_yes_clears_the_painted_tiles_and_opens_paths() -> void:
	var shape := _draw(P.shape([A, C] as Array[Vector2i]))
	_press_paths()
	_answer(true)
	assert_array(shape.stamp).is_empty()
	assert_bool(_showing_paths()).is_true()
	assert_bool(_lit(A)).is_false()
	assert_bool(_lit(C)).is_false()
	_click(A)
	assert_array(shape.path_at(0)).contains_exactly([A])


func test_switching_a_path_shape_to_stamp_asks_and_no_changes_nothing() -> void:
	var shape := _draw(P.pathed(_paths([[A, B], [C]])))
	_press_stamp()
	assert_str(_dialogs()[0].dialog_text).contains("2 paths")
	_answer(false)
	assert_int(shape.path_count()).override_failure_message(
		"answering No cleared the paths").is_equal(2)
	assert_bool(_showing_paths()).is_true()


func test_yes_clears_every_path_and_starts_the_stamp_empty() -> void:
	var shape := _draw(P.pathed(_paths([[A, B], [C]])))
	_press_stamp()
	_answer(true)
	assert_bool(shape.is_path_shape()).is_false()
	assert_array(shape.path_cells).is_empty()
	assert_array(shape.stamp).is_empty()
	assert_bool(_showing_stamp()).is_true()
	assert_bool(_line_row().visible).is_true()
	assert_bool(_arrows().visible).is_false()


func test_an_empty_shape_switches_without_asking() -> void:
	_draw(P.shape([] as Array[Vector2i]))
	_press_paths()
	assert_int(_dialogs().size()).is_equal(0)
	assert_bool(_showing_paths()).is_true()
	assert_bool(_line_row().visible).is_false()
	_press_stamp()
	assert_int(_dialogs().size()).is_equal(0)
	assert_bool(_showing_stamp()).is_true()
	assert_bool(_line_row().visible).is_true()


func test_a_conversion_announces_once() -> void:
	var shape := _draw(P.pathed(_paths([[A, B], [C]])))
	var heard: Array[String] = []
	shape.changed.connect(func() -> void:
		heard.append(shape.path_fault()))
	_press_stamp()
	_answer(true)
	assert_int(heard.size()).is_equal(1)
	assert_str(heard[0]).is_equal("")


# --- a path is written in CLICK order, and paints nothing ------------------------------------------

func test_a_click_starts_a_path_and_paints_nothing() -> void:
	var shape := _draw(P.shape([] as Array[Vector2i]))
	_press_paths()
	_click(A)
	assert_int(shape.path_count()).is_equal(1)
	assert_array(shape.path_at(0)).contains_exactly([A])
	assert_array(shape.stamp).override_failure_message(
		"a path click painted the tile -- a shape is painted tiles or paths, never both").is_empty()
	assert_bool(_lit(A)).is_true()
	assert_bool(_lit(B)).is_false()


func test_the_path_is_stored_in_click_order_and_never_sorted() -> void:
	# Reading order here would be (0,-2), (0,-1), (1,-1). A path's order IS what it says.
	var shape := _draw(P.shape([] as Array[Vector2i]))
	_press_paths()
	_click(A)
	_click(B)
	_click(C)
	assert_array(shape.path_at(0)).override_failure_message(
		"the path was reordered -- the swing would hit its tiles in an order nobody drew"
	).contains_exactly([A, B, C])


func test_a_tile_may_be_revisited() -> void:
	# Dev ruling, 2026-09-22. The third click lands on a lit tile and flips its toggle off; it must
	# still read as lit afterwards, since it is still one of the shape's tiles.
	var shape := _draw(P.shape([] as Array[Vector2i]))
	_press_paths()
	_click(A)
	_click(B)
	_click(A)
	assert_array(shape.path_at(0)).contains_exactly([A, B, A])
	assert_bool(_lit(A)).is_true()


func test_clicking_the_tile_just_visited_does_nothing() -> void:
	# Dev ruling, 2026-09-22: "it does not make sense to visit the same tile twice in a row".
	var shape := _draw(P.shape([] as Array[Vector2i]))
	_press_paths()
	_click(A)
	var heard := [0]
	shape.changed.connect(func() -> void:
		heard[0] += 1)
	_click(A)
	assert_array(shape.path_at(0)).override_failure_message(
		"a repeat click was stored -- the path now visits one tile twice in a row").contains_exactly([A])
	assert_int(heard[0]).is_equal(0)
	assert_bool(_lit(A)).is_true()


# --- more than one path ----------------------------------------------------------------------------

func test_new_path_starts_a_second_swing() -> void:
	var shape := _draw(P.shape([] as Array[Vector2i]))
	_press_paths()
	_click(A)
	_button("+ New path").pressed.emit()
	_click(C)
	_click(B)
	assert_int(shape.path_count()).is_equal(2)
	assert_array(shape.path_at(0)).contains_exactly([A])
	assert_array(shape.path_at(1)).contains_exactly([C, B])


func test_a_new_path_may_start_on_the_tile_the_last_one_ended_on() -> void:
	# The twice-in-a-row rule is per PATH: a second swing starting where the first stopped is two
	# swings, not one path standing still.
	var shape := _draw(P.shape([] as Array[Vector2i]))
	_press_paths()
	_click(A)
	_button("+ New path").pressed.emit()
	_click(A)
	assert_int(shape.path_count()).is_equal(2)
	assert_array(shape.path_at(1)).contains_exactly([A])


func test_a_new_path_is_not_stored_until_its_first_tile() -> void:
	# An empty path is a malformed pair (path_fault), so the pending row lives in the widget only.
	var shape := _draw(P.shape([] as Array[Vector2i]))
	_press_paths()
	_click(A)
	_button("+ New path").pressed.emit()
	assert_int(shape.path_count()).is_equal(1)
	assert_str(shape.path_fault()).is_equal("")


func test_picking_a_path_sends_the_next_click_to_it() -> void:
	var shape := _draw(P.pathed(_paths([[A], [C]])))
	_picker().item_selected.emit(1)
	_click(B)
	assert_array(shape.path_at(0)).contains_exactly([A])
	assert_array(shape.path_at(1)).contains_exactly([C, B])


func test_each_path_in_the_picker_carries_its_colour() -> void:
	_draw(P.pathed(_paths([[A], [C]])))
	var picker := _picker()
	for i in 2:
		assert_object(picker.get_item_icon(i)).override_failure_message(
			"Path %d has no swatch to match its arrows by" % (i + 1)).is_not_null()
	assert_object(picker.get_item_icon(0)).is_not_same(picker.get_item_icon(1))


func test_undo_step_pops_the_last_tile_and_unlights_it() -> void:
	var shape := _draw(P.shape([] as Array[Vector2i]))
	_press_paths()
	_click(A)
	_click(B)
	_button("Undo step").pressed.emit()
	assert_array(shape.path_at(0)).contains_exactly([A])
	assert_bool(_lit(B)).override_failure_message(
		"a tile no path visits any more still reads as part of the shape").is_false()


func test_undoing_the_only_tile_removes_the_path() -> void:
	var shape := _draw(P.shape([] as Array[Vector2i]))
	_press_paths()
	_click(A)
	_button("Undo step").pressed.emit()
	assert_int(shape.path_count()).is_equal(0)
	assert_str(shape.path_fault()).is_equal("")


func test_delete_path_removes_the_selected_path_only() -> void:
	var shape := _draw(P.pathed(_paths([[A], [C]])))
	_picker().item_selected.emit(0)
	_button("Delete path").pressed.emit()
	assert_int(shape.path_count()).is_equal(1)
	assert_array(shape.path_at(0)).contains_exactly([C])
	assert_bool(_lit(A)).is_false()
	assert_bool(_lit(C)).is_true()


# --- the pair is never half-written --------------------------------------------------------------

func test_every_announcement_sees_a_sound_pair() -> void:
	# A listener on `changed` reads both fields. Two separate writes would fire it between them, and
	# it would read cells that its lengths do not describe.
	var shape := _draw(P.shape([] as Array[Vector2i]))
	var faults: Array[String] = []
	shape.changed.connect(func() -> void:
		faults.append(shape.path_fault()))
	_press_paths()
	_click(A)
	_click(C)
	_button("+ New path").pressed.emit()
	_click(B)
	_button("Undo step").pressed.emit()
	_press_stamp()
	_answer(true)
	_click(A)
	assert_int(faults.size()).is_greater(0)
	for fault in faults:
		assert_str(fault).override_failure_message(
			"a listener was told about a half-written shape: %s" % fault).is_equal("")


# --- the arrows ------------------------------------------------------------------------------------

func test_segments_run_in_travel_order_with_the_selected_path_drawn_last() -> void:
	var segs := PathArrows.segments(_paths([[A, B, A], [C, B]]), 0)
	var got: Array = []
	for seg in segs:
		got.append([seg["kind"], seg["from"], seg["to"], seg["path"], seg["selected"]])
	var start := PathArrows.Kind.START
	var step := PathArrows.Kind.STEP
	assert_array(got).contains_exactly([
		[start, C, C, 1, false],
		[step, C, B, 1, false],
		[start, A, A, 0, true],
		[step, A, B, 0, true],
		[step, B, A, 0, true],
	])


func test_a_pending_new_path_leaves_every_path_unselected() -> void:
	for seg in PathArrows.segments(_paths([[A, B], [C]]), 2):
		assert_bool(seg["selected"]).is_false()


func test_the_arrow_layer_lies_over_the_grid_and_takes_no_clicks() -> void:
	_draw(P.pathed(_paths([[A, B]])))
	var arrows := _arrows()
	var grid := _grid()
	assert_object(arrows.get_parent()).is_same(grid.get_parent())
	assert_int(arrows.get_index()).override_failure_message(
		"the arrows draw under the cells").is_greater(grid.get_index())
	assert_int(arrows.mouse_filter).override_failure_message(
		"the arrow layer takes the mouse -- every click on the grid would land on it instead of a cell"
	).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_every_arrow_meets_its_cell_at_the_cell_centre() -> void:
	_draw(P.pathed(_paths([[A, B, C]])))
	await await_idle_frame()
	var arrows := _arrows()
	var at := arrows.centres()
	for offset in [A, B, C]:
		var cell := _cell(offset)
		assert_float(cell.size.x).override_failure_message("the grid never laid out").is_greater(0.0)
		var truth := cell.get_global_rect().get_center() - arrows.get_global_rect().position
		assert_vector(at[offset] as Vector2).override_failure_message(
			"the arrow layer puts %s at %s but its cell's centre is at %s" % [offset, at[offset], truth]
		).is_equal_approx(truth, Vector2(0.01, 0.01))


func test_the_arrows_follow_the_selected_path() -> void:
	_draw(P.pathed(_paths([[A], [C]])))
	_picker().item_selected.emit(1)
	assert_int(_arrows().selected_path).is_equal(1)
	_click(B)
	assert_int(_arrows().drawn_paths.size()).is_equal(2)
	assert_array(_arrows().drawn_paths[1]).contains_exactly([C, B])


# --- what the grid shows ---------------------------------------------------------------------------

func test_the_tooltip_names_every_visit() -> void:
	_draw(P.pathed(_paths([[A], [B, A]])))
	var tip := _cell(A).tooltip_text
	assert_str(tip).contains("Path 1: step 1")
	assert_str(tip).contains("Path 2: step 2")


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


func test_a_path_shape_keeps_its_visit_tips_when_the_row_is_tipped_after_it() -> void:
	# A path shape opens in Paths mode, so the cells carry visit tips BEFORE the Attack Editor tips
	# the rows. That tip is the cells' resting one: it must not cover the visits, and it must be what
	# they show once the shape is switched to Stamp.
	_draw(P.pathed(_paths([[A, B]])))
	DevWidgets._tip_rows_from(_box, 0, "THE SHAPE ROW'S TIP")
	assert_str(_cell(A).tooltip_text).override_failure_message(
		"the row's tip covered the path visits on a shape that opened in Paths mode").contains("Path 1: step 1")
	_press_stamp()
	_answer(true)
	assert_str(_cell(A).tooltip_text).is_equal("THE SHAPE ROW'S TIP")


func test_a_grid_drawn_without_the_path_fields_has_no_paths_mode() -> void:
	# The reflective editor draws any declared grid field with no path fields named, and must get
	# exactly the widget it always had.
	var attack := WeaponAttackData.new()
	attack.attack_shape = P.shape([A] as Array[Vector2i])
	DevWidgets.add_cell_grid(_box, "Stamp", attack.attack_shape, "stamp", attack)
	assert_object(_button("Paths")).is_null()
	assert_object(_picker()).is_null()
	assert_object(_arrows()).is_null()


# --- it saves --------------------------------------------------------------------------------------

func test_a_path_shape_saves_and_reloads() -> void:
	var shape := P.pathed(_paths([[A, B, A], [B]]))
	assert_bool(DevWidgets.save_over(shape, SAVE_PATH, null)).is_true()
	var back := ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as AttackShape
	assert_bool(back.is_path_shape()).is_true()
	assert_array(back.stamp).is_empty()
	assert_int(back.path_count()).is_equal(2)
	assert_array(back.path_at(0)).contains_exactly([A, B, A])
	assert_array(back.path_at(1)).contains_exactly([B])


func test_a_path_shape_resaves_byte_identical() -> void:
	# The writer's fixed point: a second save of an unchanged shape must not move a byte, or every
	# Update of a path shape hands the dev a modified file he did not edit.
	var shape := P.pathed(_paths([[A, B, A]]))
	assert_bool(DevWidgets.save_over(shape, SAVE_PATH, null)).is_true()
	var first := FileAccess.get_file_as_string(SAVE_PATH)
	assert_bool(DevWidgets.save_over(shape, SAVE_PATH, null)).is_true()
	assert_str(FileAccess.get_file_as_string(SAVE_PATH)).is_equal(first)
