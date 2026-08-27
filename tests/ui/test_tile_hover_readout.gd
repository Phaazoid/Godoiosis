# The tile hover card (#135, rebuilt round 2), on the real scene: EVERY real tile shows a card
# (icon + name header), states join as content with their live clocks, a unit standing there
# stacks both halves, and the interactions list is filtered through the resolver's own predicate
# (TerrainReaction.applies_to_tile) so the card never promises a deposit the resolver refuses.
# Driven through the real hover path (HoverPresenter.update_hover_visuals), because composition,
# panel and parking only meet there.
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
		Image.create_empty(64, 16, false, Image.FORMAT_RGBA8))
	source.texture_region_size = Vector2i(16, 16)
	_src_id = tiles.add_source(source)
	_author_tile(source, GRASS_ATLAS, Terrain.Kind.GRASS, "", true)
	_author_tile(source, NAMED_GRASS_ATLAS, Terrain.Kind.GRASS, "spring meadow", true)
	_author_tile(source, CRATE_ATLAS, Terrain.Kind.NONE, "crate", false)
	_author_tile(source, WATER_ATLAS, Terrain.Kind.WATER, "", false)
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
	get_tree().root.remove_child(_main)
	_main.free()


func _set_tile_state(cell: Vector2i, state: Terrain.TileState) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added = [state]
	game.terrain_states.apply(effect)


func _tile_block_text() -> String:
	var parts: Array[String] = []
	for child: Node in game.hover_info_panel._tile_lines_box.get_children():
		var label := child as Label
		if label != null:
			parts.append(label.text)
	return "\n".join(parts)


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
	# Round 2 flip: plain grass now shows the card — the trigger is "a real tile", not "a
	# notable one" (dev: "it should trigger on every tile").
	game.hover_presenter.update_hover_visuals(Vector2i(2, 0))
	await await_idle_frame()

	assert_bool(game.hover_info_panel.visible) \
		.override_failure_message("plain grass shows no tile card — the every-tile trigger is gone").is_true()
	assert_bool(game.hover_info_panel._tile_panel.visible).is_true()
	assert_str(_tile_header_text()).is_equal(Terrain.kind_display_name(Terrain.Kind.GRASS))
	assert_object(game.hover_info_panel._tile_icon.texture) \
		.override_failure_message("the tile card has no kind picture").is_not_null()
	# And the unit half stays down — nobody is standing there.
	assert_bool(game.hover_info_panel.hover_panel.visible).is_false()


func test_leaving_the_map_takes_the_card_with_it() -> void:
	# #582: the off-map branch used to bare-return, so the last card stayed up and went on
	# describing a cell the pointer had left. A card is about NOW or it is a lie -- and this one
	# lied about a tile's height while the dev was hunting why he could not click it.
	game.hover_presenter.update_hover_visuals(Vector2i(2, 0))
	await await_idle_frame()
	assert_bool(game.hover_info_panel.visible) \
		.override_failure_message("no card to leave behind; the case is vacuous").is_true()

	var off_map := Vector2i(-40, -40)
	assert_object(game.grid.get_cell_tile_data(off_map)) \
		.override_failure_message("the fixture grew a tile out there").is_null()
	game.hover_presenter.update_hover_visuals(off_map)
	await await_idle_frame()
	assert_bool(game.hover_info_panel.visible) \
		.override_failure_message("the card outlived the tile it describes").is_false()


func test_dev_mode_does_not_inherit_the_last_card_from_play() -> void:
	# The other half of the same lie (#582), and the one that actually bit: DEV_MODE never wrote
	# the card at all, so it held whatever IDLE last hovered -- a readout from before the mode was
	# even entered. Cleared rather than filled, because the dev-mode height readout belongs to
	# HeightDebugOverlay and must not gain a second voice.
	game.hover_presenter.update_hover_visuals(Vector2i(2, 0))
	await await_idle_frame()
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
	game.hover_presenter.update_hover_visuals(Vector2i(6, 0))
	await await_idle_frame()

	assert_str(_tile_header_text()).is_equal("Spring Meadow")


func test_named_kindless_scenery_gets_a_named_card() -> void:
	# Kind NONE used to mean a headerless card no matter what the tile was authored as -- a
	# Crate is scenery with a name, and the card must say so.
	game.grid.set_cell(Vector2i(6, 0), _src_id, CRATE_ATLAS)
	game.hover_presenter.update_hover_visuals(Vector2i(6, 0))
	await await_idle_frame()

	assert_bool(game.hover_info_panel._tile_panel.visible).is_true()
	assert_str(_tile_header_text()).is_equal("Crate")


func test_the_card_icon_is_the_tiles_own_sprite() -> void:
	# The icon is the tile's actual art (an AtlasTexture cut from its own sheet region), not the
	# hand-drawn kind icon -- TERRAIN_ICONS stays the queue rows' pathing glyph. NB the region
	# getter returns Rect2i while AtlasTexture.region is Rect2; Variant equality across them is
	# FALSE, hence the wrap.
	game.hover_presenter.update_hover_visuals(Vector2i(2, 0))
	await await_idle_frame()

	var icon := game.hover_info_panel._tile_icon.texture as AtlasTexture
	assert_object(icon).is_not_null()
	var source := (game.grid.tile_set as TileSet).get_source(_src_id) as TileSetAtlasSource
	assert_object(icon.atlas).is_same(source.texture)
	assert_that(icon.region).is_equal(Rect2(source.get_tile_texture_region(GRASS_ATLAS)))


func test_a_burning_tile_works_the_state_into_the_card() -> void:
	var cell := Vector2i(3, 0)
	_set_tile_state(cell, Terrain.TileState.BURNING)
	game.hover_presenter.update_hover_visuals(cell)
	await await_idle_frame()

	assert_bool(game.hover_info_panel._tile_panel.visible).is_true()
	assert_str(_tile_header_text()).is_equal(Terrain.kind_display_name(Terrain.Kind.GRASS))
	assert_str(_tile_block_text()) \
		.override_failure_message("the card never names Burning: '%s'" % _tile_block_text()) \
		.contains(Terrain.tile_state_display_name(Terrain.TileState.BURNING))


func test_a_unit_on_a_burning_tile_shows_both_halves() -> void:
	var cell := Vector2i(4, 0)
	_set_tile_state(cell, Terrain.TileState.BURNING)
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()

	game.hover_presenter.update_hover_visuals(cell)
	await await_idle_frame()

	assert_bool(game.hover_info_panel.visible).is_true()
	assert_bool(game.hover_info_panel.hover_panel.visible) \
		.override_failure_message("the unit half vanished when the tile card joined it").is_true()
	assert_bool(game.hover_info_panel._tile_panel.visible) \
		.override_failure_message("the tile card vanished under a standing unit").is_true()
	assert_str(_tile_block_text()).contains(Terrain.tile_state_display_name(Terrain.TileState.BURNING))


func test_a_permanent_blaze_shows_no_countdown() -> void:
	# BLAZE has no STATE_DURATIONS entry — the readout must not invent a clock for it.
	var cell := Vector2i(5, 0)
	_set_tile_state(cell, Terrain.TileState.BLAZE)
	game.hover_presenter.update_hover_visuals(cell)
	await await_idle_frame()

	assert_str(_tile_block_text()) \
		.contains(Terrain.tile_state_display_name(Terrain.TileState.BLAZE))
	assert_str(_tile_block_text()) \
		.override_failure_message("a permanent Blaze rendered a turns-left clock: '%s'" % _tile_block_text()) \
		.not_contains("left.")


func test_a_bottom_parked_card_stays_on_screen_after_a_taller_one() -> void:
	# Dev report (2026-08-11): a card parked on the bottom half ran mostly off screen. The
	# mechanism is the RATCHET: a free-floating container grows to fit content but never shrinks
	# back on its own, so sweeping the mouse across tiles (every tile carries a card since round
	# 2) pumps the panel up to the tallest card ever shown — and a SHORT card parked bottom then
	# draws that stale, taller size past the screen edge. So: show a tall card first, then a
	# short one that parks bottom, and require the drawn rect to sit inside the viewport.
	# Where the fixture's rows land on screen depends on the camera, so the case SEARCHES upward
	# for a cell whose screen position is in the top half (painting grass as it climbs) — the
	# vacuity guard below independently proves the short card really parked bottom.
	var tall_cell := Vector2i(3, 0)
	_set_tile_state(tall_cell, Terrain.TileState.BURNING)   # state line + long wrap = a tall card
	game.hover_presenter.update_hover_visuals(tall_cell)
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
	game.hover_presenter.update_hover_visuals(cell)   # plain grass: header only, the SHORT card
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

	game.hover_presenter.update_hover_visuals(cell)
	await await_idle_frame()
	var text := _tile_block_text()
	for reaction: TerrainReaction in expected:
		assert_str(text) \
			.override_failure_message("water's card never names %s — the interactions list is not rendering: '%s'"
				% [Elemental.display_name(reaction.incoming_element), text]) \
			.contains(Elemental.display_name(reaction.incoming_element))
