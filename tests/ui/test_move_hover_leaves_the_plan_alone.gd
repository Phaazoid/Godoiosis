# A Move hover previews the click; it never re-plans. The hover validates the queue WITH the candidate
# in it, which stamps verdicts onto the queued orders themselves, and it used to re-resolve the real
# queue straight after, off those borrowed verdicts. Hovering a squadmate's queued destination then
# published a plan in which that squadmate never walked: its shove gone, the shot landing on it red,
# the cached plan rewritten, all standing until the next legal tile.
#
# What the hover draws follows the queueing rule (dev, 2026-10-24): an illegal move is never queued,
# and an order goes red only when something that really happens invalidates it. A REFUSED tile queues
# nothing, so it re-tints no squadmate; a LEGAL one shows the squadmates it would turn red, before the
# click, so the knock-on is never silent.
# Fixture is tests/ui/test_safe_route_wire.gd's game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true, move_cost=1 in TestTiles.tres
const OFF_THE_BOARD := Vector2i(40, 40)

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.DEX: 10}, Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()
	return unit


# A leader whose bubble reaches three tiles and who has seats for its squadmates.
func _squad(leader_cell: Vector2i, member_cells: Array[Vector2i]) -> Array[Unit]:
	for x in range(-8, 9):
		for y in range(-8, 9):
			game.grid.paint(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	var leader := _spawn(leader_cell)
	leader.unit_instance.stats[Stats.Stat.COH] = 3
	leader.unit_instance.stats[Stats.Stat.LDR] = 8 * Squad.MEMBER_LDR_COST
	await await_idle_frame()
	var units: Array[Unit] = [leader]
	for cell in member_cells:
		var member := _spawn(cell)
		game.squad_manager.join_squad(member, leader.squad)
		units.append(member)
	await await_idle_frame()
	return units


# Queued through the player's own click, so the arrow and the ghost are drawn as in play.
func _walk(unit: Unit, cell: Vector2i) -> MoveAction:
	game.select_unit(unit, unit.movement.cell)
	game.begin_move_planning(unit)
	game._click_choosing_move(cell)
	var walk: MoveAction = unit.get_move_action()
	assert_bool(walk != null and not walk.is_hold_position and walk.get_destination() == cell) \
			.override_failure_message("fixture: the click did not queue a walk to %s" % [cell]).is_true()
	return walk


func _struck_by(plan: ResolvedPlan, aim: AttackAction) -> Array[Unit]:
	var struck: Array[Unit] = []
	for row in plan.attacks:
		if row.source_aim == aim and row.target != null:
			struck.append(row.target)
	return struck


func _wears_red(walk: MoveAction) -> bool:
	for sprite in walk.preview:
		if is_instance_valid(sprite) and sprite.modulate == OverlayManager.INVALID_ARROW_MODULATE:
			return true
	return false


# L walks onto D; squadmate N's friendly shot lands on D and shoves L off it. M is left to plan.
func _shove_board() -> Dictionary:
	var units := await _squad(Vector2i(0, 0), [Vector2i(1, 1), Vector2i(2, 3)])
	var leader := units[0]
	var shooter := units[2]
	var weapon := H.make_weapon()
	var attack: AttackData = weapon.template.main_attack
	attack.hits_allies = true
	attack.knockback = 1
	attack.min_range = 1
	attack.max_range = 4
	shooter.add_item(weapon)
	var dest := Vector2i(2, 0)
	_walk(leader, dest)
	var shot := AttackAction.declare(shooter, shooter.get_projected_destination(), dest)
	assert_bool(game.squad_manager.queue_action(leader.squad, shot)) \
			.override_failure_message("fixture: N's shot at D was refused").is_true()
	game.refresh_action_queue(leader.squad)
	return {"leader": leader, "member": units[1], "shot": shot, "dest": dest}


# M opens Move: what the click would see, and the plan the hover must leave alone.
func _plan_member_move(member: Unit, dest: Vector2i) -> void:
	game.select_unit(member, member.movement.cell)
	game.begin_move_planning(member)
	var reach: Dictionary = game.compute_move_range(member)
	assert_bool(reach.reachable.has(dest)).override_failure_message(
			"fixture: M cannot walk to D, so the hover never previews it").is_true()
	assert_bool(reach.reachable.has(OFF_THE_BOARD) or reach.squad_unreachable.has(OFF_THE_BOARD)) \
			.override_failure_message("fixture: the off-board cell is in M's range").is_false()


func test_a_refused_tile_leaves_the_plan_as_queued() -> void:
	var board := await _shove_board()
	var leader: Unit = board.leader
	var shot: AttackAction = board.shot
	var dest: Vector2i = board.dest
	var shoved_to := leader.get_projected_destination()
	assert_that(shoved_to).override_failure_message(
			"fixture: N's shot does not shove L off D, so there is no plan to lose").is_not_equal(dest)
	_plan_member_move(board.member, dest)
	var squad: Squad = leader.squad
	var plan: ResolvedPlan = game.squad_manager.resolved_plan_for(squad)
	assert_object(plan).override_failure_message("fixture: the squad's plan was never resolved").is_not_null()

	game.hover_presenter._hover_choosing_move(dest)
	assert_bool(game.overlay_manager.hover_move_preview.is_valid).override_failure_message(
			"fixture: M's move onto L's destination should be refused").is_false()
	game.hover_presenter._hover_choosing_move(OFF_THE_BOARD)

	assert_object(game.squad_manager.resolved_plan_for(squad)).override_failure_message(
			"the hover re-resolved the plan").is_same(plan)
	assert_that(leader.get_projected_destination()).override_failure_message(
			"after hovering D, L projects to %s, not where N's shot leaves it (%s)"
			% [leader.get_projected_destination(), shoved_to]).is_equal(shoved_to)
	assert_bool(shot.is_valid).override_failure_message(
			"after hovering D, N's shot reads refused: %s" % [shot.validation_errors]).is_true()
	assert_bool(_struck_by(plan, shot).has(leader)).override_failure_message(
			"the plan's shot no longer hits L").is_true()


func test_a_refused_tile_re_tints_no_squadmate() -> void:
	var board := await _shove_board()
	var leader: Unit = board.leader
	_plan_member_move(board.member, board.dest)

	game.hover_presenter._hover_choosing_move(board.dest)

	var walk: MoveAction = game.overlay_manager.planned_move_by_unit.get(leader)
	assert_bool(walk != null and not walk.preview.is_empty()).override_failure_message(
			"fixture: L's queued arrow is not drawn").is_true()
	assert_bool(_wears_red(walk)).override_failure_message(
			"hovering a tile the click refuses drew L's queued move as refused").is_false()
	assert_bool(game.overlay_manager.has_projected_unit(leader)).override_failure_message(
			"hovering a tile the click refuses took L's ghost away").is_true()


func test_a_legal_tile_shows_the_squadmate_it_would_turn_red() -> void:
	var units := await _squad(Vector2i(0, 0), [Vector2i(1, 0)])
	var leader := units[0]
	var member := units[1]
	var squad: Squad = leader.squad
	var member_walk := _walk(member, Vector2i(-2, 0))
	var member_dest := member_walk.get_destination()

	game.select_unit(leader, leader.movement.cell)
	game.begin_move_planning(leader)
	var reach: Dictionary = game.compute_move_range(leader)
	var board: BoardContext = game._board()
	var knock_on := Vector2i(-99, -99)
	var cells: Array = reach.reachable.keys()
	cells.sort()
	for cell: Vector2i in cells:
		if game.leader_followable.has(cell) and not SquadCohesion.in_range(squad, cell, member, member_dest, board):
			knock_on = cell
			break
	assert_that(knock_on).override_failure_message(
			"fixture: no tile L may take leaves K's queued walk out of reach").is_not_equal(Vector2i(-99, -99))
	var plan: ResolvedPlan = game.squad_manager.resolved_plan_for(squad)
	assert_object(plan).override_failure_message("fixture: the squad's plan was never resolved").is_not_null()

	game.hover_presenter._hover_choosing_move(knock_on)

	assert_bool(game.overlay_manager.hover_move_preview.is_valid).override_failure_message(
			"fixture: L's move to %s should be legal" % [knock_on]).is_true()
	assert_bool(_wears_red(member_walk)).override_failure_message(
			"a legal tile that strands K's queued walk did not show it red before the click").is_true()
	assert_bool(member_walk.is_valid).override_failure_message(
			"the hover left K's queued walk refused: %s" % [member_walk.validation_errors]).is_true()
	assert_object(game.squad_manager.resolved_plan_for(squad)).override_failure_message(
			"the hover re-resolved the plan").is_same(plan)
