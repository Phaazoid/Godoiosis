# Two standalone fixes from #1220: a leader with squadmates engages only from a cell its squad can
# follow it to -- the same refusal the player's Move overlay paints grey -- and a body the squad's own
# pass is about to make is rescued in that pass, as the player may (#124).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func before_test() -> void:
	AIProfiles.use_fixtures({"": AIProfile.new()})   # #1230: this suite owns its AI profile


func after_test() -> void:
	AIProfiles.clear_fixtures()


func _build_board(size: Rect2i) -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, size)
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i, stats := {}, power := 3) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data(stats, faction), cell)
	unit.equipped_weapon = H.make_weapon(power)
	return unit


func _ctx(board: Dictionary) -> BoardContext:
	return board.squad_manager.board_source.call()


# --- Followable engagement -----------------------------------------------------------------------

# A fast leader and a slow member on a corridor, the leash one step: the leader alone could charge
# further than the member can keep up with, and the old approach did -- cohesion then refused the
# group move and the squad stood still.
func test_a_leader_advances_only_as_far_as_its_squad_can_follow() -> void:
	var board := _build_board(Rect2i(0, 0, 16, 1))
	var leader := _spawn(board, ENEMY, Vector2i(1, 0), {Stats.Stat.DEX: 30})
	var member := _spawn(board, ENEMY, Vector2i(0, 0), {Stats.Stat.DEX: 1})
	board.squad_manager.join_squad(member, leader.squad)
	leader.unit_instance.stats[Stats.Stat.COH] = 1
	_spawn(board, PLAYER, Vector2i(15, 0))
	assert_int(leader.get_mov()).override_failure_message(
			"fixture: the leader must outrun the member by more than the leash, or nothing is unfollowable") \
		.is_greater(member.get_mov() + 2)

	AIController.plan_squad(leader.squad, _ctx(board), board.squad_manager)

	board.squad_manager.validate_squad_plan(leader.squad)
	assert_bool(board.squad_manager.squad_has_invalid_actions(leader.squad)) \
		.override_failure_message("the squad authored a move its member cannot follow").is_false()
	assert_that(leader.get_projected_destination()).override_failure_message(
			"the squad stood still when it could have advanced together").is_not_equal(Vector2i(1, 0))


# --- Same-pass rescue ------------------------------------------------------------------------------

# A frail member has only one swing, into an enemy whose counter fells it; its squadmate stands beside
# it with nobody to fight. The rescue lands after the counter (reactions, then rescues), so the body
# is picked up in the pass that made it.
func test_a_squadmate_felled_by_a_counter_is_rescued_in_the_same_pass() -> void:
	var board := _build_board(Rect2i(0, 0, 6, 3))
	var frail := _spawn(board, ENEMY, Vector2i(2, 1), {Stats.Stat.MHP: 2})
	var mate := _spawn(board, ENEMY, Vector2i(1, 1))
	board.squad_manager.join_squad(mate, frail.squad)
	frail.squad.archetype = AIArchetype.Type.HOLD   # its list carries RESCUE, and it never moves
	_spawn(board, PLAYER, Vector2i(3, 1), {Stats.Stat.MHP: 40})   # its counter downs, short of a kill

	AITactics.queue_main_actions_for_squad(frail.squad, _ctx(board), board.squad_manager)

	var plan: ResolvedPlan = board.squad_manager.resolve_plan(frail.squad, _ctx(board))
	assert_that(PlanResolver.projected_lifecycle(frail, plan.hypo)).override_failure_message(
			"fixture: the counter must fell the frail member").is_equal(Unit.LifecycleState.DOWNED)
	var rescued := false
	for action in frail.squad.action_queue:
		rescued = rescued or (action is RescueAction and action.actor == mate and (action as RescueAction).target == frail)
	assert_bool(rescued).override_failure_message(
			"the squadmate left a body its own pass made, though it could rescue it this pass").is_true()


# The engagement pick reads the same answer: a safe target (it cannot counter) that only the leader
# could reach, beside an armed one its squad can follow it to. The safe one wins the exchange rank, so
# only followability can make the pick the one the squad can actually fight.
func test_the_engagement_pick_skips_a_target_only_the_leader_could_reach() -> void:
	var board := _build_board(Rect2i(0, 0, 32, 2))
	var leader := _spawn(board, ENEMY, Vector2i(1, 0), {Stats.Stat.DEX: 30})
	var member := _spawn(board, ENEMY, Vector2i(0, 0), {Stats.Stat.DEX: 1})
	board.squad_manager.join_squad(member, leader.squad)
	leader.unit_instance.stats[Stats.Stat.COH] = 1
	var near := _spawn(board, PLAYER, Vector2i(2, 1))
	var firing := Vector2i(1 + leader.get_mov(), 0)   # the furthest the leader alone can stand
	var far := _spawn(board, PLAYER, firing + Vector2i.RIGHT)
	((far.get_equipped_weapon() as WeaponInstance).template.main_attack).can_counter = false
	var ctx := _ctx(board)
	assert_bool(RulesService.compute_move_range(leader, ctx).reachable.has(firing)).override_failure_message(
			"fixture: the leader alone must be able to reach a firing cell on the far target").is_true()
	assert_int(leader.get_mov()).override_failure_message(
			"fixture: the member must not be able to keep up with that cell").is_greater(member.get_mov() + 2)

	assert_object(AITactics.choose_engagement_target(leader, ctx, board.squad_manager)).override_failure_message(
			"the squad picked a fight only its leader could get to").is_same(near)
