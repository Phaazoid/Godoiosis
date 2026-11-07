class_name FrozenInIce
extends Node3D

# Every downed body the ice holds (#1506), drawn frozen INTO it: a ring of glass crystals grown up
# round the body, which UnitSprite3D draws standing, and a faint copy of that body drawn over the ice
# so it reads through. A child of UnitMirror, which reports each such body once a frame (`hold`) and
# then lets this node act (`advance`) -- StatusWorld's shape. A look only: RulesService.held_by_ice
# is the question, and the mirror asks it.
#
# The ring is built once per body off the unit's status seed, so no two are alike and one never
# changes. Ten crystals stand round the body with nothing at the middle, so none crosses the face,
# and five small ones lean out at the foot. A body no longer reported shrinks its ring away on the
# grow clock; one whose sprite has gone is freed at once.

const RING_CRYSTALS := 10
const FOOT_CRYSTALS := 5
const CRYSTAL_SIDES := 6
const GLASS_SHADER := preload("res://Classes/presentation/frozen_in_ice.gdshader")


class Casing:
	var sprite: UnitSprite3D
	var ring: MeshInstance3D
	var body: Sprite3D
	var grown := 0.0
	var held := false   # reported since the last advance


var _casings: Dictionary[int, Casing] = {}
var _glass: ShaderMaterial


func _ready() -> void:
	_glass = ShaderMaterial.new()
	_glass.shader = GLASS_SHADER
	_glass.render_priority = BoardOverlays.EFFECT_RENDER_PRIORITY


# This body is in the ice this frame.
func hold(id: int, sprite: UnitSprite3D, seed: float) -> void:
	var casing: Casing = _casings.get(id)
	if casing == null:
		casing = _build(sprite, seed)
		_casings[id] = casing
	casing.sprite = sprite
	casing.held = true


# `grow_step` is how far a ring grows this frame, on the mirror's scaled clock.
func advance(grow_step: float) -> void:
	_push_glass()
	var lean := Color.WHITE.lerp(ElementPalette.color_for_element(Elemental.Element.ICE),
			StatusLook.in_ice_body_tint)
	for id: int in _casings.keys():
		var casing: Casing = _casings[id]
		if not is_instance_valid(casing.sprite):
			_retire(id)
			continue
		casing.grown = move_toward(casing.grown, 1.0 if casing.held else 0.0, grow_step)
		var leaving := not casing.held
		casing.held = false
		if leaving and casing.grown <= 0.0:
			_retire(id)
			continue
		_place(casing, lean)


func _place(casing: Casing, lean: Color) -> void:
	var sprite := casing.sprite
	var shown := sprite.visible
	var rise := smoothstep(0.0, 1.0, casing.grown)
	var size := StatusLook.in_ice_size
	casing.ring.visible = shown
	casing.ring.position = sprite.position - sprite.art_offset
	casing.ring.scale = Vector3(size * lerpf(0.6, 1.0, rise), maxf(size * rise, 0.001), size * lerpf(0.6, 1.0, rise))
	var body := casing.body
	body.visible = shown and sprite.texture != null
	body.texture = sprite.texture
	body.flip_h = sprite.flip_h
	body.offset = sprite.offset
	body.pixel_size = sprite.pixel_size
	body.position = sprite.position
	body.modulate = Color(sprite.modulate.r * lean.r, sprite.modulate.g * lean.g, sprite.modulate.b * lean.b,
			StatusLook.in_ice_body_alpha * rise)


func _push_glass() -> void:
	_glass.set_shader_parameter("ice_color", ElementPalette.color_for_element(Elemental.Element.ICE))
	_glass.set_shader_parameter("edge_color", StatusLook.in_ice_edge_color)
	_glass.set_shader_parameter("face_alpha", StatusLook.in_ice_face_alpha)
	_glass.set_shader_parameter("edge_alpha", StatusLook.in_ice_edge_alpha)
	_glass.set_shader_parameter("edge_sharpness", StatusLook.in_ice_edge_sharpness)
	_glass.set_shader_parameter("glow", StatusLook.in_ice_glow)


func _build(sprite: UnitSprite3D, seed: float) -> Casing:
	var casing := Casing.new()
	casing.sprite = sprite
	casing.ring = MeshInstance3D.new()
	casing.ring.mesh = crystal_ring(int(seed * 997.0))
	casing.ring.material_override = _glass
	casing.ring.layers = BoardOverlays.WORLD_RENDER_LAYER
	casing.ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(casing.ring)
	# A ghost's settings (UnitMirror.set_ghosts, #317): translucent, so render_priority is what sorts it
	# over the ice.
	casing.body = Sprite3D.new()
	casing.body.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	casing.body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	casing.body.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	casing.body.shaded = true
	casing.body.layers = BoardOverlays.UNIT_RENDER_LAYER
	casing.body.render_priority = BoardOverlays.UNIT_RENDER_PRIORITY
	casing.body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(casing.body)
	return casing


func _retire(id: int) -> void:
	var casing: Casing = _casings[id]
	casing.ring.queue_free()
	casing.body.queue_free()
	_casings.erase(id)


func held_count() -> int:
	return _casings.size()


func ring_for(id: int) -> MeshInstance3D:
	var casing: Casing = _casings.get(id)
	return casing.ring if casing != null else null


func body_for(id: int) -> Sprite3D:
	var casing: Casing = _casings.get(id)
	return casing.body if casing != null else null


# The ring's mesh for one seed, its foot at the origin: hexagonal columns tapering to a point, a
# third of a cell out. Static and pure, so a case can build one with no scene.
static func crystal_ring(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	# [where, height, radius, lean in degrees]: tall and short in turn round the ring, then the foot.
	var specs: Array[Array] = []
	for i in RING_CRYSTALS:
		var a := TAU * float(i) / float(RING_CRYSTALS) + rng.randf_range(-0.2, 0.2)
		var tall := rng.randf_range(0.65, 1.0) if i % 2 == 0 else rng.randf_range(0.35, 0.6)
		specs.append([Vector2(cos(a), sin(a)) * rng.randf_range(0.3, 0.37), tall,
				rng.randf_range(0.1, 0.15), rng.randf_range(6.0, 22.0)])
	for i in FOOT_CRYSTALS:
		var a := TAU * float(i) / float(FOOT_CRYSTALS) + rng.randf_range(0.0, 0.6)
		specs.append([Vector2(cos(a), sin(a)) * 0.43, rng.randf_range(0.18, 0.32),
				rng.randf_range(0.06, 0.09), rng.randf_range(35.0, 55.0)])
	for spec in specs:
		var at: Vector2 = spec[0]
		var away := at.normalized()
		var outward := Vector3(-away.y, 0.0, away.x)   # the axis a crystal leans out about
		var basis := Basis(outward, deg_to_rad(spec[3])) * Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		_crystal(st, Transform3D(basis, Vector3(at.x, -0.05, at.y)), spec[2], spec[1])
	st.generate_normals()
	return st.commit()


static func _crystal(st: SurfaceTool, xf: Transform3D, radius: float, height: float) -> void:
	var low: Array[Vector3] = []
	var high: Array[Vector3] = []
	for k in CRYSTAL_SIDES:
		var a := TAU * float(k) / float(CRYSTAL_SIDES)
		low.append(xf * Vector3(cos(a) * radius, 0.0, sin(a) * radius))
		high.append(xf * Vector3(cos(a) * radius * 0.85, height, sin(a) * radius * 0.85))
	var apex := xf * Vector3(0.0, height * 1.28, 0.0)
	for k in CRYSTAL_SIDES:
		var n := (k + 1) % CRYSTAL_SIDES
		_tri(st, low[k], high[k], high[n])
		_tri(st, low[k], high[n], low[n])
		_tri(st, high[k], apex, high[n])


# Wound so each face points out from its crystal's axis.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)
