# BoardMirror (#215): the Kind->item table's completeness (law-style: every Kind
# except the declared NONE skip), the board wire against the REAL Prolog mission
# loaded through the real funnel inside the Battle3D fixture, fire markers derived
# from the game's own terrain-state dict (never a pinned count), and clear-board
# emptiness. The fixture disables auto_play so no AI churns during asserts.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"

var _scene: Node3D
var _game: Node2D


func before_test() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_game = _scene.game


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


func test_every_kind_is_mapped_or_declared_skip() -> void:
	for kind: Terrain.Kind in Terrain.Kind.values():
		if kind == Terrain.Kind.NONE:
			assert_bool(BoardMirror.KIND_TO_ITEM.has(kind)).is_false()  # the declared skip
		else:
			assert_bool(BoardMirror.KIND_TO_ITEM.has(kind)).is_true()


func test_prolog_mirrors_cell_for_cell() -> void:
	_scene.load_mission(PROLOG)
	await await_idle_frame()
	var board := _scene.get_node("Board") as GridMap
	var grid_cells: Array[Vector2i] = _game.grid.get_used_cells()
	assert_int(board.get_used_cells().size()).is_equal(grid_cells.size())
	assert_bool(grid_cells.size() > 100).is_true()  # Prolog is a real board, not a stub
	# Spot-check: every mirrored item matches the 2D cell's kind through the table.
	for i in 25:
		var cell := grid_cells[i * maxi(1, grid_cells.size() / 25)]
		var kind := GridUtils.get_terrain_kind_at_cell(_game.grid, cell)
		var expected: int = BoardMirror.KIND_TO_ITEM.get(kind, BoardMirror.FALLBACK_ITEM)
		assert_int(board.get_cell_item(Vector3i(cell.x, 0, cell.y))).is_equal(expected)


func _expected_fires(states: Dictionary) -> int:
	var expected := 0
	for cell: Vector2i in states.keys():
		var cell_states: Array = states[cell]
		for state in cell_states:
			if (state as Terrain.TileState) in Terrain.FIRE_STATES:
				expected += 1
				break
	return expected


func test_fire_markers_match_the_games_own_state_dict() -> void:
	_scene.load_mission(PROLOG)
	await await_idle_frame()
	var expected := _expected_fires(_game.terrain_states.to_state_dict())
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	assert_int(mirror.fire_marker_count()).is_equal(expected)
	assert_bool(expected > 0).is_true()  # Prolog authors BLAZE content; a zero here means the load broke


func test_rebuild_tracks_the_authority_after_clear_board() -> void:
	_scene.load_mission(PROLOG)
	await await_idle_frame()
	_game.scenario_manager.clear_board()
	# clear_board detaches units then queue_frees them ("same-frame respawns don't
	# see dying units") — flush the deferred deletions or they read as orphans.
	await await_idle_frame()
	_scene.rebuild()
	var board := _scene.get_node("Board") as GridMap
	# clear_board deliberately leaves TERRAIN painted (the pieces clear, the map
	# stays — sandbox behavior). The mirror's contract is parity with the
	# authority, whatever the authority does — never an assumption of emptiness.
	assert_int(board.get_used_cells().size()).is_equal(_game.grid.get_used_cells().size())
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	assert_int(mirror.fire_marker_count()).is_equal(_expected_fires(_game.terrain_states.to_state_dict()))
