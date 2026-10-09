extends Node3D
class_name StormBolts

# The thunderstorm's bolts (#1260): struck in the sky and BEYOND THE BOARD'S EDGE, never onto a cell
# (dev, 2026-10-08) -- a bolt landing on a tile would read as an attack in a game where shock is a
# rule. Drawn the way a shock's bolt is (#887): one ImmediateMesh pair, a narrow core and a wide
# corona, through BoardOverlays.add_beam_strip and ArcLightning's own look, so there is one answer to
# what lightning looks like and the weather only says how far off and how big.
#
# plan_strike and keep_outside are pure and static: a headless case asserts no point of any bolt is
# ever over the board, over many seeds.

const CULL_MARGIN := 4.0
# A bolt stays at least this far outside the board rect, in cells, wherever its kinks wander.
const CLEARANCE := 1.0

class Bolt:
	var path: PackedVector3Array
	var key := 0
	var born := 0.0
	var life := 0.5
	var width_scale := 1.0
	var rect := Rect2i()

var _core: MeshInstance3D
var _corona: MeshInstance3D
var _bolts: Array[Bolt] = []
var _elapsed := 0.0
var bolts_drawn := 0


func _ready() -> void:
	_core = BoardOverlays.make_ribbon(self, CULL_MARGIN)
	_corona = BoardOverlays.make_ribbon(self, CULL_MARGIN)


# Where the strike numbered `key` lands, for a board over `rect` (cells): a bearing out from the
# board's centre, `distance` cells past its corner radius, from `height` above `top_y` down to
# `bottom_y`. Returns {"path": the jagged line, "bearing": the unit direction out to it}.
static func plan_strike(rect: Rect2i, key: int, distance: float, height: float, top_y: float,
		bottom_y: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([key, "storm-strike"])
	var angle := rng.randf() * TAU
	var bearing := Vector3(cos(angle), 0.0, sin(angle))
	var centre := Vector3(rect.position.x + rect.size.x * 0.5, 0.0, rect.position.y + rect.size.y * 0.5) \
			* BoardSpace.CELL_SIZE
	var reach := Vector2(rect.size).length() * 0.5 * BoardSpace.CELL_SIZE + distance
	var ground := centre + bearing * reach
	var straight := PackedVector3Array([
		Vector3(ground.x, top_y + height, ground.z),
		Vector3(ground.x, bottom_y, ground.z)])
	var line := ArcLightning.jagged(straight, key, ArcLightning.bolt_segments * 2, ArcLightning.bolt_jag * 0.5)
	return {"path": keep_outside(line, rect), "bearing": bearing}


# Every point pushed back out past the board rect (+CLEARANCE) along the line from the board's centre,
# so a kink that wanders inward stops at the edge rather than crossing onto a cell.
static func keep_outside(line: PackedVector3Array, rect: Rect2i) -> PackedVector3Array:
	var lo := Vector2(rect.position) * BoardSpace.CELL_SIZE - Vector2.ONE * CLEARANCE
	var hi := Vector2(rect.end) * BoardSpace.CELL_SIZE + Vector2.ONE * CLEARANCE
	var centre := (lo + hi) * 0.5
	var out := PackedVector3Array()
	for point in line:
		var at := Vector2(point.x, point.z)
		if at.x > lo.x and at.x < hi.x and at.y > lo.y and at.y < hi.y:
			var away := at - centre
			if away.length_squared() < 0.0001:
				away = Vector2.RIGHT
			# Scale out until the point sits on the clearance box's boundary.
			var reach := INF
			if absf(away.x) > 0.0001:
				reach = minf(reach, (hi.x - centre.x) / absf(away.x))
			if absf(away.y) > 0.0001:
				reach = minf(reach, (hi.y - centre.y) / absf(away.y))
			at = centre + away * reach
		out.append(Vector3(at.x, point.y, at.y))
	return out


func strike(path: PackedVector3Array, rect: Rect2i, key: int, life: float, width_scale: float) -> void:
	var bolt := Bolt.new()
	bolt.rect = rect
	bolt.path = path
	bolt.key = key
	bolt.born = _elapsed
	bolt.life = maxf(life, 0.01)
	bolt.width_scale = width_scale
	_bolts.append(bolt)


func clear() -> void:
	_bolts.clear()
	_rebuild()


func _process(delta: float) -> void:
	if _bolts.is_empty() and bolts_drawn == 0:
		return
	_elapsed += delta
	var live: Array[Bolt] = []
	for bolt in _bolts:
		if _elapsed - bolt.born < bolt.life:
			live.append(bolt)
	_bolts = live
	_rebuild()


# ArcLightning's _rebuild for a sky bolt: the same envelope, the same re-roll (frozen under #217's
# setting), the same core/corona styling -- scaled up, because the bolt is far off.
func _rebuild() -> void:
	var core := _core.mesh as ImmediateMesh
	var corona := _corona.mesh as ImmediateMesh
	core.clear_surfaces()
	corona.clear_surfaces()
	var frozen: bool = PlayerSettings.is_on(PlayerSettings.Setting.PHOTOSENSITIVITY)
	var scale := 1.0
	for bolt in _bolts:
		var age := _elapsed - bolt.born
		var alpha := ArcLightning.envelope(age / bolt.life, ArcLightning.afterimage)
		if alpha <= 0.002:
			continue
		var key := bolt.key if frozen or ArcLightning.flicker_rate <= 0.0 \
				else hash([bolt.key, int(age * ArcLightning.flicker_rate)])
		var line := keep_outside(ArcLightning.jagged(bolt.path, key, bolt.path.size() - 1,
				ArcLightning.bolt_jag * 0.15), bolt.rect)
		var tint := Color(1.0, 1.0, 1.0, alpha)
		if BoardOverlays.add_beam_strip(core, line, tint):
			BoardOverlays.add_beam_strip(corona, line, tint)
		scale = bolt.width_scale
	bolts_drawn = core.get_surface_count()
	_core.visible = bolts_drawn > 0
	_corona.visible = bolts_drawn > 0
	var width := ArcLightning.bolt_width * scale
	_shade(_core, ArcLightning.core_color, width, ArcLightning.core_intensity)
	_shade(_corona, ElementPalette.color_for_element(Elemental.Element.SHOCK),
			width * ArcLightning.corona_scale, ArcLightning.corona_intensity)


func _shade(node: MeshInstance3D, color: Color, width: float, intensity: float) -> void:
	var material := node.material_override as ShaderMaterial
	material.set_shader_parameter("beam_color", color)
	material.set_shader_parameter("beam_width", width)
	material.set_shader_parameter("beam_intensity", intensity)
	material.set_shader_parameter("beam_softness", ArcLightning.bolt_softness)
