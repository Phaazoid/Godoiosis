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

# Named _shared rather than _board because this suite's _board is already the ground GridMap --
# the one place the pattern's usual name is taken.
var _shared := SharedBoard.new(SCENE_PATH, PROLOG)
var _scene: Node3D
var _game: Node2D
var _board: GridMap
var _staged: GridMap
var _unit_mirror: UnitMirror


func before() -> void:
	await _shared.open(self)


func before_test() -> void:
	await _shared.reset(self)
	_scene = _shared.scene
	_game = _shared.scene.game
	_board = _scene.get_node("Board") as GridMap
	_staged = _scene.get_node("StagedBoard") as GridMap
	_unit_mirror = _scene.get_node("UnitMirror") as UnitMirror


func after_test() -> void:
	await _shared.check(self)


func after() -> void:
	_shared.close()


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
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.ALWAYS)
	var unit := _a_unit()
	_swing_at_open_ground(unit)
	var before := BoardSpace.staging_version

	await _game.order_executor.execute_orders(unit)
	await _settle()

	assert_int(BoardSpace.staging_version).override_failure_message(
			"the pass never staged anything").is_greater(before)
	for cell in _painted_cells():
		assert_vector(BoardSpace.staged_offset(cell)).override_failure_message(
				"%s was left in the sky after the pass" % cell).is_equal(Vector3.ZERO)


# ...and a board SWAPPED mid-tear-out puts it down too (#520 diff 2b). Only execute_orders clears
# the staging, so an interrupted pass — F2, Mission Select — used to hand the fresh board a lifted
# set of cells nothing would ever put back down, and since the rig now RIDES that lift the camera
# went with them. `BoardSpace` is a static and outlives the board exactly the way playback_locked
# does, which is the line this one now sits beside in clear_board.
#
# Staged DIRECTLY rather than through a pass: what is under test is the clear, and driving a real
# pass to reach the state would clear it on the way out.
func test_a_board_swap_puts_the_tear_out_down() -> void:
	var cells: Array[Vector2i] = _painted_cells().slice(0, 3)
	assert_bool(cells.size() == 3).override_failure_message(
			"fixture: this board has fewer than three painted cells").is_true()
	BoardSpace.stage(cells, BoardSpace.lift_offset())
	await _settle()
	assert_bool(BoardSpace.stage_offset().length() > 1.0).override_failure_message(
			"the stage lift is zero; the case proves nothing").is_true()

	_game.scenario_manager.clear_board()
	await _settle()

	for cell in cells:
		assert_vector(BoardSpace.staged_offset(cell)).override_failure_message(
				"%s stayed in the sky after the board it belonged to was swapped out" % cell) \
			.is_equal(Vector3.ZERO)


# WHICH ground goes up, asked of the decision itself. The pass cases above cannot see this: the
# staging is cleared before execute_orders returns, so a version that staged the WHOLE BOARD and put
# it back would satisfy every one of them. Driven at _stage_the_fight because that is the decision,
# and the expected set is BeatSheet's own -- computed the same way the executor computes it, so the
# case says "the fight's ground, nobody else's" rather than naming cells.
func test_the_tear_out_set_is_the_fights_ground_and_not_the_whole_board() -> void:
	var unit := _a_unit()
	_swing_at_open_ground(unit)
	var plan: ResolvedPlan = _game.squad_manager.resolve_plan(unit.squad, _game._board())
	var sheet := BeatSheet.read(unit.squad, plan)
	assert_array(sheet.cells).override_failure_message(
			"fixture drifted: this pass touches no cells").is_not_empty()
	# Non-vacuity: if the fight already covered the board, "not the whole board" proves nothing.
	assert_int(sheet.cells.size()).override_failure_message(
			"the fight covers the whole board, so this case cannot fail") \
		.is_less(_painted_cells().size())

	# The gate is the SHEET's now (#647), not a profile handed in: the tear-out is once per pass, so
	# it asks whether this pass has a fight in it at all. Driven through the setting for that reason.
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.ALWAYS)
	_game.order_executor._stage_the_fight(sheet)

	var staged := BoardSpace.staged_cells()
	staged.sort()
	var want: Array[Vector2i] = sheet.cells.duplicate()
	want.sort()
	assert_array(staged).is_equal(want)

	# ...and the plain board tears out nothing at all, asked of the same door.
	BoardSpace.clear_staging()
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.OFF)
	_game.order_executor._stage_the_fight(sheet)
	assert_array(BoardSpace.staged_cells()).override_failure_message(
			"the plain board tore the fight out anyway").is_empty()

	# ...and COMBAT_ONLY stages it too: this sheet holds a volley, which is the fight. The mode that
	# tears out nothing is a pass with no blow in it, which test_walking_tears_out_nothing covers.
	BoardSpace.clear_staging()
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.COMBAT_ONLY)
	_game.order_executor._stage_the_fight(sheet)
	assert_array(BoardSpace.staged_cells()).override_failure_message(
			"a fight did not go on stage under combat only -- the one mode it is most about").is_not_empty()


# WALKING TEARS OUT NOTHING (dev, 2026-08-26: *"there have to be main actions at play. Movement by
# itself doesn't do it."*). Driven end to end through the real executor, since the rule is about
# what a PASS does -- and reported in play, not reasoned about: the version that shipped tore a hole
# in the board at the end of every move.
#
# The cinematic is deliberately ON, so this cannot pass for the profile gate's reason.
# THE PUBLISH SIDE OF THE CAMERA CHANNEL (#647), which nothing in the suite had ever pinned: every
# case that touches directed_line / beat_emphasis / beat_profile asserts where the RIG reads them,
# so a mutant deleting the executor's write passed the lot. #103's shape exactly -- both ends
# correct, nothing testing the wire -- and the new field would have inherited it.
#
# Driven end to end and asserted on the CONTROLLER, because that is the seam: OrderExecutor has no
# path to the rig, so what it publishes here is the whole of what the 3D camera can ever know.
func test_a_pass_publishes_each_beats_profile_to_the_camera() -> void:
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.COMBAT_ONLY)
	var unit := _a_unit()
	_swing_at_open_ground(unit)
	assert_int(unit.squad.action_queue.size()).override_failure_message(
			"fixture drifted: nothing was queued, so this case cannot fail").is_greater(0)

	await _game.order_executor.execute_orders(unit)
	await _settle()

	# The pass ends on its volley, so the last thing published is the blow's own profile.
	assert_int(_game.camera_controller.beat_profile).override_failure_message(
			"a blow published no cinematic profile -- the camera cannot tell a fight from a walk") \
		.is_equal(Pacing.Profile.CINEMATIC)


func test_a_walk_only_pass_leaves_the_camera_on_the_plain_profile() -> void:
	# The other side of the fork, and the one COMBAT_ONLY exists for: the same board, the same door,
	# a pass with no blow in it.
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.COMBAT_ONLY)
	var unit := _a_unit()
	_queue_a_move(unit)
	assert_int(unit.squad.action_queue.size()).override_failure_message(
			"fixture drifted: no move was queued, so this case cannot fail").is_greater(0)
	_game.camera_controller.beat_profile = Pacing.Profile.CINEMATIC   # a stale value to overwrite

	await _game.order_executor.execute_orders(unit)
	await _settle()

	assert_int(_game.camera_controller.beat_profile).override_failure_message(
			"a walk left the cinematic profile standing -- the camera sways through a plain move") \
		.is_equal(Pacing.Profile.BOARD)


func test_walking_tears_out_nothing() -> void:
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.ALWAYS)
	var unit := _a_unit()
	_queue_a_move(unit)
	assert_int(unit.squad.action_queue.size()).override_failure_message(
			"fixture drifted: no move was queued, so this case cannot fail").is_greater(0)
	var before := BoardSpace.staging_version

	await _game.order_executor.execute_orders(unit)
	await _settle()

	assert_int(BoardSpace.staging_version).override_failure_message(
			"a pass with nothing but movement in it tore out the board").is_equal(before)


# THE WALK HAPPENS ON THE BOARD; the fight is what tears out. An attacker's origin_cell IS its
# post-move cell, so staging before the move phase makes it walk toward a hole and pop into the sky
# on arrival -- which is why the tear-out sits AFTER _execute_action_phase_parallel.
#
# Sampled every frame rather than asserted at the end, because the ordering is only observable
# WHILE the pass runs: execute_orders is started without awaiting, and executing_plan is the
# published "a pass is running" fact that bounds the loop. Both are read, never driven.
func test_the_tear_out_waits_for_the_walk_to_finish() -> void:
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.ALWAYS)
	var mover := _a_mobile_unit()
	assert_object(mover).override_failure_message(
			"fixture: no unit on this board can move").is_not_null()
	_queue_a_move(mover)
	_swing_at_open_ground(mover)     # a MAIN action, or nothing would tear out at all
	var before := BoardSpace.staging_version

	var saw_walking := false
	var staged_mid_walk := false
	_game.order_executor.execute_orders(mover)   # deliberately NOT awaited
	while _game.order_executor.executing_plan != null:
		if mover.movement.moving:
			saw_walking = true
			if BoardSpace.staging_version != before:
				staged_mid_walk = true
		await await_idle_frame()
	await _settle()

	# Non-vacuity: a walk that never spanned a frame would make the assertion below free.
	assert_bool(saw_walking).override_failure_message(
			"the mover was never observed walking, so this case cannot fail").is_true()
	assert_bool(staged_mid_walk).override_failure_message(
			"the ground tore out from under a unit that was still walking to it").is_false()
	assert_int(BoardSpace.staging_version).override_failure_message(
			"the pass never staged at all, so the ordering was not exercised").is_greater(before)


# ...and the bystanders flag does NOT get to reopen that. It widens WHAT comes along once a fight
# is on stage; it is not a second answer to WHETHER one is, which is why _stage_the_fight asks the
# gate before adding anything. Written because the first draft asked it after, so switching the
# feels-test on would have put move-only passes back in the sky.
func test_the_bystanders_flag_does_not_put_a_walk_on_stage() -> void:
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.ALWAYS)
	Experiments.set_on(Experiments.Flag.DIORAMA_BYSTANDERS, true)
	var unit := _a_unit()
	_queue_a_move(unit)
	var before := BoardSpace.staging_version

	await _game.order_executor.execute_orders(unit)
	await _settle()

	assert_int(BoardSpace.staging_version).override_failure_message(
			"the feels-test flag tore out a pass with no main action in it").is_equal(before)


# THE LAW #521 asks for: with the cinematic off, displacement is provably zero EVERYWHERE. Read off
# the seam directly -- never off a mirror, which something rebuilds every frame and would report
# zero for a reason of its own. The version is asserted too, so "nothing was displaced" cannot pass
# by having staged and cleared within the pass.
func test_with_the_cinematic_off_a_pass_displaces_nothing_at_all() -> void:
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.OFF)
	var unit := _a_unit()
	_swing_at_open_ground(unit)
	var before := BoardSpace.staging_version

	await _game.order_executor.execute_orders(unit)
	await _settle()

	assert_int(BoardSpace.staging_version).override_failure_message(
			"the plain board staged something and put it back").is_equal(before)
	for cell in _painted_cells():
		assert_vector(BoardSpace.staged_offset(cell)).override_failure_message(
				"%s was displaced with the cinematic off" % cell).is_equal(Vector3.ZERO)


# --- the transition: tiles TRAVEL between the board and the diorama (#521 slice B) ---------------
#
# Driven at BoardSpace rather than through a pass, for the reason slice A already recorded: the
# staging is cleared before execute_orders returns, so nothing mid-transition survives to be looked
# at afterwards. What is pinned here is the DECISION and the WIRE -- who is short of the diorama,
# who has landed, and what the version says about it. The travel itself is invisible headless (the
# await returns without a frame ever drawing) and is a play-check, which is what the flag is for.


func test_a_flight_holds_its_tiles_short_of_the_diorama_until_their_turn_comes() -> void:
	var cells: Array[Vector2i] = _painted_cells().slice(0, 3)
	assert_bool(cells.size() == 3).override_failure_message(
			"fixture: this board has fewer than three painted cells").is_true()
	var lift := BoardSpace.lift_offset()
	BoardSpace.stage(cells, lift)
	var plan := StagingFlight.schedule(cells)
	BoardSpace.begin_flight(plan, -lift, Vector3.ZERO, true)

	# Nothing has moved yet: every tile is still in the socket it came from, which is the board.
	for cell in cells:
		assert_vector(BoardSpace.staged_offset(cell)).override_failure_message(
				"%s started the transition already at the diorama" % cell).is_equal(Vector3.ZERO)

	# Far enough for the FIRST to be home and not the last -- the one-by-one the ticket asks for.
	BoardSpace.advance_flight(float(plan[0]["land"]) + 0.0001)
	assert_vector(BoardSpace.staged_offset(cells[0])).override_failure_message(
			"the first tile did not arrive when its flight ended").is_equal(lift)
	assert_bool(BoardSpace.in_flight(cells[2])).override_failure_message(
			"the last tile arrived with the first -- nothing is staggered").is_true()

	BoardSpace.advance_flight(StagingFlight.total(plan))
	assert_bool(BoardSpace.flight_active()).is_false()
	for cell in cells:
		assert_vector(BoardSpace.staged_offset(cell)).override_failure_message(
				"%s never finished its flight" % cell).is_equal(lift)


func test_a_landing_bumps_the_version_and_a_plain_frame_does_not() -> void:
	# OverlayMirror rebuilds every standing prop when this number moves, so bumping it per frame
	# would rebuild the board on every frame of the transition. Landings are discrete; travel is not.
	var cells: Array[Vector2i] = _painted_cells().slice(0, 3)
	var lift := BoardSpace.lift_offset()
	BoardSpace.stage(cells, lift)
	var plan := StagingFlight.schedule(cells)
	BoardSpace.begin_flight(plan, -lift, Vector3.ZERO, true)

	var before := BoardSpace.staging_version
	assert_bool(BoardSpace.advance_flight(0.0)).override_failure_message(
			"a zero-length step reported a landing").is_false()
	assert_int(BoardSpace.staging_version).override_failure_message(
			"a frame with nothing landing still bumped the version").is_equal(before)

	assert_bool(BoardSpace.advance_flight(StagingFlight.total(plan) + 1.0)).override_failure_message(
			"every tile landed and no landing was reported").is_true()
	assert_int(BoardSpace.staging_version).is_greater(before)


func test_clearing_the_staging_takes_the_flight_with_it() -> void:
	# The F2 case. clear_board() calls clear_staging(), and if the flight did not die INSIDE that
	# door a board swapped mid-transition would hand the fresh board columns in the air with nothing
	# left to bring them down -- slice A's own bug, one layer up.
	var cells: Array[Vector2i] = _painted_cells().slice(0, 3)
	var lift := BoardSpace.lift_offset()
	BoardSpace.stage(cells, lift)
	BoardSpace.begin_flight(StagingFlight.schedule(cells), -lift, Vector3.ZERO, true)
	BoardSpace.drive_camera_lift(Vector3.ZERO)
	assert_bool(BoardSpace.flight_active()).is_true()

	_game.scenario_manager.clear_board()
	await _settle()

	assert_bool(BoardSpace.flight_active()).override_failure_message(
			"a board swapped mid-transition left tiles still flying").is_false()
	for cell in cells:
		assert_vector(BoardSpace.staged_offset(cell)).is_equal(Vector3.ZERO)


func test_the_camera_asks_where_IT_should_be_not_where_the_diorama_is() -> void:
	# Equal at rest, which is what makes this invisible to every existing caller -- and different
	# during exactly one window, which is the window that needs them apart: the cut treatment puts
	# the camera at the diorama before a single tile is there.
	var cells: Array[Vector2i] = _painted_cells().slice(0, 2)
	var lift := BoardSpace.lift_offset()
	BoardSpace.stage(cells, lift)
	assert_vector(BoardSpace.camera_lift()).override_failure_message(
			"with nothing driving it the camera should sit exactly where the diorama does"
			).is_equal(BoardSpace.stage_offset())

	BoardSpace.drive_camera_lift(Vector3.ZERO)
	assert_vector(BoardSpace.camera_lift()).override_failure_message(
			"a driven camera lift did not override the diorama's height").is_equal(Vector3.ZERO)
	assert_vector(BoardSpace.stage_offset()).override_failure_message(
			"driving the camera moved the DIORAMA, which is a different question").is_equal(lift)

	BoardSpace.release_camera_lift()
	assert_vector(BoardSpace.camera_lift()).is_equal(lift)


func test_a_pass_leaves_nothing_in_the_air_even_though_no_frame_ever_drew_it() -> void:
	# The property every existing staging assertion rests on. Headless the transition's await returns
	# without a single frame, so nothing ever advanced the flight -- the executor ends it explicitly
	# rather than trusting a driver that, in this run, does not exist.
	PlayerSettings.set_on(PlayerSettings.Setting.BATTLE_ZOOM, true)
	var unit := _a_unit()
	_swing_at_open_ground(unit)

	await _game.order_executor.execute_orders(unit)
	await _settle()

	assert_bool(BoardSpace.flight_active()).override_failure_message(
			"the pass returned with tiles still in the air").is_false()
	assert_vector(BoardSpace.camera_lift()).override_failure_message(
			"the pass returned still driving the camera's height").is_equal(BoardSpace.stage_offset())


func test_with_the_cinematic_off_nothing_ever_flies() -> void:
	# The tear-out is the zoom's, so the transition is too -- read off the seam rather than promised,
	# the same way slice A's own displacement law is.
	PlayerSettings.set_on(PlayerSettings.Setting.BATTLE_ZOOM, false)
	var unit := _a_unit()
	_swing_at_open_ground(unit)

	await _game.order_executor.execute_orders(unit)
	await _settle()

	assert_bool(BoardSpace.flight_active()).is_false()
	for cell in _painted_cells():
		assert_vector(BoardSpace.staged_offset(cell)).is_equal(Vector3.ZERO)


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


func _a_mobile_unit() -> Unit:
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit == null:
			continue
		var reachable: Array[Vector2i] = _game.get_move_range(_game.compute_move_range(unit), unit)
		if not reachable.is_empty():
			return unit
	return null


func _a_unit() -> Unit:
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit != null:
			return unit
	return null


# #47's swing at open ground: a legal aim with no unit on the cell, which resolves and PLAYS. The
# cheapest MAIN ACTION this suite can stage without asking what the board contains (the content
# razor) -- every alternative needs an enemy standing in reach. _queue_action is the raw door,
# since the queue-time whiff gate would refuse an aim at nobody and what is staged here is a pass.
func _swing_at_open_ground(attacker: Unit) -> void:
	# The PROJECTED cell, so this is still a legal aim when a move is queued ahead of it -- an aim
	# stamped from the pre-move cell would be refused and the whole pass with it.
	var origin: Vector2i = attacker.get_projected_destination()
	attacker.squad._queue_action(AttackAction.declare(attacker, origin, origin + Vector2i(1, 1)))


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
