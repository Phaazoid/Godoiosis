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
	ZONE_PATROL, ZONE_HIGHLIGHT, GROUND_ICONS,
}
enum Kind { FILL, BRACKET, SPRITE, BILLBOARD }

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
	# The zone BAND sits at -3, with the picked-zone highlight alone at -2 above it. In 2D
	# the highlight wins by TREE ORDER (appended last); 3D has no such thing, so the sort
	# number IS the relationship and a test pins it rather than the values (#231). -1 was
	# unavailable: SQUAD/SQUAD_RANGE live there and would share the lift, i.e. z-fight.
	Layer.ZONE_CAPTURE: {"color": Color(0.3, 0.9, 1, 0.5), "sort": -3, "kind": Kind.FILL},
	Layer.ZONE_EXTRACTION: {"color": Color(0.4, 1, 0.5, 0.5), "sort": -3, "kind": Kind.FILL},
	Layer.ZONE_PATROL: {"color": OverlayManager.ZONE_PATROL_MODULATE, "sort": -3, "kind": Kind.FILL},
	Layer.ZONE_HIGHLIGHT: {"color": OverlayManager.ZONE_HIGHLIGHT_MODULATE, "sort": -2, "kind": Kind.FILL},
	Layer.HOVER: {"color": Color(1, 0.9, 0.3, 0.9), "sort": 2, "kind": Kind.BRACKET},
	Layer.INVALID_MOVE: {"color": Color(0.5, 0.36, 0.4, 0.5), "sort": 0, "kind": Kind.FILL},
	Layer.SQUAD: {"color": Color(1, 0.5, 0, 0.5), "sort": -1, "kind": Kind.FILL},
	Layer.SQUAD_RANGE: {"color": Color(1, 0.5, 0, 0.5), "sort": -1, "kind": Kind.FILL},
	Layer.AIM: {"color": Color(1, 1, 0, 1), "sort": 4, "kind": Kind.FILL},
	Layer.TARGET_PICK: {"color": Color.WHITE, "sort": 5, "kind": Kind.SPRITE},
	Layer.PATH_ARROWS: {"color": Color.WHITE, "sort": 6, "kind": Kind.SPRITE},
	Layer.KNOCKBACK: {"color": Color.WHITE, "sort": 6, "kind": Kind.SPRITE},
	# The ground form of the selection icons (#325 experiment): membership rings + the leader's
	# crown decal lying on the cell surface. Above terrain state, below the aim pulse, pick
	# markers and arrows (a ring must never eat an arrowhead) -- AIM/TARGET_PICK/arrows each
	# moved up one to open this slot. Colour stays WHITE: the tint is per-entry (the squad hue,
	# copied off the 2D sprite), which is also why this layer can never take a GameKnobs colour row.
	Layer.GROUND_ICONS: {"color": Color.WHITE, "sort": 3, "kind": Kind.SPRITE},
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
# The 2D art's metric: a 16px texture covers exactly one board cell.
const ART_PIXELS_PER_CELL := 16.0

# Eye-knobs (the tuning rule); read when markers build/place.
@export var bracket_arm := 0.22
@export var bracket_thickness := 0.04
@export var bracket_scale := 1.02
@export var fill_lift := 0.02          # quad height above the top face — the z-fight gap
@export var lift_step := 0.004         # per-sort spacing so stacked layers never coincide
@export var billboard_lift := 0.85     # icon height above the cell's top face
@export var billboard_pixel_size := 1.0 / 32.0
# What the hover bracket turns when the pointer is over something the 2D calls INVALID (#245).
# A knob because there is nothing to mirror here: 2D says "invalid" with a negative-icon TEXTURE,
# and a bracket has no texture to swap, so the colour is a fresh aesthetic call.
@export var invalid_bracket_color := Color(1.0, 0.3, 0.3, 0.9)

var fill_texture: Texture2D

var _markers: Dictionary[Layer, Array] = {}       # layer -> node pool (all kinds)
var _cells: Dictionary[Layer, Array] = {}         # set_cells layers: the current cell list
var _marker_data: Dictionary[Layer, Array] = {}   # set_markers layers: the current entries
var _layer_colors: Dictionary[Layer, Color] = {}  # runtime fill colors (set_layer_modulate)
var _bracket_mesh: ArrayMesh
var _quad_mesh: PlaneMesh


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
		else:
			marker.visible = false


# Replaces a variant layer wholesale: one entry per marker, {"pos": Vector3 (the
# cell's top-face anchor), "texture": Texture2D, "modulate": Color, "basis": Basis
# (optional — how the surface under it is tilted, identity on flat ground)}. Same
# idempotent-pool contract as set_cells. SPRITE/BILLBOARD layers only.
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


func clear(layer: Layer) -> void:
	var spec: Dictionary = LAYERS[layer]
	if spec["kind"] == Kind.SPRITE or spec["kind"] == Kind.BILLBOARD:
		set_markers(layer, [])
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


# A BRACKET marks a cell VOLUME, so it keeps the centre and stays axis-aligned; a FILL is ground
# markup and rides the surface, tilt included (#281). The clearance is applied along the surface's
# OWN normal, so stacked coplanar layers stay parallel to what they sit on rather than shearing
# apart on a slope.
func _marker_transform(spec: Dictionary, cell: Vector3i, heights: BoardHeights) -> Transform3D:
	if spec["kind"] == Kind.BRACKET:
		return Transform3D(Basis.IDENTITY, BoardSpace.cell_center(cell))
	var rise := Terrain.RampRise.NONE if heights == null else heights.ramp_rise_at(BoardSpace.flat(cell))
	var surface := BoardSpace.lie_on(cell, rise)
	return Transform3D(surface.basis, surface.origin + surface.basis.y * _lift_of(spec))


# Per-sort spacing keeps coplanar stacked fills apart; render_priority (set at
# construction) keeps the alpha blend order stable regardless.
func _lift_of(spec: Dictionary) -> float:
	return fill_lift + spec["sort"] * lift_step


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
	var tilt: Basis = marker.get("basis", Basis.IDENTITY)
	var art := Vector3.ONE
	if texture != null:
		var size: Vector2 = texture.get_size() / ART_PIXELS_PER_CELL
		art = Vector3(size.x, 1.0, size.y)
	quad.transform = Transform3D(tilt * Basis.from_scale(art), pos + tilt.y * _lift_of(spec))
	var material := quad.material_override as StandardMaterial3D
	material.albedo_texture = texture
	material.albedo_color = tint
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


# Three short arms per cube corner, eight corners: the voxel's corners, nothing else.
func _build_bracket_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 0.5 * BoardSpace.CELL_SIZE * bracket_scale
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
