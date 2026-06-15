extends Resource
class_name ScenarioData

@export var scenario_name := ""
@export var unit_entries: Array[ScenarioUnitEntry] = []
@export var tile_data: PackedByteArray
@export var turn_phase: int = 0 # TurnManager.TurnPhase; 0 = PLAYER, 1 = ENEMY
@export var active_faction: Team.Faction = Team.Faction.PLAYER # whose turn it was when saved
