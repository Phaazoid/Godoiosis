# A BOARD SWAPPED OUT FROM UNDER A PASS (#661), on a real Main.tscn board through the real executor.
#
# F2 (or any load) during a walk frees the walker, so the pass suspended on its walk never resumes and
# never reaches the line that clears executing_plan -- which then stays set for good, and
# refresh_action_queue refuses every board after it. clear_board releases it now (abandon_pass), and
# every coroutine that awaits across a pass or a turn stops if the board it started on is gone.
#
# A walk is the ONE suspension a headless run keeps (its tween is real; every beat and pan collapses),
# so it is what each case interrupts. Cases 2 and 3 move the board generation by hand rather than
# swapping the board: a real swap frees the walker, and a pass suspended on a freed unit never resumes,
# so the RESUME path the guards exist for cannot be reached headlessly any other way. What they cannot
# see is a pass resuming off a timer or a pan after a real swap; that is the play-check.
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
	for x in range(12):
		for y in range(3):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10, Stats.Stat.MHP: 40}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


# A straight walk east along the unit's own row, ending at x = `to_x`.
func _queue_walk(unit: Unit, to_x: int) -> MoveAction:
	var path: Array[Vector2i] = []
	for x in range(unit.movement.cell.x, to_x + 1):
		path.append(Vector2i(x, unit.movement.cell.y))
	var move := MoveAction.new()
	move.init(unit, path, null)
	assert_bool(game.squad_manager.queue_action(unit.squad, move)) \
		.override_failure_message("fixture failed to queue the walk").is_true()
	return move


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# Spin until `unit` is mid-walk; a fixture that never gets there is not testing the interruption.
func _until_walking(unit: Unit) -> void:
	var frames := 0
	while not unit.movement.moving and frames < 120:
		await get_tree().process_frame
		frames += 1
	assert_bool(unit.movement.moving).override_failure_message(
			"fixture: the walk never started, so nothing was interrupted").is_true()


# The queue panel's rows for `action`, read off what the panel was last handed -- the visible fact.
func _panel_shows(action: BaseAction) -> bool:
	for entry: ActionQueueDisplayEntry in game.squad_action_queue_control._last_entries:
		if entry != null and entry.action == action:
			return true
	return false


# THE CASE. F2 mid-walk, then an ordinary order on the reloaded board shows in the queue.
func test_a_board_reloaded_mid_walk_still_shows_the_next_plan() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 1))
	_spawn(Team.Faction.ENEMY, Vector2i(11, 2))
	await await_idle_frame()
	var snapshot: ScenarioData = game.scenario_manager.capture_scenario("swap")
	_queue_walk(hero, 5)

	game.order_executor.execute_orders(hero.squad.get_leader())   # not awaited: it is interrupted
	await _until_walking(hero)
	game.scenario_manager.apply_scenario(snapshot)
	await _frames(10)

	assert_object(game.order_executor.executing_plan).override_failure_message(
			"the interrupted pass still reads as running on the board that replaced it").is_null()
	var fresh: Unit = null
	for child in game.units_root.get_children():
		var unit := child as Unit
		if unit != null and unit.get_faction() == Team.Faction.PLAYER:
			fresh = unit
	assert_object(fresh).override_failure_message("fixture: the reload brought no player unit back").is_not_null()
	var next := _queue_walk(fresh, fresh.movement.cell.x + 2)
	game.refresh_action_queue(fresh.squad)
	assert_bool(_panel_shows(next)).override_failure_message(
			"the queue panel never showed the reloaded board's move -- it still refuses to re-derive").is_true()


# A pass that RESUMES after its board is gone stops there: it does not finish the squad's turn.
func test_a_pass_whose_board_changes_under_it_stops_at_its_next_await() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 1))
	_spawn(Team.Faction.ENEMY, Vector2i(11, 2))
	await await_idle_frame()
	_queue_walk(hero, 3)
	var squad: Squad = hero.squad

	game.order_executor.execute_orders(hero.squad.get_leader())
	await _until_walking(hero)
	game.scenario_manager.board_generation += 1
	var frames := 0
	while hero.movement.moving and frames < 600:
		await get_tree().process_frame
		frames += 1
	await _frames(10)

	assert_bool(hero.movement.moving).override_failure_message("fixture: the walk never finished").is_false()
	assert_bool(squad.has_acted).override_failure_message(
			"the pass played on and ended its squad's turn after its board was gone").is_false()


# ...and an AI turn stops with it, rather than ending the turn of the board that replaced it.
func test_an_ai_turn_whose_board_changes_under_it_ends_nothing() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(11, 1))
	var enemy := _spawn(Team.Faction.ENEMY, Vector2i(0, 1))
	enemy.equipped_weapon = H.make_weapon()
	game.ai_controller.set_ai_factions([Team.Faction.ENEMY] as Array[Team.Faction])
	game.turn_manager.set_active_faction(Team.Faction.ENEMY)
	await await_idle_frame()

	game.ai_controller.take_faction_turn(Team.Faction.ENEMY)
	await _until_walking(enemy)
	game.scenario_manager.board_generation += 1
	var frames := 0
	while enemy.movement.moving and frames < 600:
		await get_tree().process_frame
		frames += 1
	await _frames(10)

	assert_int(game.turn_manager.active_faction()).override_failure_message(
			"the interrupted AI turn went on to end the turn").is_equal(Team.Faction.ENEMY)
