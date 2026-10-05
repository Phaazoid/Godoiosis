# The tile card (#135, rebuilt round 2; asked for by a CLICK since #1105), on the real scene: EVERY
# real tile shows a card (icon + name header), states join as content with their live clocks, and
# the interactions list is filtered through the resolver's own predicate
# (TerrainReaction.applies_to_tile) so the card never promises a deposit the resolver refuses.
# Driven through the real click door (game._on_left_click), because composition, panel and parking
# only meet there. What a click on a UNIT, the ring and Inspect do is tests/ui/test_tile_inspect.gd.
#
# The card reads the TILE'S OWN data since 2026-08-12 -- authored terrain_name first, kind name
# as the fallback, the tile's sprite as the picture (the palette rows' policy, shared through
# GridUtils). Fixture is a SYNTHETIC tileset (the palette suite's pattern): the dev names his
# real TestTiles content live, so header assertions against it would move under his authoring.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_ATLAS := Vector2i(0, 0)         # unnamed GRASS -- the default paint, kind fallback
const NAMED_GRASS_ATLAS := Vector2i(1, 0)   # GRASS authored "spring meadow"
const CRATE_ATLAS := Vector2i(2, 0)         # kindless scenery authored "crate"
const WATER_ATLAS := Vector2i(3, 0)         # unnamed WATER, no walkable flag (impassable)
const STONE_ATLAS := Vector2i(4, 0)         # DIRT: no ignition reaction keys on it, so it is not fuel

var _main: Node
var game: Node2D
var _src_id: int


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	game.grid.tile_set = _build_tile_set()
	for x in range(8):
		game.grid.set_cell(Vector2i(x, 0), _src_id, GRASS_ATLAS)
	game.grid.set_cell(Vector2i(0, 1), _src_id, WATER_ATLAS)
	await await_idle_frame()


func _build_tile_set() -> TileSet:
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(16, 16)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(0, "walkable")
	tiles.set_custom_data_layer_type(0, TYPE_BOOL)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(1, "move_cost")
	tiles.set_custom_data_layer_type(1, TYPE_INT)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(2, "terrain_type")
	tiles.set_custom_data_layer_type(2, TYPE_INT)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(3, "terrain_name")
	tiles.set_custom_data_layer_type(3, TYPE_STRING)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(
		Image.create_empty(80, 16, false, Image.FORMAT_RGBA8))
	source.texture_region_size = Vector2i(16, 16)
	_src_id = tiles.add_source(source)
	_author_tile(source, GRASS_ATLAS, Terrain.Kind.GRASS, "", true)
	_author_tile(source, NAMED_GRASS_ATLAS, Terrain.Kind.GRASS, "spring meadow", true)
	_author_tile(source, CRATE_ATLAS, Terrain.Kind.NONE, "crate", false)
	_author_tile(source, WATER_ATLAS, Terrain.Kind.WATER, "", false)
	_author_tile(source, STONE_ATLAS, Terrain.Kind.DIRT, "flagstones", true)
	return tiles


func _author_tile(source: TileSetAtlasSource, coords: Vector2i, kind: Terrain.Kind,
		tile_name: String, walkable: bool) -> void:
	source.create_tile(coords)
	var data := source.get_tile_data(coords, 0)
	if walkable:
		data.set_custom_data("walkable", true)
	data.set_custom_data("move_cost", 1)
	if kind != Terrain.Kind.NONE:
		data.set_custom_data("terrain_type", kind)
	if tile_name != "":
		data.set_custom_data("terrain_name", tile_name)


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _set_tile_state(cell: Vector2i, state: Terrain.TileState) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added = [state]
	game.terrain_states.apply(effect)


func _click(cell: Vector2i) -> void:
	game._on_left_click(cell)
	await await_idle_frame()


func _tile_block_text() -> String:
	return "\n".join(game.hover_info_panel.tile_texts())


func _tile_header_text() -> String:
	return game.hover_info_panel._tile_header.text


# Mirrors the park predicate's inputs (panel viewport's canvas transform over the cell's world
# position) — used only to FIND a suitable cell; the truth check is the in-test vacuity guard.
func _screen_pos_in_top_half(cell: Vector2i) -> bool:
	var panel: Control = game.hover_info_panel
	var world_pos: Vector2 = game.grid.to_global(game.grid.map_to_local(cell))
	var screen_pos: Vector2 = panel.get_viewport().get_canvas_transform() * world_pos
	return screen_pos.y <= panel.get_viewport_rect().size.y / 2.0


func test_every_tile_shows_a_card_with_its_kind() -> void:
	# Round 2 flip: plain grass shows the card too — the trigger is "a real tile", not "a notable
	# one" (dev: "it should trigger on every tile").
	await _click(Vector2i(2, 0))

	assert_bool(game.hover_info_panel.visible) \
		.override_failure_message("plain grass shows no tile card — the every-tile trigger is gone").is_true()
	assert_bool(game.hover_info_panel._tile_panel.visible).is_true()
	assert_str(_tile_header_text()).is_equal(Terrain.kind_display_name(Terrain.Kind.GRASS))
	assert_object(game.hover_info_panel._tile_icon.texture) \
		.override_failure_message("the tile card has no kind picture").is_not_null()
	# And the unit card stays down — nobody is standing there.
	assert_bool(game.hover_info_panel.hover_panel.visible).is_false()


func test_the_pointer_never_raises_or_clears_a_card() -> void:
	# #582 was a card describing a cell the pointer had LEFT. Since #1105 the card describes the cell
	# that was CLICKED, so the pointer is simply not its business: hovering raises none, and moving
	# on -- off the map included -- leaves a clicked one standing, still about the clicked tile.
	game.hover_presenter.update_hover_visuals(Vector2i(2, 0))
	await await_idle_frame()
	assert_bool(game.hover_info_panel.visible) \
		.override_failure_message("hovering a tile put up a card").is_false()

	await _click(Vector2i(2, 0))
	var off_map := Vector2i(-40, -40)
	assert_object(game.grid.get_cell_tile_data(off_map)) \
		.override_failure_message("the fixture grew a tile out there").is_null()
	game.hover_presenter.update_hover_visuals(Vector2i(5, 0))
	game.hover_presenter.update_hover_visuals(off_map)
	await await_idle_frame()

	assert_bool(game.hover_info_panel.is_showing_tile_at(Vector2i(2, 0))) \
		.override_failure_message("the pointer moved or took down a card the player clicked for").is_true()


func test_dev_mode_does_not_inherit_the_last_card_from_play() -> void:
	# The other half of #582, and the one that actually bit: DEV_MODE never wrote the card at all,
	# so it held whatever play last left -- a readout from before the mode was even entered.
	# Cleared rather than filled, because the dev-mode height readout belongs to
	# HeightDebugOverlay and must not gain a second voice.
	await _click(Vector2i(2, 0))
	assert_bool(game.hover_info_panel.visible) \
		.override_failure_message("no card to carry over; the case is vacuous").is_true()

	game.game_state = game.GameState.DEV_MODE
	game.hover_presenter.update_hover_visuals(Vector2i(3, 0))
	await await_idle_frame()
	assert_bool(game.hover_info_panel.visible) \
		.override_failure_message("the play card followed the dev into DEV_MODE").is_false()


func test_a_named_tile_headers_its_authored_name() -> void:
	# The 2026-08-12 report: the card assumed the name off the Kind enum, so an authored
	# variant read as plain "Grass" however it was named.
	game.grid.set_cell(Vector2i(6, 0), _src_id, NAMED_GRASS_ATLAS)
	await _click(Vector2i(6, 0))

	assert_str(_tile_header_text()).is_equal("Spring Meadow")


func test_named_kindless_scenery_gets_a_named_card() -> void:
	# Kind NONE used to mean a headerless card no matter what the tile was authored as -- a
	# Crate is scenery with a name, and the card must say so.
	game.grid.set_cell(Vector2i(6, 0), _src_id, CRATE_ATLAS)
	await _click(Vector2i(6, 0))

	assert_bool(game.hover_info_panel._tile_panel.visible).is_true()
	assert_str(_tile_header_text()).is_equal("Crate")


func test_the_card_icon_is_the_tiles_own_sprite() -> void:
	# The icon is the tile's actual art (an AtlasTexture cut from its own sheet region), not the
	# hand-drawn kind icon -- TERRAIN_ICONS stays the queue rows' pathing glyph. NB the region
	# getter returns Rect2i while AtlasTexture.region is Rect2; Variant equality across them is
	# FALSE, hence the wrap.
	await _click(Vector2i(2, 0))

	var icon := game.hover_info_panel._tile_icon.texture as AtlasTexture
	assert_object(icon).is_not_null()
	var source := (game.grid.tile_set as TileSet).get_source(_src_id) as TileSetAtlasSource
	assert_object(icon.atlas).is_same(source.texture)
	assert_that(icon.region).is_equal(Rect2(source.get_tile_texture_region(GRASS_ATLAS)))


# The picture is the board's own tile sprite, so bare on the card it read as a hole through to the
# board (#955): it sits in a frame. Asked as an OVERRIDE, because get_theme_stylebox answers for a
# control that brings nothing of its own.
func test_the_card_picture_sits_in_a_frame() -> void:
	await _click(Vector2i(2, 0))

	var well: PanelContainer = game.hover_info_panel._tile_well
	assert_bool(well.is_ancestor_of(game.hover_info_panel._tile_icon)).is_true()
	assert_bool(well.visible).is_true()
	assert_bool(well.has_theme_stylebox_override("panel")).is_true()
	assert_object(well.get_theme_stylebox("panel")).is_same(QueueStyle.section_box())


# Each zone KIND on a tile heads its own section with the emblem the board wears for it, in the
# kind's colour (#955) -- the watch section's mechanism, one texture and one colour for both surfaces.
func test_each_zone_kind_heads_its_own_section_with_its_emblem() -> void:
	var cell := Vector2i(4, 0)
	game.zone_manager.paint_cell("North Point", ZoneManager.Kind.CAPTURE, cell)
	game.zone_manager.paint_cell("The Landing", ZoneManager.Kind.DEPLOYMENT, cell)

	var zones: Array[TileReadout.Section] = []
	for section in TileReadout.compose(game, cell):
		if section.layer == TileReadout.Layer.ZONE:
			zones.append(section)
	assert_int(zones.size()).override_failure_message("two kinds on one tile, one section each").is_equal(2)
	var capture := zones[0]
	assert_str(capture.heading).is_equal(Glossary.title(Glossary.Term.CAPTURE_ZONE))
	assert_object(capture.marking).is_same(ZoneMarks.emblem_of(ZoneManager.Kind.CAPTURE))
	assert_that(capture.marking_color).is_equal(ZoneMarks.colour_of(ZoneManager.Kind.CAPTURE))
	assert_str(capture.rows[0].text).is_equal("North Point")
	assert_bool(capture.rows[-1].note).is_true()
	assert_object(zones[1].marking).is_same(ZoneMarks.emblem_of(ZoneManager.Kind.DEPLOYMENT))

	# ...and the card DRAWS it: the mark heads the section in the kind's colour.
	await _click(cell)
	var drawn := false
	for rect in game.hover_info_panel._tile_panel.find_children("*", "TextureRect", true, false):
		var mark := rect as TextureRect
		if mark.texture == ZoneMarks.emblem_of(ZoneManager.Kind.CAPTURE) \
				and mark.modulate == ZoneMarks.colour_of(ZoneManager.Kind.CAPTURE):
			drawn = true
	assert_bool(drawn).override_failure_message("the card drew no capture emblem").is_true()


func test_a_burning_tile_works_the_state_into_the_card() -> void:
	var cell := Vector2i(3, 0)
	_set_tile_state(cell, Terrain.TileState.BURNING)
	await _click(cell)

	assert_bool(game.hover_info_panel._tile_panel.visible).is_true()
	assert_str(_tile_header_text()).is_equal(Terrain.kind_display_name(Terrain.Kind.GRASS))
	assert_str(_tile_block_text()) \
		.override_failure_message("the card never names Burning: '%s'" % _tile_block_text()) \
		.contains(Terrain.tile_state_display_name(Terrain.TileState.BURNING))


func test_a_units_inspect_shows_its_burning_tile_beside_the_dock() -> void:
	# A unit's tile is read in the card beside its Inspect dock (#1105), never inside the dock.
	var cell := Vector2i(4, 0)
	_set_tile_state(cell, Terrain.TileState.BURNING)
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()

	game.inspect_unit(unit)
	await await_idle_frame()

	assert_bool(game.unit_info_panel.is_showing_unit(unit)).is_true()
	assert_bool(game.hover_info_panel._tile_panel.visible) \
		.override_failure_message("the unit's tile has no card beside its dock").is_true()
	assert_bool(game.hover_info_panel.hover_panel.visible) \
		.override_failure_message("a unit card beside the dock that already shows the unit").is_false()
	assert_str(_tile_block_text()).contains(Terrain.tile_state_display_name(Terrain.TileState.BURNING))


func test_a_frozen_slow_tile_no_longer_reads_slow_going() -> void:
	# The card prints the cost the RULES charge (#1223): ice costs Terrain.FROZEN_MOVE_COST whatever
	# the tile underneath authors, so a frozen slow tile is not "slow going" any more.
	var data: TileData = (game.grid.tile_set.get_source(_src_id) as TileSetAtlasSource) \
		.get_tile_data(STONE_ATLAS, 0)
	data.set_custom_data("move_cost", Terrain.FROZEN_MOVE_COST + 2)
	var thawed := Vector2i(6, 0)
	var frozen := Vector2i(7, 0)
	game.grid.set_cell(thawed, _src_id, STONE_ATLAS)
	game.grid.set_cell(frozen, _src_id, STONE_ATLAS)
	_set_tile_state(frozen, Terrain.TileState.FROZEN)

	await _click(thawed)
	assert_str(_tile_block_text()) \
		.override_failure_message("a slow tile's card lost its cost line: '%s'" % _tile_block_text()) \
		.contains("Slow going")
	await _click(frozen)
	assert_str(_tile_block_text()) \
		.override_failure_message("a FROZEN slow tile still reads slow: '%s'" % _tile_block_text()) \
		.not_contains("Slow going")


func test_a_fire_on_ground_that_is_not_fuel_shows_no_countdown() -> void:
	# The BLAZE case re-aimed by #890, which retired that state: a fire's clock comes from its
	# GROUND, and flagstones give it none, so the readout must not invent one. The counting half is
	# pinned by the BURNING case above, which sits on grass.
	var cell := Vector2i(5, 0)
	game.grid.set_cell(cell, _src_id, STONE_ATLAS)
	_set_tile_state(cell, Terrain.TileState.BURNING)
	await _click(cell)

	assert_str(_tile_block_text()) \
		.contains(Terrain.tile_state_display_name(Terrain.TileState.BURNING))
	assert_str(_tile_block_text()) \
		.override_failure_message("a fire with no fuel rendered a turns-left clock: '%s'" % _tile_block_text()) \
		.not_contains("left.")


func test_a_bottom_parked_card_stays_on_screen_after_a_taller_one() -> void:
	# Dev report (2026-08-11): a card parked on the bottom half ran mostly off screen. The
	# mechanism is the RATCHET: a free-floating container grows to fit content but never shrinks
	# back on its own, so moving from card to card pumps the panel up to the tallest card ever
	# shown — and a SHORT card parked bottom then draws that stale, taller size past the screen
	# edge. So: show a tall card first, then a short one that parks bottom, and require the drawn
	# rect to sit inside the viewport. Where the fixture's rows land on screen depends on the
	# camera, so the case SEARCHES upward for a cell whose screen position is in the top half
	# (painting grass as it climbs) — the vacuity guard below independently proves the short card
	# really parked bottom.
	var tall_cell := Vector2i(3, 0)
	_set_tile_state(tall_cell, Terrain.TileState.BURNING)   # state line + long wrap = a tall card
	await _click(tall_cell)
	for _i in 4:
		await get_tree().process_frame

	var cell := Vector2i(3, 0)
	var attempts := 0
	while not _screen_pos_in_top_half(cell):
		cell.y -= 1
		game.grid.set_cell(cell, _src_id, GRASS_ATLAS)
		attempts += 1
		assert_int(attempts) \
			.override_failure_message("could not find a cell in the top half of the viewport — fixture camera assumption is broken") \
			.is_less(50)
	await _click(cell)   # plain grass: the SHORT card
	for _i in 4:
		await get_tree().process_frame

	assert_bool(game.hover_info_panel._tile_panel.visible).is_true()
	var rect: Rect2 = game.hover_info_panel._tile_panel.get_global_rect()
	var viewport_height: float = game.hover_info_panel.get_viewport_rect().size.y
	# Vacuity guard: this case is about BOTTOM parking — if the card parked top, the overflow
	# assertion below could never fail and the case would be toothless.
	assert_bool(rect.position.y > viewport_height / 2.0) \
		.override_failure_message("fixture assumption broke: the card parked on the top half (top %.0f of %.0f), so this case is not exercising bottom parking"
			% [rect.position.y, viewport_height]) \
		.is_true()
	assert_bool(rect.end.y <= viewport_height + 0.5) \
		.override_failure_message("the bottom-parked tile card overflows the screen: bottom edge %.0f of %.0f"
			% [rect.end.y, viewport_height]) \
		.is_true()
	assert_bool(rect.position.y >= 0.0).is_true()


func test_the_interactions_list_matches_the_catalog() -> void:
	# Expectation derived FROM the authored catalog, never pinned prose: every reaction whose
	# own applies_to_tile passes for a bare water tile must be named on water's card (ice ->
	# frozen is the authored one today), and none of the refused ones may leak on.
	var cell := Vector2i(0, 1)
	assert_int(game._board().terrain_kind_at(cell)) \
		.override_failure_message("fixture assumption broke: the painted cell is not WATER") \
		.is_equal(Terrain.Kind.WATER)

	var expected: Array[TerrainReaction] = []
	for reaction: TerrainReaction in TerrainReactionCatalog.get_all():
		if reaction.applies_to_tile(Terrain.Kind.WATER, [] as Array[Terrain.TileState]):
			expected.append(reaction)
	assert_int(expected.size()) \
		.override_failure_message("no authored reaction touches bare water — this case is vacuous; point it at a kind the catalog covers") \
		.is_greater(0)

	await _click(cell)
	var text := _tile_block_text()
	for reaction: TerrainReaction in expected:
		assert_str(text) \
			.override_failure_message("water's card never names %s — the interactions list is not rendering: '%s'"
				% [Elemental.display_name(reaction.incoming_element), text]) \
			.contains(Elemental.display_name(reaction.incoming_element))
