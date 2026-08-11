# The tile hover readout (#135), on the real scene: hovering a cell that is anything other
# than ordinary ground shows a readout block; ordinary ground shows nothing; a unit standing
# on a notable tile shows BOTH halves of the stack. Driven through the real hover path
# (HoverPresenter.update_hover_visuals), because the composition, the panel and the parking
# only meet there — same lesson as every suite in this folder.
#
# Fixture is test_menu_catalogue_rows.gd's: the real game scene, a row of grass.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

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


func test_a_burning_tile_explains_itself_on_hover() -> void:
	var cell := Vector2i(3, 0)
	_set_tile_state(cell, Terrain.TileState.BURNING)
	game.hover_presenter.update_hover_visuals(cell)
	await await_idle_frame()

	assert_bool(game.hover_info_panel.visible) \
		.override_failure_message("hovering a burning tile showed no card at all").is_true()
	assert_bool(game.hover_info_panel._tile_panel.visible) \
		.override_failure_message("the card is up but the tile block is not").is_true()
	assert_str(_tile_block_text()) \
		.override_failure_message("the tile block never names Burning: '%s'" % _tile_block_text()) \
		.contains(Terrain.tile_state_display_name(Terrain.TileState.BURNING))
	# The unit half must NOT be up — nobody is standing there.
	assert_bool(game.hover_info_panel.hover_panel.visible).is_false()


func test_ordinary_ground_shows_nothing() -> void:
	game.hover_presenter.update_hover_visuals(Vector2i(2, 0))
	await await_idle_frame()
	assert_bool(game.hover_info_panel.visible) \
		.override_failure_message("plain grass grew a hover card — 'anything other than normal' is the spec") \
		.is_false()


func test_a_unit_on_a_burning_tile_shows_both_halves() -> void:
	var cell := Vector2i(4, 0)
	_set_tile_state(cell, Terrain.TileState.BURNING)
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()

	game.hover_presenter.update_hover_visuals(cell)
	await await_idle_frame()

	assert_bool(game.hover_info_panel.visible).is_true()
	assert_bool(game.hover_info_panel.hover_panel.visible) \
		.override_failure_message("the unit half vanished when the tile block joined it").is_true()
	assert_bool(game.hover_info_panel._tile_panel.visible) \
		.override_failure_message("the tile block vanished under a standing unit").is_true()
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
