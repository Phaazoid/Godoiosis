extends Object
class_name GridUtils

# Stateless grid math + tile-data reads shared by every layer (movement, targeting,
# overlays, dev tools): Manhattan/blended ranges, cardinal facings, and the tileset's
# terrain_type custom-data -> Terrain.Kind / icon lookups.

# The tileset's tile size in pixels — the single definition (CameraController and UnitVisuals
# each used to declare their own `TILE_SIZE = 16`). NB: a board CELL is two tiles wide; see
# CameraController.CELL_WORLD.
const TILE_SIZE := 16

# "No cell" sentinel — far outside any real board, so it can never collide with a live cell.
# One definition: game.gd/HoverPresenter used bare Vector2i(-999,-999) literals while Squad
# spelled the same idea Vector2i(-999999,-999999).
const NO_CELL := Vector2i(-999, -999)

const TERRAIN_ICONS: Dictionary[Terrain.Kind, Texture2D] = {
	Terrain.Kind.GRASS: preload("res://Art/Icons/TerrainIcons/Grass.png"),
	Terrain.Kind.ROCK: preload("res://Art/Icons/TerrainIcons/Rock.png"),
	Terrain.Kind.MUD: preload("res://Art/Icons/TerrainIcons/Mud.png"),
	Terrain.Kind.TREE: preload("res://Art/Icons/TerrainIcons/Tree.png"),
	Terrain.Kind.WATER: preload("res://Art/Icons/TerrainIcons/Water.png")
}

const ERROR_ICON: Texture2D = preload("res://Art/Icons/ArrowIcons/ERROR.png")


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

# Is there a tile here AT ALL (#245)? The one implementation of the question; BoardContext.has_ground
# is the rules layer's read-point onto it and TerrainStateManager's ground_source is wired from it.
# Deliberately the SOURCE id, not get_cell_tile_data: a headless fixture grid has cells placed but no
# TileSet to read custom data from, so the tile-data form would call every fixture cell groundless.
# A null grid cannot judge, so it does not — no board means no forbid, which is what keeps the
# bare-store terrain suites honest.
static func has_ground(grid: TileMapLayer, cell: Vector2i) -> bool:
	if grid == null:
		return true
	return grid.get_cell_source_id(cell) != -1

static func get_terrain_kind_at_cell(grid: TileMapLayer, cell: Vector2i) -> Terrain.Kind:
	return terrain_kind_of(grid.get_cell_tile_data(cell))


# The kind a TileData carries. Split out of get_terrain_kind_at_cell (#250) so a caller
# holding a tile rather than a placed cell -- the meshlib generator walks the TILESET, which
# has no board -- reads the same rule instead of copying it. Same shape as the
# authored_tile_display_name pair below.
static func terrain_kind_of(data: TileData) -> Terrain.Kind:
	if data == null or not data.has_custom_data("terrain_type"):
		return Terrain.Kind.NONE
	var raw: int = data.get_custom_data("terrain_type")
	return raw as Terrain.Kind

# Does this tile's ART depict an object STANDING ON the ground, rather than the ground itself
# (#255)? A presentation fact with no existing answer, which is why it is authored rather than
# inferred -- every candidate rule has a counterexample in the sheet we ship: crate carries no
# kind and is a prop, pot is walkable and is a prop, hole carries no kind and is NOT one, and
# chest reads opaque while pot reads 48% open. Read by the 3D mirror (which stands it up) and by
# the meshlib generator (which then bakes that cell's top face as bare ground).
static func stands_up_of(data: TileData) -> bool:
	if data == null or not data.has_custom_data("stands_up"):
		return false
	return data.get_custom_data("stands_up")


static func stands_up_at_cell(grid: TileMapLayer, cell: Vector2i) -> bool:
	return stands_up_of(grid.get_cell_tile_data(cell))


static func get_terrain_icon_at_cell(grid: TileMapLayer, cell: Vector2i) -> Texture2D:
	var kind := get_terrain_kind_at_cell(grid, cell)
	if TERRAIN_ICONS.has(kind):
		return TERRAIN_ICONS[kind]
	return ERROR_ICON

# The authored display name a tile carries (terrain_name custom data, capitalized), "" when
# unnamed. ONE naming policy for every surface that names a tile -- the brush palette rows and
# the hover card must not disagree (2026-08-12).
static func authored_tile_display_name(data: TileData) -> String:
	if data == null or not data.has_custom_data("terrain_name"):
		return ""
	var raw: String = data.get_custom_data("terrain_name")
	return raw.capitalize()

# A cell's center in the grid's GLOBAL space -- the one spelling of
# to_global(map_to_local(cell)), consolidated from 7 copies (#222). Callers assigning
# a LOCAL position keep the bare map_to_local half-form on purpose (different space).
static func cell_world(grid: TileMapLayer, cell: Vector2i) -> Vector2:
	return grid.to_global(grid.map_to_local(cell))

# The tile's own sprite, cut from its atlas sheet -- what the palette rows and the hover card
# draw. Rect2-wrapped: the getter returns Rect2i and AtlasTexture.region is Rect2, and Variant
# equality across the two is FALSE, which bites anything comparing regions later.
static func tile_sprite(source: TileSetAtlasSource, coords: Vector2i) -> Texture2D:
	if source == null:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = source.texture
	icon.region = Rect2(source.get_tile_texture_region(coords))
	return icon
	
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
