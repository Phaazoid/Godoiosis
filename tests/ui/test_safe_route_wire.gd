# The arrow and the click walk the same safe route (#920). Both ask game.route_to, so they cannot
# differ by construction; this drives the real hover and the real click to keep it that way, since a
# preview arrow that detours while the queued walk does not is a plan that lies (Law #2).
# Fixture is tests/ai/test_ai_turn_terminates.gd's game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true, move_cost=1 in TestTiles.tres

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
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.DEX: 30, Stats.Stat.MHP: 40}, faction), cell)
	assert_object(unit).is_not_null()
	unit.equipped_weapon = H.make_weapon()
	return unit


func _crosses(path: Array[Vector2i], cells: Array[Vector2i]) -> bool:
	for i in range(1, path.size()):
		if cells.has(path[i]):
			return true
	return false


func test_the_arrow_and_the_click_take_the_same_detour() -> void:
	for x in range(7):
		for y in range(5):
			game.grid.paint(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	var mover := _spawn(Team.Faction.PLAYER, Vector2i(0, 1))
	var watcher := _spawn(Team.Faction.ENEMY, Vector2i(6, 4))
	var lane: Array[Vector2i] = [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)]
	var attack: AttackData = (watcher.get_equipped_weapon() as WeaponInstance).template.main_attack
	watcher.watch = Watch.arm(watcher, watcher.movement.cell, lane[0], lane, attack)
	await await_idle_frame()
	var goal := Vector2i(4, 1)

	game.select_unit(mover, mover.movement.cell)
	game.enter_move_mode(mover)
	game.hover_presenter._hover_choosing_move(goal)
	var preview: MoveAction = game.overlay_manager.hover_move_preview
	assert_object(preview).override_failure_message("the hover drew no arrow").is_not_null()
	var arrow: Array[Vector2i] = preview.path.duplicate()

	game._click_choosing_move(goal)
	var walk: MoveAction = mover.get_move_action()
	assert_object(walk).override_failure_message("the click queued no move").is_not_null()

	assert_bool(_crosses(arrow, lane)).override_failure_message(
			"the arrow walked through the watch: %s" % [arrow]).is_false()
	assert_array(walk.path).override_failure_message(
			"the queued walk %s is not the arrow %s" % [walk.path, arrow]).is_equal(arrow)
