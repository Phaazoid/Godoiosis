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

# How far the drop pointer stands off the cliff face it hangs on (#431), in cells. A depth-buffer
# epsilon, not a feel value: big enough that a coplanar wall cannot stipple through it, small
# enough to be invisible -- roughly a sixteenth of a texture pixel, against a depth precision floor
# some three orders of magnitude finer at board distances. Anything the eye can resolve here reads
# as the ribbon breaking where the fall starts, which is what this pointer keeps being reported
# for. The two failure modes pull opposite ways: raise it if a wall ever stipples through, lower it
# if the corner ever gaps.
const WALL_CLEARANCE := 0.001

# How far the pointer runs PAST each of its join points, in cells. A butt joint between two quads
# meeting at a right angle can leave a sub-pixel sliver where neither covers the corner; a hair of
# overlap cannot, and costs nothing visually because both ends tuck into art of the same colour.
const JOIN_OVERLAP := 0.005


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


# The aim's sight line (#258), lifted into the diorama at the trajectory's own heights -- the arc
# a lob clears a wall by is literally visible, a gun's line is straight by construction. Gated on
# the store's own version, never a copied key (#308); the points and the verdict were computed ONCE
# by Reach.sight_trace, so this is a second projection of one answer, not a second computation.
func _sight_trace(om: OverlayManager) -> void:
	if om.sight_trace_version == _last_trace_version:
		return
	_last_trace_version = om.sight_trace_version
	var points := PackedVector3Array()
	var tint := SightTrace2D.CLEAR_COLOR   # colours COPIED from the 2D renderer, never restated
	var trace: Reach.SightTrace = om.sight_trace
	if trace != null:
		if trace.blocked:
			tint = SightTrace2D.BLOCKED_COLOR
		for p in trace.points:
			# Rule-height h sits at world surface_y(0) + h * CELL_SIZE: a level-E surface is world
			# surface_y(E), and h counts levels above the level-0 floor plane.
			points.append(Vector3(p.x * BoardSpace.CELL_SIZE, BoardSpace.surface_y(0) + p.y * BoardSpace.CELL_SIZE, p.z * BoardSpace.CELL_SIZE))
	overlays.set_line(BoardOverlays.Layer.SIGHT_TRACE, points, tint)


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
#
# The trail is HONEST about height since the #259 rework: a sprite stamped kb_air_from is a
# FLOWN cell and hangs flat at the launch cell's level rather than lying on whatever is below
# (the hole it sails over, the ground under the cliff); the kb_drop_from sprite is the landing,
# anchored on its own surface; everything past it is a tumble step lying on its own slope. Where
# consecutive cells' surfaces do not MEET, _append_drop folds the ribbon down the gap -- "in the
# air until he would drop, then straight down to his destination" (dev).
func _split_knockback(om: OverlayManager, trails: Array[Dictionary], ghosts: Array[Dictionary]) -> void:
	for node in om.knockback_preview_sprites:
		if not is_instance_valid(node):
			continue
		var sprite := node as Sprite2D
		if sprite == null:
			continue
		# The drop pointer is hung off a trail sprite BEFORE the flat-arrow skip: a void removal
		# nulls the landing's texture (no flat arrowhead on a hole) but the pointer still draws.
		if sprite.get_parent() == om.arrow_icon_overlay:
			_append_drop(trails, sprite)
		if sprite.texture == null:
			continue
		var entry: Dictionary
		if sprite.has_meta("kb_air_from"):
			entry = _marker(_air_anchor(sprite.global_position, sprite.get_meta("kb_air_from")),
					sprite.texture, sprite.modulate)
		else:
			entry = _marker(_anchor_px(sprite.global_position), sprite.texture, sprite.modulate)
		if sprite.get_parent() == om.arrow_icon_overlay:
			trails.append(entry)
		elif sprite.get_parent() == om.projected_unit_overlay:
			ghosts.append(entry)


# The drop pointer (#431, replacing the #259 rework's stamped landing). THE RULE: a trail cell
# DROPS when the two surfaces meeting at the EDGE it was entered by are not at the same height.
# Nothing else is asked. That is why a shove that falls off a cliff, tumbles a ramp and then
# plummets off its lip now draws a pointer at BOTH breaks -- the old gate read a flag ("did this
# shove fall?") stamped on the ONE cell the flight ended on, so a second drop was unrepresentable
# however the flag was set. The heights the trail is already drawn at answer the question; the
# flag was a second seam for a fact the geometry holds (Law #4), and it went stale the moment the
# tumble learned to plummet.
#
# BoardSpace.surface_height_at_edge is the one answer to "how high is this cell's surface AT the
# edge it meets its neighbour on", and it carries exactly what this needs: a ramp's plane meets its
# neighbour's precisely at that edge. So a slide reads continuous and draws nothing, with no ramp
# special case anywhere. Since #472 the SPRITE'S OWN FALL is off the same call
# (MovementComponent._edge_drop) -- the pointer and the drop it promises are one question now,
# rather than two spellings that happened to agree on flat ground and not on a cliff.
#
# A break hangs ONE quad, and it starts falling AT THE EDGE (dev, round 5) -- the ribbon it has to
# meet begins at the back of the tile, so a fold placed anywhere further in leaves that much flat
# arrow sticking out behind the foot. On a ramp the same half cell is worse than untidy: a ramp's
# centre is half a level under its top edge, so a foot placed there lands mid-slope while the
# slope's own arrow starts at the top, and the mismatch reads as a tail. Both ends therefore land
# on the SAME point the flat markers do: the top on the ribbon crossing the edge above, the foot on
# the surface AT the edge -- never at the cell's centre, which is a different height on any slope.
#
# The layer's own clearance does the rest: at the edge this quad is coplanar with the cliff face it
# hangs on, and _apply_marker lifts every marker along its own plane normal -- which for a vertical
# quad IS the travel direction, i.e. straight out of that wall. That is what a coplanar marker has
# always needed, and it is why the pointer can depth-test honestly rather than x-raying the board.
func _append_drop(trails: Array[Dictionary], sprite: Sprite2D) -> void:
	var rail: Texture2D = sprite.get_meta("kb_rail_texture", null)
	if rail == null or not sprite.has_meta("kb_dir"):
		return   # the first cell of a trail: no edge was crossed to reach it
	var heights := _heights()
	var px := sprite.global_position
	var cell := _cell_of_px(px)
	var dir_2d: Vector2i = sprite.get_meta("kb_dir")
	var d := Vector3(dir_2d.x, 0.0, dir_2d.y)
	var centre := BoardSpace.of_pixels(px, 0.0)
	var edge := centre - d * (BoardSpace.CELL_SIZE * 0.5)
	# The upper side of the edge. A FLOWN cell and the LANDING both have the flight above them --
	# the launch cell's level, which is what the airborne arrows hang at -- and every cell past
	# the landing is a tumble step, whose upper side is the neighbouring surface read at the edge.
	var airborne := sprite.has_meta("kb_air_from")
	var flown := airborne or sprite.has_meta("kb_drop_from")
	var top := 0.0
	if flown:
		var launch: Vector2i = sprite.get_meta("kb_air_from") if airborne \
				else sprite.get_meta("kb_drop_from")
		top = BoardSpace.surface_transform(launch, heights).origin.y
	else:
		top = BoardSpace.surface_height_at_edge(cell - dir_2d, dir_2d, heights)
	# The lower side of the SAME edge. Both sides must be read at the edge or the test is not a
	# test of whether the surfaces meet: a slide onto a ramp's high shoulder enters level with the
	# flight and only then descends, so measuring this cell at its CENTRE would call every such
	# slide half a level of fall. An airborne cell hangs at the flight height on both sides, so it
	# can never break and needs no case of its own.
	var here := top if airborne else BoardSpace.surface_height_at_edge(cell, -dir_2d, heights)
	# A REMOVAL skips the break test outright: a hole is a terrain KIND, invisible to the height
	# store, so the two surfaces meet and the fall is real anyway. It drops the full plummet -- the
	# same distance the sprite itself falls in execution, off MovementComponent's one knob, because
	# a preview that promised less than the fall shows would be a Law #2 divergence.
	var bottom := here
	if bool(sprite.get_meta("kb_removed", false)):
		bottom -= MovementComponent.VOID_PLUMMET_CELLS * BoardSpace.CELL_SIZE
	elif top <= here or is_equal_approx(top, here):
		return
	# The ENDS are the points the arrows above and below are actually DRAWN at, never the raw
	# surface heights the break was measured from: the sink lifts every marker clear of the ground,
	# and joining the surface instead of the drawn plane put a seam on every ramp landing (#431).
	# Above the edge the ribbon is the FLIGHT unless this is a tumble step, where it is the
	# neighbouring slope; below it is always this cell's own markup. The flight hangs FLAT at the
	# launch level whatever it is passing over, so it takes the lift on its own height rather than
	# on the ground's -- it is not lying on the cell below and never took that cell's tilt, which is
	# the only reason it is spelled out here instead of going through _ribbon_point.
	var head := Vector3(edge.x, top, edge.z) + Vector3.UP * overlays.marker_lift(BoardOverlays.Layer.KNOCKBACK) \
			if flown else _ribbon_point(cell - dir_2d, edge)
	var foot := _ribbon_point(cell, edge) - Vector3.UP * (here - bottom)
	# The band is a CONSISTENT horizontal perpendicular -- absf() picks +Z for an X trail and +X
	# for a Z trail, and never flips with the travel sign. A band that flipped mirrored the rail's
	# sprite, and since that sprite's band sits half a pixel off the texture centre, the mirror
	# shifted it a full pixel -- "matches in one direction, off by one in the other" (dev). Forcing
	# it makes the basis LEFT-handed on one of the two signs, which is why the quad is also
	# double-sided (never culled) -- as it wants to be anyway, standing in the world under orbit.
	var band := Vector3(absf(d.z), 0.0, absf(d.x))
	# Local X (the texture's band axis) runs head-to-foot, stretched over the drop (#281's stretch
	# lesson) and overshooting both joins; the band axis stays a unit vector so the art scale the
	# flat markers use gives it the same one-cell width they wear. Local Y is the quad's normal,
	# derived so the plane stays square when a ramp foot leans the fall a fraction off vertical,
	# and turned to face the way the unit was travelling.
	var fall := foot - head
	var normal := band.cross(fall).normalized()
	if normal.dot(d) < 0.0:
		normal = -normal
	var down := (fall + fall.normalized() * (JOIN_OVERLAP * 2.0)) / BoardSpace.CELL_SIZE
	# The pointer's ends are already the drawn planes' own points, lift included, so the sink must
	# not add the layer lift a second time -- lift_dir ZERO says exactly that. What it does still
	# need is WALL_CLEARANCE: at the edge this quad is coplanar with the cliff face, and a hair of
	# depth keeps it from stippling through without being wide enough to read as a gap.
	# The tint is COPIED off the trail sprite the pointer hangs from, never a constant of its own:
	# the pointer is part of that trail, so a second answer here would leave it white the moment the
	# shove colour is tuned -- which reads as a bug rather than as a knob (Law #4).
	trails.append({"pos": (head + foot) * 0.5 + d * WALL_CLEARANCE,
			"texture": rail, "modulate": sprite.modulate, "lift_dir": Vector3.ZERO,
			"basis": Basis(down, normal, band), "double_sided": true})


# Where the markup DRAWN on this cell actually sits at a given (x, z): the surface there, plus the
# clearance the sink lifts that cell's markers by. Since #432 that lift is straight UP on a slope
# as much as on the flat, so this is a plain surface read again and a ramp's arrow no longer
# retreats from its own cell boundary. It stays a seam rather than being inlined because both ends
# of a pointer have to ask ONE question about where markup lies.
func _ribbon_point(cell: Vector2i, at: Vector3) -> Vector3:
	var y := BoardSpace.surface_height_at(cell, at.x, at.z, _heights())
	return Vector3(at.x, y, at.z) + Vector3.UP * overlays.marker_lift(BoardOverlays.Layer.KNOCKBACK)


# A FLYING trail arrow: flat at the shove's launch height, no tilt -- it hangs in the air rather
# than lying on a surface, so neither the level nor the slope of the cell below may touch it.
func _air_anchor(px: Vector2, from_cell: Vector2i) -> Transform3D:
	var flight_y := BoardSpace.surface_transform(from_cell, _heights()).origin.y
	return Transform3D(Basis.IDENTITY, BoardSpace.of_pixels(px, flight_y))


# Unit markers, routed by TYPE rather than by a style mode (#325 verdict, dev call after playing
# both, 2026-08-19). CROWN rides ICONS as a head billboard -- leadership is what a unit IS, and
# nothing has read better over a head than the original crown. Everything else (today, SQUADMEMBER)
# rides GROUND_ICONS as a surface decal in the squad's own hue, texture and tint arriving BY COPY
# from the 2D sprite, so the hue is authored in one place and never re-derived here.
#
# They were SELECTION icons until #423 slice 1; ALWAYS_SHOW_SQUAD_RINGS can now keep membership
# rings standing, which is why the anchor below asks the ICON where its unit is instead of reading
# a cell stamped when the marker was built.
#
# The leader wears BOTH: a ring because they are a member, the crown because they lead.
#
# No per-type y-stagger any more. It existed to keep several head-icon types off each other's
# plane; CROWN is the channel's only tenant now, so there is nothing to stagger against.
func _icons(om: OverlayManager) -> void:
	var heads: Array[Dictionary] = []
	var ground: Array[Dictionary] = []
	var wards: Array[Dictionary] = []
	for unit in om.icons_by_unit:
		var by_type: Dictionary = om.icons_by_unit[unit]
		for type in by_type:
			var icon := by_type[type] as OverlayIcon
			if icon == null or not is_instance_valid(icon) or not icon.has_unit():
				continue
			var surface := _anchor(icon.current_cell())
			var entry := _marker(surface, icon.sprite.texture, icon.sprite.modulate)
			if type == OverlayIcon.IconType.CROWN:
				heads.append(entry)
			elif type == OverlayIcon.IconType.GUARD_WARD:
				# Its own layer, not because it is a different KIND of markup -- it is a ground decal
				# like the rings -- but because a layer is a PLANE, and sharing one with the ring put
				# two coplanar quads on the same cell and made them z-fight (#414, found in play).
				wards.append(entry)
			else:
				ground.append(entry)
	_markers(BoardOverlays.Layer.ICONS, heads)
	_markers(BoardOverlays.Layer.GROUND_ICONS, ground)
	_markers(BoardOverlays.Layer.GUARD_ICONS, wards)


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
	var surface := BoardSpace.surface_transform(_cell_of_px(px), _heights())
	return Transform3D(surface.basis, BoardSpace.of_pixels(px, surface.origin.y))


# Which 2D CELL a sprite's pixels fall in. Split out of _anchor_px because the drop pointer needs
# the cell itself (to reach the neighbour across the edge it was entered by) rather than the
# transform -- and two spellings of pixels-to-cell is the drift Law #4 names.
func _cell_of_px(px: Vector2) -> Vector2i:
	return Vector2i(floori(px.x / float(GridUtils.TILE_SIZE)), floori(px.y / float(GridUtils.TILE_SIZE)))
