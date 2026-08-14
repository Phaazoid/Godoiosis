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

const TOP := UnitMirror.COLUMN_TOP       # flat mirror boards: anchors at y 1.0

var game: Node2D            # the hidden Game coordinator; set by battle3d._ready
var overlays: BoardOverlays
var unit_mirror: UnitMirror
var board_mirror: BoardMirror   # for the fire poll; set by battle3d._ready

var _last_cells: Dictionary[BoardOverlays.Layer, Array] = {}
var _last_markers: Dictionary[BoardOverlays.Layer, Array] = {}
var _last_ghosts: Array[Dictionary] = []
var _last_fire: Array[Vector2i] = []
var _pick_texture: Texture2D   # the (3,0) "pick this unit" tile art, cut lazily


func _process(_delta: float) -> void:
	if game == null or overlays == null:
		return
	var om: OverlayManager = game.overlay_manager

	_fill(BoardOverlays.Layer.MOVE, om.move_overlay.get_used_cells())
	_fill(BoardOverlays.Layer.INVALID_MOVE, om.invalidmove_overlay.get_used_cells())
	_fill(BoardOverlays.Layer.SQUAD, om.squad_overlay.get_used_cells())
	_fill(BoardOverlays.Layer.SQUAD_RANGE, om.squadrange_overlay.get_used_cells())
	_fill(BoardOverlays.Layer.ZONE_CAPTURE, om.capture_overlay.get_used_cells())
	_fill(BoardOverlays.Layer.ZONE_EXTRACTION, om.extraction_overlay.get_used_cells())
	# Authoring scaffolding: cells AND visible, or patrol zones leak into play.
	_fill_gated(BoardOverlays.Layer.ZONE_PATROL, om.zone_overlay)
	_fill_gated(BoardOverlays.Layer.ZONE_HIGHLIGHT, om.zone_highlight_overlay)

	# The aim footprint pulses by layer modulate in 2D — the animation rides the poll.
	_fill(BoardOverlays.Layer.AIM, om.hover_overlay.get_used_cells())
	overlays.set_layer_modulate(BoardOverlays.Layer.AIM, om.hover_overlay.modulate)

	_attack(om)
	_arrows(om)

	var kb_trails: Array[Dictionary] = []
	var kb_ghosts: Array[Dictionary] = []
	_split_knockback(om, kb_trails, kb_ghosts)
	_markers(BoardOverlays.Layer.KNOCKBACK, kb_trails)

	_icons(om)
	_terrain(om)
	_ghost_sync(om, kb_ghosts)
	_fire()


# Which cells are alight, straight off the ONE enumeration form. Polled rather than wired
# because a states_changed signal would fire inside the resolver's per-effect loop and
# churn markers many times within a single pass; the poll coalesces a frame into one
# reconcile, and covers the sim, the dev brush, tick_states and load alike (#231).
func _fire() -> void:
	if board_mirror == null:
		return
	var burning: Array[Vector2i] = game.terrain_states.burning_cells()
	burning.sort()
	if _last_fire == burning:
		return
	_last_fire = burning
	board_mirror.refresh_states(burning)


# --- Fills -------------------------------------------------------------------------

# _fill's twin for a layer the 2D SHOWS AND HIDES. It takes the node, not a cell list,
# because the question is "should this be on screen" and the answer is cells AND visible —
# reading only the cells mirrors an authoring aid straight into the play view. `source` is
# untyped (OverlayManager declares zone_overlay with no type) and NULL on headless Play
# boards, which supply bare Node2Ds and never build the highlight; both are handled here so
# the caller stays one line. Hiding costs exactly one push: _fill's value-diff holds after.
func _fill_gated(layer: BoardOverlays.Layer, source) -> void:
	var node := source as TileMapLayer
	var cells: Array[Vector2i] = []
	if node != null and node.visible:
		cells = node.get_used_cells()
	_fill(layer, cells)


func _fill(layer: BoardOverlays.Layer, used: Array[Vector2i]) -> void:
	var cells: Array[Vector3i] = []
	for cell in used:
		cells.append(BoardSpace.of_flat(cell))
	cells.sort()
	if _last_cells.get(layer, Array()) == cells:
		return
	_last_cells[layer] = cells
	overlays.set_cells(layer, cells)


# ATTACK is dual-use in 2D: reach fill at (0,0), target-pick markers at (3,0) on the
# same layer — split by atlas coords; the heal-green arrives as the layer modulate.
func _attack(om: OverlayManager) -> void:
	var reach: Array[Vector3i] = []
	var picks: Array[Dictionary] = []
	for cell: Vector2i in om.attack_overlay.get_used_cells():
		if om.attack_overlay.get_cell_atlas_coords(cell) == OverlayManager.TARGET_ATLAS_COORDS:
			picks.append(_marker(_anchor(cell), _target_pick_texture(om), Color.WHITE))
		else:
			reach.append(BoardSpace.of_flat(cell))
	reach.sort()
	if _last_cells.get(BoardOverlays.Layer.ATTACK, Array()) != reach:
		_last_cells[BoardOverlays.Layer.ATTACK] = reach
		overlays.set_cells(BoardOverlays.Layer.ATTACK, reach)
	overlays.set_layer_modulate(BoardOverlays.Layer.ATTACK, om.attack_overlay.modulate)
	_markers(BoardOverlays.Layer.TARGET_PICK, picks)


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


# Selection icons (crown / squadmember / target / …): anchored to the icon's own
# authored target_cell; a small per-type height stagger keeps co-celled billboards
# from z-fighting (2D overlaps them by pixel offsets instead).
func _icons(om: OverlayManager) -> void:
	var entries: Array[Dictionary] = []
	for unit in om.icons_by_unit:
		var by_type: Dictionary = om.icons_by_unit[unit]
		for type in by_type:
			var icon := by_type[type] as OverlayIcon
			if icon == null or not is_instance_valid(icon):
				continue
			var pos := _anchor(icon.target_cell) + Vector3(0.0, float(type) * 0.02, 0.0)
			entries.append(_marker(pos, icon.sprite.texture, icon.sprite.modulate))
	_markers(BoardOverlays.Layer.ICONS, entries)


# Terrain live icons (FROZEN / COVER) + plan-time preview ghosts. Fire is skipped on
# the LIVE channel — BoardMirror's flame + light IS fire's 3D form (#174: one Fire
# texture covers BURNING and BLAZE) — but kept on the PREVIEW channel, where no 3D
# flame preview exists and the ghosted icon is the only warning.
func _terrain(om: OverlayManager) -> void:
	var fire: Texture2D = OverlayManager.TERRAIN_STATE_ICONS[Terrain.TileState.BURNING]
	var live: Array[Dictionary] = []
	for sprite in om.terrain_live_sprites:
		if not is_instance_valid(sprite) or sprite.texture == fire:
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


func _marker(pos: Vector3, texture: Texture2D, tint: Color) -> Dictionary:
	return {"pos": pos, "texture": texture, "modulate": tint}


# A cell's top-face center — the marker anchor convention.
func _anchor(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, TOP, cell.y + 0.5)


# A 2D world position's top-face anchor (sprites sit at cell centers).
func _anchor_px(px: Vector2) -> Vector3:
	return BoardSpace.of_pixels(px, TOP)
