extends Node2D
class_name SquadManager

# The only owner of squad lifecycle (create/destroy/join/leave — member removal funnels through
# Squad._erase_member(), the sole `members.erase` caller) and the queue/plan-resolution entry
# point: queue_action validates + stores player orders, resolve_plan expands the queue into a
# fresh ResolvedPlan each pass (attacks -> derived reactions), and calculate_reactions_for_squad
# is where reaction existence gets derived, never stored — a counter-attack or, when the source
# heals, a reactive heal on the defender's own side (#148). See docs/design/squad-system.md and
# docs/design/resolution-pipeline.md.
#
# Three tenants moved out 2026-07-26 — this file had become the second dumping ground after
# game.gd, and two of its sections were literally labelled "migrated from game.gd":
#   SquadPlanValidator (squads/)        — plan-context validity, marked onto each action
#   GroupMoveSolver (squads/)           — the pure formation solver; queue_group_move commits it
#   ActionQueueDisplayEntry.build_for() — queue-panel layout, now beside the view model
# What stays is squad lifecycle, order queueing, activation state, and plan resolution.

var squads: Array[Squad] = []
var active_squad: Squad = null

# True while several orders are queued as ONE player action (Group Move): the expensive per-order
# fan-out runs once at the end instead. Every order still passes queue_action's gates (Law #3).
# ONLY safe while a batch stays synchronous — docs/performance.md has the invariants.
var batching := false

# The live board the cohesion rule reads (#151) -- a Callable returning a FRESH BoardContext, never
# a stored one: terrain state changes mid-battle (FROZEN water melts), and a cached board would
# validate against a world that no longer exists. Wired once per bootstrap: game._ready -> _board,
# play/board_builder -> its own builder, tests/support/squad_fixtures.make_manager -> the fixture's.
var board_source: Callable

# The last resolve, kept for candidate gating and the rescue candidate list (#124). Derived data,
# never read back by the resolver itself; read only through resolved_plan_for, which guards squad
# identity. Freshness rides the synchronous queue -> repaint -> resolve chain, the same guarantee
# published knockback leans on -- a caller that queues twice with no resolve between (headless
# drivers, tests) judges the second order against the first's prefix, exactly like an aim.
var _last_resolved_plan: ResolvedPlan = null
var _last_resolved_squad: Squad = null

@onready var overlay_manager: OverlayManager = $"../OverlayManager"
@onready var grid: TileMapLayer = $"../Grid"

signal squad_created(squad: Squad)
signal squad_deleted(squad: Squad)
signal squad_action_cancelled(squad: Squad, unit: Unit, actiontype: BaseAction.ActionType)
signal squad_became_active(squad: Squad, action: BaseAction)
signal squad_became_empty(squad: Squad)
signal squad_action_queued(squad: Squad, action: BaseAction)


func any_squad_active() -> bool:
	for squad in squads:
		if not squad.get_actions().is_empty():
			return true
			
	return false

func is_another_squad_active(squad: Squad) -> bool:
	if active_squad == null:
		return false
	return active_squad != squad

func reset_faction_actions(faction: Team.Faction) -> void:
	for squad in squads:
		if squad.leader.get_faction() == faction:
			squad._reset_squad()

func create_squad(leader: Unit) -> Squad:
	var squad := Squad.new()
	add_child(squad)
	
	squad.set_leader(leader)
	
	squads.append(squad)
	_register_squad_signals(squad)
	
	squad_created.emit(squad)
	return squad
	
func _detach_from_current_squad(unit: Unit): #This should be the only place that ever erases a unit from a squad
	var old_squad := unit.squad
	if old_squad == null:
		return

	old_squad._erase_member(unit)
	check_reassign_leader(old_squad, unit)

	if old_squad.get_members().is_empty():
		destroy_empty_squad(old_squad)
		
func join_squad(unit: Unit, target_squad: Squad):
	if unit.squad == target_squad:
		return

	_detach_from_current_squad(unit)
	target_squad._add_member(unit)
	if target_squad.members.size() > target_squad.max_size():
		push_warning("Squad '%s' over capacity (%d/%d) — grandfathered (direct/loaded join)." % [target_squad.squad_name, target_squad.members.size(), target_squad.max_size()])

func leave_squad(unit: Unit):
	_detach_from_current_squad(unit)
	create_squad(unit)

# #151's loss-of-contact backstop: a member whose SETTLED position cannot path to its leader within
# COH leaves into a solo squad -- you cannot command what you cannot see or hear. Movement can no
# longer author a split (the validator refuses it), so what reaches here is displacement the plan
# didn't choose: a shove around a corner, ice melting under a formation. Called at the two points
# board state settles, mirroring OrderExecutor._process_downed_pending -- end of a resolution pass
# and turn start after the terrain/downed ticks. Deliberately not previewed, same as downed ejection.
func enforce_contact() -> void:
	var board: BoardContext = board_source.call()
	for squad in squads.duplicate():
		if not is_instance_valid(squad) or squad.members.size() <= 1:
			continue
		var leader_cell: Vector2i = squad.leader.movement.cell
		for member in squad.members.duplicate():
			if member == squad.leader:
				continue
			if not SquadCohesion.in_range(squad, leader_cell, member, member.movement.cell, board):
				leave_squad(member)

func check_reassign_leader(squad: Squad, unit: Unit):
	if squad.members.is_empty():
		return
		
	if squad.leader != unit:
		return
	
	var newLeader: Unit = squad.members[0]
	for member in squad.members.duplicate():
		if member.get_effective_ldr() > newLeader.get_effective_ldr():
			newLeader = member
	squad.leader = newLeader 

	var board: BoardContext = board_source.call()
	for member in squad.members.duplicate():
		if not SquadCohesion.in_range(squad, squad.leader.movement.cell, member, member.movement.cell, board):
			leave_squad(member)

	# Capacity overflow (#63): the new leader may command less than the old one.
	# Detach newest-first (join order = member order) until the squad fits — deterministic,
	# mirrors the out-of-range detach above; the leader is never the one detached.
	while squad.members.size() > squad.max_size():
		var newest: Unit = null
		for i in range(squad.members.size() - 1, -1, -1):
			if squad.members[i] != squad.leader:
				newest = squad.members[i]
				break
		if newest == null:
			break
		leave_squad(newest)

func validate_squad_plan(squad: Squad, plan: ResolvedPlan = null) -> bool:
	return SquadPlanValidator.validate(squad, squad.action_queue, board_source.call(), plan)

# Validate a HYPOTHETICAL queue — the hover preview's "what if it moved here?" and the queue-time
# gate's "what if this were queued?". No plan: nothing has resolved this candidate.
func validate_squad_plan_preview(squad: Squad, preview_action: BaseAction) -> bool:
	return SquadPlanValidator.validate(squad, _hypothetical_actions(squad, preview_action), board_source.call())

# The queue as it WOULD be with `preview_action` in it; displacement uses the squad's own rule.
func _hypothetical_actions(squad: Squad, preview_action: BaseAction) -> Array[BaseAction]:
	var actions: Array[BaseAction] = squad.action_queue.duplicate()
	for action in actions.duplicate():
		if squad.displaces(action, preview_action):
			actions.erase(action)
	actions.append(preview_action)
	return actions

# Same question BoardContext.projected_unit_at_cell answers, over squad membership rather than a
# board snapshot — one rule (Unit.projected_unit_at), two unit sets. #105 retired the old move-order
# scan, which knew nothing about knockback and only ever looked at the active squad.
func get_projected_unit_from_cell(cell: Vector2i) -> Unit:
	return Unit.projected_unit_at(_all_units(), cell)

func setup_hold_move_actions(squad: Squad):
	for member in squad.get_members():
		if not member.has_action_type_queued(BaseAction.ActionType.MOVE):
			var hold_move := MoveAction.new()
			hold_move.init_hold_position(member, GridUtils.get_terrain_icon_at_cell(grid, member.movement.cell))
			squad._queue_action(hold_move)

func disband_squad(squad: Squad):
	if not squads.has(squad):
		return
	
	for member in squad.get_members().duplicate():
		squad._erase_member(member)
		create_squad(member)
		
	destroy_empty_squad(squad)
		
func destroy_empty_squad(squad: Squad):
	if squad == null:
		return
	if not squad.get_members().is_empty():
		return

	if active_squad == squad:
		active_squad = null

	squads.erase(squad)
	squad_deleted.emit(squad)
	squad.queue_free()
	
func clear_all_squads():
	active_squad = null
	for squad in squads.duplicate():
		squads.erase(squad)
		squad_deleted.emit(squad)
		squad.queue_free()

func queue_action(squad: Squad, action: BaseAction) -> bool:
	# Downed/dead units can't be ordered. This is the single order chokepoint (Law #3 —
	# future AI funnels here too), so one check here covers every actor.
	if action.actor != null and not action.actor.is_active():
		return false

	# Per-action requirement (BaseAction.actor_can_perform — move ordering, verb locks,
	# ability gates): each action class declares its own; this chokepoint enforces it for
	# every caller, including AI. The menu merely hides what this refuses.
	if action.actor != null and not action.actor_can_perform():
		return false

	# Plan-context requirement: invalid is a state you fall into, never one you choose. Batched
	# orders skip it -- a formation is one decision, judged whole by queue_group_move.
	if not batching and not _candidate_would_be_valid(squad, action):
		return false

	active_squad = squad
	squad._queue_action(action)
	if batching:
		return true   # the batch re-validates and redraws once, after the last order
	validate_squad_plan(squad)
	overlay_manager.redraw_planned_paths()

	return true

# Would this order be legal if queued right now? Reads the CANDIDATE's flag, not validate's return
# value -- that is whole-plan validity, and an already-broken row would refuse a legal order.
func _candidate_would_be_valid(squad: Squad, action: BaseAction) -> bool:
	validate_squad_plan_preview(squad, action)
	if action.is_valid and _candidate_aim_connects(squad, action) and _candidate_rescue_target_ok(squad, action):
		return true
	# Refused: keep its validation_errors for the caller, and undo the probe's stamps on the real queue.
	validate_squad_plan(squad)
	return false

# The whiff half of the gate: only a CANDIDATE may be asked this -- a stored aim's answer comes
# from the resolve. Non-attack candidates pass straight through.
func _candidate_aim_connects(squad: Squad, action: BaseAction) -> bool:
	if not (action is AttackAction):
		return true
	var aim := action as AttackAction
	var found := SquadPlanValidator.aim_finds_a_target(aim, _hypothetical_actions(squad, action), _all_units())
	if not SquadPlanValidator.aim_whiffs(aim, found):
		return true
	aim.add_validation_error("Nothing to hit on that cell")
	return false

# The rescue half of the gate (#124), the whiff clause's sibling: a candidate rescue may target a
# unit that is down OR one this squad's already-resolved plan predicts will be down by the side
# channel. The stored resolve is the right witness for a candidate -- it covers exactly the queued
# prefix the rescue lands after, and a rescue changes no lethality, so the prefix IS the pass.
# Non-rescue candidates pass straight through.
func _candidate_rescue_target_ok(squad: Squad, action: BaseAction) -> bool:
	if not (action is RescueAction):
		return true
	var rescue := action as RescueAction
	if RulesService.is_rescueable(rescue.target, resolved_plan_for(squad)):
		return true
	rescue.add_validation_error("Rescue target won't be down")
	return false

func set_has_acted(squad: Squad, acted: bool) -> void:
	squad._set_has_acted(acted)

func remove_actions_for_unit(unit: Unit) -> void:
	var squad = unit.squad
	for action in squad.action_queue.duplicate():
		if action.actor == unit:
			if action.action_type == BaseAction.ActionType.MOVE:
				cancel_move_for_unit(action.actor)
			else:
				squad._remove_action(action)

	# Empty OR hold-only => the squad reverts to inactive. only_hold_actions() also reports true
	# for an empty queue, so this subsumes the old separate "no actions left" branch.
	revert_if_only_hold(squad)
	
func cancel_move_for_unit(unit: Unit):
	var squad = unit.squad
	
	for action in squad.action_queue.duplicate():
		if action.actor == unit and action.action_type == BaseAction.ActionType.MOVE:
			squad._remove_action(action)
			
	var hold_move = MoveAction.new()
	hold_move.init_hold_position(unit,GridUtils.get_terrain_icon_at_cell(grid, unit.movement.cell))
	squad._queue_action(hold_move)
	
	validate_squad_plan(squad)
	overlay_manager.redraw_planned_paths()
			
# True when a squad's queue holds nothing but hold-position moves — i.e. no real orders. Also
# true for an EMPTY queue, which is what lets revert_if_only_hold subsume "nothing left".
# Takes the squad explicitly: it used to read active_squad implicitly while every sibling took a
# parameter, so a caller asking about a different squad silently got the wrong answer.
func only_hold_actions(squad: Squad) -> bool:
	if squad == null:
		return false

	for action in squad.action_queue:
		if not action.action_type == BaseAction.ActionType.MOVE:
			return false
		if action.action_type == BaseAction.ActionType.MOVE and action.is_hold_position == false:
			return false
			
	return true

# A squad stripped down to only hold-position moves (or nothing real) has no orders worth
# committing, so it stops being active — its queue closes and another squad can be selected.
# Mirrors the revert inside remove_actions_for_unit; call it from cancel paths that DON'T funnel
# through there — notably the action-queue X button. Returns true if it actually reverted.
func revert_if_only_hold(squad: Squad) -> bool:
	if active_squad != squad or not only_hold_actions(squad):
		return false
	squad._clear_all_actions()   # fires actions_became_empty -> queue + board cleanup
	active_squad = null
	return true
	
func remove_action(squad: Squad, action: BaseAction):
	if action is AttackAction and not (action as AttackAction).volley.is_empty():
		squad._remove_volley(action)
	else:
		squad._remove_action(action)

	if not squad.has_any_queued_actions() and active_squad == squad:
		active_squad = null
		return
	validate_squad_plan(squad)
	overlay_manager.redraw_planned_paths()

func squad_has_invalid_actions(squad: Squad) -> bool:
	for action in squad.action_queue:
		if not action.is_valid:
			return true
	return false
	
func can_counter(countering_unit: Unit, target_unit: Unit) -> bool: 
	if countering_unit == null or target_unit == null:
		return false
	if not is_instance_valid(countering_unit) or not is_instance_valid(target_unit):
		return false
	# NB: there is no per-UNIT counter flag. CombatComponent carried a `can_counter` @export that
	# was never authored on any unit, so the gate here was permanently open; the authored one is
	# AttackData.can_counter, checked below via attack_source_can_counter().
	if not RulesService.can_target(countering_unit, target_unit):
		return false
	if not countering_unit.attack_source_can_counter():
		return false

	var counter_cell := countering_unit.get_projected_destination()
	var target_cell := target_unit.get_projected_destination()

	# Reach must be judged by the attack the counter will ACTUALLY fire -- main, for a weapon --
	# not by whatever this unit last aimed with. Reading the live pick here let a melee unit
	# counter from a reach attack's range and then swing a range-1 main (#102).
	return Reach.can_hit_cell_from(countering_unit, counter_cell, target_cell, countering_unit.get_counter_attack())

func choose_counter_target(countering_unit: Unit, attacking_party: Array[Unit]) -> Unit:
	# Taunt (Reaction, docs/design/jobs.md "The ability chassis"): a standing policy, never a
	# prompt — counters against the taunter's party must target the taunter WHERE LEGAL.
	# First legal taunter in member order wins (deterministic, Law #1); an unreachable taunter
	# falls through to the default policy below rather than suppressing the counter.
	for member in attacking_party:
		if member.has_live_ability(Abilities.Id.TAUNT) and can_counter(countering_unit, member):
			return member
	# Default policy (C3 placeholder): first legal member.
	for member in attacking_party:
		if can_counter(countering_unit, member):
			return member
	return null

# C8 -- a reaction's KIND is its source's AttackData.heals, and the two kinds aim opposite ways.
# A damaging source picks from the attacking party (above, unchanged); a healing one turns inward
# and can never pick an enemy. Forked off the same flag the resolver, the executor and the reach
# overlay already read, rather than a second way to ask "is this a heal" (#148).
func _choose_reaction_target(reacting_unit: Unit, attacking_party: Array[Unit], hypo: Dictionary) -> Unit:
	if _reaction_heals(reacting_unit):
		return choose_reaction_heal_target(reacting_unit, hypo)
	return choose_counter_target(reacting_unit, attacking_party)

func _reaction_heals(reacting_unit: Unit) -> bool:
	var source := reacting_unit.get_counter_attack()
	return source != null and source.heals

# C9 -- the ally a reactive heal lands on. Two rules that must stay separate: "below max HP" is a
# FILTER, "lowest HP" is the sort. Collapsed into one, a full 19/19 unit outranks a hurt 20/23 one,
# which is the exact thing the dev ruled out. Ties fall to _all_units order, the same first-in-
# order tie-break choose_counter_target uses (Law #1).
func choose_reaction_heal_target(healer: Unit, hypo: Dictionary = {}) -> Unit:
	var best: Unit = null
	var best_hp := 0
	for candidate in _all_units():
		if not can_reaction_heal(healer, candidate, hypo):
			continue
		var hp := PlanResolver.projected_hp(candidate, hypo)
		if best == null or hp < best_hp:
			best = candidate
			best_hp = hp
	return best

# May this healer's reaction land on that unit? Everything HP-shaped is read off the threaded
# hypothetical, because the attacks have already resolved into it and not onto the board -- read
# live, the healer would pick whoever was hurt BEFORE the swing and skip the squadmate who just
# took it. A DOWNED ally is excluded outright (dev call, #148): a heal moves HP but never lifts
# lifecycle_state, so healing a body would silently eat the squad's whole reaction.
func can_reaction_heal(healer: Unit, candidate: Unit, hypo: Dictionary = {}) -> bool:
	if healer == null or candidate == null:
		return false
	if not is_instance_valid(healer) or not is_instance_valid(candidate):
		return false
	if not healer.attack_source_can_counter():
		return false
	var source := healer.get_counter_attack()
	if source == null or not source.heals:
		return false
	# hits_self/hits_allies still decide who a heal may touch; allies_only strips the enemies an
	# ordinary aim is allowed to splash. Without it the reaction tops up the attacker (C8).
	if not RulesService.is_attack_victim(healer, candidate, source, true):
		return false
	if PlanResolver.projected_lifecycle(candidate, hypo) != Unit.LifecycleState.ACTIVE:
		return false
	if PlanResolver.projected_hp(candidate, hypo) >= candidate.get_max_hp():
		return false
	# Same reach test can_counter applies, judged by the attack that will actually fire (#102).
	return Reach.can_hit_cell_from(healer, healer.get_projected_destination(), candidate.get_projected_destination(), source)

# Every reaction the defending parties get, in RESOLUTION ORDER: damaging ones first, healing ones
# after (C10). That ordering is the whole reason #148 needed no separate post-counter stage --
# PlanResolver.resolve_counters walks this list in order, so a reactive heal already lands after
# any counter that ally-splashed its own squad.
#
# ONE walk, ONE ledger. C1 (a unit reacts once per plan) and C4 (a party responds once per
# attacking squad's plan) are bookkeeping, and a second sweep for heals would have to keep its own
# copy of it -- two answers to "has this party reacted yet", free to drift (Law #4).
func calculate_reactions_for_squad(attacking_squad: Squad, attacks: Array[AttackAction], hypo: Dictionary = {}) -> Array[CounterAttackAction]:
	var strikes: Array[CounterAttackAction] = []
	var heals: Array[CounterAttackAction] = []
	var defender_groups_that_countered := {} # {Squad : bool}
	var attacking_units = attacking_squad.get_members()

	for attack in attacks:
		var defender := attack.target
		if defender == null or not is_instance_valid(defender):
			continue

		var defender_squad = defender.squad

		if defender_groups_that_countered.has(defender_squad):
			continue

		for reacting_unit in defender.squad.get_members():
			var reaction_target := _choose_reaction_target(reacting_unit, attacking_units, hypo)
			if reaction_target == null:
				continue

			var reaction := CounterAttackAction.new()
			reaction.init_counter(reacting_unit, reaction_target, reacting_unit.get_projected_destination(), attack)
			if _reaction_heals(reacting_unit):
				heals.append(reaction)
			else:
				strikes.append(reaction)

		defender_groups_that_countered[defender_squad] = true

	strikes.append_array(heals)
	return strikes
	
func resolve_plan(squad: Squad, board: BoardContext) -> ResolvedPlan:
	var plan := ResolvedPlan.new()
	var hypo: Dictionary = plan.hypo   # threaded here, kept on the plan for end-of-pass reads (#124)
	var reactions := ReactionCatalog.get_all()
	var terrain_reactions := TerrainReactionCatalog.get_all()

	# Knockback uses projected positions as its single source of truth (#84, approach B). Clear last
	# pass's shove projections before recomputing; a unit's own queued move is untouched.
	for unit in board.units:
		unit.clear_projected_knockback()

	# Expand each stored AIM order into a fresh volley from CURRENT projected positions (#15):
	# AoE victims are derived data, never stored. RulesService.gather_attack_victims is already
	# projection-aware, so a re-planned move re-targets the blast — like counters.
	#
	# Each aim is expanded AND RESOLVED before the next is expanded (#105). A shove only becomes a
	# projected position once its attack has resolved, so expanding every volley up front put all
	# victim-gathering strictly before all shoves: aiming at a landing cell found nobody, and a unit
	# shoved OUT of a later blast was still hit by it. Interleaving costs nothing — same order,
	# same hypo, same cell-effect sequence.
	for action in squad.action_queue:
		if action.action_type != BaseAction.ActionType.ATTACK:
			continue
		var aim := action as AttackAction
		var origin := aim.actor.get_projected_destination()
		var affected := Reach.get_affected_cells_from(aim.actor, origin, aim.target_cell, aim.fired_attack)
		var victims := RulesService.gather_attack_victims(aim.actor, affected, board, aim.fired_attack)
		var group: Array[AttackAction] = []
		if victims.is_empty():
			# #47: a legal aim at cells with no unit still resolves — a cell-targeted attack
			# (target stays null = no unit hit). It plays out and is where terrain effects will
			# land (#50). Units are a CONSEQUENCE of the aimed cells, not the gate.
			var cell_attack := AttackAction.create(aim.actor, origin, null, aim.target_cell)
			cell_attack.fired_attack = aim.fired_attack
			group.append(cell_attack)
		else:
			group = AttackAction.create_volley(aim.actor, origin, aim.target_cell, victims, aim.fired_attack)

		# Back-link every derived action to the order that produced it -- read by the whiff clause
		# and the queue row's tint. One place, so a new expansion branch can't forget it.
		for atk in group:
			atk.source_aim = aim
		plan.attacks.append_array(group)

		# Resolve THIS aim, then publish its shoves as projected positions — so the next aim's
		# victim gather, the counter derivation below, and the board preview all read where the
		# target LANDS (#84 approach B, extended to same-plan attacks by #105).
		PlanResolver.resolve_attack_group(group, plan, hypo, reactions, board, terrain_reactions)
		for atk in group:
			if atk.resolved != null and atk.resolved.knockback_applied and atk.target != null and is_instance_valid(atk.target):
				atk.target.set_projected_knockback(atk.resolved.knockback_to)

	# Reactions are derived as single-target "aims" (who reacts to whom, strike or heal). Expand
	# each into its own volley from the reactor's projected cell — the same AoE + friendly-fire
	# gather the attack loop above uses — so an AoE counter splashes everyone in the blast, not
	# just its chosen target. (Parallels the #15 "derive victims, don't store" rule for attacks.)
	for aim in calculate_reactions_for_squad(squad, plan.attacks, hypo):
		var c_origin := aim.actor.get_projected_destination()
		var c_aim_cell := aim.target.get_projected_destination()
		# The counter's own attack drives its footprint AND its friendly-fire rule, matching what
		# create_counter_volley stamps below (#102).
		var c_attack := aim.actor.get_counter_attack()
		# A reaction HEAL's splash is ally-only (C8). Without this the target pick is correct and
		# the volley still tops the attacker up, because an enemy in the footprint is an ordinary
		# victim -- #148's bug one layer down from where it was reported. A player-AIMED heal keeps
		# its enemy splash; that is agency, and only the derived reaction is restricted (dev call).
		var healing := c_attack != null and c_attack.heals
		var c_affected := Reach.get_affected_cells_from(aim.actor, c_origin, c_aim_cell, c_attack)
		var c_victims := RulesService.gather_attack_victims(aim.actor, c_affected, board, c_attack, healing)
		for ctr in CounterAttackAction.create_counter_volley(aim.actor, c_origin, c_victims, aim.source_attack):
			plan.counters.append(ctr)
	# Phase 2: counters, now built from post-shove positions.
	PlanResolver.resolve_counters(plan, hypo, reactions, board, terrain_reactions)

	# Burrow (#84): each queued Burrow order deposits a permanent COVER tile on the burrower's
	# projected cell. Routed through cell_effects so preview + execution consume the same object
	# (R3) — it serializes and draws for free, exactly like an elemental terrain deposit.
	if board != null:
		for action in squad.action_queue:
			if action.action_type != BaseAction.ActionType.BURROW:
				continue
			var cover := ResolvedCellEffect.new()
			cover.cell = action.actor.get_projected_destination()
			cover.states_added.append(Terrain.TileState.COVER)
			plan.cell_effects.append(cover)

	_last_resolved_plan = plan
	_last_resolved_squad = squad
	return plan

# The most recent resolve for THIS squad, or null. The gate's rescue clause and the menu's
# candidate list read it the way the whiff clause reads published knockback (#124): a candidate
# is judged against the ALREADY-QUEUED prefix, and the last resolve is exactly that prefix —
# every queue change re-resolves synchronously (game.refresh_action_queue), so it cannot be
# stale for the squad being commanded. Callers that never resolved (AI builders, bare test
# fixtures) get null and fall back to live-board rules.
func resolved_plan_for(squad: Squad) -> ResolvedPlan:
	if squad != null and is_instance_valid(squad) and _last_resolved_squad == squad:
		return _last_resolved_plan
	return null


# A dead unit leaves the board entirely, so it just detaches.
func handle_unit_death(unit: Unit) -> void:
	_remove_from_squad_and_revalidate(unit, false)

# A downed unit SURVIVES as a body on the board, so it can't be left squad-less (invariant: every
# unit is in exactly one squad) — leave_squad detaches it AND gives it a fresh solo squad.
func handle_unit_downed(unit: Unit) -> void:
	_remove_from_squad_and_revalidate(unit, true)

# Shared cleanup: silently drop the unit's planned orders (a death/down is not an order
# cancellation, and the cancel handlers would restore squad badges), pull it out of its squad,
# then re-validate whatever's left behind.
func _remove_from_squad_and_revalidate(unit: Unit, keep_on_board: bool) -> void:
	var squad := unit.squad
	if squad == null or not is_instance_valid(squad):
		return

	squad._remove_actions_for_actor_silent(unit)

	if keep_on_board:
		leave_squad(unit)
	else:
		_detach_from_current_squad(unit)

	if is_instance_valid(squad) and not squad.get_members().is_empty():
		validate_squad_plan(squad)
		overlay_manager.redraw_planned_paths()

# --- squad-formation eligibility (migrated from game.gd, #22) ---

func can_create_any_squad(creating_unit: Unit) -> bool:
	if creating_unit.has_squad() or creating_unit.squad.has_acted:
		return false
	for unit in _all_units():
		if can_squad_up(unit, creating_unit.squad):
			return true
	return false

func can_join_any_squad(joining_unit: Unit) -> bool:
	for unit in _all_units():
		if can_join_squad(joining_unit, unit.squad) and unit.squad.leader.has_squad() and not unit.squad.has_acted and not joining_unit.squad.has_acted:
			return true
	return false

# Shared by both formation checks: in range of the leader, room in the squad, same faction, not
# already a member, and neither side has spent its turn.
func _formation_basics_ok(unit: Unit, squad: Squad) -> bool:
	if not SquadCohesion.in_range(squad, squad.leader.movement.cell, unit, unit.movement.cell, board_source.call()):
		return false
	if squad.members.size() >= squad.max_size():
		return false
	if squad.leader.get_faction() != unit.get_faction():
		return false
	if squad.get_members().has(unit):
		return false
	return not squad.has_acted and not unit.squad.has_acted

# Pulling a loose unit INTO a squad being formed: the recruit must be solo and both sides must
# still be order-free, since squad membership can't change once a plan exists.
func can_squad_up(joining_unit: Unit, squad: Squad) -> bool:
	if not _formation_basics_ok(joining_unit, squad):
		return false
	if joining_unit.has_squad() or joining_unit.has_any_actions():
		return false
	return squad.action_queue.is_empty()

# Joining an ALREADY-FORMED squad — so the target's leader must actually have squadmates.
func can_join_squad(unit: Unit, squad: Squad) -> bool:
	if not _formation_basics_ok(unit, squad):
		return false
	return squad.leader.has_squad()

func _all_units() -> Array[Unit]:
	# Every unit belongs to exactly one managed squad (solo units get a 1-member squad),
	# so flattening squad membership enumerates the whole board exactly once — and replaces
	# game.gd's units_root sweep, which these predicates no longer have access to.
	var result: Array[Unit] = []
	for squad in squads:
		for member in squad.get_members():
			result.append(member)
	return result
	
# --- Group Move ---
# The formation solver itself lives in GroupMoveSolver (split out 2026-07-26). This is the
# COMMITTING half: same plan, queued through the Law #3 chokepoint and drawn on the board.

func queue_group_move(squad: Squad, leader_destination: Vector2i, board: BoardContext, allowed_cells = null) -> bool:
	var moves := GroupMoveSolver.plan(squad, leader_destination, board, allowed_cells)

	# One player action, so one fan-out. Note `batching` also covers the hold-position moves that
	# setup_hold_move_actions queues when the squad first activates — those fire the same signal.
	batching = true
	var queued: Array[MoveAction] = []
	for move in moves:
		if queue_action(squad, move):
			queued.append(move)
	batching = false

	validate_squad_plan(squad)

	# All or nothing (#103) -- a rare BACKSTOP since cohesion stopped refusing an outrun member, so
	# what reaches here is a destination CONFLICT. Scope is every MOVE in the queue, not just this
	# batch's; all-hold is legal by construction.
	for action in squad.action_queue:
		if action.action_type == BaseAction.ActionType.MOVE and not action.is_valid:
			for member in squad.get_members():
				cancel_move_for_unit(member)
			# A hold-only queue is not an activation -- otherwise the squad stays `active` behind an
			# open panel with no X and no Execute.
			revert_if_only_hold(squad)
			overlay_manager.redraw_planned_paths()
			overlay_manager.redraw_projected_units()
			return false

	for move in queued:
		overlay_manager.show_planned_path(move.actor, move)
		overlay_manager.show_projected_unit(move.actor, move.destination)
	overlay_manager.redraw_planned_paths()
	overlay_manager.redraw_projected_units()
	# Re-emit for the last order so listeners do their squad-level repaint exactly once. Reusing
	# the existing signal keeps the batch invisible to everyone downstream.
	if not queued.is_empty():
		squad_action_queued.emit(squad, queued[queued.size() - 1])
	return true

func _register_squad_signals(squad: Squad):
	if not squad.action_cancelled.is_connected(_on_squad_action_cancelled):
		squad.action_cancelled.connect(_on_squad_action_cancelled)
	if not squad.actions_became_active.is_connected(_on_squad_became_active):
		squad.actions_became_active.connect(_on_squad_became_active)
	if not squad.actions_became_empty.is_connected(_on_squad_became_empty):
		squad.actions_became_empty.connect(_on_squad_became_empty)
	if not squad.action_queued.is_connected(_on_squad_action_queued):
		squad.action_queued.connect(_on_squad_action_queued)

func _on_squad_action_queued(squad: Squad, action: BaseAction):
	squad_action_queued.emit(squad, action)

func _on_squad_action_cancelled(squad: Squad, unit: Unit, actiontype: BaseAction.ActionType):
	squad_action_cancelled.emit(squad, unit, actiontype)

func _on_squad_became_active(squad: Squad, action: BaseAction):
	squad_became_active.emit(squad, action)

func _on_squad_became_empty(squad: Squad):
	squad_became_empty.emit(squad)
