# THE gap #342 was: a tile whose ground the board can tilt, with no cap mesh to tilt it WITH.
#
# `BoardMirror.ramp_item_for_cell` falls back to the generic `dirt_ramp*` when the library has no cap
# for a cell's own tile, and that fallback is real and must stay -- an empty cell, a rotated
# alternative and MULTI-CELL art all reach it legitimately, and without it those cells render as a
# hole. What it must never be is a silent stand-in for a tile that simply never got a mesh: the
# generic cap wears the generated `grass_top`, so a flowery-grass slope came out olive beside its own
# mint neighbours, and every rock, tree and fence on sloped ground did the same.
#
# The gate was `if not stands_up`, which read a TUFT -- walkable ground with flowers growing on it --
# as a prop, and the corner tool slopes any cell that has ground. But the deeper reason it was wrong
# is that what a cap draws is not the tile's ART, it is the ground the tile stands ON, and the
# generator's atlas pass has already composed that for every tile. So the rule is: a 1x1 tile with a
# block has a cap for every climb and every shape, wearing the same face.
#
# Read off the COMMITTED artifact and the COMMITTED tileset, because what ships is what must agree --
# a case that regenerated the library would pass on a machine whose meshlib was stale.
extends GdUnitTestSuite

const MESHLIB_PATH := "res://Scenes/LookDev/lookdev_meshlib.tres"
const TILESET_PATH := "res://Resources/TestTiles.tres"

const FORMS: Array[Terrain.Form] = [Terrain.Form.WEDGE, Terrain.Form.OUTER, Terrain.Form.INNER]

var _names: Dictionary[String, bool] = {}
var _tiles: TileSet


func before_test() -> void:
	_names.clear()
	var library := load(MESHLIB_PATH) as MeshLibrary
	assert_object(library).override_failure_message(
			"the meshlib is missing or unreadable at %s" % MESHLIB_PATH).is_not_null()
	for id: int in library.get_item_list():
		_names[library.get_item_name(id)] = true
	_tiles = load(TILESET_PATH) as TileSet
	assert_object(_tiles).override_failure_message(
			"the tileset is missing or unreadable at %s" % TILESET_PATH).is_not_null()


# Every 1x1 tile in the sheet, in atlas order. The SIZE filter is the generator's own skip and the
# reason the fallback still has a job -- a 1x2 lantern's art cannot go onto a 1x1 face un-squashed,
# so those tiles get no block either and are correctly not asked for a cap.
func _single_cell_tiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _tiles.get_source_count():
		var source_id := _tiles.get_source_id(s)
		var atlas := _tiles.get_source(source_id) as TileSetAtlasSource
		if atlas == null:
			continue
		for i in atlas.get_tiles_count():
			var coords := atlas.get_tile_id(i)
			if atlas.get_tile_size_in_atlas(coords) == Vector2i.ONE:
				out.append({"source": source_id, "coords": coords})
	return out


func test_every_tile_with_a_block_has_a_cap_for_every_climb_and_shape() -> void:
	var checked := 0
	var missing: Array[String] = []
	for tile in _single_cell_tiles():
		var source: int = tile["source"]
		var coords: Vector2i = tile["coords"]
		# The BLOCK is the precondition, not the tile: a tile the generator skipped has no ground
		# face for a cap to wear either, and asking one of it would be asserting the fallback.
		if not _names.has(BoardMirror.tile_item_name(source, coords)):
			continue
		for climb: int in BoardMirror.RAMP_ITEM_NAMES:
			for form: Terrain.Form in FORMS:
				var wanted := BoardMirror.ramp_item_name(source, coords, climb, form)
				if not _names.has(wanted):
					missing.append(wanted)
				checked += 1
	assert_array(missing).override_failure_message(
			"%d cap meshes are missing, so those cells fall back to the generic grass wedge and " \
			% missing.size() + "wear a texture nobody painted: %s" \
			% [", ".join(missing.slice(0, 8))]).is_empty()
	assert_int(checked).override_failure_message(
			"no tile had a block item at all; the law is vacuous").is_greater(0)


# The twin, and the half that says the rule is about TILES rather than about the count: a tuft is
# ground, and it is the shape the old gate got wrong, so it is named here rather than left to the
# sweep above. It would pass vacuously on a sheet with no tufts, which is what the message says.
func test_a_tuft_has_its_own_cap_rather_than_the_generic_grass_wedge() -> void:
	var checked := 0
	for s in _tiles.get_source_count():
		var source_id := _tiles.get_source_id(s)
		var atlas := _tiles.get_source(source_id) as TileSetAtlasSource
		if atlas == null:
			continue
		for i in atlas.get_tiles_count():
			var coords := atlas.get_tile_id(i)
			if atlas.get_tile_size_in_atlas(coords) != Vector2i.ONE:
				continue
			if GridUtils.prop_shape_of(atlas.get_tile_data(coords, 0)) != GridUtils.PropShape.TUFT:
				continue
			for climb: int in BoardMirror.RAMP_ITEM_NAMES:
				for form: Terrain.Form in FORMS:
					var wanted := BoardMirror.ramp_item_name(source_id, coords, climb, form)
					assert_bool(_names.has(wanted)).override_failure_message(
							"a TUFT is walkable ground the corner tool can slope, and '%s' has no " \
							% wanted + "mesh -- so that slope wears the generic grass instead of " \
							+ "the tile the player painted").is_true()
					checked += 1
	assert_int(checked).override_failure_message(
			"the tileset authors no TUFT tiles; the case is vacuous").is_greater(0)
