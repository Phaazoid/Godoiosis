extends Node
class_name AIController

# Runs archetype AI (#29) for AI-controlled factions. Orders funnel through
# SquadManager.queue_action exclusively (Law #3) -- this class only decides WHEN an
# archetype plans, then reuses game.execute_orders (the same path the player's Execute
# button takes) so a bot turn resolves identically to a human one.
#
# Two independent layers. ENABLED is per-faction and session-only (Dev Overlay -> Scenario
# tab checkboxes) -- a kill switch that always reverts a faction to manual control, never
# persisted. ARCHETYPE (AIArchetype.Type) is per-squad and persists WITH the scenario
# (Squad.archetype, saved via ScenarioUnitEntry.squad_archetype on the leader's entry).

var game   # the Game coordinator; set by game._ready()

var _enabled: Dictionary = {}   # Faction -> bool; unset factions fall back to DEFAULT_ENABLED
const DEFAULT_ENABLED := false  # off by default -- opt in per faction from the dev console

func is_faction_ai_enabled(faction: Team.Faction) -> bool:
	return _enabled.get(faction, DEFAULT_ENABLED)

func set_faction_ai_enabled(faction: Team.Faction, enabled: bool) -> void:
	_enabled[faction] = enabled

func is_ai_faction(faction: Team.Faction) -> bool:
	return is_faction_ai_enabled(faction)

func take_faction_turn(faction: Team.Faction, board: BoardContext) -> void:
	for squad in game.squad_manager.squads.duplicate():
		if not is_instance_valid(squad) or squad.has_acted:
			continue
		if squad.leader.get_faction() != faction or not squad.leader.is_active():
			continue

		await game.camera_controller.pan_to(squad.get_leader())
		AIArchetype.resolve(squad.archetype).call(squad, board, game.squad_manager)
		await game.execute_orders(squad.get_leader())

	await game.end_turn()
