# AI downed deprioritization (#57, fork 3): a downed unit is a LEGAL target (any hit on it
# kills), just not a PREFERRED one. Both AITactics selectors -- raw-distance nearest_enemy
# and reach-level target selection via attack_if_possible -- must prefer an active enemy
# over a closer downed one, and fall through to downed only when nothing active qualifies.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")


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


# --- attack_if_possible / reach-level selection ---

func test_attack_if_possible_prefers_active_target_in_reach() -> void:
	# attack_if_possible aims at a CELL (AttackAction.create(..., null, enemy_cell)) -- the
	# actual victim is resolved later via gather_attack_victims -- so assert on target_cell,
	# not target (which is always null for AI-queued attacks; predates #57).
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var downed_adjacent: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 0))
	downed_adjacent.lifecycle_state = Unit.LifecycleState.DOWNED
	var active_in_reach: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 1))   # pattern-less weapon: Manhattan 1

	assert_bool(AITactics.attack_if_possible(player, _context(board), board.squad_manager)).is_true()
	var queued: AttackAction = player.squad.action_queue[0]
	assert_that(queued.target_cell).is_equal(active_in_reach.movement.cell)

func test_attack_if_possible_finishes_downed_when_nothing_active_in_reach() -> void:
	# Fork 3: a downed unit is a legal fallback target -- finishing it off is intended, just
	# only when no active enemy qualifies.
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var downed_adjacent: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 0))
	downed_adjacent.lifecycle_state = Unit.LifecycleState.DOWNED

	assert_bool(AITactics.attack_if_possible(player, _context(board), board.squad_manager)).is_true()
	var queued: AttackAction = player.squad.action_queue[0]
	assert_that(queued.target_cell).is_equal(downed_adjacent.movement.cell)

func test_attack_if_possible_returns_false_when_only_downed_out_of_reach() -> void:
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var downed_far: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(5, 0))
	downed_far.lifecycle_state = Unit.LifecycleState.DOWNED

	assert_bool(AITactics.attack_if_possible(player, _context(board), board.squad_manager)).is_false()
