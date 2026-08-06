# #103: an AI squad's turn must ALWAYS terminate, and the AI must not author a plan it can't run.
#
# The bug: OrderExecutor.execute_orders' invalid-plan guard is a PLAYER affordance — flash the bad
# rows red, hand control back, let the human re-plan and press Execute again. Its early `return`
# sits above everything that ends a squad's turn, so an AI squad refused there left the board
# dressed for a plan that never ran (ghosts, path arrows, a projected destination pointing at a
# cell the unit never reached) with has_acted still false. Nothing in the turn cycle mutated the
# state that produced the plan, so the identical plan was refused every turn — forever.
#
# Two defects, tested separately because either alone is enough to hang the game:
#   1. Rushdown/Sentry can queue a group move whose formation strands a member outside the
#      leader's NEW cohesion range, and SquadPlanValidator._check_leader_range refuses the WHOLE
#      plan (SquadManager.setup_hold_move_actions gives such a member a hold, and holds are judged
#      too). Cohesion was briefly relaxed here on 2026-08-04 and put back the same day — a leader
#      may leave a member SHORT of its formation slot, never outside the bubble.
#   2. Whatever the plan turns out to be, an AI pass must reach the terminal state.
#
# The player never meets defect 1 any more: GroupMoveSolver.followable_destinations paints those
# destinations red before the click (tests/squad/test_squad_cohesion.gd). The AI does not read that
# overlay, so it still authors the refusal and still has to survive it.
#
# Why the game scene and not the headless board: the hold-position filler is queued by game.gd's
# squad_became_active handler, so a board built by play/board_builder.gd never grows the orders
# whose validity is the whole bug. That is exactly why the Play API never reproduced #103. Fixture
# is tests/ui/test_game_scene_smoke.gd's — the instanced root MUST be named "Main" under /root or
# game.gd's absolute /root/Main/DevOverlay lookup returns null (#114, tests/README.md).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true, move_cost=1 in TestTiles.tres

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


# ------------------------------------------------------------------------------
#  Fixtures
# ------------------------------------------------------------------------------

func _paint_corridor(length: int) -> void:
	for x in range(length):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()   # off-map or unwalkable — the test's own setup is wrong
	unit.equipped_weapon = H.make_weapon()
	return unit


# The minimised repro: one Rushdown squad whose leader can charge a distant enemy its member cannot
# keep up with. The three allied NON-squadmates are the jam — allied bodies do not block traversal,
# but RulesService.compute_move_range drops their cells as DESTINATIONS, which is the "both squads
# converged on the last hostile" state boiled down to a corridor.
#
# Geometry (COH 3, MOV 4): the leader's best attack destination is (5,0), and no cell within
# 3 of it is free for the member — every one is either the leader's own target or a blocker's. So
# the member can be placed nowhere legal, and the destination is refused for the whole squad.
func _jam_board() -> Dictionary:
	_paint_corridor(10)
	var leader := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var member := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	for x in [2, 3, 4]:
		# HOLD, so the jam is STABLE: these never reposition and the corridor never clears.
		_spawn(Team.Faction.PLAYER, Vector2i(x, 0)).squad.archetype = AIArchetype.Type.HOLD
	var enemy := _spawn(Team.Faction.ENEMY, Vector2i(9, 0))
	enemy.squad.archetype = AIArchetype.Type.HOLD
	await await_idle_frame()

	game.squad_manager.join_squad(member, leader.squad)
	leader.squad.archetype = AIArchetype.Type.RUSHDOWN
	game.ai_controller.set_faction_ai_enabled(Team.Faction.PLAYER, true)
	return {"leader": leader, "member": member, "squad": leader.squad, "enemy": enemy}


# A squad holding an invalid plan, so the GUARD can be tested without depending on any archetype's
# movement taste. ORDER IS THE MECHANISM, and it is the only way to reach this state now that
# queue_action refuses an order that would land invalid.
func _hand_built_invalid_plan() -> Dictionary:
	_paint_corridor(12)
	var leader := _spawn(Team.Faction.PLAYER, Vector2i(5, 0))
	var member := _spawn(Team.Faction.PLAYER, Vector2i(6, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(member, leader.squad)

	_strand_member_behind(leader, member)
	return {"leader": leader, "member": member, "squad": leader.squad}


# Queue the member's step away from the leader FIRST — legal while the two stand adjacent, since it
# lands 2 from the leader's projected cell — then the leader's retreat, which puts that same cell 6
# away and flips it to invalid. A hold would do just as well (it is #103's own shape, covered in
# test_squad_cohesion.gd); an ordered move is used here so the fixture depends on no filler.
func _strand_member_behind(leader: Unit, member: Unit) -> void:
	_queue_move(member, member.movement.cell + Vector2i.RIGHT)
	_queue_move(leader, Vector2i(1, 0))
	game.squad_manager.validate_squad_plan(leader.squad)


func _queue_move(unit: Unit, destination: Vector2i) -> void:
	var reach := RulesService.compute_move_range(unit, game._board())
	var move := MoveAction.new()
	move.init(unit, RulesService.reconstruct_path(reach.came_from, unit.movement.cell, destination),
		GridUtils.get_terrain_icon_at_cell(game.grid, destination))
	assert_bool(game.squad_manager.queue_action(unit.squad, move)).is_true()


func _move_for(unit: Unit) -> MoveAction:
	for action in unit.squad.action_queue:
		if action.actor == unit and action.action_type == BaseAction.ActionType.MOVE:
			return action as MoveAction
	return null


# The terminal state of a squad's turn: nothing queued, nothing projected, nothing drawn, and the
# squad marked as having spent its turn. Asserted as ONE block because #103 was every one of these
# leaking together — checking has_acted alone would pass on a fix that still left the ghosts up.
func _assert_turn_terminated(squad: Squad) -> void:
	assert_bool(squad.has_acted).override_failure_message("squad never acted").is_true()
	assert_int(squad.action_queue.size()).override_failure_message("orders left queued").is_equal(0)
	assert_int(game.overlay_manager.projected_unit_sprites.size()) \
		.override_failure_message("projection ghosts left on the board").is_equal(0)
	assert_int(game.overlay_manager.planned_move_by_unit.size()) \
		.override_failure_message("path arrows left on the board").is_equal(0)
	for member in squad.get_members():
		assert_bool(member.visuals.sprite.visible) \
			.override_failure_message("%s's real sprite is still hidden behind a ghost" % member.get_unit_name()).is_true()
		assert_that(member.get_projected_destination()) \
			.override_failure_message("%s still projects onto a cell it never reached" % member.get_unit_name()) \
			.is_equal(member.movement.cell)


# ==============================================================================
#  Defect 2 — the guard. An AI pass terminates however the plan turned out.
# ==============================================================================

func test_ai_squad_refused_plan_still_ends_its_turn() -> void:
	var board: Dictionary = await _hand_built_invalid_plan()
	var squad: Squad = board.squad
	game.ai_controller.set_faction_ai_enabled(Team.Faction.PLAYER, true)

	# Precondition: the plan really is refused, and the leader's valid move really is projecting a
	# ghost onto a cell it has not reached. That ghost is what the enemy AI was swinging at.
	assert_bool(game.squad_manager.squad_has_invalid_actions(squad)).is_true()
	assert_that(board.leader.get_projected_destination()).is_equal(Vector2i(1, 0))
	assert_that(board.leader.movement.cell).is_equal(Vector2i(5, 0))

	await game.order_executor.execute_orders(board.leader)

	_assert_turn_terminated(squad)
	# Conceding is not executing: a refused plan must not half-run.
	assert_that(board.leader.movement.cell).is_equal(Vector2i(5, 0))
	assert_that(board.member.movement.cell).is_equal(Vector2i(6, 0))


# The affordance the guard exists FOR. A human-controlled squad must still get its plan handed
# back — has_acted false, orders intact — or the fix has eaten the feature it was protecting.
func test_player_controlled_squad_keeps_its_refused_plan() -> void:
	var board: Dictionary = await _hand_built_invalid_plan()
	var squad: Squad = board.squad
	game.ai_controller.set_faction_ai_enabled(Team.Faction.PLAYER, false)

	await game.order_executor.execute_orders(board.leader)

	assert_bool(squad.has_acted).override_failure_message("a human's refused plan spent their turn").is_false()
	assert_int(squad.action_queue.size()).override_failure_message("a human's refused orders were dropped").is_equal(2)
	assert_bool(game.squad_manager.squad_has_invalid_actions(squad)).is_true()
	assert_that(board.leader.movement.cell).is_equal(Vector2i(5, 0))


# A hotseat faction with the AI toggle OFF is a HUMAN, whatever its Team.Faction says: the toggle
# is the only thing that decides, so the guard must key on it and not on "is this the player".
func test_hotseat_enemy_squad_keeps_its_refused_plan() -> void:
	_paint_corridor(12)
	var leader := _spawn(Team.Faction.ENEMY, Vector2i(5, 0))
	var member := _spawn(Team.Faction.ENEMY, Vector2i(6, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(member, leader.squad)
	_strand_member_behind(leader, member)
	game.ai_controller.set_faction_ai_enabled(Team.Faction.ENEMY, false)

	await game.order_executor.execute_orders(leader)

	assert_bool(leader.squad.has_acted).is_false()
	assert_int(leader.squad.action_queue.size()).is_equal(2)


# ==============================================================================
#  Defect 1 — the AI must not author a plan it cannot run.
# ==============================================================================

# Giving up the ADVANCE, not the turn: nobody is ordered outside cohesion, and the leader does not
# charge off alone. Cohesion is strict again as of 2026-08-04 — a member the leader cannot bring
# with it refuses the destination — so what this pins is that the refusal costs the squad its step
# and nothing else. Note the shape changed with revert_if_only_hold: a rolled-back group move now
# CLEARS the queue rather than leaving all-holds, so "no advance" means no real move exists at all.
#
# The player-facing half of the same rule (the destination is painted red before the click) lives in
# tests/squad/test_squad_cohesion.gd; the AI does not consult that overlay and just gets refused.
func test_rushdown_gives_up_the_advance_rather_than_stranding_a_member() -> void:
	var board: Dictionary = await _jam_board()
	var squad: Squad = board.squad

	RushdownArchetype.take_squad_turn(squad, game._board(), game.squad_manager)
	game.squad_manager.validate_squad_plan(squad)

	assert_bool(game.squad_manager.squad_has_invalid_actions(squad)) \
		.override_failure_message("Rushdown authored a plan the validator refuses").is_false()

	for action in squad.action_queue:
		if action.action_type != BaseAction.ActionType.MOVE:
			continue
		assert_bool(action.is_hold_position) \
			.override_failure_message("%s kept an advance its squad cannot follow" % action.actor.get_unit_name()) \
			.is_true()

	# The premise, or the assertion above passes on a board where nothing was ever infeasible.
	var charge: Vector2i = AITactics.best_attack_destination(board.leader, board.enemy, game._board())
	assert_int(RulesService.compute_move_range(board.member, game._board(), charge).reachable.size()) \
		.override_failure_message("fixture: the member CAN follow — this jam no longer jams") \
		.is_equal(0)


func test_ai_turn_from_a_jam_terminates_every_turn() -> void:
	var board: Dictionary = await _jam_board()
	var squad: Squad = board.squad

	# Three turns, because #103's signature was STABILITY: the state a refused pass left behind
	# regenerated the same refused pass, identically, forever. One turn cannot see that.
	#
	# The blockers are marked acted each turn, which is both what the reported scenario looked like
	# (the other squads had already moved) and what keeps this affordable: AIController pans the
	# camera to every squad it plans for, 2 real seconds each, and an already-acted squad is skipped.
	for turn in range(3):
		for s in game.squad_manager.squads:
			game.squad_manager.set_has_acted(s, s != squad)
		await game.ai_controller.take_faction_turn(Team.Faction.PLAYER, game._board())
		_assert_turn_terminated(squad)
