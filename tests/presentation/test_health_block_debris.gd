# The cubes a unit LOSES (#314): does losing HP actually knock cubes out of the readout, does a
# death detonate the whole grid, and — the case this suite exists for — does a readout that was
# never on screen stay quiet?
#
# THE BASELINE TRAP is the reason this is a wire test rather than a call to burst(). UnitMirror
# tracks each unit's HP for EVERY unit every frame, including ones wearing no readout, because a
# baseline refreshed only while a readout is up goes stale the moment one hides — and the whole
# hidden loss then reads as damage taken this frame the next time the readout appears. Both ends
# would be individually correct; only driving the real pointer -> gate -> diff chain can see it.
#
# Headless cannot see motion, so what these cases assert is POOL OCCUPANCY and the arithmetic
# feeding it. How the burst FEELS is the dev's, by playing — see the PR body.
#
# Fixture is test_unit_health_bar's, for the same reason: the Battle3D scene with the boot board
# cleared and units spawned by hand, so no content commit can redden anything here.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

var _scene: Node3D
var game: Node2D
var _unit_mirror: UnitMirror


func before_test() -> void:
	# Hermetic, and NOT optional (#350): is_on() falls through to user://settings.cfg, so without
	# this the always-show preference decides whether a readout is up, and every case here forks on
	# exactly that.
	PlayerSettings.reset_for_test()
	get_tree().root.size = Vector2i(1280, 720)
	var packed := SCENE
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	game = _scene.game
	_unit_mirror = _scene.get_node("UnitMirror") as UnitMirror
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _spawn(cell: Vector2i, overrides := {}) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data(overrides, PLAYER), cell)
	assert_object(unit).is_not_null()   # fixture setup, not the claim under test
	return unit


func _point_at(cell: Vector2i) -> void:
	var heights: BoardHeights = game.board_heights
	_scene._pointer_cell = BoardSpace.of_cell(cell, BoardSpace.top_row_of(heights.elevation_at(cell)))


func _point_away() -> void:
	_scene._pointer_cell = BoardSpace.of_cell(Vector2i(14, 14), 0)


func _live() -> int:
	return _unit_mirror.debris().live_count()


# A unit already reconciled, hovered, and with its readout up — the state every case below starts
# from except the one that deliberately does not.
func _watched(cell := Vector2i(2, 2), overrides := {}) -> Unit:
	var unit := _spawn(cell, overrides)
	_point_at(cell)
	await _settle()
	assert_bool(_unit_mirror.bar_for(unit).visible).override_failure_message(
			"the readout never came up, so nothing below is testing what it claims").is_true()
	assert_int(_live()).override_failure_message(
			"cubes were already in the air before the case did anything").is_equal(0)
	return unit


func test_losing_health_throws_one_cube_per_point() -> void:
	var unit := await _watched()
	unit.take_damage(3)
	await _settle()

	assert_int(_live()).override_failure_message(
			"the burst is not one cube per point of HP lost").is_equal(3)


func test_a_second_hit_throws_its_own_cubes_on_top_of_the_first() -> void:
	# The diff is per FRAME, so two hits in a row must each be measured against the reading before
	# it — a baseline written once at spawn would make the second hit throw the whole total again.
	var unit := await _watched()
	unit.take_damage(3)
	await _settle()
	unit.take_damage(2)
	await _settle()

	assert_int(_live()).override_failure_message(
			"the second hit re-threw the whole loss instead of only its own").is_equal(5)


func test_health_lost_while_no_readout_is_up_throws_nothing() -> void:
	# THE BASELINE TRAP, and the ORDER here is the whole case. The readout must be up FIRST so a
	# baseline is on record, then hidden, then the unit hurt — which is the ordinary shape of play:
	# point at a unit, move the mouse away, let an AI pass hurt it, point back. A baseline that only
	# advanced while a readout was up would fire the entire hidden loss at the moment of pointing
	# back.
	#
	# Found by falsification: without the hover-first leg, `_last_hp` is never seeded at all and the
	# `.get(id, current)` default silently stands in for it — so the case passed against a mutant
	# that froze the baseline behind the visibility gate. A precondition that is never established
	# is not a precondition.
	var unit := await _watched()
	_point_away()
	await _settle()
	assert_bool(_unit_mirror.bar_for(unit).visible).override_failure_message(
			"the readout was up with nothing hovered, so this case cannot see the trap").is_false()

	unit.take_damage(4)
	await _settle()
	assert_int(_live()).override_failure_message(
			"cubes flew off a readout that was not on screen").is_equal(0)

	_point_at(unit.movement.cell)
	await _settle()
	assert_int(_live()).override_failure_message(
			"pointing at the unit fired the whole hidden loss — the baseline had gone stale"
			).is_equal(0)
	# And the readout is nonetheless correct about what it missed.
	assert_int(_unit_mirror.bar_for(unit).filled_block_count()).is_equal(unit.get_current_hp())


func test_a_death_detonates_the_whole_grid_red_cubes_included() -> void:
	# Round 2 (dev: "On a killing hit, even the red blocks should fly away"). The LOST sockets go too,
	# so the count is max HP rather than what was still standing — which is why the fixture wounds
	# the unit first: with a full grid the two answers are identical and the case proves nothing.
	var unit := await _watched()
	unit.take_damage(2)
	await _settle()
	var standing := _unit_mirror.bar_for(unit).filled_block_count()
	assert_int(standing).override_failure_message(
			"the fixture did not wound the unit, so standing and max HP agree and this cannot tell "
			+ "a whole-grid detonation from a standing-only one").is_equal(unit.get_max_hp() - 2)
	var already_flying := _live()
	# Read BEFORE the kill: die() queue_free()s, and a typed read off a freed Unit dies on the
	# type-check rather than returning null (#149's rule, one shelf along).
	var sockets := unit.get_max_hp()

	unit.die()
	await _settle()

	# die() emits and queue_free()s in the same frame, and reconcile skips a unit already queued for
	# deletion — so no poll can ever see this and the count is what proves the signal is wired.
	assert_int(_live() - already_flying).override_failure_message(
			"a death did not throw every cube in the grid — the lost ones stayed behind"
			).is_equal(sockets)


func test_a_multi_cube_burst_marches_out_rather_than_leaving_all_at_once() -> void:
	# Round 2 (dev: "march through the bricks that blast out, from start to finish"). A waiting cube
	# is LIVE but has not LAUNCHED — it sits in its own socket — which is the distinction the two
	# counts draw, and the only headless-visible form of the rhythm.
	_unit_mirror.block_burst_stagger = 5.0   # fixture: long enough that the march cannot finish
	var unit := await _watched()
	unit.take_damage(4)
	await _settle()

	var debris := _unit_mirror.debris()
	assert_int(debris.live_count()).override_failure_message(
			"the hit did not throw one cube per point").is_equal(4)
	assert_int(debris.launched_count()).override_failure_message(
			"every cube launched at once, so nothing is marching").is_less(4)
	assert_int(debris.launched_count()).override_failure_message(
			"nothing launched at all, so the burst is stalled rather than staggered"
			).is_greater(0)


func test_the_march_starts_at_the_LAST_socket_not_the_first() -> void:
	# Dev, 2026-08-22: "the cubes stagger from the wrong side, inner to outer. The top right is the
	# start of the healthbar, that's where they should start bursting from. When we hit the second
	# row, right side again." The grid fills bottom-up and left-to-right, so the highest socket index
	# IS the top right — walking the lost run backwards gives top row right-to-left then the row
	# below, with no second rule to keep in step.
	_unit_mirror.block_burst_stagger = 5.0   # fixture: nothing else can launch and confuse the read
	var unit := await _watched()
	var bar := _unit_mirror.bar_for(unit)
	var highest := unit.get_current_hp() - 1        # the last standing socket, before the hit
	var top_right := bar.block_world_position(highest)

	unit.take_damage(3)
	await _settle()

	# Slots fill in launch order, so slot 0 is the first cube out.
	var debris := _unit_mirror.debris()
	assert_vector(debris.origin_of(0)).override_failure_message(
			"the first cube out did not come from the last socket — the march runs inner-to-outer"
			).is_equal_approx(top_right, Vector3.ONE * 0.001)


func test_the_heal_pop_travels_even_with_the_dent_dialled_to_zero() -> void:
	# The round-1 bug, as a property. The pop borrowed the RECESS as its travel distance, so with the
	# dent at 0 it had none — the dev saw an instant pop whatever he set the time to. The pop now has
	# its own amplitude, and this is the configuration that could not animate before.
	_unit_mirror.hp_block_recess_texels = 0.0
	_unit_mirror.block_pop_time = 5.0        # fixture: hold it mid-flight so a frame count can see it
	var unit := await _watched()
	unit.take_damage(4)
	await _settle()
	unit.heal(2)
	await _settle()

	var bar := _unit_mirror.bar_for(unit)
	# The cube that is rising must sit BEHIND one that is simply standing. Index 0 is never in the
	# pop's run, so it is the control; comparing two live sockets means no value is pinned.
	var rising := unit.get_current_hp() - 1
	assert_float(bar.block_world_position(rising).z).override_failure_message(
			"the restored cube is already at its resting depth, so the pop covered no distance"
			).is_less(bar.block_world_position(0).z)


func test_a_heal_FILLS_IN_from_the_lowest_socket_of_its_run() -> void:
	# "They should fill in in reverse order that they are knocked out from attacks" (dev, 2026-08-22).
	# The burst leaves DESCENDING, so the LOWEST socket of a run is the last one knocked out — and
	# reversing that makes it the first one back.
	#
	# Read as a SCHEDULE rather than as a race: the burst's twin case can ask which slot launched
	# first because a slot IS its launch order, but a healed cube never leaves its socket, so the
	# equivalent clock-free question is which one waits least. Chasing the depths instead would mean
	# two idle frames deciding how far a tween had got.
	_unit_mirror.hp_pop_stagger = 5.0   # fixture: far enough apart that no two delays can be confused
	var unit := await _watched()
	unit.take_damage(4)
	await _settle()
	unit.heal(3)
	await _settle()

	var bar := _unit_mirror.bar_for(unit)
	var shown := unit.get_current_hp()
	var first := shown - 3   # the run's lowest socket: the last one that left
	assert_float(bar.pop_delay_of(first)).override_failure_message(
			"the run's lowest socket does not go first, so the fill is not the burst reversed"
			).is_equal(0.0)
	for i in 2:
		var earlier := first + i
		assert_float(bar.pop_delay_of(earlier)).override_failure_message(
				"socket %d waits at least as long as the one above it — the run fills out of order" % earlier
				).is_less(bar.pop_delay_of(earlier + 1))


func test_a_thrown_cube_outlives_the_readout_it_fell_off() -> void:
	# The reason debris lives under UnitMirror in world space rather than under a readout: a readout
	# hides the instant the pointer moves, and a cube parented to one would wink out mid-air.
	var unit := await _watched()
	unit.take_damage(3)
	await _settle()
	assert_int(_live()).is_equal(3)

	_point_away()
	await _settle()
	assert_bool(_unit_mirror.bar_for(unit).visible).override_failure_message(
			"the readout stayed up, so this case never took the thing away").is_false()
	assert_int(_live()).override_failure_message(
			"the cubes vanished with the readout they came from").is_equal(3)


func test_the_cubes_that_leave_come_off_the_top_of_the_grid() -> void:
	# The grid fills bottom-up, so losses show along the TOP row — which is where a cube has
	# clearance to leave from, and what makes a partly-full grid read as a stack rather than a
	# scatter. Asserted through the sockets rather than the thrown cubes, since the socket is what
	# the drain direction is a fact about.
	# The shared fixture unit is MHP 10, which is exactly one row at the shipped ten-per-row — so
	# this case authors a bigger one rather than leaning on a value it does not own. Fixture stats,
	# never a claim about shipped content.
	var per_row: int = _unit_mirror.hp_blocks_per_row
	var unit := await _watched(Vector2i(2, 2), {Stats.Stat.MHP: per_row + 4})
	var bar := _unit_mirror.bar_for(unit)
	assert_int(unit.get_max_hp()).override_failure_message(
			"the fixture unit still fits in one row, so there is no drain direction to check"
			).is_greater(per_row)

	unit.take_damage(2)
	await _settle()

	# block_is_FILLED, not block_is_proud: this case is about WHICH sockets emptied, and the depth
	# reading cannot answer that once the recess is dialled to 0 — which is now the default.
	assert_bool(bar.block_is_filled(0)).override_failure_message(
			"the bottom of the grid emptied first").is_true()
	assert_bool(bar.block_is_filled(unit.get_max_hp() - 1)).override_failure_message(
			"the last socket is still filled, so the grid did not drain from the top").is_false()
	# And the top row really is above the bottom one, or "drains from the top" means nothing.
	assert_float(bar.block_world_position(per_row).y).override_failure_message(
			"the rows are not stacked, so there is no top for cubes to come off"
			).is_greater(bar.block_world_position(0).y)


func test_a_heal_puts_its_cubes_back_rather_than_throwing_them() -> void:
	var unit := await _watched()
	unit.take_damage(4)
	await _settle()
	var thrown := _live()
	assert_int(thrown).is_equal(4)

	unit.heal(2)
	await _settle()

	assert_int(_live()).override_failure_message(
			"healing threw cubes, which is the one thing losing health is supposed to mean"
			).is_equal(thrown)
	assert_int(_unit_mirror.bar_for(unit).filled_block_count()).is_equal(unit.get_current_hp())
