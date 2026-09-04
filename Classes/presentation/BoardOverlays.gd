extends Node3D
class_name BoardOverlays

# The 3D presentation stack's board markup (#213 / #176 stages 3+4c): the one owner
# of per-cell overlay layers. Four marker kinds — FILL (pooled unshaded quads lying
# on the cell's top face; the dev's ruling that gameplay markup must never read as
# terrain, which a lit Decal cannot honor), BRACKET (the voxel corner-bracket
# pointer), SPRITE (a ground quad with per-marker texture+tint — path arrows,
# knockback trails, terrain icons, pick markers), BILLBOARD (a camera-facing
# Sprite3D above the cell — selection icons). Layer colors deliberately mirror the
# 2D OverlayManager's constants — one declared representation per presentation
# stack (the parallel-stacks doctrine); change a color in both places or say why not.
#
# Contract: a dumb idempotent sink. set_cells/set_markers replace a layer wholesale
# and are cheap ONLY when the caller diffs first (OverlayMirror does); marker pos is
# the cell's top-face ANCHOR (the mirror's geometry), and the LAYER adds its own
# lift — board shape stays the caller's business.
#
# The layers are PARTITIONED BY WRITER, which is why there is no whole-sink wipe: battle3d owns
# HOVER (the pointer bracket, the one layer deliberately not mirrored) and OverlayMirror owns the
# rest, caching what it has pushed. Emptying every layer at once is therefore always one writer
# reaching across that line and desyncing the other's cache — the clear_all() this used to carry
# did exactly that on every board load (#318). Clear the layers you own.
#
# The mask contract: fill/sprite quads render on WORLD_RENDER_LAYER only, and
# UnitSprite3D lives on UNIT_RENDER_LAYER. Both constants live HERE; a drift test
# pins them disjoint.

enum Layer {
	MOVE, ATTACK, ZONE_CAPTURE, ZONE_EXTRACTION, HOVER,
	INVALID_MOVE, SQUAD, SQUAD_RANGE, AIM,
	TARGET_PICK, PATH_ARROWS, KNOCKBACK, TERRAIN, TERRAIN_PREVIEW, ICONS,
	ZONE_PATROL, ZONE_HIGHLIGHT, GROUND_ICONS, ATTACK_BLOCKED, SIGHT_TRACE,
	GUARD_ICONS, GUARD_LINK, WATCH_ICONS,
	ZONE_DEPLOYMENT,
}
enum Kind { FILL, BRACKET, SPRITE, BILLBOARD, LINE }

const WORLD_RENDER_LAYER := 1  # bit for layer index 0 — the board and props
const UNIT_RENDER_LAYER := 2   # bit for layer index 1 — UnitSprite3D sets this
# Every unit sprite (real or planning ghost) sorts ABOVE every overlay layer, structurally
# rather than by numeric luck — the 3D twin of the 2D's "tile overlays sit below
# Unit.BASE_SPRITE_INDEX". Must stay greater than any LAYERS "sort"; pinned by a test.
# It only ARBITRATES in the alpha queue, though (#317): an OPAQUE_PREPASS sprite is held above
# markup by the depth it writes instead, and it writes none where alpha is under the prepass
# threshold — which is why UnitMirror builds the translucent ghosts alpha_cut DISABLED.
const UNIT_RENDER_PRIORITY := 32
# Fire's 3D form is a STANDING effect, not markup lying on the tile face, so it sorts above every
# overlay layer — the same structural claim units make, one band below them so the flame-vs-sprite
# relationship #236 argued over is untouched. Found in play (#245): the flame set no priority at
# all, so it sat at 0 while Layer.TERRAIN sorts at 2, and painting a frost icon onto a burning
# tile drew straight over the flame. The fire read as erased; the store was perfectly correct.
const FLAME_RENDER_PRIORITY := 16
# The band above the units: HUD hung in the volume over a unit's head (#229's health readout), which
# must never be sorted behind the sprite it describes. It lives HERE with the other two because the
# relationship between the bands is the thing worth pinning, and a table is the only place a
# relationship can be read at a glance. The readout claims this value and the SIX above it: five
# coplanar quads (outline, missing, fill, the predicted span, the notch) then the number's outline
# and its glyphs.
const UNIT_HUD_RENDER_PRIORITY := 48

const LAYERS: Dictionary[Layer, Dictionary] = {
	Layer.MOVE: {"color": Color(1, 1, 0, 0.5), "sort": 0, "kind": Kind.FILL},
	Layer.ATTACK: {"color": Color(1, 0, 0, 0.5), "sort": 1, "kind": Kind.FILL},
	# Reach cells past the aim's vertical tolerance (#258). Shares ATTACK's sort safely: the 2D
	# splits the one layer by atlas coords, so the two cell sets are disjoint by construction and
	# can never z-fight. Colour here is only the no-mirror fallback -- OverlayMirror drives it per
	# frame as the live reach modulate x OverlayManager.BLOCKED_REACH_DIM (so no colour knob here).
	Layer.ATTACK_BLOCKED: {"color": Color(0.45, 0, 0, 0.5), "sort": 1, "kind": Kind.FILL},
	# The zone BAND sits at -3, with the picked-zone highlight alone at -2 above it. In 2D
	# the highlight wins by TREE ORDER (appended last); 3D has no such thing, so the sort
	# number IS the relationship and a test pins it rather than the values (#231). -1 was
	# unavailable: SQUAD/SQUAD_RANGE live there and would share the lift, i.e. z-fight.
	Layer.ZONE_CAPTURE: {"color": Color(0.3, 0.9, 1, 0.5), "sort": -3, "kind": Kind.FILL},
	Layer.ZONE_EXTRACTION: {"color": Color(0.4, 1, 0.5, 0.5), "sort": -3, "kind": Kind.FILL},
	Layer.ZONE_PATROL: {"color": OverlayManager.ZONE_PATROL_MODULATE, "sort": -3, "kind": Kind.FILL},
	# #736. In the band with the others: it is markup lying on the tile face like every zone, and it
	# is gone before any of them matter -- turn 1 stops it being drawn at all.
	Layer.ZONE_DEPLOYMENT: {"color": Color(0.65, 0.5, 1, 0.45), "sort": -3, "kind": Kind.FILL},
	Layer.ZONE_HIGHLIGHT: {"color": OverlayManager.ZONE_HIGHLIGHT_MODULATE, "sort": -2, "kind": Kind.FILL},
	Layer.HOVER: {"color": Color(1, 0.9, 0.3, 0.9), "sort": 2, "kind": Kind.BRACKET},
	Layer.INVALID_MOVE: {"color": Color(0.5, 0.36, 0.4, 0.5), "sort": 0, "kind": Kind.FILL},
	Layer.SQUAD: {"color": Color(1, 0.5, 0, 0.5), "sort": -1, "kind": Kind.FILL},
	Layer.SQUAD_RANGE: {"color": Color(1, 0.5, 0, 0.5), "sort": -1, "kind": Kind.FILL},
	Layer.AIM: {"color": Color(1, 1, 0, 1), "sort": 4, "kind": Kind.FILL},
	Layer.TARGET_PICK: {"color": Color.WHITE, "sort": 5, "kind": Kind.SPRITE},
	Layer.PATH_ARROWS: {"color": Color.WHITE, "sort": 6, "kind": Kind.SPRITE},
	Layer.KNOCKBACK: {"color": Color.WHITE, "sort": 6, "kind": Kind.SPRITE},
	# The aim's sight line (#258) -- a laser polyline at the trajectory's own heights, not cell
	# markup. Colour arrives per set_line call (the 2D SightTrace2D verdict colours, copied by the
	# mirror -- parallel-stacks rule); the entry colour is only the fallback.
	Layer.SIGHT_TRACE: {"color": Color.WHITE, "sort": 7, "kind": Kind.LINE},
	# The ground form of the selection icons (#325 experiment): membership rings + the leader's
	# crown decal lying on the cell surface. Above terrain state, below the aim pulse, pick
	# markers and arrows (a ring must never eat an arrowhead) -- AIM/TARGET_PICK/arrows each
	# moved up one to open this slot. Colour stays WHITE: the tint is per-entry (the squad hue,
	# copied off the 2D sprite), which is also why this layer can never take a GameKnobs colour row.
	Layer.GROUND_ICONS: {"color": Color.WHITE, "sort": 3, "kind": Kind.SPRITE},
	# The armed-Guard ward mark (#414) gets its OWN layer purely so it stops Z-FIGHTING the squad
	# ring, which it shared a cell and a layer with. A layer IS a plane here -- _lift_of is
	# fill_lift + sort * lift_step -- so two markers on one layer are coplanar by construction and
	# no per-marker nudge can separate them without breaking that rule (#432's own lesson).
	#
	# Sort 8 rather than 4: it may not share a sort with any layer whose CELLS it can overlap, and a
	# warded unit's cell can carry an aim fill (4), a target-pick marker (5), an arrow (6) or a sight
	# trace (7). 8 is the first free slot above all of them. Consequence, deliberate: the ward mark
	# reads OVER ground markup, which is #346's rule -- the interaction is the thing you must not
	# miss, and ambient membership yielding to it is the trade. One integer if that reads wrong.
	Layer.GUARD_ICONS: {"color": Color.WHITE, "sort": 8, "kind": Kind.SPRITE},
	# The blocker->ward arrow (#450), and its own layer for the reason the shield above has one: a
	# layer is a plane, and this trail's two cells are exactly the cells the shield, an aim fill, a
	# target-pick mark, a path arrow or a sight trace can already be sitting on.
	#
	# ABOVE the shield rather than under it, which is a decision and not the leftover integer: the
	# 2D draws these into ArrowIconOverlay, a later sibling than IconOverlay at the same z_index, so
	# the arrowhead lands over the shield there whatever this number says -- and the two views must
	# agree. Reverse BOTH (swap with 8, give the 2D link RING_Z_INDEX) if the head crowds the shield.
	Layer.GUARD_LINK: {"color": Color.WHITE, "sort": 9, "kind": Kind.SPRITE},
	# The watched-footprint threat mark (#413), and it takes a layer of its OWN for the same reason
	# the ward mark did: a layer IS a plane, so a marker that can share a CELL with another marker
	# must not share its sort. A watched cell can carry an aim fill (4), a target-pick marker (5), an
	# arrow (6), a sight trace (7), a ward mark (8) and now the ward LINK (9) -- a warded pair
	# standing in a watched line is an ordinary board state, not a corner case -- so 10 is the first
	# sort free of all of them. #413 and #450 both landed on 9 on their own branches; this is the one
	# that moved, because the link's 9 encodes a stated relationship to the shield's 8 and this does
	# not care which side of the pair it sits on, only that it is not IN it.
	# Colour stays WHITE here: OverlayMirror copies the 2D sprite's own modulate, which is the
	# knob-tuned OverlayManager.WATCH_MARK_COLOR, so a second value here could only disagree with it.
	Layer.WATCH_ICONS: {"color": Color.WHITE, "sort": 10, "kind": Kind.SPRITE},
	# Sort 2, NOT above the arrows: the 2D is the authority and it puts terrain state at
	# TERRAIN_Z_INDEX (above the board, below unit sprites) with arrows above it. At 6 this
	# was the top of the table, so freeze icons drew over path arrows and planning ghosts.
	Layer.TERRAIN: {"color": Color.WHITE, "sort": 2, "kind": Kind.SPRITE},
	Layer.TERRAIN_PREVIEW: {"color": Color.WHITE, "sort": 2, "kind": Kind.SPRITE},
	# The ONE layer that hangs in the AIR rather than lying on the floor, so it sorts above
	# every floor layer. It sat at 0 while nothing could overlap it; #325 then put a ring
	# decal (3) directly under every crown, which drew straight over it. 15 is the top of
	# the lawful band -- a law pins every layer under FLAME_RENDER_PRIORITY. A BILLBOARD
	# ignores _lift_of and rides billboard_lift, so this moves PRIORITY only, not geometry.
	Layer.ICONS: {"color": Color.WHITE, "sort": 15, "kind": Kind.BILLBOARD},
}

const FILL_TEXTURE_PATH := "res://Art/LookDev/cell_fill.png"
# Colocated with its only consumer rather than in a shaders folder the project does not have.
const SIGHT_BEAM_SHADER_PATH := "res://Classes/presentation/sight_beam.gdshader"
# The 2D art's metric: a 16px texture covers exactly one board cell.
const ART_PIXELS_PER_CELL := 16.0

# How much of a column the hover selector encloses (#427 slice 2 follow-up). An ENUM rather than a
# row count because the vocabulary is fixed and because a knob carrying `options` renders as a
# picker (DevWidgets.add_knob_row) -- LookKnobs' tonemap_mode is the same shape.
#
# LEVEL is one whole block, which is what the selector marked before slice 2 re-metricked a GridMap
# row to a HEIGHT UNIT. HALF is one unit, for reading a half-step apart from the level it sits in.
enum SelectorDepth { LEVEL, HALF }

# Eye-knobs (the tuning rule); read when markers build/place.
@export var bracket_arm := 0.22
@export var bracket_thickness := 0.04
@export var bracket_scale := 1.02
# NOT a plain field: the HOVER layer only repaints when the pointer CELL changes (battle3d's
# _update_pointer early-outs on an unchanged one), so turning this with the mouse still would move
# nothing until you nudged it -- a knob that appears to do nothing is the one failure that makes a
# knob worthless (#324's rule, where every flame value rebuilds what is already standing).
@export var selector_depth: SelectorDepth = SelectorDepth.LEVEL: set = _set_selector_depth
@export var fill_lift := 0.02          # quad height above the top face — the z-fight gap
@export var lift_step := 0.004         # per-sort spacing so stacked layers never coincide
@export var billboard_lift := 0.85     # icon height above the cell's top face
@export var billboard_pixel_size := 1.0 / 32.0
# What the hover bracket turns when the pointer is over something the 2D calls INVALID (#245).
# A knob because there is nothing to mirror here: 2D says "invalid" with a negative-icon TEXTURE,
# and a bracket has no texture to swap, so the colour is a fresh aesthetic call.
@export var invalid_bracket_color := Color(1.0, 0.3, 0.3, 0.9)

# The sight beam's shape (#506). Each one re-applies on write rather than being read at build time:
# a knob that only takes effect on the next rebuild is a slider the dev drags with nothing moving,
# and a standing trace does not rebuild until the pointer does. The pools may not exist yet when a
# setter runs (member initializers, and a LINE pool is built lazily by set_line), which is why
# _apply_beam_params tolerates an empty one instead of guarding at each call site.
#
# COLOUR is deliberately absent: it arrives per draw as the aim's verdict tint, copied from
# SightTrace2D so the flat view and the diorama cannot disagree about what "blocked" looks like.
# Brightness is here rather than folded into that colour -- see the shader's own note. WIDTH is the
# whole offset: the screen-pixel FLOOR that used to sit beside it is gone, and the shader says why.
#
# THE `: set = _name` SUFFIX IS REQUIRED, NOT A STYLE CHOICE, and tidying these three into inline
# `set(value):` blocks silently breaks the file. `KnobSource.DECLARATION_LINE` carries that suffix
# but has no clause for a block, so it matches an inline-block declaration anyway and eats the
# trailing colon with the value -- Save rewrites `x := 0.06:` to `x := 0.99` and leaves the block
# beneath it orphaned, i.e. a parse error in the script the whole 3D stack hangs off, written
# silently the first time the dev tunes a beam and presses Save. Measured, not reasoned.
@export var beam_width := 0.075: set = _set_beam_width              # world units; a cell is 1.0
@export var beam_softness := 1.1: set = _set_beam_softness         # edge falloff exponent
@export var beam_intensity := 3.9: set = _set_beam_intensity       # ALBEDO multiplier; >1.2 blooms


func _set_beam_width(value: float) -> void:
	beam_width = value
	_apply_beam_params()


func _set_beam_softness(value: float) -> void:
	beam_softness = value
	_apply_beam_params()


func _set_beam_intensity(value: float) -> void:
	beam_intensity = value
	_apply_beam_params()

var fill_texture: Texture2D

var _markers: Dictionary[Layer, Array] = {}       # layer -> node pool (all kinds)
var _cells: Dictionary[Layer, Array] = {}         # set_cells layers: the current cell list
var _marker_data: Dictionary[Layer, Array] = {}   # set_markers layers: the current entries
var _lines: Dictionary[Layer, PackedVector3Array] = {}   # set_line layers: the current polyline
var _layer_colors: Dictionary[Layer, Color] = {}  # runtime fill colors (set_layer_modulate)
var _bracket_mesh: ArrayMesh
var _quad_mesh: PlaneMesh
# The folded quads corner-cell markup lies on (#427 slice 4 follow-up), keyed by the cell's SHAPE --
# its corners relative to the low one -- so a whole board of corner cells costs at most twelve masks
# times two climbs. See _surface_mesh for why a transform cannot carry the fold.
var _bent_meshes: Dictionary[Vector4i, ArrayMesh] = {}


func _ready() -> void:
	if fill_texture == null:
		fill_texture = load(FILL_TEXTURE_PATH) as Texture2D


# Replaces the layer's cells wholesale (idempotent — calling twice with the same
# set changes nothing; extras from a previous, larger set are hidden, not leaked).
# FILL/BRACKET layers only — variant layers go through set_markers.
#
# `heights` is what lets a fill LIE ON a ramp rather than hang level through it (#281). Taken as a
# parameter rather than held, the way BoardMirror.sync takes it: null reads as flat, which is what
# the headless Play boards and the pooled-clear path both want.
func set_cells(layer: Layer, cells: Array[Vector3i], heights: BoardHeights = null) -> void:
	var spec: Dictionary = LAYERS[layer]
	if spec["kind"] != Kind.FILL and spec["kind"] != Kind.BRACKET:
		push_error("set_cells on a %s layer — use set_markers" % Kind.keys()[spec["kind"]])
		return
	_cells[layer] = cells.duplicate()
	var pool: Array = _pool_for(layer)
	while pool.size() < cells.size():
		pool.append(_make_marker(layer))
	for i in pool.size():
		var marker := pool[i] as Node3D
		if i < cells.size():
			marker.visible = true
			marker.transform = _marker_transform(spec, cells[i], heights)
			# A FILL rides the surface, so on a corner cell the fold is in its MESH rather than in
			# the transform above (#427 slice 4 follow-up). A BRACKET marks a VOLUME and keeps its
			# box. Assigned unconditionally because the pool is reused: a marker that was on a
			# corner and is now on flat ground has to be handed the flat quad back.
			if spec["kind"] == Kind.FILL:
				(marker as MeshInstance3D).mesh = _surface_mesh(_corners_under(cells[i], heights))
		else:
			marker.visible = false


# Replaces a variant layer wholesale: one entry per marker, {"pos": Vector3 (the
# cell's top-face anchor), "texture": Texture2D, "modulate": Color, "basis": Basis
# (optional — how the surface under it is tilted, identity on flat ground),
# "corners": Vector4i (optional — the SHAPE of the cell it lies on, so a corner
# cell's fold reaches the mesh; absent or ZERO means it lies on nothing, which is
# what an airborne marker wants)}. Same idempotent-pool contract as set_cells.
# SPRITE/BILLBOARD layers only.
func set_markers(layer: Layer, markers: Array[Dictionary]) -> void:
	var spec: Dictionary = LAYERS[layer]
	if spec["kind"] != Kind.SPRITE and spec["kind"] != Kind.BILLBOARD:
		push_error("set_markers on a %s layer — use set_cells" % Kind.keys()[spec["kind"]])
		return
	_marker_data[layer] = markers.duplicate()
	var pool: Array = _pool_for(layer)
	while pool.size() < markers.size():
		pool.append(_make_marker(layer))
	for i in pool.size():
		var node := pool[i] as Node3D
		if i < markers.size():
			node.visible = true
			_apply_marker(spec, node, markers[i])
		else:
			node.visible = false


# Runtime recolor of a FILL or BRACKET layer's pool (the heal-green reach, the aim pulse —
# colors the 2D layer modulates live; and the hover bracket's invalid red, #245). Skip-if-equal
# so a per-frame poll is free. Both kinds are a MeshInstance3D with a StandardMaterial3D
# override, which is why one loop serves them; SPRITE/BILLBOARD carry per-marker tints instead
# and would need their entry data rewritten, not their pool.
func set_layer_modulate(layer: Layer, color: Color) -> void:
	var spec: Dictionary = LAYERS[layer]
	if spec["kind"] != Kind.FILL and spec["kind"] != Kind.BRACKET:
		push_error("set_layer_modulate is for FILL and BRACKET layers")
		return
	if _layer_colors.get(layer, spec["color"]) == color:
		return
	_layer_colors[layer] = color
	for node: Node3D in _pool_for(layer):
		var material := (node as MeshInstance3D).material_override as StandardMaterial3D
		material.albedo_color = color


# Replaces a LINE layer's polyline wholesale -- one pooled MeshInstance3D whose ImmediateMesh is
# rebuilt per call (a hovered aim changes every mouse move; a ribbon rebuild of ~15 points is
# nothing). Points arrive in WORLD space at the trajectory's own heights; fewer than 2 hides it.
#
# The centreline is emitted TWICE per point (#506) -- same position, side flag 0 then 1 -- and
# sight_beam.gdshader pushes the pair apart to face the camera. So the mesh is a TRIANGLE_STRIP of
# 2N vertices, and what it stores is still just the centreline: `line_of` and every caller upstream
# are unchanged, which is what let the ribbon land without touching Reach or OverlayMirror.
func set_line(layer: Layer, points: PackedVector3Array, color: Color) -> void:
	var spec: Dictionary = LAYERS[layer]
	if spec["kind"] != Kind.LINE:
		push_error("set_line on a %s layer" % Kind.keys()[spec["kind"]])
		return
	_lines[layer] = points.duplicate()
	var pool: Array = _pool_for(layer)
	if pool.is_empty():
		pool.append(_make_marker(layer))
	var node := pool[0] as MeshInstance3D
	var mesh := node.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if points.size() < 2:
		node.visible = false
		return
	node.visible = true
	var tangents := _beam_tangents(points)
	var last := float(points.size() - 1)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in points.size():
		# UV.x is the position along the beam, UV.y the side flag the shader remaps to -1/+1.
		var along := float(i) / last
		mesh.surface_set_normal(tangents[i])
		mesh.surface_set_uv(Vector2(along, 0.0))
		mesh.surface_add_vertex(points[i])
		mesh.surface_set_normal(tangents[i])
		mesh.surface_set_uv(Vector2(along, 1.0))
		mesh.surface_add_vertex(points[i])
	mesh.surface_end()
	(node.material_override as ShaderMaterial).set_shader_parameter("beam_color", color)


# The direction the ribbon is "along" at each point. Interior points AVERAGE their two segments
# rather than taking one: a lob's arc bends at every sample, and a tangent that jumps between
# segments splits the strip open at each joint. Endpoints have one segment and use it. A
# zero-length segment (coincident samples, which a shot blocked at t=0 can produce) contributes
# nothing instead of poisoning the average with a NaN.
func _beam_tangents(points: PackedVector3Array) -> PackedVector3Array:
	var tangents := PackedVector3Array()
	var count := points.size()
	for i in count:
		var back := Vector3.ZERO
		var ahead := Vector3.ZERO
		if i > 0:
			back = points[i] - points[i - 1]
			if back.length_squared() > 0.0:
				back = back.normalized()
			else:
				back = Vector3.ZERO
		if i < count - 1:
			ahead = points[i + 1] - points[i]
			if ahead.length_squared() > 0.0:
				ahead = ahead.normalized()
			else:
				ahead = Vector3.ZERO
		var joint := back + ahead
		if joint.length_squared() > 0.0:
			tangents.append(joint.normalized())
		else:
			tangents.append(Vector3.FORWARD)
	return tangents


# Pushes the four shape knobs at every built beam. Called by each setter AND by _make_line, which
# is the half that is easy to miss: the LINE pool is built lazily on the first set_line, so a knob
# written before any aim was hovered would otherwise be dropped and the beam would come up with the
# shader's own defaults instead of the authored ones.
func _apply_beam_params() -> void:
	for layer: Layer in _markers:
		if LAYERS[layer]["kind"] != Kind.LINE:
			continue
		for node: Node3D in _markers[layer]:
			_style_beam((node as MeshInstance3D).material_override as ShaderMaterial)


func _style_beam(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter("beam_width", beam_width)
	material.set_shader_parameter("beam_softness", beam_softness)
	material.set_shader_parameter("beam_intensity", beam_intensity)


func line_of(layer: Layer) -> PackedVector3Array:
	return _lines.get(layer, PackedVector3Array()).duplicate()


func clear(layer: Layer) -> void:
	var spec: Dictionary = LAYERS[layer]
	if spec["kind"] == Kind.SPRITE or spec["kind"] == Kind.BILLBOARD:
		set_markers(layer, [])
	elif spec["kind"] == Kind.LINE:
		set_line(layer, PackedVector3Array(), LAYERS[layer]["color"])
	else:
		set_cells(layer, [])


func cells_of(layer: Layer) -> Array[Vector3i]:
	var current: Array[Vector3i] = []
	current.assign(_cells.get(layer, []))
	return current


func markers_of(layer: Layer) -> Array[Dictionary]:
	var current: Array[Dictionary] = []
	current.assign(_marker_data.get(layer, []))
	return current


func layer_modulate(layer: Layer) -> Color:
	return _layer_colors.get(layer, LAYERS[layer]["color"])


# The AUTHORED colour, ignoring any runtime override — what a layer goes back TO. Distinct from
# layer_modulate() above, which answers what it is right NOW; a caller restoring a tint needs this
# one, or it would "restore" to whatever it last set.
func authored_color(layer: Layer) -> Color:
	var color: Color = LAYERS[layer]["color"]
	return color


func marker_count(layer: Layer) -> int:
	var pool: Array = _markers.get(layer, [])
	var visible_count := 0
	for marker: Node3D in pool:
		if marker.visible:
			visible_count += 1
	return visible_count


# --- Marker construction -----------------------------------------------------------

func _pool_for(layer: Layer) -> Array:
	if not _markers.has(layer):
		_markers[layer] = []
	return _markers[layer]


# A BRACKET marks a cell VOLUME and stays axis-aligned; a FILL is ground markup and rides the
# surface, tilt included (#281). The clearance itself is VERTICAL and not along the surface's own
# normal (#432) -- see _lift_of, where the direction turns out to be the whole question on a slope.
#
# The bracket's TOP FACE sits on the cell's surface and its depth reaches DOWN from there (#427
# slice 2 follow-up). It used to be cell_center, which was the same statement while a mirror cell
# was a CUBE -- slice 2 made a row half a level, left the bracket a level tall, and so hung it a
# QUARTER of a level high at both ends: proud of the block on top, short of the floor underneath.
# Dev, with screenshots: "it hovers a half height too high ... hovering above a block, and not going
# to the floor." The same law the brush ghost states, deliberately worded the same way, because the
# two are the only things in the stack that draw a volume rather than lie on one.
#
# No `heights` needed: cell.y is already the picked column's TOP row (battle3d's _tops), so the
# surface is right there.
func _marker_transform(spec: Dictionary, cell: Vector3i, heights: BoardHeights) -> Transform3D:
	if spec["kind"] == Kind.BRACKET:
		var centre := BoardSpace.cell_center(cell)
		centre.y = BoardSpace.surface_y(cell.y) - selector_half_height()
		return Transform3D(Basis.IDENTITY, centre)
	var surface := BoardSpace.lie_on(cell, _corners_under(cell, heights))
	return Transform3D(surface.basis, surface.origin + Vector3.UP * _lift_of(spec))


# The CORNERS a cell's markup lies on, since #427 slice 3 -- not a rise and a climb, because markup
# on a corner form has to follow a DIAGONAL downhill, which the cardinal pair could not describe.
func _corners_under(cell: Vector3i, heights: BoardHeights) -> Vector4i:
	return Vector4i.ZERO if heights == null else heights.corners_at(BoardSpace.flat(cell))


# Which mesh lies on these corners (#427 slice 4 follow-up). The shared flat quad for a PLANAR form,
# which is flat ground and every cardinal ramp -- so nearly every cell on nearly every board is
# untouched and pays one predicate.
#
# A corner form is not planar, and lie_on says so by handing back an identity basis: an affine
# transform maps a plane to a plane, so the fold cannot live in the transform and lives HERE, in four
# vertices at their true heights. That is the whole fix -- a tilted flat quad crossed the ground by a
# quarter of the climb at every corner, which is what the z-fighting on a corner tile's flat half was.
#
# THE MESH CALLS THE QUERY: vertex heights and the diagonal both come from Terrain.height_at_uv, the
# same function the cap meshes are cut by (slice 3's law). Two triangulations of one quad meet at all
# four corners and differ only INSIDE, so a markup quad that split the other way would sit up to a
# quarter of the climb off the ground it is drawn on -- and PlaneMesh's own split is fixed SW--NE,
# which is the wrong one whenever NE and SW differ.
func _surface_mesh(corners: Vector4i) -> Mesh:
	if _quad_mesh == null:
		_quad_mesh = PlaneMesh.new()
		_quad_mesh.size = Vector2.ONE * BoardSpace.CELL_SIZE
	if Terrain.is_planar_form(corners):
		return _quad_mesh
	# Keyed by the SHAPE, not the cell: a form is a mask plus a climb, so twelve non-cardinal masks
	# times two climbs is the whole cache, however big the board.
	var low := Terrain.low_of_corners(corners)
	var shape := corners - Vector4i(low, low, low, low)
	if _bent_meshes.has(shape):
		return _bent_meshes[shape]
	var mesh := _build_bent_mesh(shape)
	_bent_meshes[shape] = mesh
	return mesh


# The four corners in PlaneMesh's own frame: u east across the cell, v south down it, which is the
# frame Terrain.height_at_uv answers in. Measured off PlaneMesh rather than assumed, so a bent quad
# and a flat one carry the same art the same way up.
const _QUAD_UVS: Array[Vector2] = [
	Vector2(0.0, 0.0),   # NW
	Vector2(1.0, 0.0),   # NE
	Vector2(1.0, 1.0),   # SE
	Vector2(0.0, 1.0)    # SW
]


func _build_bent_mesh(shape: Vector4i) -> ArrayMesh:
	var centre := Terrain.height_at_uv(shape, 0.5, 0.5)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	for uv in _QUAD_UVS:
		verts.append(Vector3(
			(uv.x - 0.5) * BoardSpace.CELL_SIZE,
			(Terrain.height_at_uv(shape, uv.x, uv.y) - centre) * BoardSpace.ROW_HEIGHT,
			(uv.y - 0.5) * BoardSpace.CELL_SIZE))
		uvs.append(uv)
		normals.append(Vector3.UP)   # unshaded markup: declared to match PlaneMesh, never lit
	# The diagonal joins the two EQUAL corners, exactly as height_at_uv splits -- so the drawn quad
	# and the queried surface cannot disagree. Winding replicates PlaneMesh's for each case, which is
	# what keeps the face pointing up; the vertex ORDER is the whole of it, since a bent quad is two
	# triangles and the wrong pair would tent the wrong way.
	var index := PackedInt32Array([0, 1, 2, 0, 2, 3])   # NW-SE split: (NW,NE,SE) + (NW,SE,SW)
	if shape.y == shape.w:
		index = PackedInt32Array([2, 3, 1, 3, 0, 1])    # NE-SW split: (SE,SW,NE) + (SW,NW,NE)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Per-sort spacing keeps coplanar stacked fills apart; render_priority (set at
# construction) keeps the alpha blend order stable regardless.
#
# Applied STRAIGHT UP, never along the surface's normal (#432). What the lift buys is a shared
# PLANE -- every marker on a layer the same distance off the ground, which is what lets one
# ribbon run through several of them -- and BoardSpace.surface_height_at already meets exactly at
# shared edges, so a CONSTANT vertical offset stays continuous wherever the ground is. A normal
# lift does not: a ramp's leans, so it decomposed into half up and half DOWNHILL, sliding every
# marker out of its own cell by lift*sin(slope) and stepping the plane at every flat-to-ramp edge.
# The price is that a 45-degree slope's PERPENDICULAR clearance is cos(45) of the flat ground's
# -- fill_lift is the knob if a ramp ever speckles.
func _lift_of(spec: Dictionary) -> float:
	return fill_lift + spec["sort"] * lift_step


# How far off its surface this layer's markup sits. Public because a marker that has to MEET other
# markers rather than lie beside them -- the knockback drop pointer, which joins the flat arrows at
# a right angle -- has to land in the plane they were lifted INTO, not on the raw surface (#431).
# Since #432 that plane is the surface plus this, straight up, on a slope as much as on the flat.
func marker_lift(layer: Layer) -> float:
	return _lift_of(LAYERS[layer])


func _apply_marker(spec: Dictionary, node: Node3D, marker: Dictionary) -> void:
	var pos: Vector3 = marker["pos"]
	var texture: Texture2D = marker["texture"]
	var tint: Color = marker.get("modulate", Color.WHITE)
	if spec["kind"] == Kind.BILLBOARD:
		var sprite := node as Sprite3D
		sprite.position = pos + Vector3(0.0, billboard_lift, 0.0)
		sprite.texture = texture
		sprite.modulate = tint
		return
	# Orientation and art scale are ONE write: a basis carries scale, so assigning them separately
	# would have whichever came second wipe the other. Both are set unconditionally because the
	# marker nodes are POOLED — a quad that was on a ramp and is now on flat ground, or that had art
	# and now has none, would otherwise keep the tilt and the size of whatever it drew last.
	var quad := node as MeshInstance3D
	# Which surface this marker LIES on, if it lies on one at all (#427 slice 4 follow-up). Carried
	# ALONGSIDE the basis rather than instead of it: the knockback drop pointer supplies an
	# orientation of its own and STANDS in the world, so `basis` stays "how this is oriented" and
	# `corners` is "the ground it lies flat against" -- absent when there is none, which is flat.
	quad.mesh = _surface_mesh(marker.get("corners", Vector4i.ZERO))
	var tilt: Basis = marker.get("basis", Basis.IDENTITY)
	var art := Vector3.ONE
	if texture != null:
		var size: Vector2 = texture.get_size() / ART_PIXELS_PER_CELL
		art = Vector3(size.x, 1.0, size.y)
	# The layer lift goes straight UP whatever the marker lies on (#432; _lift_of holds the why).
	# Riding the marker's own basis.y instead leaned a ramp's markers downhill out of their cells.
	# A marker that already carries its lift says so with a ZERO lift_dir -- and those two are the
	# only values the key has, now that the direction is no longer a free choice: the knockback drop
	# pointer's ends are the neighbouring arrows' own DRAWN points, so lifting it again would double
	# the clearance and float it off the join it exists to make (#431).
	var lift_dir: Vector3 = marker.get("lift_dir", Vector3.UP)
	quad.transform = Transform3D(tilt * Basis.from_scale(art), pos + lift_dir * _lift_of(spec))
	var material := quad.material_override as StandardMaterial3D
	material.albedo_texture = texture
	material.albedo_color = tint
	# The drop pointer's one render exception, off by default so every flat marker is unchanged:
	# it is double-sided, because it stands in the world rather than lying on a face and free
	# orbit reaches both of its sides (and its consistent band makes the basis left-handed on one
	# travel sign). Reset each time because the markers are pooled. It does NOT skip the depth
	# test: a marker that wins against every surface is an x-ray, visible through the platform
	# the camera panned behind (#431) -- what the pointer needed was to stop being coplanar with
	# a wall, which it now is by position rather than by opting out of depth.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if marker.get("double_sided", false) \
			else BaseMaterial3D.CULL_BACK
	_apply_atlas_uv(material, texture)


# A 3D material samples the WHOLE image behind an AtlasTexture -- a region is a 2D-only notion --
# so a cut from a multi-tile sheet arrives as the entire sheet squeezed into one cell (#316). The
# region is re-expressed as UVs here. The RESET on the plain-texture path is the load-bearing
# half: the marker nodes are pooled, so a quad that drew a cut would keep those UVs over its next
# art. Sprite3D is not affected -- it reads the region itself -- so BILLBOARD needs none of this.
func _apply_atlas_uv(material: StandardMaterial3D, texture: Texture2D) -> void:
	var cut := texture as AtlasTexture
	var sheet := Vector2.ZERO
	if cut != null and cut.atlas != null:
		sheet = cut.atlas.get_size()
	if sheet.x <= 0.0 or sheet.y <= 0.0:
		material.uv1_scale = Vector3.ONE
		material.uv1_offset = Vector3.ZERO
		return
	var region: Rect2 = cut.region
	material.uv1_scale = Vector3(region.size.x / sheet.x, region.size.y / sheet.y, 1.0)
	material.uv1_offset = Vector3(region.position.x / sheet.x, region.position.y / sheet.y, 0.0)


func _make_marker(layer: Layer) -> Node3D:
	var spec: Dictionary = LAYERS[layer]
	match spec["kind"] as Kind:
		Kind.BRACKET:
			# The runtime colour, not the authored one: a bracket built AFTER a set_layer_modulate
			# (the pool grows on demand) would otherwise come back gold on a red layer.
			return _make_bracket(_layer_colors.get(layer, spec["color"]))
		Kind.BILLBOARD:
			return _make_billboard(spec)
		Kind.LINE:
			return _make_line(spec)
		Kind.SPRITE:
			return _make_quad(spec, null, Color.WHITE)
		_:
			return _make_quad(spec, fill_texture, _layer_colors.get(layer, spec["color"]))


# The one fill/sprite recipe: an unshaded alpha quad lying on the cell's top face —
# markup, never terrain (the dev's unshaded ruling; a Decal's albedo modulates the
# lit surface, which is why 4c retired decals).
func _make_quad(spec: Dictionary, texture: Texture2D, color: Color) -> MeshInstance3D:
	if _quad_mesh == null:
		_quad_mesh = PlaneMesh.new()
		_quad_mesh.size = Vector2.ONE * BoardSpace.CELL_SIZE
	var instance := MeshInstance3D.new()
	instance.mesh = _quad_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = texture
	material.albedo_color = color
	material.render_priority = spec["sort"]
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.layers = WORLD_RENDER_LAYER
	add_child(instance)
	return instance


# The sight beam: an ImmediateMesh ribbon, rebuilt by set_line and widened toward the camera by
# sight_beam.gdshader. This WAS a 1-px engine line strip, and the note here said the upgrade would
# be "a camera-facing ribbon built here, with nothing upstream changing" -- #506 is that upgrade,
# and the prediction held: only this function and set_line changed.
#
# extra_cull_margin exists because the mesh's AABB is computed from the CENTRELINE while the shader
# draws outside it. Without the margin a beam whose centreline leaves the frustum pops out while
# its visible width is still on screen. The value is generous next to any sane beam width -- this
# is one small mesh, so there is nothing to save by trimming it.
func _make_line(spec: Dictionary) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = ImmediateMesh.new()
	var material := ShaderMaterial.new()
	material.shader = load(SIGHT_BEAM_SHADER_PATH) as Shader
	material.render_priority = spec["sort"]
	instance.material_override = material
	instance.extra_cull_margin = 1.0
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.layers = WORLD_RENDER_LAYER
	add_child(instance)
	_style_beam(material)
	return instance


func _make_billboard(spec: Dictionary) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.pixel_size = billboard_pixel_size
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.render_priority = spec["sort"]
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.layers = WORLD_RENDER_LAYER
	add_child(sprite)
	return sprite


func _make_bracket(color: Color) -> MeshInstance3D:
	if _bracket_mesh == null:
		_bracket_mesh = _build_bracket_mesh()
	var instance := MeshInstance3D.new()
	instance.mesh = _bracket_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


# How many ROWS of column the selector encloses -- the enum in the units the geometry works in.
func selector_depth_rows() -> int:
	return 1 if selector_depth == SelectorDepth.HALF else Terrain.UNITS_PER_LEVEL


# Half the COLUMN the selector marks -- the volume ITSELF, before bracket_scale swells the drawn box
# around it. The scale belongs to the mesh and not to the placement, exactly as on X and Z where the
# cell's own half is 0.5 * CELL_SIZE and only the mesh multiplies it: fold it in here and the box
# grows downward only, so it sits (scale - 1) * half a row low. Caught by
# test_the_selector_encloses_the_whole_block, which measures the CENTRE for this reason.
func selector_half_height() -> float:
	return 0.5 * float(selector_depth_rows()) * BoardSpace.ROW_HEIGHT


# Turning the knob has to move what is ALREADY on screen -- see the export's own note. Both halves
# are needed and neither implies the other: the box is a different HEIGHT (a new mesh) and it hangs
# from a different POINT (a new transform), and a pool that never repaints would show whichever half
# was forgotten.
func _set_selector_depth(value: SelectorDepth) -> void:
	selector_depth = value
	if _markers.is_empty():
		return   # nothing standing yet -- the mesh builds at the new height on demand
	_bracket_mesh = null
	for layer: Layer in _markers:
		if LAYERS[layer]["kind"] != Kind.BRACKET:
			continue
		if _bracket_mesh == null:
			_bracket_mesh = _build_bracket_mesh()
		var cells: Array = _cells.get(layer, [])
		var pool: Array = _markers[layer]
		for i in pool.size():
			var bracket := pool[i] as MeshInstance3D
			if bracket == null:
				continue
			bracket.mesh = _bracket_mesh
			if i < cells.size():
				var cell: Vector3i = cells[i]
				bracket.transform = _marker_transform(LAYERS[layer], cell, null)


# Three short arms per corner, eight corners: the voxel's corners, nothing else. NOT a cube since
# #427 slice 2 -- X and Z span a CELL, Y spans however many ROWS the selector is set to, because a
# mirror row is half a level and a cube would enclose the wrong volume.
func _build_bracket_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := Vector3(0.5 * BoardSpace.CELL_SIZE, selector_half_height(),
			0.5 * BoardSpace.CELL_SIZE) * bracket_scale
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var corner := Vector3(sx, sy, sz) * half
				_add_arm(st, corner, Vector3(-sx, 0, 0))
				_add_arm(st, corner, Vector3(0, -sy, 0))
				_add_arm(st, corner, Vector3(0, 0, -sz))
	st.commit(mesh)
	return mesh


func _add_arm(st: SurfaceTool, corner: Vector3, inward: Vector3) -> void:
	var arm_end := corner + inward * bracket_arm
	var lo := Vector3(minf(corner.x, arm_end.x), minf(corner.y, arm_end.y), minf(corner.z, arm_end.z))
	var hi := Vector3(maxf(corner.x, arm_end.x), maxf(corner.y, arm_end.y), maxf(corner.z, arm_end.z))
	var pad := Vector3.ONE * (bracket_thickness * 0.5)
	pad -= inward.abs() * (bracket_thickness * 0.5)  # no padding along the arm's own axis
	lo -= pad
	hi += pad
	_add_box(st, lo, hi)


func _add_box(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var corners := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z),
		Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	var faces := [
		[4, 5, 6, 7, Vector3.UP], [3, 2, 1, 0, Vector3.DOWN],
		[7, 6, 2, 3, Vector3.BACK], [5, 4, 0, 1, Vector3.FORWARD],
		[6, 5, 1, 2, Vector3.RIGHT], [4, 7, 3, 0, Vector3.LEFT],
	]
	for face: Array in faces:
		var normal: Vector3 = face[4]
		for index in [0, 1, 2, 0, 2, 3]:
			st.set_normal(normal)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(corners[face[index]])
