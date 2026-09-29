# The flat camera's pan wall follows the board it frames (#974): every board load refreshes the
# bounds at the board's own pitch, so a wall left by an earlier board or dev edit cannot stand.
# Main.tscn has no 3D host, so this camera IS the view and its clamp is live.
#
# The expectation is asked of the GRID (its tile size and map_to_local), never of the constant the
# code under test multiplies by, so a wall built at the wrong pitch cannot agree with it.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const PROLOG_PATH := "res://Scenarios/missions/Prolog.tres"

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# Both doors a board arrives by: the apply_scenario funnel and the sandbox, which emits
# board_loaded itself. No dev edit runs between the stale wall and the check.
func test_every_board_load_rebuilds_the_pan_wall_around_that_board() -> void:
	assert_bool(game.board_input_delegated).override_failure_message(
			"precondition: a bare Main.tscn launch should own its own board input").is_false()
	var cam: CameraController = game.camera_controller
	var doors: Dictionary[String, Callable] = {
		"load_scenario": func() -> void: game.scenario_manager.load_scenario(PROLOG_PATH),
		"spawn_sandbox": func() -> void: game.spawn_sandbox(),
	}
	for door: String in doors:
		cam.min_world = Vector2(100000.0, 100000.0)
		cam.max_world = Vector2(104000.0, 104000.0)
		doors[door].call()
		var expected := _board_rect_plus_margin()
		assert_vector(cam.min_world).override_failure_message(
				"after %s the pan wall is not this board's extent plus its margin" % [door]).is_equal(expected.position)
		assert_vector(cam.max_world).override_failure_message(
				"after %s the pan wall is not this board's extent plus its margin" % [door]).is_equal(expected.end)


# The board's pixel extent off the grid itself, plus the flat view's margin in the grid's own cells.
func _board_rect_plus_margin() -> Rect2:
	var grid: TileMapLayer = game.grid
	var used := grid.get_used_rect()
	assert_bool(used.has_area()).override_failure_message(
			"the loaded board has no tiles, so its bounds prove nothing").is_true()
	var pitch := Vector2(grid.tile_set.tile_size)
	var first := grid.map_to_local(used.position) - pitch / 2.0
	var last := grid.map_to_local(used.end - Vector2i.ONE) + pitch / 2.0
	var margin := pitch * CameraController.EDIT_MARGIN_CELLS
	return Rect2(first - margin, last - first + margin * 2.0)
