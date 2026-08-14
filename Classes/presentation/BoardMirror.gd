extends Node3D
class_name BoardMirror

# The Battle3D board mirror (#215 / #176 stage 4a): paints the 3D GridMap from the
# LIVE 2D grid — the hidden game is the authority, this only reads. Terrain kinds
# resolve through the existing seam (GridUtils.get_terrain_kind_at_cell); the one
# Kind -> meshlib-item table below is law-tested complete. Boards mirror FLAT
# (column height 1) because the sim has no elevation yet — the diorama's hills
# arrive when the rules do.
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

var board: GridMap

# How many terrain diffs have run. Read by the test that pins COALESCING — a drag
# crossing N cells inside one frame must cost one pass, not N.
var sync_passes := 0

# Keyed by cell, not a flat list: a reconcile has to answer "the marker for X", and the
# positional array this replaced could only answer it by freeing everything (#149's shape).
var _fire_markers: Dictionary[Vector2i, Node3D] = {}


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
	for cell in grid.get_used_cells():
		live[cell] = true
		var kind := GridUtils.get_terrain_kind_at_cell(grid, cell)
		var item: int = KIND_TO_ITEM.get(kind, FALLBACK_ITEM)
		var at := BoardSpace.of_flat(cell)
		if board.get_cell_item(at) != item:
			board.set_cell_item(at, item)
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
	quad.material = material
	flame.mesh = quad
	flame.position = Vector3(0, flame_base_lift(), 0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flame)

	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.62, 0.3)
	light.light_energy = flame_light_energy
	light.omni_range = flame_light_range
	light.position = Vector3(0, 0.6, 0)
	root.add_child(light)
	return root
