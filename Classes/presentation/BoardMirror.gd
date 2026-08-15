extends Node3D
class_name BoardMirror

# The Battle3D board mirror (#215 / #176 stage 4a): paints the 3D GridMap from the
# LIVE 2D grid — the hidden game is the authority, this only reads. Boards mirror
# FLAT (column height 1) because the sim has no elevation yet — the diorama's hills
# arrive when the rules do.
#
# WHICH BLOCK a cell gets is two questions, and Kind was answering both until #250:
#   surface  — what the top face looks like. The 2D answers this with the tile's
#              ATLAS COORDS, so item_for_cell asks the same thing (Law #4: mirror
#              the question, not a field downstream of it). Four grass variants are
#              four looks, and a fence stops being drawn as a tree.
#   material — what the cell is made of, i.e. the side/wall texture. Still Kind,
#              which is the vocabulary that is actually good at it.
# KIND_TO_ITEM survives as the DECLARED FALLBACK for tiles the meshlib has no item
# for (multi-cell art, flipped alternatives, an atlas newer than the generator run),
# so a cell can never come out with no block at all.
#
# PROPS stand up (#255). A tile whose art depicts an object rather than ground carries
# `stands_up`, and this mirror gives it a billboarded sprite planted on the cell while
# the generator bakes that cell's top face as bare ground — so a tree is drawn ONCE,
# standing, not also lying flat under itself. Same per-cell reconcile as the fire
# markers, and the lantern borrows the torch's light.
#
# Fire-state cells (BURNING / BLAZE) get a flame billboard + a real OmniLight —
# the torch recipe, and the dev's "fire casts light" wish. Which cells burn is
# TerrainStateManager.burning_cells — the one enumeration form (Terrain.gd: "no
# reader may enumerate fire members itself").
#
# BOTH halves are LIVE as of #231, and both reconcile per cell rather than
# rebuilding. refresh_states() used to be re-read only at a turn boundary — a
# declared v1 approximation that made mid-pass ignitions late and made a flame
# that rendered wrong appear to "come back at the end of the turn". It is now
# polled (OverlayMirror, the poll-don't-wire doctrine), so a marker survives
# untouched across frames and allocation is proportional to fire CHANGES, which
# is normally none — strictly cheaper than the free-everything it replaces.
# sync() is the terrain twin: a per-cell diff against the live 2D grid, driven
# while the dev brush can paint, so painting shows up without an F2.

# NONE is the one declared skip: an authored tile with no kind still renders
# ground via FALLBACK_ITEM rather than a hole.
const KIND_TO_ITEM: Dictionary[Terrain.Kind, int] = {
	Terrain.Kind.GRASS: 0,
	Terrain.Kind.ROCK: 1,
	Terrain.Kind.DIRT: 3,
	Terrain.Kind.MUD: 4,
	Terrain.Kind.WATER: 5,
	Terrain.Kind.TREE: 6,
}
const FALLBACK_ITEM := 3  # dirt
const FLAME_TEXTURE_PATH := "res://Art/LookDev/torch_flame.png"

# Flame knobs (aesthetics get a knob, not a guess). See _make_fire for how lift and gap
# interact — the flame is CLAMPED off the ground, the knob cannot sink it back in.
@export var flame_lift := 0.35
@export var flame_size := Vector2(0.5, 0.7)
# Minimum clearance between the flame's bottom edge and the tile's top face. This is the
# z-fight gap, the flame's twin of BoardOverlays.fill_lift, and it is a CLAMP rather than
# an offset so no authored flame_lift can put the quad back into the ground plane.
@export var flame_ground_gap := 0.03
# FALSE restores the rendering the flame had before #236, which is the known-good look.
# #236 turned this on to stop a downed body swallowing the flame and bought constant
# z-fighting for a rare, self-correcting artefact — a bad trade, reverted by default
# (dev, 2026-08-14: "if anything, the z fighting is worse now"). The switch stays because
# the two modes fail in opposite directions and only an eye can rank them; see _make_fire.
@export var flame_writes_depth := false
@export var flame_light_energy := 2.0
@export var flame_light_range := 4.0

# How solid the brush preview reads. A knob, not a guess — it is a pure feel call (#231).
@export var brush_ghost_alpha := 0.45

# Which props light the board, by the ONE authored naming policy
# (GridUtils.authored_tile_display_name, so these are its capitalized forms). A SET rather than a
# colour table: WHICH props glow is content, while what the glow looks like is a feel call and
# lives in the knobs below. Keyed on the authored name because that is the identity that survives
# an atlas re-layout — a coordinate would not.
const LIT_PROPS: PackedStringArray = ["Lantern"]

# The lantern's light (#255, dev ask: "give it light like the torches"). Separate knobs from the
# flame's on purpose — a steady lamp and a fire are different looks, and one shared number would
# force whoever tunes the second to un-tune the first.
@export var prop_light_color := Color(1, 0.8, 0.5)
@export var prop_light_energy := 1.5
@export var prop_light_range := 3.5
@export var prop_light_height := 0.7

var board: GridMap

# How many terrain diffs have run. Read by the test that pins COALESCING — a drag
# crossing N cells inside one frame must cost one pass, not N.
var sync_passes := 0

# Keyed by cell, not a flat list: a reconcile has to answer "the marker for X", and the
# positional array this replaced could only answer it by freeing everything (#149's shape).
var _fire_markers: Dictionary[Vector2i, Node3D] = {}

# The standing props, keyed by cell — the same reconcile shape as the fire markers. Each node
# carries the TILE it was built from (PROP_TILE_META), because unlike fire a cell's prop can be
# REPLACED rather than merely added or removed: painting a rock over a tree leaves the cell in
# both the old and new wanted-set, and a keyed-by-cell-only reconcile would leave the tree
# standing forever.
const PROP_TILE_META := "prop_tile"
var _props: Dictionary[Vector2i, Node3D] = {}

var _brush_ghost: MeshInstance3D = null

# Meshlib item name -> id, built once off the library itself. The library IS the mapping;
# indexing it here beats storing a second table that could disagree with the artifact.
var _item_by_name: Dictionary[String, int] = {}
var _item_index_built := false


func rebuild(grid: TileMapLayer, burning: Array[Vector2i]) -> void:
	board.clear()
	sync(grid)
	refresh_states(burning)


# The live terrain diff: write only what differs, erase what the 2D no longer paints.
# board.clear() is deliberately NOT here — a wholesale repaint per motion event is the
# thing this exists to avoid; rebuild() owns the clear for a genuine board swap.
func sync(grid: TileMapLayer) -> void:
	sync_passes += 1
	var live: Dictionary[Vector2i, bool] = {}
	var propped: Dictionary[Vector2i, bool] = {}
	for cell in grid.get_used_cells():
		live[cell] = true
		var item := item_for_cell(grid, cell)
		var at := BoardSpace.of_flat(cell)
		if board.get_cell_item(at) != item:
			board.set_cell_item(at, item)
		# Props ride the SAME walk rather than a second pass over the same cells — this is the
		# terrain diff, and whether a cell carries a standing object is a terrain fact.
		if GridUtils.stands_up_at_cell(grid, cell):
			propped[cell] = true
			_reconcile_prop(grid, cell)
	_free_props_except(propped)
	# get_used_cells returns a copy, so erasing inside the walk is safe.
	for cell: Vector3i in board.get_used_cells():
		if not live.has(BoardSpace.flat(cell)):
			board.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)


# Add what is newly alight, free what went out, LEAVE STANDING what still burns. The last
# clause is the one with teeth: a marker that is rebuilt every frame looks identical
# through fire_marker_count(), so the pin is node identity, not the count.
func refresh_states(burning: Array[Vector2i]) -> void:
	var wanted: Dictionary[Vector2i, bool] = {}
	for cell in burning:
		wanted[cell] = true
		if not _fire_markers.has(cell):
			_fire_markers[cell] = _make_fire(BoardSpace.of_flat(cell))
	for cell: Vector2i in _fire_markers.keys():
		if not wanted.has(cell):
			_fire_markers[cell].queue_free()
			_fire_markers.erase(cell)


# Which meshlib item draws this cell — the SURFACE question, asked the way the 2D asks it.
# Falls back to the cell's Kind when the tile has no item of its own, so the answer is always
# a real block.
func item_for_cell(grid: TileMapLayer, cell: Vector2i) -> int:
	var item := item_for_tile(grid.get_cell_source_id(cell), grid.get_cell_atlas_coords(cell),
			grid.get_cell_alternative_tile(cell))
	if item != GridMap.INVALID_CELL_ITEM:
		return item
	return KIND_TO_ITEM.get(GridUtils.get_terrain_kind_at_cell(grid, cell), FALLBACK_ITEM)


# The tile's OWN item, or INVALID_CELL_ITEM when the meshlib has none. Three ways to get
# there, all deliberate: an empty cell (source -1), a flipped/rotated ALTERNATIVE, and a tile
# the generator skipped (multi-cell art, which cannot go onto a 1x1 top face un-squashed).
# INVALID_CELL_ITEM is the sentinel because it is already GridMap's own "no item" — this
# function never writes it to the board; item_for_cell converts it into the Kind block.
func item_for_tile(source_id: int, coords: Vector2i, alternative: int) -> int:
	if source_id == -1 or alternative != 0:
		return GridMap.INVALID_CELL_ITEM
	_ensure_item_index()
	return _item_by_name.get(tile_item_name(source_id, coords), GridMap.INVALID_CELL_ITEM)


# The ONE spelling of a tile's meshlib item name. tools/lookdev/gen_lookdev_assets.gd writes
# the items with this exact call, so the mapping cannot drift from the artifact it maps —
# there is no second table to keep in sync.
static func tile_item_name(source_id: int, coords: Vector2i) -> String:
	return "tile_%d_%d_%d" % [source_id, coords.x, coords.y]


func _ensure_item_index() -> void:
	if _item_index_built or board == null or board.mesh_library == null:
		return
	_item_index_built = true
	for id: int in board.mesh_library.get_item_list():
		_item_by_name[board.mesh_library.get_item_name(id)] = id


# The brush preview: the REAL block that would be painted, half-transparent (dev ruling —
# WYSIWYG beat the bracket I recommended). It runs item_for_cell against the 2D GHOST LAYER,
# which is the same function sync() runs against the real grid — so the preview physically
# cannot disagree with the paint that follows it; only the material differs.
func show_brush_ghost(cell: Vector2i, ghost: TileMapLayer) -> void:
	if ghost == null:
		hide_brush_ghost()
		return
	_ensure_brush_ghost()
	var item := item_for_cell(ghost, cell)
	var mesh: Mesh = board.mesh_library.get_item_mesh(item)
	if _brush_ghost.mesh != mesh:
		_brush_ghost.mesh = mesh
	# The item's own transform carries any authored offset/rotation; the cell supplies where.
	var item_xform: Transform3D = board.mesh_library.get_item_mesh_transform(item)
	var at := BoardSpace.of_flat(cell)
	_brush_ghost.transform = Transform3D(item_xform.basis, BoardSpace.cell_center(at) + item_xform.origin)
	_brush_ghost.visible = true


func hide_brush_ghost() -> void:
	if _brush_ghost == null or not _brush_ghost.visible:
		return
	_brush_ghost.visible = false


func _ensure_brush_ghost() -> void:
	if _brush_ghost != null:
		return
	_brush_ghost = MeshInstance3D.new()
	_brush_ghost.name = "BrushGhost"
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, brush_ghost_alpha)
	_brush_ghost.material_override = mat
	_brush_ghost.visible = false
	board.add_child(_brush_ghost)


func fire_marker_count() -> int:
	return _fire_markers.size()


# The flame node standing on a cell, or null. The identity read the persistence pin needs.
func fire_marker_at(cell: Vector2i) -> Node3D:
	return _fire_markers.get(cell)


# Where the flame's CENTRE sits above the tile's top face, clamped so its bottom edge always
# clears the ground by flame_ground_gap. A QuadMesh is centred on its origin, so the authored
# 0.35 lift against a 0.7-tall quad put the bottom edge at exactly y = 0 — coplanar with the
# tile it stands on. That was invisible while the flame did not write depth and became the
# worst z-fighting on the board the moment it did (reported in play, 2026-08-14). Clamped
# rather than merely re-defaulted: the knob must not be able to author the bug back.
# Only clamped while the flame WRITES depth, because that is the only time coplanarity
# costs anything — the bottom edge sat in the ground plane harmlessly for months before
# #236 put the quad in the depth buffer. With depth off the authored lift stands, so the
# default configuration reproduces the pre-#236 look exactly rather than approximately.
func flame_base_lift() -> float:
	if not flame_writes_depth:
		return flame_lift
	return maxf(flame_lift, flame_size.y * 0.5 + flame_ground_gap)


func _make_fire(cell: Vector3i) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = BoardSpace.standing_point(cell)

	var flame := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = flame_size
	var material := StandardMaterial3D.new()
	# DEPTH_PRE_PASS, not plain ALPHA: unit sprites are ALPHA_CUT_OPAQUE_PREPASS, so they
	# write depth and a pure-alpha flame is drawn afterwards and depth-TESTED against them.
	# A standing sprite is cut-out air around its feet so the flame showed through; a DOWNED
	# body is solid coverage at exactly ground level and swallowed it whole (reported in play
	# 2026-08-14 — the marker was never freed, only hidden). Matching the discipline puts both
	# in the same per-pixel sort.
	#
	# The knob exists because the two modes fail in OPPOSITE directions and only an eye can
	# say which is worse here: writing depth makes the flame fight anything near-coplanar
	# with it (its own tile, and a unit sprite standing on that tile — both are camera-facing
	# planes through the same point), while not writing depth makes it lose to whatever wrote
	# depth first, which is the swallowed-by-a-body bug. The ground half is fixed by geometry
	# below; this switch is for the sprite half.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS if flame_writes_depth \
			else BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0, 0, 0, 1)
	material.albedo_texture = load(FLAME_TEXTURE_PATH) as Texture2D
	material.emission_enabled = true
	material.emission = Color(1, 0.55, 0.15)
	material.emission_energy_multiplier = 2.5
	material.emission_texture = material.albedo_texture
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Above every overlay layer, structurally rather than by luck. Unset, this was 0 while
	# Layer.TERRAIN sorts at 2, so a frost icon painted onto a burning tile drew over the flame
	# and the fire read as ERASED (#245, found in play). Transparent materials draw in priority
	# order and this one does not write depth, so the sort IS the whole answer here.
	material.render_priority = BoardOverlays.FLAME_RENDER_PRIORITY
	quad.material = material
	flame.mesh = quad
	flame.position = Vector3(0, flame_base_lift(), 0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flame)

	_add_light(root, Color(1, 0.62, 0.3), flame_light_energy, flame_light_range, 0.6)
	return root


# The one "a thing standing on a cell casts light" recipe — the torch's, now also the lantern's
# (#255). Only the LIGHT is shared: a flame is a hand-built emissive quad with a knob-driven
# transparency mode and a prop is a plain Sprite3D, so a common visual builder would have had to
# change one of them. The values stay each caller's own knobs; what cannot drift is the shape.
func prop_count() -> int:
	return _props.size()


# The prop standing on a cell, or null. The identity read the reconcile pin needs — a prop
# rebuilt every frame looks identical through prop_count().
func prop_at(cell: Vector2i) -> Node3D:
	return _props.get(cell)


# Build the prop this cell wants, or leave the standing one alone when it is already the right
# tile. The tile comparison is what makes REPLACEMENT work: painting a rock onto a tree keeps the
# cell in the wanted-set, so a cell-only check would leave the tree standing.
func _reconcile_prop(grid: TileMapLayer, cell: Vector2i) -> void:
	var coords: Vector2i = grid.get_cell_atlas_coords(cell)
	var tile := Vector3i(grid.get_cell_source_id(cell), coords.x, coords.y)
	var standing: Node3D = _props.get(cell)
	if standing != null:
		if standing.get_meta(PROP_TILE_META) == tile:
			return
		standing.queue_free()
		_props.erase(cell)
	var built := _make_prop(grid, cell)
	if built == null:
		return
	built.set_meta(PROP_TILE_META, tile)
	_props[cell] = built


func _free_props_except(wanted: Dictionary[Vector2i, bool]) -> void:
	for cell: Vector2i in _props.keys():
		if not wanted.has(cell):
			_props[cell].queue_free()
			_props.erase(cell)


# A billboarded sprite of the tile's own art, standing on the cell that paints it.
func _make_prop(grid: TileMapLayer, cell: Vector2i) -> Node3D:
	var texture := _prop_texture(grid, cell)
	if texture == null:
		return null
	var root := Node3D.new()
	add_child(root)
	root.position = BoardSpace.standing_point(BoardSpace.of_flat(cell))

	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Unit sprites' discipline: cut-out alpha that WRITES DEPTH, so a unit standing behind a tree
	# sorts correctly in 3D and no render_priority has to be hand-maintained against it.
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.shaded = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Tied to the TILESET's tile size, never to UnitSprite3D.texels_per_unit: a tile is one cell
	# wide BY DEFINITION, which is what makes a 1x2 lantern two cells tall and what lets a future
	# 32px sheet drop in without touching this.
	sprite.pixel_size = 1.0 / float(GridUtils.TILE_SIZE)
	sprite.layers = BoardOverlays.WORLD_RENDER_LAYER
	# Pivot at the BASE. A Sprite3D centres on its origin, so lifting it half its own height plants
	# the bottom edge on the tile instead of burying half the prop in the ground.
	sprite.offset = Vector2(0, texture.region.size.y * 0.5)
	root.add_child(sprite)

	if LIT_PROPS.has(GridUtils.authored_tile_display_name(grid.get_cell_tile_data(cell))):
		_add_light(root, prop_light_color, prop_light_energy, prop_light_range, prop_light_height)
	return root


# The tile's own art, region-cut from the tileset atlas. Multi-cell art comes through WHOLE — the
# 1x2 lantern is a 16x32 sprite — which is exactly what a 1x1 top face could not carry, and why
# the lantern arrives with this pass rather than with 5a's.
func _prop_texture(grid: TileMapLayer, cell: Vector2i) -> AtlasTexture:
	var tiles := grid.tile_set
	if tiles == null:
		return null
	var atlas := tiles.get_source(grid.get_cell_source_id(cell)) as TileSetAtlasSource
	if atlas == null:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = atlas.texture
	texture.region = Rect2(atlas.get_tile_texture_region(grid.get_cell_atlas_coords(cell), 0))
	return texture


func _add_light(root: Node3D, color: Color, energy: float, omni_range: float, height: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = omni_range
	light.position = Vector3(0, height, 0)
	root.add_child(light)
	return light
