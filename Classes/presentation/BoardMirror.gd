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
# The generator bakes a standing tile's top face as bare ground — so a tree is drawn ONCE,
# standing, not also lying flat under itself — and this mirror plants the object on it:
#   BILLBOARD  a camera-facing sprite. Thin, symmetric things: lamps, trees.
#   CUBE/FACETED/ROUND  real geometry from the meshlib, sides wearing the tile's own art and a
#              GENERATED top face. Volumetric things: crates, chests, rocks, barrels — the class the
#              dev judged "so odd" as billboards, because a 3/4 drawing has no top to show.
#   PLANE      real geometry too, but thin and DIRECTIONAL: a fence (#263). Which way it runs is the
#              tile's authored `wall_edges` mask, and the generator bakes that into the tile's OWN
#              mesh — so nothing here holds a yaw, and a fence is planted by the same
#              _make_prop_block that plants a crate.
#   TUFT       walkable ground with things growing ON it (#280) — one small camera-facing sprite
#              PER DRAWN CLUSTER, each planted where the art puts it in the cell. Its top face is
#              the one the generator SPECKLES rather than leaving as the bare kind base, since the
#              plants were cut out of that tile and must stand on the field they came from.
# Same per-cell reconcile for all of them, and the lantern borrows the torch's light.
#
# Fire-state cells (BURNING / BLAZE) get a flame billboard + a real OmniLight —
# the torch recipe, and the dev's "fire casts light" wish. Which cells burn is
# TerrainStateManager.burning_cells — the one enumeration form (Terrain.gd: "no
# reader may enumerate fire members itself").
#
# COVER cells (#326) stand up the same way, and that is why they live HERE rather than
# on Layer.TERRAIN with the frost icon: a terrain STATE whose art draws OBJECTS takes
# fire's route — this mirror owns its 3D form and OverlayMirror keeps only the plan-time
# preview icon. The bumps themselves are #280's TUFT decomposition (one billboard per
# drawn cluster, planted where the art puts it), pointed at the state's own icon.
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

# How tall a TUFT's plants stand relative to their own art (#280) — 1.0 would draw a flower at the
# size the tile draws it, which is a flower the height of a unit's shin; 0.25 is the dev's eye
# against the units. Only the SIZE: where each plant sits in the cell comes off the art, not here.
# Unlike the baked block props this is a live Sprite3D property, so it can be a real knob; the
# SETTER is what makes it one. Props are only rebuilt when their tile changes and sync() runs in
# DEV_MODE alone, so a value read at build time would need a repaint to show — which is the one
# failure that makes a tuning knob worthless.
@export var tuft_scale := 0.25: set = _set_tuft_scale

# The same, for the mud bumps a Burrow's COVER state stands up (#326). A SECOND knob rather than
# a shared one, on the lantern-vs-flame rule: cover and grass are different objects drawn at
# different sizes, so one number would force whoever tunes the second to un-tune the first.
@export var cover_scale := 0.5: set = _set_cover_scale

var board: GridMap

# How many terrain diffs have run. Read by the test that pins COALESCING — a drag
# crossing N cells inside one frame must cost one pass, not N.
var sync_passes := 0

# Keyed by cell, not a flat list: a reconcile has to answer "the marker for X", and the
# positional array this replaced could only answer it by freeing everything (#149's shape).
var _fire_markers: Dictionary[Vector2i, Node3D] = {}

# The COVER bumps, keyed the same way and reconciled by the same loop (#326). A second store
# rather than a state-keyed one: two states that both stand something up would otherwise share a
# cell key, and a covered tile CAN also be burning.
var _cover_markers: Dictionary[Vector2i, Node3D] = {}

# The standing props, keyed by cell — the same reconcile shape as the fire markers. Each node
# carries the TILE it was built from (PROP_TILE_META), because unlike fire a cell's prop can be
# REPLACED rather than merely added or removed: painting a rock over a tree leaves the cell in
# both the old and new wanted-set, and a keyed-by-cell-only reconcile would leave the tree
# standing forever.
const PROP_TILE_META := "prop_tile"
var _props: Dictionary[Vector2i, Node3D] = {}

# Marks a prop sprite as a TUFT, so the tuft_scale setter can find the standing ones. A mark on the
# node rather than a second dictionary keyed by cell: _props already tracks prop LIFETIME, and a
# parallel store would have to be kept in step with every free.
const TUFT_META := "tuft"

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


func rebuild(grid: TileMapLayer, heights: BoardHeights, burning: Array[Vector2i],
		covered: Array[Vector2i]) -> void:
	board.clear()
	sync(grid, heights)
	refresh_states(heights, burning, covered)


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
	var floor_level := floor_level_of(heights)
	var live: Dictionary[Vector2i, bool] = {}
	for cell in grid.get_used_cells():
		live[cell] = true
		reconcile_cell(grid, cell, heights, floor_level)
	# A prop on a cell that lost its ground entirely: reconcile_cell's own else-branch covers a cell
	# repainted from prop to flat, but this walk only visits cells that still HAVE ground.
	_free_props_except(live)
	# get_used_cells returns a copy, so erasing inside the walk is safe.
	for cell: Vector3i in board.get_used_cells():
		if not live.has(BoardSpace.flat(cell)):
			board.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)


# The INCREMENTAL door (#319), and the whole reason sync() above was split. Same reconcile, over the
# cells a writer announced through BoardGrid.dirty / BoardHeights.dirty instead of over the board.
#
# It has NO erase sweep and needs none: a cell that lost its ground is IN the announced set, and
# reconcile_cell clears its column. The sweep in sync() exists only to catch cells nobody named,
# which is exactly the case an announcement rules out.
#
# The floor is PASSED, not re-derived, because the caller has to compare it anyway: a lowered floor
# invalidates every column on the board, so that case is the caller's cue to call sync() instead.
func sync_cells(grid: TileMapLayer, cells: Array[Vector2i], heights: BoardHeights,
		floor_level: int) -> void:
	sync_passes += 1
	for cell in cells:
		reconcile_cell(grid, cell, heights, floor_level)


# ONE cell, in whatever direction it moved — the single implementation both sync() and sync_cells()
# run, so the full and incremental paths physically cannot draw a cell differently (Law #4).
#
# Props ride the SAME call rather than a second pass: whether a cell carries a standing object is a
# terrain fact, and splitting it would be two answers to "what is on this cell".
func reconcile_cell(grid: TileMapLayer, cell: Vector2i, heights: BoardHeights,
		floor_level: int) -> void:
	if not GridUtils.has_ground(grid, cell):
		_clear_column(cell, floor_level)
		_free_prop_at(cell)
		return
	_write_column(cell, grid, item_for_cell(grid, cell), heights, floor_level)
	if GridUtils.stands_up_at_cell(grid, cell):
		_reconcile_prop(grid, cell, heights)
	else:
		_free_prop_at(cell)   # repainted from a tree to bare grass


# Erase a whole column. Walks UP from the shared floor and stops at the first gap, which is exact
# rather than approximate: _write_column fills floor..level contiguously (plus the ramp wedge one
# above), so a column can never have a hole for this to stop early on. The same contiguity is what
# _write_column's own walk-up cleanup already assumes.
func _clear_column(cell: Vector2i, floor_level: int) -> void:
	var y := floor_level
	while board.get_cell_item(Vector3i(cell.x, y, cell.y)) != GridMap.INVALID_CELL_ITEM:
		board.set_cell_item(Vector3i(cell.x, y, cell.y), GridMap.INVALID_CELL_ITEM)
		y += 1


# The lowest surface any column has to reach down to. A dip must have a bottom rather than a hole,
# and every column shares one floor so the board's underside stays flat.
#
# Public since #319: the authoring poll compares it frame to frame, because a LOWERED floor is the
# one edit that invalidates every column at once and so cannot be reconciled incrementally.
func floor_level_of(heights: BoardHeights) -> int:
	return heights.lowest_elevation()


# One cell's whole COLUMN (#273): the surface block repeated down to the shared floor, which is the
# dev's call — BoardMirror already splits surface (top face, from atlas coords) from material (side
# texture, from Kind), so a stack of one block already reads as a cliff face of that material.
# Painting a DIFFERENT tile under a tile is a separate ticket he scoped out.
#
# A ramp adds its wedge ONE LEVEL ABOVE its own: a level-E block occupies [E..E+1], so level E's
# surface is at E+1, and a ramp whose own elevation is its LOW side must slope from E+1 up to E+2.
# That makes a ramp column read one cell taller than its flat neighbour, which is exactly what
# BoardPicker's "ramps count as full blocks" already assumes.
# The grid is taken so the wedge can wear the cell's own art (#340). Asked INSIDE the rise branch
# rather than resolved beside `item` at the caller: it costs a name format per lookup, and a flat
# cell -- almost every cell -- has no wedge to pick art for.
func _write_column(cell: Vector2i, grid: TileMapLayer, item: int, heights: BoardHeights,
		floor_level: int) -> void:
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
		var wedge_item := ramp_item_for_cell(grid, cell)
		if board.get_cell_item(wedge) != wedge_item \
				or board.get_cell_item_orientation(wedge) != orientation:
			board.set_cell_item(wedge, wedge_item, orientation)
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


# The wedge wearing THIS cell's own art (#340) — item_for_cell's twin, and it degrades the same way.
# A ramp used to be one hardcoded dirt mesh whatever was painted under it, so a stone ramp read as
# dirt; the generator now emits a variant per FLAT tile and this picks it.
#
# The generic wedge stays as the fallback rather than as dead scaffolding: the three cases
# item_for_tile already documents (empty cell, rotated alternative, multi-cell art) reach here too,
# and so does a standing prop, which is refused a rise at the brush but can still be painted onto a
# cell that already slopes.
func ramp_item_for_cell(grid: TileMapLayer, cell: Vector2i) -> int:
	var source_id := grid.get_cell_source_id(cell)
	if source_id != -1 and grid.get_cell_alternative_tile(cell) == 0:
		_ensure_item_index()
		var own: int = _item_by_name.get(
				ramp_item_name(source_id, grid.get_cell_atlas_coords(cell)),
				GridMap.INVALID_CELL_ITEM)
		if own != GridMap.INVALID_CELL_ITEM:
			return own
	return ramp_item()


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


# Every terrain state that STANDS something on its cell, reconciled in one pass. Both lists are
# required rather than defaulted: a caller that forgot one would silently erase every marker of
# that state, which is the failure #318 cost a release.
func refresh_states(heights: BoardHeights, burning: Array[Vector2i],
		covered: Array[Vector2i]) -> void:
	_reconcile_state(_fire_markers, burning, heights, _make_fire)
	_reconcile_state(_cover_markers, covered, heights, _make_cover)


# Add what is newly there, free what went, LEAVE STANDING what remains. The last clause is the
# one with teeth: a marker that is rebuilt every frame looks identical through the counts below,
# so the pin is node identity. One loop for every standing state — the invariant is the thing
# worth having in a single place.
#
# Standing is not the same as UNMOVED, though (#308): the ground under a survivor can be raised
# while its cell keeps burning, so its footing is re-read every pass. Same expression the builder
# is handed, and it costs the marker nothing it was relying on — identity is untouched.
func _reconcile_state(markers: Dictionary[Vector2i, Node3D], cells: Array[Vector2i],
		heights: BoardHeights, make: Callable) -> void:
	var wanted: Dictionary[Vector2i, bool] = {}
	for cell in cells:
		wanted[cell] = true
		if markers.has(cell):
			markers[cell].position = surface_point(cell, heights)
		else:
			var built: Node3D = make.call(surface_point(cell, heights))
			if built != null:
				markers[cell] = built
	for cell: Vector2i in markers.keys():
		if not wanted.has(cell):
			markers[cell].queue_free()
			markers.erase(cell)


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


# And the same contract for the tile's own ramp wedge (#340). A third namespace, not a flag on the
# ground item: a cell can be flat or sloped and the two need different geometry off one tile.
# Only FLAT tiles get one — a rock cannot slope — which is what makes the fallback below load-bearing.
static func ramp_item_name(source_id: int, coords: Vector2i) -> String:
	return "ramp_%d_%d_%d" % [source_id, coords.x, coords.y]


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
	var item := ramp_item_for_cell(ghost.source, ghost.cell) if ramping \
			else item_for_cell(ghost.source, ghost.cell)
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


func cover_marker_count() -> int:
	return _cover_markers.size()


# The bumps standing on a covered cell, or null — the fire reads' twin.
func cover_marker_at(cell: Vector2i) -> Node3D:
	return _cover_markers.get(cell)


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
			_free_prop_at(cell)


# The single-cell twin, which is what the incremental path can use — the sweep above cannot answer
# "this one cell stopped standing up" without a set of every cell that still does.
func _free_prop_at(cell: Vector2i) -> void:
	if not _props.has(cell):
		return
	_props[cell].queue_free()
	_props.erase(cell)


# The object standing on the cell that paints it, in whatever form its art asks for. The FORM is
# the only fork; everything around it — where it stands, what layer it draws on, whether it casts a
# shadow, whether it carries a light — is one answer for every prop.
#
# A TUFT is the one prop that is SEVERAL objects rather than one, so it owns its whole assembly
# below (the shape _make_fire already has) instead of being forced through a one-body path.
func _make_prop(grid: TileMapLayer, cell: Vector2i, at: Vector3) -> Node3D:
	var shape := GridUtils.prop_shape_at_cell(grid, cell)
	if shape == GridUtils.PropShape.TUFT:
		return _make_tuft(grid, cell, at)
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


# --- TUFTS (#280) -------------------------------------------------------------------------------
#
# A tuft is ONE SPRITE PER DRAWN CLUSTER, not one sprite of the tile, and that is the whole trick.
# The art is a TOP-DOWN tile: a flower's y inside it is DEPTH INTO THE CELL, not height. Stand the
# whole rectangle up and every one of those depths silently becomes an altitude — two flowers drawn
# at different depths end up one above the other, with the lower one hanging in the air. (The same
# reading error #263 made with the foreshortened fence pieces.)
#
# So the tile is decomposed: its background colour is keyed out, what remains is split into
# connected clusters, and each cluster stands up AT ITS OWN PLACE IN THE CELL — x from the cluster's
# centre column, z from its BOTTOM row, because in a top-down drawing the lowest drawn pixel is
# where the plant meets the ground.
#
# The background is the tile's OWN most common colour, measured, not a diff against a base tile:
# "which tile is this one's ground?" is a relationship the content does not declare and this must
# not invent (Law #4). It holds by construction for a tuft — ground with something on it is mostly
# ground — and it is measured at 76-96% across the authored tufts. The generator fills the cell's
# top face with that same colour (speckled), so the plants stand on the field they were cut from.

# Below this many pixels a cluster is grass TEXTURE, not an object standing on grass. Measured
# rather than picked: the shipped sheet's clusters are 2px specks or 23px-plus objects with nothing
# in between, so any threshold in that gap says the same thing. A speck is not lost by staying flat
# — a tuft tile keeps its full bake, so it is still drawn on the ground; it is only not duplicated.
# Standing every speck up as well is #311, and needs one mesh per cell to stay affordable.
const TUFT_MIN_CLUSTER_PIXELS := 4

# Keyed art + cluster list per TILE, since every cell painted with one tile stands up the same
# thing. Prolog paints over a thousand tuft cells off three tiles, so this is the difference
# between three decompositions and a thousand.
var _tuft_tiles: Dictionary[Vector3i, Dictionary] = {}


# The cell's tufts: a root on the surface with one camera-facing sprite per cluster. Null when the
# tile's art holds no cluster worth standing up, which is a supported outcome rather than an error
# — the tile simply stays the ground it already draws.
#
# No light and no shadow, unlike every other prop. LIT_PROPS is keyed on a whole prop's name and a
# tuft is not one object; shadows are a count, not a look call — a thousand tuft cells is thousands
# of shadow-map draws for plants a few pixels tall.
func _make_tuft(grid: TileMapLayer, cell: Vector2i, at: Vector3) -> Node3D:
	var tiles := grid.tile_set
	if tiles == null:
		return null
	var source_id := grid.get_cell_source_id(cell)
	var atlas := tiles.get_source(source_id) as TileSetAtlasSource
	if atlas == null:
		return null
	var art := _tuft_art(atlas, source_id, grid.get_cell_atlas_coords(cell))
	var clusters: Array[Rect2i] = art.get("clusters", [] as Array[Rect2i])
	var sheet: Texture2D = art.get("texture")
	if sheet == null or clusters.is_empty():
		return null

	var root := Node3D.new()
	add_child(root)
	root.position = at
	for rect: Rect2i in clusters:
		var sprite := _make_cluster_sprite(sheet, rect, _tuft_pixel_size(),
				float(GridUtils.TILE_SIZE))
		sprite.set_meta(TUFT_META, true)
		root.add_child(sprite)
	return root


# One cluster, standing on the cell at the spot the art draws it — every caller that stands
# decomposed art up builds its sprites here (a tile's tufts, a COVER state's bumps). The two
# densities are separate parameters on purpose: `pixel_size` is knob-scaled and sizes the art,
# `pixels_per_cell` is the art's own metric and places it, so a knob can never move a plant.
func _make_cluster_sprite(sheet: Texture2D, rect: Rect2i, pixel_size: float,
		pixels_per_cell: float) -> Sprite3D:
	var texture := AtlasTexture.new()
	texture.atlas = sheet
	texture.region = Rect2(rect)

	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.shaded = true
	sprite.layers = BoardOverlays.WORLD_RENDER_LAYER
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.pixel_size = pixel_size
	sprite.offset = Vector2(0, rect.size.y * 0.5)   # planted at ITS OWN base, per cluster

	# The cluster's FOOT, in art pixels, placed on the cell: centre column and bottom edge, against
	# the art's own centre. The art covers exactly one cell by definition, so a pixel is
	# 1/pixels_per_cell of it — the density the unscaled sprite would draw at.
	var half := pixels_per_cell * 0.5
	var foot := Vector2(rect.position.x + rect.size.x * 0.5, float(rect.end.y))
	sprite.position = Vector3((foot.x - half), 0.0, (foot.y - half)) / pixels_per_cell
	return sprite


# How many world units one art pixel of a TUFT covers. Scaled through DENSITY rather than the
# node's scale: a Y-billboard rebuilds its basis from the camera, and pixel_size also scales the
# base offset, so a tuft shrinks toward the ground it stands on. Its POSITION in the cell is
# untouched by the knob, because where a flower grows is not a matter of taste.
func _tuft_pixel_size() -> float:
	return tuft_scale / float(GridUtils.TILE_SIZE)


# Re-size every standing tuft. What makes tuft_scale a live knob rather than a value baked into
# whatever was built last (see the export).
func _set_tuft_scale(value: float) -> void:
	tuft_scale = value
	for root: Node3D in _props.values():
		for child in root.get_children():
			var sprite := child as Sprite3D
			if sprite != null and sprite.has_meta(TUFT_META):
				sprite.pixel_size = _tuft_pixel_size()


# --- COVER (#326) -------------------------------------------------------------------------------
#
# The dev's ask, from the scratchpad and again in play: cover should pop up as THREE MUD BUMPS,
# not as the whole icon rotating vertical. That is #280's tuft decomposition exactly — the icon
# is drawn top-down, so a bump's y inside it is DEPTH INTO THE CELL and each cluster stands at its
# own place — pointed at a runtime state's icon instead of a baked tile.
#
# It does NOT key a background out, and that is the one real difference: a tile is opaque ground
# with things drawn on it, so the ground has to be measured and removed, while an icon already
# carries its own alpha. Clustering runs on what is drawn either way.
const COVER_ICON_MIN_CLUSTERS := 2

# One decomposition for the whole board — cover art is fixed, unlike a tuft's per-tile answer.
var _cover_art: Dictionary = {}
var _cover_art_built := false


# The bumps standing on a covered cell: a root on the surface with one billboard per drawn cluster.
# No light and no shadow, for the tufts' reasons.
func _make_cover(at: Vector3) -> Node3D:
	var art := _cover_bumps()
	var clusters: Array[Rect2i] = art.get("clusters", [] as Array[Rect2i])
	var sheet: Texture2D = art.get("texture")
	if sheet == null or clusters.is_empty():
		return null

	var root := Node3D.new()
	add_child(root)
	root.position = at
	for rect: Rect2i in clusters:
		root.add_child(_make_cluster_sprite(sheet, rect, _cover_pixel_size(),
				BoardOverlays.ART_PIXELS_PER_CELL))
	return root


# The cover icon and the bumps drawn in it. The TEXTURE is the 2D's own icon — one answer to
# "what does cover look like", so a re-drawn icon reaches both views — and the clusters are read
# off its decoded image.
func _cover_bumps() -> Dictionary:
	if _cover_art_built:
		return _cover_art
	_cover_art_built = true
	var icon: Texture2D = OverlayManager.TERRAIN_STATE_ICONS.get(Terrain.TileState.COVER)
	if icon == null:
		return _cover_art
	var image := icon.get_image()
	if image == null:
		return _cover_art
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var clusters := _clusters_of(image)
	if clusters.size() < COVER_ICON_MIN_CLUSTERS:
		# The art stopped answering "several bumps" — one popped sprite of the whole icon is the
		# thing this exists to avoid, so say so rather than shipping it.
		push_warning("Cover icon decomposes into %d cluster(s): the bumps are touching (#326)"
				% clusters.size())
	_cover_art = {"texture": icon, "clusters": clusters}
	return _cover_art


# How many world units one icon pixel covers. The ICON's metric, not the tileset's: cover is
# markup art, and BoardOverlays already declares that a 16px texture covers one cell.
func _cover_pixel_size() -> float:
	return cover_scale / BoardOverlays.ART_PIXELS_PER_CELL


# Re-size every standing bump — what makes cover_scale a live knob. Every child of a cover marker
# IS a bump, so this needs no mark of its own, unlike the tufts sharing the props tree.
func _set_cover_scale(value: float) -> void:
	cover_scale = value
	for root: Node3D in _cover_markers.values():
		for child in root.get_children():
			var sprite := child as Sprite3D
			if sprite != null:
				sprite.pixel_size = _cover_pixel_size()


# This tile's tuft art: {"texture": the tile with its background keyed out, "clusters": each
# standing thing's rect inside it}. Both fall out of one decomposition, so they are cached together
# and can never describe different pixels.
func _tuft_art(atlas: TileSetAtlasSource, source_id: int, coords: Vector2i) -> Dictionary:
	var key := Vector3i(source_id, coords.x, coords.y)
	if _tuft_tiles.has(key):
		return _tuft_tiles[key]
	var built: Dictionary = {}
	var sheet := _art_image(atlas, source_id)
	if sheet != null:
		var region := atlas.get_tile_texture_region(coords, 0)
		var keyed := Image.create_empty(region.size.x, region.size.y, false, Image.FORMAT_RGBA8)
		var ground := background_colour(sheet, region)
		for y in region.size.y:
			for x in region.size.x:
				var c := sheet.get_pixel(region.position.x + x, region.position.y + y)
				keyed.set_pixel(x, y, Color(0, 0, 0, 0) if c == ground else c)
		built = {"texture": ImageTexture.create_from_image(keyed), "clusters": _clusters_of(keyed)}
	_tuft_tiles[key] = built
	return built


# The most common colour in a region — a tuft's GROUND, by the argument above. A static both stacks
# call, for the reason opaque_bounds is one: the mirror keys this colour OUT to find the plants and
# the generator FILLS the tile's top face with it, so two answers here would stand the plants on a
# patch that does not match what they were cut from.
static func background_colour(image: Image, region: Rect2i) -> Color:
	var counts: Dictionary[Color, int] = {}
	var best := Color(0, 0, 0, 0)
	var best_seen := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var c := image.get_pixel(x, y)
			var seen: int = counts.get(c, 0) + 1
			counts[c] = seen
			if seen > best_seen:
				best_seen = seen
				best = c
	return best


# The drawn pixels split into 8-connected clusters, each as its own rect. DIAGONALS count: pixel art
# this small draws a stem as a diagonal run, and 4-connectivity would cut one plant into three.
func _clusters_of(keyed: Image) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var seen: Dictionary[Vector2i, bool] = {}
	var size := Vector2i(keyed.get_width(), keyed.get_height())
	for y in size.y:
		for x in size.x:
			var start := Vector2i(x, y)
			if seen.has(start) or keyed.get_pixel(x, y).a < 0.5:
				continue
			seen[start] = true
			var stack: Array[Vector2i] = [start]
			var drawn := 0
			var lo := start
			var hi := start
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				drawn += 1
				lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
				hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
				for dy: int in [-1, 0, 1]:
					for dx: int in [-1, 0, 1]:
						var n := p + Vector2i(dx, dy)
						if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
							continue
						if seen.has(n) or keyed.get_pixel(n.x, n.y).a < 0.5:
							continue
						seen[n] = true
						stack.push_back(n)
			if drawn >= TUFT_MIN_CLUSTER_PIXELS:
				out.append(Rect2i(lo, hi - lo + Vector2i.ONE))
	return out


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
