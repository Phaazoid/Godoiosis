# The pre-mission phase, headlessly (#46): the loadout screen's placement decisions and its Begin,
# driven through PlaySession with the session as PreMissionPhase's host.
#
# The roster is a REAL shipped one (RosterCatalog), because a roster resolves by name off disk; its
# contents are never asserted (the content razor, tests/README #9) -- every expectation is derived
# from the roster's own offered entries or from the phase's own answers. The mission around it is
# authored here, in memory: a strip of grass, a five-cell DEPLOYMENT zone, one enemy.
#
# The game-vs-headless agreement is tests/flow/test_pre_mission_two_hosts.gd; this file is the
# headless host on its own.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const CAP := 2
const ZONE: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
const OUTSIDE := Vector2i(6, 2)   # grass, but not in the zone

var _board: Dictionary
var _sess
var _drawn := 0


func before_test() -> void:
	_board = BoardBuilder.build(self, "PreMissionRoot")
	auto_free(_board.root)
	BoardBuilder.paint_rect(_board.grid, Rect2i(0, 0, 10, 4))
	BoardBuilder.spawn(_board, UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Foe",
			Team.Faction.ENEMY), Vector2i(9, 3))
	var scenario := ScenarioData.new()
	scenario.roster = _largest_roster()
	scenario.deployment_cap = CAP
	scenario.zones = {"landing": {"kind": ZoneManager.Kind.DEPLOYMENT, "cells": ZONE.duplicate()}}
	_board.zone_manager.load_dict(scenario.zones)
	_board["scenario"] = scenario
	_sess = PlaySession.new(_board)
	_drawn = _sess.start_pre_mission()


# The shipped roster offering the most characters, so the cap leaves someone in reserve.
static func _largest_roster() -> String:
	var best := ""
	var most := -1
	for name: String in RosterCatalog.saved_rosters():
		var count := _offered_count(name)
		if count > most:
			best = name
			most = count
	return best


static func _offered_count(roster_name: String) -> int:
	var roster: Roster = RosterCatalog.resolve(roster_name)
	if roster == null:
		return 0
	var count := 0
	for entry: ScenarioUnitEntry in roster.offered_entries():
		if entry != null and entry.unit_data != null:
			count += 1
	return count


func _deployed() -> Array[Unit]:
	var out: Array[Unit] = []
	for unit: Unit in _sess.roster_units():
		if _sess.is_deployed(unit):
			out.append(unit)
	return out


func _reserve() -> Array[Unit]:
	return _sess.reserve_units()


func _precondition_reserve() -> bool:
	if _reserve().is_empty():
		fail("fixture: the largest shipped roster is not larger than the cap (%d), so nobody waits in reserve" % CAP)
		return false
	return true


func _free_zone_cell() -> Vector2i:
	for cell: Vector2i in ZONE:
		if _sess.get_unit_at_cell(cell) == null:
			return cell
	return Vector2i(-99, -99)


# ==============================================================================

func test_the_draw_puts_the_roster_in_reserve_and_stands_the_authored_plan() -> void:
	assert_bool(_drawn > 0).override_failure_message("nobody stood up -- is a roster shipped?").is_true()
	assert_bool(_sess.is_deploying()).is_true()
	assert_int(_sess.deployed_count()).is_equal(_drawn)
	assert_int(_drawn).is_less_equal(CAP)
	for unit: Unit in _deployed():
		assert_bool(ZONE.has(unit.movement.cell)).override_failure_message(
			"%s stood outside the deployment zone" % unit.get_unit_name()).is_true()
	# Everybody the roster offers exists, standing or waiting.
	assert_int(_deployed().size() + _reserve().size()).is_equal(_offered_count(_largest_roster()))


func test_every_battle_verb_waits_for_begin() -> void:
	var h: String = _sess.handle_for(_deployed()[0])
	var answers: Array[Dictionary] = [
		_sess.legal_moves(h), _sess.queue_move(h, Vector2i(1, 1)), _sess.execute(), _sess.end_turn()]
	for answer: Dictionary in answers:
		assert_bool(answer.ok).is_false()
		assert_str(str(answer.error)).contains("has not begun")


func test_the_cap_refuses_one_more_in_the_phases_own_words() -> void:
	if not _precondition_reserve():
		return
	assert_int(_sess.deployed_count()).is_equal(CAP)
	var reason: String = _sess.deploy_block_reason()
	assert_str(reason).override_failure_message("fixture: the force is not full").is_not_empty()
	var r: Dictionary = _sess.deploy(_sess.handle_for(_reserve()[0]), _free_zone_cell())
	assert_bool(r.ok).is_false()
	assert_str(str(r.error)).is_equal(reason)


func test_undeploy_frees_a_place_and_deploy_takes_only_a_zone_cell() -> void:
	if not _precondition_reserve():
		return
	var standing := _deployed()[0]
	assert_bool((_sess.undeploy(_sess.handle_for(standing)) as Dictionary).ok).is_true()
	assert_bool(_sess.is_deployed(standing)).is_false()

	var waiting := _reserve()[0]
	var outside: Dictionary = _sess.deploy(_sess.handle_for(waiting), OUTSIDE)
	assert_bool(outside.ok).is_false()
	assert_bool(_sess.is_deployed(waiting)).is_false()

	var cell := _free_zone_cell()
	assert_bool((_sess.deploy(_sess.handle_for(waiting), cell) as Dictionary).ok).is_true()
	assert_bool(_sess.is_deployed(waiting)).is_true()
	assert_object(waiting.squad).override_failure_message("a deployed unit has no squad").is_not_null()
	assert_that(waiting.movement.cell).is_equal(cell)


func test_reposition_swaps_two_drawn_units_and_stays_in_the_zone() -> void:
	var standing := _deployed()
	if standing.size() < 2:
		fail("fixture: fewer than two units stood up")
		return
	var a := standing[0]
	var b := standing[1]
	var a_cell := a.movement.cell
	var b_cell := b.movement.cell
	assert_bool((_sess.reposition(_sess.handle_for(a), b_cell) as Dictionary).ok).is_true()
	assert_that(a.movement.cell).is_equal(b_cell)
	assert_that(b.movement.cell).is_equal(a_cell)
	assert_bool((_sess.reposition(_sess.handle_for(a), OUTSIDE) as Dictionary).ok).is_false()


func test_a_reserve_unit_takes_no_squad_verb() -> void:
	if not _precondition_reserve():
		return
	var r: String = _sess.handle_for(_reserve()[0])
	var d: String = _sess.handle_for(_deployed()[0])
	for answer: Dictionary in [_sess.join(r, d) as Dictionary, _sess.join(d, r) as Dictionary,
			_sess.leave(r) as Dictionary]:
		assert_bool(answer.ok).is_false()
		assert_str(str(answer.error)).contains("in reserve")


func test_begin_is_refused_with_nobody_standing_and_then_opens_the_battle() -> void:
	for unit: Unit in _deployed():
		_sess.undeploy(_sess.handle_for(unit))
	var refused: Dictionary = _sess.begin()
	assert_bool(refused.ok).is_false()
	assert_bool(_sess.is_deploying()).is_true()

	var first: Unit = _sess.roster_units()[0]
	assert_bool((_sess.deploy(_sess.handle_for(first), _free_zone_cell()) as Dictionary).ok).is_true()
	assert_bool((_sess.begin() as Dictionary).ok).is_true()
	assert_bool(_sess.is_deploying()).is_false()
	var moves: Dictionary = _sess.legal_moves(_sess.handle_for(first))
	assert_str(str(moves.get("error", ""))).not_contains("has not begun")
