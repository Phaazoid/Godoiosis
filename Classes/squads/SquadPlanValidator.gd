extends Object
class_name SquadPlanValidator

# Decides which of a squad's queued orders are currently legal, by stamping is_valid +
# validation_errors onto each action. Split out of SquadManager 2026-07-26: it reads a plan and
# marks it, touching no squad lifecycle and no board state, so it is entirely static. Callers go
# through SquadManager.validate_squad_plan / validate_squad_plan_preview.
#
# Why it runs to a FIXED POINT rather than once (#16): the occupancy rule asks "did the unit
# standing here move away *validly*?", so one action's invalidation can invalidate another's.
# is_valid is reset ONCE up front and each pass only ever ADDS invalidations, which makes the
# loop monotonic and therefore terminating. Per-pass we clear only the MESSAGES
# (clear_validation_messages, which leaves is_valid alone) so text doesn't stack up across passes.
#
# Actions carrying their own queueing requirements (move-before-main, verb locks) enforce those in
# BaseAction.actor_block_reason at queue time. This is the separate, plan-CONTEXT layer: leader
# range, destination conflicts, and adjacency that a re-planned move can silently break. The one
# queue-time gate it re-asks is the FIRE gate, which a dock swap can break after queueing (#1283).

# `board` (#151): cohesion is path distance, so the validator reads terrain. Taken as a PARAMETER,
# not looked up -- SquadManager.board_source resolves it fresh per validate, so a mid-battle terrain
# change (FROZEN melting) is seen by the very next validation and never by a stale cache.
static func validate(squad: Squad, actions: Array[BaseAction], board: BoardContext, plan: ResolvedPlan = null) -> bool:
	for action in actions:
		action.reset_validation()

	# One pass per member plus one: each pass can invalidate at least one more action, so this
	# bounds the cascade. Breaks as soon as a pass changes nothing.
	var max_passes := squad.get_members().size() + 1
	for _i in range(max_passes):
		var before := actions.map(func(a): return a.is_valid)
		_run_pass(squad, actions, board)
		if actions.map(func(a): return a.is_valid) == before:
			break

	# OUTSIDE the loop, deliberately. Attack validity is a LEAF -- no other clause reads it, and
	# resolve_plan expands aims without consulting is_valid -- so running it out here lets it read
	# SETTLED move validity instead of the loop's own half-finished output.
	#
	# And only WITH a plan (2026-08-02): a shove puts its target on a SEQUENCE of cells, and only
	# the resolve loop walks that sequence in order. Judged against the settled end state, an aim
	# hunted its victim on the cell its own shove had just cleared. No plan = attacks untouched.
	if plan != null:
		_revalidate_unit_attacks(actions, plan)
		_revalidate_guard_range(actions)
		_revalidate_rescue_targets(actions, plan)
		_revalidate_watch_material(actions, board)
		_revalidate_fire_gates(actions)

	for action in actions:
		if not action.is_valid:
			return false
	return true

# The projected cell a unit occupies under this action list — Unit.projected_cell with validation's
# own two answers, stated here because BOTH are load-bearing and neither is obvious (#105):
#   require_valid = false — this function runs inside the fixed-point loop that SETS is_valid, so
#                           reading the flag would read our own partially-computed output.
#   use_knockback = false — a shove is derived by a resolve pass that reads validity; feeding it
#                           back in here would make validity depend on itself.
# Everything OUTSIDE validation wants the opposite of both, which is Unit.get_projected_destination.
static func projected_cell_for(unit: Unit, actions: Array[BaseAction]) -> Vector2i:
	return Unit.projected_cell(unit, actions, false, false)

static func _run_pass(squad: Squad, actions: Array[BaseAction], board: BoardContext) -> void:
	for action in actions:
		action.clear_validation_messages()

	# Typed as MoveAction, not BaseAction: get_destination() is declared on MoveAction only, so a
	# BaseAction-typed list would resolve it dynamically and lose every return type downstream.
	var move_actions: Array[MoveAction] = []
	for action in actions:
		if action.action_type == BaseAction.ActionType.MOVE:
			move_actions.append(action as MoveAction)

	# Leader-range validity must resolve BEFORE the occupancy check, which trusts is_valid.
	_check_leader_range(squad, actions, move_actions, board)
	_check_destination_conflicts(squad, actions, move_actions)
	_revalidate_rescues(actions)
	_revalidate_captures(actions)
	_revalidate_guards(actions)

# A non-leader squadmate must end inside the leader's projected cohesion range -- SquadCohesion's
# path-based bubble since #151, asked per member because traversal is per-unit. Group Move may leave
# a slower member SHORT of its formation slot, but never outside this bubble — a destination that
# would is refused, and painted red before the click (GroupMoveSolver.followable_destinations).
static func _check_leader_range(squad: Squad, actions: Array[BaseAction], move_actions: Array[MoveAction], board: BoardContext) -> void:
	var leader_cell := projected_cell_for(squad.leader, actions)
	for action in move_actions:
		var moving_unit: Unit = action.actor
		if moving_unit == squad.leader or not moving_unit.has_squad():
			continue
		if not SquadCohesion.in_range(squad, leader_cell, moving_unit, action.get_destination(), board):
			action.add_validation_error("Too far from the squad leader")

# Two members can't land on the same cell, and a cell only frees up if its current occupant has a
# VALID move away. An invalid move (out of leader range) or a hold means they stay put.
static func _check_destination_conflicts(squad: Squad, actions: Array[BaseAction], move_actions: Array[MoveAction]) -> void:
	var current_member_locations := {}   # {Vector2i : Unit}
	for member in squad.get_members():
		current_member_locations[member.movement.cell] = member

	var actions_by_destination := {}     # {Vector2i : Array[MoveAction]}
	for action in move_actions:
		var destination := action.get_destination()
		if not actions_by_destination.has(destination):
			actions_by_destination[destination] = []
		actions_by_destination[destination].append(action)

	for destination in actions_by_destination.keys():
		var actions_at_cell: Array = actions_by_destination[destination]

		if current_member_locations.has(destination):
			var occupying_unit: Unit = current_member_locations[destination]
			if not _unit_has_valid_move_away_from(occupying_unit, destination, actions):
				for action in actions_at_cell:
					if action.actor == occupying_unit:
						continue   # the occupant's own hold/stay on this cell isn't a self-collision
					action.add_validation_error("Destination occupied")
				continue

		if actions_at_cell.size() > 1:
			for action in actions_at_cell:
				action.add_validation_error("Multiple units attempting to move here")

static func _unit_has_valid_move_away_from(unit: Unit, cell: Vector2i, actions: Array[BaseAction]) -> bool:
	for action in actions:
		if action.actor == unit and action.action_type == BaseAction.ActionType.MOVE and action.is_valid and action.get_destination() != cell:
			return true
	return false

# The rescuer must still END its projected move adjacent to the target. ADJACENCY ONLY since #124:
# the lifecycle half (is the target down, or predicted to be by the side channel?) needs the
# resolve, so it lives in _revalidate_rescue_targets below, outside the loop with the attacks.
static func _revalidate_rescues(actions: Array[BaseAction]) -> void:
	for action in actions:
		if not (action is RescueAction):
			continue
		var rescue := action as RescueAction
		var target: Unit = rescue.target
		if target == null or not is_instance_valid(target):
			rescue.add_validation_error("Rescue target is gone")
			continue
		if not _actor_ends_adjacent_to(rescue, target, actions):
			rescue.add_validation_error("Rescuer no longer adjacent to the downed ally")

# A Guard needs a ward to guard. Whether the pair is in RANGE is not asked here: that belongs to the
# moment the ward arms, which only the resolve can see (_revalidate_guard_range, below).
static func _revalidate_guards(actions: Array[BaseAction]) -> void:
	for action in actions:
		if not (action is GuardAction):
			continue
		var guard := action as GuardAction
		var ward: Unit = guard.target
		if ward == null or not is_instance_valid(ward) or ward.is_dead():
			guard.add_validation_error("Guard target is gone")

# A re-planned move that walks the actor out of the zone invalidates the capture, rather than
# claiming wherever it ended up. Same shape as rescue; the context is a CELL.
static func _revalidate_captures(actions: Array[BaseAction]) -> void:
	for action in actions:
		if not (action is CaptureAction):
			continue
		var capture := action as CaptureAction
		if projected_cell_for(capture.actor, actions) != capture.cell:
			capture.add_validation_error("No longer standing on the capture point")

# Whiff POLICY, the single copy: `targets` decides whether an empty footprint matters -- MAP/BOTH
# still deposits on bare ground (#47/#50), UNIT-only does nothing, null is bare fists. It TAKES the
# positional fact so its two sources (the plan, or the candidate predictor below) share one policy.
static func aim_whiffs(aim: AttackAction, found_a_target: bool) -> bool:
	if aim.fired_attack != null and aim.fired_attack.hits_map():
		return false
	return not found_a_target

# Source 1 -- a stored aim: read the plan. resolve_plan stamps source_aim on every action it derives.
static func _revalidate_unit_attacks(actions: Array[BaseAction], plan: ResolvedPlan) -> void:
	for action in actions:
		if not (action is AttackAction):
			continue
		var aim := action as AttackAction
		if aim_whiffs(aim, _plan_found_a_target(plan, aim)):
			aim.add_validation_error("Nothing left to hit on that cell")
		# ...and the fizzle (Deep Alchemy Phase 2): the resolve marked this aim's carving fizzled where
		# the pass has its caster, so a re-plan has walked them away from what it needs. RED, still
		# queued -- one-way validity, the whiff's own rule. The resolve's answer, never a re-derivation.
		if _plan_fizzled(plan, aim):
			aim.add_validation_error("Fizzles where they'll be standing")

# The pair must still be together WHEN THE GUARD ARMS, so a re-plan that parts them refuses the order
# rather than arming a Guard that covers nothing (#414). The ward arms at the order's QUEUE SLOT in the
# attack walk, so the answer is the resolve's (GuardAction.resolved_in_range, #1354), read beside the
# whiff clause for its reason: a shove queued AFTER the Guard is the authored counterplay (shove the
# blocker, shove the ward), asked per hit by PlanResolver._guard_for, while one queued before it really
# can part the pair. A CANDIDATE Guard is judged at the gate (SquadManager._candidate_guard_in_range).
static func _revalidate_guard_range(actions: Array[BaseAction]) -> void:
	for action in actions:
		var guard := action as GuardAction
		if guard == null or not guard.is_valid:
			continue   # already red: the ward is gone
		if not guard.resolved_in_range:
			guard.add_validation_error("Too far from the unit being guarded")

# A stored WATCH's twin of the clause above (Deep Alchemy Phase 2): the resolve stamped where the watch
# arms (OverwatchAction.resolved_anchor), and a carving that fizzles from there could only ever fire a
# fizzle -- so a re-plan that walked the watcher off its material reds it, still queued. Asked from
# the resolve's own stamp, beside the attacks for their reason; an empty footprint is "nothing to
# arm" (a felled watcher, #1005) and is asked nothing.
static func _revalidate_watch_material(actions: Array[BaseAction], board: BoardContext) -> void:
	for action in actions:
		var watch := action as OverwatchAction
		if watch == null or watch.resolved_footprint.is_empty():
			continue
		if CellSubstances.fizzle_reason(watch.fired_attack, watch.resolved_anchor, board, watch.actor.state) != "":
			watch.add_validation_error("Fizzles where they'll be standing")

# The gate that ADMITTED a stored aim or watch, asked again (#1283): the dock can swap the weapon in
# hand after the order was queued, and the stamped attack then belongs to nothing being held. RED,
# still queued, and green again when the weapon comes back -- the whiff clause's one-way validity.
#
# Plan-armed ONLY because every plan-armed validate runs before a pass (refresh_action_queue refuses
# mid-pass, #361). The plan-less one a death runs mid-pass would re-ask readiness this pass has
# already spent, and red an order that has just fired.
static func _revalidate_fire_gates(actions: Array[BaseAction]) -> void:
	for action in actions:
		var stamped: AttackData
		if action is AttackAction:
			stamped = (action as AttackAction).fired_attack
		elif action is OverwatchAction:
			stamped = (action as OverwatchAction).fired_attack
		else:
			continue
		var reason := AttackAction.fire_block_reason(action.actor, stamped)
		if reason != "":
			action.add_validation_error(reason)

static func _plan_fizzled(plan: ResolvedPlan, aim: AttackAction) -> bool:
	for resolved_attack in plan.attacks:
		if resolved_attack.source_aim == aim and resolved_attack.resolved != null and resolved_attack.resolved.fizzled:
			return true
	return false

static func _plan_found_a_target(plan: ResolvedPlan, aim: AttackAction) -> bool:
	for resolved_attack in plan.attacks:
		if resolved_attack.source_aim == aim and resolved_attack.target != null:
			return true
	return false

# The lifecycle half of rescue validity (#124) -- plan-armed and outside the loop for the attack
# clause's reasons: it is a LEAF (nothing reads it back), and its answer belongs to the resolve --
# a target may legally not be down YET, provided this pass's own hits put it down before the side
# channel runs. A cancelled attack un-predicts the down on the next resolve and the rescue falls
# into red, still queued (one-way validity). No plan = rescues untouched, same as attacks.
static func _revalidate_rescue_targets(actions: Array[BaseAction], plan: ResolvedPlan) -> void:
	for action in actions:
		if not (action is RescueAction):
			continue
		var rescue := action as RescueAction
		if not RulesService.is_rescueable(rescue.target, plan):
			rescue.add_validation_error("Rescue target won't be down")
			continue
		# The rescuer must still be BESIDE the body when the side channel reaches it (#1349): the
		# resolve's verdict on its own cells, since a counter can shove either of them away after the
		# plan was authored. Skipped when the loop's adjacency clause has already said so on the moves.
		if rescue.is_valid and not rescue.resolved_within_reach:
			rescue.add_validation_error("Won't be beside the downed ally when the rescue runs")
			continue
		# And the CHOSEN cell must still be one it can be put on (#116). The player picked a bank at
		# queue time and the order carries that stamp, so a re-plan that walks the rescuer away from
		# it strands the order -- it goes RED and stays queued (one-way validity) rather than being
		# silently relocated, which for a cell the player chose deliberately would be worse than
		# refusing, and rather than fizzling at execute where the BREAK repeal (#155) calls a
		# divergence a bug. CaptureAction's frozen-stamp ruling, one verb along.
		#
		# Out here with the lifecycle clause rather than beside adjacency inside the loop, and for the
		# same reason: it reads the resolve's output, which reads validity back. The resolve's own
		# verdict (resolved_haul_lands), on the pass's cells and ground (#1349, #1498) -- the one it
		# published the haul off, so the two cannot disagree about a bank a counter's shove has put
		# out of the rescuer's reach, or one the pass melted.
		if rescue.target != null and is_instance_valid(rescue.target) and not rescue.resolved_haul_lands:
			rescue.add_validation_error("Can't pull them out to there any more")

# Source 2 -- a CANDIDATE only: would this aim connect if queued right now? There is no plan for an
# order the resolver has never seen. Correct because the published knockback is the ALREADY-QUEUED
# aims' shoves, exactly the prefix a new aim lands after. NEVER ask it about a stored aim -- that
# same knockback then includes the aim's OWN shove.
#
# gather_attack_victims without a board: same eligibility rule (RulesService.is_attack_victim),
# positions from Unit.projected_cell with both axes TRUE, unlike projected_cell_for above --
# a refused move moves nobody, and you must be able to aim where a shove will land (#105).
#
# The board it DOES take is the footprint's (#756): a spread the terrain truncates covers fewer
# cells, so a candidate whose only victim stands past a ledge must whiff at the queue gate exactly
# as it will whiff at the resolve. The eligibility question above still asks no board.
static func aim_finds_a_target(aim: AttackAction, actions: Array[BaseAction], units: Array[Unit], board: BoardContext) -> bool:
	var origin := Unit.projected_cell(aim.actor, actions, true, true)
	var footprint := Reach.get_affected_cells_from(origin, aim.target_cell, aim.fired_attack, board)
	# The current is reach, so an aim whose only casualties arrive by the arc is not a whiff. Asked
	# with this function's own projection rather than through Conduction.sweep, which reads the
	# occupancy seam a RESOLVED plan uses -- the two falses above are load-bearing here (#126).
	#
	# It reads LIVE wetness, so it is CONSERVATIVE by exactly one case: an aim that would only catch
	# somebody a not-yet-executed order in this same plan soaks is refused at the gate. An over-read
	# would be the harmful direction (a victimless aim still resolves as a cell attack, #47); this
	# way costs one exotic order and never queues a shot that finds nobody.
	#
	# PATH-BLIND ON PURPOSE for a single-target swing (#1057), and exactly right rather than close: a
	# path is only ever cut AT a valid victim, so if any path has one this already answers true, and
	# if none does nothing was cut -- the footprint here and the struck tiles the sweep floods from
	# are then the same cells. Whether anybody is found cannot differ; only who, which is the resolve's.
	var arc := Conduction.arc_cells(aim.actor, aim.fired_attack, footprint, board)
	for unit in units:
		if not is_instance_valid(unit):
			continue
		var cell := Unit.projected_cell(unit, actions, true, true)
		if arc.has(cell):
			return true     # the current does not check tags -- anybody in it is a casualty
		if not footprint.has(cell):
			continue
		if RulesService.is_attack_victim(aim.actor.state, unit, aim.fired_attack):
			return true
	return false

# The two sides are projected DIFFERENTLY, and the asymmetry is the point (#126).
#
# The ACTOR is inside the plan under validation, so it gets projected_cell_for's two load-bearing
# falses. The TARGET is not — a rescue target is a body in its own solo squad — so its cell is a
# board FACT, read exactly the way board.projected_unit_at_cell and the board preview read it. That
# is what makes rescue follow a shoved body: it executes in the side channel, AFTER attacks and
# counters have landed every shove, so the end-of-pass cell is the one it meets the target on. Reading target.movement.cell instead was correct only while downed
# units could not move.
#
# Not a fixed-point hazard: this reads another squad's settled validity plus a knockback published
# before validate ran, both constant across the loop, so rescue validity stays the leaf it was.
#
# The loop's answer, on the moves. What the pass then does to either of them -- a counter's shove -- is
# the resolve's to say (RescueAction.resolved_within_reach, read in _revalidate_rescue_targets).
static func _actor_ends_adjacent_to(action: BaseAction, target: Unit, actions: Array[BaseAction]) -> bool:
	return RescueAction.within_reach(projected_cell_for(action.actor, actions), target.get_projected_destination())
