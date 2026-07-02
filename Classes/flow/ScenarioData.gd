extends Resource
class_name ScenarioData

@export var scenario_name := ""
@export var unit_entries: Array[ScenarioUnitEntry] = []
@export var tile_data: PackedByteArray
@export var terrain_states: Dictionary = {}   # Vector2i -> Array[Terrain.TileState] deposited at runtime
@export var active_faction: Team.Faction = Team.Faction.PLAYER # whose turn it was when saved
@export var zones: Dictionary = {}   # String (zone name) -> Array[Vector2i], painted via Tile Brush's Zone mode
