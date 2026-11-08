extends Node3D
class_name VeinMirror

# The 3D drawing of the vein store (#696): low crystals strung along each vein, one HABIT per element in
# its colour, a cell's middle kept clear for whoever stands there, and a soft stain on the ground under
# the vein. The dev's pick of the round-5 mocks ("Field", 2026-11-07). Owned by battle3d beside
# GasMirror; reads VeinField, BoardHeights and VeinLook, and writes nothing back.
#
# Polls rather than listens, GasMirror's shape: the vein, height and grid versions, the staging and the
# basin, and VeinLook.key(). A rebuild redraws every vein on the board, a few hundred crystals.
#
# A crystal's place is SEEDED by its cell, so a rebuild never reshuffles a vein. Each habit is ONE mesh,
# built flat-shaded on the CPU so every crystal's facets light true whatever its proportions: one draw
# per habit, not a node per crystal. Every mesh is on WORLD_RENDER_LAYER.
#
# The STAIN is one Decal masked to GROUND_RENDER_LAYER (WeatherMirror's precedent), so it paints the
# ground and nothing that stands on it, and follows a slope where a flat plane could not. Its texture is
# REASSIGNED, never update()d, and redrawn at most every STAIN_SETTLE seconds, so a painting drag stays
# smooth.

# Every habit, in the order they are built. Alkahest is no habit: its crystals take one of the five
# sigil habits each (ALKAHEST_MIX), each in that element's colour.
const HABITS: Array[Vein.Kind] = [Vein.Kind.FIRE, Vein.Kind.WATER, Vein.Kind.EARTH, Vein.Kind.AIR,
	Vein.Kind.AETHER, Vein.Kind.LIGHTNING]
const ALKAHEST_MIX: Array[Vein.Kind] = [Vein.Kind.FIRE, Vein.Kind.EARTH, Vein.Kind.AIR, Vein.Kind.WATER,
	Vein.Kind.AETHER]
# North, east, south, west: the order a cell looks for its own vein's neighbours, which the seed leans on.
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const CENTRE := Vector2(0.5, 0.5)
const EDGE := 0.04           # how near a crystal may stand to the cell's own edge
const TRIES_PER_CRYSTAL := 9

# Per habit: roughness, metallic, alpha, glow (times VeinLook.vein_glow). The mock's values.
const SURFACE: Dictionary[Vein.Kind, Array] = {
	Vein.Kind.FIRE: [0.35, 0.0, 1.0, 0.55],
	Vein.Kind.WATER: [0.08, 0.15, 0.82, 0.35],
	Vein.Kind.EARTH: [0.85, 0.0, 1.0, 0.12],
	Vein.Kind.AIR: [0.2, 0.55, 1.0, 0.25],
	Vein.Kind.AETHER: [0.25, 0.0, 1.0, 0.45],
	Vein.Kind.LIGHTNING: [0.1, 0.6, 1.0, 0.5],
}

const STAIN_TEXELS := 16     # per cell
const STAIN_INSET := 0.12    # how far inside its cell a vein's stain is at full strength
const STAIN_SETTLE := 0.2    # the least time between two stain redraws

var field: VeinField
var heights: BoardHeights
var grid: TileMapLayer
var stands_down: Callable

var _meshes: Dictionary[Vein.Kind, MeshInstance3D] = {}
var _decal: Decal
var _tools: Dictionary[Vein.Kind, SurfaceTool] = {}
var _counts: Dictionary[Vein.Kind, int] = {}
var _seen := []
var _stain_seen := []
var _stain_pending := false
var _stain_wait := 0.0


func _ready() -> void:
	for habit: Vein.Kind in HABITS:
		var mesh := MeshInstance3D.new()
		mesh.name = Vein.display_name(habit)
		mesh.layers = BoardOverlays.WORLD_RENDER_LAYER
		mesh.material_override = StandardMaterial3D.new()
		add_child(mesh)
		_meshes[habit] = mesh
	_decal = Decal.new()
	_decal.name = "Stain"
	_decal.cull_mask = BoardOverlays.GROUND_RENDER_LAYER
	_decal.upper_fade = 0.0
	_decal.lower_fade = 0.0
	_decal.visible = false
	add_child(_decal)


func _process(delta: float) -> void:
	var down: bool = stands_down.is_valid() and stands_down.call()
	visible = not down
	if down or field == null:
		return
	var look := VeinLook.key()
	var key := [field.dirty.version, heights.dirty.version if heights != null else 0,
		(grid as BoardGrid).dirty.version if grid is BoardGrid else 0, BoardSpace.staging_version,
		BoardSpace.basin_version, look]
	if key != _seen:
		_seen = key
		rebuild()
	_stain_wait = maxf(0.0, _stain_wait - delta)
	var stain_key := [field.dirty.version, look]
	if stain_key != _stain_seen:
		_stain_seen = stain_key
		_stain_pending = true
	if _stain_pending and _stain_wait <= 0.0:
		redraw_stain()


# Every crystal on the board, from the store as it stands, and the stain's box under them.
func rebuild() -> void:
	_counts.clear()
	for habit: Vein.Kind in HABITS:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[habit] = tool
	for cell: Vector2i in field.cells():
		_grow(cell)
	for habit: Vein.Kind in HABITS:
		var mesh := _meshes[habit]
		mesh.mesh = _tools[habit].commit() if _counts.get(habit, 0) > 0 else null
		_style(mesh.material_override as StandardMaterial3D, habit)
	_tools.clear()
	_fit_decal()


# How many crystals stand on the board, by habit and in all: what a test asks.
func crystal_count(habit: Vein.Kind = Vein.Kind.NONE) -> int:
	if habit != Vein.Kind.NONE:
		return _counts.get(habit, 0)
	var total := 0
	for count: int in _counts.values():
		total += count
	return total


func mesh_of(habit: Vein.Kind) -> MeshInstance3D:
	return _meshes.get(habit)


func stain_node() -> Decal:
	return _decal


# ---- placement -----------------------------------------------------------------------------------

# Low crystals scattered along the vein's spine through this cell -- a spoke toward each neighbour of
# the same vein, three short ones on a lone cell -- never inside the clear middle.
func _grow(cell: Vector2i) -> void:
	var kind := field.kind_at(cell)
	var r := RandomNumberGenerator.new()
	r.seed = hash("f%s" % cell)
	var spokes: Array[Vector2] = []
	for d: Vector2i in DIRS:
		if field.kind_at(cell + d) == kind:
			spokes.append(CENTRE + Vector2(d) * 0.5)
	if spokes.is_empty():
		for k in 3:
			spokes.append(CENTRE + Vector2.from_angle(TAU * k / 3.0 + _h("sp%s" % cell)) * 0.4)
	var placed := 0
	var tries := 0
	while placed < VeinLook.vein_density and tries < VeinLook.vein_density * TRIES_PER_CRYSTAL:
		tries += 1
		var spoke := spokes[r.randi() % spokes.size()]
		var t := r.randf_range(0.0, 1.0)
		var p := CENTRE.lerp(spoke, t) + Vector2(r.randf_range(-0.16, 0.16), r.randf_range(-0.16, 0.16))
		if p.distance_to(CENTRE) < VeinLook.vein_clear or p.x < EDGE or p.y < EDGE \
				or p.x > 1.0 - EDGE or p.y > 1.0 - EDGE:
			continue
		var habit: Vein.Kind = ALKAHEST_MIX[r.randi() % ALKAHEST_MIX.size()] if kind == Vein.Kind.ALKAHEST else kind
		_crystal(habit, cell, p, r.randf_range(0.35, 0.65) * VeinLook.vein_size, r, p - CENTRE)
		placed += 1


# One crystal of this habit at a point inside the cell (0..1 across it), `s` its scale, leaning
# away from the cell's middle.
func _crystal(habit: Vein.Kind, cell: Vector2i, local: Vector2, s: float, r: RandomNumberGenerator,
		lean: Vector2) -> void:
	if not _tools.has(habit):
		return
	var out := lean.normalized() if lean.length() > 0.001 else Vector2.from_angle(r.randf() * TAU)
	_counts[habit] = _counts.get(habit, 0) + 1
	var tool := _tools[habit]
	match habit:
		Vein.Kind.FIRE:
			# flame shards: tall four-sided points splaying outward
			var hgt := r.randf_range(0.22, 0.42) * s
			var rad := r.randf_range(0.035, 0.055) * s
			var tilt := r.randf_range(0.12, 0.42)
			_frustum(tool, _place(_at(cell, local, hgt * 0.42), out, tilt, r.randf() * TAU), 0.003, rad, hgt, 4)
		Vein.Kind.WATER:
			# glassy hexagonal columns with a short point on top
			var hgt := r.randf_range(0.14, 0.28) * s
			var rad := r.randf_range(0.032, 0.048) * s
			var tilt := r.randf_range(0.0, 0.28)
			var xf := _place(_at(cell, local, hgt * 0.45), out, tilt, r.randf() * TAU)
			_frustum(tool, xf, rad, rad, hgt, 6)
			_frustum(tool, xf * Transform3D(Basis(), Vector3(0.0, hgt * 0.5 + rad * 0.7, 0.0)), 0.002, rad,
					rad * 1.4, 6)
		Vein.Kind.EARTH:
			# rusty cubes, half sunk, sometimes stepped
			var size := r.randf_range(0.07, 0.13) * s
			_box(tool, _place(_at(cell, local, size * 0.32), out, r.randf_range(0.0, 0.3), r.randf() * TAU), size)
			if r.randf() < 0.45:
				_box(tool, _place(_at(cell, local + out * size * 0.4, size * 0.75), out, r.randf_range(0.1, 0.5),
						r.randf() * TAU), size * 0.55)
		Vein.Kind.AIR:
			# a spray of silver needles fanning up from one root
			var needles := 5 + r.randi() % 4
			for k in needles:
				var hgt := r.randf_range(0.16, 0.34) * s
				var dir := Vector2.from_angle(r.randf() * TAU)
				var tilt := r.randf_range(0.25, 0.85)
				var at := _at(cell, local + dir * hgt * sin(tilt) * 0.45, hgt * 0.45 * cos(tilt))
				_frustum(tool, _place(at, dir, tilt, r.randf() * TAU), 0.001, 0.009 * s + 0.003, hgt, 4)
		Vein.Kind.AETHER:
			# a double-pointed gem hovering over the ground
			var hgt := r.randf_range(0.14, 0.24) * s
			var lift := r.randf_range(0.12, 0.22) * maxf(s, 0.5)
			_bipyramid(tool, _place(_at(cell, local, lift + hgt * 0.5), out, r.randf_range(0.0, 0.25),
					r.randf() * TAU), hgt * 0.32, hgt, 4)
		Vein.Kind.LIGHTNING:
			# yellow diamonds set into the ground: a faceted crown above, the pointed pavilion sunk
			var rad := r.randf_range(0.05, 0.08) * s
			var tilt := r.randf_range(0.15, 0.7)
			var xf := _place(_at(cell, local, rad * 0.2), out, tilt, r.randf() * TAU)
			_frustum(tool, xf, rad * 0.55, rad, rad * 0.55, 8)
			_frustum(tool, xf * Transform3D(Basis(), Vector3(0.0, -rad * 1.025, 0.0)), rad, 0.002, rad * 1.5, 8)


# A point inside the cell (0..1 across it) on the ground as drawn, `lift` above it.
func _at(cell: Vector2i, local: Vector2, lift: float) -> Vector3:
	var x := (float(cell.x) + local.x) * BoardSpace.CELL_SIZE
	var z := (float(cell.y) + local.y) * BoardSpace.CELL_SIZE
	var y := BoardSpace.surface_height_at(cell, x, z, heights)
	return Vector3(x, y + lift, z) + BoardSpace.drawn_offset(cell)


# Spun about its own axis, then tipped `tilt` radians away along `out`.
func _place(at: Vector3, out: Vector2, tilt: float, spin: float) -> Transform3D:
	var basis := Basis(Vector3.UP, spin)
	var axis := Vector3(out.y, 0.0, -out.x)
	if axis.length() > 0.001 and tilt != 0.0:
		basis = Basis(axis.normalized(), tilt) * basis
	return Transform3D(basis, at)


# ---- shapes: flat-shaded, built in place ---------------------------------------------------------

# A ring-sided prism from `bottom` radius to `top`, centred on its own middle, CylinderMesh's frame.
func _frustum(tool: SurfaceTool, xf: Transform3D, top: float, bottom: float, height: float, sides: int) -> void:
	var low: Array[Vector3] = []
	var high: Array[Vector3] = []
	for k in sides:
		var angle := TAU * k / sides
		var across := Vector3(sin(angle), 0.0, cos(angle))
		low.append(across * bottom - Vector3(0.0, height * 0.5, 0.0))
		high.append(across * top + Vector3(0.0, height * 0.5, 0.0))
	for k in sides:
		var n := (k + 1) % sides
		_tri(tool, xf, low[k], low[n], high[n])
		_tri(tool, xf, low[k], high[n], high[k])
	var foot := Vector3(0.0, -height * 0.5, 0.0)
	var head := Vector3(0.0, height * 0.5, 0.0)
	for k in sides:
		var n := (k + 1) % sides
		_tri(tool, xf, foot, low[n], low[k])
		_tri(tool, xf, head, high[k], high[n])


func _box(tool: SurfaceTool, xf: Transform3D, size: float) -> void:
	var h := size * 0.5
	var c: Array[Vector3] = []
	for i in 8:
		c.append(Vector3(h if i & 1 else -h, h if i & 2 else -h, h if i & 4 else -h))
	for face: Array in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		_tri(tool, xf, c[face[0]], c[face[1]], c[face[2]])
		_tri(tool, xf, c[face[0]], c[face[2]], c[face[3]])


# Two pyramids base to base: SphereMesh at four sides and two rings, which is what the mock drew.
func _bipyramid(tool: SurfaceTool, xf: Transform3D, radius: float, height: float, sides: int) -> void:
	var top := Vector3(0.0, height * 0.5, 0.0)
	var bottom := -top
	for k in sides:
		var a := TAU * k / sides
		var b := TAU * (k + 1) / sides
		var p := Vector3(sin(a), 0.0, cos(a)) * radius
		var q := Vector3(sin(b), 0.0, cos(b)) * radius
		_tri(tool, xf, top, p, q)
		_tri(tool, xf, bottom, q, p)


# One face, wound to face away from the shape's own middle (each shape is convex about its origin)
# whatever order it was handed, with its own normal: a flat facet.
func _tri(tool: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3) -> void:
	var facing := (b - a).cross(c - a)
	if facing.length_squared() < 1e-14:
		return   # a point collapsed to nothing: a cone's tip
	if facing.dot(a + b + c) > 0.0:   # anticlockwise seen from outside; Godot's front face is clockwise
		var swap := b
		b = c
		c = swap
		facing = -facing
	var normal := xf.basis * (-facing).normalized()
	tool.set_normal(normal)
	tool.add_vertex(xf * a)
	tool.set_normal(normal)
	tool.add_vertex(xf * b)
	tool.set_normal(normal)
	tool.add_vertex(xf * c)


func _style(material: StandardMaterial3D, habit: Vein.Kind) -> void:
	var colour := VeinLook.color_of(habit)
	var surface: Array = SURFACE[habit]
	material.albedo_color = Color(colour, surface[2])
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if surface[2] < 1.0 \
			else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.roughness = surface[0]
	material.metallic = surface[1]
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = surface[3] * VeinLook.vein_glow


# ---- the stain -----------------------------------------------------------------------------------

# The cells the stain covers: every vein's, one cell of margin round them.
func _stain_rect() -> Rect2i:
	var cells := field.cells()
	if cells.is_empty():
		return Rect2i()
	var rect := Rect2i(cells[0], Vector2i.ONE)
	for cell: Vector2i in cells:
		rect = rect.merge(Rect2i(cell, Vector2i.ONE))
	return rect.grow(1)


# The decal's box: the stain's cells, deep enough to reach every surface drawn under them.
func _fit_decal() -> void:
	var rect := _stain_rect()
	if not rect.has_area():
		_decal.visible = false
		return
	var low := INF
	var high := -INF
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var c := heights.corners_at(cell) if heights != null else Vector4i.ZERO
			var drawn := BoardSpace.drawn_offset(cell).y
			low = minf(low, BoardSpace.world_y_of_height(Terrain.low_of_corners(c)) + drawn)
			high = maxf(high, BoardSpace.world_y_of_height(maxi(maxi(c.x, c.y), maxi(c.z, c.w))) + drawn)
	var size := Vector2(rect.size) * BoardSpace.CELL_SIZE
	_decal.size = Vector3(size.x, high - low + 1.0, size.y)
	_decal.position = Vector3(rect.position.x * BoardSpace.CELL_SIZE + size.x * 0.5, (low + high) * 0.5,
			rect.position.y * BoardSpace.CELL_SIZE + size.y * 0.5)
	_decal.normal_fade = VeinLook.vein_stain_slope
	_decal.visible = _decal.texture_albedo != null


# The ground under each vein darkened toward its colour, ragged at the rim and continuous across an
# edge two cells of one vein share. Only cells within one of a vein are walked: the stain reaches no
# further.
func redraw_stain() -> void:
	_stain_pending = false
	_stain_wait = STAIN_SETTLE
	var rect := _stain_rect()
	if not rect.has_area():
		_decal.texture_albedo = null
		_decal.visible = false
		return
	var image := Image.create(rect.size.x * STAIN_TEXELS, rect.size.y * STAIN_TEXELS, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var near: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in field.cells():
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				near[cell + Vector2i(dx, dy)] = true
	var reach := maxf(VeinLook.vein_stain_reach, 0.001)
	var ragged := _noise()
	for cell: Vector2i in near:
		var veins: Array[Vector2i] = []
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if field.kind_at(cell + Vector2i(dx, dy)) != Vein.Kind.NONE:
					veins.append(cell + Vector2i(dx, dy))
		var origin := (cell - rect.position) * STAIN_TEXELS
		for ty in STAIN_TEXELS:
			for tx in STAIN_TEXELS:
				var p := Vector2(cell) + Vector2(tx + 0.5, ty + 0.5) / STAIN_TEXELS
				var nearest := INF
				for vein: Vector2i in veins:
					nearest = minf(nearest, _to_heart(p, vein))
				if nearest > reach + NOISE_REACH:
					continue   # no ragged edge reaches this far: skip the noise
				var noise: float = ragged[0].get_noise_2dv(p) * 0.22 + ragged[1].get_noise_2dv(p) * 0.07
				var best := 0.0
				var colour := Color.TRANSPARENT
				for vein: Vector2i in veins:
					var strength := clampf(1.0 - (_to_heart(p, vein) + noise) / reach, 0.0, 1.0)
					if strength > best:
						best = strength
						colour = VeinLook.color_of(field.kind_at(vein)).darkened(VeinLook.vein_stain_dark)
				if best > 0.0:
					image.set_pixel(origin.x + tx, origin.y + ty, Color(colour, best * VeinLook.vein_stain))
	_decal.texture_albedo = ImageTexture.create_from_image(image)
	_fit_decal()


# How far a point (in cells) lies from a vein's heart, the square STAIN_INSET inside its cell.
static func _to_heart(p: Vector2, vein: Vector2i) -> float:
	var lo := Vector2(vein) + Vector2(STAIN_INSET, STAIN_INSET)
	var hi := Vector2(vein) + Vector2(1.0 - STAIN_INSET, 1.0 - STAIN_INSET)
	return (p - p.clamp(lo, hi)).length()


# ---- noise ---------------------------------------------------------------------------------------

const NOISE_REACH := 0.29   # the most the ragged edge can push a stain outward (0.22 + 0.07)

static var _ragged: Array[FastNoiseLite] = []


static func _h(key: String) -> float:
	return float(hash(key) & 0xFFFF) / 65535.0


# The stain's ragged edge: smooth value noise in -1..1 at three and nine waves a cell, fixed seeds so a
# redraw never moves it.
static func _noise() -> Array[FastNoiseLite]:
	if _ragged.is_empty():
		for frequency: float in [3.0, 9.0]:
			var noise := FastNoiseLite.new()
			noise.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
			noise.fractal_type = FastNoiseLite.FRACTAL_NONE
			noise.frequency = frequency
			noise.seed = 696
			_ragged.append(noise)
	return _ragged
