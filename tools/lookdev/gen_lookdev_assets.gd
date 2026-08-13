# Generates the HD-2D look-dev placeholder assets (#203 / #176 Stage 0).
# Two phases, because the meshlib needs the PNGs to be IMPORTED first:
#   godot --headless --path . --script res://tools/lookdev/gen_lookdev_assets.gd -- --textures
#   godot --headless --path . --import
#   godot --headless --path . --script res://tools/lookdev/gen_lookdev_assets.gd -- --meshlib
# Textures land in Art/LookDev/ (32 px/tile, flat-lit, deterministic seed);
# the MeshLibrary (grass block / stone block / dirt ramp) in Scenes/LookDev/.
# Placeholder only -- real tile art replaces these files at the #176 art pass.
extends SceneTree

const ART_DIR := "res://Art/LookDev"
const MESHLIB_PATH := "res://Scenes/LookDev/lookdev_meshlib.tres"
const TILE := 32

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var code := 0
	if args.has("--textures"):
		code = _gen_textures()
	elif args.has("--meshlib"):
		code = _gen_meshlib()
	else:
		push_error("Pass -- --textures or -- --meshlib (see file header for the two-phase order).")
		code = 1
	quit(code)


# --- Phase 1: pixel textures -------------------------------------------------

func _gen_textures() -> int:
	DirAccess.make_dir_recursive_absolute(ART_DIR)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("iosis-lookdev-v1")
	_save(_grass_top(rng), "grass_top.png")
	_save(_dirt_side(rng), "dirt_side.png")
	_save(_stone_top(rng), "stone_top.png")
	_save(_stone_side(rng), "stone_side.png")
	_save(_flame(rng), "torch_flame.png")
	_save(_cell_fill(), "cell_fill.png")
	_save(_speckled(rng, Color8(118, 86, 58), 0.10), "dirt_top.png")
	_save(_speckled(rng, Color8(74, 58, 44), 0.14), "mud_top.png")
	_save(_water_top(rng), "water_top.png")
	_save(_speckled(rng, Color8(44, 86, 52), 0.16), "tree_top.png")
	print("LookDev textures written to %s" % ART_DIR)
	return 0


# Generic speckled flat tile — the #215 kind tops (dirt / mud / tree canopy).
func _speckled(rng: RandomNumberGenerator, base: Color, spread: float) -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		for x in TILE:
			var c := base
			var r := rng.randf()
			if r < 0.08:
				c = base.darkened(spread)
			elif r > 0.94:
				c = base.lightened(spread)
			img.set_pixel(x, y, c)
	return img


func _water_top(rng: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	var base := Color8(52, 96, 150)
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, base.lightened(0.04) if (y % 8 < 1) else base)
	for i in 14:  # sparse wave flecks
		var x := rng.randi_range(0, TILE - 3)
		var y := rng.randi_range(0, TILE - 1)
		for dx in 2:
			img.set_pixel(x + dx, y, base.lightened(0.22))
	return img


# The overlay fill (#213): white with a soft 2px inset border; layers tint it via
# Decal.modulate, so ONE texture serves every fill color.
func _cell_fill() -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		for x in TILE:
			var edge := mini(mini(x, TILE - 1 - x), mini(y, TILE - 1 - y))
			var alpha := 1.0
			if edge == 0:
				alpha = 0.9
			elif edge == 1:
				alpha = 0.55
			elif edge >= 2:
				alpha = 0.75
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	return img


func _save(img: Image, file_name: String) -> void:
	var err := img.save_png("%s/%s" % [ART_DIR, file_name])
	if err != OK:
		push_error("Failed to write %s (error %d)" % [file_name, err])


func _grass_top(rng: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	var shades: Array[Color] = [
		Color8(88, 134, 66), Color8(96, 144, 72), Color8(104, 152, 78),
	]
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, shades[rng.randi_range(0, shades.size() - 1)])
	for i in 26:  # sparse darker speckles + light blades
		var x := rng.randi_range(0, TILE - 1)
		var y := rng.randi_range(0, TILE - 1)
		img.set_pixel(x, y, Color8(72, 112, 56) if i % 2 == 0 else Color8(122, 168, 90))
	return img


func _dirt_side(rng: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	var band_shift := 0.0
	for y in TILE:
		if y % 5 == 0:
			band_shift = rng.randf_range(-0.05, 0.05)  # horizontal strata
		var base := Color8(118, 86, 58).lightened(band_shift) if band_shift > 0.0 \
				else Color8(118, 86, 58).darkened(-band_shift)
		for x in TILE:
			var c := base
			var r := rng.randf()
			if r < 0.06:
				c = base.darkened(0.18)  # pebbles
			elif r > 0.95:
				c = base.lightened(0.10)
			img.set_pixel(x, y, c)
	for x in TILE:  # darker soil lip under the grass line
		img.set_pixel(x, 0, Color8(94, 66, 44))
		img.set_pixel(x, 1, Color8(102, 73, 49))
	return img


func _stone_top(rng: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		for x in TILE:
			var quad_light := 0.03 if (x / 16 + y / 16) % 2 == 0 else -0.03
			var c := Color8(118, 118, 126).lightened(quad_light)
			var r := rng.randf()
			if r < 0.05:
				c = c.darkened(0.12)
			elif r > 0.96:
				c = c.lightened(0.08)
			img.set_pixel(x, y, c)
	return img


func _stone_side(rng: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	var mortar := Color8(84, 84, 92)
	for y in TILE:
		var course := y / 8
		for x in TILE:
			var offset := 8 if course % 2 == 1 else 0  # running bond
			var brick := (x + offset) / 16
			var shade := 0.04 * float((brick + course * 3) % 3 - 1)
			var c := Color8(112, 112, 122).lightened(shade) if shade > 0.0 \
					else Color8(112, 112, 122).darkened(-shade)
			if y % 8 == 7 or (x + offset) % 16 == 15:
				c = mortar
			elif rng.randf() < 0.04:
				c = c.darkened(0.10)
			img.set_pixel(x, y, c)
	return img


func _flame(rng: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(8.0, 9.5)
	for y in 16:
		for x in 16:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d := Vector2(p.x - center.x, (p.y - center.y) * 1.35).length()
			d += rng.randf_range(-0.35, 0.35)  # rough pixel edge
			if d < 2.2:
				img.set_pixel(x, y, Color(1.0, 0.96, 0.78))
			elif d < 3.9:
				img.set_pixel(x, y, Color(1.0, 0.78, 0.25))
			elif d < 5.4:
				img.set_pixel(x, y, Color(0.94, 0.45, 0.10))
	return img


# --- Phase 2: the MeshLibrary ------------------------------------------------

func _gen_meshlib() -> int:
	var grass_top := _load_tex("grass_top.png")
	var dirt_side := _load_tex("dirt_side.png")
	var stone_top := _load_tex("stone_top.png")
	var stone_side := _load_tex("stone_side.png")
	if grass_top == null or dirt_side == null or stone_top == null or stone_side == null:
		push_error("Textures missing or unimported -- run the --textures phase, then --import, first.")
		return 1

	DirAccess.make_dir_recursive_absolute(MESHLIB_PATH.get_base_dir())
	var dirt_top := _load_tex("dirt_top.png")
	var mud_top := _load_tex("mud_top.png")
	var water_top := _load_tex("water_top.png")
	var tree_top := _load_tex("tree_top.png")
	if dirt_top == null or mud_top == null or water_top == null or tree_top == null:
		push_error("Kind textures missing (#215) -- rerun --textures, then --import, first.")
		return 1

	var ml := MeshLibrary.new()
	_add_item(ml, 0, "grass_block", _block_mesh(_mat(grass_top), _mat(dirt_side)))
	_add_item(ml, 1, "stone_block", _block_mesh(_mat(stone_top), _mat(stone_side)))
	_add_item(ml, 2, "dirt_ramp", _ramp_mesh(_mat(grass_top), _mat(dirt_side)))
	_add_item(ml, 3, "dirt_block", _block_mesh(_mat(dirt_top), _mat(dirt_side)))
	_add_item(ml, 4, "mud_block", _block_mesh(_mat(mud_top), _mat(dirt_side)))
	_add_item(ml, 5, "water_block", _block_mesh(_mat(water_top), _mat(water_top)))
	_add_item(ml, 6, "tree_block", _block_mesh(_mat(tree_top), _mat(dirt_side)))
	var err := ResourceSaver.save(ml, MESHLIB_PATH)
	if err != OK:
		push_error("Failed to save %s (error %d)" % [MESHLIB_PATH, err])
		return 1
	print("MeshLibrary written to %s" % MESHLIB_PATH)
	return 0


func _load_tex(file_name: String) -> Texture2D:
	var path := "%s/%s" % [ART_DIR, file_name]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _mat(tex: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 1.0
	mat.metallic_specular = 0.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _add_item(ml: MeshLibrary, id: int, item_name: String, mesh: Mesh) -> void:
	ml.create_item(id)
	ml.set_item_name(id, item_name)
	ml.set_item_mesh(id, mesh)


# A 1x1x1 cell block: surface 0 = top (terrain face), surface 1 = sides + bottom.
func _block_mesh(top_mat: Material, side_mat: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(top_mat)
	_quad(st, Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5),
			Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3.UP)
	st.commit(mesh)

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(side_mat)
	_quad(st, Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5),
			Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5), Vector3.BACK)      # south
	_quad(st, Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5),
			Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3.FORWARD) # north
	_quad(st, Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, -0.5),
			Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3.RIGHT)     # east
	_quad(st, Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, 0.5, 0.5),
			Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, -0.5, -0.5), Vector3.LEFT)    # west
	_quad(st, Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5),
			Vector3(0.5, -0.5, -0.5), Vector3(-0.5, -0.5, -0.5), Vector3.DOWN)    # bottom
	st.commit(mesh)
	return mesh


# A wedge: high edge at -Z falling to -0.5 at +Z. Slope face wears the terrain
# texture; GridMap orientation (yaw steps) points the high side at the upper level.
func _ramp_mesh(top_mat: Material, side_mat: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var slope_normal := Vector3(0.0, 1.0, 1.0).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(top_mat)
	_quad(st, Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5),
			Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5), slope_normal)
	st.commit(mesh)

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(side_mat)
	_tri(st, Vector3(0.5, 0.5, -0.5), Vector3(0.5, -0.5, -0.5),
			Vector3(0.5, -0.5, 0.5), Vector3.RIGHT)                               # east
	_tri(st, Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, -0.5, 0.5),
			Vector3(-0.5, -0.5, -0.5), Vector3.LEFT)                              # west
	_quad(st, Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5),
			Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3.FORWARD) # back
	_quad(st, Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5),
			Vector3(0.5, -0.5, -0.5), Vector3(-0.5, -0.5, -0.5), Vector3.DOWN)    # bottom
	st.commit(mesh)
	return mesh


# Corners in clockwise order viewed from outside (Godot front-face winding).
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var points: Array[Vector3] = [a, b, c, a, c, d]
	var uv_order: Array[int] = [0, 1, 2, 0, 2, 3]
	for i in points.size():
		st.set_normal(normal)
		st.set_uv(uvs[uv_order[i]])
		st.add_vertex(points[i])


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	var uvs: Array[Vector2] = [Vector2(0.5, 0), Vector2(1, 1), Vector2(0, 1)]
	var points: Array[Vector3] = [a, b, c]
	for i in points.size():
		st.set_normal(normal)
		st.set_uv(uvs[i])
		st.add_vertex(points[i])
