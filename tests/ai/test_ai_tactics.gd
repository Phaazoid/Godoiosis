# AITactics (#29, chooser rebuilt #78): the shared board queries the archetypes compose with,
# plus the ATTACK path of queue_main_action. Runs on the real managers + TestTiles terrain via
# the Play API's headless board_builder (proven pattern). Fixture weapons are pattern-less ->
# CombatComponent reach falls back to Manhattan range 1, so attack geometry is trivial:
# distance <= 1 can hit. Units default to MOV 4 (#56: MOV is now a derived readout —
# JOBLESS_MOV_BASE 4 + dex_mov_band(5)=0 for the default statline).
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


# --- nearest_enemy ---

func test_nearest_enemy_picks_closest_active() -> void:
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var near: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 0))
	var _far: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(4, 0))

	assert_object(AITactics.nearest_enemy(player, _context(board))).is_same(near)


func test_nearest_enemy_ignores_allies_and_downed() -> void:
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var _ally: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(1, 0))
	var downed: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(2, 0))
	var far_active: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(5, 0))

	downed.take_damage(12)   # fatal but sub-overkill (MHP 10, ceiling 10) -> DOWNED, not dead
	assert_bool(downed.is_downed()).is_true()

	assert_object(AITactics.nearest_enemy(player, _context(board))).is_same(far_active)


func test_nearest_enemy_within_filter() -> void:
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var _near: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 0))
	var far: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(5, 0))

	var within := { Vector2i(5, 0): true }
	assert_object(AITactics.nearest_enemy(player, _context(board), within)).is_same(far)


func test_nearest_enemy_none_returns_null() -> void:
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))

	assert_object(AITactics.nearest_enemy(player, _context(board))).is_null()


# --- queue_main_action: the ATTACK path (#78; replaces attack_if_possible) ---

func test_attack_in_reach_queues_one_stamped_aim() -> void:
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(2, 1))
	var enemy: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(2, 2))

	var queued: bool = AITactics.queue_main_action(player, _context(board), board.squad_manager, ATTACK_ONLY)

	assert_bool(queued).is_true()
	assert_int(player.squad.action_queue.size()).is_equal(1)
	var aim: AttackAction = player.squad.action_queue[0] as AttackAction
	assert_object(aim).is_not_null()
	assert_that(aim.target_cell).is_equal(enemy.movement.cell)
	# The declare stamp (#78's fists bug): an AI aim carries its chosen attack exactly like a
	# player aim -- here the fixture weapon's main.
	var weapon: WeaponInstance = player.get_equipped_weapon() as WeaponInstance
	assert_object(aim.fired_attack).is_same(weapon.template.main_attack)


func test_attack_out_of_reach_queues_nothing() -> void:
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(2, 1))
	var _enemy: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(5, 1))   # distance 3 > reach 1

	assert_bool(AITactics.queue_main_action(player, _context(board), board.squad_manager, ATTACK_ONLY)).is_false()
	assert_array(player.squad.action_queue).is_empty()


func test_attack_respects_existing_main_action() -> void:
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(2, 1))
	var _enemy: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(2, 2))

	assert_bool(AITactics.queue_main_action(player, _context(board), board.squad_manager, ATTACK_ONLY)).is_true()
	# One main action per unit per turn: a second pass may not queue a duplicate order.
	assert_bool(AITactics.queue_main_action(player, _context(board), board.squad_manager, ATTACK_ONLY)).is_false()
	assert_int(player.squad.action_queue.size()).is_equal(1)


# --- best_attack_destination ---

func test_best_attack_destination_moves_into_range() -> void:
	var board: Dictionary = _build_board(Rect2i(0, 0, 8, 1))   # 1-wide corridor
	var leader: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var enemy: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(5, 0))

	var dest: Vector2i = AITactics.best_attack_destination(leader, enemy, _context(board))

	# (4,0) is the only reachable cell in Manhattan-1 reach of (5,0): the enemy blocks the
	# corridor, so (6,0) is unreachable, and (5,0) itself is occupied.
	assert_that(dest).is_equal(Vector2i(4, 0))
	assert_bool(leader.combat.get_all_attack_cells_from(dest).has(enemy.movement.cell)).is_true()


func test_best_attack_destination_closes_distance_when_out_of_reach() -> void:
	var board: Dictionary = _build_board(Rect2i(0, 0, 12, 1))
	var leader: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var enemy: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(11, 0))

	# No reachable cell can hit (11,0) with MOV 4 -> rush the closest reachable cell.
	assert_that(AITactics.best_attack_destination(leader, enemy, _context(board))).is_equal(Vector2i(4, 0))


func test_best_attack_destination_respects_allowed() -> void:
	var board: Dictionary = _build_board(Rect2i(0, 0, 8, 1))
	var leader: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var enemy: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(5, 0))

	# The true best (4,0) is excluded: the clamp forces the nearest allowed cell instead.
	var allowed := { Vector2i(0, 0): true, Vector2i(2, 0): true }
	assert_that(AITactics.best_attack_destination(leader, enemy, _context(board), allowed)).is_equal(Vector2i(2, 0))


# --- closest_reachable_cell_to ---

func test_closest_reachable_cell_to_approaches_goal() -> void:
	var board: Dictionary = _build_board(Rect2i(0, 0, 12, 1))
	var unit: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))

	# MOV 4 (default DEX 5, #56) -> farthest reachable cell in a straight corridor is (4,0).
	assert_that(AITactics.closest_reachable_cell_to(unit, Vector2i(11, 0), _context(board))).is_equal(Vector2i(4, 0))


func test_closest_reachable_cell_to_respects_allowed() -> void:
	var board: Dictionary = _build_board(Rect2i(0, 0, 12, 1))
	var unit: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))

	var allowed := { Vector2i(3, 0): true, Vector2i(1, 0): true }
	assert_that(AITactics.closest_reachable_cell_to(unit, Vector2i(11, 0), _context(board), allowed)).is_equal(Vector2i(3, 0))


func test_closest_reachable_cell_to_stays_put_when_nothing_allowed() -> void:
	var board: Dictionary = _build_board(Rect2i(0, 0, 12, 1))
	var unit: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))

	var allowed := {}   # nothing legal -> current cell wins by fallback
	assert_that(AITactics.closest_reachable_cell_to(unit, Vector2i(11, 0), _context(board), allowed)).is_equal(Vector2i(0, 0))
