extends Node3D
class_name BoardOverlays

# The 3D presentation stack's board markup (#213 / #176 stage 3): the one owner of
# per-cell overlay layers. FILL layers are pooled Decals projecting straight down,
# so fills conform to ramp slopes structurally (the dev's stage-1 requirement);
# HOVER is a voxel corner-bracket mesh (the dev's stage-2 requirement, "just the
# corners of the specific voxel"). Layer colors deliberately mirror the 2D
# OverlayManager's constants — one declared representation per presentation stack
# (the parallel-stacks doctrine); change a color in both places or say why not.
#
# The mask contract: fill decals paint WORLD_RENDER_LAYER only, and UnitSprite3D
# lives on UNIT_RENDER_LAYER, so a fill never tints a sprite. Both constants live
# HERE; a drift test pins them disjoint.

enum Layer { MOVE, ATTACK, ZONE_CAPTURE, ZONE_EXTRACTION, HOVER }
enum Kind { FILL, BRACKET }

const WORLD_RENDER_LAYER := 1  # bit for layer index 0 — the board and props
const UNIT_RENDER_LAYER := 2   # bit for layer index 1 — UnitSprite3D sets this

const LAYERS: Dictionary[Layer, Dictionary] = {
	Layer.MOVE: {"color": Color(1, 1, 0, 0.5), "sort": 0, "kind": Kind.FILL},
	Layer.ATTACK: {"color": Color(1, 0, 0, 0.5), "sort": 1, "kind": Kind.FILL},
	Layer.ZONE_CAPTURE: {"color": Color(0.3, 0.9, 1, 0.5), "sort": -2, "kind": Kind.FILL},
	Layer.ZONE_EXTRACTION: {"color": Color(0.4, 1, 0.5, 0.5), "sort": -2, "kind": Kind.FILL},
	Layer.HOVER: {"color": Color(1, 0.9, 0.3, 0.9), "sort": 2, "kind": Kind.BRACKET},
}

const FILL_TEXTURE_PATH := "res://Art/LookDev/cell_fill.png"

# Bracket proportions — eye-knobs (the tuning rule); read when the mesh first builds.
@export var bracket_arm := 0.22
@export var bracket_thickness := 0.04
@export var bracket_scale := 1.02

var fill_texture: Texture2D

var _markers: Dictionary[Layer, Array] = {}
var _cells: Dictionary[Layer, Array] = {}
var _bracket_mesh: ArrayMesh


func _ready() -> void:
	if fill_texture == null:
		fill_texture = load(FILL_TEXTURE_PATH) as Texture2D


# Replaces the layer's cells wholesale (idempotent — calling twice with the same
# set changes nothing; extras from a previous, larger set are hidden, not leaked).
func set_cells(layer: Layer, cells: Array[Vector3i]) -> void:
	_cells[layer] = cells.duplicate()
	if not _markers.has(layer):
		_markers[layer] = []
	var pool: Array = _markers[layer]
	while pool.size() < cells.size():
		pool.append(_make_marker(layer))
	var spec: Dictionary = LAYERS[layer]
	for i in pool.size():
		var marker := pool[i] as Node3D
		if i < cells.size():
			marker.visible = true
			marker.position = _marker_position(spec, cells[i])
		else:
			marker.visible = false


func clear(layer: Layer) -> void:
	set_cells(layer, [])


func clear_all() -> void:
	for layer: Layer in LAYERS.keys():
		clear(layer)


func cells_of(layer: Layer) -> Array[Vector3i]:
	var current: Array[Vector3i] = []
	current.assign(_cells.get(layer, []))
	return current


func marker_count(layer: Layer) -> int:
	var pool: Array = _markers.get(layer, [])
	var visible_count := 0
	for marker: Node3D in pool:
		if marker.visible:
			visible_count += 1
	return visible_count


# --- Marker construction -----------------------------------------------------------

func _marker_position(spec: Dictionary, cell: Vector3i) -> Vector3:
	if spec["kind"] == Kind.BRACKET:
		return BoardSpace.cell_center(cell)
	# The decal box straddles the cell's top: tall enough to catch a full ramp slope,
	# normal-faded so it barely touches vertical walls.
	return BoardSpace.cell_center(cell) + Vector3(0.0, 0.4 * BoardSpace.CELL_SIZE, 0.0)


func _make_marker(layer: Layer) -> Node3D:
	var spec: Dictionary = LAYERS[layer]
	if spec["kind"] == Kind.BRACKET:
		return _make_bracket(spec)
	return _make_fill(spec)


func _make_fill(spec: Dictionary) -> Decal:
	var decal := Decal.new()
	decal.texture_albedo = fill_texture
	decal.modulate = spec["color"]
	decal.size = Vector3(1.0, 2.0, 1.0) * BoardSpace.CELL_SIZE
	decal.cull_mask = WORLD_RENDER_LAYER
	decal.sorting_offset = spec["sort"]
	decal.normal_fade = 0.3
	add_child(decal)
	return decal


func _make_bracket(spec: Dictionary) -> MeshInstance3D:
	if _bracket_mesh == null:
		_bracket_mesh = _build_bracket_mesh()
	var instance := MeshInstance3D.new()
	instance.mesh = _bracket_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = spec["color"]
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
