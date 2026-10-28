# The AI and smoke (#1514, a #117 child). Smoke on a squad leader's cell shortens its leash (#1335):
# a leader keeps out of the cells the round's gas will drift that smoke onto, and a walk toward a
# place asks only cells the squad can follow it to.
#
# Every case plans through the AI's real door and asserts on the plan it left. Cells that depend on
# movement are DERIVED: from a clear-board run, from the unit's MOV, and from the gas rules.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const ZONE := "post"
const FIGHT := Rect2i(0, 0, 12, 5)
const LEADER_AT := Vector2i(2, 2)
const MEMBER_AT := Vector2i(2, 3)
const TARGET_AT := Vector2i(6, 2)


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


func _plan(squad: Squad, board: Dictionary) -> void:
	AIController.plan_squad(squad, _ctx(board), board.squad_manager)


func _heedless() -> void:
	var heedless := AIProfile.new()
	heedless.avoids_hazards = false
	AIProfiles.use_fixtures({"": heedless})


func _gas(board: Dictionary) -> GasField:
	return board.gas_field as GasField


# --- A leader keeps out of the round's drift --------------------------------------------------------

# A fast two-unit squad and a sturdy target in the open: the leader walks up and fights.
func _fight(board: Dictionary) -> Unit:
	var leader := _spawn(board, ENEMY, LEADER_AT, {Stats.Stat.DEX: 30, Stats.Stat.LDR: 10})
	var member := _spawn(board, ENEMY, MEMBER_AT, {Stats.Stat.DEX: 30})
	board.squad_manager.join_squad(member, leader.squad)
	_spawn(board, PLAYER, TARGET_AT, {Stats.Stat.MHP: 40})
	return leader


# Where the leader fights from on a clear board.
func _clear_board_cell() -> Vector2i:
	var board := _build_board(FIGHT)
	var leader := _fight(board)
	_plan(leader.squad, board)
	var at := leader.get_projected_destination()
	assert_int(GridUtils.manhattan_distance(at, TARGET_AT)).override_failure_message(
			"fixture: on a clear board the leader must fight, not %s" % [at]).is_equal(1)
	return at


# The same fight with thick smoke one cell behind `cell`, away from the target: the round spills it
# onto `cell` and nowhere else the leader could fight from.
func _smoky_fight(cell: Vector2i) -> Dictionary:
	var board := _build_board(FIGHT)
	var leader := _fight(board)
	var source := cell + (cell - TARGET_AT)
	assert_bool(FIGHT.has_point(source)).override_failure_message("fixture: no room behind %s" % [cell]).is_true()
	_gas(board).set_level(source, Gas.Kind.SMOKE, Gas.Level.THICK)
	var ctx := _ctx(board)
	var drift := _gas(board).next_round(ctx)
	assert_bool(SquadCohesion.reach_in(leader.state, drift.get(cell, 0)) < SquadCohesion.reach_at(leader.state, cell, ctx)) \
		.override_failure_message("fixture: the round's smoke does not shorten the leash on %s" % [cell]).is_true()
	return {"board": board, "leader": leader}


func test_a_leader_fights_from_a_cell_the_rounds_smoke_will_not_reach() -> void:
	var drifted := _clear_board_cell()
	var setup := _smoky_fight(drifted)
	var leader: Unit = setup.leader

	_plan(leader.squad, setup.board)

	var at := leader.get_projected_destination()
	assert_that(at).override_failure_message(
			"the leader stopped where the round's smoke will cut its squad loose").is_not_equal(drifted)
	assert_int(GridUtils.manhattan_distance(at, TARGET_AT)).override_failure_message(
			"the leader gave up the fight to dodge the smoke, ending at %s" % [at]).is_equal(1)


# #1230: a band that does not avoid hazards reads the drift as ordinary ground.
func test_a_leader_that_ignores_hazards_fights_from_the_drift() -> void:
	_heedless()
	var drifted := _clear_board_cell()
	var setup := _smoky_fight(drifted)
	var leader: Unit = setup.leader

	_plan(leader.squad, setup.board)

	assert_that(leader.get_projected_destination()).override_failure_message(
			"a leader that ignores hazards still stepped round the drift").is_equal(drifted)


# --- A walk asks only cells its squad can follow it to ---------------------------------------------

# A Sentry squad drawn off its post walks home down a corridor. Smoke on the post shortens the leash
# there below what the member can close, so the leader stops short rather than freezing the squad.
func test_a_sentry_walking_home_into_smoke_stops_where_its_squad_can_follow() -> void:
	var board := _build_board(Rect2i(0, 0, 18, 1))
	var start := Vector2i(6, 0)
	var leader := _spawn(board, ENEMY, start, {Stats.Stat.LDR: 10})
	var reach := leader.squad.get_max_squad_range()
	assert_bool(reach <= start.x).override_failure_message("fixture: no room behind the leader").is_true()
	var member := _spawn(board, ENEMY, start - Vector2i(reach, 0))   # at the leash's edge, as fast as it
	board.squad_manager.join_squad(member, leader.squad)
	var post := start + Vector2i(leader.get_mov(), 0)
	assert_bool(post.x < 18).override_failure_message("fixture: the corridor is too short").is_true()
	for x in range(0, 18):
		(board.zone_manager as ZoneManager).paint_cell(ZONE, ZoneManager.Kind.PATROL, Vector2i(x, 0))
	leader.squad.archetype = AIArchetype.Type.SENTRY
	leader.squad.zone_name = ZONE
	leader.squad.home_cell = post
	_gas(board).set_level(post, Gas.Kind.SMOKE, GasRules.for_kind(Gas.Kind.SMOKE).state_from)
	var ctx := _ctx(board)
	assert_bool(RulesService.compute_move_range(leader, ctx).reachable.has(post)).override_failure_message(
			"fixture: the leader cannot reach its post this turn").is_true()
	assert_bool(SquadCohesion.reach_at(leader.state, post, ctx) < reach).override_failure_message(
			"fixture: smoke on the post does not shorten the leash").is_true()
	assert_bool(GroupMoveSolver.followable_destinations(leader.squad, ctx, [post]).is_empty()).override_failure_message(
			"fixture: the member can follow the leader onto the smoky post").is_true()

	_plan(leader.squad, board)

	var at := leader.get_projected_destination()
	assert_that(at).override_failure_message(
			"the squad froze: its walk home asked a cell the member could not follow it to").is_not_equal(start)
	assert_bool(GridUtils.manhattan_distance(at, post) < GridUtils.manhattan_distance(start, post)) \
		.override_failure_message("the leader did not close on its post, ending at %s" % [at]).is_true()
	assert_bool(SquadCohesion.in_range(leader.squad, at, member, member.get_projected_destination(), ctx)) \
		.override_failure_message("the member was left outside the leash").is_true()
