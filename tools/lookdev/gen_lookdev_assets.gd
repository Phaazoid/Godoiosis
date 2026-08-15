# Generates the HD-2D look-dev placeholder assets (#203 / #176 Stage 0).
# Two phases, because the meshlib needs the PNGs to be IMPORTED first:
#   godot --headless --path . --script res://tools/lookdev/gen_lookdev_assets.gd -- --textures
#   godot --headless --path . --import
#   godot --headless --path . --script res://tools/lookdev/gen_lookdev_assets.gd -- --meshlib
# Textures land in Art/LookDev/ (32 px/tile, flat-lit, deterministic seed);
# the MeshLibrary in Scenes/LookDev/.
#
# The meshlib has TWO tenants since #250, and the split is the whole point:
#   ids 0-6   the hand-picked Kind blocks + the ramp. The LookDev diorama paints
#             these by id (board_painter.gd's GRASS/STONE/RAMP), and BoardMirror
#             keeps them as its declared fallback -- so they are APPEND-ONLY.
#   ids 7+    one block per real tileset tile, top face wearing that tile's own
#             art. This is what makes the 3D board show the GAME's tiles instead
#             of six generated stand-ins.
# A cell's SURFACE comes from its atlas coords (id 7+); what it is MADE OF -- the
# side/wall material -- still comes from its Terrain.Kind. Two questions, and Kind
# was answering both until #250.
extends SceneTree

const ART_DIR := "res://Art/LookDev"
const MESHLIB_PATH := "res://Scenes/LookDev/lookdev_meshlib.tres"
const TILESET_PATH := "res://Resources/TestTiles.tres"
const TILE := 32

# Where the per-tileset-tile items start. Everything below is the Stage-0 set.
const FIRST_TILE_ITEM := 7

# Share of non-opaque pixels above which a tile is reported as "mostly open" — a sprite on an
# empty field rather than ground with a soft edge. Diagnostic only; every tile is based over
# its kind regardless, so nothing depends on where exactly this sits.
const HOLE_FRACTION := 0.05

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

	var bases: Dictionary[Terrain.Kind, Texture2D] = {
		Terrain.Kind.GRASS: grass_top,
		Terrain.Kind.MUD: mud_top,
		Terrain.Kind.ROCK: stone_top,
		Terrain.Kind.TREE: tree_top,
		Terrain.Kind.WATER: water_top,
		Terrain.Kind.DIRT: dirt_top,
	}
	if _add_tileset_items(ml, _mat(dirt_side), _mat(stone_side), bases, dirt_top) < 0:
		return 1

	var err := ResourceSaver.save(ml, MESHLIB_PATH)
	if err != OK:
		push_error("Failed to save %s (error %d)" % [MESHLIB_PATH, err])
		return 1
	print("MeshLibrary written to %s" % MESHLIB_PATH)
	return 0


# One block per real tileset tile, top face wearing that tile's own art -- except a stands_up
# tile, whose top face is the bare ground it stands on (#255). Returns how many items were
# added, or -1 on failure.
#
# Two classes are SKIPPED entirely, and BoardMirror falls back to the Kind blocks for both:
# a multi-cell tile (the 1x2 lantern, the 3x3s) has art taller than a cell and cannot go onto
# a 1x1 top face without squashing it, and a non-zero alternative is a flip/rotate variant.
# The multi-cell ones are all props, so their art DOES reach the board -- on a billboard,
# which has no 1x1 constraint. This loop only decides what the GROUND under them looks like.
func _add_tileset_items(ml: MeshLibrary, dirt_side: Material, stone_side: Material,
		bases: Dictionary[Terrain.Kind, Texture2D], default_base: Texture2D) -> int:
	var ts := load(TILESET_PATH) as TileSet
	if ts == null:
		push_error("Tileset missing or unreadable at %s" % TILESET_PATH)
		return -1

	var next_id := FIRST_TILE_ITEM
	var translucent: PackedStringArray = []
	for i in ts.get_source_count():
		var source_id := ts.get_source_id(i)
		var atlas := ts.get_source(source_id) as TileSetAtlasSource
		if atlas == null:
			continue   # only an atlas source has per-tile art to carry over
		var tex := atlas.texture
		var source_image := _rgba(tex)
		if source_image == null:
			push_error("Atlas source %d has no readable image" % source_id)
			return -1
		# The GROUND ATLAS: every tile painted over an opaque base of its own kind. In 2D a
		# rock's transparent pixels show the window behind the board -- a void, which is a fine
		# thing for a flat board to have and an impossible one for a solid block: the same pixels
		# would cut a hole clean through it (measured: rock 32% open, tree 43%, fences up to 56%).
		# A diorama's answer is that the rock SITS ON ground, so that is what gets baked. Ground
		# tiles are already opaque, so for them this is a no-op -- no branch, one rule.
		var ground := Image.create_empty(source_image.get_width(), source_image.get_height(),
				false, Image.FORMAT_RGBA8)
		var base_cache: Dictionary[Terrain.Kind, Image] = {}
		# ONE material for every top face in this source: the items differ by UV, not by
		# material, so the whole board's ground is one texture and one shader. Opaque, because
		# the compositing above leaves nothing to blend.
		var atlas_mat := _mat(null)
		var atlas_size := Vector2(source_image.get_width(), source_image.get_height())
		for coords in _sorted_tile_coords(atlas):
			if atlas.get_tile_size_in_atlas(coords) != Vector2i.ONE:
				continue
			var region := atlas.get_tile_texture_region(coords, 0)
			var data := atlas.get_tile_data(coords, 0)
			var kind := GridUtils.terrain_kind_of(data)
			if not base_cache.has(kind):
				var base_tex: Texture2D = bases.get(kind, default_base)
				var base_img := _rgba(base_tex)
				base_img.resize(region.size.x, region.size.y, Image.INTERPOLATE_NEAREST)
				base_cache[kind] = base_img
			ground.blit_rect(base_cache[kind], Rect2i(Vector2i.ZERO, region.size), region.position)
			# A prop's top face is the ground it STANDS ON, so its art is left off (#255) --
			# BoardMirror puts that art on a billboard instead, and baking it here as well would
			# render the tree twice, once flat and once standing.
			var stands_up := GridUtils.stands_up_of(data)
			if not stands_up:
				ground.blend_rect(source_image, region, region.position)

			var top_uv := _uv_rect(region, atlas_size)
			var side: Material = stone_side if kind == Terrain.Kind.ROCK else dirt_side
			var side_uv := Rect2(0, 0, 1, 1)
			if kind == Terrain.Kind.WATER:
				side = atlas_mat        # water wears its own surface down the sides, as water_block does
				side_uv = top_uv
			_add_item(ml, next_id, BoardMirror.tile_item_name(source_id, coords),
					_block_mesh(atlas_mat, side, top_uv, side_uv))
			next_id += 1
			# Only GROUND tiles are worth reporting now: an open prop is expected (it stands up
			# and its art never reaches a top face), while an open ground tile is the surprising
			# case -- it is being based over a kind colour that nobody chose deliberately.
			var clear := _transparent_fraction(source_image, region)
			if not stands_up and clear >= HOLE_FRACTION:
				translucent.append("%d/%d:%d (%d%%)" % [source_id, coords.x, coords.y, roundi(clear * 100.0)])

		# Embedded in the meshlib rather than written as a PNG: a generated atlas saved to disk
		# would be imported with detect_3d on and silently re-imported to VRAM compression with
		# MIPMAPS the first time it rendered -- and mipmaps on an atlas bleed neighbouring tiles
		# into each other at distance, which is the one thing the half-texel UV inset cannot fix.
		atlas_mat.albedo_texture = ImageTexture.create_from_image(ground)

	var added := next_id - FIRST_TILE_ITEM
	print("Tileset items %d..%d (%d tiles) from %s" % [FIRST_TILE_ITEM, next_id - 1, added, TILESET_PATH])
	if not translucent.is_empty():
		# A report, not an error. A GROUND tile this open is a sprite on an empty field wearing a
		# kind colour behind it -- either it wants stands_up ticked, or its base was never chosen.
		print("  mostly-open GROUND tiles (%d) (candidates for stands_up): %s" \
				% [translucent.size(), ", ".join(translucent)])
	return added


# Deterministic order, so regenerating an unchanged tileset produces an identical file.
func _sorted_tile_coords(atlas: TileSetAtlasSource) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for i in atlas.get_tiles_count():
		coords.append(atlas.get_tile_id(i))
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	return coords


# The tile's atlas region as UVs, inset by half a texel. The atlas declares no separation
# or margin, so edge-exact UVs sample into the neighbouring tile.
func _uv_rect(region: Rect2i, atlas_size: Vector2) -> Rect2:
	var inset := Vector2(0.5, 0.5)
	var from := (Vector2(region.position) + inset) / atlas_size
	var to := (Vector2(region.end) - inset) / atlas_size
	return Rect2(from, to - from)


# A texture's pixels as a plain RGBA8 Image — imported textures arrive compressed, and both
# blend_rect and get_pixel need the decoded form.
func _rgba(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


# What share of the tile's pixels are not fully opaque. A FRACTION rather than a yes/no,
# because the two ends mean opposite things: a couple of soft corner pixels are nothing, while
# a sprite drawn on an empty field cannot be a top face at all -- it would cut a hole straight
# into the block. HOLE_FRACTION is where the second starts.
func _transparent_fraction(image: Image, region: Rect2i) -> float:
	if image == null:
		return 0.0
	var clear := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if image.get_pixel(x, y).a < 1.0:
				clear += 1
	return float(clear) / float(maxi(1, region.size.x * region.size.y))


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
# The UV rects default to the whole texture (the Kind blocks, whose textures are one
# tile each); an atlas-backed item passes the tile's own region instead.
func _block_mesh(top_mat: Material, side_mat: Material,
		top_uv := Rect2(0, 0, 1, 1), side_uv := Rect2(0, 0, 1, 1)) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(top_mat)
	_quad(st, Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5),
			Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3.UP, top_uv)
	st.commit(mesh)

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(side_mat)
	_quad(st, Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5),
			Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5), Vector3.BACK, side_uv)      # south
	_quad(st, Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5),
			Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3.FORWARD, side_uv) # north
	_quad(st, Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, -0.5),
			Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3.RIGHT, side_uv)     # east
	_quad(st, Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, 0.5, 0.5),
			Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, -0.5, -0.5), Vector3.LEFT, side_uv)    # west
	_quad(st, Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5),
			Vector3(0.5, -0.5, -0.5), Vector3(-0.5, -0.5, -0.5), Vector3.DOWN, side_uv)    # bottom
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
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3,
		uv_rect := Rect2(0, 0, 1, 1)) -> void:
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var points: Array[Vector3] = [a, b, c, a, c, d]
	var uv_order: Array[int] = [0, 1, 2, 0, 2, 3]
	for i in points.size():
		st.set_normal(normal)
		st.set_uv(uv_rect.position + uvs[uv_order[i]] * uv_rect.size)
		st.add_vertex(points[i])


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	var uvs: Array[Vector2] = [Vector2(0.5, 0), Vector2(1, 1), Vector2(0, 1)]
	var points: Array[Vector3] = [a, b, c]
	for i in points.size():
		st.set_normal(normal)
		st.set_uv(uvs[i])
		st.add_vertex(points[i])
