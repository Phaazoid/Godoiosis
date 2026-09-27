extends MeshInstance3D
class_name ZoneWalls

# Look C of the zone experiment (#955): a low wall of light on every drawn zone's perimeter. ONE mesh
# for the whole board -- a vertical strip per outward cell edge, its kind's colour in the vertices --
# built by OverlayMirror from OverlayManager.outline_segments, the tracer the COH line and the enemy
# focus edge already share. Rebuilt only when the zones, the heights or a knob move; the shimmer is
# the shader's own clock.
#
# On the WORLD render layer alone, or the damp blot would darken it (the decal law). It HIDES while a
# tear-out has cells up: its strips stand where the ground rests and cannot follow a flight (declared,
# experiment scope).

const SHADER := preload("res://Classes/presentation/zone_wall.gdshader")

var strip_count := 0


func _init() -> void:
	name = "ZoneWalls"
	layers = BoardOverlays.WORLD_RENDER_LAYER
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = BoardOverlays.LAYERS[BoardOverlays.Layer.ZONE_MARKS]["sort"]
	material_override = material
	visible = false


# `strips` is {"from": Vector3, "to": Vector3, "colour": Color} each, in world space at the ground.
func build(strips: Array[Dictionary], height: float, strength: float, shimmer_speed: float) -> void:
	var material := material_override as ShaderMaterial
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("shimmer_speed", shimmer_speed)
	strip_count = strips.size()
	if strips.is_empty():
		mesh = null
		return
	var up := Vector3.UP * height
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for strip in strips:
		var a: Vector3 = strip["from"]
		var b: Vector3 = strip["to"]
		var colour: Color = strip["colour"]
		_vertex(st, a, colour, Vector2(0, 0))
		_vertex(st, b, colour, Vector2(1, 0))
		_vertex(st, b + up, colour, Vector2(1, 1))
		_vertex(st, a, colour, Vector2(0, 0))
		_vertex(st, b + up, colour, Vector2(1, 1))
		_vertex(st, a + up, colour, Vector2(0, 1))
	mesh = st.commit()


func _vertex(st: SurfaceTool, at: Vector3, colour: Color, uv: Vector2) -> void:
	st.set_color(colour)
	st.set_uv(uv)
	st.add_vertex(at)
