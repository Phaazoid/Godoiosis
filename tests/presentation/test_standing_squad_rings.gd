# Standing squad rings (#423 slice 1). ALWAYS_SHOW_SQUAD_RINGS turns the membership ring from a
# SELECTION marker into a persistent one, and a persistent marker has to follow the unit it belongs
# to -- which is the bug this setting exposed.
#
# Driven through the real seams (spawn, join_squad, leave_squad, a resolution pass) rather than by
# calling the sweep directly, because the claim is that MEMBERSHIP CHANGES reach the channel at all.
# Asserted on OverlayManager's marker store and on the 3D mirror's anchors, never on pixels.
#
# Fixture is test_overlay_mirror's: the Battle3D scene with the boot board cleared.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

var _scene: Node3D
var game: Node2D
var _overlays: BoardOverlays


func before_test() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	# The setting persists to disk for real players, so a suite that skipped this would read the
	# DEV'S OWN settings.cfg and pass or fail by what he last clicked.
	PlayerSettings.reset_for_test()
	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	game = _scene.game
	_overlays = _scene.get_node("BoardOverlays") as BoardOverlays
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	PlayerSettings.reset_for_test()
	get_tree().root.remove_child(_scene)
	_scene.free()


# process_frame resumes coroutines BEFORE node _process, so one frame is stale.
func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _om() -> OverlayManager:
	return game.overlay_manager


func _spawn(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), cell)
	assert_object(unit).is_not_null()   # fixture setup, not the claim under test
	return unit


func _rings_on() -> void:
	PlayerSettings.set_on(PlayerSettings.Setting.ALWAYS_SHOW_SQUAD_RINGS, true)


func _pair() -> Array[Unit]:
	var leader := _spawn(Vector2i(2, 2))
	var member := _spawn(Vector2i(5, 2))
	game.squad_manager.join_squad(member, leader.squad)
	return [leader, member]


func _ringed_units() -> Array[Unit]:
	var ringed: Array[Unit] = []
	for key in _om().icons_by_unit:
		var unit := key as Unit
		if unit != null and _om().icons_by_unit[key].has(OverlayIcon.IconType.SQUADMEMBER):
			ringed.append(unit)
	return ringed


# --- The setting -------------------------------------------------------------------

# Off is a promise that nothing changed: the channel still belongs to the selection paths, so the
# setting cannot regress the old board simply by existing.
func test_off_by_default_a_join_leaves_no_standing_ring() -> void:
	assert_bool(PlayerSettings.is_on(PlayerSettings.Setting.ALWAYS_SHOW_SQUAD_RINGS)).is_false()
	_pair()
	await _settle()
	assert_array(_ringed_units()).override_failure_message(
			"a ring stood on the board with the setting OFF -- the selection paths no longer own the channel"
			).is_empty()


func test_on_a_two_member_squad_wears_rings_with_nothing_selected() -> void:
	_rings_on()
	var pair := _pair()
	await _settle()
	var ringed := _ringed_units()
	assert_int(ringed.size()).is_equal(2)
	assert_bool(ringed.has(pair[0]) and ringed.has(pair[1])).is_true()
	# Parity (#292): the 3D view carries the same two, so this is not a 2D-only feature.
	assert_int(_overlays.markers_of(BoardOverlays.Layer.GROUND_ICONS).size()).override_failure_message(
			"the standing rings never reached the 3D ground channel").is_equal(2)


func test_on_solo_squads_wear_none() -> void:
	_rings_on()
	_spawn(Vector2i(2, 2))
	_spawn(Vector2i(5, 2))
	await _settle()
	assert_array(_ringed_units()).override_failure_message(
			"a unit with no squadmates wore a membership ring").is_empty()


# The ring_hue trap. A hue is dealt once at the first squadmate and NEVER reset, so gating the sweep
# on "does this squad have a colour" would leave the leftover member wearing one forever.
func test_on_a_squad_that_shrank_back_to_one_wears_none() -> void:
	_rings_on()
	var pair := _pair()
	await _settle()
	assert_int(_ringed_units().size()).is_equal(2)   # precondition, not the claim
	game.squad_manager.leave_squad(pair[1])
	await _settle()
	assert_bool(pair[0].squad.ring_hue != Color.WHITE).override_failure_message(
			"the shrunken squad lost its dealt hue -- this case no longer covers the trap it was written for"
			).is_true()
	assert_array(_ringed_units()).override_failure_message(
			"a lone unit kept its squad ring -- the sweep is gated on the dealt hue, not on membership"
			).is_empty()


# --- The wire ----------------------------------------------------------------------

# THE bug persistence exposed. A marker used to STORE the cell it was built on and the mirror
# anchored on that copy; markers rebuilt every repaint hid it, but a standing ring outlives the
# move, so the copy went stale and the ring stayed on the cell its unit walked off (#308).
func test_a_standing_ring_follows_the_unit_that_moved() -> void:
	_rings_on()
	var pair := _pair()
	await _settle()
	var moved_to := Vector2i(5, 5)
	pair[1].movement.set_cell(moved_to)
	await _settle()
	var heights: BoardHeights = game.board_heights
	var expected := BoardSpace.surface_transform(moved_to, heights).origin
	var found := false
	for marker: Dictionary in _overlays.markers_of(BoardOverlays.Layer.GROUND_ICONS):
		if (marker["pos"] as Vector3).is_equal_approx(expected):
			found = true
	assert_bool(found).override_failure_message(
			"no ring sits on the cell the unit moved to -- the anchor is a stored copy again"
			).is_true()


# The rings stand down for the WHOLE resolution pass (a marker sits on its unit's projected
# destination, which mid-pass is a cell the unit has not reached) and come back on the settled
# board. The restore is last in _end_squad_turn because that method OPENS by clearing the channel --
# an ordering no assertion about the two ends could catch.
func test_rings_come_back_after_a_pass_settles() -> void:
	_rings_on()
	var pair := _pair()
	await _settle()
	assert_int(_ringed_units().size()).is_equal(2)   # precondition, not the claim
	await game.order_executor.execute_orders(pair[0])
	await _settle()
	assert_int(_ringed_units().size()).override_failure_message(
			"the standing rings never came back after the pass -- the restore runs before the clear"
			).is_equal(2)
