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

func take_faction_turn(faction: Team.Faction, board: BoardContext) -> void:
	for squad in game.squad_manager.squads.duplicate():
		# The mission can end mid-turn -- this squad's pass may have wiped the player. Stop
		# issuing orders behind the end-of-mission card (#96).
		if game.mission_controller.is_over():
			return
		if not is_instance_valid(squad) or squad.has_acted:
			continue
		if squad.leader.get_faction() != faction or not squad.leader.is_active():
			continue

		await game.camera_controller.pan_to(squad.get_leader())
		for member in squad.get_members():
			member.active_attack = null   # fresh pick each turn -- a stale winner from last turn would skew reach queries (mirrors _begin_attack's reset)
		AIArchetype.resolve(squad.archetype).call(squad, board, game.squad_manager)
		# The plan is on screen now -- queueing repaints the queue panel, path arrows, ghosts and
		# target markers synchronously -- so hold before resolving it (#118). Skipped when the squad
		# only holds position: there is nothing to read, and dead air per squad is the complaint.
		if not game.squad_manager.only_hold_actions(squad):
			await Pacing.beat(self, Pacing.AI_PLAN_READ)
		await game.order_executor.execute_orders(squad.get_leader())

	if game.mission_controller.is_over():
		return
	await game.end_turn()
