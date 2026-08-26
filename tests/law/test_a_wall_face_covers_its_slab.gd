# THE gap #554 was: a wall you can see over, baked into the artifact and invisible to every other
# test.
#
# A PLANE's slab is dressed either with the tile's OWN sprite or with a face generated in the tile's
# colours, and which one is `GridUtils.plane_own_art_edges` (#263's answer was the AXIS, which is a
# fact about how this sheet draws a PALISADE rather than a fact about walls). Get that wrong and
# nothing anywhere goes red: the mesh is the right size, the mask reaches it, every #263 case passes
# -- and the wall renders as a ribbon floating over an invisible slab, because the art it wears is a
# PLAN of the wall's footprint rather than a picture of its face. `stone_wall_hor_top` is opaque in
# 5 of its 16 rows; the palisade the rule was written for is opaque in 13.
#
# So the rule is: WHATEVER a slab wears, it must cover the slab -- the art must be opaque over MORE
# THAN HALF its rows. Half is a definition of "mostly", not a tuned value: it is deliberately NOT
# `PLANE_HEIGHT`, which is a feel value the dev may retune, and which the palisade art happens to
# match to the row (13/16). Measured per ROW rather than per pixel because a palisade's gaps are
# vertical BY DESIGN -- see-through between the logs is the art, see-through above them is the bug.
#
# Read off the COMMITTED meshlib and the atlas THAT MESH ITSELF NAMES, because what ships is what
# must agree -- and asking the mesh for its texture is what keeps this law free of an atlas path to
# go stale.
extends GdUnitTestSuite

const MESHLIB_PATH := "res://Scenes/LookDev/lookdev_meshlib.tres"
const TILESET_PATH := "res://Resources/TestTiles.tres"

# The share of a slab's rows that must carry an opaque pixel.
const MIN_COVERED_ROWS := 0.5

var _library: MeshLibrary
var _tiles: TileSet
var _by_name: Dictionary[String, int] = {}


func before_test() -> void:
	_by_name.clear()
	_library = load(MESHLIB_PATH) as MeshLibrary
	assert_object(_library).override_failure_message(
			"the meshlib is missing or unreadable at %s" % MESHLIB_PATH).is_not_null()
	for id: int in _library.get_item_list():
		_by_name[_library.get_item_name(id)] = id
	_tiles = load(TILESET_PATH) as TileSet
	assert_object(_tiles).override_failure_message(
			"the tileset is missing or unreadable at %s" % TILESET_PATH).is_not_null()


# Every PLANE tile in the sheet, read off the tileset so an atlas swap cannot slip one past.
func _plane_tiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _tiles.get_source_count():
		var source_id := _tiles.get_source_id(s)
		var atlas := _tiles.get_source(source_id) as TileSetAtlasSource
		if atlas == null:
			continue
		for i in atlas.get_tiles_count():
			var coords := atlas.get_tile_id(i)
			var data := atlas.get_tile_data(coords, 0)
			if GridUtils.prop_shape_of(data) != GridUtils.PropShape.PLANE:
				continue
			out.append({"name": BoardMirror.prop_item_name(source_id, coords),
					"label": GridUtils.authored_tile_display_name(data)})
	return out


# The distinct atlas rects this mesh samples. Each quad wears ONE rect and `_quad` maps its four
# corners onto the quad, so ANY triangle of it spans the whole rect -- a per-triangle bounding box
# is exact, and needs no assumption about vertex order or how many slabs were built.
func _sampled_rects(mesh: Mesh, size: Vector2) -> Array[Rect2i]:
	var arrays := mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		index = arrays[Mesh.ARRAY_INDEX]
	else:
		for v in uvs.size():
			index.append(v)
	var seen: Dictionary[String, Rect2i] = {}
	for t in range(0, index.size(), 3):
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for k in 3:
			var uv: Vector2 = uvs[index[t + k]]
			lo = lo.min(uv)
			hi = hi.max(uv)
		# The UVs are inset half a texel (gen_lookdev_assets._uv_rect), so floor/ceil land back on
		# the patch's own pixel bounds.
		var from := Vector2i((lo * size).floor())
		var rect := Rect2i(from, Vector2i((hi * size).ceil()) - from)
		seen[str(rect)] = rect
	var out: Array[Rect2i] = []
	for key: String in seen:
		out.append(seen[key])
	return out


func _covered_rows(img: Image, rect: Rect2i) -> int:
	var rows := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if img.get_pixel(x, y).a >= 0.5:
				rows += 1
				break
	return rows


func test_every_wall_slab_wears_art_that_covers_it() -> void:
	var checked := 0
	for tile in _plane_tiles():
		var item_name: String = tile["name"]
		assert_bool(_by_name.has(item_name)).override_failure_message(
				"no geometry item '%s' — the meshlib is stale, regenerate it" % item_name).is_true()
		var mesh := _library.get_item_mesh(_by_name[item_name])
		var mat := mesh.surface_get_material(0) as StandardMaterial3D
		assert_object(mat).override_failure_message(
				"'%s' has no StandardMaterial3D to name its atlas" % tile["label"]).is_not_null()
		var img: Image = mat.albedo_texture.get_image()
		if img.is_compressed():
			img.decompress()
		var size := Vector2(img.get_width(), img.get_height())
		for rect in _sampled_rects(mesh, size):
			var rows := _covered_rows(img, rect)
			assert_float(float(rows) / float(maxi(1, rect.size.y))).override_failure_message(
					"'%s' dresses a slab with art opaque in %d of %d rows — a wall you can see " \
					% [tile["label"], rows, rect.size.y] + "over. Either the sheet draws that face " \
					+ "on and GridUtils.plane_own_art_edges should say so, or it does not and the " \
					+ "face must be generated").is_greater(MIN_COVERED_ROWS)
			checked += 1
	assert_int(checked).override_failure_message(
			"no PLANE tiles authored; the case is vacuous").is_greater(0)
