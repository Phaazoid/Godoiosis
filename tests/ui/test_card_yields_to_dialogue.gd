# THE DIALOGUE OWNS THE BOTTOM STRIP WHILE IT TALKS (#1033). The info card parks on the screen half
# opposite what it describes, and with the Inspect dock open its bottom park sat on the dialogue box
# (a playtester's report). Ruled (dev, 2026-10-08): while a dialogue is up, a card that would park at
# the bottom parks at the top instead, and goes back down when the dialogue ends.
#
# Driven through the real doors: game.show_tile_card opens the card, ScenarioDirector.preview plays a
# real timeline, and the card is told nothing -- it asks the director's own is_talking through the
# source game.gd wires, which is the wire these cases exist to see.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
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
	game.scenario_director.disarm()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	get_tree().root.remove_child(_main)
	_main.free()


func _card() -> HoverInfoPanelControl:
	return game.hover_info_panel


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# A cell drawn in the screen's top half, so its card parks at the BOTTOM -- the park in question.
# Searched for rather than assumed, because where a row lands on screen is the camera's business.
func _top_half_cell() -> Vector2i:
	var cell := Vector2i(3, 0)
	var attempts := 0
	while true:
		var world_pos: Vector2 = game.grid.to_global(game.grid.map_to_local(cell))
		var screen_pos: Vector2 = _card().get_viewport().get_canvas_transform() * world_pos
		if screen_pos.y <= _card().get_viewport_rect().size.y / 2.0:
			return cell
		cell.y -= 1
		game.grid.set_cell(cell, GRASS_SOURCE, GRASS_ATLAS)
		attempts += 1
		assert_int(attempts).override_failure_message(
				"fixture: no cell in the top half of the viewport").is_less(50)
	return cell


func _card_top() -> float:
	return _card()._tile_panel.get_global_rect().position.y


func _half() -> float:
	return _card().get_viewport_rect().size.y / 2.0


func _talk() -> void:
	var timeline := DialogicTimeline.new()
	timeline.from_text("torv: A line about the tile you just clicked.")
	assert_bool(game.scenario_director.preview(timeline)).override_failure_message(
			"fixture: the dialogue did not start").is_true()


# The card was up first, then the line began (the Prolog's UNIT_SELECTED shape): it moves up, and
# comes back down once the dialogue is over.
func test_a_card_already_up_moves_to_the_top_while_a_line_plays() -> void:
	game.show_tile_card(_top_half_cell())
	await _frames(4)
	assert_bool(_card_top() > _half()).override_failure_message(
			"fixture: the card did not park at the bottom, so nothing here tests leaving it").is_true()

	_talk()
	await _frames(4)
	assert_bool(game.scenario_director.is_talking()).is_true()
	assert_float(_card_top()).override_failure_message(
			"the card stayed in the bottom strip while the dialogue held it").is_less(_half())

	await DialogFixtures.end_all_dialog(self)
	await _frames(2)
	assert_bool(_card_top() > _half()).override_failure_message(
			"the card never went back down once the dialogue ended").is_true()


# A card opened while a line is already playing parks at the top straight away.
func test_a_card_opened_during_a_line_parks_at_the_top() -> void:
	var cell := _top_half_cell()
	_talk()
	await _frames(2)
	game.show_tile_card(cell)
	await _frames(4)
	assert_float(_card_top()).override_failure_message(
			"a card opened during a dialogue parked in the strip the dialogue holds").is_less(_half())
