extends Node
class_name AIController

# Runs archetype AI (#29) for AI-controlled factions. Orders funnel through
# SquadManager.queue_action exclusively (Law #3) -- this class only decides WHEN an
# archetype plans, then reuses OrderExecutor.execute_orders (the same path the player's
# Execute button takes) so a bot turn resolves identically to a human one.
#
# Two independent layers, and since #150 both are BOARD CONTENT. ENABLED is per-faction,
# carried by ScenarioData.ai_factions and applied on every load -- the Dev Overlay -> Scenario
# tab checkboxes are the live override, no longer the only source. ARCHETYPE (AIArchetype.Type)
# is per-squad (Squad.archetype, saved via ScenarioUnitEntry.squad_archetype on the leader's).

var game   # the Game coordinator; set by game._ready()

var _enabled: Dictionary = {}   # Faction -> bool; unset factions fall back to DEFAULT_ENABLED
const DEFAULT_ENABLED := false  # off by default -- opt in per faction from the dev console

func is_faction_ai_enabled(faction: Team.Faction) -> bool:
	return _enabled.get(faction, DEFAULT_ENABLED)

func set_faction_ai_enabled(faction: Team.Faction, enabled: bool) -> void:
	_enabled[faction] = enabled

func is_ai_faction(faction: Team.Faction) -> bool:
	return is_faction_ai_enabled(faction)

# The enabled set, in Team.all_factions() order -- deterministic, so re-saving an unchanged
# board produces no spurious .tres churn.
func ai_factions() -> Array[Team.Faction]:
	var result: Array[Team.Faction] = []
	for faction in Team.all_factions():
		if is_faction_ai_enabled(faction):
			result.append(faction)
	return result

# REPLACES the whole set, never adds to it (#150): an unlisted faction falls back to
# DEFAULT_ENABLED, so one board's flags cannot leak into the next board loaded.
func set_ai_factions(factions: Array[Team.Faction]) -> void:
	_enabled.clear()
	for faction in factions:
		_enabled[faction] = true

# WHICH SQUADS a faction still has to act with. Static and game-free because the headless Play
# API takes an AI turn too (#665), and "which squads act" must have ONE answer -- a second walk
# would drift the moment either side grew a skip condition (Law #4). What genuinely differs
# between the two callers is PRESENTATION (camera, pacing) and EXECUTION (animated orders versus
# the headless resolve), and those stay at the callers where they belong.
#
# The caller must STILL revalidate inside its loop: acting with one squad can kill another's
# leader or disband it outright, so this is the starting list, not a promise about later.
static func actable_squads(faction: Team.Faction, squad_manager: SquadManager) -> Array[Squad]:
	var out: Array[Squad] = []
	for squad: Squad in squad_manager.squads.duplicate():
		if is_squad_actable(squad, faction):
			out.append(squad)
	return out


static func is_squad_actable(squad: Squad, faction: Team.Faction) -> bool:
	return is_squad_previewable(squad, faction) and not squad.has_acted


# The same question with the SPENT clause removed (#710 plan tier): could this squad act if its
# turn came round now? A split rather than a second predicate -- the shared half is shared.
#
# has_acted is cleared by reset_faction_actions for the INCOMING faction only, so during the
# player's turn every enemy squad still carries last turn's true. Asking is_squad_actable there
# returns an empty list from turn 2 onward, and an empty preview reads as "nobody is attacking
# you" under the always-attack ruling -- a silent lie. The flag is about the turn that FINISHED;
# the preview is about the turn that is coming.
static func is_squad_previewable(squad: Squad, faction: Team.Faction) -> bool:
	if not is_instance_valid(squad):
		return false
	if squad.leader == null or squad.leader.get_faction() != faction:
		return false
	return squad.leader.is_active()


# ONE squad's DECISION -- the archetype call, and the stale-pick reset that has to precede it.
# No camera, no pacing, no execution: the caller owns those. Orders still reach the board only
# through SquadManager.queue_action inside the archetype, so Law #3 is unaffected by the split.
static func plan_squad(squad: Squad, board: BoardContext, squad_manager: SquadManager) -> void:
	for member in squad.get_members():
		member.active_attack = null   # fresh pick each turn -- a stale winner from last turn would skew reach queries (mirrors _begin_attack's reset)
	AIArchetype.resolve(squad.archetype).call(squad, board, squad_manager)


# ==============================================================================
#  The threat preview (#710 plan tier)
# ==============================================================================

# What every faction hostile to `viewer` will DO next turn, against the board as the viewer's
# pending plan will leave it. Runs the real archetypes through the real SquadManager (Law #3) and
# rolls every order back, so nothing here is a second implementation of how the AI decides.
#
# THE MECHANISM IS A POSITIONAL SNAPSHOT: every unit is stood on its projected cell for the
# duration. That is what makes the answer honest, and it replaces fixing the reads one at a time --
# AITactics chooses targets and walks from movement.cell in eight places, compute_move_range starts
# there too, and the whiff gate positions a foreign unit there as well. Moving the units answers
# all of them at once and edits no rules code. Safe because planning is wholly synchronous (the
# only awaits in this file are in take_faction_turn) and MovementComponent.set_cell is already the
# teleport door a rescue haul and the deployment swap use; no frame renders mid-preview, so the
# board never draws a unit anywhere but where it stands.
# The instance door: supplies which factions this controller drives, and nothing else.
func preview_faction_turn(viewer: Team.Faction) -> Array[ThreatIntent]:
	return preview_turn(viewer, game.squad_manager, ai_factions())


# STATIC and game-free, for actable_squads' own reason (#665): the headless Play API is a second
# caller, and "what will the enemy do" must have ONE answer. The board comes from the manager's
# own board_source -- the same fresh-per-call door every rule already reads through (#151).
# How many squads the LAST preview actually planned, as opposed to skipped. The early-out's only
# observable -- it changes what the preview COSTS and never what it says, so without this a mutant
# that disables it passes every behavioural case. Quoted in docs/performance.md, and what a
# one-squad-per-frame fallback would budget against.
static var previewed_squad_count := 0


static func preview_turn(viewer: Team.Faction, sm: SquadManager,
		factions: Array[Team.Faction]) -> Array[ThreatIntent]:
	var intents: Array[ThreatIntent] = []
	previewed_squad_count = 0
	sm.previewing = true

	var saved := {}
	for unit: Unit in (sm.board_source.call() as BoardContext).units:   # units_root only -- a grid-less reserve unit would push_error
		saved[unit] = unit.movement.cell
	for unit: Unit in saved:
		unit.movement.set_cell(unit.get_projected_destination())

	var board: BoardContext = sm.board_source.call()   # fresh, so every read below sees the projected cells
	var field := ThreatField.build(board, viewer)
	for faction in factions:
		if not Team.is_enemy(viewer, faction):
			continue
		for squad: Squad in sm.squads.duplicate():
			if not is_squad_previewable(squad, faction):
				continue
			if not _squad_can_reach_anyone(squad, field, board):
				continue   # exact and free: the field is a superset of what this squad could aim at
			previewed_squad_count += 1
			intents.append_array(_preview_squad(squad, board, sm, saved))

	for unit: Unit in saved:
		unit.movement.set_cell(saved[unit])
	_undress(sm)
	sm.previewing = false
	return _merged(intents)


# ONE squad's intentions, with the board handed back exactly as it arrived. The rollback is the
# risky half of this feature and its order matters: active_squad goes back FIRST, because the
# cancel path draws squad icons when it names the squad being cleared.
static func _preview_squad(squad: Squad, board: BoardContext, sm: SquadManager, saved: Dictionary) -> Array[ThreatIntent]:
	var out: Array[ThreatIntent] = []
	var was_active: Squad = sm.active_squad
	var was_home: Vector2i = squad.home_cell
	var picks := {}
	for member: Unit in squad.get_members():
		picks[member] = member.active_attack
	assert(squad.action_queue.is_empty(), "preview: a hostile squad held orders -- the hand-off drain (#709) should have shed them")

	AIController.plan_squad(squad, board, sm)
	var plan: ResolvedPlan = sm.resolve_plan(squad, board)
	for attack: AttackAction in plan.attacks:
		var intent := _intent_for(attack, plan, saved)
		if intent != null:
			out.append(intent)

	sm.active_squad = was_active
	squad._clear_all_actions()
	squad.home_cell = was_home
	for member: Unit in picks:
		member.active_attack = picks[member]
	return out


# One resolved row -> one intent, or null when the row is not a threat TO somebody. The damage is
# the queue panel's own subtraction (ActionQueueRow), not a second spelling of it, so the number on
# the line and the number in the panel can never disagree.
static func _intent_for(attack: AttackAction, plan: ResolvedPlan, saved: Dictionary) -> ThreatIntent:
	var victim: Unit = attack.target
	if victim == null or not is_instance_valid(victim) or attack.resolved == null:
		return null   # a cell attack (#47) threatens nobody by itself
	if not Team.is_enemy(attack.actor.get_faction(), victim.get_faction()):
		return null   # friendly fire is not an intention against the viewer
	var outcome: ResolvedOutcome = attack.resolved
	if outcome.skipped:
		return null
	var after: int = LethalityRules.displayed_hp(outcome.target_hp_after,
			LethalityRules.lifecycle_for(outcome.lethality))
	return ThreatIntent.make(attack.actor, victim,
			saved.get(attack.actor, attack.actor.movement.cell),
			victim.movement.cell,   # the snapshot cell: where the plan puts them when it lands
			maxi(outcome.hp_before - after, 0),
			PlanResolver.plan_fells(victim, plan.hypo))


# ONE line per attacker/target pair, whatever the plan spread across volley rows, watch shots and
# counters. Order is preserved so the readout is stable between recomputes.
static func _merged(intents: Array[ThreatIntent]) -> Array[ThreatIntent]:
	var by_key := {}
	var out: Array[ThreatIntent] = []
	for intent: ThreatIntent in intents:
		var key := intent.key()
		if by_key.has(key):
			var kept: ThreatIntent = by_key[key]
			kept.damage += intent.damage
			kept.fells = kept.fells or intent.fells
			continue
		by_key[key] = intent
		out.append(intent)
	return out


# Could this squad attack ANYBODY from anywhere it can stand? Read off the slice-1 field, which is
# built on the projected board here and is a superset of what the squad's own builder will aim at
# (tests/ai/test_threat_field.gd pins that), so a false is a proof rather than an estimate.
#
# ITS BITE SHRINKS AS RANGES GROW -- a long-enough weapon reaches the whole board and nothing is
# ever skipped. That is the honest behaviour, not a defect; see docs/performance.md.
static func _squad_can_reach_anyone(squad: Squad, field: ThreatField, board: BoardContext) -> bool:
	var faction := squad.leader.get_faction()
	for member: Unit in squad.get_members():
		for cell: Vector2i in field.by_unit.get(member, {}):
			var occupant: Unit = board.unit_at_cell(cell)
			if occupant != null and Team.is_enemy(faction, occupant.get_faction()):
				return true
	return false


# Hand the board back undressed. The last previewed resolve published its shoves onto the viewer's
# units and left itself in the resolve cache; both have to go, or get_projected_destination answers
# with an enemy's hypothetical and the #313 bars read someone else's plan. Re-resolving the viewer's
# own squad is what puts their shoves and their cache entry back.
static func _undress(sm: SquadManager) -> void:
	for unit: Unit in (sm.board_source.call() as BoardContext).units:
		unit.clear_projected_knockback()
		unit.clear_projected_rescue()
	if sm.active_squad != null and is_instance_valid(sm.active_squad):
		sm.resolve_plan(sm.active_squad, sm.board_source.call())


# THE BOARD IS RE-DERIVED PER SQUAD, and it takes no board parameter for exactly that reason (#714).
# This used to build one BoardContext for the whole turn while `execute_orders` between squads spans
# frames, so a unit an earlier squad KILLED was genuinely freed by the time a later squad planned --
# and `_resolve_actions`' clear loop calls a method on every unit the board lists. Everything else it
# got wrong was quieter: for the rest of the turn the AI targeted, pathed and measured cohesion
# against a roster including the dead.
#
# `play_session._take_ai_turn` has always called `_board()` inside its own loop, which is why the
# headless API never reproduced it -- two live implementations of one walk, and the crash lived in
# whichever one was not the model. This is now the same shape.
func take_faction_turn(faction: Team.Faction) -> void:
	for squad in actable_squads(faction, game.squad_manager):
		# The mission can end mid-turn -- this squad's pass may have wiped the player. Stop
		# issuing orders behind the end-of-mission card (#96).
		if game.mission_controller.is_over():
			return
		# Revalidated per iteration, not merely filtered once above: the squad that just acted
		# may have downed this one's leader.
		if not is_squad_actable(squad, faction):
			continue

		# NO CAMERA HERE (#987). This used to open with pan_to(squad.get_leader()) and then hold for
		# AI_PLAN_READ, and both were in the wrong place: the pan ran BEFORE plan_squad, so the shot
		# that opened every AI squad was committed while its destination was still unchosen and could
		# only ever centre the unit's start cell -- against the dev's own ruling that the opening
		# shot should show both ends of the move. (It also pushed IN, pan_to ending in follow(),
		# which is what the shot table reads as a trained subject.)
		#
		# Both moved into OrderExecutor's move phase, which is where the walk's span is known, so the
		# opening shot is the walk's own framing rather than a second answer to where the squad is.
		# The plan is drawn by the queueing below and the camera arrives to it.
		#
		# board_source is the wired seam for "the board as it stands", the same Callable
		# SquadManager's own validators resolve fresh per query.
		var board: BoardContext = game.squad_manager.board_source.call()
		plan_squad(squad, board, game.squad_manager)
		await game.order_executor.execute_orders(squad.get_leader())

	if game.mission_controller.is_over():
		return
	await game.end_turn()
