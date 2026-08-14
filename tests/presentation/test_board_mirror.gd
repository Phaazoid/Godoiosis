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


func test_a_unit_going_down_on_fire_does_not_take_the_flame_with_it() -> void:
	# Reported in play: a unit downed while standing in fire makes that fire vanish for the
	# rest of the turn, returning at the next turn boundary. This isolates WHICH half is
	# wrong — the marker being freed, or the marker still existing and being drawn under the
	# downed sprite (both flame and unit are transparent quads at the same standing point).
	# A held count means the node is alive and it is a render-order question, not a logic one.
	_scene.load_mission(PROLOG)
	await await_idle_frame()
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	var states: Dictionary = _game.terrain_states.to_state_dict()
	var fire_cell := Vector2i(-9999, -9999)
	for cell: Vector2i in states.keys():
		for state in states[cell]:
			if (state as Terrain.TileState) in Terrain.FIRE_STATES:
				fire_cell = cell
				break
		if fire_cell.x != -9999:
			break
	assert_bool(fire_cell.x != -9999).override_failure_message(
			"Prolog authored no fire; the case is vacuous").is_true()

	var unit: Unit = null
	for child in _game.units_root.get_children():
		var candidate := child as Unit
		if candidate != null:
			unit = candidate
			break
	assert_object(unit).is_not_null()
	unit.movement.set_cell(fire_cell)   # teleport onto the burning tile
	await await_idle_frame()
	var before := mirror.fire_marker_count()
	assert_int(before).override_failure_message("no flame to lose; the case is vacuous").is_greater(0)

	unit._go_downed(false)
	await await_idle_frame()
	await await_idle_frame()
	assert_int(mirror.fire_marker_count()).override_failure_message(
			"the flame marker was FREED when the unit went down").is_equal(before)


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


func test_the_flame_never_sits_in_the_ground_plane() -> void:
	# A QuadMesh is centred on its origin, so a 0.7-tall flame lifted 0.35 has its BOTTOM EDGE
	# at exactly y = 0 — coplanar with the tile top face it stands on. Harmless while the
	# flame did not write depth; the worst z-fighting on the board once it did. Clamped in
	# flame_base_lift, so this holds for any authored knob value, including a hostile one.
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	mirror.flame_writes_depth = true
	for lift in [0.0, 0.1, 0.35, 0.4, 2.0]:
		mirror.flame_lift = lift
		var bottom: float = mirror.flame_base_lift() - mirror.flame_size.y * 0.5
		assert_float(bottom).override_failure_message(
				"flame_lift %s puts the flame's bottom edge at %s — in/through the ground plane" \
				% [lift, bottom]).is_greater_equal(mirror.flame_ground_gap)
	# Non-vacuous: the clamp is doing work at the authored default, not just at absurd values.
	mirror.flame_lift = 0.35
	assert_float(mirror.flame_base_lift()).override_failure_message(
			"the clamp is inert at the value that caused the bug").is_greater(0.35)

	# ...and with depth off — the shipped default — the authored lift stands untouched, so
	# the flame renders exactly as it did before #236 rather than approximately.
	mirror.flame_writes_depth = false
	assert_float(mirror.flame_base_lift()).override_failure_message(
			"the clamp moved the flame even with depth-write off, so the revert is not exact" \
			).is_equal_approx(0.35, 0.0001)
