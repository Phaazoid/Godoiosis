# AITactics (#29, chooser rebuilt #78): the shared board queries the archetypes compose with,
# plus the ATTACK path of queue_main_action. Runs on the real managers + TestTiles terrain via
# the Play API's headless board_builder (proven pattern). Fixture weapons are pattern-less ->
# Reach falls back to Manhattan range 1 with no pattern, so attack geometry is trivial:
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


# A 12x6 board split by a solid wall at x=5, with the ONLY gap at (5,5):
#
#   x   0 1 2 3 4 5 6 7 8 9 10 11
#   y=0 . . . . . #  . . E . .  .        # = unpainted (impassable)
#   y=1 . . . . . #  . . . . .  .        E = where the tests put the enemy
#    ...
#   y=4 . . . . . #  . . . . .  .
#   y=5 . . . . . .  . . . . .  .        <- the gap
#
# Straight-line distance says the cell against the wall is the best place to stand; the ROUTE says
# the way through is down and around. Every approach test below lives on this board.
func _wall_board(seal_the_gap := false) -> Dictionary:
	var board: Dictionary = _build_board(Rect2i(0, 0, 12, 6))
	var grid: TileMapLayer = board.grid
	var wall_height: int = 6 if seal_the_gap else 5
	for y in range(0, wall_height):
		grid.erase_cell(Vector2i(5, y))
	return board


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
	assert_bool(Reach.get_all_attack_cells_from(leader, dest, leader.get_fired_attack()).has(enemy.movement.cell)).is_true()


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


# --- Approach is by ROUTE, not straight-line distance ---
#
# The bug these pin: every approach query ranked candidate cells by Manhattan distance, so a squad
# facing a wall found that its own cell was already the distance-minimum -- no reachable cell scored
# better -- and stood there. Not for a turn: forever, because nothing about the situation changed
# between turns. Hop distance answers the question distance was standing in for.

func test_best_attack_destination_leaves_a_wall_it_cannot_shoot_through() -> void:
	var board: Dictionary = _wall_board()
	var leader: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(4, 0))    # flat against the wall
	var enemy: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(8, 0))    # two cells away, 14 by road

	var dest: Vector2i = AITactics.best_attack_destination(leader, enemy, _context(board))

	# Every reachable cell is further from (8,0) in a straight line than (4,0) is, which is exactly
	# why the old ranking stalled here. By route, (4,4) is four hops of progress toward the gap.
	assert_that(dest).is_not_equal(Vector2i(4, 0))
	assert_that(dest).is_equal(Vector2i(4, 4))


func test_rushdown_closes_the_whole_distance_over_multiple_turns() -> void:
	var board: Dictionary = _wall_board()
	var leader: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 0))
	var enemy: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(8, 0))

	# One "turn" = pick a destination and walk it. NOTHING is carried between turns -- the field is
	# re-derived from scratch each time, which is what makes a multi-turn route need no stored plan.
	var reached := false
	var crossed := false
	var stalled := false
	for _turn in range(12):
		var dest: Vector2i = AITactics.best_attack_destination(leader, enemy, _context(board))
		if dest == leader.movement.cell:
			stalled = true   # the reported bug: a turn that decides to go nowhere, forever
			break
		leader.movement.set_cell(dest)
		if dest.x > 5:
			crossed = true
		if Reach.get_all_attack_cells_from(leader, dest, leader.get_fired_attack()).has(enemy.movement.cell):
			reached = true
			break

	assert_bool(stalled).is_false()
	assert_bool(crossed).is_true()    # it really went through the gap, not just up to the wall
	assert_bool(reached).is_true()


func test_best_attack_destination_still_closes_in_when_the_target_is_sealed_off() -> void:
	# No route at all: every candidate scores UNREACHABLE, so the ladder falls through to straight-
	# line distance and the squad crowds the nearest shore -- the old behaviour, deliberately kept.
	# What it must NOT do is read "no route" as "stay home".
	var board: Dictionary = _wall_board(true)
	var leader: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 0))
	var enemy: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(8, 0))

	assert_that(AITactics.best_attack_destination(leader, enemy, _context(board))).is_equal(Vector2i(4, 0))


func test_closest_reachable_cell_to_routes_around_a_wall() -> void:
	# Sentry's walk home rides the same ladder: a post on the far side of a wall is approached by
	# route, not by the cell that merely looks nearest.
	var board: Dictionary = _wall_board()
	var unit: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(4, 0))

	assert_that(AITactics.closest_reachable_cell_to(unit, Vector2i(8, 0), _context(board))).is_equal(Vector2i(4, 4))


func test_nearest_enemy_is_nearest_by_route() -> void:
	# (6,0) is two cells away and twelve hops away; (0,4) is eight of each. Chasing the walled one
	# is how a squad commits its whole turn to walking at a wall.
	var board: Dictionary = _wall_board()
	var leader: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(4, 0))
	var _behind_the_wall: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(6, 0))
	var open_side: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 4))

	assert_object(AITactics.nearest_enemy(leader, _context(board))).is_same(open_side)


func test_nearest_enemy_falls_back_to_distance_when_nothing_is_reachable() -> void:
	# Both enemies are sealed away, so route ranks them equally (UNREACHABLE) and distance decides:
	# an unreachable board must still produce a target, or Rushdown returns without acting at all.
	var board: Dictionary = _wall_board(true)
	var leader: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(4, 0))
	var near: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(6, 0))
	var _far: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(11, 5))

	assert_object(AITactics.nearest_enemy(leader, _context(board))).is_same(near)
