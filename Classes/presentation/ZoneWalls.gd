extends Node3D
class_name ZoneWalls

# A zone's WALL (#955): a low wall of light just inside every drawn zone's perimeter, a vertical strip
# per outward cell edge, its kind's colour in the vertices -- built by OverlayMirror from
# ZoneMarks.wall_outline, which steps the tracer the COH line and the enemy focus edge share just
# inside the zone, off the plane a border block's face stands in. Rebuilt only when the zones, the
# heights or a knob move; the shimmer is the shader's own clock.
#
# ONE MESH PER WALL CELL (#1118), every one wearing the one material, so a tear-out can PLACE each
# cell's strips with its ground (place(), a position write) rather than rebuild them: a strip belongs
# to the zone cell it stands inside, and BoardSpace.staged_offset is where that cell's ground is.
# It used to be one mesh for the board, and so hid for the whole of every staged fight.
#
# On the WORLD render layer alone, or the damp blot would darken it (the decal law). The flat view
# has no wall. A wall on a column the battle zoom hides (#1132) stays standing, as that zone's rim
# marks do.

const SHADER := preload("res://Classes/presentation/zone_wall.gdshader")

var strip_count := 0
var _material: ShaderMaterial
var _cells: Dictionary[Vector2i, MeshInstance3D] = {}


func _init() -> void:
	name = "ZoneWalls"
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = BoardOverlays.LAYERS[BoardOverlays.Layer.ZONE_MARKS]["sort"]
	visible = false


# `strips` is {"cell": Vector2i, "from": Vector3, "to": Vector3, "colour": Color, "height": float}
# each, in world space at the ground. The colour's alpha is the strip's strength at its foot and the
# height its own, so a LIT zone (#955 part 3) stands taller and brighter in the same build.
func build(strips: Array[Dictionary], shimmer_speed: float) -> void:
	_material.set_shader_parameter("shimmer_speed", shimmer_speed)
	strip_count = strips.size()
	var by_cell: Dictionary[Vector2i, Array] = {}
	for strip in strips:
		var cell: Vector2i = strip["cell"]
		if not by_cell.has(cell):
			by_cell[cell] = []
		by_cell[cell].append(strip)
	for cell: Vector2i in _cells.keys():
		if not by_cell.has(cell):
			_cells[cell].free()
			_cells.erase(cell)
	for cell: Vector2i in by_cell:
		var piece: MeshInstance3D = _cells.get(cell)
		if piece == null:
			piece = MeshInstance3D.new()
			piece.layers = BoardOverlays.WORLD_RENDER_LAYER
			piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			piece.material_override = _material
			add_child(piece)
			_cells[cell] = piece
		piece.mesh = _mesh_of(by_cell[cell])
	place()


# Each cell's strips sit where its ground is: at rest that is where they were built, during a tear-out
# the cell's staged offset. A position write per cell -- cheap enough for every frame of a flight.
func place() -> void:
	for cell: Vector2i in _cells:
		_cells[cell].position = BoardSpace.staged_offset(cell)


# The cell meshes, for a reader that has to see every strip (the suite).
func pieces() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	out.assign(_cells.values())
	return out


func piece_at(cell: Vector2i) -> MeshInstance3D:
	return _cells.get(cell)


func _mesh_of(strips: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for strip: Dictionary in strips:
		var up := Vector3.UP * float(strip["height"])
		var a: Vector3 = strip["from"]
		var b: Vector3 = strip["to"]
		var colour: Color = strip["colour"]
		_vertex(st, a, colour, Vector2(0, 0))
		_vertex(st, b, colour, Vector2(1, 0))
		_vertex(st, b + up, colour, Vector2(1, 1))
		_vertex(st, a, colour, Vector2(0, 0))
		_vertex(st, b + up, colour, Vector2(1, 1))
		_vertex(st, a + up, colour, Vector2(0, 1))
	return st.commit()


func _vertex(st: SurfaceTool, at: Vector3, colour: Color, uv: Vector2) -> void:
	st.set_color(colour)
	st.set_uv(uv)
	st.add_vertex(at)
