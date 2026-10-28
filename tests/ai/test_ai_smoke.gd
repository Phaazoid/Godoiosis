# The AI and smoke (#1514, a #117 child). Smoke on a squad leader's cell shortens its leash (#1335):
# a leader keeps out of the cells the round's gas will drift that smoke onto, a walk toward a place
# asks only cells the squad can follow it to, and an Air hit that shoves (#1332) is aimed at a cloud
# to blow it onto an enemy leader when that cuts a member loose -- in a band that values splits.
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


# --- A Gust blows smoke onto an enemy leader --------------------------------------------------------

const BLOW := Rect2i(0, 0, 14, 3)
const GALE_AT := Vector2i(1, 1)
const CLOUD_AT := Vector2i(3, 1)   # in the Gust's range, on the line out from it
const SQUAD := {Stats.Stat.LDR: 10, Stats.Stat.MHP: 40}


# The air reaction that blows gas, failing loudly when the content no longer has one.
func _disperse() -> TerrainReaction:
	for reaction in TerrainReactionCatalog.get_all():
		if reaction.in_the_air and reaction.disperses_gas:
			return reaction
	assert_bool(false).override_failure_message("fixture: no authored reaction disperses gas").is_true()
	return null


# A Hold unit whose main is a Gust: Air on units and ground alike, which shoves and deals nothing.
func _galewright(board: Dictionary) -> Unit:
	var unit := _spawn(board, ENEMY, GALE_AT, {}, 1)
	var gust := unit.get_fired_attack()
	gust.targets = EquippableData.TargetMode.BOTH
	gust.max_range = 3
	gust.deals_no_damage = true
	gust.elemental_damage_type = _disperse().incoming_element
	gust.knockback = 2
	unit.squad.archetype = AIArchetype.Type.HOLD
	return unit


# Where a Gust at the cloud lands it: straight on, as far as it shoves.
func _landing(gale: Unit) -> Vector2i:
	return CLOUD_AT + (CLOUD_AT - GALE_AT).sign() * gale.get_fired_attack().knockback


func _recruit(board: Dictionary, leader: Unit, cell: Vector2i) -> Unit:
	var member := _spawn(board, PLAYER, cell, SQUAD)
	board.squad_manager.join_squad(member, leader.squad)
	return member


# Thick smoke on the cloud's cell, with the squad out of the Gust's own reach: the blow is its only aim.
func _lay_cloud(board: Dictionary, gale: Unit) -> void:
	assert_bool(GridUtils.manhattan_distance(GALE_AT, _landing(gale)) > gale.get_fired_attack().max_range) \
		.override_failure_message("fixture: the Gust reaches the squad itself").is_true()
	_gas(board).set_level(CLOUD_AT, Gas.Kind.SMOKE, Gas.Level.THICK)


func _blind_reach(leader: Unit) -> int:
	return SquadCohesion.reach_in(leader.state, Gas.with_level(0, Gas.Kind.SMOKE, Gas.Level.THICK))


func _aims_at(unit: Unit, cell: Vector2i) -> bool:
	for action in unit.squad.action_queue:
		if action is AttackAction and action.actor == unit and (action as AttackAction).target_cell == cell:
			return true
	return false


# The enemy leader stands where the cloud lands, its member at the clear leash's edge.
func _split_setup(board: Dictionary) -> Dictionary:
	var gale := _galewright(board)
	var leader := _spawn(board, PLAYER, _landing(gale), SQUAD)
	var reach := leader.squad.get_max_squad_range()
	assert_bool(_blind_reach(leader) < reach).override_failure_message(
			"fixture: thick smoke does not shorten the leash").is_true()
	var member := _recruit(board, leader, _landing(gale) + Vector2i(reach, 0))
	_lay_cloud(board, gale)
	return {"gale": gale, "member": member}


func test_a_gust_blows_a_cloud_onto_an_enemy_leader_to_split_its_squad() -> void:
	var board := _build_board(BLOW)
	var setup := _split_setup(board)
	var gale: Unit = setup.gale

	_plan(gale.squad, board)

	assert_bool(_aims_at(gale, CLOUD_AT)).override_failure_message(
			"the Galewright did not blow the cloud onto the enemy leader").is_true()
	var plan := (board.squad_manager as SquadManager).resolve_plan(gale.squad, _ctx(board))
	assert_bool(SplitForecast.leavers(plan).has(setup.member)).override_failure_message(
			"the blow it aimed does not cut the member loose").is_true()


# Medium does not value splits (#1230), so the cloud is no mark of its.
func test_a_band_that_does_not_value_splits_never_aims_the_blow() -> void:
	var medium := AIProfile.new()
	medium.values_splits = false
	AIProfiles.use_fixtures({"": medium})
	var board := _build_board(BLOW)
	var gale: Unit = _split_setup(board).gale

	_plan(gale.squad, board)

	assert_bool(_aims_at(gale, CLOUD_AT)).override_failure_message(
			"a band that does not value splits aimed a blow at the cloud").is_false()


# Smoke on a member sets no leash. A second member stands where a leash measured from the cloud's
# landing would lose it, so reading the member's cell as the leader's would aim the blow.
func test_no_blow_is_aimed_when_the_cloud_would_land_on_a_member() -> void:
	var board := _build_board(BLOW)
	var gale := _galewright(board)
	var leader := _spawn(board, PLAYER, _landing(gale) + Vector2i(1, 0), SQUAD)
	var reach := leader.squad.get_max_squad_range()
	assert_bool(_blind_reach(leader) < reach).override_failure_message(
			"fixture: thick smoke does not shorten the leash").is_true()
	_recruit(board, leader, _landing(gale))
	_recruit(board, leader, _landing(gale) + Vector2i(reach, 0))
	_lay_cloud(board, gale)

	_plan(gale.squad, board)

	assert_bool(_aims_at(gale, CLOUD_AT)).override_failure_message(
			"the Galewright blew the cloud onto a member, which splits nobody").is_false()


func test_no_blow_is_aimed_when_the_members_stand_inside_the_shorter_leash() -> void:
	var board := _build_board(BLOW)
	var gale := _galewright(board)
	var leader := _spawn(board, PLAYER, _landing(gale), SQUAD)
	assert_int(_blind_reach(leader)).override_failure_message(
			"fixture: thick smoke leaves no leash at all, so a member beside the leader still leaves").is_greater_equal(1)
	_recruit(board, leader, _landing(gale) + Vector2i(1, 0))
	_lay_cloud(board, gale)

	_plan(gale.squad, board)

	assert_bool(_aims_at(gale, CLOUD_AT)).override_failure_message(
			"the Galewright blew the cloud onto a leader whose squad stays together").is_false()
