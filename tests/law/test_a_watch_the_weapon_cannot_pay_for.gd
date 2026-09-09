# CAN THE WEAPON STILL PAY? (#810's original question, answered at last.) A watch whose weapon can
# no longer fire the stamped attack does not fire and is not drawn -- the REFUSE arm of the ticket's
# own three-way fork, settled 2026-09-09 over "fire anyway" and "fire downgraded", because a
# footprint promising a shot the weapon cannot pay for is a lie either way (Law #2).
#
# Parts 1 and 2 closed the dry-watch hole by ARGUING that nothing can change a weapon's fireability
# while a watch stands. That argument is true today and enforced nowhere; the first family gating
# firing on a timer-decayed resource would have re-opened it silently. These cases pin the check
# that replaced the argument, so no future content can regress it.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

const WATCHED: Array[Vector2i] = [Vector2i(2, 0)]

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


# A Carbine-shaped weapon: its watch attack REQUIRES and CONSUMES a round, exactly as
# Resources/WeaponAttacks/Overwatch.tres does.
func _metered_carbine() -> CarbineWeaponInstance:
	var watch_attack := WeaponAttackData.new()
	watch_attack.display_name = "Overwatch"
	watch_attack.power = 4
	watch_attack.requires_readiness = true
	watch_attack.consumes_readiness = true
	P.point(watch_attack, 1, 1)
	var main := WeaponAttackData.new()
	main.display_name = "Shot"
	main.power = 4
	P.point(main, 1, 1)
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CARBINE
	t.main_attack = main
	t.extra_attacks = [watch_attack] as Array[WeaponAttackData]
	return WeaponInstance.make(t) as CarbineWeaponInstance


# A watcher off the walking row, holding a metered carbine and watching WATCHED.
func _watcher(rounds: int) -> Unit:
	var unit := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 1), {Stats.Stat.STR: 4, Stats.Stat.MHP: 200}, false)
	var weapon := _metered_carbine()
	unit.equipped_weapon = weapon
	weapon.shots_remaining = rounds
	unit.arm_watch(unit.movement.cell, WATCHED[0], WATCHED, weapon.template.extra_attacks[0])
	return unit


func _walker() -> Unit:
	return H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 200}, false)


func _walk(unit: Unit) -> MoveAction:
	var path: Array[Vector2i] = []
	for x in range(unit.movement.cell.x, 5):
		path.append(Vector2i(x, 0))
	var move := MoveAction.new()
	move.init(unit, path, null)
	return move


func _board_with(units_in: Array) -> BoardContext:
	var units: Array[Unit] = []
	units.assign(units_in)
	return BoardContext.new(_sm.grid, units, _sm)


func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for shot in plan.watch_shots:
		shot.volley = empty


# THE HEADLINE, and #810's opening sentence: "a dry Carbine's standing watch still fires."
func test_a_dry_weapons_watch_does_not_fire() -> void:
	var watcher := _watcher(0)
	var walker := _walker()
	walker.squad._queue_action(_walk(walker))

	var plan := _sm.resolve_plan(walker.squad, _board_with([watcher, walker]))
	_break_volleys(plan)

	assert_array(plan.watch_shots).is_empty()


# The baseline it loses. Same board, one round in the magazine.
func test_a_loaded_weapons_watch_fires() -> void:
	var watcher := _watcher(1)
	var walker := _walker()
	walker.squad._queue_action(_walk(walker))

	var plan := _sm.resolve_plan(walker.squad, _board_with([watcher, walker]))
	_break_volleys(plan)

	assert_int(plan.watch_shots.size()).is_equal(1)


# LAW #2's half, and the reason this clause lives on is_armed() rather than in the resolver's
# trigger filter: a filter that refused the shot would leave the board drawing a threat that can
# never land.
func test_a_dry_weapons_watch_is_not_drawn() -> void:
	var loaded := _watcher(1)
	_sm.overlay_manager.redraw_watch_marks([loaded] as Array[Unit], null)
	assert_array(_sm.overlay_manager.watch_cells).contains([WATCHED[0]])   # the baseline

	var dry := _watcher(0)
	_sm.overlay_manager.redraw_watch_marks([dry] as Array[Unit], null)
	assert_array(_sm.overlay_manager.watch_cells).is_empty()


# The predicate is "can it fire NOW", not "was it ever dry": reloading brings the watch back. Without
# this the clause could read `shots_remaining == MAGAZINE_SIZE` and every other case would pass.
func test_reloading_brings_the_watch_back() -> void:
	var watcher := _watcher(0)
	assert_bool(watcher.watch.is_armed()).is_false()

	(watcher.get_equipped_weapon() as CarbineWeaponInstance).reload(watcher)

	assert_bool(watcher.watch.is_armed()).is_true()


# THE DOUBLE PENALTY, ruled deliberately: a watch that goes dry neither fires nor hands the reaction
# back. is_standing_watch reads past every ending -- spent, cancelled, and now unpayable -- because
# the cost is one ROUND, not one live watch.
func test_a_dry_watch_still_costs_the_reaction() -> void:
	var watcher := _watcher(0)

	assert_bool(watcher.watch.is_armed()).is_false()
	assert_bool(watcher.is_standing_watch()).is_true()
