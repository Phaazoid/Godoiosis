# Generates the HD-2D look-dev placeholder assets (#203 / #176 Stage 0).
# Two phases, because the meshlib needs the PNGs to be IMPORTED first:
#   godot --headless --path . --script res://tools/lookdev/gen_lookdev_assets.gd -- --textures
#   godot --headless --path . --import
#   godot --headless --path . --script res://tools/lookdev/gen_lookdev_assets.gd -- --meshlib
# Textures land in Art/LookDev/ (32 px/tile, flat-lit, deterministic seed);
# the MeshLibrary in Scenes/LookDev/.
#
# The --meshlib phase WRITES one more texture than --textures does: the composed ground atlas
# (#540, see _write_atlas), which the library then references rather than embedding. So a run that
# CHANGES the atlas -- new tileset art, a new prop shape -- refuses, because the imported copy it
# would name is still the previous one; repeat --import and --meshlib and the second pass lands.
# An unchanged atlas needs neither, which is every run that is not editing the tileset.
#
# The meshlib has TWO tenants since #250, and the split is the whole point:
#   ids 0-8   the hand-picked Kind blocks, both fallback ramps and the wedge filler. The LookDev
#             diorama paints these by id (board_painter.gd's GRASS/STONE/RAMP), and BoardMirror
#             keeps them as its declared fallback -- so they are APPEND-ONLY, which is why #427
#             slice 2's gentle wedge and filler landed at 7 and 8 rather than beside the steep one.
#   ids 9+    one block per real tileset tile, top face wearing that tile's own
#             art, PLUS one wedge per authorable climb. This is what makes the 3D
#             board show the GAME's tiles instead of six generated stand-ins.
# A cell's SURFACE comes from its atlas coords (id 7+); what it is MADE OF -- the
# side/wall material -- still comes from its Terrain.Kind. Two questions, and Kind
# was answering both until #250.
#
# SOLID PROPS (#264) ride the same ids: a tile whose authored PropShape is CUBE/FACETED/ROUND
# also gets a `prop_` item holding real geometry. Its SIDES wear the tile's own sprite and its
# TOP is GENERATED, because that top face is the entire reason a blocky prop could not be a
# billboard -- one 3/4 drawing cannot supply it, and at the board's ~40 degree pitch you see
# plenty of it. Both faces are packed into extra rows of the same composited atlas, so the whole
# board is still one texture.
extends SceneTree

const ART_DIR := "res://Art/LookDev"
const MESHLIB_PATH := "res://Scenes/LookDev/lookdev_meshlib.tres"
const TILESET_PATH := "res://Resources/TestTiles.tres"
const TILE := 32

# The composed ground atlas, one PNG per tileset source (#540) -- a generated artifact like every
# other file in ART_DIR, committed alongside an authored .import.
const ATLAS_NAME := "ground_atlas_%d.png"

# Where the per-tileset-tile items start. Everything below is the Stage-0 set, plus #427 slice 2's
# gentle fallback wedge and the wedge filler, plus slice 3's four generic corner caps (outer and
# inner, at each authorable climb).
#
# It MOVED with slice 3, and the number is load-bearing rather than cosmetic: the generic block below
# writes ids up to FIRST_TILE_ITEM - 1 and the tileset loop writes from it, so leaving this at 9
# silently overwrote four tile items with fallbacks -- Godot's own create_item refused them, which is
# the only reason it was loud.
const FIRST_TILE_ITEM := 13

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
	_save(_fire_sheet(), "fire_flame.png")
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


# The TERRAIN fire sheet (#324): FIRE_FRAMES frames left to right, each FIRE_FRAME_W x
# FIRE_FRAME_H. A separate asset from the torch blob above, because a cell on fire and a lamp
# on a wall are different objects -- the torch keeps its own texture.
#
# Analytic and EXACTLY LOOPING rather than per-frame noise: every term is periodic in
# t = frame / FIRE_FRAMES, so the last frame hands back to the first with no seam. Two upward
# travelling harmonics sway the centreline, the height pulses on the same period, and the four
# tones fall out of ONE heat value -- hottest at the base centre, cooling outward and upward.
# That gradient is what makes the silhouette read as flame rather than as a wobbling triangle.
const FIRE_FRAMES := 8
const FIRE_FRAME_W := 16
const FIRE_FRAME_H := 24


func _fire_sheet() -> Image:
	var img := Image.create_empty(FIRE_FRAME_W * FIRE_FRAMES, FIRE_FRAME_H, false,
			Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var core := Color8(255, 246, 214)
	var hot := Color8(255, 198, 64)
	var mid := Color8(240, 122, 24)
	var edge := Color8(176, 48, 16)
	var cx := FIRE_FRAME_W * 0.5
	for f in FIRE_FRAMES:
		var t := float(f) / float(FIRE_FRAMES)
		# How much of the frame the flame fills this beat -- the whole body rises and settles.
		var top: float = 0.82 + 0.18 * sin(TAU * (t + 0.15))
		for y in FIRE_FRAME_H:
			# h is measured from the BOTTOM: the art stands on the frame's lower edge.
			var h := float(FIRE_FRAME_H - 1 - y) / float(FIRE_FRAME_H - 1)
			if h > top:
				continue
			var u := h / top
			# Anchored at the foot (the pow), free at the tip -- a flame does not slide sideways
			# along the ground it burns on.
			var sway: float = (2.2 * sin(TAU * (u - t))
					+ 1.0 * sin(TAU * (2.0 * u - 2.0 * t) + 1.3)) * pow(u, 1.4)
			var half: float = 5.2 * pow(1.0 - u, 0.7) * (0.7 + 0.3 * sin(PI * u))
			half *= 1.0 + 0.18 * sin(TAU * (1.5 * u - t) + 0.7)
			for x in FIRE_FRAME_W:
				var d: float = absf(float(x) + 0.5 - (cx + sway))
				if half <= 0.01 or d > half:
					continue
				var heat := (1.0 - d / half) * (1.0 - 0.55 * u)
				var c := edge
				if heat > 0.70:
					c = core
				elif heat > 0.48:
					c = hot
				elif heat > 0.24:
					c = mid
				img.set_pixel(f * FIRE_FRAME_W + x, y, c)
		_fire_ember(img, f, t, cx, mid, edge)
	return img


# A spark leaving the tip. It RESTARTS at the loop point rather than travelling through it,
# which is what a spark does -- one dies and the next goes up.
func _fire_ember(img: Image, frame: int, t: float, cx: float, warm: Color, cool: Color) -> void:
	var rise: float = 0.80 + 0.20 * t
	var y := FIRE_FRAME_H - 1 - int(round(rise * float(FIRE_FRAME_H - 1)))
	var x := int(round(cx + 1.6 * sin(TAU * (t + 0.25))))
	if y < 0 or x < 0 or x >= FIRE_FRAME_W:
		return
	var c: Color = warm if t < 0.5 else cool
	img.set_pixel(frame * FIRE_FRAME_W + x, y, c)


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

	# REUSE the existing library rather than building a fresh one, so the object being saved IS the
	# cache entry and keeps its path and its UID. A MeshLibrary.new() gets a NEW uid at save time, and
	# every .tscn naming the old one is left pointing at nothing -- Godot degrades to the path and
	# rewrites the scene, which is exactly what #427 slice 2 did to Battle3D.tscn. take_over_path is
	# NOT enough on its own: #481 measured DevWidgets.save_over dropping UIDs while doing precisely
	# that. Absent file = first run, and a fresh library is then correct.
	var previous_uids := DevWidgets.uid_map_in_file(MESHLIB_PATH)
	var ml: MeshLibrary = ResourceLoader.load(MESHLIB_PATH, "MeshLibrary", ResourceLoader.CACHE_MODE_REPLACE)
	if ml == null:
		ml = MeshLibrary.new()
	else:
		for id in ml.get_item_list():
			ml.remove_item(id)
	_add_item(ml, 0, "grass_block", _block_mesh(_mat(grass_top), _mat(dirt_side)))
	_add_item(ml, 1, "stone_block", _block_mesh(_mat(stone_top), _mat(stone_side)))
	_add_item(ml, 2, "dirt_ramp", _form_mesh(_canonical_corners(Terrain.Form.WEDGE,
			Terrain.UNITS_PER_LEVEL), _mat(grass_top), _mat(dirt_side)))
	_add_item(ml, 3, "dirt_block", _block_mesh(_mat(dirt_top), _mat(dirt_side)))
	_add_item(ml, 4, "mud_block", _block_mesh(_mat(mud_top), _mat(dirt_side)))
	_add_item(ml, 5, "water_block", _block_mesh(_mat(water_top), _mat(water_top)))
	_add_item(ml, 6, "tree_block", _block_mesh(_mat(tree_top), _mat(dirt_side)))
	# Ids 0-6 are the hand-picked fallbacks and Scenes/LookDev/LookDev.tscn's diorama references them
	# BY ID, so #427 slice 2's additions append rather than renumber. The gentle fallback wedge is the
	# steep one's twin; the filler is an EMPTY mesh, whose whole job is to occupy the rows a tall
	# wedge spans (see BoardMirror.RAMP_FILL_ITEM_NAME).
	_add_item(ml, 7, BoardMirror.RAMP_ITEM_NAMES[1], _form_mesh(
			_canonical_corners(Terrain.Form.WEDGE, 1), _mat(grass_top), _mat(dirt_side)))
	_add_item(ml, 8, BoardMirror.RAMP_FILL_ITEM_NAME, ArrayMesh.new())
	# The generic OUTER and INNER caps (#427 slice 3), appended for the same reason the gentle wedge
	# was: ids 0-8 are referenced BY ID from LookDev.tscn. These are the fallback a cell gets when its
	# own tile has no cap -- an empty cell, a rotated alternative, multi-cell art, or a prop painted
	# onto sloped ground.
	var next_generic := 9
	for climb: int in BoardMirror.RAMP_ITEM_NAMES:
		for form: Terrain.Form in [Terrain.Form.OUTER, Terrain.Form.INNER]:
			_add_item(ml, next_generic, "%s_%s" % [BoardMirror.RAMP_ITEM_NAMES[climb],
					BoardMirror.form_suffix(form)],
					_form_mesh(_canonical_corners(form, climb), _mat(grass_top), _mat(dirt_side)))
			next_generic += 1

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
	if not DevWidgets.restore_uids(MESHLIB_PATH, previous_uids):
		return 1
	print("MeshLibrary written to %s" % MESHLIB_PATH)
	return 0


# UID preservation lives in DevWidgets.uid_map_in_file / DevWidgets.restore_uids now (#481) -- the
# generator and the single dev-tool writer share it, so there is ONE answer to "what uid does this
# file have" rather than a private copy here drifting out of step.


# One block per real tileset tile, top face wearing that tile's own art -- except a tile that
# STANDS UP, whose top face is the bare ground it stands on (#255). A tile whose shape is solid
# gets a second item as well, holding its prop geometry (#264). Returns how many items were
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
	var props := 0
	var translucent: PackedStringArray = []
	# Seeded, like every other generated texture here, so an unchanged tileset regenerates an
	# identical meshlib and a re-run produces no diff.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("iosis-props-v1")
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
		#
		# It also grows EXTRA ROWS below the source art (#264), two per solid prop: its SIDE strip
		# and its TOP. BOTH are generated as of #274 -- the sprite reached neither face -- so a
		# prism's side is one patch PER FACET rather than one patch, which is why the layout is
		# packed by a function instead of counted. Packing BEFORE the walk is what lets a UV be
		# computed inside it: the finished atlas height has to be known before the first is written.
		var patch: Vector2i = atlas.texture_region_size
		var columns := maxi(1, source_image.get_width() / patch.x)
		var packed := _pack_slots(_solid_patch_widths(atlas), columns, patch, source_image.get_height())
		if packed.is_empty():
			return -1
		var slots: Array[Rect2i] = packed["slots"]
		var ground := Image.create_empty(source_image.get_width(),
				source_image.get_height() + int(packed["rows"]) * patch.y, false, Image.FORMAT_RGBA8)
		var next_slot := 0
		var base_cache: Dictionary[Terrain.Kind, Image] = {}
		# ONE material for every top face in this source: the items differ by UV, not by
		# material, so the whole board's ground is one texture and one shader. Opaque, because
		# the compositing above leaves nothing to blend.
		var atlas_mat := _mat(null)
		# The props' own material over the SAME texture. Backface culling ON, because a prop is a
		# closed solid.
		#
		# The ALPHA SCISSOR is back for #263, reversing #274's simplification. That reasoning still
		# holds for the solids -- every generated face paints every pixel, so this is a no-op for
		# them -- but a PLANE wears the tile's own sprite, and the gaps between a fence's logs ARE
		# the art: opaque, a palisade renders as a solid board and stops being a fence. Cut-out
		# rather than blended, matching the unit sprites' discipline so it writes depth and needs no
		# hand-maintained render_priority.
		var prop_mat := _mat(null)
		prop_mat.cull_mode = BaseMaterial3D.CULL_BACK
		prop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		prop_mat.alpha_scissor_threshold = 0.5
		var atlas_size := Vector2(ground.get_width(), ground.get_height())
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
			#
			# THREE answers, not two, since #280. A FLAT tile wears its own art. A prop wears the
			# bare kind base. A TUFT wears a GENERATED SPECKLE in its own colours: its plants stand
			# up, so drawing them flat here as well is the same double-render -- but the bare kind
			# base is the wrong ground under them, because it is a different green from the tile
			# the plants were cut out of.
			var shape := GridUtils.prop_shape_of(data)
			var stands_up := shape != GridUtils.PropShape.FLAT
			if not stands_up:
				ground.blend_rect(source_image, region, region.position)
			elif shape == GridUtils.PropShape.TUFT:
				ground.blit_rect(_tuft_ground(rng, source_image, region),
						Rect2i(Vector2i.ZERO, region.size), region.position)

			var top_uv := _uv_rect(region, atlas_size)
			var side: Material = stone_side if kind == Terrain.Kind.ROCK else dirt_side
			var side_uv := Rect2(0, 0, 1, 1)
			if kind == Terrain.Kind.WATER:
				side = atlas_mat        # water wears its own surface down the sides, as water_block does
				side_uv = top_uv
			_add_item(ml, next_id, BoardMirror.tile_item_name(source_id, coords),
					_block_mesh(atlas_mat, side, top_uv, side_uv))
			next_id += 1

			# The same surface on a SLOPE (#340). EVERY 1x1 tile gets one, wearing exactly what the
			# block above wears on its top face -- same top_uv, same side, same materials.
			#
			# It was FLAT tiles only until #342, on the reading that a rock has no top face to tilt.
			# That confused a tile's ART with a tile's GROUND: what a cap draws is the ground the prop
			# STANDS ON, which the atlas pass above has already composed for every tile -- own art for
			# flat, the bare kind base for a prop, a generated speckle for a tuft. The gate was a
			# SECOND answer to a question that pass already answers, and it degraded twice over: a
			# TUFT is walkable ground the corner tool slopes freely, and any prop can be painted onto
			# a cell that already slopes. Both wore the generic grass wedge, so a flowery-grass slope
			# read olive beside its own mint neighbours.
			#
			# ONE PER AUTHORABLE CLIMB since #427 slice 2 — the tile's art on a 45 degree wedge and on
			# the gentle one are different geometry, and the item NAME carries the climb so the mirror
			# picks by asking rather than by guessing which of two namespaces to look in.
			#
			# ONE PER SHAPE as well since #427 slice 3: a cell can be a cardinal wedge, an outer
			# corner or an inner one, and those are different geometry off one tile's art. Three
			# shapes and not twelve masks -- the GridMap's yaw supplies each shape's four rotations,
			# which is what keeps the artifact at ~2200 items instead of ~4000.
			for climb: int in BoardMirror.RAMP_ITEM_NAMES:
				for form: Terrain.Form in [Terrain.Form.WEDGE, Terrain.Form.OUTER,
						Terrain.Form.INNER]:
					_add_item(ml, next_id,
							BoardMirror.ramp_item_name(source_id, coords, climb, form),
							_form_mesh(_canonical_corners(form, climb), atlas_mat, side,
									top_uv, side_uv))
					next_id += 1

			# The solid prop's own item: real geometry sized by the art, wearing faces GENERATED in
			# that tile's own dominant colours. A billboard prop gets none -- BoardMirror builds its
			# sprite directly, and a billboard is the one form a sprite maps onto correctly.
			if GridUtils.SOLID_SHAPES.has(shape):
				var edges := GridUtils.wall_edges_of(data)
				var palette := _palette_of(source_image, region)
				var mesh: ArrayMesh = null
				if shape == GridUtils.PropShape.PLANE:
					# A plane is sized by PLANE_HEIGHT/THICKNESS rather than by opaque bounds: it is
					# thin BY DEFINITION in the axis it does not run along, and the bounds of a
					# foreshortened north-south piece measure a run, not a wall (#263).
					var own_edges := GridUtils.plane_own_art_edges(data)
					var own_uv := Rect2()
					var face_uv := Rect2()
					if edges & own_edges != 0:
						var own_slot: Rect2i = slots[next_slot]
						next_slot += 1
						# blit, not blend: an UNBASED copy, so the gaps between the logs stay
						# transparent and the prop material scissors them out.
						ground.blit_rect(source_image, region, own_slot.position)
						own_uv = _uv_rect(own_slot, atlas_size)
					if edges & ~own_edges != 0:
						var face_slot: Rect2i = slots[next_slot]
						next_slot += 1
						ground.blit_rect(_prop_side(rng, shape, palette, face_slot.size, 1, kind),
								Rect2i(Vector2i.ZERO, face_slot.size), face_slot.position)
						face_uv = _uv_rect(face_slot, atlas_size)
					mesh = _plane_mesh(prop_mat, edges, own_edges, own_uv, face_uv)
				else:
					var side_slot: Rect2i = slots[next_slot]
					var top_slot: Rect2i = slots[next_slot + 1]
					next_slot += 2
					ground.blit_rect(_prop_side(rng, shape, palette, side_slot.size, _facets_of(shape), kind),
							Rect2i(Vector2i.ZERO, side_slot.size), side_slot.position)
					ground.blit_rect(_prop_top(rng, shape, palette, top_slot.size),
							Rect2i(Vector2i.ZERO, top_slot.size), top_slot.position)
					# The mesh is sized to the art's OPAQUE BOUNDS, not to the tile: a rock is 32%
					# clear (measured in #250), so a cell-wide cube would be a box of mostly air.
					mesh = _prop_mesh(shape, prop_mat, _uv_rect(top_slot, atlas_size), side_slot,
							atlas_size, _opaque_bounds(source_image, region), patch, rng)
				if mesh == null:
					return -1
				_add_item(ml, next_id, BoardMirror.prop_item_name(source_id, coords), mesh)
				next_id += 1
				props += 1
			# Only GROUND tiles are worth reporting now: an open prop is expected (it stands up
			# and its art never reaches a top face), while an open ground tile is the surprising
			# case -- it is being based over a kind colour that nobody chose deliberately.
			# This one really is stands_up and not the bake predicate above: a TUFT tile is baked,
			# but it already carries an authored shape, so it is not a CANDIDATE for one.
			var clear := _transparent_fraction(source_image, region)
			if not stands_up and clear >= HOLE_FRACTION:
				translucent.append("%d/%d:%d (%d%%)" % [source_id, coords.x, coords.y, roundi(clear * 100.0)])

		# Written to disk and REFERENCED, never embedded (#540). An embedded atlas is an Image
		# sub-resource behind an ImageTexture, and ImageTexture.set_image() keeps no reference to
		# the Image it is handed -- get_image() rebuilds an anonymous one off the RenderingServer --
		# so the parsed sub-resource id dies on every load and the next save mints a fresh one.
		# Only an ext_resource survives a save, and only a Texture2D with a resource_path is one.
		#
		# Its .import is AUTHORED and committed: the default detect_3d/compress_to would re-import
		# to VRAM compression WITH MIPMAPS the first time it rendered, and mipmaps on an atlas bleed
		# neighbouring tiles into each other at distance -- the one thing the half-texel UV inset
		# cannot fix. Art/LookDev/grass_top.png.import is what that looks like when it is not pinned.
		var composited := _write_atlas(ground, source_id)
		if composited == null:
			return -1
		atlas_mat.albedo_texture = composited
		prop_mat.albedo_texture = composited

	var added := next_id - FIRST_TILE_ITEM
	print("Tileset items %d..%d (%d ground + %d prop) from %s" \
			% [FIRST_TILE_ITEM, next_id - 1, added - props, props, TILESET_PATH])
	if not translucent.is_empty():
		# A report, not an error. A GROUND tile this open is a sprite on an empty field wearing a
		# kind colour behind it -- either it wants a prop_shape authored, or its base was never chosen.
		print("  mostly-open GROUND tiles (%d) (candidates for prop_shape): %s" \
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


# The composed atlas as something ResourceSaver will write as an ext_resource -- which means a
# Texture2D carrying a resource_path, which means the PNG on disk. Writes it, hands back the
# IMPORTED texture.
#
# REFUSES rather than returning a stale one: load() serves whatever the last import pass produced,
# so an atlas whose pixels have just changed would pair THIS run's UVs with the PREVIOUS run's art
# -- every UV in the library correct about a texture nobody can see. Comparing the two is one
# memcmp, and it is the only thing here that can catch it.
func _write_atlas(ground: Image, source_id: int) -> Texture2D:
	var path := "%s/%s" % [ART_DIR, ATLAS_NAME % source_id]
	var err := ground.save_png(path)
	if err != OK:
		push_error("Failed to write %s (error %d)" % [path, err])
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("%s is not imported yet -- run --import, then rerun --meshlib." % path)
		return null
	var imported := _rgba(tex)
	if imported == null or imported.get_data() != ground.get_data():
		push_error("%s no longer matches its import -- run --import, then rerun --meshlib." % path)
		return null
	return tex


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
	# BACK, i.e. Godot's own default, since #559. It was DISABLED from the Stage 0 bootstrap (#203)
	# — set before the thin PLANE slabs and the open-shell cap existed, so it was never chosen for
	# them. A solid board is mostly interior, and drawing both sides meant shading every buried face
	# and putting two of them, not one, into the depth tie at each cell border.
	#
	# What it costs is that an OPEN shell now reads as a hole rather than as its own inside surface.
	# _form_mesh ships one on purpose (no bottom quad), so the claim that keeps it safe — its opening
	# is exactly the footprint the block below covers — is load-bearing now instead of merely true,
	# and test_a_cap_opening_lies_on_the_block_top pins it.
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	return mat


func _add_item(ml: MeshLibrary, id: int, item_name: String, mesh: Mesh) -> void:
	ml.create_item(id)
	ml.set_item_name(id, item_name)
	ml.set_item_mesh(id, mesh)


# A box: surface 0 = top (terrain face), surface 1 = sides + bottom.
# The UV rects default to the whole texture (the Kind blocks, whose textures are one
# tile each); an atlas-backed item passes the tile's own region instead.
# `size`/`center_y` default to ONE ROW of ground centred on the origin, which is what every GROUND
# item is. That row is half a cell tall since #427 slice 2 — the mirror's vertical index counts
# height UNITS now, so a full-cell block would overlap the row above it and a column would be drawn
# twice as tall. A prop (#264) passes its measured size and lifts the box so its BASE sits at
# y = 0, because BoardMirror plants it on the cell's top face rather than inside the cell.
#
# THE SIDES STOP SHORT OF THE TOP PLANE, and the gap is closed by a RIM wearing the TOP material
# (#559). A side quad used to run from `up`, so at every cell border four surfaces met along one
# line — this block's top face, the neighbour's, and both blocks' buried sides — and a pixel centre
# landing on it could be won by the side. At an axis-aligned yaw a whole row of those borders lands
# on one scanline, which is how a hairline of dirt drew itself across the board.
#
# The rim is not decoration and not an epsilon nudge: dropping the sides ALONE would leave a
# BoardSpace.SIDE_RIM-tall band of nothing at every real cliff crest, and with back faces culled a
# ray entering there passes through the block and out — a hole. The rim closes the shell, and
# because it wears the top art the surface still meeting the neighbour at the border is the GROUND
# rather than the dirt under it, so a residual tie there is invisible rather than brown.
#
# `rim` is 0 for a PROP: it stands alone on a cell instead of tiling with neighbours, so it has no
# border to tie at, and a zero-height rim would only add degenerate triangles.
#
# The top face keeps its FULL extent either way. Two things lean on that: BoardSpace.CELL_SIZE has
# to keep agreeing with the authored GridMap cell_size, and _form_mesh's open shell is safe only
# while the block below covers the whole footprint its opening sits in.
func _block_mesh(top_mat: Material, side_mat: Material,
		top_uv := Rect2(0, 0, 1, 1), side_uv := Rect2(0, 0, 1, 1),
		size := Vector3(1.0, BoardSpace.ROW_HEIGHT, 1.0), center_y := 0.0,
		rim := BoardSpace.SIDE_RIM) -> ArrayMesh:
	var h := size * 0.5
	var up := center_y + h.y
	var down := center_y - h.y
	var brim := up - rim   # where the side material starts, and the rim leaves off
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(top_mat)
	_quad(st, Vector3(-h.x, up, -h.z), Vector3(h.x, up, -h.z),
			Vector3(h.x, up, h.z), Vector3(-h.x, up, h.z), Vector3.UP, top_uv)
	# The rim: the same four walls the side surface draws, in miniature and in the ground's own art.
	# Same winding and outward normals, so it lights as the wall it caps rather than as a lip.
	if rim > 0.0:
		_quad(st, Vector3(-h.x, up, h.z), Vector3(h.x, up, h.z),
				Vector3(h.x, brim, h.z), Vector3(-h.x, brim, h.z), Vector3.BACK, top_uv)      # south
		_quad(st, Vector3(h.x, up, -h.z), Vector3(-h.x, up, -h.z),
				Vector3(-h.x, brim, -h.z), Vector3(h.x, brim, -h.z), Vector3.FORWARD, top_uv) # north
		_quad(st, Vector3(h.x, up, h.z), Vector3(h.x, up, -h.z),
				Vector3(h.x, brim, -h.z), Vector3(h.x, brim, h.z), Vector3.RIGHT, top_uv)     # east
		_quad(st, Vector3(-h.x, up, -h.z), Vector3(-h.x, up, h.z),
				Vector3(-h.x, brim, h.z), Vector3(-h.x, brim, -h.z), Vector3.LEFT, top_uv)    # west
	st.commit(mesh)

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(side_mat)
	_quad(st, Vector3(-h.x, brim, h.z), Vector3(h.x, brim, h.z),
			Vector3(h.x, down, h.z), Vector3(-h.x, down, h.z), Vector3.BACK, side_uv)      # south
	_quad(st, Vector3(h.x, brim, -h.z), Vector3(-h.x, brim, -h.z),
			Vector3(-h.x, down, -h.z), Vector3(h.x, down, -h.z), Vector3.FORWARD, side_uv) # north
	_quad(st, Vector3(h.x, brim, h.z), Vector3(h.x, brim, -h.z),
			Vector3(h.x, down, -h.z), Vector3(h.x, down, h.z), Vector3.RIGHT, side_uv)     # east
	_quad(st, Vector3(-h.x, brim, -h.z), Vector3(-h.x, brim, h.z),
			Vector3(-h.x, down, h.z), Vector3(-h.x, down, -h.z), Vector3.LEFT, side_uv)    # west
	_quad(st, Vector3(-h.x, down, h.z), Vector3(h.x, down, h.z),
			Vector3(h.x, down, -h.z), Vector3(-h.x, down, -h.z), Vector3.DOWN, side_uv)    # bottom
	st.commit(mesh)
	return mesh


# #263's oriented plane: one HALF-LENGTH slab per authored edge, running from the cell centre out to
# that edge. A straight piece is two collinear halves -- one wall -- and a corner is two perpendicular
# ones -- an L. One rule, no corner special case, and it falls out that each half wears the MATCHING
# half of its tile's art, so a straight run reassembles the whole sprite un-squashed.
#
# Which slabs wear the tile's OWN sprite is `own_edges`, a mask, and every other slab wears the
# generated face. It was the AXIS until #554 (east-west own, north-south generated), which is a fact
# about how this sheet draws a PALISADE rather than a fact about walls -- see
# GridUtils.plane_own_art_edges. Its own builder rather than a widened _block_mesh, which centres on
# the origin and takes one UV for all five non-top faces -- a half-slab needs neither.
#
# Every face of a slab takes the same rect: the narrow ends and the top are a PLANE_THICKNESS sliver,
# and reserving atlas patches to dress 3 pixels would cost more than it could show.
func _plane_mesh(mat: Material, edges: int, own_edges: int, own_uv: Rect2,
		generated_uv: Rect2) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var half := PLANE_THICKNESS * 0.5
	var built := 0
	for edge: GridUtils.WallEdge in WALL_EDGE_STEPS:
		if edges & edge == 0:
			continue
		var step: Vector3 = WALL_EDGE_STEPS[edge]
		var lo: Vector3
		var hi: Vector3
		if absf(step.z) > 0.5:
			lo = Vector3(-half, 0.0, minf(step.z * 0.5, 0.0))
			hi = Vector3(half, PLANE_HEIGHT, maxf(step.z * 0.5, 0.0))
		else:
			lo = Vector3(minf(step.x * 0.5, 0.0), 0.0, -half)
			hi = Vector3(maxf(step.x * 0.5, 0.0), PLANE_HEIGHT, half)
		# Own art is split so a straight run reassembles the sprite un-squashed; a generated face is
		# one patch per tile, so both its slabs take it whole. _uv_half is EAST/WEST-shaped because
		# own_edges is EW-or-nothing today -- a north-south own art would need a z twin.
		var uv: Rect2 = _uv_half(own_uv, step.x > 0.0) if (edge & own_edges) != 0 else generated_uv
		_box(st, lo, hi, uv)
		built += 1
	if built == 0:
		push_error("A PLANE tile authored no wall_edges — it would render as nothing")
		return null
	st.commit(mesh)
	return mesh


# An axis-aligned box between two corners, every face wearing one rect. Same face order, winding and
# normals as _block_mesh, which is the point of writing it out rather than sharing a helper: the two
# differ only in that this one is not centred on the origin.
func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, uv: Rect2) -> void:
	_quad(st, Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z),
			Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.UP, uv)          # top
	_quad(st, Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z),
			Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3.BACK, uv)        # south
	_quad(st, Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
			Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3.FORWARD, uv)     # north
	_quad(st, Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z),
			Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3.RIGHT, uv)       # east
	_quad(st, Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z),
			Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, lo.y, lo.z), Vector3.LEFT, uv)        # west
	_quad(st, Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z),
			Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3.DOWN, uv)        # bottom


# The east or west half of a UV rect — the half of the sprite that belongs to that half-slab.
func _uv_half(uv: Rect2, east: bool) -> Rect2:
	var w := uv.size.x * 0.5
	return Rect2(Vector2(uv.position.x + (w if east else 0.0), uv.position.y), Vector2(w, uv.size.y))


# A wedge `climb` height-units tall: high edge at -Z falling to the row's floor at +Z. Slope face
# wears the terrain texture; GridMap orientation (yaw steps) points the high side at the upper level.
# Both UVs default to the whole texture (the Stage-0 dirt_ramp, whose materials are one tile each);
# an atlas-backed wedge passes the tile's own regions instead — the same pair _block_mesh already
# takes, so a ramp wears the ground painted on it (#340).
#
# The CLIMB is a parameter since #427 slice 2 (it was a fixed 45 degrees): a wedge is placed on the
# row directly above its cell's surface, so its base sits at that row's FLOOR whatever it climbs to,
# and the slope normal has to follow the pitch or a gentle ramp lights like a steep one.
#
# side_uv is NOT optional in practice, and shipping it as a default cost a bug: a WATER tile wears
# its own surface down the sides (side_mat is the composited atlas, not the one-tile dirt strip), so
# an unpassed side_uv mapped the ENTIRE tilesheet onto every water slope. Whenever side_mat can be
# the atlas, side_uv has to travel with it.
# The corner heights a shape's mesh is CUT in, at this climb -- Terrain's own canonical orientation,
# which is the anchor BoardMirror._form_orientation measures every yaw from. Asked of Terrain rather
# than written out here: the generator and the mirror must agree about which way an authored cap
# faces, and a second table would be the place they stop agreeing.
func _canonical_corners(form: Terrain.Form, climb: int) -> Vector4i:
	return Terrain.corners_of_form(0, Terrain.CANONICAL_MASKS[form], climb)


func _form_mesh(corners: Vector4i, top_mat: Material, side_mat: Material,
		top_uv := Rect2(0, 0, 1, 1), side_uv := Rect2(0, 0, 1, 1)) -> ArrayMesh:
	var lo := -BoardSpace.ROW_HEIGHT * 0.5
	# The four corners in the CLOCKWISE order Terrain packs them (NW, NE, SE, SW), which is also the
	# winding the top face and every side wall use -- so a wall is simply two consecutive corners.
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var height := [corners.x, corners.y, corners.z, corners.w]
	var top: Array[Vector3] = []
	for i in 4:
		top.append(Vector3(uv[i].x - 0.5, lo + float(height[i]) * BoardSpace.ROW_HEIGHT,
				uv[i].y - 0.5))

	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(top_mat)
	# THE SURFACE, SPLIT THE WAY Terrain.height_at_uv SPLITS IT. Not "the same rule as" -- the same
	# CALL: the diagonal is asked of the function the rules and the sprite placement read, so the
	# drawn cap and the queried height cannot disagree. They differ only in the cell's interior, and
	# only by up to a quarter of the climb, which is exactly the amount that would float a unit.
	#
	# A CAP DRAWS NOTHING IN ITS OWN FLOOR PLANE. That plane already belongs to the BLOCK underneath
	# -- _write_column writes one before placing any cap -- so anything the cap puts there is a second
	# copy of a face already being drawn, coplanar to the float, and the pair fights.
	#
	# THREE faces live down there and all three are now declined: the side wall of an edge whose two
	# corners are both low (the loop below, which has always skipped it), the bottom quad (deleted,
	# see there), and this top triangle. Only an OUTER corner has such a triangle -- three corners low
	# -- which is exactly why the artefact appeared on corner tiles and never on a wedge, whose low
	# side is an EDGE with no area, nor on an inner corner, whose flat region is at its HIGH plane.
	if corners.y == corners.w:
		_surface_tri(st, top, uv, [0, 1, 3], top_uv, height)   # NW, NE, SW
		_surface_tri(st, top, uv, [1, 2, 3], top_uv, height)   # NE, SE, SW
	else:
		_surface_tri(st, top, uv, [0, 1, 2], top_uv, height)   # NW, NE, SE
		_surface_tri(st, top, uv, [0, 2, 3], top_uv, height)   # NW, SE, SW
	st.commit(mesh)

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(side_mat)
	# One wall per edge, from that edge's two corner heights down to the row floor. A wall whose two
	# corners both sit ON the floor has no area and is skipped rather than emitted degenerate -- the
	# oldest of the three floor-plane refusals above, and the one the other two were derived from.
	for i in 4:
		var next := (i + 1) % 4
		if height[i] == 0 and height[next] == 0:
			continue
		var floor_here := Vector3(top[i].x, lo, top[i].z)
		var floor_next := Vector3(top[next].x, lo, top[next].z)
		# The edge's own midpoint, seen from the cell centre -- FORWARD, RIGHT, BACK, LEFT in turn,
		# derived rather than tabled so the four walls cannot drift from the corner order above.
		var outward := Vector3(top[i].x + top[next].x, 0.0, top[i].z + top[next].z).normalized()
		_quad(st, top[i], floor_here, floor_next, top[next], outward, side_uv)
	# NO BOTTOM QUAD. It used to close the mesh at `lo`, which is the block-top plane -- so it fought
	# whatever was drawn there, and being DOWN-facing it loses to nothing and wins as a HOLE: a
	# back-facing polygon rasterises to no pixels at all, so where it took the depth test you saw
	# straight through the board. That is what the dev's screenshots showed once the top triangle
	# above stopped competing with it for the same plane.
	#
	# The cap is an open shell now, and what closes it is the block below: its opening is exactly the
	# footprint that block's top face covers, so there is no angle the inside can be seen from. Safe
	# to omit rather than merely invisible -- meshlib items carry no collision shape and no navmesh,
	# so nothing but the rasteriser ever reads this geometry.
	st.commit(mesh)
	return mesh


# One triangle of a cell's top surface: positions and UVs both indexed off the clockwise corner
# order, so the art lands on the ground the same way whichever diagonal the cell is split on.
#
# DECLINES a triangle lying entirely on the floor: that is the block underneath's own top face, at
# the same plane and in the same art, and drawing it twice is a z-fight rather than a surface. The
# side walls have always been skipped on the same test one loop down -- one rule, two places it
# applies. `heights` is the cap's four corner heights in the caller's clockwise order.
func _surface_tri(st: SurfaceTool, top: Array[Vector3], uv: Array, order: Array,
		uv_rect: Rect2, heights: Array) -> void:
	if heights[order[0]] == 0 and heights[order[1]] == 0 and heights[order[2]] == 0:
		return
	var a: Vector3 = top[order[0]]
	var b: Vector3 = top[order[1]]
	var c: Vector3 = top[order[2]]
	var normal := (b - a).cross(c - a).normalized()
	if normal.y < 0.0:
		normal = -normal   # a cap's surface always faces up; the winding is the quad's, not a guess
	for i in 3:
		var corner: int = order[i]
		st.set_normal(normal)
		st.set_uv(uv_rect.position + (uv[corner] as Vector2) * uv_rect.size)
		st.add_vertex(top[corner])


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


# _tri went with #427 slice 3. It existed for the wedge's two triangular side walls, and a cap's
# walls are now trapezoids built from two corner heights -- degenerating to that triangle on their
# own when one of the two sits on the floor.


# --- Solid props (#264) ------------------------------------------------------

# How many SIDE FACES a shape's geometry has, and therefore how many independent slices its side
# texture is cut into. ONE table (#274): the mesh builder and the texture generator both read it, and
# if they disagreed the art would land on the wrong facets. A shape absent here is a box, whose four
# sides are congruent and share one whole-rect slice.
const PRISM_FACETS: Dictionary[GridUtils.PropShape, int] = {
	GridUtils.PropShape.FACETED: 6,
	GridUtils.PropShape.ROUND: 10,
}


func _facets_of(shape: GridUtils.PropShape) -> int:
	return PRISM_FACETS.get(shape, 1)


# How thick a wall stands and how tall, as fractions of a cell (#263). FEEL values, and there is no
# runtime knob for the same reason PRISM_PROFILE has none: the mesh is baked, so a slider would move
# nothing. The height is the measured extent of this sheet's face-on fence art (13 of its 16 rows) and
# is applied to EVERY plane rather than read per tile -- a north-south piece's art is a foreshortened
# RUN, so its 16-row extent measures the wrong thing, and reading it would step a pen's side walls
# 3/16 of a cell above its corners. The thickness is chosen, not measured: a palisade log is about
# 7px across and rendering that literally reads as a barricade.
const PLANE_THICKNESS := 3.0 / 16.0
const PLANE_HEIGHT := 13.0 / 16.0

# The world direction of each authored edge. Board -Z is north, the same convention
# BoardMirror.RAMP_MESH_HIGH_SIDE states for the ramp wedge. Kept beside the builder that consumes it
# rather than on the enum, because turning an edge into an offset is mesh knowledge.
const WALL_EDGE_STEPS: Dictionary[GridUtils.WallEdge, Vector3] = {
	GridUtils.WallEdge.NORTH: Vector3(0, 0, -1),
	GridUtils.WallEdge.EAST: Vector3(1, 0, 0),
	GridUtils.WallEdge.SOUTH: Vector3(0, 0, 1),
	GridUtils.WallEdge.WEST: Vector3(-1, 0, 0),
}


# A prism's silhouette, as rings of (height fraction, radius fraction) bottom to top.
#
# ROUND came back for the barrel, which was still authored `pot` when the dev said this (2026-08-15):
# *"the pots don't really look like pots, the geometry needs to come back to a central point on the
# bottom to make them look round."* Two rings made a truncated cone standing on its widest part,
# which is the opposite of a vessel — narrow at the foot, widest at the belly, drawn back in at the
# rim.
#
# FACETED got the same treatment for the rock (#323): two rings is one straight run of facets from a
# wide base to a flat top disc, which reads as a pillar however much the footprint is jittered. It is
# now widest BELOW its crown and drawn back in above it.
#
# No radius may exceed 1.0 and the top ring must sit at height 1.0 — the mesh is inscribed in its own
# art's footprint and its cap defines its height, and both are asserted.
#
# These numbers are a FEEL value, not a measurement. Nothing pins them, and there is no runtime knob
# because the mesh is baked — rounder is a line here plus a regenerate.
const PRISM_PROFILE: Dictionary[GridUtils.PropShape, Array] = {
	GridUtils.PropShape.FACETED: [
		Vector2(0.00, 0.78), Vector2(0.28, 1.00), Vector2(0.62, 0.94),
		Vector2(0.86, 0.72), Vector2(1.00, 0.36),
	],
	GridUtils.PropShape.ROUND: [
		Vector2(0.0, 0.32), Vector2(0.18, 0.80), Vector2(0.50, 1.0),
		Vector2(0.80, 0.78), Vector2(1.0, 0.66),
	],
}


# How irregular a prism is, as three fractions — FACET, RING, ANGLE.
#
#   FACET  a radius wobble drawn once per facet, so the footprint is an irregular polygon.
#   RING   a further wobble drawn per facet PER RING. This is what stops a facet's edges running
#          dead vertical, and it deliberately reverses #279's "draw it once per angle so a jittered
#          facet stays a straight facet" — a straight vertical edge is exactly what made the rock
#          read as a column (#323).
#   ANGLE  how far a facet's angle may slip, as a share of the even step, so the facets are not
#          evenly spaced around the axis.
#
# ROUND takes none of it: a barrel is turned, and irregularity is the opposite of what it wants.
# FEEL values, and baked, so no runtime knob — the same call PRISM_PROFILE records.
const PRISM_JITTER: Dictionary[GridUtils.PropShape, Vector3] = {
	GridUtils.PropShape.FACETED: Vector3(0.30, 0.18, 0.10),
	GridUtils.PropShape.ROUND: Vector3.ZERO,
}


# How tall a FACETED lump stands, as a fraction of its own footprint width (#323).
#
# Every other solid takes its height from the art's opaque vertical extent, and that is right only
# where the art is drawn UPRIGHT — a crate and a barrel are. The rock sprite is a top-down cluster of
# boulders, so its 16 rows are mostly DEPTH into the cell; read as height they build a thing taller
# than it is wide, which is the pillar the dev saw. A shape whose art cannot answer "how tall" has to
# declare it. Same reading error as #263's foreshortened fence and #280's flowerbed.
const FACETED_HEIGHT_OF_WIDTH := 0.64


# The generated patches ONE tile needs, in the order the walk consumes them. Both the pre-pass that
# sizes the atlas and the walk that fills it call this, so they cannot disagree -- #274 collapsed a
# counter consulted twice into one function for exactly that reason, and #263 is why it had to become
# a function of the tile rather than of the shape: a plane's count depends on its authored edges.
#
# A prism's side run is one patch PER FACET, and that is a resolution requirement rather than a
# convenience: slicing a single 16px patch into a barrel's ten facets would leave 1.6 texels each.
func _patch_widths_for(data: TileData) -> Array[int]:
	var shape := GridUtils.prop_shape_of(data)
	if not GridUtils.SOLID_SHAPES.has(shape):
		return []
	if shape == GridUtils.PropShape.PLANE:
		# Up to two, and which ones depends on which of this piece's edges are drawn face-on in the
		# sheet (GridUtils.plane_own_art_edges). Own art needs a patch even though it is already in
		# the atlas, because the ground square under a standing tile holds only its BASE (the sprite
		# is deliberately not baked there, or the fence would render twice) and an UNBASED copy is
		# the only place the gaps between the logs survive. Every OTHER edge shares ONE generated
		# patch -- masonry has no face-on art at all and takes exactly this branch.
		# No top patch either way: a slab's top is a PLANE_THICKNESS sliver.
		var edges := GridUtils.wall_edges_of(data)
		var own_edges := GridUtils.plane_own_art_edges(data)
		var widths: Array[int] = []
		if (edges & own_edges) != 0:
			widths.append(1)   # the tile's own sprite, copied unbased
		if (edges & ~own_edges) != 0:
			widths.append(1)   # the generated face
		return widths
	return [_facets_of(shape), 1]   # side run, then top


# Measured ahead of the walk because the atlas has to be allocated at its finished height before the
# first UV inside the walk is taken.
func _solid_patch_widths(atlas: TileSetAtlasSource) -> Array[int]:
	var widths: Array[int] = []
	for coords in _sorted_tile_coords(atlas):
		if atlas.get_tile_size_in_atlas(coords) != Vector2i.ONE:
			continue
		widths.append_array(_patch_widths_for(atlas.get_tile_data(coords, 0)))
	return widths


# Lay the extra patches out in rows below the source art, wrapping when a run will not fit.
# Returns {"slots": Array[Rect2i], "rows": int}.
#
# ONE function rather than a counter consulted twice: the row count is needed before the atlas is
# allocated and the rects are needed inside the walk, and two pieces of arithmetic kept in step by
# hand is exactly how a UV ends up pointing at the wrong patch.
func _pack_slots(widths: Array[int], columns: int, patch: Vector2i, base_y: int) -> Dictionary:
	var slots: Array[Rect2i] = []
	var col := 0
	var row := 0
	for w: int in widths:
		if w > columns:
			push_error("A %d-patch run does not fit an atlas %d patches wide" % [w, columns])
			return {}
		if col + w > columns:
			col = 0
			row += 1
		slots.append(Rect2i(Vector2i(col * patch.x, base_y + row * patch.y),
				Vector2i(w * patch.x, patch.y)))
		col += w
	var rows := 0
	if not slots.is_empty():
		rows = row + 1
	return {"slots": slots, "rows": rows}


# The ground a TUFT's plants stand on (#280): the tile's own field colour, sparsely speckled in its
# own other colours. GENERATED rather than borrowed from the plain-grass tile, because "which tile
# is this one's base?" is a relationship the content does not declare (Law #4) -- and generated in
# MEASURED colours rather than in the kind base's, because the kind base is a muted olive while the
# sheet's grass is a bright green, so a tuft cell would read as a patch among its neighbours.
#
# The field colour is BoardMirror's, the same static the mirror keys OUT to cut the plants from the
# tile -- so the plants cannot end up standing on a field they were not cut from.
#
# Sparse on purpose: a speckle every 25 pixels or so. This is ground, and the interest on a tuft
# cell is meant to come from the things standing on it.
func _tuft_ground(rng: RandomNumberGenerator, source_image: Image, region: Rect2i) -> Image:
	var field := BoardMirror.background_colour(source_image, region)
	var palette := _palette_of(source_image, region)
	var speckles: Array[Color] = []
	for shade: Color in palette:
		if shade != field:
			speckles.append(shade)
	var img := Image.create_empty(region.size.x, region.size.y, false, Image.FORMAT_RGBA8)
	img.fill(field)
	if speckles.is_empty():
		return img          # a single-colour tile has nothing to speckle WITH; flat is honest
	for i in maxi(1, region.size.x * region.size.y / 25):
		img.set_pixel(rng.randi_range(0, region.size.x - 1), rng.randi_range(0, region.size.y - 1),
				speckles[rng.randi_range(0, speckles.size() - 1)])
	return img


# The art's opaque extent inside its tile, in tile-local pixels. This is what sizes a prop's mesh:
# a sprite drawn small in its cell should become a small object, not a cell-wide box of air.
# BoardMirror owns the rule because it asks the same question at runtime to PLANT a billboard --
# one answer, two stacks, the shape tile_item_name already has.
func _opaque_bounds(image: Image, region: Rect2i) -> Rect2i:
	return BoardMirror.opaque_bounds(image, region)


# How many shades a generated face is allowed to use, and how coarsely colours are bucketed when
# looking for them. Five bits per channel groups a pixel-artist's near-identical shades together
# without merging the highlight into the midtone.
const PALETTE_SHADES := 4
const PALETTE_BITS := 5


# The sprite's DOMINANT colours, darkest first. Every generated face is painted only from these, so
# a prop reads as the same object the 2D board shows even though none of its art is the sprite —
# which is what keeps this from contradicting #250 (the 3D shows the GAME's tiles).
#
# Dominant, not mean (#274): averaging a rock's greys returns one flat grey, so every face came out
# a wash and the shading carried no shape. A pixel artist's shade ramp is already in the art; this
# reads it back rather than inventing one.
func _palette_of(image: Image, region: Rect2i) -> Array[Color]:
	var counts: Dictionary[int, int] = {}
	var sums: Dictionary[int, Vector3] = {}
	var shift := 8 - PALETTE_BITS
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var c := image.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var key := ((int(c.r8) >> shift) << (PALETTE_BITS * 2)) \
					| ((int(c.g8) >> shift) << PALETTE_BITS) | (int(c.b8) >> shift)
			counts[key] = counts.get(key, 0) + 1
			sums[key] = sums.get(key, Vector3.ZERO) + Vector3(c.r, c.g, c.b)
	if counts.is_empty():
		var grey := Color(0.5, 0.5, 0.5)
		return _pad_palette([grey])

	var keys: Array[int] = counts.keys()
	keys.sort_custom(func(a: int, b: int) -> bool: return counts[a] > counts[b])
	var shades: Array[Color] = []
	for i in mini(PALETTE_SHADES, keys.size()):
		var key: int = keys[i]
		var mean: Vector3 = sums[key] / float(counts[key])
		shades.append(Color(mean.x, mean.y, mean.z))
	shades.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())
	return _pad_palette(shades)


# A sprite may genuinely hold fewer distinct shades than a face wants. Extend the ramp off its own
# ends rather than refusing, so every generator can index PALETTE_SHADES entries unconditionally.
func _pad_palette(shades: Array[Color]) -> Array[Color]:
	while shades.size() < PALETTE_SHADES:
		if shades.size() % 2 == 0:
			shades.push_front(shades[0].darkened(0.22))
		else:
			shades.append(shades[shades.size() - 1].lightened(0.16))
	return shades


# The face one 3/4 drawing cannot supply. One pattern per shape family, because the pattern IS the
# object's identity read from above: planks on a crate lid, speckle on a boulder, rings on a
# barrel's head. Flat-lit and nearest-filtered like every other texture here.
func _prop_top(rng: RandomNumberGenerator, shape: GridUtils.PropShape, palette: Array[Color],
		size: Vector2i) -> Image:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var center := Vector2(size) * 0.5
	var plank := maxi(3, size.y / 4)
	for y in size.y:
		for x in size.x:
			var shade := 2
			match shape:
				GridUtils.PropShape.CUBE:
					shade = 0 if y % plank == 0 else (3 if (y / plank) % 2 == 0 else 2)
				GridUtils.PropShape.ROUND:
					var d := (Vector2(x, y) + Vector2(0.5, 0.5) - center).length()
					var rim := float(mini(size.x, size.y)) * 0.5
					shade = 1 if d > rim * 0.62 else (2 if d > rim * 0.34 else 3)
				_:
					shade = 2
			img.set_pixel(x, y, _speck(rng, palette, shade))
	return img


# The faces #264 could not supply, because it wore the SPRITE there and a sprite cannot wrap (#274).
# Laid out as one strip of `facets` cells, which _prism_mesh then slices one cell per facet:
#   CUBE     one cell, four congruent sides — vertical planks between end rails
#   ROUND    a continuous band, one stave per facet, so it wraps the pot exactly once
#   FACETED  one INDEPENDENT cell per facet, each a different stone tone, so the lump reads faceted
#   PLANE    a palisade — upright logs with a gap between them, capped by a rail (#263) — or, for a
#            ROCK wall, a running-bond MASONRY course (#554)
# ROUND and FACETED are the same UV rule; only the texture differs, which is the point. PLANE keeps
# its own arm rather than borrowing ROUND's staves, which it happens to resemble: the pattern IS the
# object's identity here, and welding a fence to a barrel would make either one untunable alone.
#
# PLANE is the one shape that forks on KIND, and only because a wall is the one form the sheet draws
# in more than one material. Kind is already what this generator asks for what a tile is MADE of
# (a ROCK block wears stone down its sides), so it answers here too rather than growing a column.
func _prop_side(rng: RandomNumberGenerator, shape: GridUtils.PropShape, palette: Array[Color],
		size: Vector2i, facets: int, kind: Terrain.Kind) -> Image:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var cell := maxi(1, size.x / maxi(1, facets))
	var stave := maxi(2, cell / 2)
	var rail := maxi(1, size.y / 6)
	var course := maxi(2, size.y / 4)      # rows per masonry course
	var brick := maxi(3, size.x / 2)       # a brick's length along the wall
	for x in size.x:
		# Which facet this column belongs to, and how far along that facet it sits — FACETED reads
		# the first (a whole cell is one tone), ROUND and CUBE read the second.
		var facet := mini(facets - 1, x / cell)
		for y in size.y:
			var shade := 2
			match shape:
				GridUtils.PropShape.CUBE:
					if y < rail or y >= size.y - rail:
						shade = 1                      # top and bottom rails
					elif x % stave == 0:
						shade = 0                      # the gap between planks
					else:
						shade = 3 if (x / stave) % 2 == 0 else 2
				GridUtils.PropShape.ROUND:
					if y < rail:
						shade = 1                      # the lip
					elif x % stave == 0:
						shade = 1
					else:
						shade = 3 if (x / stave) % 2 == 0 else 2
				GridUtils.PropShape.PLANE when kind == Terrain.Kind.ROCK:
					# A running bond: mortar between courses, and vertical joints offset half a
					# brick every other course so nothing lines up into a column.
					var row := y / course
					var offset: int = 0 if row % 2 == 0 else brick / 2
					if y % course == 0:
						shade = 0                      # the mortar line
					elif (x + offset) % brick == 0:
						shade = 0                      # the vertical joint
					else:
						shade = 3 if (row + (x + offset) / brick) % 2 == 0 else 2
				GridUtils.PropShape.PLANE:
					# A gap between logs, not a seam: the darkest shade, so the wall reads as
					# see-through even though the face itself is opaque.
					if x % stave == 0:
						shade = 0
					elif y < rail:
						shade = 3                      # the rounded, lit tops
					else:
						shade = 2 if (x / stave) % 2 == 0 else 1
				_:
					# A tone per facet, walked so neighbours differ; the real sun does the shading,
					# so this is albedo variation only and nothing is baked in.
					shade = 1 + (facet * 2) % 3
			img.set_pixel(x, y, _speck(rng, palette, shade))
	return img


# One pixel of a generated face: a palette shade, roughened. The roughening stays INSIDE the palette
# by stepping to a neighbouring shade rather than tinting, so every pixel of every face is a colour
# the sprite actually contains.
func _speck(rng: RandomNumberGenerator, palette: Array[Color], shade: int) -> Color:
	var i := clampi(shade, 0, palette.size() - 1)
	var r := rng.randf()
	if r < 0.10:
		i = maxi(0, i - 1)
	elif r > 0.92:
		i = mini(palette.size() - 1, i + 1)
	return palette[i]


# The prop's geometry, sized by the art's opaque bounds. A tile is one cell wide by definition, so
# a pixel is 1/patch of a world unit — the same density rule the billboard props use.
# The footprint is SQUARE (depth = width): a 3/4 sprite says nothing about how deep the object is,
# so inventing a second number would be a guess dressed as a measurement.
#
# The side face arrives as a PIXEL rect rather than a UV rect (#274) so a prism can cut it per facet
# and inset each slice by its own half texel — insetting the whole strip once would leave every
# internal facet boundary sampling half a texel of its neighbour.
func _prop_mesh(shape: GridUtils.PropShape, mat: Material, top_uv: Rect2, side_px: Rect2i,
		atlas_size: Vector2, bounds: Rect2i, patch: Vector2i,
		rng: RandomNumberGenerator) -> ArrayMesh:
	var w := float(bounds.size.x) / float(patch.x)
	var h := float(bounds.size.y) / float(patch.y)
	var size := Vector3(w, h, w)
	match shape:
		GridUtils.PropShape.CUBE:
			return _block_mesh(mat, mat, top_uv, _uv_rect(side_px, atlas_size), size, h * 0.5, 0.0)
		GridUtils.PropShape.FACETED:
			# The one solid whose height is NOT the art's vertical extent -- see
			# FACETED_HEIGHT_OF_WIDTH. The footprint is still measured.
			return _prism_mesh(mat, mat, top_uv, side_px, atlas_size,
					Vector3(w, w * FACETED_HEIGHT_OF_WIDTH, w), rng, shape)
		GridUtils.PropShape.ROUND:
			return _prism_mesh(mat, mat, top_uv, side_px, atlas_size, size, rng, shape)
		_:
			return _prism_mesh(mat, mat, top_uv, side_px, atlas_size, size, rng, shape)


# A tapered prism standing on y = 0 — the faceted lump and the round pot are the same solid with
# different facet counts and jitter.
#
# Every facet takes its OWN SLICE of the side strip (#274). #264 put the whole texture on every
# facet, because the texture was the tile's sprite and a sprite cannot wrap — which is exactly what
# the dev saw: *"the rocks and the pots need it most, their sprites do not map to their models"*, a
# pot rendering as ten overlapping pots. With the strip generated, slice i is simply facet i's art,
# and whether that reads as a continuous wrap (ROUND) or as distinct stone faces (FACETED) is
# decided by the texture rather than by this loop.
func _prism_mesh(top_mat: Material, side_mat: Material, top_uv: Rect2, side_px: Rect2i,
		atlas_size: Vector2, size: Vector3,
		rng: RandomNumberGenerator, shape: GridUtils.PropShape) -> ArrayMesh:
	var sides := _facets_of(shape)
	var jitter: Vector3 = PRISM_JITTER.get(shape, Vector3.ZERO)
	# Packed on read: a PackedVector2Array literal is not a constant expression, and the packed form
	# is what makes every profile[i] a typed Vector2 rather than a Variant.
	var profile := PackedVector2Array(PRISM_PROFILE[shape])
	var facet_w := side_px.size.x / sides
	# Each slice is inset by its own half texel. Insetting the strip once instead would leave every
	# internal boundary sampling half a texel of the neighbouring facet.
	var facet_uv: Array[Rect2] = []
	for i in sides:
		facet_uv.append(_uv_rect(Rect2i(side_px.position + Vector2i(i * facet_w, 0),
				Vector2i(facet_w, side_px.size.y)), atlas_size))

	# rings[r][i] — one ring per profile entry. A facet's ANGLE and its base wobble are drawn once,
	# so the facet stays one face; the per-ring wobble on top is what tilts its edges off vertical.
	# Every factor is <= 1, which is what keeps the mesh inside the footprint its art measured.
	var rings: Array[PackedVector3Array] = []
	for r in profile.size():
		rings.append(PackedVector3Array())
	var step_angle := TAU / float(sides)
	for i in sides:
		var a := step_angle * (float(i) + rng.randf_range(-jitter.z, jitter.z))
		var wobble := 1.0 - rng.randf() * jitter.x
		for r in profile.size():
			var step := profile[r]
			var radius := wobble * (1.0 - rng.randf() * jitter.y)
			rings[r].append(Vector3(cos(a) * size.x * 0.5 * step.y * radius, step.x * size.y,
					sin(a) * size.z * 0.5 * step.y * radius))

	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(top_mat)
	# BOTH caps live on the top surface (#274 follow-up). The bottom one is invisible, both surfaces
	# share one material on a prism, and it leaves the side surface meaning exactly "the facets" —
	# which is what lets the facet-slicing test derive its count from the mesh rather than from the
	# table it is checking.
	var top_ring := rings[rings.size() - 1]
	var base_ring := rings[0]
	var apex := Vector3(0.0, size.y, 0.0)
	var foot := Vector3(0.0, base_ring[0].y, 0.0)
	for i in sides:
		var j := (i + 1) % sides
		# Increasing angle, matching the winding _block_mesh's top quad uses.
		_cap_vertex(st, apex, size, top_uv, Vector3.UP)
		_cap_vertex(st, top_ring[i], size, top_uv, Vector3.UP)
		_cap_vertex(st, top_ring[j], size, top_uv, Vector3.UP)
		_cap_vertex(st, foot, size, top_uv, Vector3.DOWN)
		_cap_vertex(st, base_ring[j], size, top_uv, Vector3.DOWN)
		_cap_vertex(st, base_ring[i], size, top_uv, Vector3.DOWN)
	st.commit(mesh)

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(side_mat)
	for i in sides:
		var j := (i + 1) % sides
		for b in profile.size() - 1:
			var lower := rings[b]
			var upper := rings[b + 1]
			# j is screen-LEFT of i seen from outside, so this is the clockwise order _quad wants.
			var normal := (lower[i] - lower[j]).cross(upper[j] - lower[j]).normalized()
			if normal.dot(lower[i] + lower[j]) < 0.0:
				normal = -normal   # the jitter can flip a degenerate face; point it outward
			_quad(st, upper[j], upper[i], lower[i], lower[j], normal,
					_band_uv(facet_uv[i], profile[b].x, profile[b + 1].x))
	st.commit(mesh)
	return mesh


# A facet's slice narrowed to one band of the profile. v runs DOWN the texture while the profile
# runs UP the mesh, so the band's top edge is the higher fraction.
func _band_uv(facet: Rect2, low: float, high: float) -> Rect2:
	return Rect2(facet.position.x, facet.position.y + facet.size.y * (1.0 - high),
			facet.size.x, facet.size.y * (high - low))


# One vertex of a cap fan, its UV taken from where the point sits in the footprint.
func _cap_vertex(st: SurfaceTool, point: Vector3, size: Vector3, uv_rect: Rect2,
		normal: Vector3) -> void:
	var uv := Vector2(clampf(0.5 + point.x / size.x, 0.0, 1.0),
			clampf(0.5 + point.z / size.z, 0.0, 1.0))
	st.set_normal(normal)
	st.set_uv(uv_rect.position + uv * uv_rect.size)
	st.add_vertex(point)
