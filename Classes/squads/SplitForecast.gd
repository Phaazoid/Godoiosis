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
#   - a unit the pass's own melt drops into the water (#922) goes under when the deposits land, right
#     after the volley -- or once the pass has settled, for a melt only a counter or tail shot made;
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
# THE GROUND it stands on is the live one too: a pass's terrain deposits (ice frozen, ice melted) land
# in one batch after the attack volley (OrderExecutor._apply_cell_effects), so the walk and the volley
# settle on the board as it was, and everything after on BoardContext.with_deposits.
#
# A DEATH IS NEVER COUNTED -- a death is not a split, and its tether plays a look of its own (#1104) --
# and neither is a unit that leaves a squad of one.

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

	var bands: Dictionary[Unit, _Band] = {}
	var all_bands: Array[_Band] = []
	_seed_bands(hits, bands, all_bands)
	# A pass that changes the ground can move ANY squad's range, hit or not: ice melting between two
	# members strands one without a blow landing on either.
	if not plan.cell_effects.is_empty():
		for unit in board.units:
			_seed_band(unit, bands, all_bands)
	if all_bands.is_empty():
		return

	var landed := board.with_deposits(plan.cell_effects)
	var walk_ends := plan.mid_walk_shots().size()
	var deposits_land := walk_ends + plan.attack_playback().size()
	var start := _start_positions(blows, bands, plan.hypo)
	var pos: Dictionary[Unit, Vector2i] = start.duplicate()
	var dead: Dictionary[Unit, bool] = {}
	var downs: Array[BaseAction] = []
	var downed: Dictionary[Unit, bool] = {}
	var held: Array[_Handover] = []
	var sunk := false
	for i in blows.size():
		if i == walk_ends:
			_hand_over_held(held, bands, pos, board)
		if i == deposits_land:
			_sink(plan.sinks_at(SinkAction.Moment.DEPOSITS_LAND), bands, pos, landed, dead, downed, downs)
			sunk = true
		var blow := blows[i]
		var outcome := blow.resolved_outcome()
		var victim := blow.target
		if not _landed(outcome) or victim == null or not is_instance_valid(victim):
			continue
		if outcome.knockback_applied and not outcome.removed:
			pos[victim] = outcome.knockback_to
		var ground := board if i < deposits_land else landed
		match LethalityRules.lifecycle_for(outcome.lethality):
			Unit.LifecycleState.DEAD:
				if not dead.has(victim):
					dead[victim] = true
					_leave(victim, outcome, bands, pos, ground, SquadManager.LeaveCause.DEATH, held,
							i < walk_ends)
			Unit.LifecycleState.DOWNED:
				if not downed.has(victim):
					downed[victim] = true
					downs.append(blow)
	_hand_over_held(held, bands, pos, board)   # a pass that is nothing but its walk
	if not sunk:   # nothing played after the volley, so the loop never reached the deposits' moment
		_sink(plan.sinks_at(SinkAction.Moment.DEPOSITS_LAND), bands, pos, landed, dead, downed, downs)
	_sink(plan.sinks_at(SinkAction.Moment.PASS_END), bands, pos, landed, dead, downed, downs)

	# A body finished off later in the pass is never ejected -- and needs no check here: its death
	# already took it out of its copied squad, so _leave finds nothing to do.
	_settle_downs(downs, bands, pos, landed)
	_sweep_contact(blows, all_bands, start, pos, board, plan.cell_effects, landed)
	_settle_burns(plan.tile_hits, bands, pos, landed)


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


static func _landed(outcome: ResolvedOutcome) -> bool:
	return outcome != null and not outcome.skipped


# Who a hit lands on: an attack's target, or the unit standing in the fire (a burn's actor).
static func _victim(hit: BaseAction) -> Unit:
	var blow := hit as AttackAction
	return blow.target if blow != null else hit.actor


# A copy of every squad the pass can change -- one whose member is shoved, downed or killed. The copy
# keeps member ORDER, which the successor tie-break and the newest-first overflow both read.
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


# A unit leaves its copied squad, and a leader's leaving hands over -- the successor's range and
# capacity ejections are stamped on the SAME blow. A death is never counted as a split. A handover
# DURING THE WALK (`walking`) names its successor now and waits for the walk to end for the rest,
# in `held`.
static func _leave(unit: Unit, outcome: ResolvedOutcome, bands: Dictionary[Unit, _Band],
		pos: Dictionary[Unit, Vector2i], board: BoardContext, cause: SquadManager.LeaveCause,
		held: Array[_Handover] = [], walking := false) -> void:
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
	band.leader = SquadManager.successor_among(band.members)
	if walking:
		held.append(handover)
	else:
		_hand_over(handover, bands, pos, board)


# The rest of a handover: what the successor can hold, where everyone stands NOW.
#
# The LINKS it records are the ones the tether presenter would diff after the same settle: every link
# to a leaving leader ends, a member ejected by the handover ending on its OWN cause (FORCED) and the
# rest on the leader's, and the survivors' links to the successor begin.
static func _hand_over(handover: _Handover, bands: Dictionary[Unit, _Band],
		pos: Dictionary[Unit, Vector2i], board: BoardContext) -> void:
	var band := handover.band
	var outcome := handover.outcome
	for member in band.members.duplicate():
		if not SquadCohesion.in_range_of(band.leader, pos[band.leader], member, pos[member], board):
			_eject(member, band, bands, outcome)
	for member in SquadManager.capacity_overflow(band.members, band.leader):
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
		pos: Dictionary[Unit, Vector2i], board: BoardContext) -> void:
	for handover in held:
		if not handover.band.members.is_empty():
			_hand_over(handover, bands, pos, board)
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
		pos: Dictionary[Unit, Vector2i], board: BoardContext) -> void:
	for hit in downs:
		_leave(_victim(hit), hit.resolved_outcome(), bands, pos, board, SquadManager.LeaveCause.DOWNED)


# The pass's own terrain dropping units into the water (#922), at the moment they go under: the burn's
# two halves -- a death leaves at once, a down waits for the settle with the rest, in the order it went
# down. The ground is the landed one, since the deposits are what took the floor away.
static func _sink(sinks: Array[SinkAction], bands: Dictionary[Unit, _Band], pos: Dictionary[Unit, Vector2i],
		ground: BoardContext, dead: Dictionary[Unit, bool], downed: Dictionary[Unit, bool],
		downs: Array[BaseAction]) -> void:
	for sink in sinks:
		var outcome := sink.resolved_outcome()
		var victim := sink.actor
		if not _landed(outcome) or victim == null or not is_instance_valid(victim):
			continue
		match LethalityRules.lifecycle_for(outcome.lethality):
			Unit.LifecycleState.DEAD:
				if not dead.has(victim):
					dead[victim] = true
					_leave(victim, outcome, bands, pos, ground, SquadManager.LeaveCause.DEATH)
			Unit.LifecycleState.DOWNED:
				if not downed.has(victim):
					downed[victim] = true
					downs.append(sink)


# END OF TURN, after the pass has settled: a burn death hands over at once, and the burned-down leave
# once every burn has landed, in the order they burned.
static func _settle_burns(burns: Array[TileHitAction], bands: Dictionary[Unit, _Band],
		pos: Dictionary[Unit, Vector2i], board: BoardContext) -> void:
	var downs: Array[BaseAction] = []
	for burn in burns:
		var outcome := burn.resolved_outcome()
		var victim := burn.actor
		if not _landed(outcome) or victim == null or not is_instance_valid(victim):
			continue
		match LethalityRules.lifecycle_for(outcome.lethality):
			Unit.LifecycleState.DEAD:
				_leave(victim, outcome, bands, pos, board, SquadManager.LeaveCause.DEATH)
			Unit.LifecycleState.DOWNED:
				downs.append(burn)
	_settle_downs(downs, bands, pos, board)


# The pass-end contact sweep, on the ground the pass leaves. A break is owned by the blow after which
# the pair STAYED out of range: the last in-range -> out-of-range transition, whether the member or
# its leader was the one shoved, or the ground between them changed under a blow's own deposits.
static func _sweep_contact(blows: Array[AttackAction], all_bands: Array[_Band],
		start: Dictionary[Unit, Vector2i], pos: Dictionary[Unit, Vector2i], board: BoardContext,
		deposits: Array[ResolvedCellEffect], landed: BoardContext) -> void:
	for band in all_bands:
		if band.members.size() <= 1:
			continue
		for member in band.members:
			if member == band.leader \
					or SquadCohesion.in_range_of(band.leader, pos[band.leader], member, pos[member], landed):
				continue
			var culprit := _breaking_blow(blows, band.leader, member, start, board, deposits)
			if culprit != null:
				culprit.resolved_outcome().splits.append(member)
				_relink(culprit.resolved_outcome(), member, band.leader, true,
						SquadManager.LeaveCause.FORCED, pos)


# Replays the pair blow by blow, each blow carrying its own deposits (ResolvedCellEffect.cause) --
# the causal order, which is what names a row. Who leaves is the sweep's to say, on the full board.
static func _breaking_blow(blows: Array[AttackAction], leader: Unit, member: Unit,
		start: Dictionary[Unit, Vector2i], board: BoardContext,
		deposits: Array[ResolvedCellEffect]) -> AttackAction:
	var at_leader: Vector2i = start[leader]
	var at_member: Vector2i = start[member]
	var ground := board
	var made: Array[ResolvedCellEffect] = []
	var held := SquadCohesion.in_range_of(leader, at_leader, member, at_member, ground)
	var culprit: AttackAction = null
	for blow in blows:
		var outcome := blow.resolved_outcome()
		if not _landed(outcome):
			continue
		var moved := false
		if outcome.knockback_applied and not outcome.removed:
			if blow.target == leader:
				at_leader = outcome.knockback_to
				moved = true
			elif blow.target == member:
				at_member = outcome.knockback_to
				moved = true
		var dug := false
		for effect in deposits:
			if effect.cause == blow:
				made.append(effect)
				dug = true
		if dug:
			ground = board.with_deposits(made)
		if not moved and not dug:
			continue
		var now := SquadCohesion.in_range_of(leader, at_leader, member, at_member, ground)
		if held and not now:
			culprit = blow
		elif now:
			culprit = null
		held = now
	return culprit
