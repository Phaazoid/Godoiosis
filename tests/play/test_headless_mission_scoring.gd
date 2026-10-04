# The headless board SCORES a mission the way the game does (#46 slice 2).
#
# Until this, PlaySession.mission_outcome asked MissionRules.evaluate with no progress and no failure,
# so every board was a rout map out there: a capture mission was won by killing everyone, a clock
# never ran, a protected unit could die unremarked -- and the loader never copied a squad's archetype,
# so a saved Sentry rushed the player in every headless run. The session now owns the game's own
# MissionState and the loader applies the same placement the game does.
#
# Every scenario here is authored in the test and goes through BoardBuilder.apply_scenario, the real
# headless load path, so a field the loader drops is a field these cases lose.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")
const BoardView := preload("res://play/board_view.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), name, fac)


func _scenario() -> ScenarioData:
	var src: Dictionary = BoardBuilder.build(self, "ScoringSrc")
	auto_free(src.root)
	BoardBuilder.paint_rect(src.grid, Rect2i(-2, -2, 14, 8))
	var scenario := ScenarioData.new()
	scenario.tile_data = src.grid.tile_map_data
	return scenario


func _place(scenario: ScenarioData, name: String, fac: Team.Faction, cell: Vector2i) -> ScenarioUnitEntry:
	var entry := ScenarioUnitEntry.new()
	entry.unit_data = _data(name, fac)
	entry.cell = cell
	scenario.unit_entries.append(entry)
	return entry


func _zone(scenario: ScenarioData, name: String, kind: ZoneManager.Kind, rect: Rect2i) -> void:
	var cells: Array[Vector2i] = []
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			cells.append(Vector2i(x, y))
	scenario.zones[name] = {"kind": kind, "cells": cells}


# Loads `scenario` onto a fresh headless board. Returns [session, spawned units in entry order].
func _load(scenario: ScenarioData) -> Array:
	var board: Dictionary = BoardBuilder.build(self, "ScoringDst")
	auto_free(board.root)
	var spawned: Array = await BoardBuilder.apply_scenario(board, scenario)
	return [PlaySession.new(board), spawned]


# Both sides up at an evaluation is what lets a mission end at all; this asks it, and says so if not.
func _contest(sess) -> void:
	assert_str(sess.mission_tag()).override_failure_message(
		"precondition: the mission ended before anything happened").is_equal("")
	assert_bool(sess.mission.contested).override_failure_message(
		"precondition: both sides were up and the mission never latched contested").is_true()


# ==============================================================================
#  Objectives
# ==============================================================================

func test_a_rout_does_not_win_a_capture_mission() -> void:
	var scenario := _scenario()
	_zone(scenario, "Point", ZoneManager.Kind.CAPTURE, Rect2i(4, 4, 1, 1))
	var capture: Array[MissionRules.Objective] = [MissionRules.Objective.CAPTURE]
	scenario.objectives = capture
	_place(scenario, "P1", PLAYER, Vector2i(0, 0))
	_place(scenario, "E1", ENEMY, Vector2i(8, 0))
	var loaded: Array = await _load(scenario)
	var sess = loaded[0]
	var enemy: Unit = loaded[1][1]
	_contest(sess)

	enemy.die()
	assert_bool(MissionRules.has_active_hostiles(sess._board())).override_failure_message(
		"precondition: the enemy is still standing, so nothing here is a rout").is_false()
	assert_str(sess.mission_tag()).override_failure_message(
		"a rout won a CAPTURE mission headlessly -- the game refuses it, the zone is still unclaimed").is_equal("")

	assert_bool(sess.mission.capture("Point")).is_true()
	assert_str(sess.mission_tag()).override_failure_message(
		"claiming the only capture zone did not win the mission").is_equal("VICTORY")


func test_the_overview_shows_the_briefing() -> void:
	var scenario := _scenario()
	_zone(scenario, "Point", ZoneManager.Kind.CAPTURE, Rect2i(4, 4, 1, 1))
	var capture: Array[MissionRules.Objective] = [MissionRules.Objective.CAPTURE]
	var clock: Array[MissionRules.LoseCondition] = [MissionRules.LoseCondition.ROUND_LIMIT]
	scenario.objectives = capture
	scenario.lose_conditions = clock
	scenario.round_limit = 6
	_place(scenario, "P1", PLAYER, Vector2i(0, 0))
	_place(scenario, "E1", ENEMY, Vector2i(8, 0))
	var loaded: Array = await _load(scenario)
	var sess = loaded[0]

	var text: String = BoardView.render_overview(sess)
	var rows: Array[MissionStatusPanel.Row] = MissionStatusPanel.briefing(sess.mission, sess._board())
	var wording: Array[String] = []
	for row in rows:
		wording.append(row.label.text)
		row.label.free()
	assert_int(wording.size()).override_failure_message(
		"precondition: the briefing built no rows for a mission with an objective and a clock").is_greater(0)
	for line in wording:
		assert_str(text).override_failure_message(
			"the overview does not show the briefing row %s\n%s" % [line, text]).contains(line)


# ==============================================================================
#  Lose conditions
# ==============================================================================

func test_the_round_clock_ends_the_mission_through_real_turns() -> void:
	var scenario := _scenario()
	var clock: Array[MissionRules.LoseCondition] = [MissionRules.LoseCondition.ROUND_LIMIT]
	scenario.lose_conditions = clock
	scenario.round_limit = 2
	_place(scenario, "P1", PLAYER, Vector2i(0, 0))
	_place(scenario, "E1", ENEMY, Vector2i(8, 0))
	var loaded: Array = await _load(scenario)
	var sess = loaded[0]
	_contest(sess)

	var last: Dictionary = {}
	var hand_offs := 0
	while sess.mission.rounds_remaining() > 0 and hand_offs < scenario.round_limit * 2 + 4:
		assert_str(sess.mission_tag()).override_failure_message(
			"the mission ended with %d rounds still on the clock" % sess.mission.rounds_remaining()).is_equal("")
		last = sess.end_turn()
		hand_offs += 1

	assert_int(sess.mission.rounds_remaining()).override_failure_message(
		"the clock never ran down across %d hand-offs -- a completed round does not reach the mission" % hand_offs).is_equal(0)
	assert_str(str(last.get("mission", ""))).override_failure_message(
		"the hand-off that ran the clock out did not report the ending: %s" % str(last)).is_equal("DEFEAT")
	assert_int(sess.mission.failed_by).is_equal(MissionRules.LoseCondition.ROUND_LIMIT)


func test_a_loaded_protected_unit_dying_loses_the_mission() -> void:
	var scenario := _scenario()
	var escort: Array[MissionRules.LoseCondition] = [MissionRules.LoseCondition.PROTECTED_UNIT_LOST]
	scenario.lose_conditions = escort
	var vip_entry := _place(scenario, "Vip", PLAYER, Vector2i(0, 0))
	vip_entry.must_survive = true
	_place(scenario, "Guard", PLAYER, Vector2i(0, 2))
	_place(scenario, "E1", ENEMY, Vector2i(8, 0))
	var loaded: Array = await _load(scenario)
	var sess = loaded[0]
	var vip: Unit = loaded[1][0]
	_contest(sess)

	vip.die()
	assert_bool(sess._board().faction_has_active_units(PLAYER)).override_failure_message(
		"precondition: the squad is gone, so this would be a wipe rather than the escort").is_true()
	assert_str(sess.mission_tag()).override_failure_message(
		"the protected unit died and the headless mission went on").is_equal("DEFEAT")
	assert_int(sess.mission.failed_by).is_equal(MissionRules.LoseCondition.PROTECTED_UNIT_LOST)


# ==============================================================================
#  A loaded squad plays its own archetype
# ==============================================================================

# A lone enemy leader, a Sentry over the PATROL zone `zone`, with the computer playing it.
func _sentry_scenario(zone: Rect2i, player_cell: Vector2i) -> ScenarioData:
	var scenario := _scenario()
	_zone(scenario, "Post", ZoneManager.Kind.PATROL, zone)
	var ai: Array[Team.Faction] = [ENEMY]
	scenario.ai_factions = ai
	_place(scenario, "P1", PLAYER, player_cell)
	var sentry := _place(scenario, "E1", ENEMY, Vector2i(8, 0))
	sentry.squad_id = 0
	sentry.is_leader = true
	sentry.squad_archetype = AIArchetype.Type.SENTRY
	sentry.squad_zone = "Post"
	return scenario


func test_a_loaded_sentry_holds_its_post_while_nobody_is_in_its_zone() -> void:
	var loaded: Array = await _load(_sentry_scenario(Rect2i(7, -1, 3, 3), Vector2i(0, 0)))
	var sess = loaded[0]
	var sentry: Unit = loaded[1][1]
	BoardBuilder.arm(loaded[1][0], 4)
	BoardBuilder.arm(sentry, 4)
	var post := sentry.movement.cell

	assert_bool(sess.end_turn().ok).is_true()
	assert_vector(sentry.movement.cell).override_failure_message(
		"a loaded Sentry left its post with nobody in its zone -- it ran as Rushdown").is_equal(post)


func test_a_loaded_sentry_engages_whoever_walks_into_its_zone() -> void:
	var loaded: Array = await _load(_sentry_scenario(Rect2i(3, -1, 7, 3), Vector2i(4, 0)))
	var sess = loaded[0]
	var sentry: Unit = loaded[1][1]
	BoardBuilder.arm(loaded[1][0], 4)
	BoardBuilder.arm(sentry, 4)
	var post := sentry.movement.cell

	assert_bool(sess.end_turn().ok).is_true()
	assert_vector(sentry.movement.cell).override_failure_message(
		"a loaded Sentry stood still with the player inside its zone -- it could not see the zone").is_not_equal(post)
