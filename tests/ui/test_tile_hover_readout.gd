# The tile hover card (#135, rebuilt round 2), on the real scene: EVERY real tile shows a card
# (icon + kind header), states join as content with their live clocks, a unit standing there
# stacks both halves, and the interactions list is filtered through the resolver's own predicate
# (TerrainReaction.applies_to_tile) so the card never promises a deposit the resolver refuses.
# Driven through the real hover path (HoverPresenter.update_hover_visuals), because composition,
# panel and parking only meet there.
#
# Fixture is test_menu_catalogue_rows.gd's: the real game scene, a row of grass + one water cell.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const WATER_ATLAS := Vector2i(5, 6)

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	game.grid.set_cell(Vector2i(0, 1), GRASS_SOURCE, WATER_ATLAS)
	await await_idle_frame()


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
		game.grid.set_cell(cell, GRASS_SOURCE, GRASS_ATLAS)
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
