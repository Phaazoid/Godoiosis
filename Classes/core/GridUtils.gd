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
	Terrain.Kind.WATER: preload("res://Art/Icons/TerrainIcons/Water.png"),
	# DIRT is the first WALKABLE kind to get one (#554): an unmapped kind falls back to ERROR_ICON,
	# which VOID could get away with because nothing ever ends a move on a hole.
	Terrain.Kind.DIRT: preload("res://Art/Icons/TerrainIcons/Dirt.png")
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

# Every cell the center-to-center segment from `a` to `b` passes through, in order, ENDPOINTS
# EXCLUDED (#258's sight trace walks these). Supercover: an exact corner crossing includes BOTH
# side cells — conservative for line of sight, so a shot can never thread a diagonal seam between
# two walls. Integer arithmetic throughout (the crossing compare is cross-multiplied), so the walk
# is exact and deterministic (Law #1).
static func cells_crossed(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var nx := absi(b.x - a.x)
	var ny := absi(b.y - a.y)
	var sx := 1 if b.x > a.x else -1
	var sy := 1 if b.y > a.y else -1
	var p := a
	var ix := 0
	var iy := 0
	while ix < nx or iy < ny:
		# Next crossing times: (ix + 0.5) / nx vs (iy + 0.5) / ny, kept exact by cross-multiplying.
		var decision := (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		if decision == 0:
			cells.append(Vector2i(p.x + sx, p.y))
			cells.append(Vector2i(p.x, p.y + sy))
			p = Vector2i(p.x + sx, p.y + sy)
			ix += 1
			iy += 1
			if p != b:
				cells.append(p)
		elif decision < 0:
			p = Vector2i(p.x + sx, p.y)
			ix += 1
			if p != b:
				cells.append(p)
		else:
			p = Vector2i(p.x, p.y + sy)
			iy += 1
			if p != b:
				cells.append(p)
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

# Is there a tile here AT ALL (#245)? The one implementation of the question, called directly by
# everyone who asks it -- TerrainStateManager's ground_source is wired from it, and the dev pruner
# and BoardMirror reach it from where they stand.
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

# What FORM this tile's art wants in 3D (#264, widening #255's `stands_up` bool). A presentation
# fact with no existing answer, which is why it is authored rather than inferred -- every candidate
# rule has a counterexample in the sheet we ship: crate carries no kind and is a prop, pot is
# walkable and is a prop, hole carries no kind and is NOT one, and chest reads opaque while pot
# reads 48% open.
#
# FLAT is the ground itself. Everything else STANDS ON the ground, and the member says how it is
# built: BILLBOARD is a camera-facing sprite (thin, symmetric -- lamps, trees), the rest are real
# geometry (volumetric -- crates, rocks, barrels). The split is the dev's measured ruling on #255:
# "anything that's thin already works in this style"; blocky things "really want to be textures on
# a 3D model". PLANE is #263's oriented plane -- thin but DIRECTIONAL, a fence -- and it says only
# the FORM; which way it runs is the separate wall_edges question below. TUFT is #280's: WALKABLE
# GROUND with things growing on it -- flowers, a weed -- each standing up individually. It is the
# one shape whose cell keeps a ground face of its own rather than the bare kind base: the generator
# fills it with a speckle in the tile's own colours, because the plants were cut out of that tile
# and the kind base is a different green.
#
# APPEND-ONLY: the values are persisted in the tileset.
enum PropShape { FLAT, BILLBOARD, CUBE, FACETED, ROUND, PLANE, TUFT }

# Which shapes are real geometry rather than a sprite. Declared as a set so the renderer and the
# meshlib generator agree on what needs a mesh built for it, and adding a member is one line.
const SOLID_SHAPES: Array[PropShape] = [PropShape.CUBE, PropShape.FACETED, PropShape.ROUND,
		PropShape.PLANE]

# Which shapes ARE the ground rather than something sitting on it (#342). NOT the inverse of
# stands_up_of, and that is the whole point: a TUFT stands up AND is ground -- its plants are
# billboards, so it stands, while the cell itself is walkable ground with things growing out of it
# (#280). Those are two questions that happened to agree until TUFT existed.
const GROUND_SHAPES: Array[PropShape] = [PropShape.FLAT, PropShape.TUFT]

# Which cell EDGES a PLANE's wall runs out to (#263). A FLAG SET rather than a yaw, because a corner
# piece reaches TWO -- fence_tl runs east and south -- and one angle cannot say that. Each authored
# edge becomes a half-length slab from the cell centre out to it, so a straight run is two collinear
# halves (one wall) and a corner is two perpendicular ones (an L): one rule, no corner special case.
#
# A SECOND authored column beside prop_shape rather than more members on it, declared per Law #4:
# they answer different questions -- what form, and which way it runs -- and folding direction into
# the shape would mean PLANE_EW/PLANE_NS/PLANE_CORNER_ES... for one concept. The four cardinal
# VECTORS are deliberately not stored here: turning an edge into an offset is mesh knowledge, so that
# table lives beside the builder that consumes it (gen_lookdev_assets.gd), the way BoardMirror keeps
# RAMP_MESH_HIGH_SIDE beside the wedge it orients.
#
# APPEND-ONLY, and stored as a MASK -- bit values, not an index.
enum WallEdge { NORTH = 1, EAST = 2, SOUTH = 4, WEST = 8 }

# The two axes, as masks. Pure derivations of the enum above, so they live WITH it rather than in
# either reader: the meshlib generator asks which axis a slab runs along to decide whether it can wear
# the tile's own sprite, and the presentation suite asks the same question to check that it did.
const NS_EDGES := WallEdge.NORTH | WallEdge.SOUTH
const EW_EDGES := WallEdge.EAST | WallEdge.WEST


# Read by the 3D mirror (which stands the tile up in the right form) and by the meshlib generator
# (which then bakes that cell's top face as bare ground, and builds the mesh). An unauthored tile
# reads FLAT -- the same default the missing bool gave, so an untouched tile is unchanged.
static func prop_shape_of(data: TileData) -> PropShape:
	if data == null or not data.has_custom_data("prop_shape"):
		return PropShape.FLAT
	var raw: int = data.get_custom_data("prop_shape")
	return raw as PropShape


static func prop_shape_at_cell(grid: TileMapLayer, cell: Vector2i) -> PropShape:
	return prop_shape_of(grid.get_cell_tile_data(cell))


# The WallEdge mask this tile carries, 0 when unauthored. Read by the meshlib generator, which bakes
# the orientation into that tile's own mesh -- so nothing at runtime holds a yaw, and BoardMirror
# plants a fence with the same _make_prop_block it plants a crate with.
#
# This is the seam if a facing ever has to vary per PLACEMENT (a sheet with one generic fence tile
# used in both axes): the override lands HERE, in the reader, rather than as a second column.
static func wall_edges_of(data: TileData) -> int:
	if data == null or not data.has_custom_data("wall_edges"):
		return 0
	return data.get_custom_data("wall_edges")


static func wall_edges_at_cell(grid: TileMapLayer, cell: Vector2i) -> int:
	return wall_edges_of(grid.get_cell_tile_data(cell))


# Which of a PLANE's authored edges wear the TILE'S OWN SPRITE on their slab, rather than a face
# generated in the tile's colours (#554). The rest are generated.
#
# It exists because #263's answer was the AXIS -- east-west wore the sprite, north-south did not --
# and that is not a fact about walls, it is a fact about how this sheet draws a PALISADE: face-on
# across, foreshortened along. Masonry is drawn as a PLAN of its footprint in both axes, so its
# sprite is a picture of no wall at all: `stone_wall_hor_top` is opaque in 5 of its 16 rows, and
# stood up it renders as a ribbon floating over an invisible slab.
#
# Keyed on KIND because kind is already what the generator asks when it wants to know what a tile is
# MADE OF (a ROCK block wears stone down its sides, everything else wears dirt). Read by the meshlib
# generator ONLY -- both the pass that sizes the atlas and the pass that fills it, which is the whole
# reason it is one function: they must not disagree about how many patches a tile needs.
static func plane_own_art_edges(data: TileData) -> int:
	if terrain_kind_of(data) == Terrain.Kind.ROCK:
		return 0
	return EW_EDGES


# --- Per-OBJECT presentation fields (#272 slice 2) --------------------------------------------
#
# A terrain object may carry its own light and its own size; a global on BoardMirror is the DEFAULT
# it overrides (dev, 2026-08-16). These readers answer only "what did the author write", so the two
# layers stay separable: BoardMirror is the only place that knows a global exists, and a future
# second reader takes the RESOLVED value as a parameter rather than re-deriving the fallback.
#
# INHERIT IS A DECLARED SENTINEL, stated here and nowhere else, and it is ZERO because the storage
# leaves no choice: `TileData.has_custom_data(name)` answers whether the LAYER exists, never whether
# this tile authored a value, so an unauthored float reads the type's own 0.0. Any other sentinel
# would have to be written onto every field of every object tile -- a migration with nothing
# enforcing it for the next tile added.
#
# The cost is that a literal zero stops being authorable, and for these six fields that costs
# nothing real: a prop scaled to 0 is invisible, and a light with no energy or reach is what
# prop_lit = false already says, better. Measured against the alternative rather than assumed
# (dev, 2026-08-16).
const INHERIT := 0.0

# Does this object emit light at all? Pure CONTENT, and the one field with no global behind it --
# false is both the type default and the right answer for nearly every tile, which is what lets it
# replace BoardMirror's old LIT_PROPS name list outright rather than sit beside it.
static func prop_lit_of(data: TileData) -> bool:
	if data == null or not data.has_custom_data("prop_lit"):
		return false
	return data.get_custom_data("prop_lit")


# An authored float override, or INHERIT. One reader for all of them: the layer NAME is the only
# thing that differs, so a per-field copy would be five spellings of one guard.
static func prop_override_of(data: TileData, layer: String) -> float:
	if data == null or not data.has_custom_data(layer):
		return INHERIT
	return data.get_custom_data(layer)


# The colour twin, and it obeys the same storage rule the hard way: a Color layer's own default is
# OPAQUE BLACK (Color() is 0,0,0,1), not transparent, so the sentinel is blackness rather than
# alpha. A black light emits nothing, which is the same non-value a zero energy is -- so this costs
# exactly as little, and it is one rule with the float above rather than two.
static func prop_color_override_of(data: TileData, layer: String) -> Color:
	if data == null or not data.has_custom_data(layer):
		return INHERIT_COLOR
	return data.get_custom_data(layer)


const INHERIT_COLOR := Color(0, 0, 0, 1)


# <= rather than ==, so a value nudged fractionally below zero by a slider cannot land between
# "inherited" and "authored" and be neither.
static func is_inherited(value: float) -> bool:
	return value <= 0.0


# Alpha is deliberately ignored: a black light is a non-light at any opacity, and reading only the
# channels that matter means a stray alpha cannot strand a colour between the two states.
static func is_inherited_color(value: Color) -> bool:
	return value.r <= 0.0 and value.g <= 0.0 and value.b <= 0.0


# Does this tile stand on the ground rather than BE it? The question #255 asked, now derived from
# the shape rather than stored beside it -- the two could otherwise disagree.
static func stands_up_of(data: TileData) -> bool:
	return prop_shape_of(data) != PropShape.FLAT


static func stands_up_at_cell(grid: TileMapLayer, cell: Vector2i) -> bool:
	return stands_up_of(grid.get_cell_tile_data(cell))


# Is this tile's own surface the GROUND? Asked by anything deciding what may be shaped like terrain
# -- the tile brush's rise gate is the first (#342). An unauthored tile reads FLAT, so it is ground,
# the same permissive default prop_shape_of gives everywhere else.
static func is_ground_shape(data: TileData) -> bool:
	return GROUND_SHAPES.has(prop_shape_of(data))


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
	# #316: without this the getter errors and hands back an empty Rect2i, so a wrong coord
	# returns a non-null texture that draws NOTHING -- a failure that reads as success.
	if not source.has_tile(coords):
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
