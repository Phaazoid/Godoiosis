# AI downed deprioritization (#57, fork 3): a downed unit is a LEGAL target (any hit on it
# kills), just not a PREFERRED one. Both selectors -- raw-distance nearest_enemy and the
# chooser's two-pass attack scoring (#78: downed units neither aim nor score until nothing
# active produced a candidate) -- must prefer an active enemy over a closer downed one, and
# fall through to downed only when nothing active qualifies.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const ATTACK_ONLY: Array = [BaseAction.ActionType.ATTACK]


func _build_board(size := Rect2i(0, 0, 8, 3)) -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, size)
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data({}, faction), cell)
	unit.equipped_weapon = H.make_weapon()
	return unit


func _context(board: Dictionary) -> BoardContext:
	var units: Array[Unit] = []
	for child in board.units_root.get_children():
		units.append(child as Unit)
	return BoardContext.new(board.grid, units, board.squad_manager)


# --- nearest_enemy: raw-distance selection ---

func test_nearest_enemy_prefers_active_over_closer_downed() -> void:
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var downed_close: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 0))
	downed_close.lifecycle_state = Unit.LifecycleState.DOWNED
	var active_far: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(5, 0))

	assert_object(AITactics.nearest_enemy(player, _context(board))).is_same(active_far)

func test_nearest_enemy_falls_back_to_downed_when_nothing_active() -> void:
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var downed: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(2, 0))
	downed.lifecycle_state = Unit.LifecycleState.DOWNED

	assert_object(AITactics.nearest_enemy(player, _context(board))).is_same(downed)

func test_nearest_enemy_active_still_wins_within_a_zone_filter() -> void:
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var downed_close: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 0))
	downed_close.lifecycle_state = Unit.LifecycleState.DOWNED
	var active_far: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 0))

	var within := {}
	for x in range(0, 4):
		within[Vector2i(x, 0)] = true

	assert_object(AITactics.nearest_enemy(player, _context(board), within)).is_same(active_far)


# --- the chooser's two-pass attack scoring (#78; replaces attack_if_possible) ---

func test_attack_prefers_active_target_in_reach() -> void:
	# AI attacks aim at a CELL (target null; victims derive at resolve time, #15) -- assert on
	# target_cell. The downed unit sits closer in board order AND in distance; pass 1 must
	# still pick the active one.
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var downed_adjacent: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 0))
	downed_adjacent.lifecycle_state = Unit.LifecycleState.DOWNED
	var active_in_reach: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 1))   # pattern-less weapon: Manhattan 1

	assert_bool(AITactics.queue_main_action(player, _context(board), board.squad_manager, ATTACK_ONLY)).is_true()
	var queued: AttackAction = player.squad.action_queue[0]
	assert_that(queued.target_cell).is_equal(active_in_reach.movement.cell)

func test_attack_finishes_downed_when_nothing_active_in_reach() -> void:
	# Fork 3: a downed unit is a legal fallback target -- finishing it off is intended, just
	# only when no active enemy qualifies (the chooser's second pass).
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var downed_adjacent: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 0))
	downed_adjacent.lifecycle_state = Unit.LifecycleState.DOWNED

	assert_bool(AITactics.queue_main_action(player, _context(board), board.squad_manager, ATTACK_ONLY)).is_true()
	var queued: AttackAction = player.squad.action_queue[0]
	assert_that(queued.target_cell).is_equal(downed_adjacent.movement.cell)

func test_attack_declines_when_only_downed_out_of_reach() -> void:
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var downed_far: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(5, 0))
	downed_far.lifecycle_state = Unit.LifecycleState.DOWNED

	assert_bool(AITactics.queue_main_action(player, _context(board), board.squad_manager, ATTACK_ONLY)).is_false()
	assert_array(player.squad.action_queue).is_empty()
