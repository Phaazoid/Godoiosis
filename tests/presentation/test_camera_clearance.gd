# The shot clearance's WIRE (#1132): battle3d reads the real mirrors, decides, and pushes the answer
# back at them -- the camera turns, a column leaves the drawn board, a sprite and its readout go dark,
# and all of it comes back when the camera lets go.
#
# The rules themselves are test_shot_clearance's, asked scene-free. What this suite owns is that the
# ends are CONNECTED, which is the half a green rules suite cannot see (#103's shape).
#
# The causes are scripted at the seam the mirror reads and _mirror_camera is driven by hand: a real
# pass collapses to zero frames headless, so it never polls the mirror at all (test_camera_follow's
# shot-transcript note). Board geometry is PAINTED here, never read off authored content: the patch
# is levelled to the ground and every tower raised by the case that needs it.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

# A tower's rule height: twenty world units up, over any lens this rig settles at.
const TALL := 40
# How far round the subject the ground is levelled, so nothing authored stands in a sight line.
const PATCH := 6

var _board := SharedBoard.new(SCENE_PATH)
var _scene: Node3D
var _game: Node2D
var _rig: CameraRig3D
var _mirror: BoardMirror
var _units: UnitMirror


func before() -> void:
	await _board.open(self, _clear_the_board)


func _clear_the_board() -> void:
	_board.game.scenario_manager.clear_board()
	_board.game.game_state = _board.game.GameState.IDLE


func before_test() -> void:
	await _board.reset(self)
	_scene = _board.scene
	_game = _board.scene.game
	_rig = _scene.get_node("CameraRig") as CameraRig3D
	_mirror = _scene.get_node("BoardMirror") as BoardMirror
	_units = _scene.get_node("UnitMirror") as UnitMirror


func after_test() -> void:
	_cam()._panning = false   # the approach cases script a pan in flight; a stuck one freezes the 2D camera
	_units._death_show = false
	_cam().set_playback_locked(false)
	_scene._mirror_camera()
	await _board.check(self)


func after() -> void:
	_board.close()


func _cam() -> CameraController:
	return _game.camera_controller


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = _game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()   # fixture setup, not the claim under test
	return unit


func _floor_row() -> int:
	return _mirror.floor_row_of(_game.board_heights)


# An open field PATCH cells in every direction, PAINTED here: flat walkable grass at ground level, so
# nothing the scene's own board happens to hold stands in a sight line. The tile is found by the
# tileset's own rules (its kind, its walkability, that it stands nothing up), never by name.
func _open_ground() -> Vector2i:
	var grass := _grass_tile()
	var centre := Vector2i(PATCH + 1, PATCH + 1)
	for dy in range(-PATCH, PATCH + 1):
		for dx in range(-PATCH, PATCH + 1):
			var cell := centre + Vector2i(dx, dy)
			_game.grid.paint(cell, grass.x, Vector2i(grass.y, grass.z))
			_game.board_heights.set_cell(cell, 0, Terrain.RampRise.NONE)
	_scene.rebuild()
	return centre


func _grass_tile() -> Vector3i:
	var tiles: TileSet = _game.grid.tile_set
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var source := tiles.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			var data := source.get_tile_data(coords, 0)
			if GridUtils.terrain_kind_of(data) == Terrain.Kind.GRASS \
					and GridUtils.walkable_of(data) and not GridUtils.stands_up_of(data):
				return Vector3i(source_id, coords.x, coords.y)
	assert_bool(false).override_failure_message("the tileset has no flat walkable grass").is_true()
	return Vector3i.ZERO


func _raise(cells: Array[Vector2i]) -> void:
	for cell in cells:
		_game.board_heights.set_cell(cell, TALL, Terrain.RampRise.NONE)
	_scene.rebuild()


func _ring(centre: Vector2i) -> Array[Vector2i]:
	var ring: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx != 0 or dy != 0:
				ring.append(centre + Vector2i(dx, dy))
	return ring


# Playback owns the camera on a battle-zoom beat, aimed along `line`, trained on `subject` -- the
# approach's first frame, where the angle is CHOSEN (only a travelling pan may turn the camera), and
# then the landing. A headless pan lands before any frame runs, so the travelling frame is scripted.
func _frame(subject: Unit, line: Array[Vector2i], profile := Pacing.Profile.CINEMATIC,
		cinematic := true) -> void:
	await _settle()   # the unit mirror draws a spawned unit on its next frame, and the clearance looks at the DRAWN body
	var cam := _cam()
	cam.set_playback_locked(true)
	cam.playback_cinematic = cinematic
	cam.beat_profile = profile
	cam.directed_line = line
	cam.pan_subject = subject
	cam.pan_destination = subject.global_position
	cam._panning = true
	_scene._mirror_camera()
	cam._panning = false
	await cam.pan_to(subject)
	_scene._mirror_camera()


# Playback holds the camera over `from`, and a pan has just set off toward `subject` -- its FIRST
# frame, scripted at the seam the mirror reads, because a headless pan lands before any frame runs
# (pan_to_position's escape). The caller drives the frame itself.
func _approach(subject: Unit, line: Array[Vector2i], from: Vector2i,
		profile := Pacing.Profile.CINEMATIC) -> void:
	await _settle()
	var cam := _cam()
	cam.set_playback_locked(true)
	cam.playback_cinematic = true
	cam.beat_profile = profile
	cam.directed_line = line
	cam.snap_to_position(GridUtils.cell_world(_game.grid, from))
	_scene._mirror_camera()
	cam.pan_subject = subject
	cam.pan_destination = subject.global_position
	cam._panning = true


# The cell `share` of the way from the subject toward where the lens would settle at turn 0.
func _toward_lens(subject: Unit, line: Array[Vector2i], share: float) -> Vector2i:
	var lens := _rig.lens_at(_rig.directed_yaw(line, 0.0), CameraRig3D.When.SETTLED)
	var feet := _units.sprite_for(subject).global_position
	var at := feet.lerp(lens, share)
	return Vector2i(floori(at.x), floori(at.z))


func _drawn_in(map: GridMap, cell: Vector2i) -> bool:
	return BoardPicker.top_of(map, cell, _floor_row()) != BoardPicker.NO_COLUMN


func _east_west(centre: Vector2i) -> Array[Vector2i]:
	var line: Array[Vector2i] = [centre + Vector2i(2, 0), centre]
	return line


# --- turning first -----------------------------------------------------------------------------

func test_a_blocked_side_turns_the_camera_to_the_clear_one() -> void:
	var centre := _open_ground()
	var subject := _spawn(Team.Faction.PLAYER, centre)
	var line := _east_west(centre)
	await _frame(subject, line)
	assert_float(_scene._clearance.turn).override_failure_message(
			"an open field turned the camera -- the shot no longer opens side-on").is_equal(0.0)
	var tower := _toward_lens(subject, line, 0.45)
	assert_bool(tower != centre).override_failure_message(
			"the lens sits over the subject's own cell, so no tower can stand between them") \
		.is_true()
	# The tower is up BEFORE the next beat's approach: the angle is chosen while the camera travels.
	_cam().set_playback_locked(false)
	_scene._mirror_camera()
	_raise([tower])
	await _frame(subject, line)
	assert_float(ShotClearance.deviation(_scene._clearance.turn)).override_failure_message(
			"the turn left side-on when the other side was open").is_equal(0.0)
	assert_float(absf(_scene._clearance.turn)).override_failure_message(
			"a tower stood between the lens and the subject and the camera did not turn") \
		.is_equal(180.0)
	assert_float(_rig._target_yaw_degrees).override_failure_message(
			"the clearance chose a turn the camera is not heading for") \
		.is_equal_approx(_rig.directed_yaw(line, _scene._clearance.turn), 0.001)
	assert_bool(_mirror.is_column_hidden(tower)).override_failure_message(
			"a clear angle existed and the tower was hidden anyway").is_false()


# --- holding still once landed (round 3, dev 2026-10-07) ---------------------------------------
#
# "If the camera is still moving to a new position, nothing should be playing." Once the approach has
# landed an action is about to play or playing, so whatever comes into the way after that -- a lunge,
# a tumble, a tower -- is HIDDEN, and the camera keeps the angle it arrived at.

func test_once_landed_a_new_blocker_is_hidden_and_the_camera_holds_its_angle() -> void:
	var centre := _open_ground()
	var subject := _spawn(Team.Faction.PLAYER, centre)
	var line := _east_west(centre)
	await _frame(subject, line)
	var yaw_before := _rig._target_yaw_degrees
	var tower := _toward_lens(subject, line, 0.45)
	assert_bool(tower != centre).override_failure_message(
			"the lens sits over the subject's own cell, so no tower can stand between them") \
		.is_true()
	_raise([tower])
	_scene._mirror_camera()
	assert_float(_scene._clearance.turn).override_failure_message(
			"a blocker arriving after the camera landed TURNED it -- the mid-blow swing").is_equal(0.0)
	assert_float(_rig._target_yaw_degrees).override_failure_message(
			"the camera is heading for a new angle while the shot plays").is_equal(yaw_before)
	assert_bool(_mirror.is_column_hidden(tower)).override_failure_message(
			"the tower that came into the way after landing was left in it").is_true()


# A shot CHANGE after landing is not an approach either -- the tether break's pull back to the stage
# (#367 2B) happens mid-linger, with no pan. Its fresh search may hide but may not turn.
func test_a_shot_change_after_landing_hides_rather_than_turns() -> void:
	var centre := _open_ground()
	var subject := _spawn(Team.Faction.PLAYER, centre)
	var line := _east_west(centre)
	await _frame(subject, line)
	var tower := _toward_lens(subject, line, 0.45)
	_raise([tower])
	_scene._mirror_camera()
	var stage: Array[Vector2i] = [centre]
	var cam := _cam()
	cam.shot_cells = stage
	cam.follow(null)
	_scene._mirror_camera()
	assert_int(_scene._shots.active).override_failure_message(
			"precondition: the shot did not change to the stage, so no fresh search ran") \
		.is_equal(ShotDirector.Shot.STAGE)
	assert_float(_scene._clearance.turn).override_failure_message(
			"a search with no pan travelling turned the camera").is_equal(0.0)
	cam.shot_cells = []


# --- the approach (#1132 follow-up) ------------------------------------------------------------
#
# Dev, 2026-10-07: "that first camera zoom should just be going to the correct spot to watch the hit".
# The shot -- the close-up, and the clearance's angle -- is decided on the pan's FIRST frame, from
# where it lands, so the approach is one movement rather than a landing followed by an adjustment.

func test_the_approach_decides_the_shot_from_where_the_pan_lands() -> void:
	var centre := _open_ground()
	var subject := _spawn(Team.Faction.PLAYER, centre)
	var line := _east_west(centre)
	# The tower's cell comes from the lens the rig settles at over the subject...
	await _frame(subject, line)
	var tower := _toward_lens(subject, line, 0.45)
	assert_bool(tower != centre).override_failure_message(
			"the lens sits over the subject's own cell, so no tower can stand between them").is_true()
	_cam().set_playback_locked(false)
	_scene._mirror_camera()
	_raise([tower])
	# ...and the camera now starts five cells further along the line, so the sight line from where it
	# is passing through runs wide of the tower.
	await _approach(subject, line, centre + Vector2i(5, 0))
	_scene._mirror_camera()
	assert_int(_scene._shots.active).override_failure_message(
			"the close-up waited for the pan to land -- the approach is two movements again") \
		.is_equal(ShotDirector.Shot.TRAINED)
	assert_float(_rig._target_distance).override_failure_message(
			"the shot is trained on the subject but the zoom is not heading for the close-up") \
		.is_equal_approx(Pacing.TRAINED_DISTANCE, 0.001)
	var cam := _cam()
	var in_flight := _rig.lens_at(_rig.directed_yaw(line, 0.0), CameraRig3D.When.SETTLED)
	var seen := ShotClearance.survey(_scene._clearance_world(cam, subject), in_flight,
			_scene._clearance_subjects(cam, subject), _scene._clearance_extras(cam))
	assert_bool(seen.is_clear()).override_failure_message(
			"precondition: the tower blocks the camera where it is passing through too, so the case "
			+ "cannot tell which lens the choice was judged from").is_true()
	assert_float(absf(_scene._clearance.turn)).override_failure_message(
			"the angle was not chosen from where the pan lands, so the turn waits for the landing") \
		.is_equal(180.0)
	assert_float(_rig._target_yaw_degrees).override_failure_message(
			"the clearance chose a turn the approaching camera is not heading for") \
		.is_equal_approx(_rig.directed_yaw(line, _scene._clearance.turn), 0.001)


func test_off_the_battle_zoom_the_approach_is_not_the_shot() -> void:
	var centre := _open_ground()
	var subject := _spawn(Team.Faction.PLAYER, centre)
	await _approach(subject, _east_west(centre), centre + Vector2i(5, 0), Pacing.Profile.BOARD)
	_scene._mirror_camera()
	assert_int(_scene._shots.active).override_failure_message(
			"a plain-board pan trained the shot before it landed -- zoom off is not today's") \
		.is_equal(ShotDirector.Shot.WIDE)


func test_a_live_death_show_outranks_the_approach() -> void:
	# DEATH_SHOW stands only while nobody is followed; an approach counting as a follow would pull the
	# camera out of the pit with the cubes still in the air (#602 round 8).
	var centre := _open_ground()
	var subject := _spawn(Team.Faction.PLAYER, centre)
	await _approach(subject, _east_west(centre), centre + Vector2i(5, 0))
	_units._death_show = true
	_scene._mirror_camera()
	assert_int(_scene._shots.active).override_failure_message(
			"the next beat's approach took the camera while the death show still held it") \
		.is_equal(ShotDirector.Shot.DEATH_SHOW)
	_units._death_show = false
	_scene._mirror_camera()
	assert_int(_scene._shots.active).override_failure_message(
			"the show ended and the approach never took the shot -- the case above proves nothing") \
		.is_equal(ShotDirector.Shot.TRAINED)


# --- then hiding -------------------------------------------------------------------------------

func test_with_every_side_blocked_the_tower_in_the_way_leaves_the_drawn_board() -> void:
	var centre := _open_ground()
	var subject := _spawn(Team.Faction.PLAYER, centre)
	var ring := _ring(centre)
	_raise(ring)
	await _frame(subject, _east_west(centre))
	var hidden: Array[Vector2i] = []
	for cell in ring:
		if _mirror.is_column_hidden(cell):
			hidden.append(cell)
	assert_int(hidden.size()).override_failure_message(
			"every angle was walled in and no tower was hidden").is_greater(0)
	for cell in hidden:
		assert_bool(_drawn_in(_scene.get_node("Board") as GridMap, cell)).override_failure_message(
				"hidden tower %s is still drawn on the board" % cell).is_false()
		assert_bool(_drawn_in(_mirror.hidden_board, cell)).override_failure_message(
				"hidden tower %s is in no lattice at all -- the release has nothing to put back"
				% cell).is_true()
	assert_bool(_drawn_in(_scene.get_node("Board") as GridMap, centre)).override_failure_message(
			"the ground the subject stands on was hidden").is_true()


func test_the_release_puts_every_hidden_tower_back() -> void:
	var centre := _open_ground()
	var subject := _spawn(Team.Faction.PLAYER, centre)
	var ring := _ring(centre)
	_raise(ring)
	await _frame(subject, _east_west(centre))
	assert_int(_mirror.hidden_counts().x).override_failure_message(
			"precondition: nothing was hidden, so the release has nothing to prove").is_greater(0)
	_cam().set_playback_locked(false)
	_scene._mirror_camera()
	assert_int(_mirror.hidden_counts().x).override_failure_message(
			"the camera let go and a tower stayed hidden").is_equal(0)
	for cell in ring:
		assert_bool(_drawn_in(_scene.get_node("Board") as GridMap, cell)).override_failure_message(
				"tower %s did not come back to the board" % cell).is_true()


func test_a_hidden_staged_column_goes_back_to_the_stage() -> void:
	var cell := _open_ground()
	BoardSpace.stage([cell] as Array[Vector2i], BoardSpace.lift_offset())
	await _settle()
	var staged := _scene.get_node("StagedBoard") as GridMap
	assert_bool(_drawn_in(staged, cell)).override_failure_message(
			"precondition: the column never reached the stage").is_true()
	var hide: Dictionary[Vector2i, bool] = {cell: true}
	var none: Dictionary[Vector2i, bool] = {}
	_mirror.set_camera_hidden(hide, none, _game.grid, _game.board_heights, _floor_row())
	assert_bool(_drawn_in(staged, cell)).override_failure_message(
			"a hidden column is still drawn on the stage").is_false()
	_mirror.set_camera_hidden(none, none, _game.grid, _game.board_heights, _floor_row())
	assert_bool(_drawn_in(staged, cell)).override_failure_message(
			"the column came back somewhere other than the stage it was hidden from").is_true()
	assert_bool(_drawn_in(_scene.get_node("Board") as GridMap, cell)).override_failure_message(
			"the unhidden column was drawn on the board as well as the stage").is_false()
	BoardSpace.clear_staging()
	await _settle()


func test_a_hidden_prop_stays_hidden_when_a_tear_out_rebuilds_it() -> void:
	# Every staging bump drops and rebuilds a staged cell's prop. A hide written only when the set
	# changed would come back on the next landing -- the builder has to ask as well.
	var cell := _open_ground()
	var tiles := ObjectKnobs.object_tiles(_game.grid.tile_set)
	assert_int(tiles.size()).override_failure_message(
			"the tileset has no standing tile to plant").is_greater(0)
	var tile: Dictionary = tiles[0]
	var coords: Vector2i = tile["coords"]
	_game.grid.paint(cell, int(tile["source_id"]), coords)
	_scene.rebuild()
	var before: Node3D = _mirror._props.get(cell)
	assert_object(before).override_failure_message(
			"precondition: the painted tile stood nothing up").is_not_null()
	var none: Dictionary[Vector2i, bool] = {}
	var hide: Dictionary[Vector2i, bool] = {cell: true}
	_mirror.set_camera_hidden(none, hide, _game.grid, _game.board_heights, _floor_row())
	assert_bool(before.visible).override_failure_message("the prop was not hidden").is_false()
	BoardSpace.stage([cell] as Array[Vector2i], BoardSpace.lift_offset())
	await _settle()
	var after: Node3D = _mirror._props.get(cell)
	assert_bool(after != null and after != before).override_failure_message(
			"the tear-out did not rebuild the prop, so the case proves nothing about a rebuild") \
		.is_true()
	assert_bool(after.visible).override_failure_message(
			"the tear-out rebuilt a hidden prop and it came back into the shot").is_false()
	_mirror.set_camera_hidden(none, none, _game.grid, _game.board_heights, _floor_row())
	BoardSpace.clear_staging()
	await _settle()


# --- the scope: battle zoom only (dev ruling 4) ---------------------------------------------------

func test_a_beat_that_is_not_a_battle_zoom_beat_turns_nothing_and_hides_nothing() -> void:
	var centre := _open_ground()
	var subject := _spawn(Team.Faction.PLAYER, centre)
	_raise(_ring(centre))
	await _frame(subject, _east_west(centre), Pacing.Profile.BOARD)
	assert_float(_scene._clearance.turn).override_failure_message(
			"a plain-board beat was turned by the clearance").is_equal(0.0)
	assert_int(_mirror.hidden_counts().x).override_failure_message(
			"a plain-board beat hid terrain").is_equal(0)
	_cam().set_playback_locked(false)
	_scene._mirror_camera()
	await _frame(subject, _east_west(centre), Pacing.Profile.CINEMATIC, false)
	assert_int(_mirror.hidden_counts().x).override_failure_message(
			"a pass with no fight in it hid terrain").is_equal(0)


func test_a_board_swap_mid_hide_leaves_nothing_hidden() -> void:
	var centre := _open_ground()
	var subject := _spawn(Team.Faction.PLAYER, centre)
	_raise(_ring(centre))
	await _frame(subject, _east_west(centre))
	assert_int(_mirror.hidden_counts().x).override_failure_message(
			"precondition: nothing was hidden").is_greater(0)
	_game.scenario_manager.clear_board()
	await _settle()
	assert_int(_mirror.hidden_counts().x).override_failure_message(
			"a board swap left a column hidden").is_equal(0)
	assert_int(_scene._clearance.hidden.hideable()).override_failure_message(
			"a board swap left the clearance holding hides for a board that is gone").is_equal(0)


# --- units --------------------------------------------------------------------------------------

func test_a_unit_the_zoom_hides_drops_its_sprite_and_its_readout() -> void:
	var centre := _open_ground()
	var unit := _spawn(Team.Faction.PLAYER, centre)
	PlayerSettings.set_choice(PlayerSettings.Setting.HEALTH_BARS, PlayerSettings.HealthBars.EVERY)
	await _settle()
	var sprite := _units.sprite_for(unit)
	var bar := _units.bar_for(unit)
	assert_bool(sprite.visible and bar.visible).override_failure_message(
			"precondition: the unit and its readout were not up").is_true()
	_units.camera_hidden = {unit.get_instance_id(): true}
	await _settle()
	assert_bool(sprite.visible).override_failure_message(
			"a unit the battle zoom hid is still drawn").is_false()
	assert_bool(bar.visible).override_failure_message(
			"a hidden unit's readout hung in the air without it").is_false()
	_units.camera_hidden = {}
	await _settle()
	assert_bool(sprite.visible and bar.visible).override_failure_message(
			"the unit did not come back when the hide lifted").is_true()


func test_the_zoom_pushes_its_hidden_units_at_the_mirror_and_takes_them_back() -> void:
	var centre := _open_ground()
	var subject := _spawn(Team.Faction.PLAYER, centre)
	var other := _spawn(Team.Faction.ENEMY, centre + Vector2i(0, 3))
	await _frame(subject, _east_west(centre))
	_scene._clearance.hidden.units[other.get_instance_id()] = true
	_scene._push_hidden()
	assert_bool(_units.camera_hidden.has(other.get_instance_id())).override_failure_message(
			"the clearance hid a unit and the unit mirror was never told").is_true()
	_cam().set_playback_locked(false)
	_scene._mirror_camera()
	assert_int(_units.camera_hidden.size()).override_failure_message(
			"the camera let go and a unit stayed hidden").is_equal(0)
