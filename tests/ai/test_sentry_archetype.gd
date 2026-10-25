# SentryArchetype (#29): the zone-bound guard's stateless branches — engage (zone-clamped),
# pursue an intruder, walk home when clear, hold the post. Its zone limits where it WALKS, never
# what it hits (#1377, dev 2026-10-21): an enemy outside the zone that it can reach from inside is
# fought, and no queued destination may leave zone∪post. Real managers + TestTiles via board_builder.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const ZONE := "post"


func before_test() -> void:
	AIProfiles.use_fixtures({"": AIProfile.new()})   # #1230: this suite owns its AI profile


func after_test() -> void:
	AIProfiles.clear_fixtures()


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
			zones.paint_cell(ZONE, ZoneManager.Kind.PATROL, Vector2i(x, y))
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
	for action in H.given_orders(squad):   # a hold filler (#46) goes nowhere
		if action is MoveAction:
			result.append((action as MoveAction).destination)
	return result


func _attack_aims(squad: Squad) -> Array[AttackAction]:
	var result: Array[AttackAction] = []
	for action in squad.action_queue:
		if action is AttackAction:
			result.append(action as AttackAction)
	return result


func test_idle_at_post_takes_a_fallback_action_but_never_moves_or_attacks() -> void:
	# At the post with nobody in the zone (#726, dev 2026-09-03: "at the post only"): the fallback
	# walk runs -- a chainsword revs (H.make_weapon's family) -- but nothing moves and nothing
	# swings. This case pinned "queues nothing" until then.
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var guard: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 1))
	var squad: Squad = _bind_sentry(guard, Vector2i(1, 1))
	var _intruder: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(7, 1))   # far outside the zone

	SentryArchetype.take_squad_turn(squad, _context(board, zones), board.squad_manager)

	assert_array(_move_destinations(squad)).is_empty()
	assert_array(_attack_aims(squad)).is_empty()
	assert_int(H.given_orders(squad).size()).is_equal(1)
	assert_int(H.given_orders(squad)[0].action_type).is_equal(BaseAction.ActionType.REV)


# #1377 retired the lure test that stood here: an enemy in reach but outside the zone was "bait"
# and pointedly ignored. The zone now limits the FOOTING alone, so the same board is a fight.
func test_attacks_an_enemy_in_reach_outside_its_zone_without_stepping_out() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var guard: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1))       # zone edge, at its post
	var squad: Squad = _bind_sentry(guard, Vector2i(3, 1))
	var outsider: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(4, 1))   # adjacent = in weapon reach, NOT in zone

	SentryArchetype.take_squad_turn(squad, _context(board, zones), board.squad_manager)

	var aims: Array[AttackAction] = _attack_aims(squad)
	assert_int(aims.size()).override_failure_message(
			"the sentry let an enemy it could hit from its post stand there unanswered").is_equal(1)
	assert_that(aims[0].target_cell).is_equal(outsider.movement.cell)
	for cell in _move_destinations(squad):
		assert_bool(zones.contains(ZONE, cell) or cell == squad.home_cell).override_failure_message(
				"the sentry stepped out of its zone to %s" % cell).is_true()


# ...and the footing half still holds: an enemy it could only hit by standing outside is left alone.
# Mutant: drop `allowed` from the engagement and it steps out to (4, 1) and swings.
func test_never_steps_out_of_its_zone_to_reach_an_enemy() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var guard: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1))       # zone edge, at its post
	var squad: Squad = _bind_sentry(guard, Vector2i(3, 1))
	var _outsider: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(5, 1))  # two out: only hittable from (4, 1)

	SentryArchetype.take_squad_turn(squad, _context(board, zones), board.squad_manager)

	assert_array(_move_destinations(squad)).is_empty()
	assert_array(_attack_aims(squad)).is_empty()
	assert_int(H.given_orders(squad).size()).is_equal(1)
	assert_int(H.given_orders(squad)[0].action_type).is_equal(BaseAction.ActionType.REV)


# AT THE POST it attacks whatever it can hit from where it stands -- here with an extra that outranges
# the melee main the engagement fork reads, so only the post branch can fire it. It took the fallback
# verbs alone until #1377, so this queued a REV and nothing else.
func test_at_its_post_it_fires_a_longer_attack_at_an_enemy_outside_its_zone() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var guard: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1))       # zone edge, at its post
	guard.equipped_weapon = _melee_with_a_long_extra()
	var lob: AttackData = guard.get_selectable_attacks()[1]
	var squad: Squad = _bind_sentry(guard, Vector2i(3, 1))
	var outsider: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(6, 1))   # three out: the melee cannot reach it from the zone

	SentryArchetype.take_squad_turn(squad, _context(board, zones), board.squad_manager)

	assert_array(_move_destinations(squad)).is_empty()
	var aims: Array[AttackAction] = _attack_aims(squad)
	assert_int(aims.size()).override_failure_message(
			"the sentry held its long shot at an enemy it could hit from its post").is_equal(1)
	assert_that(aims[0].target_cell).is_equal(outsider.movement.cell)
	assert_object(aims[0].fired_attack).is_same(lob)


# A melee main (Manhattan 1, the counter) plus an extra that fires at range 1 to 3.
func _melee_with_a_long_extra() -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 3
	var lob := WeaponAttackData.new()
	lob.display_name = "Lob"
	lob.power = 3
	P.point(lob, 3)
	var extras: Array[WeaponAttackData] = [lob]
	template.extra_attacks = extras
	return WeaponInstance.make(template)


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
	assert_bool(Reach.get_all_attack_cells_from(moves[0], guard.get_fired_attack()).has(intruder.movement.cell)).is_true()

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
	assert_array(_move_destinations(squad)).is_empty()     # already standing on its (new) post
	assert_array(_attack_aims(squad)).is_empty()


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
