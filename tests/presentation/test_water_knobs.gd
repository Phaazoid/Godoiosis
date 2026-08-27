# The water knobs' WIRE (#552): does moving one actually reach the surface?
#
# The tuning values are GLOBAL shader uniforms rather than parameters on the meshlib's material,
# because writing to that material would mutate a generated artifact at runtime. The cost of that
# choice is a hand-written push per knob, and a knob nobody pushed is the born-dead slider #264
# shipped and #380 named -- it moves, it saves, and nothing on the board changes. Neither end is
# visible from the other: the @export and the uniform are in different files and different
# languages, and a mismatched name is silent, since GLSL reads an unset global as zero.
#
# WHERE THE LINE IS DRAWN, and it is drawn by the engine rather than by preference. Measured under
# --headless: the globals REGISTER (RenderingServer.global_shader_parameter_get_list returns them
# all) but the dummy renderer stores no values, so global_shader_parameter_get answers null whatever
# anyone sets. So the readback cannot be the assertion. What these cases pin instead is every hop
# that can DRIFT -- one setter, one name and one registration per knob -- by overriding the one
# funnel they all pass through; the funnel's own single line into RenderingServer is the one hop no
# headless test can watch, and it is one line with no name in it to get wrong.
#
# And the hop none of them can reach: whether a knob's effect is VISIBLE. Both of #552's dead knobs
# passed every case here while moving nothing on screen.
extends GdUnitTestSuite


# Records what BoardMirror pushes instead of letting it reach a renderer that is not listening.
# The funnel takes a Variant because one water knob is a Colour (the bed's), so this does too --
# GDScript refuses an override whose signature narrows its parent's.
class SpyMirror extends BoardMirror:
	var pushed: Dictionary[String, Variant] = {}
	# The mask as BUILT. Not read back off the ImageTexture, because headless it cannot be: measured
	# under the dummy renderer, get_image() answers the FIRST image the texture was ever given and
	# never changes again -- a second set_image, even at a different SIZE, still reads back the
	# original. A case that read the texture would be green on a mask that stopped updating, which
	# is the exact bug these cases exist to catch.
	var mask_image: Image

	func _push_mask(image: Image, rect: Vector4) -> void:
		mask_image = image
		super(image, rect)


	func _push_water(uniform: StringName, value: Variant) -> void:
		pushed[String(uniform)] = value


var _mirror: SpyMirror


func before_test() -> void:
	_mirror = SpyMirror.new()


func after_test() -> void:
	if _mirror.is_inside_tree():
		get_tree().root.remove_child(_mirror)
	_mirror.free()
	await await_idle_frame()


# The knob table is the authority on which knobs exist, so this reads its Water rows rather than
# keeping a second list here to fall out of step with.
func _water_props() -> PackedStringArray:
	var out := PackedStringArray()
	for knob: Dictionary in GameKnobs.KNOBS:
		# The Water FAMILY, matched by prefix: two groups since every dial went per type, and a third
		# should join without editing this. The vacuity assertion in each case is what guards the
		# prefix, since a filter matching nothing passes everything.
		if (knob["group"] as String).begins_with("Water") and knob["node"] == "BoardMirror":
			out.append(knob["prop"])
	return out


# A distinct probe value per knob, SHAPED like the one already there -- one water knob is a Colour
# and the rest are floats, so a flat float sweep would silently no-op on the bed's colour and prove
# nothing about it.
func _probe(current: Variant, index: int) -> Variant:
	if current is Color:
		return Color(0.11 + float(index) * 0.01, 0.37, 0.59)
	return 0.131 + float(index) * 0.017


func _same(a: Variant, b: Variant) -> bool:
	if a is Color and b is Color:
		return (a as Color).is_equal_approx(b as Color)
	if a is float and b is float:
		return is_equal_approx(a as float, b as float)
	return false


func test_every_water_knob_reaches_a_uniform_of_its_own_name() -> void:
	var props := _water_props()
	assert_int(props.size()).override_failure_message(
			"no Water knobs declared; the case is vacuous").is_greater(0)
	# A DISTINCT value each, well away from any default, so a knob wired to the wrong uniform shows
	# up as the wrong number rather than agreeing with its neighbour by coincidence.
	var sent: Dictionary[String, Variant] = {}
	for i in props.size():
		var value: Variant = _probe(_mirror.get(props[i]), i)
		sent[props[i]] = value
		_mirror.pushed.clear()
		_mirror.set(props[i], value)
		assert_array(_mirror.pushed.keys()).override_failure_message(
				"setting BoardMirror.%s pushed %s -- a knob writes ITS OWN uniform and nothing " \
				% [props[i], _mirror.pushed.keys()] + "else").contains_exactly([props[i]])
		# A gdUnit assertion does not halt, so a wrong-name push has to be stepped over or the
		# clean failure above arrives wearing a script error from the lookup below.
		if not _mirror.pushed.has(props[i]):
			continue
		assert_bool(_same(_mirror.pushed[props[i]], value)).override_failure_message(
				"BoardMirror.%s pushed %s, not the %s it was given" \
				% [props[i], _mirror.pushed[props[i]], value]).is_true()
	# And the property kept what it was handed -- a setter that pushes but forgets to store leaves
	# the panel snapping back to the old number on its next refresh.
	for prop: String in sent:
		assert_bool(_same(_mirror.get(prop), sent[prop])).override_failure_message(
				"BoardMirror.%s pushed its value and did not keep it" % prop).is_true()


# _ready pushes the lot, and it has to: until something writes them the board wears project.godot's
# saved values, so an @export default edited in source would be ignored until someone happened to
# touch that slider. This is the case that catches a knob left out of _push_all_water.
func test_entering_the_tree_pushes_every_declared_default() -> void:
	_mirror.pushed.clear()
	get_tree().root.add_child(_mirror)
	await await_idle_frame()
	for prop in _water_props():
		var declared: Variant = _mirror.get(prop)
		assert_bool(_mirror.pushed.has(prop)).override_failure_message(
				"_ready pushed no uniform '%s' -- the board would wear project.godot's saved " \
				% prop + "value until someone moved that slider").is_true()
		# A gdUnit assertion does not halt, so the missing key has to be stepped over or the clean
		# failure above arrives wearing a script error from the lookup below.
		if not _mirror.pushed.has(prop):
			continue
		assert_bool(_same(_mirror.pushed[prop], declared)).override_failure_message(
				"_ready pushed '%s' as something other than its own declared default" % prop) \
				.is_true()


# The third leg, and the only one the RenderingServer will still answer headless: a global the
# shader names must actually be REGISTERED, or the shader refuses to compile at first render --
# which is a failure no test asserting on materials would see.
func test_every_water_uniform_is_registered_with_the_renderer() -> void:
	var registered := RenderingServer.global_shader_parameter_get_list()
	for prop in _water_props():
		assert_bool(registered.has(StringName(prop))).override_failure_message(
				"'%s' is not a registered global shader parameter -- project.godot's " % prop \
				+ "[shader_globals] and the knob table disagree").is_true()


# --- The board mask (#552 slice 2) --------------------------------------------------------------
#
# Foam is the one thing in this shader that has to know about the cell NEXT DOOR, and a meshlib item
# knows nothing about its neighbours -- which is the objection #552 filed against keeping water a
# meshlib item at all. The mask is the answer: one texel per cell, pushed down the same funnel as
# every knob above.
#
# It is BOARD DATA rather than tuning, so it has no knob and none of the cases above see it. What
# can drift here is different too: not a name, but whether the picture matches the board and whether
# anyone rebuilds it when the board moves.

const TILESET_PATH := "res://Resources/TestTiles.tres"


# A tile of each sort, read OFF the tileset rather than named here -- 5:6 and its neighbours are
# content, and a case that hardcodes them breaks the day the sheet is re-cut.
func _a_tile_of(kind_is_water: bool) -> Dictionary:
	var tiles := load(TILESET_PATH) as TileSet
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var atlas := tiles.get_source(source_id) as TileSetAtlasSource
		if atlas == null:
			continue
		for i in atlas.get_tiles_count():
			var coords := atlas.get_tile_id(i)
			if atlas.get_tile_size_in_atlas(coords) != Vector2i.ONE:
				continue
			var kind := GridUtils.terrain_kind_of(atlas.get_tile_data(coords, 0))
			if kind == Terrain.Kind.VOID or kind == Terrain.Kind.NONE:
				continue
			if (kind == Terrain.Kind.WATER) == kind_is_water:
				return {"tileset": tiles, "source": source_id, "coords": coords}
	return {}


# Painted at a deliberate OFFSET from the origin: a mask rect that quietly assumed (0,0) still
# passes over a board that starts there, and every real level starts somewhere else.
func _grid_with(water: Array[Vector2i], land: Array[Vector2i]) -> TileMapLayer:
	var wet := _a_tile_of(true)
	var dry := _a_tile_of(false)
	assert_bool(wet.is_empty() or dry.is_empty()).override_failure_message(
			"the tileset has no water tile or no land tile; these cases would be vacuous") \
			.is_false()
	var grid := TileMapLayer.new()
	grid.tile_set = wet["tileset"]
	for cell in water:
		grid.set_cell(cell, wet["source"], wet["coords"])
	for cell in land:
		grid.set_cell(cell, dry["source"], dry["coords"])
	return grid


func _pushed_mask_image() -> Image:
	assert_object(_mirror.pushed.get("water_board_mask")).override_failure_message(
			"nothing pushed a water_board_mask texture at all").is_not_null()
	assert_object(_mirror.mask_image).override_failure_message(
			"_push_mask was never reached").is_not_null()
	return _mirror.mask_image


# Per CELL, not in aggregate: a count of white texels passes while they sit in the wrong places,
# and where a cell's water lands is the entire point of the picture.
func _assert_mask_matches(grid: TileMapLayer, where: String) -> void:
	var image := _pushed_mask_image()
	if image == null:
		return
	var rect: Vector4 = _mirror.pushed["water_board_mask_rect"]
	var seen_water := false
	var seen_land := false
	for cell in grid.get_used_cells():
		var is_water := GridUtils.get_terrain_kind_at_cell(grid, cell) == Terrain.Kind.WATER
		seen_water = seen_water or is_water
		seen_land = seen_land or not is_water
		# The SIGN is what the shader thresholds, and it survives the encoding: R runs above 0.5
		# on the water side of a boundary and below it on the land side, at any scale.
		var texel := image.get_pixel(cell.x - int(rect.x), cell.y - int(rect.y))
		var reads_water := texel.r > 0.5
		assert_bool(reads_water == is_water).override_failure_message(
				"%s: cell %s is %s on the board but the mask reads it as %s -- the shoreline " \
				% [where, cell, "WATER" if is_water else "land",
						"water" if reads_water else "land"] \
				+ "would be drawn in the wrong place").is_true()
		# THE WALKABLE WIRE, which lived on the material's baked `deep` until slice 2b deleted it. A
		# tile that declares itself wadeable must not render as the water that drowns you, and the
		# mask is now the only thing saying which is which. Water cells only: a land texel's G is
		# the DILATE, asserted by its own case below.
		if is_water:
			var drowns := not GridUtils.walkable_of(grid.get_cell_tile_data(cell))
			assert_bool((texel.g > 0.5) == drowns).override_failure_message(
					"%s: cell %s declares walkable=%s and the mask renders it as %s water" \
					% [where, cell, not drowns, "deep" if texel.g > 0.5 else "shallow"]).is_true()
	# Both sorts present, or the comparison above proves nothing: an all-land board matches a mask
	# that is black because it was never filled in.
	assert_bool(seen_water and seen_land).override_failure_message(
			"%s: the fixture has only one sort of cell; the case is vacuous" % where).is_true()


func test_the_mask_says_water_exactly_where_the_board_does() -> void:
	var grid := _grid_with([Vector2i(4, 3), Vector2i(5, 3)], [Vector2i(4, 4), Vector2i(6, 3)])
	_mirror._rebuild_water_mask(grid)
	_assert_mask_matches(grid, "freshly built")
	grid.free()


# Where the picture LIVES. The shader turns a world position into a texel with this rect alone, so
# an origin one cell out slides the whole shoreline one cell sideways -- and nothing else in the
# suite would notice, because the picture itself would still be correct.
func test_the_mask_rect_is_the_board_it_was_built_from() -> void:
	var grid := _grid_with([Vector2i(4, 3)], [Vector2i(4, 4), Vector2i(6, 3)])
	_mirror._rebuild_water_mask(grid)
	var used := grid.get_used_rect()
	var rect: Vector4 = _mirror.pushed["water_board_mask_rect"]
	assert_bool(rect.is_equal_approx(Vector4(used.position.x, used.position.y,
			used.size.x, used.size.y))).override_failure_message(
			"mask rect %s does not describe the board's used rect %s -- a cell of drift here " \
			% [rect, used] + "slides every shoreline sideways").is_true()
	var image := _pushed_mask_image()
	if image != null:
		assert_bool(image.get_size() == used.size).override_failure_message(
				"the mask is %s for a board of %s" % [image.get_size(), used.size]).is_true()
	grid.free()


# An empty board still owes the shader a DEFINED mask: an unset sampler global reads as WHITE, which
# says every cell is water and puts a shoreline nowhere at all.
func test_an_empty_board_still_pushes_a_mask() -> void:
	var grid := TileMapLayer.new()
	_mirror._rebuild_water_mask(grid)
	var image := _pushed_mask_image()
	if image != null:
		assert_bool(image.get_pixel(0, 0).r < 0.5).override_failure_message(
				"an empty board pushed a WHITE mask -- the shader would read the whole world " \
				+ "as water").is_true()
	grid.free()


# THE case this slice exists for, and the one a call-count would only half ask. The mask is built
# from the board, so a mask built ONCE and never again is a shoreline frozen at whatever the board
# looked like when the level loaded -- and every other case in this file would stay green, because
# the first build is correct.
#
# So it asserts the CONSEQUENCE rather than the call: paint a land cell into water, run the door,
# and the picture has to have changed. Both doors, because sync() and sync_cells() are two entry
# points and only one of them is on the path a brush edit takes.
func test_both_sync_doors_rebuild_the_mask() -> void:
	_mirror.board = auto_free(GridMap.new())
	var heights := BoardHeights.new()
	var dry := _a_tile_of(false)
	var wet := _a_tile_of(true)
	var swing := Vector2i(6, 3)
	var grid := _grid_with([Vector2i(4, 3)], [Vector2i(4, 4), swing])

	_mirror.sync(grid, heights)
	_assert_mask_matches(grid, "after sync()")

	# The same cell, repainted -- so a stale mask is a WRONG mask rather than merely an old one.
	grid.set_cell(swing, wet["source"], wet["coords"])
	_mirror.sync_cells(grid, [swing], heights, _mirror.floor_row_of(heights))
	_assert_mask_matches(grid, "after sync_cells()")

	# And back the other way, so the case cannot pass on a mask that only ever gains water.
	grid.set_cell(swing, dry["source"], dry["coords"])
	_mirror.sync_cells(grid, [swing], heights, _mirror.floor_row_of(heights))
	_assert_mask_matches(grid, "after sync_cells() painted it back to land")
	grid.free()


# A water tile of a stated DEPTH, read off the tileset -- the cases below need a wadeable one and a
# drowning one specifically, which _a_tile_of(true) cannot promise.
func _a_water_tile_of(walkable: bool) -> Dictionary:
	var tiles := load(TILESET_PATH) as TileSet
	for s in tiles.get_source_count():
		var source_id := tiles.get_source_id(s)
		var atlas := tiles.get_source(source_id) as TileSetAtlasSource
		if atlas == null:
			continue
		for i in atlas.get_tiles_count():
			var coords := atlas.get_tile_id(i)
			if atlas.get_tile_size_in_atlas(coords) != Vector2i.ONE:
				continue
			var data := atlas.get_tile_data(coords, 0)
			if GridUtils.terrain_kind_of(data) != Terrain.Kind.WATER:
				continue
			if GridUtils.walkable_of(data) == walkable:
				return {"tileset": tiles, "source": source_id, "coords": coords}
	return {}


func _texel(image: Image, rect: Vector4, cell: Vector2i) -> Color:
	return image.get_pixel(cell.x - int(rect.x), cell.y - int(rect.y))


# THE property slice 2b bought, and the one a BITMAP cannot have: R is a real DISTANCE, so it keeps
# rising as you move away from the shore instead of saturating at the first cell.
#
# That is not a cosmetic difference. Thresholding a binary mask gives a foam band whose width
# follows the interpolation GRADIENT -- steep across a straight edge, shallow near a corner -- which
# is why an L-shaped patch grew a fat mushy corner while its straight runs stayed crisp. A field
# with a constant gradient gives a band with a constant width.
#
# No encoded VALUE is pinned, only the ordering: the encoding is free to move.
func test_the_shore_field_deepens_with_distance_from_land() -> void:
	var wet := _a_water_tile_of(false)
	var dry := _a_tile_of(false)
	var grid := TileMapLayer.new()
	grid.tile_set = wet["tileset"]
	# A 4x4 lake ringed by land, so there is a cell two clear cells in from every shore.
	for y in 6:
		for x in 6:
			var inside: bool = x >= 1 and x <= 4 and y >= 1 and y <= 4
			var tile: Dictionary = wet if inside else dry
			grid.set_cell(Vector2i(x, y), tile["source"], tile["coords"])
	_mirror._rebuild_water_mask(grid)
	var image := _pushed_mask_image()
	if image != null:
		var rect: Vector4 = _mirror.pushed["water_board_mask_rect"]
		var shore_side := _texel(image, rect, Vector2i(1, 1)).r
		var two_in := _texel(image, rect, Vector2i(2, 2)).r
		var on_land := _texel(image, rect, Vector2i(0, 1)).r
		assert_bool(shore_side > 0.5).override_failure_message(
				"water touching land reads %f, on the LAND side of the shoreline" % shore_side) \
				.is_true()
		assert_bool(on_land < 0.5).override_failure_message(
				"land touching water reads %f, on the WATER side of the shoreline" % on_land) \
				.is_true()
		assert_bool(two_in > shore_side).override_failure_message(
				"a cell two in from the shore reads %f and one touching it reads %f -- the mask " \
				% [two_in, shore_side] + "is still a BITMAP, so the foam band's width will " \
				+ "follow the interpolation gradient and corners will read rough").is_true()
	grid.free()


# The DILATE, and it is the difference between a blend and a bug. Bilinear from a deep cell's centre
# reaches into its LAND neighbours, so a land texel carrying 0 would drag deep water toward shallow
# along every cliff rim and fade the bed in where no bottom should show.
#
# Asserted as a PAIR, because "land next to water reads deep" would pass on a dilate that just wrote
# 1 everywhere. What has to be true is that the land carries the deepness of the water beside IT.
func test_land_carries_the_deepness_of_the_water_beside_it() -> void:
	var deep := _a_water_tile_of(false)
	var shallow := _a_water_tile_of(true)
	var dry := _a_tile_of(false)
	assert_bool(deep.is_empty() or shallow.is_empty()).override_failure_message(
			"the tileset lacks a wadeable or a drowning water tile; the case is vacuous").is_false()
	if deep.is_empty() or shallow.is_empty():
		return
	var grid := TileMapLayer.new()
	grid.tile_set = deep["tileset"]
	# Deep on the left, shallow on the right, a land column between them touching only one each.
	grid.set_cell(Vector2i(0, 0), deep["source"], deep["coords"])
	grid.set_cell(Vector2i(1, 0), dry["source"], dry["coords"])
	grid.set_cell(Vector2i(3, 0), shallow["source"], shallow["coords"])
	grid.set_cell(Vector2i(2, 0), dry["source"], dry["coords"])
	_mirror._rebuild_water_mask(grid)
	var image := _pushed_mask_image()
	if image != null:
		var rect: Vector4 = _mirror.pushed["water_board_mask_rect"]
		assert_bool(_texel(image, rect, Vector2i(1, 0)).g > 0.5).override_failure_message(
				"the land cell beside DEEP water reads shallow -- every cliff rim will drag its " \
				+ "own water toward shallow and fade the bed in against the wall").is_true()
		assert_bool(_texel(image, rect, Vector2i(2, 0)).g < 0.5).override_failure_message(
				"the land cell beside SHALLOW water reads deep -- the dilate is writing a " \
				+ "constant rather than carrying the neighbouring water's own depth").is_true()
	grid.free()
