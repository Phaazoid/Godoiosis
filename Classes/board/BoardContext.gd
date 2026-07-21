extends RefCounted
class_name BoardContext

# The slice of world the rules read: terrain (grid), occupancy (units), and
# planned moves (squad_manager, for projected positions). game.gd builds this from
# its live nodes; the headless PlaySession (M2) builds it from its own — so
# RulesService runs identically in-game and headless. See docs/play-api.md.

var grid: TileMapLayer
var units: Array[Unit]
var squad_manager: SquadManager
var terrain_states: TerrainStateManager
var zones: ZoneManager

func _init(grid_layer: TileMapLayer, unit_list: Array[Unit], manager: SquadManager, states: TerrainStateManager = null, zone_manager: ZoneManager = null) -> void:
	grid = grid_layer
	units = unit_list
	squad_manager = manager
	terrain_states = states
	zones = zone_manager

func unit_at_cell(cell: Vector2i) -> Unit:
	for unit in units:
		if is_instance_valid(unit) and unit.movement.cell == cell:
			return unit
	return null

func is_walkable(cell: Vector2i) -> bool:
	if terrain_states != null and terrain_states.has_state(cell, Terrain.TileState.FROZEN):
		return true
	var tile_data: TileData = grid.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	return tile_data.get_custom_data("walkable")

func projected_unit_at_cell(cell: Vector2i) -> Unit:
	if squad_manager == null:
		return null
	return squad_manager.get_projected_unit_from_cell(cell)
	
# The rules' single read-point for a cell's static kind (#50): reads the tileset's
# "terrain_type" int layer as a Terrain.Kind. A method (not an inline grid read in the
# resolver) so tests can stub it — the headless fixture grid has no TileSet to paint.
func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
	return GridUtils.get_terrain_kind_at_cell(grid, cell)
	
# Census over this board's units — shared by game.gd and the headless PlaySession so the
# turn cycle's membership/auto-skip reads have ONE implementation.
func present_factions() -> Array[Team.Faction]:
	# Factions with at least one living unit (active OR downed) — downed units keep their
	# faction in the cycle so its downed clocks keep ticking; dead units are excluded.
	var seen: Dictionary = {}
	var result: Array[Team.Faction] = []
	for unit in units:
		if not is_instance_valid(unit) or unit.is_dead():
			continue
		var f := unit.get_faction()
		if not seen.has(f):
			seen[f] = true
			result.append(f)
	return result

func faction_has_active_units(faction: Team.Faction) -> bool:
	for unit in units:
		if is_instance_valid(unit) and unit.get_faction() == faction and unit.is_active():
			return true
	return false

func has_active_units() -> bool:
	for unit in units:
		if is_instance_valid(unit) and unit.is_active():
			return true
	return false
