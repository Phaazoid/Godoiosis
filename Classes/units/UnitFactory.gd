extends Object
class_name UnitFactory

static func create_unit(data: UnitData, grid: TileMapLayer, pos : Vector2i) -> Unit:
	var unit_scene = preload("res://Scenes/Unit.tscn")
	var unit = unit_scene.instantiate()
	
	
	unit.setup(grid, pos)
	unit.unit_data = data

	return unit
	
static func create_unit_data(
		stats: Dictionary[Stats.Stat, int],
		name: String,
		faction: Team.Faction,
		map_sprite: Texture2D = null,
		move_sprite: Texture2D = null,
		downed_sprite: Texture2D = null) -> UnitData:
	var data := UnitData.new()
	data.base_stats = stats
	data.display_name = name
	data.faction = faction
	if map_sprite != null:
		data.map_sprite = map_sprite
	if move_sprite != null:
		data.move_sprite = move_sprite
	if downed_sprite != null:
		data.downed_sprite = downed_sprite
	return data
