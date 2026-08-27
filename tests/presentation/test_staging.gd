# The TEAR-OUT seam (#521 slice A, umbrella #410): one question -- "is this cell STAGED, and
# where" -- and whether every surface that draws a cell honours the answer.
#
# Two mechanisms carry one answer, because a GridMap cell CANNOT be offset individually: the ground
# routes to a second lattice whose node transform is the displacement, and everything else (units,
# health readouts, props, markup) adds the offset at its own placement site. Both read
# BoardSpace.staged_offset, so a case that pins one does not pin the other -- hence cases for each.
#
# The offset is READ back rather than written down anywhere below (BoardSpace.stage_offset), so the
# lift stays a knob the dev can move without reddening a line here.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"

var _scene: Node3D
var _game: Node2D
var _board: GridMap
var _staged: GridMap
var _unit_mirror: UnitMirror


func before_test() -> void:
	# A static outlives a suite (#449). Cleared at BOTH ends: a case that leaves the board in the
	# sky poisons every case after it, and the poll that draws it is per-frame.
	BoardSpace.reset_for_test()
	get_tree().root.size = Vector2i(1280, 720)
	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_game = _scene.game
	_board = _scene.get_node("Board") as GridMap
	_staged = _scene.get_node("StagedBoard") as GridMap
	_unit_mirror = _scene.get_node("UnitMirror") as UnitMirror
	_scene.load_mission(PROLOG)
	await await_idle_frame()


func after_test() -> void:
	BoardSpace.reset_for_test()
	PlayerSettings.reset_for_test()
	await DialogFixtures.end_all_dialog(self)   # the mission door arms #182 dialog; end it or it leaks
	get_tree().root.remove_child(_scene)
	_scene.free()


# --- the question itself -----------------------------------------------------------------------

# ZERO displacement IS the board, and that is what makes every reader safe on a board that has
# never staged. Asked of every painted cell rather than a sample: the seam has to be inert
# everywhere, not on average.
func test_an_unstaged_board_displaces_nothing() -> void:
	var painted: Array[Vector2i] = _painted_cells()
	assert_array(painted).override_failure_message(
			"fixture drifted: the mission painted no cells").is_not_empty()
	for cell in painted:
		assert_vector(BoardSpace.staged_offset(cell)).override_failure_message(
				"%s was displaced on a board nothing staged" % cell).is_equal(Vector3.ZERO)


func test_a_staged_cell_answers_the_offset_and_the_rest_of_the_board_does_not() -> void:
	var painted := _painted_cells()
	var on_stage: Vector2i = painted[0]
	BoardSpace.stage([on_stage] as Array[Vector2i], BoardSpace.lift_offset())

	assert_vector(BoardSpace.staged_offset(on_stage)).is_equal(BoardSpace.stage_offset())
	assert_bool(BoardSpace.is_staged(on_stage)).is_true()
	var off_stage := _a_cell_other_than(on_stage)
	assert_vector(BoardSpace.staged_offset(off_stage)).override_failure_message(
			"a cell nobody staged came up with the diorama").is_equal(Vector3.ZERO)


# --- the ground: two lattices, one set of coordinates -------------------------------------------

# The tiles LEAVE the board and arrive on the staged lattice at the SAME cell coordinates -- which
# is what makes the diorama an exact reconstruction rather than an arithmetic one -- and the hole
# they leave is the socket the exit will thud them back into.
func test_a_torn_out_column_moves_to_the_staged_lattice_and_comes_home() -> void:
	var cell := _painted_cells()[0]
	var column := _column_of(_board, cell)
	assert_array(column).override_failure_message(
			"fixture drifted: this cell has no column on the board").is_not_empty()

	BoardSpace.stage([cell] as Array[Vector2i], BoardSpace.lift_offset())
	await _settle()

	assert_array(_column_of(_board, cell)).override_failure_message(
			"the ground stayed in the board it was torn out of").is_empty()
	assert_array(_column_of(_staged, cell)).override_failure_message(
			"the torn-out column did not arrive on the staged lattice").is_equal(column)

	BoardSpace.clear_staging()
	await _settle()

	assert_array(_column_of(_staged, cell)).override_failure_message(
			"the column stayed in the sky after the staging cleared").is_empty()
	assert_array(_column_of(_board, cell)).override_failure_message(
			"the column did not thud back into its socket").is_equal(column)


# The staged lattice carries the displacement as its NODE transform -- the whole reason a second
# GridMap exists, since a cell inside one cannot be offset at all.
func test_the_staged_lattice_carries_the_displacement_as_its_own_transform() -> void:
	BoardSpace.stage([_painted_cells()[0]] as Array[Vector2i], BoardSpace.lift_offset())
	await _settle()
	assert_vector(_staged.position).is_equal(BoardSpace.stage_offset())

	BoardSpace.clear_staging()
	await _settle()
	assert_vector(_staged.position).override_failure_message(
			"the staged lattice stayed in the sky with nothing on it").is_equal(Vector3.ZERO)


# --- everything that is not a tile --------------------------------------------------------------

# A unit rides the ground it is standing on. Its sprite is placed from PIXELS, not from BoardSpace,
# which is exactly why the offset has to be added to the whole placement rather than hidden inside
# surface_point -- an offset applied only to the surface query would move it vertically and leave it
# behind horizontally.
func test_a_unit_on_torn_out_ground_rides_up_with_it() -> void:
	var unit := _a_unit()
	assert_object(unit).override_failure_message("fixture drifted: no unit on this board").is_not_null()
	var sprite := _unit_mirror.sprite_for(unit)
	await _settle()
	var home: Vector3 = sprite.position

	var cell: Vector2i = unit.movement.cell
	BoardSpace.stage([cell] as Array[Vector2i], BoardSpace.lift_offset())
	await _settle()

	var offset := BoardSpace.stage_offset()
	# Non-vacuity: at a zero lift the assertion below is true whether anything moved or not.
	assert_float(offset.length()).override_failure_message(
			"the lift is zero, so this case cannot fail").is_greater(0.1)
	assert_vector(sprite.position).override_failure_message(
			"the unit stayed on the board its ground left").is_equal_approx(home + offset, Vector3.ONE * 0.01)


# Anything STANDING on a torn-out cell goes up with it -- props, cover, and the flames here, all of
# which BoardMirror places through its own surface_point. Driven end to end (deposit real fire, let
# the poll stand it up, tear the cell out) because that offset is a wire and #103's law applies:
# ADDED AFTER a mutant deleting it survived every case in this file.
func test_what_stands_on_torn_out_ground_goes_up_with_it() -> void:
	var cell := _painted_cells()[0]
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([Terrain.TileState.BLAZE])
	_game.terrain_states.apply(effect)
	await _settle()

	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var flame := mirror.fire_marker_at(cell)
	assert_object(flame).override_failure_message(
			"no flame was ever stood up -- this case cannot see the offset").is_not_null()
	var home: Vector3 = flame.position

	BoardSpace.stage([cell] as Array[Vector2i], BoardSpace.lift_offset())
	await _settle()

	var offset := BoardSpace.stage_offset()
	assert_float(offset.length()).override_failure_message(
			"the lift is zero, so this case cannot fail").is_greater(0.1)
	assert_vector(mirror.fire_marker_at(cell).position).override_failure_message(
			"the fire stayed burning on the board its ground left") \
		.is_equal_approx(home + offset, Vector3.ONE * 0.01)


# ...and so does the MARKUP on it. Asked of OverlayMirror._anchor directly rather than of a drawn
# marker: every channel that reads it is torn down by the time a pass ends, so there is nothing left
# on screen to look at -- and this is the decision, one answer for every marker in that file.
# ADDED AFTER the same mutant survived.
func test_markup_on_torn_out_ground_goes_up_with_it() -> void:
	var cell := _painted_cells()[0]
	var mirror := _scene.get_node("OverlayMirror") as OverlayMirror
	var home: Transform3D = mirror._anchor(cell)["surface"]

	BoardSpace.stage([cell] as Array[Vector2i], BoardSpace.lift_offset())

	var offset := BoardSpace.stage_offset()
	assert_float(offset.length()).override_failure_message(
			"the lift is zero, so this case cannot fail").is_greater(0.1)
	var staged: Transform3D = mirror._anchor(cell)["surface"]
	assert_vector(staged.origin).override_failure_message(
			"markup stayed on the board the cell it marks left").is_equal_approx(
			home.origin + offset, Vector3.ONE * 0.01)
	assert_that(staged.basis).override_failure_message(
			"the tear-out changed how markup LIES on the cell, which is not its business") \
		.is_equal(home.basis)


# --- the wire into a real pass ------------------------------------------------------------------

# The executor tears out and puts back, and BOTH ends are pinned by one case -- the version moves
# (so it staged at all) and the board is flat again afterwards (so it cleared). Written against the
# VERSION rather than by watching mid-pass, because clear_staging runs before execute_orders
# returns and there is no frame in between to look at.
func test_a_pass_tears_the_fight_out_and_puts_the_board_back() -> void:
	PlayerSettings.set_on(PlayerSettings.Setting.BATTLE_ZOOM, true)
	var unit := _a_unit()
	_queue_a_move(unit)
	var before := BoardSpace.staging_version

	await _game.order_executor.execute_orders(unit)
	await _settle()

	assert_int(BoardSpace.staging_version).override_failure_message(
			"the pass never staged anything").is_greater(before)
	for cell in _painted_cells():
		assert_vector(BoardSpace.staged_offset(cell)).override_failure_message(
				"%s was left in the sky after the pass" % cell).is_equal(Vector3.ZERO)


# WHICH ground goes up, asked of the decision itself. The pass cases above cannot see this: the
# staging is cleared before execute_orders returns, so a version that staged the WHOLE BOARD and put
# it back would satisfy every one of them. Driven at _stage_the_fight because that is the decision,
# and the expected set is BeatSheet's own -- computed the same way the executor computes it, so the
# case says "the fight's ground, nobody else's" rather than naming cells.
func test_the_tear_out_set_is_the_fights_ground_and_not_the_whole_board() -> void:
	var unit := _a_unit()
	_queue_a_move(unit)
	var plan: ResolvedPlan = _game.squad_manager.resolve_plan(unit.squad, _game._board())
	var sheet := BeatSheet.read(unit.squad, plan)
	assert_array(sheet.cells).override_failure_message(
			"fixture drifted: this pass touches no cells").is_not_empty()
	# Non-vacuity: if the fight already covered the board, "not the whole board" proves nothing.
	assert_int(sheet.cells.size()).override_failure_message(
			"the fight covers the whole board, so this case cannot fail") \
		.is_less(_painted_cells().size())

	_game.order_executor._stage_the_fight(sheet, Pacing.Profile.CINEMATIC)

	var staged := BoardSpace.staged_cells()
	staged.sort()
	var want: Array[Vector2i] = sheet.cells.duplicate()
	want.sort()
	assert_array(staged).is_equal(want)

	# ...and the plain board tears out nothing at all, asked of the same door.
	BoardSpace.clear_staging()
	_game.order_executor._stage_the_fight(sheet, Pacing.Profile.BOARD)
	assert_array(BoardSpace.staged_cells()).override_failure_message(
			"the plain board tore the fight out anyway").is_empty()


# THE LAW #521 asks for: with the cinematic off, displacement is provably zero EVERYWHERE. Read off
# the seam directly -- never off a mirror, which something rebuilds every frame and would report
# zero for a reason of its own. The version is asserted too, so "nothing was displaced" cannot pass
# by having staged and cleared within the pass.
func test_with_the_cinematic_off_a_pass_displaces_nothing_at_all() -> void:
	PlayerSettings.set_on(PlayerSettings.Setting.BATTLE_ZOOM, false)
	var unit := _a_unit()
	_queue_a_move(unit)
	var before := BoardSpace.staging_version

	await _game.order_executor.execute_orders(unit)
	await _settle()

	assert_int(BoardSpace.staging_version).override_failure_message(
			"the plain board staged something and put it back").is_equal(before)
	for cell in _painted_cells():
		assert_vector(BoardSpace.staged_offset(cell)).override_failure_message(
				"%s was displaced with the cinematic off" % cell).is_equal(Vector3.ZERO)


# --- helpers ------------------------------------------------------------------------------------

func _painted_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(_game.grid.get_used_cells())
	return cells


func _a_cell_other_than(cell: Vector2i) -> Vector2i:
	for other in _painted_cells():
		if other != cell:
			return other
	return cell


# The rows of a cell's column, top to bottom, as meshlib item ids -- what the tear-out has to move
# without changing. Read off the lattice rather than re-derived, so the case compares the SAME
# question on both sides.
func _column_of(map: GridMap, cell: Vector2i) -> Array[int]:
	var items: Array[int] = []
	for at: Vector3i in map.get_used_cells():
		if at.x == cell.x and at.z == cell.y:
			items.append(map.get_cell_item(at))
	return items


func _a_unit() -> Unit:
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit != null:
			return unit
	return null


# The production door game._click_choosing_move uses, minus the click.
func _queue_a_move(unit: Unit) -> void:
	var moverange = _game.compute_move_range(unit)
	var destinations: Array[Vector2i] = _game.get_move_range(moverange, unit)
	if destinations.is_empty():
		return
	_game.enter_move_mode(unit)
	_game.selected_unit = unit
	_game._on_left_click(destinations[0])


# The rig's own settle: process_frame resumes coroutines BEFORE node _process, so one frame is stale.
func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()
