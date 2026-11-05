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
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")   # held, #621

var _tiles: TileSet
var _data: TileData
var _mirror: BoardMirror
var _scene: Node3D   # only the real-window case boots one


func before_test() -> void:
	_tiles = TileSet.new()
	for field: Dictionary in ObjectKnobs.FIELDS:
		var at := _tiles.get_custom_data_layers_count()
		_tiles.add_custom_data_layer()
		_tiles.set_custom_data_layer_name(at, field["layer"])
		_tiles.set_custom_data_layer_type(at, field["type"])
	# prop_shape is not an override field, so it is not in FIELDS -- but the rules-height column falls
	# back to it, so the synthetic sheet has to be able to say what shape a tile is. Unauthored it
	# reads 0 = FLAT, exactly what the missing layer read before.
	_tiles.add_custom_data_layer()
	_tiles.set_custom_data_layer_name(_tiles.get_custom_data_layers_count() - 1, "prop_shape")
	_tiles.set_custom_data_layer_type(_tiles.get_custom_data_layers_count() - 1, TYPE_INT)
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
	if FileAccess.file_exists(SCRATCH_TILES):
		DirAccess.remove_absolute(SCRATCH_TILES)
	if is_instance_valid(_scene):
		# The real page edits the CACHED board tileset: put the file's columns back before any later
		# suite reads it.
		ObjectKnobs.revert_fields(load(BOARD_TILES) as TileSet)
		get_tree().root.remove_child(_scene)
		_scene.free()
		await await_idle_frame()   # #93/#101 orphan workaround


# --- Reset tile fields (#1376) -------------------------------------------------------------

const SCRATCH_TILES := "user://__test_object_fields_reset.tres"

# The page edits the CACHED tileset in place, so Reset must read the FILE and put the column back on
# the very TileData the board draws -- not swap the source out from under it. A scratch sheet, saved
# and loaded through the cache, is the board's own situation without touching TestTiles.tres.
func test_reset_tile_fields_puts_a_moved_column_back_on_the_same_tile() -> void:
	_data.set_custom_data("prop_light_energy", 1.5)
	assert_int(ResourceSaver.save(_tiles, SCRATCH_TILES)).is_equal(OK)
	var live := load(SCRATCH_TILES) as TileSet
	var live_data := (live.get_source(0) as TileSetAtlasSource).get_tile_data(Vector2i.ZERO, 0)
	live_data.set_custom_data("prop_light_energy", 4.0)

	assert_bool(ObjectKnobs.revert_fields(live)).is_true()

	assert_float(live_data.get_custom_data("prop_light_energy")).override_failure_message(
		"the moved column did not come back to the file's value").is_equal_approx(1.5, 0.0001)
	assert_object((live.get_source(0) as TileSetAtlasSource).get_tile_data(Vector2i.ZERO, 0)).override_failure_message(
		"the reset replaced the tile the board draws instead of writing onto it").is_same(live_data)


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


# --- the INT column (#660) ---------------------------------------------------------------------
#
# The same storage lesson one type further along from the colour case, with one difference that
# matters: this field's fallback is not a global at all. An unauthored solid prop stands one block
# because of its SHAPE, so GridUtils resolves it and BoardMirror never sees it.

func test_a_rules_height_inherits_its_shape_until_a_value_is_authored() -> void:
	_data.set_custom_data("prop_shape", GridUtils.PropShape.PLANE)
	assert_int(GridUtils.prop_int_override_of(_data, "prop_rule_height")).override_failure_message(
		"an unwritten int column must read the sentinel, not a height").is_equal(0)
	assert_int(GridUtils.prop_rule_height_of(_data)).override_failure_message(
		"an unauthored wall does not stand one block").is_equal(Terrain.UNITS_PER_LEVEL)

	# The authored path, which is the whole point of the column and which the trace's own suite
	# cannot reach: its boards stub the read-point, so only this exercises the reader.
	_data.set_custom_data("prop_rule_height", 1)
	assert_int(GridUtils.prop_rule_height_of(_data)).override_failure_message(
		"an authored height did not override the shape default").is_equal(1)

	_data.set_custom_data("prop_rule_height", 0)
	assert_int(GridUtils.prop_rule_height_of(_data)).override_failure_message(
		"writing the sentinel back did not return the field to its shape default"
		).is_equal(Terrain.UNITS_PER_LEVEL)


# The narrowing, at the reader rather than through a painted board: a BILLBOARD stands up but is
# thin, so it stops nothing until someone decides otherwise. Authoring is how a tree becomes cover.
func test_a_billboard_stops_nothing_until_it_is_authored() -> void:
	_data.set_custom_data("prop_shape", GridUtils.PropShape.BILLBOARD)
	assert_int(GridUtils.prop_rule_height_of(_data)).override_failure_message(
		"a lantern blocks line of sight by default").is_equal(0)
	_data.set_custom_data("prop_rule_height", 3)
	assert_int(GridUtils.prop_rule_height_of(_data)).override_failure_message(
		"a billboard cannot be given a height, so a tree can never be cover").is_equal(3)


# --- the inherit checkbox, driven for real (#660 follow-up) -------------------------------------
#
# Shipped broken, and no test could see it: everything above asks GridUtils, and ObjectTool's row
# builder had no coverage at all -- `_rebuild` early-outs on "no 3D host", so even the suites that
# hold a real ObjectTool never reach `_build_override_field`. These call it directly.
#
# The bug: unticking "inherit" writes the value the field RESOLVES to, which for a BILLBOARD's rules
# height is 0 -- the sentinel. The write read straight back as "inherited", the box re-ticked itself,
# and a tree could never be given a height. The one thing billboards were offered the field for.

func _rows_for(shape: GridUtils.PropShape) -> ObjectTool:
	var panel: ObjectTool = auto_free(ObjectTool.new())
	add_child(panel)
	_data.set_custom_data("prop_shape", shape)
	panel._build_field_rows({"data": _data, "shape": shape})
	return panel


func _inherit_box(panel: ObjectTool, label: String) -> CheckBox:
	for child in panel._rows.get_children():
		if child is CheckBox and (child as CheckBox).text == "%s - inherit" % label:
			return child
	return null


func test_a_billboards_rules_height_can_actually_be_authored() -> void:
	var panel := _rows_for(GridUtils.PropShape.BILLBOARD)
	var box := _inherit_box(panel, "Rules height")
	assert_object(box).override_failure_message(
		"the Objects panel offers a billboard no Rules height row at all").is_not_null()

	box.toggled.emit(false)   # the dev unticking "inherit" to give a tree a height

	assert_int(GridUtils.prop_int_override_of(_data, "prop_rule_height")).override_failure_message(
		"unticking wrote the sentinel back, so the row is stuck inheriting and a tree can never block"
		).is_greater(0)
	assert_int(GridUtils.prop_rule_height_of(_data)).override_failure_message(
		"a tree that was just given a height still stops nothing").is_greater(0)


func test_unticking_a_solid_prop_adopts_what_it_already_resolved() -> void:
	# The control: the fix must not simply write the minimum. A PLANE already resolves to a full
	# block, so unticking has to keep THAT -- switching a field to authored does not move the board.
	var panel := _rows_for(GridUtils.PropShape.PLANE)
	_inherit_box(panel, "Rules height").toggled.emit(false)
	assert_int(GridUtils.prop_rule_height_of(_data)).override_failure_message(
		"unticking moved a wall's height instead of adopting what it already stood at"
		).is_equal(Terrain.UNITS_PER_LEVEL)


# --- The page widened to every NAMED tile (#902) -----------------------------------------------
#
# The picker listed props alone, so `grass_basic` and `grass_clover` -- FLAT, and half the grass in
# the game -- had no page at all while their ground's burn rules needed one.

func test_a_flat_ground_tile_gets_a_page() -> void:
	var tiles := load(BOARD_TILES) as TileSet
	var named_flat: Variant = _flat_named_tile(tiles)
	assert_object(named_flat).override_failure_message(
		"the sheet names no FLAT tile, so this case is vacuous").is_not_null()

	var pages := _coords_of(ObjectKnobs.authorable_tiles(tiles))

	assert_array(pages).override_failure_message(
		"a named flat ground tile has no page, so its burn rules are unreachable"
		).contains([named_flat])


# object_tiles() answers a DIFFERENT question -- which tiles stand something up -- and BoardMirror's
# light coverage plus the prop_lit content law both ask it. Widening it in place would have left
# test_board_mirror picking a flat tile as its unlit example, prop_at returning null, and its
# assertion passing VACUOUSLY: a test going blind, which is worse than one going red.
func test_the_prop_list_stays_narrow_while_the_page_list_widens() -> void:
	var tiles := load(BOARD_TILES) as TileSet
	var props := _coords_of(ObjectKnobs.object_tiles(tiles))
	var pages := _coords_of(ObjectKnobs.authorable_tiles(tiles))

	assert_array(props).override_failure_message(
		"object_tiles now lists a flat tile, so every prop-only reader has quietly widened with it"
		).not_contains([_flat_named_tile(tiles)])
	assert_int(pages.size()).override_failure_message(
		"the page list is no wider than the prop list, so the widening did not happen"
		).is_greater(props.size())
	for coords: Vector2i in props:
		assert_array(pages).override_failure_message(
			"a prop lost its page when the list widened").contains([coords])


# `shapes: []` has always meant "every OBJECT", and every object was non-FLAT. Re-reading it as
# "flat ground too" would hand `grass_basic` a Rules height, which Reach honours for ANY cell
# (Reach.gd's column_top asks prop_rule_height_at) -- flat ground that blocks a shot, smuggled in by
# a picker filter.
func test_a_flat_tile_is_offered_no_per_tile_prop_field() -> void:
	assert_array(_layers_of(ObjectKnobs.fields_for(GridUtils.PropShape.FLAT, true))
		).override_failure_message(
		"a flat ground tile is offered prop fields, so it can be given a rules height a gun dies on"
		).is_empty()
	assert_array(_layers_of(ObjectKnobs.globals_for(GridUtils.PropShape.FLAT, true))
		).is_empty()


func _flat_named_tile(tiles: TileSet) -> Variant:
	for entry: Dictionary in ObjectKnobs.authorable_tiles(tiles):
		if entry["shape"] == GridUtils.PropShape.FLAT:
			return entry["coords"]
	return null


func _coords_of(entries: Array[Dictionary]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for entry: Dictionary in entries:
		out.append(entry["coords"])
	return out


# --- The game-wide defaults, moved onto the tile's page (#902) ----------------------------------

# The dev's ask was that these be easier to FIND, so a row that falls back to a global must be able
# to show that global on the same page. This is that property, pinned.
func test_every_override_field_can_see_its_default_on_the_same_page() -> void:
	var globals: Array[String] = []
	for knob: Dictionary in ObjectKnobs.GLOBALS:
		globals.append(knob["prop"])
	var orphans: Array[String] = []
	for field: Dictionary in ObjectKnobs.FIELDS:
		var knob: String = field["knob"]
		if knob != "" and not globals.has(knob):
			orphans.append(field["layer"])
	assert_array(orphans).override_failure_message(
		"these fields fall back to a global the page cannot show: %s" % ", ".join(orphans)
		).is_empty()


# The same shape-and-lit filter as the fields, for the fields' reason: a crate must not be offered a
# tuft density any more than it is offered a tuft scale.
func test_a_tuft_is_offered_the_tuft_globals_and_a_crate_is_not() -> void:
	var tuft := _props_of(ObjectKnobs.globals_for(GridUtils.PropShape.TUFT, false))
	var crate := _props_of(ObjectKnobs.globals_for(GridUtils.PropShape.CUBE, false))

	assert_array(tuft).contains(["tuft_scale", "tuft_density"])
	assert_array(crate).override_failure_message(
		"a crate's page offers grass tuft dials").not_contains(["tuft_scale", "tuft_density"])
	assert_array(crate).override_failure_message(
		"a solid prop is not offered the block height it falls back to").contains(["block_height_scale"])


func test_the_lamp_defaults_appear_only_once_a_tile_says_it_is_lit() -> void:
	assert_array(_props_of(ObjectKnobs.globals_for(GridUtils.PropShape.BILLBOARD, false))
		).not_contains(["prop_light_energy"])
	assert_array(_props_of(ObjectKnobs.globals_for(GridUtils.PropShape.BILLBOARD, true))
		).contains(["prop_light_energy"])


# A GLOBALS row is saved into its @export declaration, so it must name a property that is really
# declared there -- the law GameKnobs' own rows carry, applied to the table that left it.
func test_every_global_is_declared_in_the_script_its_node_carries() -> void:
	var source := FileAccess.get_file_as_string("res://Classes/presentation/BoardMirror.gd")
	assert_str(source).override_failure_message("BoardMirror.gd did not read").is_not_empty()
	var missing: Array[String] = []
	for knob: Dictionary in ObjectKnobs.GLOBALS:
		assert_str(knob["node"]).override_failure_message(
			"a global names a node other than BoardMirror -- widen this law before moving it"
			).is_equal("BoardMirror")
		if not source.contains("var %s" % knob["prop"]):
			missing.append(knob["prop"])
	assert_array(missing).override_failure_message(
		"these globals name no declaration to save into: %s" % ", ".join(missing)).is_empty()


# They carry no `group`: a group names which SUB-TAB of the Game page a row lands on, and these land
# on none. A stray one would send test_every_knob_group_has_a_sub_tab hunting for a tab.
func test_a_global_declares_no_game_tab_group() -> void:
	for knob: Dictionary in ObjectKnobs.GLOBALS:
		assert_bool(knob.has("group")).override_failure_message(
			"'%s' still carries a Game-tab group" % knob["label"]).is_false()


func _props_of(knobs: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for knob: Dictionary in knobs:
		out.append(knob["prop"])
	return out


# --- What this tile is made of (#1315) ----------------------------------------------------------
#
# A ground's makeup is a TileSet column, edited on the Tiles page. These drive the page's own row
# against the synthetic sheet, given the column, with a stub host whose game counts plan re-reads.
# The ids typed are picked from the real catalog, never named (the content razor).

class _StubGrid extends RefCounted:
	var tile_set: TileSet

class _StubSquads extends RefCounted:
	var active_squad = null

class _StubGame extends RefCounted:
	var grid := _StubGrid.new()
	var squad_manager := _StubSquads.new()
	var refreshed := 0
	var dropped := 0
	func refresh_action_queue(_squad) -> void:
		refreshed += 1
	func drop_threat_field() -> void:
		dropped += 1

class _StubHost extends Node3D:
	var game


func _add_made_of_column() -> void:
	var at := _tiles.get_custom_data_layers_count()
	_tiles.add_custom_data_layer()
	_tiles.set_custom_data_layer_name(at, GridUtils.MADE_OF)
	_tiles.set_custom_data_layer_type(at, TYPE_PACKED_STRING_ARRAY)


func _made_of_page(game: _StubGame) -> ObjectTool:
	_add_made_of_column()
	game.grid.tile_set = _tiles
	var host: _StubHost = auto_free(_StubHost.new())
	host.game = game
	var panel: ObjectTool = auto_free(ObjectTool.new())
	add_child(panel)
	panel._host = host   # not attach_host: the row is what is under test, not the page rebuild
	panel._build_made_of_row(_data)
	return panel


func _type_made_of(panel: ObjectTool, text: String) -> void:
	panel._made_of.text = text
	panel._made_of.text_changed.emit(text)   # setting text from code emits nothing; a keystroke does


# THE MISSING-WIRE CASE: a typed makeup lands on the tile the board reads, with no save, and the
# plan is re-read so a queued carving is judged against it.
func test_a_typed_makeup_reaches_the_tile_and_the_plan() -> void:
	var game := _StubGame.new()
	var panel := _made_of_page(game)
	var pick: String = SubstanceCatalog.get_all().keys()[0]
	_type_made_of(panel, pick)
	assert_array(GridUtils.made_of(_data)).is_equal([pick])
	var layer: TileMapLayer = auto_free(TileMapLayer.new())
	layer.tile_set = _tiles
	layer.set_cell(Vector2i(2, 3), 0, Vector2i.ZERO)
	assert_array(BoardContext.new(layer, [] as Array[Unit], null).made_of_at(Vector2i(2, 3))).override_failure_message(
			"the page wrote a column the board does not read").is_equal([pick])
	assert_int(game.refreshed).is_equal(1)
	assert_int(game.dropped).is_equal(1)
	assert_bool(panel.has_unsaved_changes()).is_true()


func test_an_unknown_or_repeated_substance_is_not_written() -> void:
	var game := _StubGame.new()
	var panel := _made_of_page(game)
	var any: String = SubstanceCatalog.get_all().keys()[0]
	for text: String in ["no_such_substance_here", "%s + %s" % [any, any]]:
		_type_made_of(panel, text)
		assert_array(GridUtils.made_of(_data)).override_failure_message("\"%s\" was written" % text).is_empty()
		assert_str(panel._made_of_readout.text).contains("Not written")
	assert_int(game.refreshed).override_failure_message("a refused row re-resolved the plan").is_equal(0)
	assert_bool(panel.has_unsaved_changes()).is_false()


# The readout names the row's own substances and the parts a cast would find with them.
func test_the_makeup_readout_names_what_a_cast_would_find() -> void:
	var compound := ""
	for id: String in SubstanceCatalog.get_all():
		if CellSubstances.present_from([id] as Array[String]).size() > 1:
			compound = id
			break
	assert_str(compound).override_failure_message("no substance lends a part").is_not_empty()
	var panel := _made_of_page(_StubGame.new())
	_type_made_of(panel, compound)
	var catalog := SubstanceCatalog.get_all()
	for id: String in CellSubstances.present_from([compound] as Array[String]):
		var shown: String = (catalog[id] as Substance).display_name
		assert_str(panel._made_of_readout.text).contains(shown if shown != "" else id)


# Reset tile fields puts the makeup back too: it is a tile column like the look fields.
func test_reset_tile_fields_puts_the_makeup_back() -> void:
	_add_made_of_column()
	var saved: String = SubstanceCatalog.get_all().keys()[0]
	_data.set_custom_data(GridUtils.MADE_OF, PackedStringArray([saved]))
	assert_int(ResourceSaver.save(_tiles, SCRATCH_TILES)).is_equal(OK)
	# REPLACE: the other reset case cached a sheet at this path that has no makeup column.
	var live := ResourceLoader.load(SCRATCH_TILES, "", ResourceLoader.CACHE_MODE_REPLACE) as TileSet
	var live_data := (live.get_source(0) as TileSetAtlasSource).get_tile_data(Vector2i.ZERO, 0)
	live_data.set_custom_data(GridUtils.MADE_OF, PackedStringArray())

	assert_bool(ObjectKnobs.revert_fields(live)).is_true()

	assert_array(GridUtils.made_of(live_data)).override_failure_message(
			"Reset tile fields left the makeup as edited").is_equal([saved])


# The real window: the picked tile's page carries the row, and a typed makeup lands on that tile of the
# board's own tileset. The only case that reaches the row through _rebuild rather than calling it.
func test_the_real_tiles_page_edits_the_picked_tiles_makeup() -> void:
	_scene = SCENE.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	var overlay := _scene.get_node("Main/DevOverlay") as DevOverlay
	var page := overlay.object_tool
	assert_bool(page.has_host()).override_failure_message("the Tiles page has no 3D host").is_true()
	assert_bool(page._objects.is_empty()).override_failure_message("the Tiles page lists no tile").is_false()
	page._picked = 0
	page._rebuild()
	overlay.show_leaf(page)
	assert_object(page._made_of).override_failure_message("the picked tile's page has no makeup row").is_not_null()
	var data: TileData = page._objects[0]["data"]
	var ids := GridUtils.made_of(data)
	var pick := ""
	for id: String in SubstanceCatalog.get_all():
		if not ids.has(id):
			pick = id
			break
	ids.append(pick)
	_type_made_of(page, " + ".join(ids))
	assert_array(GridUtils.made_of(data)).override_failure_message(
			"the typed makeup did not land on the picked tile").contains([pick])
