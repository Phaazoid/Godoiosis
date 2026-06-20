extends RefCounted
class_name BoardContext

# The slice of world the rules read: terrain (grid), occupancy (units), and
# planned moves (squad_manager, for projected positions). game.gd builds this from
# its live nodes; the headless PlaySession (M2) builds it from its own — so
# RulesService runs identically in-game and headless. See docs/play-api.md.

var grid: TileMapLayer
var units: Array[Unit]
var squad_manager: SquadManager

func _init(grid_layer: TileMapLayer, unit_list: Array[Unit], manager: SquadManager) -> void:
	grid = grid_layer
	units = unit_list
	squad_manager = manager

func unit_at_cell(cell: Vector2i) -> Unit:
	for unit in units:
		if is_instance_valid(unit) and unit.movement.cell == cell:
			return unit
	return null

func is_walkable(cell: Vector2i) -> bool:
	var tile_data: TileData = grid.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	return tile_data.get_custom_data("walkable")

func projected_unit_at_cell(cell: Vector2i) -> Unit:
	if squad_manager == null:
		return null
	return squad_manager.get_projected_unit_from_cell(cell)
