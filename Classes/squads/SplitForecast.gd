extends Object
class_name SplitForecast

# WHO A PASS WILL KNOCK OUT OF A SQUAD, AND WHICH BLOW DOES IT (#367). The plan-time mirror of the
# settle that runs after a pass, so the queue can say "Split" on the row that causes one (Law #2)
# and the tether break can play at that same blow. Stamped once per resolve, by
# SquadManager.resolve_plan, into ResolvedOutcome.splits (who leaves) and .relinks (which links end
# and begin -- a handover names its successor once, here, for the presenter and the stage to read).
#
# THE ORDER IT REPLAYS is the live one, and it is the only thing here that is not shared code:
#   - a DEATH settles at once, mid-pass (game._on_unit_died -> handle_unit_death), so a killed
#     leader's successor is judged where everyone stands at that blow;
#   - at pass end, OrderExecutor._process_downed_pending ejects each downed unit in the order it went
#     down -- skipping one finished off later in the pass -- and a downed leader hands over;
#   - then SquadManager.enforce_contact ejects every member out of its leader's range.
# The RULES inside each step are not copied: the successor and the capacity overflow are
# SquadManager's own statics, and range is SquadCohesion's. tests/squad/test_split_forecast.gd runs
# the real pass and requires the two to agree.
#
# WHERE EVERYONE STANDS at a given blow is rebuilt from the outcomes, not snapshotted: once the walk
# is over only a knockback moves a unit, and each outcome records its own knockback_from/to.
#
# A DEATH IS NEVER COUNTED (#1104's), and neither is a unit that leaves a squad of one.

class _Band:
	var leader: Unit
	var members: Array[Unit] = []


static func stamp(plan: ResolvedPlan, board: BoardContext) -> void:
	var blows := playback(plan)
	for blow in blows:
		var outcome := blow.resolved_outcome()
		if outcome != null:
			outcome.splits.clear()
			outcome.relinks.clear()

	var bands: Dictionary[Unit, _Band] = {}
	var all_bands: Array[_Band] = []
	_seed_bands(blows, bands, all_bands)
	if all_bands.is_empty():
		return

	var start := _start_positions(blows, bands, plan.hypo)
	var pos: Dictionary[Unit, Vector2i] = start.duplicate()
	var dead: Dictionary[Unit, bool] = {}
	var downs: Array[AttackAction] = []
	var downed: Dictionary[Unit, bool] = {}
	for blow in blows:
		var outcome := blow.resolved_outcome()
		var victim := blow.target
		if not _landed(outcome) or victim == null or not is_instance_valid(victim):
			continue
		if outcome.knockback_applied and not outcome.removed:
			pos[victim] = outcome.knockback_to
		match LethalityRules.lifecycle_for(outcome.lethality):
			Unit.LifecycleState.DEAD:
				if not dead.has(victim):
					dead[victim] = true
					_leave(victim, outcome, bands, pos, board, SquadManager.LeaveCause.DEATH)
			Unit.LifecycleState.DOWNED:
				if not downed.has(victim):
					downed[victim] = true
					downs.append(blow)

	# A body finished off later in the pass is never ejected -- and needs no check here: its death
	# already took it out of its copied squad, so _leave finds nothing to do.
	for blow in downs:
		_leave(blow.target, blow.resolved_outcome(), bands, pos, board, SquadManager.LeaveCause.DOWNED)

	_sweep_contact(blows, all_bands, start, pos, board)


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


static func _landed(outcome: ResolvedOutcome) -> bool:
	return outcome != null and not outcome.skipped


# A copy of every squad the pass can change -- one whose member is shoved, downed or killed. The copy
# keeps member ORDER, which the successor tie-break and the newest-first overflow both read.
static func _seed_bands(blows: Array[AttackAction], bands: Dictionary[Unit, _Band],
		all_bands: Array[_Band]) -> void:
	for blow in blows:
		var outcome := blow.resolved_outcome()
		var victim := blow.target
		if not _landed(outcome) or victim == null or not is_instance_valid(victim):
			continue
		var moves_squads := outcome.knockback_applied \
				or LethalityRules.lifecycle_for(outcome.lethality) != Unit.LifecycleState.ACTIVE
		var squad := victim.squad
		if not moves_squads or bands.has(victim) or squad == null or not squad.has_squadmates():
			continue
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
# capacity ejections are stamped on the SAME blow. A death is never counted as a split.
#
# The LINKS it records are the ones the tether presenter would diff after the same settle: every link
# to a leaving leader ends, a member ejected by the handover ending on its OWN cause (FORCED) and the
# rest on the leader's, and the survivors' links to the successor begin.
static func _leave(unit: Unit, outcome: ResolvedOutcome, bands: Dictionary[Unit, _Band],
		pos: Dictionary[Unit, Vector2i], board: BoardContext, cause: SquadManager.LeaveCause) -> void:
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
	var stayed: Array[Unit] = band.members.duplicate()
	band.leader = SquadManager.successor_among(band.members)
	for member in band.members.duplicate():
		if not SquadCohesion.in_range_of(band.leader, pos[band.leader], member, pos[member], board):
			_eject(member, band, bands, outcome)
	for member in SquadManager.capacity_overflow(band.members, band.leader):
		_eject(member, band, bands, outcome)
	for member in stayed:
		var ejected := not band.members.has(member)
		_relink(outcome, member, unit, true, SquadManager.LeaveCause.FORCED if ejected else cause, pos)
	for member in band.members:
		if member != band.leader:
			_relink(outcome, member, band.leader, false, -1, pos)


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


# The pass-end contact sweep. A break is owned by the blow after which the pair STAYED out of range:
# the last in-range -> out-of-range transition, whether the member or its leader was the one shoved.
static func _sweep_contact(blows: Array[AttackAction], all_bands: Array[_Band],
		start: Dictionary[Unit, Vector2i], pos: Dictionary[Unit, Vector2i], board: BoardContext) -> void:
	for band in all_bands:
		if band.members.size() <= 1:
			continue
		for member in band.members:
			if member == band.leader \
					or SquadCohesion.in_range_of(band.leader, pos[band.leader], member, pos[member], board):
				continue
			var culprit := _breaking_blow(blows, band.leader, member, start, board)
			if culprit != null:
				culprit.resolved_outcome().splits.append(member)
				_relink(culprit.resolved_outcome(), member, band.leader, true,
						SquadManager.LeaveCause.FORCED, pos)


static func _breaking_blow(blows: Array[AttackAction], leader: Unit, member: Unit,
		start: Dictionary[Unit, Vector2i], board: BoardContext) -> AttackAction:
	var at_leader: Vector2i = start[leader]
	var at_member: Vector2i = start[member]
	var held := SquadCohesion.in_range_of(leader, at_leader, member, at_member, board)
	var culprit: AttackAction = null
	for blow in blows:
		var outcome := blow.resolved_outcome()
		if not _landed(outcome) or not outcome.knockback_applied or outcome.removed:
			continue
		if blow.target == leader:
			at_leader = outcome.knockback_to
		elif blow.target == member:
			at_member = outcome.knockback_to
		else:
			continue
		var now := SquadCohesion.in_range_of(leader, at_leader, member, at_member, board)
		if held and not now:
			culprit = blow
		elif now:
			culprit = null
		held = now
	return culprit
