# Dev placement mid-plan (#1432): the dev-mode cursor and every dev placement ask ONE rule,
# RulesService.can_place_at -- spawn's, plus the cells a queued plan ends a unit on. The cursor used
# to read projected occupancy and the click live occupancy, so with a move A -> Q queued the cursor
# promised A's old cell the click refused, and refused Q while the click dropped a unit onto it.
#
# Every case drives the real doors: game._on_left_click (which repaints the cursor for the clicked
# cell, then dispatches the armed Move or Duplicate) and SpawnTool.try_spawn_at, the SPACE door.
# The cursor is read off CursorController.state, the stored answer the 3D bracket mirrors.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const LEAVES := Vector2i(0, 0)    # where A stands, and plans to leave
const ARRIVES := Vector2i(2, 0)   # where A's queued move ends
const HOME := Vector2i(5, 0)      # where B stands
const FREE := Vector2i(7, 0)      # nobody stands or arrives here

var _main: Node
var game: Node2D
var _mover: Unit
var _placed: Unit


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	for x in range(8):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()
	game.game_state = game.GameState.DEV_MODE
	_mover = _spawn(LEAVES)
	_placed = _spawn(HOME)
	_queue_move(_mover, ARRIVES)


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


# ---- helpers ----

func _spawn(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).override_failure_message("fixture: spawn refused %s" % cell).is_not_null()
	return unit


func _queue_move(unit: Unit, destination: Vector2i) -> void:
	var reach := RulesService.compute_move_range(unit, game._board())
	var move := MoveAction.new()
	move.init(unit, game.route_to(unit, reach, destination),
		GridUtils.get_terrain_icon_at_cell(game.grid, destination))
	assert_bool(game.squad_manager.queue_action(unit.squad, move)) \
		.override_failure_message("fixture: the move to %s was refused" % destination).is_true()
	assert_object(unit.get_projected_destination()).override_failure_message(
		"fixture: the queued move does not project %s onto %s" % [unit.get_unit_name(), destination]) \
		.is_equal(destination)


func _cursor_invalid() -> bool:
	var cursor: CursorController = game.cursor_controller
	return cursor.state == CursorController.CursorState.INVALID


func _unit_count() -> int:
	return game._all_units().size()


# Arm B's Move and click the cell, through the real dispatch.
func _move_placed_to(cell: Vector2i) -> void:
	game.dev_controller.arm_move(_placed)
	game._on_left_click(cell)


func _assert_both_refuse(cell: Vector2i, what: String) -> void:
	assert_bool(_cursor_invalid()).override_failure_message(
		"the cursor offered %s (%s), which the click refuses" % [cell, what]).is_true()
	assert_object(_placed.movement.cell).override_failure_message(
		"the click dropped %s onto %s (%s)" % [_placed.get_unit_name(), cell, what]).is_equal(HOME)


# ---- the cursor and the click agree ----

func test_both_refuse_the_cell_a_queued_move_ends_on() -> void:
	_move_placed_to(ARRIVES)

	_assert_both_refuse(ARRIVES, "A's queued destination")
	assert_object(_mover.get_projected_destination()).override_failure_message(
		"A's queued move no longer ends where it was planned").is_equal(ARRIVES)


func test_both_refuse_the_cell_a_unit_plans_to_leave() -> void:
	# A only leaves if the plan runs; until then it is standing there.
	_move_placed_to(LEAVES)

	_assert_both_refuse(LEAVES, "the cell A stands on and plans to leave")


func test_both_accept_a_cell_nobody_stands_on_or_arrives_at() -> void:
	# The twin that keeps the two refusals above from passing on a cursor stuck at INVALID.
	_move_placed_to(FREE)

	assert_bool(_cursor_invalid()).override_failure_message(
		"the cursor refused a free cell").is_false()
	assert_object(_placed.movement.cell).override_failure_message(
		"the click refused a free cell").is_equal(FREE)


# ---- the other two placement doors ----

func test_duplicate_refuses_a_queued_destination() -> void:
	var before := _unit_count()
	game.dev_controller.arm_duplicate(_placed)
	game._on_left_click(ARRIVES)

	assert_bool(_cursor_invalid()).is_true()
	assert_int(_unit_count()).override_failure_message(
		"Duplicate dropped a copy onto A's queued destination").is_equal(before)


func test_space_spawn_refuses_a_queued_destination_and_takes_a_free_cell() -> void:
	var spawn: SpawnTool = game.dev_overlay.spawn
	spawn.selected_character = H.make_unit_data({}, Team.Faction.PLAYER)
	var before := _unit_count()

	spawn.try_spawn_at(ARRIVES)
	assert_int(_unit_count()).override_failure_message(
		"SPACE spawned onto A's queued destination").is_equal(before)

	spawn.try_spawn_at(FREE)
	assert_int(_unit_count()).override_failure_message(
		"fixture: SPACE spawned nothing on a free cell, so the refusal above proves nothing") \
		.is_equal(before + 1)
