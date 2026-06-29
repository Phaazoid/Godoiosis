extends Object
class_name GridUtils

const TERRAIN_ICONS := {
	"grass" : preload("res://Art/Icons/TerrainIcons/grass.png"),
	"rock" : preload("res://Art/Icons/TerrainIcons/rock.png"),
	"mud" : preload("res://Art/Icons/TerrainIcons/mud.png"),
	"error" : preload("res://Art/Icons/ArrowIcons/ERROR.png"),
	"tree" : preload("res://Art/Icons/TerrainIcons/tree.png"),
	"water" : preload("res://Art/Icons/TerrainIcons/water.png")
}


static func manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

static func cells_within_manhattan_range(origin: Vector2i, range: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	
	for x in range(origin.x - range, origin.x + range + 1):
		for y in range(origin.y - range, origin.y + range + 1):
			var cell = Vector2i(x, y)
			var dist = abs(cell.x - origin.x) + abs(cell.y - origin.y)
			
			if dist <= range:
				cells.append(cell)
	return cells

static func cardinal_direction_between(from_cell: Vector2i, to_cell: Vector2i) -> Vector2:
	var diff := to_cell - from_cell

	if diff == Vector2i.ZERO:
		return Vector2.ZERO

	if abs(diff.x) >= abs(diff.y):
		return Vector2(sign(diff.x), 0)

	return Vector2(0, sign(diff.y))
	
static func cardinal_direction_i_between(from_cell: Vector2i, to_cell: Vector2i) -> Vector2i:
	var dir := cardinal_direction_between(from_cell, to_cell)
	return Vector2i(int(dir.x), int(dir.y))

static func get_terrain_type_at_cell(grid: TileMapLayer, cell:Vector2i) -> String:
	var data := grid.get_cell_tile_data(cell)
	
	if data == null:
		return "error"
		
	if data.has_custom_data("terrain_type"):
		return str(data.get_custom_data("terrain_type"))
		
	return "error"
	
static func get_terrain_icon_at_cell(grid: TileMapLayer, cell: Vector2i) -> Texture2D:
	var terrain_type := get_terrain_type_at_cell(grid, cell)
	
	if TERRAIN_ICONS.has(terrain_type):
		return TERRAIN_ICONS[terrain_type]
		
	return TERRAIN_ICONS["error"]
	
static func validate_member_distance(unit: Unit) -> bool:
	var dist = manhattan_distance(unit.movement.cell, unit.squad.leader.movement.cell)
	if dist > unit.squad.get_max_range():
		return false
	else:
		return true

# Blended Manhattan/Chebyshev range (#25). `integral` = Manhattan reach; `and_a_half`
# bevels in the diagonal corners of that ring (Chebyshev <= integral AND Manhattan
# <= integral + 1): {1, true} = all 8 neighbours, {2, true} = next ring with corners
# clipped. No floats — the bool is the only legal fraction. cells_within_manhattan_range
# is deliberately left alone; this is the additive sibling.
static func cells_within_blended_range(origin: Vector2i, integral: int, and_a_half: bool) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var reach := integral + (1 if and_a_half else 0)
	# The [-integral, integral] iteration box already guarantees Chebyshev <= integral,
	# so inside we only test Manhattan against `reach`.
	for x in range(origin.x - integral, origin.x + integral + 1):
		for y in range(origin.y - integral, origin.y + integral + 1):
			var cell := Vector2i(x, y)
			if abs(cell.x - origin.x) + abs(cell.y - origin.y) <= reach:
				cells.append(cell)
	return cells
