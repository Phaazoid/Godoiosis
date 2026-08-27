# Overwatch's TRIGGER (#413, docs/design/standing-reactions.md) — driven through the real
# SquadManager.resolve_plan with a real queue, because every claim here is about WHEN something
# happens and a test handed a pre-built plan cannot see any of it.
#
# The one sentence the whole suite is about: WATCHES LISTEN TO ENTRIES. Standing in the footprint
# when the watch arms is not entering; walking in is; walking out is not; and a watch absorbs
# exactly one trigger and then lapses when its owner's turn comes round again.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

# The watched column: two cells, side by side, so two movers can each enter their own.
const WATCHED: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 1)]

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _main_of(unit: Unit) -> WeaponAttackData:
	return (unit.get_equipped_weapon() as WeaponInstance).template.main_attack


# A watcher standing off to the side with a live watch over WATCHED. Its own cell is the anchor.
func _watcher(cell := Vector2i(2, 5), power := 6) -> Unit:
	var unit := H.spawn_solo(self, _sm, ENEMY, cell, {Stats.Stat.STR: 4}, true, power)
	unit.arm_watch(cell, WATCHED[0], WATCHED, _main_of(unit))
	return unit


func _walker(faction: Team.Faction, row := 0, hp := 60) -> Unit:
	return H.spawn_solo(self, _sm, faction, Vector2i(0, row), {Stats.Stat.MHP: hp}, false)


# A straight walk along one row, from wherever the unit stands to x = 4 — through WATCHED[row].
func _walk(unit: Unit) -> MoveAction:
	var path: Array[Vector2i] = []
	for x in range(unit.movement.cell.x, 5):
		path.append(Vector2i(x, unit.movement.cell.y))
	var move := MoveAction.new()
	move.init(unit, path, null)
	return move


func _board_with(units_in: Array) -> BoardContext:
	var units: Array[Unit] = []
	units.assign(units_in)
	return BoardContext.new(_sm.grid, units, _sm)


# Volley siblings link into a shared self-referential array (#35) — break them so a derived plan
# does not leak after the test. Watch shots are volleys like any other.
func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for ctr in plan.counters:
		ctr.volley = empty
	for shot in plan.watch_shots:
		shot.volley = empty


func test_walking_into_a_watched_cell_takes_the_shot() -> void:
	var watcher := _watcher()
	var crosser := _walker(PLAYER)
	crosser.squad._queue_action(_walk(crosser))

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser]))

	assert_int(plan.watch_shots.size()).is_equal(1)
	assert_object(plan.watch_shots[0].actor).is_same(watcher)
	assert_object(plan.watch_shots[0].target).is_same(crosser)
	assert_int(plan.watch_shots[0].resolved.damage).is_greater(0)
	_break_volleys(plan)


# The trigger is ENTRY. A unit that was already parked in the footprint when the watch armed is not
# entering anything, and a watch that fired on arming would be a different mechanic (a mine).
func test_standing_in_the_footprint_is_not_entering_it() -> void:
	var watcher := _watcher()
	var squatter := H.spawn_solo(self, _sm, PLAYER, WATCHED[0], {Stats.Stat.MHP: 60}, false)
	var hold := MoveAction.new()
	hold.init_hold_position(squatter, null)
	squatter.squad._queue_action(hold)

	var plan := _sm.resolve_plan(squatter.squad, _board_with([watcher, squatter]))

	assert_array(plan.watch_shots).is_empty()


# Stepping OUT is not an entry either. The unit's first path cell is where it already stands, which
# is the same fact the case above states about a unit that never moves at all — and the reason the
# walk starts at path[1] rather than path[0].
func test_stepping_out_of_a_watched_cell_is_not_an_entry() -> void:
	var watcher := _watcher()
	var leaver := H.spawn_solo(self, _sm, PLAYER, WATCHED[0], {Stats.Stat.MHP: 60}, false)
	var path: Array[Vector2i] = [WATCHED[0], Vector2i(3, 0), Vector2i(4, 0)]
	var move := MoveAction.new()
	move.init(leaver, path, null)
	leaver.squad._queue_action(move)

	var plan := _sm.resolve_plan(leaver.squad, _board_with([watcher, leaver]))

	assert_array(plan.watch_shots).is_empty()


# But moving from one watched cell to ANOTHER is an entry — there is no safe repositioning inside a
# watched line.
func test_moving_between_two_watched_cells_is_an_entry() -> void:
	var watcher := _watcher()
	var shuffler := H.spawn_solo(self, _sm, PLAYER, WATCHED[0], {Stats.Stat.MHP: 60}, false)
	var path: Array[Vector2i] = [WATCHED[0], WATCHED[1]]
	var move := MoveAction.new()
	move.init(shuffler, path, null)
	shuffler.squad._queue_action(move)

	var plan := _sm.resolve_plan(shuffler.squad, _board_with([watcher, shuffler]))

	assert_int(plan.watch_shots.size()).is_equal(1)
	assert_object(plan.watch_shots[0].target).is_same(shuffler)
	_break_volleys(plan)


# Allies never trigger a watch — the whole mechanic is aimed at the other side.
func test_an_ally_of_the_watcher_never_triggers_it() -> void:
	var watcher := _watcher()
	var friend := _walker(ENEMY)
	friend.squad._queue_action(_walk(friend))

	var plan := _sm.resolve_plan(friend.squad, _board_with([watcher, friend]))

	assert_array(plan.watch_shots).is_empty()


# The accepted cut: you cannot spend a watch by throwing a corpse through it.
func test_a_downed_body_never_triggers_it() -> void:
	var watcher := _watcher()
	var body := _walker(PLAYER)
	body.lifecycle_state = Unit.LifecycleState.DOWNED
	body.squad._queue_action(_walk(body))

	var plan := _sm.resolve_plan(body.squad, _board_with([watcher, body]))

	assert_array(plan.watch_shots).is_empty()


# Fires once, then spent: the second crosser walks through the same line untouched.
func test_a_watch_absorbs_exactly_one_trigger() -> void:
	var watcher := _watcher()
	var first := _walker(PLAYER, 0)
	var second := _walker(PLAYER, 1)
	_sm.join_squad(second, first.squad)
	first.squad._queue_action(_walk(first))
	first.squad._queue_action(_walk(second))

	var plan := _sm.resolve_plan(first.squad, _board_with([watcher, first, second]))

	assert_int(plan.watch_shots.size()).is_equal(1)
	assert_object(plan.watch_shots[0].target).is_same(first)
	_break_volleys(plan)


# The ANCHOR rule: the footprint is geometry aimed from one cell, so a watcher who is not standing
# on that cell has no watch left, however it happened.
func test_a_watcher_off_its_anchor_has_no_watch() -> void:
	var watcher := _watcher()
	watcher.movement.cell = Vector2i(3, 5)   # shoved, hauled, whatever moved it
	var crosser := _walker(PLAYER)
	crosser.squad._queue_action(_walk(crosser))

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser]))

	assert_array(plan.watch_shots).is_empty()


# Untriggered, it lapses when its owner's faction comes round again — the shared standing-reaction
# lifetime, and the same tick pass that lapses a Guard.
func test_an_untriggered_watch_lapses_at_its_owners_turn_start() -> void:
	var watcher := _watcher()
	assert_object(watcher.watch).is_not_null()

	watcher.lapse_watch()

	assert_object(watcher.watch).is_null()


# A crosser the shot DOWNS stops where it was hit — lifecycle, not a new rule — and the walk it
# actually plays back is the prefix, so the preview and the playback cannot disagree.
func test_a_crosser_the_shot_downs_stops_at_the_crossing_cell() -> void:
	var watcher := _watcher(Vector2i(2, 5), 40)   # enough power to put a 6 HP walker down
	var crosser := _walker(PLAYER, 0, 6)
	var move := _walk(crosser)
	crosser.squad._queue_action(move)

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser]))

	assert_int(plan.watch_shots.size()).is_equal(1)
	assert_bool(move.was_halted()).is_true()
	assert_that(move.walked_path().back()).is_equal(WATCHED[0])
	assert_that(move.get_destination()).is_equal(WATCHED[0])
	_break_volleys(plan)


# Law #2's half of the mechanic, and it lives in this suite because it is the same claim from the
# other side: a queued move that would cross a standing watch shows the shot it triggers IMMEDIATELY,
# on its own row. Deliberately the crossing MOVE's row rather than a section of its own — dragging
# that row is what changes who eats the shot, so the feedback has to be on the thing being dragged.
func test_the_crossing_move_row_says_what_it_walks_into() -> void:
	var watcher := _watcher()
	var crosser := _walker(PLAYER)
	crosser.squad._queue_action(_walk(crosser))

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser]))
	var entries := ActionQueueDisplayEntry.build_for(crosser.squad, plan)

	var move_notes: Array[String] = []
	for entry in entries:
		if entry.entry_type == ActionQueueDisplayEntry.EntryType.ACTION \
				and entry.action.action_type == BaseAction.ActionType.MOVE:
			move_notes.append_array(entry.annotations)
	assert_int(move_notes.size()).is_equal(1)
	# The number is the resolve's, not a re-derivation -- what the row says and what the pass does
	# are one answer (R3/R8).
	assert_str(move_notes[0]).contains(str(plan.watch_shots[0].resolved.damage))
	assert_str(move_notes[0]).contains(watcher.get_unit_name())
	_break_volleys(plan)


# A derived attack is never counter-bait: the shot is a reaction, and its victim's answer is the
# rest of their own turn. Structural rather than filtered — watch shots are not in plan.attacks,
# which is the only list calculate_reactions_for_squad reads.
func test_a_triggered_shot_draws_no_counter() -> void:
	var watcher := _watcher()
	var crosser := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 60}, true, 5)
	crosser.squad._queue_action(_walk(crosser))

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser]))

	assert_int(plan.watch_shots.size()).is_equal(1)
	assert_array(plan.attacks).is_empty()
	assert_array(plan.counters).is_empty()
	_break_volleys(plan)
