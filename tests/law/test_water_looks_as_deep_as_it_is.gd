# THE law #552 exists to keep: the water a tile SHOWS is the water it IS.
#
# Shallow water is ordinary ground and deep water drowns you, and the two are told apart on the
# board by their top face alone -- there is no second Kind to read (#116: "One Kind, two tiles").
# Before this the sheet painted both the identical flat blue: measured, the deep tile was one
# colour in all 256 of its pixels and the shallow tile in 242 of them. A player could not see which
# was which, and the hover card was already saying it in words.
#
# So there are two halves and each has its own case. The 3D SURFACE picks between two shader
# materials on `deep`, baked from the tile's own `walkable` flag -- the flag the rules read, which
# is what stops the render and the ruleset drifting apart. The BASE COLOUR is the tile's authored
# modulate, because that half has to reach the flat view too and a shader cannot.
#
# The last case is a wire, not a look: a global uniform is spelled in THREE places (the shader, the
# knob table, project.godot) and a misspelling in any of them is silent -- GLSL just reads zero.
extends GdUnitTestSuite

const MESHLIB_PATH := "res://Scenes/LookDev/lookdev_meshlib.tres"
const TILESET_PATH := "res://Resources/TestTiles.tres"
const SHADER_PATH := "res://Scenes/LookDev/water.gdshader"
const ATLAS_PATH := "res://Art/LookDev/ground_atlas_0.png"

var _library: MeshLibrary
var _tiles: TileSet
var _by_name: Dictionary[String, int] = {}


func before_test() -> void:
	_library = load(MESHLIB_PATH) as MeshLibrary
	assert_object(_library).override_failure_message(
			"the meshlib is missing or unreadable at %s" % MESHLIB_PATH).is_not_null()
	_tiles = load(TILESET_PATH) as TileSet
	assert_object(_tiles).override_failure_message(
			"the tileset is missing or unreadable at %s" % TILESET_PATH).is_not_null()
	_by_name.clear()
	for id: int in _library.get_item_list():
		_by_name[_library.get_item_name(id)] = id


# Every WATER tile the tileset declares, with the source it came from. Read off the TILESET rather
# than off a list here, so a water tile authored tomorrow joins these cases by existing.
func _water_tiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _tiles.get_source_count():
		var source_id := _tiles.get_source_id(s)
		var atlas := _tiles.get_source(source_id) as TileSetAtlasSource
		if atlas == null:
			continue
		for i in atlas.get_tiles_count():
			var coords := atlas.get_tile_id(i)
			if atlas.get_tile_size_in_atlas(coords) != Vector2i.ONE:
				continue
			var data := atlas.get_tile_data(coords, 0)
			if GridUtils.terrain_kind_of(data) != Terrain.Kind.WATER:
				continue
			out.append({"source": source_id, "coords": coords, "data": data, "atlas": atlas})
	return out


# Every item name that draws THIS tile's surface: its block, and the wedge per climb and shape.
func _surface_items(source_id: int, coords: Vector2i) -> PackedStringArray:
	var names := PackedStringArray([BoardMirror.tile_item_name(source_id, coords)])
	for climb: int in BoardMirror.RAMP_ITEM_NAMES:
		for form: Terrain.Form in [Terrain.Form.WEDGE, Terrain.Form.OUTER, Terrain.Form.INNER]:
			names.append(BoardMirror.ramp_item_name(source_id, coords, climb, form))
	return names


# THE wire. `deep` is not a look setting -- it is walkability, inverted, so a tile that declares
# itself wadeable cannot render as the tile that drowns you.
func test_every_water_surface_says_what_walkable_says() -> void:
	var checked := 0
	for tile: Dictionary in _water_tiles():
		var data: TileData = tile["data"]
		var want := 0.0 if GridUtils.walkable_of(data) else 1.0
		for item_name in _surface_items(tile["source"], tile["coords"]):
			assert_bool(_by_name.has(item_name)).override_failure_message(
					"no item '%s' -- the meshlib is stale, regenerate it" % item_name).is_true()
			var mat := _library.get_item_mesh(_by_name[item_name]).surface_get_material(0)
			var shaded := mat as ShaderMaterial
			assert_object(shaded).override_failure_message(
					"'%s' wears a %s, not the water shader" % [item_name, mat]).is_not_null()
			var got: float = shaded.get_shader_parameter("deep")
			assert_float(got).override_failure_message(
					"'%s' renders as %s water while its tile declares walkable=%s" \
					% [item_name, "deep" if want > 0.5 else "shallow",
					GridUtils.walkable_of(data)]).is_equal(want)
			checked += 1
	assert_int(checked).override_failure_message(
			"no WATER tiles authored; the case is vacuous").is_greater(0)


# The blast radius, from the other end: the shader is on water and NOWHERE else. A material is
# shared across items by construction, so leaking it onto one wrong tile leaks it onto a whole kind.
func test_only_water_wears_the_water_shader() -> void:
	var water_items: Dictionary[String, bool] = {}
	for tile: Dictionary in _water_tiles():
		for item_name in _surface_items(tile["source"], tile["coords"]):
			water_items[item_name] = true
	# The declared Kind FALLBACK is water too, and wears it for the same reason: a cell with no
	# per-tile item would otherwise sit still in the middle of a moving lake.
	water_items[_library.get_item_name(BoardMirror.KIND_TO_ITEM[Terrain.Kind.WATER])] = true

	var shader := load(SHADER_PATH) as Shader
	for id: int in _library.get_item_list():
		var item_name := _library.get_item_name(id)
		var mesh := _library.get_item_mesh(id)
		for surface in mesh.get_surface_count():
			var shaded := mesh.surface_get_material(surface) as ShaderMaterial
			if shaded == null:
				continue
			assert_bool(shaded.shader == shader).override_failure_message(
					"'%s' surface %d wears an unknown ShaderMaterial" \
					% [item_name, surface]).is_true()
			assert_bool(water_items.has(item_name)).override_failure_message(
					"'%s' is not a water item but wears the water shader" % item_name).is_true()
			assert_int(surface).override_failure_message(
					"'%s' wears the water shader on surface %d -- the shader is the SURFACE, and " \
					% [item_name, surface] + "a block's sides are the water's BODY").is_equal(0)


# The other half of the read, and the half that reaches BOTH views: shallow water is lighter than
# deep. Asserted as the FORK and never as either side of it -- how much lighter is a by-eye call
# that will move, and a test that pins one of those numbers turns re-tuning into a red run.
func test_shallow_water_reads_lighter_than_deep() -> void:
	var shallow: Array[Dictionary] = []
	var deep: Array[Dictionary] = []
	for tile: Dictionary in _water_tiles():
		if GridUtils.walkable_of(tile["data"]):
			shallow.append(tile)
		else:
			deep.append(tile)
	assert_bool(shallow.is_empty()).override_failure_message(
			"no walkable water tile authored; the case is vacuous").is_false()
	assert_bool(deep.is_empty()).override_failure_message(
			"no unwalkable water tile authored; the case is vacuous").is_false()

	var atlas_image := (load(ATLAS_PATH) as Texture2D).get_image()
	if atlas_image.is_compressed():
		atlas_image.decompress()
	for wet: Dictionary in shallow:
		for dry: Dictionary in deep:
			# The tileset's own modulate -- what the flat view multiplies the sprite by.
			var lit: Color = (wet["data"] as TileData).modulate
			var dark: Color = (dry["data"] as TileData).modulate
			assert_float(lit.get_luminance()).override_failure_message(
					"tile %s is walkable but its modulate is no lighter than %s's -- in the FLAT " \
					% [wet["coords"], dry["coords"]] + "view that tint is the whole difference " \
					+ "between wading and drowning").is_greater(dark.get_luminance())
			# And the COMPOSED atlas, which is where 3D reads the same number from. Two surfaces,
			# one authored value -- this is what would catch the generator dropping the tint.
			assert_float(_mean_luminance(atlas_image, wet)).override_failure_message(
					"the composed atlas draws %s no lighter than %s -- the tileset carries the " \
					% [wet["coords"], dry["coords"]] + "tint but the generator is not baking it") \
					.is_greater(_mean_luminance(atlas_image, dry))


func _mean_luminance(image: Image, tile: Dictionary) -> float:
	var region: Rect2i = (tile["atlas"] as TileSetAtlasSource).get_tile_texture_region(
			tile["coords"], 0)
	var total := 0.0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			total += image.get_pixel(x, y).get_luminance()
	return total / float(maxi(1, region.get_area()))


# The parse canary. Godot compiles its own shader language to GLSL, and a shader that fails that
# parse still LOADS — it just exposes no uniforms — so nothing else in this file would notice: the
# materials would carry their parameters, the meshlib would be identical, and the first sign would
# be an error surface on the dev's screen. It also pins the two names the generator sets by hand.
func test_the_water_shader_parses_and_exposes_what_the_generator_sets() -> void:
	var shader := load(SHADER_PATH) as Shader
	assert_object(shader).is_not_null()
	var names := PackedStringArray()
	for entry: Dictionary in shader.get_shader_uniform_list():
		names.append(entry["name"])
	assert_bool(names.is_empty()).override_failure_message(
			"the water shader exposes no uniforms at all -- it failed to parse, and every water " \
			+ "surface will render as an error").is_false()
	for wanted in ["atlas", "deep"]:
		assert_bool(names.has(wanted)).override_failure_message(
				"gen_lookdev_assets sets shader parameter '%s' and the shader declares no such " \
				% wanted + "uniform -- the value is dropped in silence").is_true()


# A global uniform is spelled in three files and NOTHING complains when two of them disagree: an
# undeclared global refuses to compile, and a misspelled one silently reads zero. So the three
# spellings are held to being one set.
func test_every_water_knob_is_spelled_the_same_in_all_three_places() -> void:
	var declared: Dictionary[String, bool] = {}
	for line in (load(SHADER_PATH) as Shader).code.split("\n"):
		var text := line.strip_edges()
		if text.begins_with("global uniform "):
			var words := text.trim_suffix(";").split(" ")
			declared[words[words.size() - 1]] = true
	assert_bool(declared.is_empty()).override_failure_message(
			"the water shader declares no globals; the case is vacuous").is_false()

	var rows: Dictionary[String, bool] = {}
	for knob: Dictionary in GameKnobs.KNOBS:
		if knob["group"] == "Water":
			rows[knob["prop"]] = true
	assert_array(rows.keys()).override_failure_message(
			"the Water knob rows and the shader's globals are different sets -- a row with no " \
			+ "uniform moves nothing, and a uniform with no row cannot be tuned") \
			.contains_exactly_in_any_order(declared.keys())

	for name: String in declared:
		assert_bool(ProjectSettings.has_setting("shader_globals/%s" % name)) \
				.override_failure_message("the shader declares global '%s' and project.godot " \
				% name + "does not -- the shader will refuse to compile").is_true()
