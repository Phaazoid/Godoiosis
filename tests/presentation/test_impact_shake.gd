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

var _board := SharedBoard.new(SCENE_PATH)
var _scene: Node3D
var game: Node2D
var _unit_mirror: UnitMirror
var _rig: CameraRig3D
# What the wire actually delivered. An Array rather than a bare float because a GDScript lambda
# captures locals BY VALUE, so a plain var assigned inside a Callable never reaches an assertion.
var _reported: Array = []


func before() -> void:
	await _board.open(self, _clear_the_board)


func _clear_the_board() -> void:
	_board.game.scenario_manager.clear_board()
	_board.game.game_state = _board.game.GameState.IDLE


func before_test() -> void:
	await _board.reset(self)
	_scene = _board.scene
	game = _board.scene.game
	_unit_mirror = _scene.get_node("UnitMirror") as UnitMirror
	_rig = _scene.get_node("CameraRig") as CameraRig3D
	_unit_mirror.hovered_unit_source = Callable()
	_reported = []


func after_test() -> void:
	await _board.check(self)


func after() -> void:
	_board.close()


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
	_unit_mirror.report_impact = func(kind: int) -> void:
		seen.append(kind)
		production.call(kind)


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
	# A KIND since #520 diff 2c, not an amplitude: what the mirror observes is that a blow landed
	# and how final it was. What that is WORTH is battle3d's to decide.
	assert_int(_reported[0]).is_equal(UnitMirror.Impact.HIT)


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
	assert_int(_reported[0]).is_equal(UnitMirror.Impact.DOWN)


func test_the_jolt_reaches_the_rig_and_not_just_the_mirror() -> void:
	# The far end of the wire. Asserting the mirror CALLED something would pass against a Callable
	# bound to anything at all; this reads the rig's own channel.
	var victim := _spawn(ENEMY, Vector2i(3, 3))
	await _settle()
	# Claim the lock, not just the view: since 2c the impact handler is GATED on playback owning
	# the camera, because a killing blow now freezes the world and an ungated die() from any source
	# would stop the game dead. stash_view alone is the production edge's SECOND half.
	game.camera_controller.set_playback_locked(true)
	_rig.stash_view()
	assert_float(_rig._shake_amplitude).is_equal_approx(0.0, 0.0001)

	victim.take_damage(3)
	await _settle()
	assert_float(_rig._shake_amplitude).override_failure_message(
			"the mirror reported an impact and the rig's shake channel never moved"
	).is_greater(0.0)


# --- the freeze gate (#520 diff 2c) --------------------------------------------------------------

func test_a_death_outside_playback_does_not_reach_the_director_at_all() -> void:
	# THE GATE, and the freeze is why it exists. A jolt is safe on its own -- the rig's flourish
	# channel is dead unless the view is borrowed -- but a hitstop is GLOBAL, so an ungated die()
	# from any source (a dev-tool kill, a board teardown) would stop the whole game with nobody
	# watching a pass. Asserted through the jolt because both consequences sit behind one gate, and
	# because the freeze itself no-ops headless by design.
	var victim := _spawn(ENEMY, Vector2i(3, 3))
	await _settle()
	_rig.stash_view()
	game.camera_controller.set_playback_locked(false)   # nobody is playing anything back
	assert_float(_rig._shake_amplitude).is_equal_approx(0.0, 0.0001)

	victim.die()
	await _settle()
	assert_float(_rig._shake_amplitude).override_failure_message(
			"a death outside playback reached the director -- so it would also have frozen the world"
	).is_equal_approx(0.0, 0.0001)
	assert_bool(Pacing.is_frozen()).is_false()


func test_the_world_is_never_left_frozen_by_a_pass() -> void:
	# The consequence worth guarding rather than the freeze itself, which headless is a no-op: a
	# time_scale stuck at 0 would stall every case after this one, so the invariant is asserted
	# whatever path got here.
	var victim := _spawn(ENEMY, Vector2i(3, 3))
	await _settle()
	game.camera_controller.set_playback_locked(true)
	_rig.stash_view()
	victim.die()
	await _settle()
	assert_float(Engine.time_scale).override_failure_message(
			"the world was left running at a scale other than 1 -- every later case pays for this"
	).is_equal_approx(1.0, 0.0001)
