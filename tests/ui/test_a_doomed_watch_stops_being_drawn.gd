# THE PREVIEW HALF of #810's cancel (Law #2, the chip cannot lie): a queued blow that will break a
# standing watch must stop drawing its footprint NOW, not when it lands. The live watch still reads
# armed at that moment -- the pass's copy is the only thing that knows -- so the markup has to take
# the plan.
#
# Asserts OverlayManager.watch_cells, THE store both projections read (2D sprites and OverlayMirror's
# markers), so this covers the 3D view too without a second fixture (#292 parity by construction).
#
# THE UNTESTED INCH, stated rather than faked: game.refresh_watch_markers(plan) is the call site that
# feeds this, and it sits in refresh_action_queue beside refresh_guard_markers. That line is game.gd
# wiring with no headless seam -- the same gap #450 declared for the guard markers.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

const WATCHED: Array[Vector2i] = [Vector2i(2, 0)]

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _main_of(unit: Unit) -> WeaponAttackData:
	return (unit.get_equipped_weapon() as WeaponInstance).template.main_attack


func _watcher(cell := Vector2i(2, 1)) -> Unit:
	var unit := H.spawn_solo(self, _sm, ENEMY, cell, {Stats.Stat.STR: 4}, true, 6)
	unit.arm_watch(cell, WATCHED[0], WATCHED, _main_of(unit))
	return unit


func _board_with(units_in: Array) -> BoardContext:
	var units: Array[Unit] = []
	units.assign(units_in)
	return BoardContext.new(_sm.grid, units, _sm)


func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty


# The baseline: an untouched watch draws its footprint.
func test_an_untouched_watch_draws_its_footprint() -> void:
	var watcher := _watcher()

	_sm.overlay_manager.redraw_watch_marks([watcher] as Array[Unit], null)

	assert_array(_sm.overlay_manager.watch_cells).contains([WATCHED[0]])


# The rule: with a blow queued on the watcher, the SAME live watch stops being drawn.
func test_a_watch_this_plan_will_break_stops_being_drawn() -> void:
	var watcher := _watcher()
	var gunner := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 2), {}, true, 6)
	gunner.squad._queue_action(H.stamped_attack(gunner, watcher))

	var plan := _sm.resolve_plan(gunner.squad, _board_with([watcher, gunner]))
	_break_volleys(plan)

	assert_bool(watcher.watch.is_armed()).is_true()   # the LIVE watch is untouched...
	_sm.overlay_manager.redraw_watch_marks([watcher, gunner] as Array[Unit], plan)
	assert_array(_sm.overlay_manager.watch_cells).is_empty()   # ...and the board says so anyway


# Without the plan there is nothing to know, and the live flags are the whole answer. That is the
# board-load and turn-start call site, and it must not go blank just because a plan exists elsewhere.
func test_without_a_plan_the_live_watch_is_the_answer() -> void:
	var watcher := _watcher()
	var gunner := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 2), {}, true, 6)
	gunner.squad._queue_action(H.stamped_attack(gunner, watcher))
	var plan := _sm.resolve_plan(gunner.squad, _board_with([watcher, gunner]))
	_break_volleys(plan)

	_sm.overlay_manager.redraw_watch_marks([watcher, gunner] as Array[Unit], null)

	assert_array(_sm.overlay_manager.watch_cells).contains([WATCHED[0]])
