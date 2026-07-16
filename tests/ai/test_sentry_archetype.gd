# SentryArchetype (#29): the zone-bound guard's three stateless branches — engage an
# intruder (zone-clamped), walk home when clear, idle at the post. Also the lure-proofing
# contract: an enemy in weapon reach but OUTSIDE the zone is pointedly ignored, and no
# queued destination may leave zone∪post. Real managers + TestTiles via board_builder.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const ZONE := "post"


func _build_board() -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(0, 0, 8, 3))
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data({}, faction), cell)
	unit.equipped_weapon = H.make_weapon()
	return unit


# Zone = the 4x3 room x:0..3 / y:0..2 (inside the painted 8x3 board).
func _make_zone_manager() -> ZoneManager:
	var zones: ZoneManager = auto_free(ZoneManager.new())
	for x in range(0, 4):
		for y in range(0, 3):
			zones.paint_cell(ZONE, Vector2i(x, y))
	return zones


func _context(board: Dictionary, zones: ZoneManager) -> BoardContext:
	var units: Array[Unit] = []
	for child in board.units_root.get_children():
		units.append(child as Unit)
	return BoardContext.new(board.grid, units, board.squad_manager, null, zones)


func _bind_sentry(unit: Unit, home: Vector2i) -> Squad:
	var squad: Squad = unit.squad
	squad.archetype = AIArchetype.Type.SENTRY
	squad.zone_name = ZONE
	squad.home_cell = home
	return squad


func _move_destinations(squad: Squad) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for action in squad.action_queue:
		if action is MoveAction:
			result.append((action as MoveAction).destination)
	return result


func _attack_aims(squad: Squad) -> Array[AttackAction]:
	var result: Array[AttackAction] = []
	for action in squad.action_queue:
		if action is AttackAction:
			result.append(action as AttackAction)
	return result


func test_idle_at_post_queues_nothing() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var guard: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 1))
	var squad: Squad = _bind_sentry(guard, Vector2i(1, 1))
	var _intruder: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(7, 1))   # far outside the zone

	SentryArchetype.take_squad_turn(squad, _context(board, zones), board.squad_manager)

	assert_array(squad.action_queue).is_empty()


func test_cannot_be_lured_by_enemy_in_reach_but_outside_zone() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var guard: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1))       # zone edge, at its post
	var squad: Squad = _bind_sentry(guard, Vector2i(3, 1))
	var _bait: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(4, 1))      # adjacent = in weapon reach, NOT in zone

	SentryArchetype.take_squad_turn(squad, _context(board, zones), board.squad_manager)

	assert_array(squad.action_queue).is_empty()


func test_intruder_triggers_zone_clamped_engage() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var guard: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 1))
	var squad: Squad = _bind_sentry(guard, Vector2i(0, 1))
	var intruder: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(3, 1))   # standing in the zone

	SentryArchetype.take_squad_turn(squad, _context(board, zones), board.squad_manager)

	# Moved into attack position -- but never onto a cell outside zone∪post.
	var moves: Array[Vector2i] = _move_destinations(squad)
	assert_int(moves.size()).is_equal(1)
	assert_bool(zones.contains(ZONE, moves[0])).is_true()
	assert_bool(guard.combat.get_all_attack_cells_from(moves[0]).has(intruder.movement.cell)).is_true()

	var aims: Array[AttackAction] = _attack_aims(squad)
	assert_int(aims.size()).is_equal(1)
	assert_that(aims[0].target_cell).is_equal(intruder.movement.cell)


func test_returns_to_post_when_zone_clears() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var guard: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1))       # displaced from its post
	var squad: Squad = _bind_sentry(guard, Vector2i(0, 1))

	SentryArchetype.take_squad_turn(squad, _context(board, zones), board.squad_manager)

	# No intruder, no attacking -- one move, straight back to the post (3 cells, within MOV 4).
	assert_array(_attack_aims(squad)).is_empty()
	assert_array(_move_destinations(squad)).contains_exactly([Vector2i(0, 1)])


func test_first_turn_fixes_home_for_mid_play_squads() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var guard: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(2, 1))
	var squad: Squad = guard.squad
	squad.archetype = AIArchetype.Type.SENTRY
	squad.zone_name = ZONE
	assert_that(squad.home_cell).is_equal(Squad.NO_HOME)   # never set: not from a scenario load

	SentryArchetype.take_squad_turn(squad, _context(board, zones), board.squad_manager)

	assert_that(squad.home_cell).is_equal(Vector2i(2, 1))
	assert_array(squad.action_queue).is_empty()            # already standing on its (new) post


func test_missing_zone_falls_back_to_hold() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = auto_free(ZoneManager.new())  # empty: assigned zone was never painted
	var guard: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(2, 1))
	var squad: Squad = _bind_sentry(guard, Vector2i(2, 1))
	var intruder: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(2, 2))   # adjacent

	SentryArchetype.take_squad_turn(squad, _context(board, zones), board.squad_manager)

	# Hold semantics: attack what's in reach, never move.
	assert_array(_move_destinations(squad)).is_empty()
	var aims: Array[AttackAction] = _attack_aims(squad)
	assert_int(aims.size()).is_equal(1)
	assert_that(aims[0].target_cell).is_equal(intruder.movement.cell)
