# A WATCH BREAKS ON CONTACT (#810, dev 2026-09-09, docs/design/standing-reactions.md). Overwatch's
# cost is that it is fragile as well as exclusive: the watcher taking a blow ends the watch.
#
# Driven through the real SquadManager.resolve_plan with a real queue, because every claim here is
# about WHEN something happens relative to something else -- a test handed a pre-built plan cannot
# see any of it. The headline case is the ORDERING one: hit the watcher, THEN cross the footprint.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

# The watched column, on row 0 -- the row the walker crosses.
# The walk is row 0 from x=0 to x=4; every footprint in this suite is passed in per case, because
# what these cases are about is one watch's blast reaching another watcher.

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _main_of(unit: Unit) -> WeaponAttackData:
	return (unit.get_equipped_weapon() as WeaponInstance).template.main_attack



# A watcher standing on `cell`, watching exactly `cells`. The footprint is passed in because these
# cases are entirely about one watch's blast reaching another watcher.
func _watcher_at(cell: Vector2i, cells: Array) -> Unit:
	var unit := H.spawn_solo(self, _sm, ENEMY, cell, {Stats.Stat.STR: 4}, true, 6)
	var footprint: Array[Vector2i] = []
	footprint.assign(cells)
	unit.arm_watch(cell, footprint[0], footprint, _main_of(unit))
	return unit


func _walker(hp := 200) -> Unit:
	return H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: hp}, false)


# Did this unit's watch fire in this pass?
func _fired(plan: ResolvedPlan, watcher: Unit) -> bool:
	for shot in plan.watch_shots:
		if shot.actor == watcher:
			return true
	return false

# A straight walk along row 0, from wherever the unit stands to x = 4.
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


# Volley siblings link into a shared self-referential array (#35) -- break them so a derived plan
# does not leak after the test.
func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for ctr in plan.counters:
		ctr.volley = empty
	for shot in plan.watch_shots:
		shot.volley = empty


# THE HEADLINE, and the ordering the pass actually has: the MOVE phase resolves as a block ahead of
# every attack, so a queued blow can never precede a queued walk. What CAN is another watch's shot.
#
# Watcher A's footprint covers the walker's first step AND the cell watcher B stands on, and A's
# attack hits allies -- so A's volley catches B, breaking B's watch mid-walk, before the walker
# reaches the cell B was watching. Everything else in this suite passes if the cancel is applied at
# execution instead of threaded through the pass; only this case can see the difference.
func test_a_watch_shot_breaks_a_second_watch_before_the_walker_reaches_it() -> void:
	var walker := _walker()
	var a := _watcher_at(Vector2i(1, 1), [Vector2i(1, 0), Vector2i(2, 1)])
	_main_of(a).hits_allies = true          # A's volley catches B, who is standing in its footprint
	var b := _watcher_at(Vector2i(2, 1), [Vector2i(3, 0)])
	walker.squad._queue_action(_walk(walker))

	var plan := _sm.resolve_plan(walker.squad, _board_with([walker, a, b]))
	_break_volleys(plan)

	assert_bool(_fired(plan, a)).is_true()    # A shot, and its blast broke B's watch...
	assert_bool(_fired(plan, b)).is_false()   # ...so B never fires at step (3, 0)


# The baseline the case above loses. Identical board, except A's blast does NOT catch its ally: B is
# never hit, so B's watch survives the walk and takes its own shot. Without this, a fixture where B
# simply never triggers would prove nothing.
func test_the_second_watch_fires_when_the_first_blast_spares_it() -> void:
	var walker := _walker()
	var a := _watcher_at(Vector2i(1, 1), [Vector2i(1, 0), Vector2i(2, 1)])
	_main_of(a).hits_allies = false         # the only difference from the case above
	var b := _watcher_at(Vector2i(2, 1), [Vector2i(3, 0)])
	walker.squad._queue_action(_walk(walker))

	var plan := _sm.resolve_plan(walker.squad, _board_with([walker, a, b]))
	_break_volleys(plan)

	assert_bool(_fired(plan, a)).is_true()
	assert_bool(_fired(plan, b)).is_true()


# A HEAL IS THE ONE LANDED HIT THAT DOES NOT BREAK A WATCH, and the gate is POSITION -- the cancel
# sits below _resolve_one's heal short-circuit -- rather than hostility. can_target would be the
# WRONG gate: a player-aimed heal keeps its enemy splash (C8), so an enemy watcher caught in one
# would have had its watch healed off.
func test_a_heal_that_lands_on_a_watcher_leaves_the_watch_alone() -> void:
	var watcher := _watcher_at(Vector2i(2, 1), [Vector2i(3, 0)])
	var medic := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 2), {}, true, 6)
	_main_of(medic).heals = true
	_main_of(medic).hits_allies = true
	watcher.take_damage(3)

	medic.squad._queue_action(H.stamped_attack(medic, watcher))
	var plan := _sm.resolve_plan(medic.squad, _board_with([watcher, medic]))
	_break_volleys(plan)

	assert_int(plan.attacks[0].resolved.heal_amount).is_greater(0)   # it really landed
	assert_bool(plan.attacks[0].resolved.cancels_watch).is_false()
	assert_bool(plan.watches[0].cancelled).is_false()


# THE STAMP, and the door execution pushes. The resolver decides; nothing is marked live until the
# outcome is applied.
func test_the_hit_stamps_the_outcome_and_marks_the_pass_copy() -> void:
	var watcher := _watcher_at(Vector2i(2, 1), [Vector2i(3, 0)])
	var gunner := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 2), {}, true, 6)

	gunner.squad._queue_action(H.stamped_attack(gunner, watcher))
	var plan := _sm.resolve_plan(gunner.squad, _board_with([watcher, gunner]))
	_break_volleys(plan)

	assert_bool(plan.attacks[0].resolved.cancels_watch).is_true()
	assert_bool(plan.watches[0].cancelled).is_true()
	assert_bool(watcher.watch.cancelled).is_false()   # the LIVE watch is execution's business


# FABLE'S FINDING, MADE EXECUTABLE (#810 part 1's own constraint): the cancel MARKS, it never
# lapses. A nulled watch would read as "never watching" and hand the reaction straight back in the
# next squad's pass of the same enemy phase -- the penalty refunding itself.
func test_a_broken_watch_still_costs_the_reaction() -> void:
	var watcher := _watcher_at(Vector2i(2, 1), [Vector2i(3, 0)])

	watcher.cancel_watch()

	assert_bool(watcher.watch.cancelled).is_true()
	assert_bool(watcher.watch.is_armed()).is_false()   # it cannot fire...
	assert_bool(watcher.is_standing_watch()).is_true() # ...and it still costs the reaction


# The save seam (#87). A save taken after the blow must not hand the watch back on load.
func test_a_broken_watch_round_trips_broken() -> void:
	var watcher := _watcher_at(Vector2i(2, 1), [Vector2i(3, 0)])
	# The capture indexes into overwatch_attacks() (#590), so the armed attack has to be IN that
	# view or the snapshot silently keeps no watch at all -- which is what this assertion caught.
	_main_of(watcher).can_overwatch = true
	watcher.cancel_watch()

	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(watcher)

	assert_bool(entry.watch_cancelled).is_true()
