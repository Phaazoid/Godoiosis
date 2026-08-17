# Per-object fields (#272 slice 2): the layering, the sentinel, and the schema they need.
#
# The mutation cases build a SYNTHETIC tileset rather than touching the board's. `TestTiles.tres` is
# a res:// resource served from the cache to every suite in the run, so a case that wrote a custom
# datum into it would leak into whatever ran next and could be saved over the real file by any later
# save path. Nothing here needs the real tiles to test the RULE — only the schema law does, and that
# one reads.
#
# The rule under test is the dev's ruling in one line: a global is the default, a tile may override
# it, and INHERIT is a declared sentinel because 0 is a legal tuned value for every one of these.
extends GdUnitTestSuite

const BOARD_TILES := "res://Resources/TestTiles.tres"

var _tiles: TileSet
var _data: TileData
var _mirror: BoardMirror


func before_test() -> void:
	_tiles = TileSet.new()
	for field: Dictionary in ObjectKnobs.FIELDS:
		var at := _tiles.get_custom_data_layers_count()
		_tiles.add_custom_data_layer()
		_tiles.set_custom_data_layer_name(at, field["layer"])
		_tiles.set_custom_data_layer_type(at, field["type"])
	var source := TileSetAtlasSource.new()
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(16, 16)
	source.create_tile(Vector2i.ZERO)
	_tiles.add_source(source, 0)
	_data = source.get_tile_data(Vector2i.ZERO, 0)
	_mirror = BoardMirror.new()
	add_child(_mirror)


func after_test() -> void:
	_mirror.free()


# --- The sentinel ------------------------------------------------------------------------

# An unauthored field must read INHERIT. This is the case that FORCED the sentinel to be zero:
# has_custom_data answers whether the LAYER exists, never whether this tile wrote to it, so an
# untouched float arrives as the type's 0.0 and any other sentinel would have to be authored onto
# every field of every object tile by hand.
func test_an_unwritten_field_reads_inherit() -> void:
	for field: Dictionary in ObjectKnobs.FIELDS:
		if field["type"] == TYPE_FLOAT:
			assert_bool(GridUtils.is_inherited(
				GridUtils.prop_override_of(_data, field["layer"]))).override_failure_message(
				"'%s' does not read as inherited when nothing authored it" % field["layer"]).is_true()


# The accepted cost, stated so it cannot be forgotten and quietly "fixed" into a bug: zero IS
# inherit, so a literal zero is not authorable. Nothing is lost — a lightless light is what
# prop_lit = false says, and it says it better.
func test_zero_means_inherit_rather_than_a_light_tuned_to_nothing() -> void:
	_mirror.prop_light_energy = 4.0
	_data.set_custom_data("prop_light_energy", 0.0)
	assert_float(_mirror.light_energy_for(_data)).override_failure_message(
		"a zero was taken as an authored value; the sentinel and the storage default must agree"
		).is_equal_approx(4.0, 0.0001)


func test_writing_the_sentinel_back_returns_a_field_to_inherit() -> void:
	_data.set_custom_data("prop_height_scale", 1.8)
	assert_bool(GridUtils.is_inherited(
		GridUtils.prop_override_of(_data, "prop_height_scale"))).is_false()
	_data.set_custom_data("prop_height_scale", GridUtils.INHERIT)
	assert_bool(GridUtils.is_inherited(
		GridUtils.prop_override_of(_data, "prop_height_scale"))).is_true()


# The same storage lesson one type along: a Color layer defaults to OPAQUE BLACK, not transparent,
# so blackness is the sentinel and alpha is not part of the question.
func test_a_colour_field_inherits_while_it_is_black() -> void:
	assert_bool(GridUtils.is_inherited_color(
		GridUtils.prop_color_override_of(_data, "prop_light_color"))).is_true()
	_data.set_custom_data("prop_light_color", Color(0, 1, 0, 1))
	assert_bool(GridUtils.is_inherited_color(
		GridUtils.prop_color_override_of(_data, "prop_light_color"))).is_false()


# --- The layering ------------------------------------------------------------------------

func test_an_unauthored_tile_resolves_to_the_global() -> void:
	_mirror.block_height_scale = 1.25
	assert_float(_mirror.block_height_for(_data)).is_equal_approx(1.25, 0.0001)
	_mirror.prop_light_energy = 4.0
	assert_float(_mirror.light_energy_for(_data)).is_equal_approx(4.0, 0.0001)


# THE case the whole slice exists for.
func test_an_authored_override_beats_the_global() -> void:
	_mirror.block_height_scale = 1.25
	_data.set_custom_data("prop_height_scale", 0.4)
	assert_float(_mirror.block_height_for(_data)).override_failure_message(
		"the tile's own height did not win — the global is still answering for it"
		).is_equal_approx(0.4, 0.0001)
	# And moving the global no longer moves this tile, which is the other half of "override".
	_mirror.block_height_scale = 2.0
	assert_float(_mirror.block_height_for(_data)).is_equal_approx(0.4, 0.0001)


func test_clearing_an_override_hands_the_tile_back_to_the_global() -> void:
	_mirror.tuft_scale = 0.25
	_data.set_custom_data("prop_tuft_scale", 1.0)
	assert_float(_mirror.tuft_scale_for(_data)).is_equal_approx(1.0, 0.0001)
	_data.set_custom_data("prop_tuft_scale", GridUtils.INHERIT)
	assert_float(_mirror.tuft_scale_for(_data)).is_equal_approx(0.25, 0.0001)


func test_a_colour_override_beats_the_global() -> void:
	_mirror.prop_light_color = Color(1, 0.8, 0.5)
	_data.set_custom_data("prop_light_color", Color(0, 0.5, 1, 1))
	assert_bool(_mirror.light_color_for(_data).is_equal_approx(Color(0, 0.5, 1, 1))).is_true()


# --- Which fields a tile is offered -------------------------------------------------------

# The filter belongs to the table, so a meaningless row is impossible to draw rather than merely
# hidden by whoever remembers to.
func test_a_tuft_is_not_offered_a_block_height_and_a_crate_is_not_offered_a_tuft_scale() -> void:
	var tuft := _layers_of(ObjectKnobs.fields_for(GridUtils.PropShape.TUFT, false))
	assert_array(tuft).contains(["prop_tuft_scale"])
	assert_array(tuft).not_contains(["prop_height_scale"])
	var crate := _layers_of(ObjectKnobs.fields_for(GridUtils.PropShape.CUBE, false))
	assert_array(crate).contains(["prop_height_scale"])
	assert_array(crate).not_contains(["prop_tuft_scale"])


func test_light_rows_appear_only_once_a_tile_says_it_is_lit() -> void:
	var unlit := _layers_of(ObjectKnobs.fields_for(GridUtils.PropShape.BILLBOARD, false))
	assert_array(unlit).contains(["prop_lit"])
	assert_array(unlit).not_contains(["prop_light_energy"])
	var lit := _layers_of(ObjectKnobs.fields_for(GridUtils.PropShape.BILLBOARD, true))
	assert_array(lit).contains(["prop_light_energy", "prop_light_color"])


func _layers_of(fields: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for field: Dictionary in fields:
		out.append(field["layer"])
	return out


# --- The schema, and the migration ---------------------------------------------------------

# The board's real tileset, read-only. A FIELDS row naming a layer the tileset does not declare is a
# row that reads unset forever and writes nowhere — the panel would draw it, the dev would tune it,
# and nothing would happen.
func test_every_field_names_a_layer_the_board_tileset_declares() -> void:
	var tiles := load(BOARD_TILES) as TileSet
	assert_object(tiles).override_failure_message(
		"could not load %s — every check below would be vacuous" % BOARD_TILES).is_not_null()
	for field: Dictionary in ObjectKnobs.FIELDS:
		var at := tiles.get_custom_data_layer_by_name(field["layer"])
		assert_int(at).override_failure_message(
			"the board tileset declares no '%s' layer — the field is inert" % field["layer"]
			).is_greater_equal(0)
		assert_int(tiles.get_custom_data_layer_type(at)).override_failure_message(
			"'%s' is declared with the wrong type" % field["layer"]).is_equal(field["type"])


# The LIT_PROPS migration, stated as a property rather than by naming the Lantern: which tile glows
# is authored content the dev may re-author freely, but a tileset where NOTHING is lit means the
# name list was retired into a column nobody filled in, and every lamp on every board went dark.
func test_at_least_one_object_tile_is_authored_as_lit() -> void:
	var tiles := load(BOARD_TILES) as TileSet
	var lit := 0
	for entry: Dictionary in ObjectKnobs.object_tiles(tiles):
		if GridUtils.prop_lit_of(entry["data"]):
			lit += 1
	assert_int(lit).override_failure_message(
		"no object tile declares prop_lit — the light that used to come from LIT_PROPS is gone"
		).is_greater(0)


func test_the_board_tileset_declares_objects_at_all() -> void:
	assert_int(ObjectKnobs.object_tiles(load(BOARD_TILES) as TileSet).size()).override_failure_message(
		"no object tiles — the Objects tab would list nothing and the laws above are vacuous"
		).is_greater(0)
