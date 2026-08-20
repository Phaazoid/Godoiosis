extends Node
class_name OverlayMirror

# The 4c observer (#222): polls the 2D OverlayManager's retained state every frame
# and diffs it into BoardOverlays / UnitMirror — board markup parity with ZERO
# trigger-site hooks (the alternative was ~40 sites across 9 files; UnitMirror's
# poll-don't-wire precedent, applied to overlays). The 2D stays the ONE authority:
# every cell set, texture, tint and animation arrives by copy — the aim pulse IS
# hover_overlay.modulate, polled; arrow textures arrive pre-picked on the retained
# preview sprites; validity tints arrive pre-applied. Value-diff before every push
# (fills compare SORTED — get_used_cells/Dictionary orderings aren't frame-stable),
# so a static board costs comparisons, not writes.
#
# Deliberately NOT mirrored: the 2D hover layer's POINTER role (battle3d's bracket
# is the 3D pointer; AIM covers the footprint role), CursorController, and the 2D
# brush ghost (the 3D has its own block ghost).
#
# ZONE_PATROL and the picked-zone highlight ARE mirrored as of #231, reversing this
# file's earlier "dev authoring stays on the 2D surface" exclusion: authoring moved
# into the 3D view, and patrol is the brush's DEFAULT zone kind, so leaving it out
# made zone painting invisible exactly where it is now done. They are the only two
# layers whose mirroring is VISIBILITY-GATED — they are authoring scaffolding the 2D
# shows solely while the Tile Brush tab is up, so mirroring their cells alone would
# leak patrol zones into play. Mirror the QUESTION ("should this be on screen"),
# which is cells AND visible, never just the field the cells happen to live in.
#
# It also owns the fire poll: BoardMirror's flame markers are board markup with the
# same cadence question, and this is the node that already runs every frame.


var game: Node2D            # the hidden Game coordinator; set by battle3d._ready
var overlays: BoardOverlays
var unit_mirror: UnitMirror
var board_mirror: BoardMirror   # for the fire poll; set by battle3d._ready

var _last_cells: Dictionary[BoardOverlays.Layer, Array] = {}
var _last_markers: Dictionary[BoardOverlays.Layer, Array] = {}
var _last_ghosts: Array[Dictionary] = []
var _last_fire: Array[Vector2i] = []
var _last_cover: Array[Vector2i] = []
var _pick_texture: Texture2D   # the (1,0) "pick this unit" tile art, cut lazily

# Every value-diff below is blind to the board's HEIGHTS (#308): a fill's tilt and a flame's
# footing both come from BoardHeights, and neither is in the cells being compared. Gated on the
# source changing rather than folded into every key -- one int compare per frame.
var _last_heights_version := -1
var _heights_moved := false

var _last_trace_version := -1   # OverlayManager.sight_trace_version -- the store's own signal (#308)
var _bead_texture_cache: GradientTexture2D


func _process(_delta: float) -> void:
	if game == null or overlays == null:
		return
	var om: OverlayManager = game.overlay_manager
	_heights_moved = _poll_heights()   # once per frame, ahead of every diff that reads it

	_fill(BoardOverlays.Layer.MOVE, om.move_overlay.get_used_cells())
	_fill(BoardOverlays.Layer.INVALID_MOVE, om.invalidmove_overlay.get_used_cells())
	_fill(BoardOverlays.Layer.SQUAD, om.squad_overlay.get_used_cells())
	_fill(BoardOverlays.Layer.SQUAD_RANGE, om.squadrange_overlay.get_used_cells())
	_fill(BoardOverlays.Layer.ZONE_CAPTURE, om.capture_overlay.get_used_cells())
	_fill(BoardOverlays.Layer.ZONE_EXTRACTION, om.extraction_overlay.get_used_cells())
	# Authoring scaffolding: cells AND the authoring INTENT, or patrol zones leak into play.
	var authoring: bool = om.zones_authoring_visible
	_fill_gated(BoardOverlays.Layer.ZONE_PATROL, om.zone_overlay, authoring)
	_fill_gated(BoardOverlays.Layer.ZONE_HIGHLIGHT, om.zone_highlight_overlay, authoring)

	# The aim footprint pulses by layer modulate in 2D — the animation rides the poll.
	_fill(BoardOverlays.Layer.AIM, om.hover_overlay.get_used_cells())
	overlays.set_layer_modulate(BoardOverlays.Layer.AIM, om.hover_overlay.modulate)

	_attack(om)
	_sight_trace(om)
	_arrows(om)

	var kb_trails: Array[Dictionary] = []
	var kb_ghosts: Array[Dictionary] = []
	_split_knockback(om, kb_trails, kb_ghosts)
	_markers(BoardOverlays.Layer.KNOCKBACK, kb_trails)

	_icons(om)
	_terrain(om)
	_ghost_sync(om, kb_ghosts)
	_standing_states()


# Did the board's height data move since the last frame? BoardHeights.dirty.version is the
# non-consuming read — it never takes the cell list away from battle3d's authoring poll, which is
# what that store's ONE-CONSUMER rule protects. Null heights (the headless Play boards) hold at -1,
# so a board with no store never reports a move.
func _poll_heights() -> bool:
	var heights := _heights()
	var version: int = -1 if heights == null else heights.dirty.version
	if version == _last_heights_version:
		return false
	_last_heights_version = version
	return true


# Which cells are alight and which are dug in, each straight off its ONE enumeration form. Polled
# rather than wired because a states_changed signal would fire inside the resolver's per-effect
# loop and churn markers many times within a single pass; the poll coalesces a frame into one
# reconcile, and covers the sim, the dev brush, tick_states and load alike (#231).
func _standing_states() -> void:
	if board_mirror == null:
		return
	var burning: Array[Vector2i] = game.terrain_states.burning_cells()
	burning.sort()
	var covered: Array[Vector2i] = game.terrain_states.cells_with(Terrain.TileState.COVER)
	covered.sort()
	# A marker STANDS on its cell's surface, so raising that cell moves it while the burning set
	# stays byte-identical (#308).
	if not _heights_moved and _last_fire == burning and _last_cover == covered:
		return
	_last_fire = burning
	_last_cover = covered
	var heights: BoardHeights = game.board_heights
	board_mirror.refresh_states(heights, burning, covered)


# --- Fills -------------------------------------------------------------------------

# _fill's twin for a layer the 2D shows and hides. `wanted` is the AUTHORING INTENT, passed
# in rather than read off the node's `.visible` — that field is the 2D's own render fact and
# is false in this very host, because Battle3D hides the whole 2D board behind the diorama.
# Keying on it made the mirror go dark exactly where it is needed (#231; #232's lesson, which
# the first draft of this function quoted and then broke). `source` is untyped (OverlayManager
# declares zone_overlay with no type) and NULL on headless Play boards, which supply bare
# Node2Ds and never build the highlight. Hiding costs one push: _fill's value-diff holds after.
func _fill_gated(layer: BoardOverlays.Layer, source, wanted: bool) -> void:
	var node := source as TileMapLayer
	var cells: Array[Vector2i] = []
	if wanted and node != null:
		cells = node.get_used_cells()
	_fill(layer, cells)


# Which level a marked cell's overlay lies on (#273) — a move-range tile on a terrace has to sit
# ON the terrace. Read off the hidden game rather than passed, unlike BoardMirror.sync: this class
# already POLLS the game for everything it draws, and nothing here takes board state as an
# argument. Null-guarded for the headless Play boards that never set `game`.
func _level_of(cell: Vector2i) -> int:
	var heights := _heights()
	return heights.elevation_at(cell) if heights != null else 0


# Null on the headless Play boards that never set `game`; BoardSpace.surface_point reads that as
# flat, so every anchor keeps working on a board with no heights wired.
func _heights() -> BoardHeights:
	if game == null:
		return null
	var heights: BoardHeights = game.board_heights
	return heights


# The cell list is only PART of the key: how a fill lies on its cell also depends on that cell's
# ramp rise (#281), and a Vector3i carries the level but not the rise. So a rise painted onto a
# cell whose elevation did not change leaves this array identical while the render must move —
# hence the heights gate rather than a per-cell rise lookup in the comparison (#308).
func _fill(layer: BoardOverlays.Layer, used: Array[Vector2i]) -> void:
	var cells: Array[Vector3i] = []
	for cell in used:
		cells.append(BoardSpace.of_cell(cell, _level_of(cell)))
	cells.sort()
	if not _heights_moved and _last_cells.get(layer, Array()) == cells:
		return
	_last_cells[layer] = cells
	overlays.set_cells(layer, cells, _heights())


# ATTACK is TRIPLE-use in 2D: reach fill at (0,0), target-pick markers at (1,0), and the
# vertically-blocked reach cells at (2,0) (#258) — split by atlas coords; the heal-green arrives
# as the layer modulate. The split is EXPLICIT per coord: an `else` catch-all here silently drew
# any new coord as plain red reach, which is how the blocked state would have vanished in 3D.
#
# The reach half hands its cells to _fill rather than lifting and diffing them here: a hand-copied
# diff is a second copy of whatever _fill's key gets wrong, which is exactly how #308 had two homes.
func _attack(om: OverlayManager) -> void:
	var reach: Array[Vector2i] = []
	var blocked: Array[Vector2i] = []
	var picks: Array[Dictionary] = []
	for cell: Vector2i in om.attack_overlay.get_used_cells():
		var coords: Vector2i = om.attack_overlay.get_cell_atlas_coords(cell)
		if coords == OverlayManager.TARGET_ATLAS_COORDS:
			picks.append(_marker(_anchor(cell), _target_pick_texture(om), Color.WHITE))
		elif coords == OverlayManager.BLOCKED_ATLAS_COORDS:
			blocked.append(cell)
		else:
			reach.append(cell)
	_fill(BoardOverlays.Layer.ATTACK, reach)
	_fill(BoardOverlays.Layer.ATTACK_BLOCKED, blocked)
	overlays.set_layer_modulate(BoardOverlays.Layer.ATTACK, om.attack_overlay.modulate)
	# Derived, never a second colour: the 2D hatch tile wears the same modulate, so the 3D twin
	# is the same modulate dimmed by one tunable factor (a GameKnobs row).
	var dim: float = OverlayManager.BLOCKED_REACH_DIM
	var m: Color = om.attack_overlay.modulate
	overlays.set_layer_modulate(BoardOverlays.Layer.ATTACK_BLOCKED, Color(m.r * dim, m.g * dim, m.b * dim, m.a))
	_markers(BoardOverlays.Layer.TARGET_PICK, picks)


# The aim's bead path (#258), lifted into the diorama at the trajectory's own heights -- the arc a
# lob clears a wall by is literally visible. Gated on the store's own version, never a copied key
# (#308); the points and the verdict were computed ONCE by Reach.sight_trace, so this is a second
# projection of one answer, not a second computation.
func _sight_trace(om: OverlayManager) -> void:
	if om.sight_trace_version == _last_trace_version:
		return
	_last_trace_version = om.sight_trace_version
	var beads: Array[Dictionary] = []
	var trace: Reach.SightTrace = om.sight_trace
	if trace != null:
		# Colours COPIED from the 2D renderer (parallel-stacks rule), never restated.
		var tint := SightTrace2D.BLOCKED_COLOR if trace.blocked else SightTrace2D.CLEAR_COLOR
		for p in trace.points:
			# Rule-height h sits at world (h + 1) * CELL_SIZE: a level-E surface is world
			# surface_y(E), and h counts levels above the level-0 floor plane.
			var pos := Vector3(p.x * BoardSpace.CELL_SIZE, BoardSpace.surface_y(0) + p.y * BoardSpace.CELL_SIZE, p.z * BoardSpace.CELL_SIZE)
			beads.append({"pos": pos, "texture": _bead_texture(), "modulate": tint})
	_markers(BoardOverlays.Layer.SIGHT_TRACE, beads)


# A tiny radial dot, code-built -- no art file to author for a readout whose whole identity is
# "a bead" (GradientTexture2D renders on first use; pooled markers reuse the one instance).
func _bead_texture() -> Texture2D:
	if _bead_texture_cache == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
		gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
		_bead_texture_cache = GradientTexture2D.new()
		_bead_texture_cache.gradient = gradient
		_bead_texture_cache.fill = GradientTexture2D.FILL_RADIAL
		_bead_texture_cache.fill_from = Vector2(0.5, 0.5)
		_bead_texture_cache.fill_to = Vector2(0.5, 0.0)
		_bead_texture_cache.width = 8
		_bead_texture_cache.height = 8
	return _bead_texture_cache


func _target_pick_texture(om: OverlayManager) -> Texture2D:
	if _pick_texture == null:
		var source := om.attack_overlay.tile_set.get_source(OverlayManager.SOURCE_ID) as TileSetAtlasSource
		_pick_texture = GridUtils.tile_sprite(source, OverlayManager.TARGET_ATLAS_COORDS)
	return _pick_texture


# --- Sprite channels ---------------------------------------------------------------

# Planned + hover + group-preview path arrows: the retained preview Sprite2Ds carry
# the already-picked texture (14 authored variants) and the already-computed
# validity tint — copy, never re-derive.
func _arrows(om: OverlayManager) -> void:
	var entries: Array[Dictionary] = []
	var moves: Array = om.planned_move_by_unit.values()
	if om.hover_move_preview != null:
		moves.append(om.hover_move_preview)
	moves.append_array(om.hover_move_previews)
	for move in moves:
		var action := move as MoveAction
		if action == null:
			continue
		for sprite: Sprite2D in action.preview:
			if not is_instance_valid(sprite) or sprite.texture == null:
				continue
			entries.append(_marker(_anchor_px(sprite.global_position), sprite.texture, sprite.modulate))
	_markers(BoardOverlays.Layer.PATH_ARROWS, entries)


# knockback_preview_sprites holds BOTH halves of the preview; the parent says which:
# arrow trail under ArrowIconOverlay, landing ghost under ProjectedUnitOverlay.
func _split_knockback(om: OverlayManager, trails: Array[Dictionary], ghosts: Array[Dictionary]) -> void:
	for node in om.knockback_preview_sprites:
		if not is_instance_valid(node):
			continue
		var sprite := node as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		var entry := _marker(_anchor_px(sprite.global_position), sprite.texture, sprite.modulate)
		if sprite.get_parent() == om.arrow_icon_overlay:
			trails.append(entry)
		elif sprite.get_parent() == om.projected_unit_overlay:
			ghosts.append(entry)


# Selection icons, routed by TYPE rather than by a style mode (#325 verdict, dev call after playing
# both, 2026-08-19). CROWN rides ICONS as a head billboard -- leadership is what a unit IS, and
# nothing has read better over a head than the original crown. Everything else (today, SQUADMEMBER)
# rides GROUND_ICONS as a surface decal in the squad's own hue, texture and tint arriving BY COPY
# from the 2D sprite, so the hue is authored in one place and never re-derived here.
#
# The leader wears BOTH: a ring because they are a member, the crown because they lead.
#
# No per-type y-stagger any more. It existed to keep several head-icon types off each other's
# plane; CROWN is the channel's only tenant now, so there is nothing to stagger against.
func _icons(om: OverlayManager) -> void:
	var heads: Array[Dictionary] = []
	var ground: Array[Dictionary] = []
	for unit in om.icons_by_unit:
		var by_type: Dictionary = om.icons_by_unit[unit]
		for type in by_type:
			var icon := by_type[type] as OverlayIcon
			if icon == null or not is_instance_valid(icon):
				continue
			var surface := _anchor(icon.target_cell)
			if type == OverlayIcon.IconType.CROWN:
				heads.append(_marker(surface, icon.sprite.texture, icon.sprite.modulate))
			else:
				ground.append(_marker(surface, icon.sprite.texture, icon.sprite.modulate))
	_markers(BoardOverlays.Layer.ICONS, heads)
	_markers(BoardOverlays.Layer.GROUND_ICONS, ground)


# Terrain live icons (FROZEN) + plan-time preview ghosts. A state whose art draws OBJECTS is
# skipped on the LIVE channel, because BoardMirror stands its 3D form on the cell: the flame +
# light IS fire (#174: one Fire texture covers BURNING and BLAZE), and the mud bumps ARE cover
# (#326). Both are kept on the PREVIEW channel, where no 3D preview exists and the ghosted icon
# is the only warning a queued Burrow or ignite gets. FROZEN is genuinely flat and stays here.
const STANDING_STATES: Array[Terrain.TileState] = [
	Terrain.TileState.BURNING, Terrain.TileState.COVER,
]


func _terrain(om: OverlayManager) -> void:
	var standing: Array[Texture2D] = []
	for state in STANDING_STATES:
		standing.append(OverlayManager.TERRAIN_STATE_ICONS[state])
	var live: Array[Dictionary] = []
	for sprite in om.terrain_live_sprites:
		if not is_instance_valid(sprite) or standing.has(sprite.texture):
			continue
		live.append(_marker(_anchor_px(sprite.global_position), sprite.texture, sprite.modulate))
	_markers(BoardOverlays.Layer.TERRAIN, live)
	var preview: Array[Dictionary] = []
	for sprite in om.terrain_preview_sprites:
		if not is_instance_valid(sprite):
			continue
		preview.append(_marker(_anchor_px(sprite.global_position), sprite.texture, sprite.modulate))
	_markers(BoardOverlays.Layer.TERRAIN_PREVIEW, preview)


# Move-projection ghosts + knockback landing ghosts -> UnitMirror's ghost pool.
func _ghost_sync(om: OverlayManager, kb_ghosts: Array[Dictionary]) -> void:
	var entries: Array[Dictionary] = []
	for sprite in om.projected_unit_sprites.values():
		if not is_instance_valid(sprite):
			continue
		var ghost := sprite as Sprite2D
		if ghost == null or ghost.texture == null:
			continue
		entries.append(_marker(_anchor_px(ghost.global_position), ghost.texture, ghost.modulate))
	entries.append_array(kb_ghosts)
	if _last_ghosts == entries:
		return
	_last_ghosts = entries
	unit_mirror.set_ghosts(entries)


# --- Shared ------------------------------------------------------------------------

func _markers(layer: BoardOverlays.Layer, entries: Array[Dictionary]) -> void:
	if _last_markers.get(layer, Array()) == entries:
		return
	_last_markers[layer] = entries
	overlays.set_markers(layer, entries)


# Both halves of a marker come off ONE surface_transform, so where it sits and how it lies can
# never disagree. A BILLBOARD ignores the basis and stays upright; the ghost channel likewise.
func _marker(surface: Transform3D, texture: Texture2D, tint: Color) -> Dictionary:
	return {"pos": surface.origin, "texture": texture, "modulate": tint, "basis": surface.basis}


# How markup LIES on a cell — the marker anchor convention, on the cell's own SURFACE since #273 so
# a marker on a terrace rides the terrace, and tilted with that surface since #281 so one on a ramp
# lies flat against the slope. BoardSpace.surface_transform is the one answer.
func _anchor(cell: Vector2i) -> Transform3D:
	return BoardSpace.surface_transform(cell, _heights())


# The same, for a 2D world position (sprites sit at cell centers). The LEVEL and the SLOPE both come
# from the cell those pixels fall in, so a ghost or arrow over a terrace lifts and tilts with it.
func _anchor_px(px: Vector2) -> Transform3D:
	var cell := Vector2i(floori(px.x / float(GridUtils.TILE_SIZE)), floori(px.y / float(GridUtils.TILE_SIZE)))
	var surface := BoardSpace.surface_transform(cell, _heights())
	return Transform3D(surface.basis, BoardSpace.of_pixels(px, surface.origin.y))
