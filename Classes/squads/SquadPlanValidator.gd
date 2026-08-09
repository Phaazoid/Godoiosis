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
# BaseAction.actor_can_perform at queue time. This is the separate, plan-CONTEXT layer: leader
# range, destination conflicts, and adjacency that a re-planned move can silently break.

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
	_revalidate_intimidates(actions)
	_revalidate_captures(actions)

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

# The rescuer must still END its projected move adjacent to a still-downed ally. Mirrors the AoE
# re-derivation debt: a move re-planned away from the body invalidates the rescue, and a target
# someone else rescued first drops out too.
static func _revalidate_rescues(actions: Array[BaseAction]) -> void:
	for action in actions:
		if not (action is RescueAction):
			continue
		var rescue := action as RescueAction
		var target: Unit = rescue.target
		if target == null or not is_instance_valid(target) or not target.is_downed():
			rescue.add_validation_error("Rescue target is no longer down")
			continue
		if not _actor_ends_adjacent_to(rescue, target, actions):
			rescue.add_validation_error("Rescuer no longer adjacent to the downed ally")

# Same shape as rescue, but the target only has to still be ALIVE (active or downed).
static func _revalidate_intimidates(actions: Array[BaseAction]) -> void:
	for action in actions:
		if not (action is IntimidateAction):
			continue
		var intimidate := action as IntimidateAction
		var victim: Unit = intimidate.target
		if victim == null or not is_instance_valid(victim) or victim.is_dead():
			intimidate.add_validation_error("Intimidate target is gone")
			continue
		if not _actor_ends_adjacent_to(intimidate, victim, actions):
			intimidate.add_validation_error("No longer adjacent to the intimidate target")

# A re-planned move that walks the actor out of the zone invalidates the capture, rather than
# claiming wherever it ended up. Same shape as rescue/intimidate; the context is a CELL.
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

static func _plan_found_a_target(plan: ResolvedPlan, aim: AttackAction) -> bool:
	for resolved_attack in plan.attacks:
		if resolved_attack.source_aim == aim and resolved_attack.target != null:
			return true
	return false

# Source 2 -- a CANDIDATE only: would this aim connect if queued right now? There is no plan for an
# order the resolver has never seen. Correct because the published knockback is the ALREADY-QUEUED
# aims' shoves, exactly the prefix a new aim lands after. NEVER ask it about a stored aim -- that
# same knockback then includes the aim's OWN shove.
#
# gather_attack_victims without a board: same eligibility rule (RulesService.is_attack_victim),
# positions from Unit.projected_cell with both axes TRUE, unlike projected_cell_for above --
# a refused move moves nobody, and you must be able to aim where a shove will land (#105).
static func aim_finds_a_target(aim: AttackAction, actions: Array[BaseAction], units: Array[Unit]) -> bool:
	var origin := Unit.projected_cell(aim.actor, actions, true, true)
	var footprint := Reach.get_affected_cells_from(aim.actor, origin, aim.target_cell, aim.fired_attack)
	for unit in units:
		if not is_instance_valid(unit):
			continue
		if not footprint.has(Unit.projected_cell(unit, actions, true, true)):
			continue
		if RulesService.is_attack_victim(aim.actor, unit, aim.fired_attack):
			return true
	return false

# The two sides are projected DIFFERENTLY, and the asymmetry is the point (#126).
#
# The ACTOR is inside the plan under validation, so it gets projected_cell_for's two load-bearing
# falses. The TARGET is not — a rescue target is a body in its own solo squad, an intimidate victim
# an enemy in its own — so its cell is a board FACT, read exactly the way board.projected_unit_at_cell
# and the board preview read it. That is what makes rescue follow a shoved body: both verbs execute
# in the side channel, AFTER attacks and counters have landed every shove, so the end-of-pass cell is
# the one they meet the target on. Reading target.movement.cell instead was correct only while downed
# units could not move.
#
# Not a fixed-point hazard: this reads another squad's settled validity plus a knockback published
# before validate ran, both constant across the loop, so rescue validity stays the leaf it was.
static func _actor_ends_adjacent_to(action: BaseAction, target: Unit, actions: Array[BaseAction]) -> bool:
	var actor_cell := projected_cell_for(action.actor, actions)
	return GridUtils.cells_within_manhattan_range(actor_cell, 1).has(target.get_projected_destination())
