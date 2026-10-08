# MissionState -- one mission's state and rules, shared by both hosts (#46).
#
# The game's MissionController is pinned by test_mission_controller.gd and
# test_mission_lose_conditions.gd, through a real game scene. This suite pins the property the
# headless Play API is about to depend on: the state scores a mission with NO game at all -- a
# fixture board, a bare ZoneManager, and nothing else. A rule that quietly reached back for the
# game would pass both controller suites and fail here.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const POINT := "Alpha Point"

var _sm: SquadManager
var _grid: TileMapLayer
var _zones: ZoneManager
var _state: MissionState
var _player: Unit
var _enemy: Unit


func before_test() -> void:
	_sm = H.make_manager(self)
	_grid = _sm.get_node("../Grid")
	_zones = auto_free(ZoneManager.new())
	add_child(_zones)
	_state = MissionState.new(_zones)
	_player = H.spawn_solo(self, _sm, Team.Faction.PLAYER, Vector2i(0, 0))
	_enemy = H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(6, 0))


# The board as the given units leave it -- standing in for "the enemy has been routed" without
# killing anyone, since BoardContext reads exactly the list it is handed.
func _board(units: Array[Unit]) -> BoardContext:
	return BoardContext.new(_grid, units, _sm, null, _zones)


func _both() -> BoardContext:
	var units: Array[Unit] = [_player, _enemy]
	return _board(units)


# The enemy routed.
func _alone() -> BoardContext:
	var units: Array[Unit] = [_player]
	return _board(units)


func test_a_rout_does_not_win_a_capture_mission() -> void:
	_zones.paint_cell(POINT, ZoneManager.Kind.CAPTURE, Vector2i(3, 3))
	_state.objectives.assign([MissionRules.Objective.CAPTURE])
	assert_int(_state.evaluate(_both())).is_equal(MissionRules.Outcome.ONGOING)

	assert_int(_state.evaluate(_alone())) \
		.override_failure_message("routing the enemy won a mission whose one objective is a capture") \
		.is_equal(MissionRules.Outcome.ONGOING)

	assert_bool(_state.capture(POINT)).is_true()
	assert_int(_state.evaluate(_alone())).is_equal(MissionRules.Outcome.VICTORY)


func test_the_clock_fires_on_its_last_round_and_not_before() -> void:
	_state.lose_conditions.assign([MissionRules.LoseCondition.ROUND_LIMIT])
	_state.round_limit = 3
	while _state.rounds_remaining() > 0:
		assert_int(_state.evaluate(_both())) \
			.override_failure_message("the clock fired with %d rounds left" % _state.rounds_remaining()) \
			.is_equal(MissionRules.Outcome.ONGOING)
		_state.advance_round()

	assert_int(_state.evaluate(_both())).is_equal(MissionRules.Outcome.DEFEAT)
	assert_int(_state.failed_by).is_equal(MissionRules.LoseCondition.ROUND_LIMIT)


func test_a_protected_death_latches_and_an_unprotected_one_does_not() -> void:
	var vip := H.spawn_solo(self, _sm, Team.Faction.PLAYER, Vector2i(0, 2))
	vip.must_survive = true
	_state.lose_conditions.assign([MissionRules.LoseCondition.PROTECTED_UNIT_LOST])
	var with_vip: Array[Unit] = [_player, vip, _enemy]
	assert_int(_state.evaluate(_board(with_vip))).is_equal(MissionRules.Outcome.ONGOING)

	_state.note_unit_died(_player)   # not flagged: the mission does not care
	assert_bool(_state.protected_lost).is_false()

	# The VIP is GONE from the board by the time anything evaluates -- Unit.die() queue_frees -- so
	# only the latch can say it died rather than was never placed.
	_state.note_unit_died(vip)
	var without_vip: Array[Unit] = [_player, _enemy]
	assert_int(_state.evaluate(_board(without_vip))).is_equal(MissionRules.Outcome.DEFEAT)
	assert_int(_state.failed_by).is_equal(MissionRules.LoseCondition.PROTECTED_UNIT_LOST)
	assert_array(_state.lose_conditions_missing_setup(_board(without_vip))) \
		.override_failure_message("the condition that just fired reported itself as never set up") \
		.is_empty()


func test_an_ended_mission_stays_ended_whatever_the_board_does_next() -> void:
	assert_int(_state.evaluate(_both())).is_equal(MissionRules.Outcome.ONGOING)
	assert_int(_state.evaluate(_alone())).is_equal(MissionRules.Outcome.VICTORY)

	# The enemy "comes back": a live evaluation would read this board as ONGOING.
	assert_int(_state.evaluate(_both())).is_equal(MissionRules.Outcome.VICTORY)
	assert_bool(_state.is_over()).is_true()


func test_reset_is_a_blank_slate() -> void:
	_zones.paint_cell(POINT, ZoneManager.Kind.CAPTURE, Vector2i(3, 3))
	_state.objectives.assign([MissionRules.Objective.CAPTURE])
	_state.capture(POINT)
	_state.advance_round()
	_state.evaluate(_both())
	_state.evaluate(_alone())
	assert_bool(_state.is_over()).is_true()

	_state.reset()

	assert_bool(_state.is_over()).is_false()
	assert_bool(_state.contested).is_false()
	assert_array(_state.captured_zones).is_empty()
	assert_array(_state.objectives).is_empty()
	assert_int(_state.rounds_elapsed).is_equal(0)
