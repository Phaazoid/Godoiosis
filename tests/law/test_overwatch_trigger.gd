# Overwatch's TRIGGER (#413, docs/design/standing-reactions.md) — driven through the real
# SquadManager.resolve_plan with a real queue, because every claim here is about WHEN something
# happens and a test handed a pre-built plan cannot see any of it.
#
# The one sentence the whole suite is about: WATCHES LISTEN TO ENTRIES. Standing in the footprint
# when the watch arms is not entering; walking in is; walking out is not; and a watch absorbs
# exactly one trigger and then lapses when its owner's turn comes round again.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

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


# The trigger is ENTRY, and occupancy is a trigger at the ARM MOMENT ALONE (#1003). A watch left
# STANDING from an earlier pass goes on waiting for an entry however long somebody sits in it —
# re-asking every resolve would make it a mine that re-fires on every repaint.
#
# The name changed with the rule: it used to say "standing in the footprint is not entering it",
# which is still true of an entry and no longer the whole claim.
func test_a_standing_watch_does_not_fire_on_a_squatter() -> void:
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
# on a row of its own indented under that move. Deliberately hung off the crossing MOVE rather than
# given a section — dragging that row is what changes who eats the shot, so the feedback has to be
# on the thing being dragged.
#
# It asserted on `entry.annotations` until #592 and PASSED for the mechanic's whole life, while the
# note was being written into a Label that has been `visible = false` since the panel's first
# version. The data was always right; nobody asked whether it was DRAWN. That question is
# tests/ui/test_watch_note_reaches_the_panel.gd's, on the real scene — this one stays the
# data-layer claim it always was, now in the shape the panel actually renders.
func test_the_crossing_move_row_says_what_it_walks_into() -> void:
	var watcher := _watcher()
	var crosser := _walker(PLAYER)
	crosser.squad._queue_action(_walk(crosser))

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser]))
	var entries := ActionQueueDisplayEntry.build_for(crosser.squad, plan)

	var derived: Array[BaseAction] = []
	for entry in entries:
		if entry.entry_type == ActionQueueDisplayEntry.EntryType.ACTION and entry.indent_level > 0:
			derived.append(entry.action)
	assert_int(derived.size()).is_equal(1)
	# The row carries the resolve's own shot, not a re-derivation -- what the row shows and what the
	# pass does are one answer (R3/R8), which is also what lets it draw the watcher and the victim.
	assert_object(derived[0]).is_same(plan.watch_shots[0])
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


# --- WHEN the shot plays (#567) ------------------------------------------------------------
#
# The resolve records the MOMENT as well as the outcome, because playback cannot recover it: a
# crosser who walks on leaves no trace of where it was hit, and resolved_stop_index only answers
# the case where the shot STOPPED them. Everything below is about that one recorded fact.

func test_a_triggered_shot_records_the_walk_and_the_step_it_fired_at() -> void:
	var watcher := _watcher()
	var crosser := _walker(PLAYER)
	var move := _walk(crosser)
	crosser.squad._queue_action(move)

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser]))

	assert_int(plan.watch_shots.size()).is_equal(1)
	var shot: AttackAction = plan.watch_shots[0]
	assert_object(shot.triggered_during).override_failure_message(
			"the shot does not name the walk it interrupts, so playback has no walk to halt") \
		.is_same(move)
	assert_vector(move.path[shot.triggered_at_step]).override_failure_message(
			"the recorded step is not the cell the shot was fired at") \
		.is_equal(WATCHED[0])
	# ...and the crosser walked ON, so the step is the only record of the moment there is.
	assert_bool(move.was_halted()).is_false()
	_break_volleys(plan)


# The SHOVE combo's shot has no step to halt: the blow has already landed, and the answer follows
# it. Before #567 every triggered shot played in one batch ahead of the attacks, so this one fired
# before the mace that threw them into it.
func test_a_shove_triggered_shot_plays_after_the_volley_that_threw_them() -> void:
	var watcher := _watcher()
	var shover := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), {Stats.Stat.STR: 4}, true, 4)
	var victim := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.MHP: 60}, false)
	(shover.get_equipped_weapon() as WeaponInstance).template.main_attack.knockback = 1
	shover.squad._queue_action(H.stamped_attack(shover, victim))

	var plan := _sm.resolve_plan(shover.squad, _board_with([watcher, shover, victim]))

	assert_int(plan.attacks.size()).is_equal(1)
	assert_int(plan.watch_shots.size()).override_failure_message(
			"the shove did not land the victim in the watched cell -- fixture, not mechanic") \
		.is_equal(1)
	var shot: AttackAction = plan.watch_shots[0]
	assert_object(shot.triggered_during).is_same(plan.attacks[0])
	assert_int(shot.triggered_at_step).override_failure_message(
			"a shove landing has no walk step -- it follows the volley, it does not interrupt one") \
		.is_equal(-1)
	# ...and that is what the attack phase plays: the blow, THEN the answer.
	assert_array(plan.attack_playback()).is_equal([plan.attacks[0], shot])
	assert_array(plan.mid_walk_shots()).is_empty()
	_break_volleys(plan)


# --- The watch reads the TERRAIN (#756) --------------------------------------------------------
#
# A watch is an aimed attack held in reserve, so its footprint is truncated like any other spread:
# the cells it covers are the cells the shot could actually reach. Driven through the real queue,
# because the trigger asks Watch.covers and only a resolve knows what the pass armed.

const WATCH_LINE_LENGTH := 3

# A watcher at (0,0) aiming a length-3 line EAST, queued as a real order so resolve_plan derives
# the footprint. Its weapon's main IS the line, so nothing here depends on authored content.
func _line_watcher(cell := Vector2i(0, 0), faction := ENEMY) -> Unit:
	var unit := H.spawn_solo(self, _sm, faction, cell, {Stats.Stat.STR: 4}, true, 6)
	var main := (unit.get_equipped_weapon() as WeaponInstance).template.main_attack
	P.line(main, WATCH_LINE_LENGTH)
	var watch := OverwatchAction.new()
	watch.init(unit, cell + Vector2i(1, 0), main)
	unit.squad._queue_action(watch)
	return unit


func _heights_board(units_in: Array, heights: BoardHeights) -> BoardContext:
	var units: Array[Unit] = []
	units.assign(units_in)
	return BoardContext.new(_sm.grid, units, _sm, null, null, heights)


# Take the watcher's own turn for real: the resolve stamps the footprint, execution arms it. Going
# through both is the point — the trigger reads a LIVE watch, and what makes the live one right is
# that the pass handed it its cells.
func _arm_queued_watch(watcher: Unit, board: BoardContext) -> ResolvedPlan:
	var plan := _sm.resolve_plan(watcher.squad, board)
	for action in watcher.squad.action_queue:
		action.execute()
	return plan


# A pillar one cell along the watched line: the watch covers the pillar's own cell and nothing
# behind it, so a walker who crosses BEHIND the pillar is never shot at.
func test_a_watch_covers_only_what_its_shot_can_reach() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 4)   # two levels up, one cell along the aim
	var watcher := _line_watcher()
	var crosser := H.spawn_solo(self, _sm, PLAYER, Vector2i(3, 1), {Stats.Stat.MHP: 60}, false)
	var board := _heights_board([watcher, crosser], heights)
	# ARMED BEFORE THE WALK IS QUEUED, which is the game's own sequence (a watch stands from an
	# earlier turn; the player then plans into it) and since #1003 the only one that measures an
	# ENTRY. Arming over a crosser whose walk already ENDS in the footprint is now an arm-fire --
	# the resolver reads projected cells everywhere, so the crosser is threaded at its destination
	# before it has taken a step -- and both cases here would have gone on passing while measuring it.
	_arm_queued_watch(watcher, board)
	var walk := MoveAction.new()
	walk.init(crosser, [Vector2i(3, 1), Vector2i(3, 0)], null)   # enters the far end of the line
	crosser.squad._queue_action(walk)

	var plan := _sm.resolve_plan(crosser.squad, board)

	assert_array(plan.watch_shots).override_failure_message(
			"the watch fired past a ledge its own shot cannot clear").is_empty()
	_break_volleys(plan)


# Non-vacuity twin, and the reason it is not just "the fixture never fires": the SAME walk into the
# SAME cell on flat ground takes the shot.
func test_the_same_crossing_on_flat_ground_takes_the_shot() -> void:
	var watcher := _line_watcher()
	var crosser := H.spawn_solo(self, _sm, PLAYER, Vector2i(3, 1), {Stats.Stat.MHP: 60}, false)
	var board := _heights_board([watcher, crosser], BoardHeights.new())
	_arm_queued_watch(watcher, board)   # before the walk, for the reason the case above states
	var walk := MoveAction.new()
	walk.init(crosser, [Vector2i(3, 1), Vector2i(3, 0)], null)
	crosser.squad._queue_action(walk)

	var plan := _sm.resolve_plan(crosser.squad, board)

	assert_int(plan.watch_shots.size()).is_equal(1)
	_break_volleys(plan)


# EXECUTION ARMS WHAT THE PASS STAMPED. No action can reach a board in execute(), so a watch that
# re-derived its own geometry there would arm the untruncated spread — the queue would preview one
# footprint and the live watch would hold another (Law #2).
func test_an_executed_watch_arms_the_footprint_the_resolve_stamped() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 4)
	var watcher := _line_watcher()

	var plan := _arm_queued_watch(watcher, _heights_board([watcher], heights))
	assert_int(plan.watches.size()).override_failure_message(
			"the resolve projected no watch at all, so this case measures nothing").is_equal(1)

	assert_object(watcher.watch).is_not_null()
	assert_array(watcher.watch.footprint).override_failure_message(
			"execution armed cells the resolve had already cut").contains_exactly([Vector2i(1, 0)])


# The two partitions are TOTAL and disjoint -- every shot plays exactly once. A shot that fell out
# of both would simply never be seen, and nothing else in the pass would notice.
func test_every_triggered_shot_plays_exactly_once() -> void:
	var watcher := _watcher()
	var crosser := _walker(PLAYER)
	crosser.squad._queue_action(_walk(crosser))

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser]))

	var played: Array[AttackAction] = plan.mid_walk_shots()
	for action in plan.attack_playback():
		if (action as AttackAction).is_watch_shot:
			played.append(action)
	assert_array(played).override_failure_message(
			"the mid-walk and attack-phase partitions do not add up to every shot fired") \
		.contains_exactly_in_any_order(plan.watch_shots)
	_break_volleys(plan)


# --- ARMING ONTO AN OCCUPIED CELL (#1003) --------------------------------------------------------
#
# The dev's ruling: "if someone queues up an overwatch attack on a unit that it would trigger, the
# overwatch attack should just get triggered." Occupancy at the ARM MOMENT is a second trigger
# beside entry. Every case here drives the real queue, because a pre-armed Watch handed to the
# resolver has no arm moment to measure -- which is why the rest of this suite is blind to all of it.

func test_arming_onto_an_occupied_cell_fires_on_the_spot() -> void:
	var watcher := _line_watcher()
	var squatter := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0), {Stats.Stat.MHP: 60}, false)

	var plan := _sm.resolve_plan(watcher.squad, _board_with([watcher, squatter]))

	assert_int(plan.watch_shots.size()).is_equal(1)
	assert_object(plan.watch_shots[0].actor).is_same(watcher)
	assert_object(plan.watch_shots[0].target).is_same(squatter)
	assert_int(plan.watch_shots[0].resolved.damage).is_greater(0)
	_break_volleys(plan)


# ...and it is THE WATCH BEING ARMED that fires, never whichever armed watch happens to cover the
# cell first. The seed is scoped to one watch for exactly this: _watch_triggered_by searches the
# whole list in ARM ORDER, so an older standing watch would eat the trigger and a unit the player
# never commanded would take the shot the main action was spent on.
func test_an_older_watch_over_the_same_cell_does_not_eat_the_arm_trigger() -> void:
	var elder := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 5), {Stats.Stat.STR: 4}, true, 6)
	var elder_cells: Array[Vector2i] = [Vector2i(2, 0)]
	elder.arm_watch(Vector2i(0, 5), Vector2i(2, 0), elder_cells, _main_of(elder))
	var watcher := _line_watcher()
	var squatter := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0), {Stats.Stat.MHP: 60}, false)

	var plan := _sm.resolve_plan(watcher.squad, _board_with([elder, watcher, squatter]))

	assert_int(plan.watch_shots.size()).is_equal(1)
	assert_object(plan.watch_shots[0].actor).override_failure_message(
			"an older standing watch covering the same cell ate the arming watch's trigger") \
		.is_same(watcher)
	_break_volleys(plan)


# One trigger, ONE target (#1040, dev 2026-09-18: "only hit the first enemy they encounter, ever").
# Two enemies stand in the line as it arms and the shot takes the NEARER, where until #1057 it swept
# the frozen footprint and hit both. The line is painted rather than drawn as a path, so this is also
# the every-watch-is-single-target rule: a watch walks its whole footprint as one path, nearest first.
func test_an_arm_fired_shot_hits_only_the_nearest_in_its_line() -> void:
	var watcher := _line_watcher()
	var near := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.MHP: 60}, false)
	var far := H.spawn_solo(self, _sm, PLAYER, Vector2i(3, 0), {Stats.Stat.MHP: 60}, false)

	var plan := _sm.resolve_plan(watcher.squad, _board_with([watcher, near, far]))

	var hit: Array[Unit] = []
	for shot in plan.watch_shots:
		hit.append(shot.target)
	assert_array(hit).override_failure_message(
			"the watch shot swept its footprint -- it hit %d units, not just the nearer" % hit.size()) \
		.contains_exactly([near])
	_break_volleys(plan)


# The arm door and the entry door share ONE predicate, so every rider comes along with no clause of
# its own: a body does not trip a watch, and neither does the watcher's own side.
func test_arming_over_a_body_does_not_fire_the_watch() -> void:
	var watcher := _line_watcher()
	var body := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0), {Stats.Stat.MHP: 60}, false)
	body.lifecycle_state = Unit.LifecycleState.DOWNED

	var plan := _sm.resolve_plan(watcher.squad, _board_with([watcher, body]))

	assert_array(plan.watch_shots).is_empty()


func test_arming_over_an_ally_does_not_fire_the_watch() -> void:
	var watcher := _line_watcher()
	var friend := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {Stats.Stat.MHP: 60}, false)

	var plan := _sm.resolve_plan(watcher.squad, _board_with([watcher, friend]))

	assert_array(plan.watch_shots).is_empty()


# It arms ALREADY SPENT, so the queue row reads "(fired this pass)" and execution cannot hand back a
# live watch the preview showed as used -- GuardAction.resolved_spent's rule, through a new door.
func test_an_arm_fired_watch_arms_already_spent() -> void:
	var watcher := _line_watcher()
	var squatter := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0), {Stats.Stat.MHP: 60}, false)

	var plan := _sm.resolve_plan(watcher.squad, _board_with([watcher, squatter]))
	var order := watcher.squad.action_queue[0] as OverwatchAction
	assert_bool(order.resolved_spent).is_true()

	order.execute()
	assert_bool(watcher.watch.spent).override_failure_message(
			"execution armed a live watch the pass had already fired").is_true()
	_break_volleys(plan)


# The MOMENT it plays at is its own ORDER, at no walk step -- which puts it in the THIRD playback
# partition, the side-channel tail, and keeps it out of the attack phase entirely.
func test_an_arm_fired_shot_plays_in_the_tail_and_not_in_the_attack_phase() -> void:
	var watcher := _line_watcher()
	var squatter := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0), {Stats.Stat.MHP: 60}, false)

	var plan := _sm.resolve_plan(watcher.squad, _board_with([watcher, squatter]))
	var shot: AttackAction = plan.watch_shots[0]
	var order := watcher.squad.action_queue[0] as OverwatchAction

	assert_object(shot.triggered_during).is_same(order)
	assert_int(shot.triggered_at_step).is_equal(-1)
	assert_array(plan.coda_shots()).contains_exactly([shot])
	assert_array(plan.attack_playback()).not_contains([shot])
	assert_array(plan.mid_walk_shots()).is_empty()
	_break_volleys(plan)


# ...and the THREE partitions still add up to every shot fired, which is the property that stops a
# shot playing twice or not at all.
func test_the_three_playback_partitions_are_total() -> void:
	var watcher := _line_watcher()
	var squatter := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0), {Stats.Stat.MHP: 60}, false)

	var plan := _sm.resolve_plan(watcher.squad, _board_with([watcher, squatter]))

	var played: Array[AttackAction] = []
	played.append_array(plan.mid_walk_shots())
	played.append_array(plan.coda_shots())
	for action in plan.attack_playback():
		if (action as AttackAction).is_watch_shot:
			played.append(action)
	assert_array(played).override_failure_message(
			"the three playback partitions do not add up to every shot fired") \
		.contains_exactly_in_any_order(plan.watch_shots)
	_break_volleys(plan)


# WHERE IN THE PASS the shot lands is the ruling's own second sentence -- "the very last thing to
# happen, after everything else, even counters" -- which is the whole of why arming-as-an-attack is
# strictly worse than attacking. Falsifiable form: a counter that BREAKS the watch (#810) lands
# first, so the arm-fire never happens. Resolve the arm-fire any earlier and it does.
func test_a_counter_breaks_the_watch_before_the_arm_fire_can_happen() -> void:
	var watcher := _line_watcher(Vector2i(0, 0), PLAYER)   # the squad's leader, so the counter picks it
	var squadmate := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 1), {Stats.Stat.MHP: 60}, true)
	_sm.join_squad(squadmate, watcher.squad)
	var brawler := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 1), {Stats.Stat.MHP: 60}, true)
	var squatter := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {Stats.Stat.MHP: 60}, false)
	watcher.squad._queue_action(H.stamped_attack(squadmate, brawler))

	var plan := _sm.resolve_plan(watcher.squad, _board_with([watcher, squadmate, brawler, squatter]))

	# Fixture preconditions, stated loudly: without either of these the case measures nothing.
	assert_int(plan.counters.size()).override_failure_message(
			"the brawler never countered -- fixture, not mechanic").is_greater(0)
	assert_object(plan.counters[0].target).override_failure_message(
			"the counter answered the squadmate rather than the watcher -- fixture, not mechanic") \
		.is_same(watcher)

	assert_array(plan.watch_shots).override_failure_message(
			"the watch fired although a counter had already broken it, so the arm-fire is not " \
			+ "resolving after the counters") \
		.is_empty()
	_break_volleys(plan)


# The tail is now the FIRST phase that can fell somebody, and GUARD is the one verb that executes
# after Overwatch -- so its liveness stamp has to be re-taken after the arm-fire (#1005's rule,
# reached by a phase that did not exist when it was written). Without this a bodyguard the arm shot
# killed still steps in front of somebody at execution.
func test_an_arm_fired_shot_that_fells_a_guard_restamps_its_liveness() -> void:
	var watcher := _line_watcher(Vector2i(0, 0), PLAYER)
	_main_of(watcher).hits_allies = true   # the shot IS the attack, splash included
	var guard_unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.MHP: 1}, false)
	_sm.join_squad(guard_unit, watcher.squad)
	var ward := GuardAction.new()
	ward.init(guard_unit, watcher)
	watcher.squad._queue_action(ward)
	var squatter := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {Stats.Stat.MHP: 60}, false)

	var plan := _sm.resolve_plan(watcher.squad, _board_with([watcher, guard_unit, squatter]))

	assert_int(plan.watch_shots.size()).override_failure_message(
			"the watch never arm-fired -- fixture, not mechanic").is_greater(0)
	assert_int(PlanResolver.projected_lifecycle(guard_unit, plan.hypo)).override_failure_message(
			"the splash did not fell the bodyguard -- fixture, not mechanic") \
		.is_not_equal(Unit.LifecycleState.ACTIVE)
	assert_bool(ward.resolved_actor_felled).override_failure_message(
			"a bodyguard the arm-fired shot killed is still stamped live, so execution arms its ward") \
		.is_true()
	_break_volleys(plan)
