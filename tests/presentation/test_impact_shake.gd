# The impact WIRE (#520 diff 2b): the mirror sees a blow land, the camera jolts.
#
# This is #103's shape and it is why the suite exists at all. Both ends were already correct and
# unconnected — UnitMirror has polled HP diffs since #314, CameraRig3D gained a shake channel in this
# same diff — so pinning either end alone proves nothing. Every case here drives real damage through
# `Unit.take_damage` / `Unit.die()` and asserts on what reached the RIG.
#
# THE CASE THAT MATTERS MOST is the hidden-bar one. The impact is read ABOVE
# `_settle_health_change`'s `not bar.visible` guard on purpose: the health cubes are a readout and
# rightly vanish with it, but ALWAYS_SHOW_HEALTH ships FALSE, so an impact reported below that line
# would leave the DEFAULT settings with no jolt in them anywhere. That is #534's bug verbatim — a
# whole phase that showed nothing until the dev's own cfg was taken out of the picture — and this
# file is what refuses it a second time.
#
# Fixture is test_predicted_health's: the Battle3D scene with the boot board cleared and units
# spawned by hand, so no content commit can redden it.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _scene: Node3D
var game: Node2D
var _unit_mirror: UnitMirror
var _rig: CameraRig3D
# What the wire actually delivered. An Array rather than a bare float because a GDScript lambda
# captures locals BY VALUE, so a plain var assigned inside a Callable never reaches an assertion.
var _reported: Array = []


func before_test() -> void:
	PlayerSettings.reset_for_test()
	get_tree().root.size = Vector2i(1280, 720)
	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	game = _scene.game
	_unit_mirror = _scene.get_node("UnitMirror") as UnitMirror
	_rig = _scene.get_node("CameraRig") as CameraRig3D
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	_unit_mirror.hovered_unit_source = Callable()
	_reported = []
	await await_idle_frame()


func after_test() -> void:
	PlayerSettings.reset_for_test()
	get_tree().root.remove_child(_scene)
	_scene.free()
	await await_idle_frame()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


# Listen in on the wire WITHOUT replacing it: the production Callable is whatever battle3d bound in
# _ready, and a case that overwrites it is pinning its own stand-in. This wraps it, so the rig still
# receives every report and the assertions read the same values it did.
func _tap() -> void:
	var production: Callable = _unit_mirror.report_impact
	assert_bool(production.is_valid()).override_failure_message(
			"battle3d never bound report_impact -- the wire is missing, which is the whole bug this file exists for"
	).is_true()
	var seen := _reported
	_unit_mirror.report_impact = func(amount: float) -> void:
		seen.append(amount)
		production.call(amount)


func test_a_blow_that_takes_health_off_someone_jolts_the_camera() -> void:
	# Bars ON here, deliberately. This is the ORDINARY path, and keeping it distinct from the hidden
	# case below is what makes the two separable: a mutant that moves the impact under the visibility
	# guard has to leave THIS one green and red only the other, or neither case proves the placement.
	PlayerSettings.set_on(PlayerSettings.Setting.ALWAYS_SHOW_HEALTH, true)
	_tap()
	var victim := _spawn(ENEMY, Vector2i(3, 3))
	await _settle()              # the poll seeds _last_hp at full health
	victim.take_damage(3)
	await _settle()

	assert_int(_reported.size()).override_failure_message(
			"the mirror saw the HP drop and nothing reached the camera"
	).is_greater(0)
	assert_float(_reported[0]).is_equal_approx(Pacing.SHAKE_HIT, 0.0001)


func test_a_hit_still_jolts_the_camera_when_health_bars_are_hidden() -> void:
	# THE DEFAULT SETTINGS CASE. ALWAYS_SHOW_HEALTH is false out of the box and this fixture cuts the
	# hover leg, so no bar is visible here — which is precisely the state a jolt reported below the
	# visibility guard would be silent in. Moving the report under that guard turns this red and
	# leaves every other case in the file green, which is the point of writing it separately.
	_tap()
	var victim := _spawn(ENEMY, Vector2i(3, 3))
	await _settle()
	var bar_showing := false
	for bar in _unit_mirror._bars.values():
		if (bar as UnitHealthBar).visible:
			bar_showing = true
	assert_bool(bar_showing).override_failure_message(
			"a bar was visible, so this case cannot see the bug it exists for"
	).is_false()      # non-vacuity: the precondition IS the case

	victim.take_damage(3)
	await _settle()
	assert_int(_reported.size()).override_failure_message(
			"no jolt with the bars hidden -- the impact is riding the readout's visibility gate (#534's bug)"
	).is_greater(0)


func test_a_heal_does_not_jolt_the_camera() -> void:
	_tap()
	var patient := _spawn(PLAYER, Vector2i(3, 3))
	patient.take_damage(4)
	await _settle()
	_reported.clear()          # the hit above is not what this case is about

	patient.heal(2)
	await _settle()
	assert_int(_reported.size()).override_failure_message(
			"health coming back knocked the camera about"
	).is_equal(0)


func test_a_killing_blow_jolts_harder_and_only_once() -> void:
	# The poll NEVER observes a unit at 0 HP -- die() emits and queue_frees in one frame and the
	# reconcile skips a unit already queued for deletion -- so a death reaches the death rung ALONE.
	# Without the report on that path the loudest moment in a pass would be the one with no jolt at
	# all, which is the failure mode this case names.
	_tap()
	var victim := _spawn(ENEMY, Vector2i(3, 3))
	await _settle()
	_reported.clear()

	victim.die()
	await _settle()

	assert_int(_reported.size()).override_failure_message(
			"a death reported nothing -- the loudest beat in a pass would have no jolt in it"
	).is_equal(1)
	assert_float(_reported[0]).is_equal_approx(Pacing.SHAKE_DOWN, 0.0001)


func test_the_jolt_reaches_the_rig_and_not_just_the_mirror() -> void:
	# The far end of the wire. Asserting the mirror CALLED something would pass against a Callable
	# bound to anything at all; this reads the rig's own channel.
	var victim := _spawn(ENEMY, Vector2i(3, 3))
	await _settle()
	_rig.stash_view()                       # a flourish lives only while playback holds the view
	assert_float(_rig._shake_amplitude).is_equal_approx(0.0, 0.0001)

	victim.take_damage(3)
	await _settle()
	assert_float(_rig._shake_amplitude).override_failure_message(
			"the mirror reported an impact and the rig's shake channel never moved"
	).is_greater(0.0)
