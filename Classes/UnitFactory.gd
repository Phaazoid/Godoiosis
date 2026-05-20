extends Object
class_name UnitFactory

static func create_unit(data: UnitData, grid: TileMapLayer, pos : Vector2i) -> Unit:
	var unit_scene = preload("res://Scenes/unit.tscn")
	var unit = unit_scene.instantiate()
	
	
	unit.setup(grid, pos)
	unit.unit_data = data

	return unit
	
#TODO move builder functions from dev_overlay here

static func create_unit_data(stats: Dictionary[String, int], name: String, faction: Team.Faction) -> UnitData:
	var data = UnitData.new()
	data.base_stats = stats
	data.display_name = name
	data.faction = faction
	
	return data
