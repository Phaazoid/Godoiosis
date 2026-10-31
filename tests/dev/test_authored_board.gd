# An authored save writes the board AS AUTHORED (#1507). Turns passed in dev mode spread and burn out
# fires and move gas, and an Update used to write that played board into the mission as if it had been
# painted. The undo history now keeps the board as authored beside each live step, moved only by what an
# authoring edit itself changed (BoardSnapshot.edited), and the dev header hands it to the save.
#
# Strokes go through DevController.handle_tile_brush and the panel's own doors, never _paint_state,
# because the stroke bracket is the whole mechanism: a write outside one never reaches the authored
# board. A round is game._on_round_completed, the handler TurnManager.round_completed fires. Where a
# case needs play to REMOVE something, it lands an effect through the stores' apply, which is what
# ResolvedPlan.play_landing calls for a pass. Cells are injected through DevController.cell_source, the
# test_board_undo harness.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const FIRE := Vector2i(3, 1)

var _main: Node
var game: Node2D
var _brush: TileBrushTool
var _dc: DevController
var _cursor: Array[Vector2i] = [Vector2i.ZERO]


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.grid.reset()
	# A grass field, so a painted fire has fuel to spread into and burn out on.
	for x in range(8):
		for y in range(3):
			game.grid.paint(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	game.game_state = game.GameState.DEV_MODE
	_brush = game.dev_overlay.tile_brush
	_dc = game.dev_controller
	game.dev_overlay.show_leaf(_brush)
	_brush.brush_active = true
	_cursor = [Vector2i.ZERO]
	var cursor := _cursor
	_dc.cell_source = func() -> Vector2i: return cursor[0]
	# What a load does to the history: this field is the board as the file holds it.
	game.scenario_manager.board_loaded.emit()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


# ---- helpers ----

func _press(button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func _stroke(button: MouseButton, cells: Array[Vector2i]) -> void:
	_cursor[0] = cells[0]
	_dc.handle_tile_brush(_press(button, true))
	for i in range(1, cells.size()):
		_cursor[0] = cells[i]
		_dc.handle_tile_brush(InputEventMouseMotion.new())
	_dc.handle_tile_brush(_press(button, false))


func _paint(state: Terrain.TileState, cell: Vector2i) -> void:
	_brush._set_paint_mode(TileBrushTool.PaintMode.STATE)
	_brush._tile_state = state
	_stroke(MOUSE_BUTTON_LEFT, [cell] as Array[Vector2i])


func _paint_gas(kind: Gas.Kind, level: Gas.Level, cell: Vector2i) -> void:
	_brush._set_paint_mode(TileBrushTool.PaintMode.GAS)
	_brush._gas_kind = kind
	_brush._gas_level = level
	_stroke(MOUSE_BUTTON_LEFT, [cell] as Array[Vector2i])


func _round() -> void:
	game._on_round_completed()


# Grass's authored burn clock, read off its reaction: content, never a literal.
func _burn_ticks() -> int:
	var fuel: TerrainReaction = TerrainReactionCatalog.fuel_for_kind(
			Terrain.Kind.GRASS, TerrainReactionCatalog.get_all())
	assert_object(fuel).override_failure_message(
			"precondition: grass authors no ignition reaction, so nothing below proves anything").is_not_null()
	var turns: int = fuel.add_state_turns[Terrain.TileState.BURNING]
	return turns


# Play taking a state off a cell, the way a pass's douse lands (ResolvedPlan.play_landing).
func _play_removes(cell: Vector2i, state: Terrain.TileState) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_removed.assign([state] as Array[Terrain.TileState])
	game.terrain_states.apply(effect)


# What the dev header's Update writes, without the disk: its board, through the save's own capture.
func _saved() -> ScenarioData:
	var header: ScenarioHeader = game.dev_overlay.scenario_header
	var scenario: ScenarioData = game.scenario_manager.capture_scenario("authored-board", true,
			header.authored_board())
	return scenario


func _authored() -> BoardSnapshot:
	return _dc.history.authored()


func _live() -> BoardSnapshot:
	var live: BoardSnapshot = game.scenario_manager.capture_board()   # typed: game is untyped
	return live


# ---- play never reaches the save ----

func test_a_fire_that_spread_and_burnt_out_saves_as_painted() -> void:
	_paint(Terrain.TileState.BURNING, FIRE)
	for i in range(_burn_ticks()):
		_round()
	assert_bool(game.terrain_states.has_state(FIRE, Terrain.TileState.SCORCHED)).override_failure_message(
			"precondition: the painted fire never burnt out, so nothing below proves anything").is_true()
	assert_int(game.terrain_states.burning_cells().size()).override_failure_message(
			"precondition: the fire never spread, so nothing below proves anything").is_greater(0)

	var saved := _saved()

	assert_array(saved.terrain_states.keys()).override_failure_message(
			"the save wrote cells play lit or scorched: %s" % [saved.terrain_states]).contains_exactly([FIRE])
	assert_array(saved.terrain_states[FIRE]).override_failure_message(
			"the painted fire saved as play left it").contains_exactly([Terrain.TileState.BURNING])
	assert_dict(saved.gas).override_failure_message("the save wrote gas play gave off").is_empty()
	assert_dict(saved.terrain_state_turns).override_failure_message(
			"an authored save wrote a countdown (#1483)").is_empty()


func test_an_authored_start_survives_the_fire_play_burnt_out() -> void:
	_brush._start_spin.value = 1   # through the row's own wire, so the fire is out after one round
	_paint(Terrain.TileState.BURNING, FIRE)
	_round()
	assert_int(game.terrain_states.start_turns(FIRE, Terrain.TileState.BURNING)).override_failure_message(
			"precondition: the start outlived its burnt-out fire on the live board").is_equal(-1)

	var saved := _saved()

	assert_int(saved.terrain_state_starts.get(FIRE, {}).get(Terrain.TileState.BURNING, -1)) \
		.override_failure_message("the save lost the start because play burnt its fire out").is_equal(1)


func test_gas_that_drifted_saves_as_painted() -> void:
	_paint_gas(Gas.Kind.STEAM, Gas.Level.THICK, FIRE)
	var painted := _live().gas
	_round()
	assert_bool(game.gas_field.to_dict() == painted).override_failure_message(
			"precondition: a round moved no gas, so nothing below proves anything").is_false()

	assert_bool(_saved().gas == painted).override_failure_message(
			"the save wrote the gas as play left it").is_true()


func test_step_gas_is_an_authoring_act_and_saves_what_it_did() -> void:
	_paint_gas(Gas.Kind.STEAM, Gas.Level.THICK, FIRE)
	var painted := _live().gas

	_dc.step_gas()

	var stepped := game.gas_field.to_dict() as Dictionary
	assert_bool(stepped == painted).override_failure_message(
			"precondition: Step Gas moved nothing").is_false()
	assert_bool(_saved().gas == stepped).override_failure_message(
			"Step Gas is pressed on purpose, yet the save left its step out").is_true()


func test_painting_a_played_cell_saves_the_paint_and_not_the_play() -> void:
	_paint(Terrain.TileState.BURNING, FIRE)
	_round()
	var spread := FIRE + Vector2i.LEFT
	assert_bool(game.terrain_states.has_state(spread, Terrain.TileState.BURNING)).override_failure_message(
			"precondition: the fire never spread west").is_true()

	_paint(Terrain.TileState.COVER, spread)

	var saved := _saved()
	assert_array(saved.terrain_states.get(spread, [])).override_failure_message(
			"the cell saved the fire play spread onto it with the paint").contains_exactly(
			[Terrain.TileState.COVER])


# ---- the authored board follows the history ----

func test_undo_after_play_puts_the_authored_board_back_too() -> void:
	_paint(Terrain.TileState.BURNING, FIRE)
	_round()
	var cover := Vector2i(6, 0)
	_paint(Terrain.TileState.COVER, cover)
	assert_bool(_authored().terrain_states.has(cover)).is_true()

	_dc.undo_board()

	assert_array(_authored().terrain_states.keys()).override_failure_message(
			"undo moved the live board and left the authored one where it was").contains_exactly([FIRE])

	_dc.redo_board()

	assert_bool(_authored().terrain_states.has(cover)).override_failure_message(
			"redo did not bring the authored paint back").is_true()


func test_clear_tile_states_empties_the_authored_states_play_had_already_taken() -> void:
	_paint(Terrain.TileState.BURNING, FIRE)
	_play_removes(FIRE, Terrain.TileState.BURNING)
	assert_bool(_authored().terrain_states.has(FIRE)).override_failure_message(
			"precondition: the douse reached the authored board").is_true()

	_dc.clear_tile_states()

	assert_dict(_saved().terrain_states).override_failure_message(
			"Clear Tile States left a fire the save still writes, on a cell play had emptied").is_empty()


func test_clear_all_gas_empties_the_authored_gas_play_had_already_taken() -> void:
	_paint_gas(Gas.Kind.SMOKE, Gas.Level.MEDIUM, FIRE)
	var effect := ResolvedCellEffect.new()
	effect.cell = FIRE
	effect.gas_cleared = true
	game.gas_field.apply(effect)
	assert_bool(_authored().gas.has(FIRE)).override_failure_message(
			"precondition: the clear reached the authored board").is_true()

	_dc.clear_gas()

	assert_dict(_saved().gas).override_failure_message(
			"Clear All Gas left gas the save still writes, on a cell play had cleared").is_empty()


func test_erasing_the_ground_under_a_fire_play_put_out_drops_it() -> void:
	_paint(Terrain.TileState.BURNING, FIRE)
	_play_removes(FIRE, Terrain.TileState.BURNING)
	_brush._set_paint_mode(TileBrushTool.PaintMode.TERRAIN)

	_stroke(MOUSE_BUTTON_RIGHT, [FIRE] as Array[Vector2i])

	assert_bool(GridUtils.has_ground(game.grid, FIRE)).override_failure_message(
			"precondition: the erase left the ground").is_false()
	assert_dict(_saved().terrain_states).override_failure_message(
			"the save wrote a fire onto a cell with no ground").is_empty()


func test_a_load_makes_the_loaded_board_the_authored_one() -> void:
	_paint(Terrain.TileState.BURNING, FIRE)
	_round()
	var scenario: ScenarioData = game.scenario_manager.capture_scenario("played", false)

	game.scenario_manager.apply_scenario(scenario)

	assert_bool(_authored().equals(_live())).override_failure_message(
			"a load left the previous board's authored copy in the history").is_true()
	assert_int(_authored().cells_moved_from(_live())).is_equal(0)


func test_the_header_writes_the_live_board_with_authored_unticked() -> void:
	var header: ScenarioHeader = game.dev_overlay.scenario_header
	assert_object(header.authored_board()).is_same(_authored())

	header.authored_save = false

	assert_object(header.authored_board()).override_failure_message(
			"a snapshot save took the authored board; it must write the battle as it stands").is_null()


func test_the_moved_cell_count_sees_play_and_nothing_else() -> void:
	_paint(Terrain.TileState.BURNING, FIRE)
	assert_int(_authored().cells_moved_from(_live())).override_failure_message(
			"a painted board with no play reads as moved").is_equal(0)

	_round()

	assert_int(_authored().cells_moved_from(_live())).override_failure_message(
			"a round that spread the fire reads as nothing moved").is_greater(0)


# The live store keeps a cell's states in arrival order, so one that play took and gave back sits
# elsewhere in the list: the same states, nothing moved.
func test_the_moved_cell_count_reads_a_cells_states_as_a_set() -> void:
	var authored := BoardSnapshot.new()
	var live := BoardSnapshot.new()
	var cover_then_frozen: Array[Terrain.TileState] = [Terrain.TileState.COVER, Terrain.TileState.FROZEN]
	var frozen_then_cover: Array[Terrain.TileState] = [Terrain.TileState.FROZEN, Terrain.TileState.COVER]
	authored.terrain_states = {FIRE: cover_then_frozen}
	live.terrain_states = {FIRE: frozen_then_cover}
	assert_int(authored.cells_moved_from(live)).override_failure_message(
			"the same states in another order read as a moved cell").is_equal(0)

	var frozen_only: Array[Terrain.TileState] = [Terrain.TileState.FROZEN]
	live.terrain_states = {FIRE: frozen_only}
	assert_int(authored.cells_moved_from(live)).override_failure_message(
			"a state play took reads as nothing moved").is_equal(1)


# ---- the law the merge leans on ----

# BoardSnapshot.PLAY_WRITTEN is a claim about play: a field outside it is taken whole from each edit,
# so a round that changed one would bake play into the authored board on the next stroke.
func test_a_round_writes_only_the_fields_play_is_declared_to_write() -> void:
	_paint(Terrain.TileState.BURNING, FIRE)
	_paint_gas(Gas.Kind.STEAM, Gas.Level.THICK, Vector2i(6, 1))
	var before := _live()

	_round()

	var after := _live()
	var changed: Array[StringName] = []
	for property: Dictionary in before.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and before.get(property.name) != after.get(property.name):
			changed.append(StringName(property.name))
	assert_array(changed).override_failure_message(
			"precondition: the round moved neither the fire nor the gas").contains([&"terrain_states", &"gas"])
	for field in changed:
		assert_bool(BoardSnapshot.PLAY_WRITTEN.has(field)).override_failure_message(
				"a round wrote '%s', which BoardSnapshot.PLAY_WRITTEN does not declare" % field).is_true()
