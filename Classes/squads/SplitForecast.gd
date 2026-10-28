extends Object
class_name SplitForecast

# WHO A PASS WILL KNOCK OUT OF A SQUAD, AND WHICH BLOW DOES IT (#367). The plan-time mirror of the
# settle that runs after a pass, so the queue can say "Split" on the row that causes one (Law #2)
# and the tether break can play at that same blow. Stamped once per resolve, by
# SquadManager.resolve_plan and resolve_hypothetical (the AI scores a split, #761), into
# ResolvedOutcome.splits (who leaves) and .relinks (which links end and begin -- a handover names its
# successor once, here, for the presenter and the stage to read).
#
# THE ORDER IT REPLAYS is the live one, and it is the only thing here that is not shared code:
#   - a DEATH settles at once, mid-pass (game._on_unit_died -> handle_unit_death), so a killed
#     leader's successor is judged where everyone stands at that blow -- except during the WALK,
#     where the successor is named at once and its reach waits for the walk to end
#     (SquadManager.hold_handovers);
#   - a unit the pass's own melt drops into the water (#922) goes under once the attack phase has
#     played and its deposits have landed -- or once the pass has settled, for a melt only a counter or
#     tail shot made;
#   - at pass end, OrderExecutor._process_downed_pending ejects each downed unit in the order it went
#     down -- skipping one finished off later in the pass -- and a downed leader hands over;
#   - then SquadManager.enforce_contact ejects every member out of its leader's range;
#   - then, at END OF TURN, the burn (OrderExecutor.apply_end_of_turn_tiles): a death at once, the
#     downed once every burn has landed. Its Split rides the END OF TURN row.
# The RULES inside each step are not copied: the successor and the capacity overflow are
# SquadManager's own statics, and range is SquadCohesion's. tests/squad/test_split_forecast.gd runs
# the real pass and requires the two to agree.
#
# WHERE EVERYONE STANDS at a given blow is rebuilt from the outcomes, not snapshotted: once the walk
# is over only a knockback moves a unit, and each outcome records its own knockback_from/to.
#
# WHAT BODY EACH HAS is rebuilt beside it (#1499), and the shared rules are handed it: the leader's
# COH and states, a successor's LDR, a member's traversal. A unit has its live body until the last
# blow that moves one of its stats (a limb taken, a state with a paired effect), and the pass's copy
# (PlanResolver.state_of) from that blow on. One no blow changes that way has the copy throughout:
# what the walk or a carried weapon changed is on it before any blow. So by pass end every body is the
# one the settle reads. Exact unless one unit's stats move at two blows of one pass: between them it
# has its live body, so a break they cause goes on the later blow.
#
# THE GROUND it stands on is the live one too: playback lands a volley's terrain deposits (ice frozen,
# ice melted) once its last member has played (ResolvedPlan.landing_after, #1498), so a blow settles on
# the ground every EARLIER volley has left, and the pass end on the plan's planned tiles
# (ResolvedPlan.tiles). A Burrow's COVER is never landed partway: it is DEF, and no reach reads it.
#
# A DEATH IS NEVER COUNTED -- a death is not a split, and its tether plays a look of its own (#1104) --
# and neither is a unit that leaves a squad of one.
#
# THE ROUND'S SPLITS are round_leavers (#1430), a separate question with no row to stamp: smoke the
# round's gas step spills onto a leader shortens its leash, and the first contact sweep after it -- at
# the next turn start, TurnBoundary.start_turn -> SquadManager.enforce_contact -- ejects whoever it no
# longer reaches. The red tether is its readout (game._member_links), and it judges the bodies the
# previewed pass leaves (#1504).

class _Band:
	var leader: Unit
	var members: Array[Unit] = []


# A leader's leaving whose reach check has not run yet: at once, or when the walk ends.
class _Handover:
	var band: _Band
	var outcome: ResolvedOutcome
	var old_leader: Unit
	var cause: SquadManager.LeaveCause
	var stayed: Array[Unit] = []


static func stamp(plan: ResolvedPlan, board: BoardContext) -> void:
	var blows := playback(plan)
	var hits := _hits(plan)
	for hit in hits:
		var outcome := hit.resolved_outcome()
		if outcome != null:
			outcome.splits.clear()
			outcome.relinks.clear()

	var changes := _stat_changes(blows)
	var bands: Dictionary[Unit, _Band] = {}
	var all_bands: Array[_Band] = []
	_seed_bands(hits, bands, all_bands)
	# A blow that moves a stat can move a squad's range or its successor without moving anyone: an arm
	# taken with the piece that lengthened the leader's leash.
	for unit in changes:
		_seed_band(unit, bands, all_bands)
	# A pass that changes the ground can move ANY squad's range, hit or not: ice melting between two
	# members strands one without a blow landing on either.
	if not plan.cell_effects.is_empty():
		for unit in board.units:
			_seed_band(unit, bands, all_bands)
	if all_bands.is_empty():
		return

	var landed := board.planned(plan.tiles)
	var walk_ends := plan.mid_walk_shots().size()
	var deposits_land := walk_ends + plan.attack_playback().size()
	var landings := _landings(plan, blows)
	var so_far := PlannedTiles.new(board.terrain_states, board.gas)
	var ground := board.planned(so_far)   # what playback has landed by the blow being replayed
	var start := _start_positions(blows, bands, plan.hypo)
	var pos: Dictionary[Unit, Vector2i] = start.duplicate()
	var start_bodies := _start_bodies(bands, changes, plan.hypo)
	var body: Dictionary[Unit, UnitState] = start_bodies.duplicate()
	var dead: Dictionary[Unit, bool] = {}
	var downs: Array[BaseAction] = []
	var downed: Dictionary[Unit, bool] = {}
	var held: Array[_Handover] = []
	var sunk := false
	for i in blows.size():
		if i > 0:
			_land(so_far, landings[i - 1])
		if i == walk_ends:
			_hand_over_held(held, bands, pos, body, ground)
		if i == deposits_land:
			_sink(plan.sinks_at(SinkAction.Moment.DEPOSITS_LAND), bands, pos, body, ground, dead, downed, downs)
			sunk = true
		var blow := blows[i]
		var outcome := blow.resolved_outcome()
		var victim := blow.target
		if not _landed(outcome) or victim == null or not is_instance_valid(victim):
			continue
		if outcome.knockback_applied and not outcome.removed:
			pos[victim] = outcome.knockback_to
		if changes.get(victim, -1) == i:
			body[victim] = PlanResolver.state_of(victim, plan.hypo)
		match LethalityRules.lifecycle_for(outcome.lethality):
			Unit.LifecycleState.DEAD:
				if not dead.has(victim):
					dead[victim] = true
					_leave(victim, outcome, bands, pos, body, ground, SquadManager.LeaveCause.DEATH, held,
							i < walk_ends)
			Unit.LifecycleState.DOWNED:
				if not downed.has(victim):
					downed[victim] = true
					downs.append(blow)
	if not blows.is_empty():
		_land(so_far, landings[-1])
	_hand_over_held(held, bands, pos, body, ground)   # a pass that is nothing but its walk
	if not sunk:   # nothing played after the volley, so the loop never reached the deposits' moment
		_sink(plan.sinks_at(SinkAction.Moment.DEPOSITS_LAND), bands, pos, body, ground, dead, downed, downs)
	_sink(plan.sinks_at(SinkAction.Moment.PASS_END), bands, pos, body, landed, dead, downed, downs)

	# A body finished off later in the pass is never ejected -- and needs no check here: its death
	# already took it out of its copied squad, so _leave finds nothing to do.
	_settle_downs(downs, bands, pos, body, landed)
	_sweep_contact(blows, all_bands, start, pos, start_bodies, body, changes, board, landings, landed)
	_settle_burns(plan.tile_hits, bands, pos, body, landed)


# The pass's blows in the order they PLAY -- ResolvedPlan's own partitions, the ones OrderExecutor
# and BeatSheet read, so this cannot place a blow somewhere the executor does not.
static func playback(plan: ResolvedPlan) -> Array[AttackAction]:
	var order: Array[AttackAction] = []
	order.append_array(plan.mid_walk_shots())
	order.append_array(plan.attack_playback())
	for counter in plan.counters:
		order.append(counter)
	order.append_array(plan.coda_shots())
	return order


# What playback lands after each of those blows, index for index (#1498): a volley's deposits at its
# last member, nothing at the others. Asked once per stamp, so the replays below only read it.
static func _landings(plan: ResolvedPlan, blows: Array[AttackAction]) -> Array[Array]:
	var out: Array[Array] = []
	for blow in blows:
		out.append(plan.landing_after(blow))
	return out


# Lands one blow's deposits on a replay's tiles; true when there were any.
static func _land(tiles: PlannedTiles, effects: Array) -> bool:
	for effect: ResolvedCellEffect in effects:
		tiles.land(effect)
	return not effects.is_empty()


# Every row a stamp can write a split onto: the blows, then the end-of-turn burn and the sinkings.
static func _hits(plan: ResolvedPlan) -> Array[BaseAction]:
	var hits: Array[BaseAction] = []
	hits.append_array(playback(plan))
	hits.append_array(plan.tile_hits)
	hits.append_array(plan.sinks)
	return hits


# Who a STAMPED plan knocks out of a squad, each once -- the AI's split term (#761). A downed unit's
# ejection is in here too; the caller decides whether a removal already paid for it.
static func leavers(plan: ResolvedPlan) -> Array[Unit]:
	var out: Array[Unit] = []
	for hit in _hits(plan):
		var outcome := hit.resolved_outcome()
		if outcome == null:
			continue
		for unit in outcome.splits:
			if is_instance_valid(unit) and not out.has(unit):
				out.append(unit)
	return out


# Who leaves `squad` at the first turn start after the round (#1430): in range of the leader on `board`
# and out of it once `next` -- GasField.next_round(board), the round's own answer -- lies on the leader's
# cell. `leader_cell` and `at` are where the bodies stand. One already out of range on `board` is not
# the round's: the pass's own sweep takes it, and the Split chip says so. The two halves are
# SquadCohesion's (reach_in, field_within), the pieces in_range is made of. `plan` is the previewed pass,
# and the leader's leash and each member's traversal are judged on the bodies it leaves
# (PlanResolver.state_of, #1504); null judges the live ones. The AI asks it of one blown cloud too
# (AITactics._blow_splits, #1514), handing the gas the blow leaves as `next`.
static func round_leavers(squad: Squad, leader_cell: Vector2i, at: Dictionary[Unit, Vector2i],
		board: BoardContext, next: Dictionary[Vector2i, int], plan: ResolvedPlan) -> Array[Unit]:
	var leavers: Array[Unit] = []
	if squad == null or not squad.has_squadmates():
		return leavers
	var hypo: Dictionary = plan.hypo if plan != null else {}
	var leader := squad.leader
	var leader_body := PlanResolver.state_of(leader, hypo)
	var now := SquadCohesion.reach_in(leader_body, board.gas_at(leader_cell))
	var then := SquadCohesion.reach_in(leader_body, next.get(leader_cell, 0))
	if then >= now:
		return leavers
	for member: Unit in at:
		if member == leader or not squad.members.has(member):
			continue
		var body := PlanResolver.state_of(member, hypo)
		var hops: int = SquadCohesion.field_within(now, leader_cell, body, board).get(at[member], -1)
		if hops > then:
			leavers.append(member)
	return leavers


static func _landed(outcome: ResolvedOutcome) -> bool:
	return outcome != null and not outcome.skipped


# Who a hit lands on: an attack's target, or the unit standing in the fire (a burn's actor).
static func _victim(hit: BaseAction) -> Unit:
	var blow := hit as AttackAction
	return blow.target if blow != null else hit.actor


# Unit -> the index in `blows` of the last landed blow that moves one of its stats.
static func _stat_changes(blows: Array[AttackAction]) -> Dictionary[Unit, int]:
	var changes: Dictionary[Unit, int] = {}
	for i in blows.size():
		var outcome := blows[i].resolved_outcome()
		var victim := blows[i].target
		if _landed(outcome) and victim != null and is_instance_valid(victim) and _moves_stats(outcome):
			changes[victim] = i
	return changes


# Does this hit move a stat on its target's body: a limb taken (#1174), or a state with a paired
# effect added or removed (Elemental.paired_stat_mods)? A piece the wearer falls under the gate of
# comes off with it, and everything it gave.
static func _moves_stats(outcome: ResolvedOutcome) -> bool:
	if outcome.severed_limb != -1:
		return true
	for state in outcome.states_added:
		if not Elemental.paired_stat_mods(state).is_empty():
			return true
	for state in outcome.states_removed:
		if not Elemental.paired_stat_mods(state).is_empty():
			return true
	return false


# A copy of every squad the pass can change -- one whose member is shoved, downed or killed (stamp
# adds one whose member has a stat moved, and every squad when the ground changes). The copy keeps
# member ORDER, which the successor tie-break and the newest-first overflow both read.
static func _seed_bands(hits: Array[BaseAction], bands: Dictionary[Unit, _Band],
		all_bands: Array[_Band]) -> void:
	for hit in hits:
		var outcome := hit.resolved_outcome()
		var victim := _victim(hit)
		if not _landed(outcome) or victim == null or not is_instance_valid(victim):
			continue
		var moves_squads := outcome.knockback_applied \
				or LethalityRules.lifecycle_for(outcome.lethality) != Unit.LifecycleState.ACTIVE
		if moves_squads:
			_seed_band(victim, bands, all_bands)


static func _seed_band(unit: Unit, bands: Dictionary[Unit, _Band], all_bands: Array[_Band]) -> void:
	var squad := unit.squad
	if bands.has(unit) or squad == null or not squad.has_squadmates():
		return
	var band := _Band.new()
	band.leader = squad.leader
	band.members = squad.members.duplicate()
	all_bands.append(band)
	for member in band.members:
		bands[member] = band


# Where each copied unit stands when the attacks begin: where its first shove found it, else where
# the pass leaves it (an unshoved unit does not move once the walk is done).
static func _start_positions(blows: Array[AttackAction], bands: Dictionary[Unit, _Band],
		hypo: Dictionary) -> Dictionary[Unit, Vector2i]:
	var start: Dictionary[Unit, Vector2i] = {}
	for blow in blows:
		var outcome := blow.resolved_outcome()
		if _landed(outcome) and outcome.knockback_applied and bands.has(blow.target) \
				and not start.has(blow.target):
			start[blow.target] = outcome.knockback_from
	for unit in bands:
		if not start.has(unit):
			start[unit] = PlanResolver.projected_position(unit, hypo)
	return start


# The body each copied unit has when the blows begin: its live one if a blow will move its stats,
# else the one the pass leaves it with.
static func _start_bodies(bands: Dictionary[Unit, _Band], changes: Dictionary[Unit, int],
		hypo: Dictionary) -> Dictionary[Unit, UnitState]:
	var bodies: Dictionary[Unit, UnitState] = {}
	for unit in bands:
		bodies[unit] = unit.state if changes.has(unit) else PlanResolver.state_of(unit, hypo)
	return bodies


static func _bodies_of(members: Array[Unit], body: Dictionary[Unit, UnitState]) -> Array[UnitState]:
	var bodies: Array[UnitState] = []
	for member in members:
		bodies.append(body[member])
	return bodies


# A unit leaves its copied squad, and a leader's leaving hands over -- the successor's range and
# capacity ejections are stamped on the SAME blow. A death is never counted as a split. A handover
# DURING THE WALK (`walking`) names its successor now and waits for the walk to end for the rest,
# in `held`.
static func _leave(unit: Unit, outcome: ResolvedOutcome, bands: Dictionary[Unit, _Band],
		pos: Dictionary[Unit, Vector2i], body: Dictionary[Unit, UnitState], board: BoardContext,
		cause: SquadManager.LeaveCause, held: Array[_Handover] = [], walking := false) -> void:
	var band: _Band = bands.get(unit)
	if band == null:
		return
	band.members.erase(unit)
	bands.erase(unit)
	if cause != SquadManager.LeaveCause.DEATH and not band.members.is_empty():
		outcome.splits.append(unit)
	if band.members.is_empty():
		return
	if band.leader != unit:
		_relink(outcome, unit, band.leader, true, cause, pos)
		return
	var handover := _Handover.new()
	handover.band = band
	handover.outcome = outcome
	handover.old_leader = unit
	handover.cause = cause
	handover.stayed = band.members.duplicate()
	band.leader = SquadManager.successor_among(_bodies_of(band.members, body))
	if walking:
		held.append(handover)
	else:
		_hand_over(handover, bands, pos, body, board)


# The rest of a handover: what the successor can hold, where everyone stands NOW.
#
# The LINKS it records are the ones the tether presenter would diff after the same settle: every link
# to a leaving leader ends, a member ejected by the handover ending on its OWN cause (FORCED) and the
# rest on the leader's, and the survivors' links to the successor begin.
static func _hand_over(handover: _Handover, bands: Dictionary[Unit, _Band],
		pos: Dictionary[Unit, Vector2i], body: Dictionary[Unit, UnitState], board: BoardContext) -> void:
	var band := handover.band
	var outcome := handover.outcome
	for member in band.members.duplicate():
		if not SquadCohesion.in_range_of(body[band.leader], pos[band.leader], body[member], pos[member], board):
			_eject(member, band, bands, outcome)
	for member in SquadManager.capacity_overflow(band.members, body[band.leader]):
		_eject(member, band, bands, outcome)
	for member in handover.stayed:
		var ejected := not band.members.has(member)
		_relink(outcome, member, handover.old_leader, true,
				SquadManager.LeaveCause.FORCED if ejected else handover.cause, pos)
	for member in band.members:
		if member != band.leader:
			_relink(outcome, member, band.leader, false, -1, pos)


# The walk is over: every handover it held judges reach where the walkers now stand.
static func _hand_over_held(held: Array[_Handover], bands: Dictionary[Unit, _Band],
		pos: Dictionary[Unit, Vector2i], body: Dictionary[Unit, UnitState], board: BoardContext) -> void:
	for handover in held:
		if not handover.band.members.is_empty():
			_hand_over(handover, bands, pos, body, board)
	held.clear()


static func _eject(member: Unit, band: _Band, bands: Dictionary[Unit, _Band],
		outcome: ResolvedOutcome) -> void:
	band.members.erase(member)
	bands.erase(member)
	outcome.splits.append(member)


static func _relink(outcome: ResolvedOutcome, member: Unit, leader: Unit, ends: bool, cause: int,
		pos: Dictionary[Unit, Vector2i]) -> void:
	var link := ResolvedOutcome.Relink.new()
	link.member = member
	link.leader = leader
	link.ends = ends
	link.cause = cause
	link.member_cell = pos[member]
	link.leader_cell = pos[leader]
	outcome.relinks.append(link)


static func _settle_downs(downs: Array[BaseAction], bands: Dictionary[Unit, _Band],
		pos: Dictionary[Unit, Vector2i], body: Dictionary[Unit, UnitState], board: BoardContext) -> void:
	for hit in downs:
		_leave(_victim(hit), hit.resolved_outcome(), bands, pos, body, board, SquadManager.LeaveCause.DOWNED)


# The pass's own terrain dropping units into the water (#922), at the moment they go under: the burn's
# two halves -- a death leaves at once, a down waits for the settle with the rest, in the order it went
# down. The ground is what playback has landed by then, the deposits that took the floor away among it.
static func _sink(sinks: Array[SinkAction], bands: Dictionary[Unit, _Band], pos: Dictionary[Unit, Vector2i],
		body: Dictionary[Unit, UnitState], ground: BoardContext, dead: Dictionary[Unit, bool],
		downed: Dictionary[Unit, bool], downs: Array[BaseAction]) -> void:
	for sink in sinks:
		var outcome := sink.resolved_outcome()
		var victim := sink.actor
		if not _landed(outcome) or victim == null or not is_instance_valid(victim):
			continue
		match LethalityRules.lifecycle_for(outcome.lethality):
			Unit.LifecycleState.DEAD:
				if not dead.has(victim):
					dead[victim] = true
					_leave(victim, outcome, bands, pos, body, ground, SquadManager.LeaveCause.DEATH)
			Unit.LifecycleState.DOWNED:
				if not downed.has(victim):
					downed[victim] = true
					downs.append(sink)


# END OF TURN, after the pass has settled: a burn death hands over at once, and the burned-down leave
# once every burn has landed, in the order they burned.
static func _settle_burns(burns: Array[TileHitAction], bands: Dictionary[Unit, _Band],
		pos: Dictionary[Unit, Vector2i], body: Dictionary[Unit, UnitState], board: BoardContext) -> void:
	var downs: Array[BaseAction] = []
	for burn in burns:
		var outcome := burn.resolved_outcome()
		var victim := burn.actor
		if not _landed(outcome) or victim == null or not is_instance_valid(victim):
			continue
		match LethalityRules.lifecycle_for(outcome.lethality):
			Unit.LifecycleState.DEAD:
				_leave(victim, outcome, bands, pos, body, board, SquadManager.LeaveCause.DEATH)
			Unit.LifecycleState.DOWNED:
				downs.append(burn)
	_settle_downs(downs, bands, pos, body, board)


# The pass-end contact sweep, on the ground the pass leaves. A break is owned by the blow after which
# the pair STAYED out of range: the last in-range -> out-of-range transition, whether the member or
# its leader was the one shoved, the ground between them changed as a volley's deposits landed, or a
# blow moved a stat of either (`changes`, flipping `start_bodies` to `body`, the pass's copies).
static func _sweep_contact(blows: Array[AttackAction], all_bands: Array[_Band],
		start: Dictionary[Unit, Vector2i], pos: Dictionary[Unit, Vector2i],
		start_bodies: Dictionary[Unit, UnitState], body: Dictionary[Unit, UnitState],
		changes: Dictionary[Unit, int], board: BoardContext, landings: Array[Array],
		landed: BoardContext) -> void:
	for band in all_bands:
		if band.members.size() <= 1:
			continue
		for member in band.members:
			if member == band.leader or SquadCohesion.in_range_of(body[band.leader], pos[band.leader],
					body[member], pos[member], landed):
				continue
			var culprit := _breaking_blow(blows, band.leader, member, start, start_bodies, body, changes,
					board, landings)
			if culprit != null:
				culprit.resolved_outcome().splits.append(member)
				_relink(culprit.resolved_outcome(), member, band.leader, true,
						SquadManager.LeaveCause.FORCED, pos)


# Replays the pair blow by blow, each volley's deposits landing on a fresh copy of the tiles after its
# last member, as playback lands them -- the causal order, which is what names a row. Who leaves is the
# sweep's to say, on the full board.
static func _breaking_blow(blows: Array[AttackAction], leader: Unit, member: Unit,
		start: Dictionary[Unit, Vector2i], start_bodies: Dictionary[Unit, UnitState],
		body: Dictionary[Unit, UnitState], changes: Dictionary[Unit, int], board: BoardContext,
		landings: Array[Array]) -> AttackAction:
	var at_leader: Vector2i = start[leader]
	var at_member: Vector2i = start[member]
	var leader_body: UnitState = start_bodies[leader]
	var member_body: UnitState = start_bodies[member]
	var made := PlannedTiles.new(board.terrain_states, board.gas)
	var ground := board.planned(made)
	var held := SquadCohesion.in_range_of(leader_body, at_leader, member_body, at_member, ground)
	var culprit: AttackAction = null
	for i in blows.size():
		var blow := blows[i]
		var outcome := blow.resolved_outcome()
		var moved := false
		var changed := false
		if _landed(outcome):
			if outcome.knockback_applied and not outcome.removed:
				if blow.target == leader:
					at_leader = outcome.knockback_to
					moved = true
				elif blow.target == member:
					at_member = outcome.knockback_to
					moved = true
			if changes.get(leader, -1) == i:
				leader_body = body[leader]
				changed = true
			if changes.get(member, -1) == i:
				member_body = body[member]
				changed = true
		# ...and a volley's tiles at its last member, which lands them even when the pass skipped it.
		var dug := _land(made, landings[i])
		if not moved and not dug and not changed:
			continue
		var now := SquadCohesion.in_range_of(leader_body, at_leader, member_body, at_member, ground)
		if held and not now:
			culprit = blow
		elif now:
			culprit = null
		held = now
	return culprit
