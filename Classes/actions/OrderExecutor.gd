extends Node
class_name OrderExecutor

# Runs a squad's queued plan against the board, then settles the fallout. One pass:
# resolve -> moves (parallel) -> attacks (sequential) -> cell effects -> counters ->
# side-channel verbs -> eject whoever went down. Pulled out of game.gd 2026-07-26; holds a
# back-ref to the Game coordinator (same pattern as DevController/AIController/MainActionMenu)
# for the managers and panels it drives.
#
# Every plan resolves through execute_orders() -- the queue panel's Execute button, the action
# menu's Execute Orders entry, and AIController all land here. That single path is what keeps
# Law #2 honest (the queue previewed exactly this pass) and Law #3 cheap (the AI has no side
# channel to add).
#
# The headless Play API (play/play_session.gd) deliberately keeps its OWN twin of this
# sequence -- no animation, no awaits, no prompts. The two are documented mirrors: a phase
# added here needs the same phase added there.

var game   # the Game coordinator (Node2D); set by game._ready()

# Units downed mid-execution. Squad ejection is DEFERRED to the end of the pass -- restructuring
# squads while execute_orders sat mid-await was buggy. The Crisis OFFER is deliberately NOT
# deferred; see _offer_pending_crisis.
var _downed_pending: Array[Unit] = []

# ==============================================================================
#  Resolving a plan
# ==============================================================================

func execute_orders(unit):
	var squad = unit.squad

	game.squad_manager.validate_squad_plan(squad)
	game.overlay_manager.redraw_planned_paths()
	game.refresh_action_queue(squad)

	if game.squad_manager.squad_has_invalid_actions(squad):
		# A human gets control BACK here: flash the bad rows, leave the plan queued, let them fix it
		# and press Execute again. An AI squad has nobody to hand control back TO -- nothing in the
		# turn cycle mutates the state that produced the plan, so the identical plan is refused every
		# turn while the board keeps its ghosts and the squad never acts (#103). It concedes instead:
		# however a plan turns out, an AI pass must reach _end_squad_turn.
		if game.ai_controller.is_ai_faction(squad.leader.get_faction()):
			push_warning("AI squad conceded its turn: %s" % _invalid_plan_summary(squad))
			_end_squad_turn(squad)
			return
		for action in squad.action_queue:
			if not action.is_valid:
				action.actor.visuals.play_invalid_flash()
		return

	game.clear_selection_icons()

	# Explicit types throughout: `game` is untyped (game.gd has no class_name), so every
	# game.* call reads as Variant and `:=` cannot infer from it.
	var plan: ResolvedPlan = game.squad_manager.resolve_plan(squad, game._board())
	var move_actions := []
	var side_channel: Dictionary[BaseAction.ActionType, Array] = {}

	game.overlay_manager.clear_knockback_preview()
	for action in squad.action_queue.duplicate():
		action.actor.visuals.set_projected(false)
		if action.action_type == BaseAction.ActionType.MOVE:
			move_actions.append(action)
		elif BaseAction.SIDE_CHANNEL_ORDER.has(action.action_type):
			if not side_channel.has(action.action_type):
				side_channel[action.action_type] = []
			side_channel[action.action_type].append(action)

	await _execute_action_phase_parallel(move_actions)
	await _execute_action_sequence(plan.attacks)
	_apply_cell_effects(plan.cell_effects)
	await _execute_action_sequence(plan.counters)
	for type in BaseAction.SIDE_CHANNEL_ORDER:
		var batch: Array = side_channel.get(type, [])
		await _execute_action_sequence(batch)
	_process_downed_pending()
	# The pass has settled: this is where a mission is won or lost (#96, fork E). Before the
	# squad-validity guard below -- a squad that wiped itself must not skip the check.
	game.mission_controller.check()

	if not is_instance_valid(squad):
		return

	_end_squad_turn(squad)

# The terminal state of a squad's turn, and the ONE place it is defined: no orders queued, no
# projection or path arrows left, and the squad marked as having spent its turn. Reached at the end
# of a successful pass AND from the invalid-plan concede above (#103).
#
# set_has_acted does most of the visual work for free -- Squad._set_has_acted clears the queue, and
# every action_cancelled hop lands in game._on_unit_action_cancelled, which is what pulls a move's
# ghost and arrow. The icon clear ahead of it is for the TARGET markers a queued attack drew; the
# success path also clears them before it animates, and clearing twice is idempotent.
func _end_squad_turn(squad: Squad) -> void:
	game.clear_selection_icons()
	for action in squad.action_queue.duplicate():
		action.actor.visuals.set_projected(false)
		game.squad_manager.remove_action(squad, action)
	game.squad_manager.set_has_acted(squad, true)
	for member in squad.members:
		game.overlay_manager.clear_planned_path(member)

# Why a concede happened, for the console: an AI cannot see a red flash, so this is the only place
# the refusal is visible at all.
func _invalid_plan_summary(squad: Squad) -> String:
	var lines: Array[String] = []
	for action in squad.action_queue:
		if not action.is_valid:
			lines.append("%s: %s" % [action.actor.get_unit_name(), ", ".join(action.validation_errors)])
	return " | ".join(lines)

func _execute_action_phase_parallel(actions: Array):
	if actions.is_empty():
		return

	for action in actions:
		action.begin_execution()

	for action in actions:
		action.execute()

	while true:
		var all_complete := true

		for action in actions:
			if not action.execution_complete:
				all_complete = false
				break
		if all_complete:
			return

		await get_tree().process_frame

func _execute_action_sequence(actions: Array):
	if actions.is_empty():
		return

	for action in actions:
		action.begin_execution()
		action.execute()

		while not action.execution_complete:
			await get_tree().process_frame

		await _offer_pending_crisis()   # live Crisis interrupt: fire the instant a unit drops, before the next hit

# Play the resolved terrain deposits into the live store, then redraw the board (#50). Runs after
# the attack phase that produced them. Burning-only for now; generalizes as more tile states land.
func _apply_cell_effects(cell_effects: Array[ResolvedCellEffect]) -> void:
	for effect in cell_effects:
		game.terrain_states.apply(effect)
	game.overlay_manager.redraw_terrain_live(game.terrain_states)

# ==============================================================================
#  End-of-phase damage
# ==============================================================================

# End-of-phase burn: a unit standing in fire when ITS faction's turn ends takes damage. Routed
# through take_damage so downs/kills apply, then the crisis-offer + eject the attack pass uses.
func apply_burning_tile_damage(faction: Team.Faction) -> void:
	for cell in game.terrain_states.cells_with(Terrain.TileState.BURNING):
		var unit: Unit = game.get_unit_at_cell(cell)
		if unit != null and unit.is_active() and unit.get_faction() == faction:
			unit.take_damage(Terrain.BURNING_TILE_DAMAGE)
	await _offer_pending_crisis()
	_process_downed_pending()

# ==============================================================================
#  Downed units + Crisis
# ==============================================================================

func on_unit_downed(unit: Unit) -> void:
	# The down fires INSIDE AttackAction.execute(). The unit's state (DOWNED, 1 HP) is already
	# set in _go_downed; defer the squad/overlay cleanup until the execution pass settles, so
	# we never mutate squads while execute_orders is mid-await.
	if not _downed_pending.has(unit):
		_downed_pending.append(unit)

func _process_downed_pending() -> void:
	if _downed_pending.is_empty():
		return
	for unit in _downed_pending:
		if not is_instance_valid(unit) or unit.is_queued_for_deletion():
			continue   # finished off later in the same pass -- the death path already cleaned it up
		game.overlay_manager.handle_unit_death(unit)   # clear its planning overlays (not its board presence)
		game.squad_manager.handle_unit_downed(unit)    # eject into a solo squad -- safe now, execution is over
	_downed_pending.clear()
	game.refresh_action_queue(game.squad_manager.active_squad)

func _offer_pending_crisis() -> void:
	# Crisis is a LIVE interrupt (will-and-death.md): the offer must fire the moment a unit goes
	# down -- BEFORE a later hit in the same pass kills the downed unit. We poll between hits here
	# (the sequence loop is already async) instead of awaiting inside the synchronous take_damage
	# path, and instead of the old end-of-pass offer (which never fired when a follow-up counter
	# finished the unit first). Squad ejection stays deferred to _process_downed_pending.
	for unit in _downed_pending.duplicate():
		if not is_instance_valid(unit) or unit.is_queued_for_deletion():
			continue
		if unit.crisis_offered_pending:
			unit.crisis_offered_pending = false
			if await _offer_crisis(unit):
				unit.enter_crisis()
				_downed_pending.erase(unit)   # back on its feet -- not ejected at pass end

func _offer_crisis(unit: Unit) -> bool:
	# Non-player factions decide by archetype stance -- deterministic, so the player's queue
	# previewed this exact outcome (Law #2; R9: enemy Crisis is never a BREAK). The PLAYER
	# faction keeps the live prompt, except when AI-driven (dev toggle) -- nothing to block on.
	if unit.get_faction() != Team.Faction.PLAYER or game.ai_controller.is_ai_faction(unit.get_faction()):
		return AIArchetype.accepts_crisis(unit.squad.archetype)
	return await CrisisPrompt.show_prompt(game.ui_layer, unit.get_unit_name())
