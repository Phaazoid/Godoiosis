extends Node3D
class_name BoardMirror

# The Battle3D board mirror (#215 / #176 stage 4a): paints the 3D GridMap from the
# LIVE 2D grid — the hidden game is the authority, this only reads.
#
# THE HILLS HAVE ARRIVED (#273). This mirrored flat, column height 1, on the stated promise that
# "the diorama's hills arrive when the rules do" — they did, in #257, and became authorable in
# #260. A cell now writes its whole COLUMN: the surface block repeated down to a shared floor
# (min(0, lowest painted level), so a dip has a bottom rather than a hole), and a ramp adds the
# generated wedge ONE level above its own, since a level-E block occupies [E..E+1] and a ramp
# whose elevation is its LOW side must slope from E+1 to E+2.
#
# The heights are PASSED IN, never looked up: the caller already holds the store, and this mirror
# reaching back into the game for it would be the second answer to "how tall is this cell".
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
# PROPS stand up (#255), and HOW they stand up is the tile's authored `prop_shape` (#264).
# The generator bakes a standing tile's top face as bare ground either way — so a tree is drawn
# ONCE, standing, not also lying flat under itself — and this mirror plants the object on it:
#   BILLBOARD  a camera-facing sprite. Thin, symmetric things: lamps, trees.
#   CUBE/FACETED/ROUND  real geometry from the meshlib, sides wearing the tile's own art and a
#              GENERATED top face. Volumetric things: crates, chests, rocks, barrels — the class the
#              dev judged "so odd" as billboards, because a 3/4 drawing has no top to show.
#   PLANE      real geometry too, but thin and DIRECTIONAL: a fence (#263). Which way it runs is the
#              tile's authored `wall_edges` mask, and the generator bakes that into the tile's OWN
#              mesh — so nothing here holds a yaw, and a fence is planted by the same
#              _make_prop_block that plants a crate.
# Same per-cell reconcile for all of them, and the lantern borrows the torch's light.
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

# The ramp wedge the generator emits (#273). A NAME, not an id, for the reason item_for_tile is
# name-keyed: gen_lookdev_assets.gd writes it under this exact string, so the mapping cannot drift
# from the artifact it maps.
const RAMP_ITEM_NAME := "dirt_ramp"

# Which way the authored wedge already climbs, in board space: its high edge is at -Z, and -Z is
# north. Every other rise is this rotated.
const RAMP_MESH_HIGH_SIDE := Vector3(0.0, 0.0, -1.0)
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
# (dev, 2026-08-14: "if anything, the z fighting is worse now"). NOT a choice between two
# artefacts, though it read as one for a day: OFF fights the unit sprite too (#298), since
# both are Y-billboards through one cell centre, i.e. one plane. The switch only picks
# which surface the flame argues with; see _make_fire.
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

# How tall a solid prop stands relative to its own art. A knob rather than a constant because the
# art is drawn in 3/4: a crate sprite includes some of its own lid, so the height measured off the
# sprite is always a little more than the object's front face really is. 1.0 is the measurement;
# the right number is whatever looks like a crate.
@export var block_height_scale := 1.0

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

# Where each tile's art actually sits, so a billboard is planted by its DRAWN pixels rather than by
# its region. Both caches are pure derivations of the tileset — a decoded sheet per source, a
# trimmed region per tile — and neither survives a board swap needing invalidation, because the
# tileset is the same object throughout a run.
var _art_images: Dictionary[int, Image] = {}
var _drawn_regions: Dictionary[Vector3i, Rect2i] = {}

var _brush_ghost: MeshInstance3D = null

# Meshlib item name -> id, built once off the library itself. The library IS the mapping;
# indexing it here beats storing a second table that could disagree with the artifact.
var _item_by_name: Dictionary[String, int] = {}
var _item_index_built := false


func rebuild(grid: TileMapLayer, heights: BoardHeights, burning: Array[Vector2i]) -> void:
	board.clear()
	sync(grid, heights)
	refresh_states(heights, burning)


func surface_point(cell: Vector2i, heights: BoardHeights) -> Vector3:
	return BoardSpace.surface_point(cell, heights)   # the one answer lives with the convention


# The live terrain diff: write only what differs, erase what the 2D no longer paints.
# board.clear() is deliberately NOT here — a wholesale repaint per motion event is the
# thing this exists to avoid; rebuild() owns the clear for a genuine board swap.
#
# The heights are PASSED, not looked up (#273): this already takes the grid the same way, and the
# mirror has no business reaching into the game for the store the caller is already holding.
func sync(grid: TileMapLayer, heights: BoardHeights) -> void:
	sync_passes += 1
	var floor_level := _floor_level(heights)
	var live: Dictionary[Vector2i, bool] = {}
	var propped: Dictionary[Vector2i, bool] = {}
	for cell in grid.get_used_cells():
		live[cell] = true
		_write_column(cell, item_for_cell(grid, cell), heights, floor_level)
		# Props ride the SAME walk rather than a second pass over the same cells — this is the
		# terrain diff, and whether a cell carries a standing object is a terrain fact.
		if GridUtils.stands_up_at_cell(grid, cell):
			propped[cell] = true
			_reconcile_prop(grid, cell, heights)
	_free_props_except(propped)
	# get_used_cells returns a copy, so erasing inside the walk is safe.
	for cell: Vector3i in board.get_used_cells():
		if not live.has(BoardSpace.flat(cell)):
			board.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)


# The lowest surface any column has to reach down to. A dip must have a bottom rather than a hole,
# and every column shares one floor so the board's underside stays flat. Clamped at 0 so an
# all-flat board writes exactly the one layer it always did.
func _floor_level(heights: BoardHeights) -> int:
	var lowest := 0
	for cell in heights.painted_cells():
		lowest = mini(lowest, heights.elevation_at(cell))
	return lowest


# One cell's whole COLUMN (#273): the surface block repeated down to the shared floor, which is the
# dev's call — BoardMirror already splits surface (top face, from atlas coords) from material (side
# texture, from Kind), so a stack of one block already reads as a cliff face of that material.
# Painting a DIFFERENT tile under a tile is a separate ticket he scoped out.
#
# A ramp adds its wedge ONE LEVEL ABOVE its own: a level-E block occupies [E..E+1], so level E's
# surface is at E+1, and a ramp whose own elevation is its LOW side must slope from E+1 up to E+2.
# That makes a ramp column read one cell taller than its flat neighbour, which is exactly what
# BoardPicker's "ramps count as full blocks" already assumes.
func _write_column(cell: Vector2i, item: int, heights: BoardHeights, floor_level: int) -> void:
	var level := heights.elevation_at(cell)
	var rise := heights.ramp_rise_at(cell)
	for y in range(floor_level, level + 1):
		var at := Vector3i(cell.x, y, cell.y)
		if board.get_cell_item(at) != item:
			board.set_cell_item(at, item)
	var top := level
	if rise != Terrain.RampRise.NONE:
		var wedge := Vector3i(cell.x, level + 1, cell.y)
		var orientation := _ramp_orientation(rise)
		if board.get_cell_item(wedge) != ramp_item() \
				or board.get_cell_item_orientation(wedge) != orientation:
			board.set_cell_item(wedge, ramp_item(), orientation)
		top = level + 1
	# LOWERING a cell strands everything the column used to hold above its new top. Walk up until
	# the column is genuinely clear rather than assuming one stale cell — a 5-level cut leaves 5.
	var above := top + 1
	while board.get_cell_item(Vector3i(cell.x, above, cell.y)) != GridMap.INVALID_CELL_ITEM:
		board.set_cell_item(Vector3i(cell.x, above, cell.y), GridMap.INVALID_CELL_ITEM)
		above += 1


# The wedge's meshlib id, asked of the LIBRARY rather than hardcoded — the same reason
# item_for_tile indexes by name: the library is the mapping, and a literal id here would silently
# point at whatever the generator emitted second.
func ramp_item() -> int:
	_ensure_item_index()
	return _item_by_name.get(RAMP_ITEM_NAME, GridMap.INVALID_CELL_ITEM)


# The generator draws the wedge with its high edge at -Z and notes that "GridMap orientation (yaw
# steps) points the high side at the upper level". -Z is NORTH in board space, so the yaw is
# DERIVED from Terrain.rise_direction — the same vocabulary the rules use — rather than a
# hand-written table of orthogonal indices that could drift from the mesh.
func _ramp_orientation(rise: Terrain.RampRise) -> int:
	var dir := Terrain.rise_direction(rise)
	if dir == Vector2i.ZERO:
		return 0
	var target := Vector3(dir.x, 0.0, dir.y)
	var angle := RAMP_MESH_HIGH_SIDE.signed_angle_to(target, Vector3.UP)
	return board.get_orthogonal_index_from_basis(Basis(Vector3.UP, angle))


# Add what is newly alight, free what went out, LEAVE STANDING what still burns. The last
# clause is the one with teeth: a marker that is rebuilt every frame looks identical
# through fire_marker_count(), so the pin is node identity, not the count.
func refresh_states(heights: BoardHeights, burning: Array[Vector2i]) -> void:
	var wanted: Dictionary[Vector2i, bool] = {}
	for cell in burning:
		wanted[cell] = true
		if not _fire_markers.has(cell):
			_fire_markers[cell] = _make_fire(surface_point(cell, heights))
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


# The same contract for a solid prop's geometry item (#264). A separate namespace rather than a
# suffix on the ground item, because the two answer different questions about one tile: what the
# cell's SURFACE looks like, and what STANDS on it.
static func prop_item_name(source_id: int, coords: Vector2i) -> String:
	return "prop_%d_%d_%d" % [source_id, coords.x, coords.y]


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
func show_brush_ghost(ghost: BrushGhost) -> void:
	if ghost == null or ghost.source == null:
		hide_brush_ghost()
		return
	_ensure_brush_ghost()
	# A ramp previews as the WEDGE one level above its own, the rule _write_column paints by: a
	# level-E block occupies [E..E+1], so the slope that starts at E's surface sits at E+1. A flat
	# paint previews the block that would become the column's new top.
	var ramping := ghost.rise != Terrain.RampRise.NONE
	var item := ramp_item() if ramping else item_for_cell(ghost.source, ghost.cell)
	var level := ghost.level + 1 if ramping else ghost.level
	var mesh: Mesh = board.mesh_library.get_item_mesh(item)
	if _brush_ghost.mesh != mesh:
		_brush_ghost.mesh = mesh
	# The item's own transform carries any authored offset/rotation; the cell supplies where. A
	# wedge needs the same yaw the real one gets, or the ghost previews a slope climbing elsewhere.
	var item_xform: Transform3D = board.mesh_library.get_item_mesh_transform(item)
	var basis := item_xform.basis
	if ramping:
		basis = board.get_basis_with_orthogonal_index(_ramp_orientation(ghost.rise)) * basis
	var at := BoardSpace.of_cell(ghost.cell, level)
	_brush_ghost.transform = Transform3D(basis, BoardSpace.cell_center(at) + item_xform.origin)
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


func _make_fire(at: Vector3) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = at

	var flame := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = flame_size
	var material := StandardMaterial3D.new()
	# DEPTH_PRE_PASS, not plain ALPHA: unit sprites are ALPHA_CUT_OPAQUE_PREPASS, so they
	# write depth and a pure-alpha flame is drawn afterwards and depth-TESTED against them.
	# #236 turned that on because a downed body swallowed the flame whole; that symptom no
	# longer reproduces and #243 is closed.
	#
	# What the switch does NOT do is trade one artefact for another, which is what this
	# comment claimed until #298. The marker root and the sprite origin share a cell centre
	# and both are BILLBOARD_FIXED_Y, so the two quads are not near-coplanar — they are the
	# SAME plane, and the flame fights the sprite either way. Swallowed vs. speckled is which
	# way the per-fragment precision fell. Only separating the planes reaches a clean frame,
	# and flame_lift cannot: Y is the one axis that does not separate them. The ground half
	# is fixed by the geometry below.
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
func _reconcile_prop(grid: TileMapLayer, cell: Vector2i, heights: BoardHeights) -> void:
	var coords: Vector2i = grid.get_cell_atlas_coords(cell)
	var tile := Vector3i(grid.get_cell_source_id(cell), coords.x, coords.y)
	var standing: Node3D = _props.get(cell)
	if standing != null:
		if standing.get_meta(PROP_TILE_META) == tile:
			return
		standing.queue_free()
		_props.erase(cell)
	var built := _make_prop(grid, cell, surface_point(cell, heights))
	if built == null:
		return
	built.set_meta(PROP_TILE_META, tile)
	_props[cell] = built


func _free_props_except(wanted: Dictionary[Vector2i, bool]) -> void:
	for cell: Vector2i in _props.keys():
		if not wanted.has(cell):
			_props[cell].queue_free()
			_props.erase(cell)


# The object standing on the cell that paints it, in whatever form its art asks for. The FORM is
# the only fork; everything around it — where it stands, what layer it draws on, whether it casts
# a shadow, whether it carries a light — is one answer for every prop.
func _make_prop(grid: TileMapLayer, cell: Vector2i, at: Vector3) -> Node3D:
	var shape := GridUtils.prop_shape_at_cell(grid, cell)
	var body: GeometryInstance3D = null
	if GridUtils.SOLID_SHAPES.has(shape):
		body = _make_prop_block(grid, cell)
	# A solid tile with no geometry item falls back to the billboard — the same declared fallback
	# item_for_cell makes, for the same reason: an atlas newer than the last generator run must
	# still draw SOMETHING rather than nothing.
	if body == null:
		body = _make_prop_billboard(grid, cell)
	if body == null:
		return null

	var root := Node3D.new()
	add_child(root)
	root.position = at
	body.layers = BoardOverlays.WORLD_RENDER_LAYER
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(body)

	if LIT_PROPS.has(GridUtils.authored_tile_display_name(grid.get_cell_tile_data(cell))):
		_add_light(root, prop_light_color, prop_light_energy, prop_light_range, prop_light_height)
	return root


# Real geometry, built by the meshlib generator: the tile's own sprite on the sides, a generated
# top face, sized to the art's opaque bounds. Null when this tile has no prop item.
func _make_prop_block(grid: TileMapLayer, cell: Vector2i) -> MeshInstance3D:
	if board == null or board.mesh_library == null:
		return null
	_ensure_item_index()
	var coords := grid.get_cell_atlas_coords(cell)
	var item_name := prop_item_name(grid.get_cell_source_id(cell), coords)
	if not _item_by_name.has(item_name):
		return null
	var node := MeshInstance3D.new()
	node.mesh = board.mesh_library.get_item_mesh(_item_by_name[item_name])
	# The mesh stands on y = 0 with its measured height, so the knob is a pure vertical stretch.
	node.scale = Vector3(1.0, block_height_scale, 1.0)
	return node


# A billboarded sprite of the tile's own art.
func _make_prop_billboard(grid: TileMapLayer, cell: Vector2i) -> Sprite3D:
	var texture := _prop_texture(grid, cell)
	if texture == null:
		return null
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Unit sprites' discipline: cut-out alpha that WRITES DEPTH, so a unit standing behind a tree
	# sorts correctly in 3D and no render_priority has to be hand-maintained against it.
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.shaded = true
	# Tied to the TILESET's tile size, never to UnitSprite3D.texels_per_unit: a tile is one cell
	# wide BY DEFINITION, which is what makes a 1x2 lantern two cells tall and what lets a future
	# 32px sheet drop in without touching this.
	sprite.pixel_size = 1.0 / float(GridUtils.TILE_SIZE)
	# Pivot at the BASE. A Sprite3D centres on its origin, so lifting it half its own height plants
	# the bottom edge on the tile instead of burying half the prop in the ground.
	sprite.offset = Vector2(0, texture.region.size.y * 0.5)
	return sprite


# The tile's own art, region-cut from the tileset atlas and TRIMMED to the pixels that are actually
# drawn. Multi-cell art still comes through whole — the 1x2 lantern is a 16x32 sprite — which is
# exactly what a 1x1 top face could not carry, and why the lantern arrives with a billboard.
#
# The trim is what plants it. A tile region may carry transparent padding: the lantern's art stops
# 5 rows above its region's bottom edge, so a quad planted by the REGION left the visible lamp
# floating 5/16 of a cell in the air (reported in play 2026-08-15; present since #255, and only
# obvious once the blocks beside it started sitting correctly). Trimming is a no-op for any sprite
# that already reaches its own edges — crate, chest, rock and tree all measure a 0px gap — so this
# can only move art that was floating.
func _prop_texture(grid: TileMapLayer, cell: Vector2i) -> AtlasTexture:
	var tiles := grid.tile_set
	if tiles == null:
		return null
	var source_id := grid.get_cell_source_id(cell)
	var atlas := tiles.get_source(source_id) as TileSetAtlasSource
	if atlas == null:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = atlas.texture
	texture.region = Rect2(_drawn_region(atlas, source_id, grid.get_cell_atlas_coords(cell)))
	return texture


# The tile's region narrowed to its drawn pixels, in ATLAS coordinates. Cached per tile: decoding an
# atlas sheet is not free and a prop is rebuilt whenever its cell's tile changes.
func _drawn_region(atlas: TileSetAtlasSource, source_id: int, coords: Vector2i) -> Rect2i:
	var key := Vector3i(source_id, coords.x, coords.y)
	if _drawn_regions.has(key):
		return _drawn_regions[key]
	var region := atlas.get_tile_texture_region(coords, 0)
	var image := _art_image(atlas, source_id)
	var drawn := region
	if image != null:
		var bounds := opaque_bounds(image, region)
		drawn = Rect2i(region.position + bounds.position, bounds.size)
	_drawn_regions[key] = drawn
	return drawn


# The atlas sheet as readable pixels, once per source. Imported textures arrive compressed, and
# get_pixel needs the decoded form.
func _art_image(atlas: TileSetAtlasSource, source_id: int) -> Image:
	if _art_images.has(source_id):
		return _art_images[source_id]
	var image: Image = null
	if atlas.texture != null:
		image = atlas.texture.get_image()
	if image != null:
		if image.is_compressed():
			image.decompress()
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
	_art_images[source_id] = image
	return image


# Where a tile's art actually sits inside its region, in tile-local pixels. ONE answer to a question
# both stacks ask: the meshlib generator sizes a solid prop's geometry by it, and the mirror plants a
# billboard by it. Falls back to the whole region when nothing is drawn, so a blank tile cannot
# produce a zero-sized sprite or mesh.
static func opaque_bounds(image: Image, region: Rect2i) -> Rect2i:
	var min_p := region.size
	var max_p := Vector2i(-1, -1)
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if image.get_pixel(x, y).a < 0.5:
				continue
			var p := Vector2i(x, y) - region.position
			min_p = Vector2i(mini(min_p.x, p.x), mini(min_p.y, p.y))
			max_p = Vector2i(maxi(max_p.x, p.x), maxi(max_p.y, p.y))
	if max_p.x < 0:
		return Rect2i(Vector2i.ZERO, region.size)
	return Rect2i(min_p, max_p - min_p + Vector2i.ONE)


func _add_light(root: Node3D, color: Color, energy: float, omni_range: float, height: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = omni_range
	light.position = Vector3(0, height, 0)
	root.add_child(light)
	return light
