# BALANCED (#1220; rulings 11, 13, 14, 18 on #117): with nobody in reach it pursues the nearest enemy
# that could NOT answer it, where Rushdown pursues the nearest at all; among cells it can attack from
# it takes the one the fewest enemies could reach next turn, where Rushdown takes the nearest; and it
# carries Hold's and Sentry's whole action list, so it rescues.
#
# Each case runs the same board twice, Balanced and a Rushdown control, so the fixture is shown to
# offer the choice rather than assumed to. Positions that depend on a unit's movement are DERIVED from
# its MOV rather than assumed.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _build_board(size: Rect2i) -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, size)
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i, stats := {}) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data(stats, faction), cell)
	unit.equipped_weapon = H.make_weapon(3)
	return unit


func _holding(unit: Unit) -> Unit:
	unit.squad.archetype = AIArchetype.Type.HOLD
	return unit


func _plan(squad: Squad, board: Dictionary) -> void:
	AIController.plan_squad(squad, board.squad_manager.board_source.call(), board.squad_manager)


# --- Rulings 13 and 14: who it pursues -------------------------------------------------------------

# Nobody is in reach. The nearer enemy could answer a blow; the farther one's weapon never counters.
# Balanced walks toward the farther one, Rushdown toward the nearer.
func _pursuit_board(archetype: AIArchetype.Type) -> Dictionary:
	var probe := _build_board(Rect2i(0, 0, 1, 1))
	var mov := _spawn(probe, ENEMY, Vector2i.ZERO).get_mov()
	var start := mov + 4
	var board := _build_board(Rect2i(0, 0, start + mov + 8, 3))
	var leader := _spawn(board, ENEMY, Vector2i(start, 1))
	leader.squad.archetype = archetype
	_holding(_spawn(board, PLAYER, Vector2i(start - mov - 3, 1), {Stats.Stat.MHP: 40}))
	var mute := _holding(_spawn(board, PLAYER, Vector2i(start + mov + 5, 1), {Stats.Stat.MHP: 40}))
	(mute.get_equipped_weapon() as WeaponInstance).template.main_attack.can_counter = false
	return {"board": board, "leader": leader, "start": start}


func test_with_nobody_in_reach_balanced_pursues_an_enemy_that_cannot_answer() -> void:
	var setup := _pursuit_board(AIArchetype.Type.BALANCED)
	var leader: Unit = setup.leader
	_plan(leader.squad, setup.board)
	assert_int(leader.get_projected_destination().x).override_failure_message(
			"Balanced walked toward the enemy that could answer it (to %s)" % [leader.get_projected_destination()]) \
		.is_greater(int(setup.start))


func test_the_pursuit_control_rushdown_walks_to_the_nearer_enemy() -> void:
	var setup := _pursuit_board(AIArchetype.Type.RUSHDOWN)
	var leader: Unit = setup.leader
	_plan(leader.squad, setup.board)
	assert_int(leader.get_projected_destination().x).override_failure_message(
			"fixture: Rushdown should take the nearer enemy (went to %s)" % [leader.get_projected_destination()]) \
		.is_less(int(setup.start))


# --- Ruling 11: safety as the last tie-break -------------------------------------------------------

# The target holds at (6,2). The nearest cell to fight it from is (5,2), which a second enemy with a
# reach of two also covers; (6,1) is as good a cell to fight from and only the target reaches it.
func _safety_board(archetype: AIArchetype.Type) -> Dictionary:
	var board := _build_board(Rect2i(0, 0, 12, 6))
	var leader := _spawn(board, ENEMY, Vector2i(2, 2), {Stats.Stat.DEX: 30})
	leader.squad.archetype = archetype
	var target := _holding(_spawn(board, PLAYER, Vector2i(6, 2), {Stats.Stat.MHP: 40}))
	var lancer := _holding(_spawn(board, PLAYER, Vector2i(5, 4), {Stats.Stat.MHP: 40}))
	P.point((lancer.get_equipped_weapon() as WeaponInstance).template.main_attack, 2)
	return {"board": board, "leader": leader, "target": target, "lancer": lancer}


func _in_lancer_reach(setup: Dictionary) -> bool:
	var lancer: Unit = setup.lancer
	var at: Vector2i = (setup.leader as Unit).get_projected_destination()
	return GridUtils.manhattan_distance(at, lancer.movement.cell) <= 2


func test_balanced_fights_from_the_cell_fewer_enemies_can_reach() -> void:
	var setup := _safety_board(AIArchetype.Type.BALANCED)
	var leader: Unit = setup.leader
	_plan(leader.squad, setup.board)
	var at := leader.get_projected_destination()
	assert_int(GridUtils.manhattan_distance(at, (setup.target as Unit).movement.cell)).override_failure_message(
			"fixture: Balanced must still fight the target, from %s" % [at]).is_equal(1)
	assert_bool(_in_lancer_reach(setup)).override_failure_message(
			"Balanced fought from %s, inside the second enemy's reach" % [at]).is_false()


func test_the_safety_control_rushdown_takes_the_nearest_firing_cell() -> void:
	var setup := _safety_board(AIArchetype.Type.RUSHDOWN)
	var leader: Unit = setup.leader
	_plan(leader.squad, setup.board)
	assert_bool(_in_lancer_reach(setup)).override_failure_message(
			"fixture: Rushdown should take the nearest firing cell, the covered one (went to %s)"
			% [leader.get_projected_destination()]).is_true()


# --- Ruling 18: the whole action list --------------------------------------------------------------

# Nobody is in reach; a squadmate lies downed one full move up the road, beside where the squad will
# stand. Balanced picks it up on the way, which Rushdown -- whose list has no RESCUE -- never does.
func _rescue_board(archetype: AIArchetype.Type) -> Dictionary:
	var board := _build_board(Rect2i(0, 0, 30, 6))
	var leader := _spawn(board, ENEMY, Vector2i(1, 1))
	var member := _spawn(board, ENEMY, Vector2i(1, 2))
	board.squad_manager.join_squad(member, leader.squad)
	leader.squad.archetype = archetype
	var body := _spawn(board, ENEMY, Vector2i(1 + leader.get_mov(), 3))
	body.force_down()
	_holding(_spawn(board, PLAYER, Vector2i(28, 1), {Stats.Stat.MHP: 40}))
	return {"board": board, "leader": leader, "body": body}


func _rescues(setup: Dictionary) -> bool:
	var squad: Squad = (setup.leader as Unit).squad
	for action in squad.action_queue:
		if action is RescueAction and (action as RescueAction).target == setup.body:
			return true
	return false


func test_balanced_rescues_a_downed_squadmate() -> void:
	var setup := _rescue_board(AIArchetype.Type.BALANCED)
	_plan((setup.leader as Unit).squad, setup.board)
	assert_bool(_rescues(setup)).override_failure_message("a Balanced squad left its downed squadmate").is_true()


func test_the_rescue_control_rushdown_does_not_rescue() -> void:
	var setup := _rescue_board(AIArchetype.Type.RUSHDOWN)
	_plan((setup.leader as Unit).squad, setup.board)
	assert_bool(_rescues(setup)).override_failure_message(
			"fixture: Rushdown has no RESCUE and should not have picked the body up").is_false()
