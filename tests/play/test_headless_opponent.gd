# The headless board has an OPPONENT (#665).
#
# Until this shipped, PlaySession.end_turn advanced the faction and did nothing else: no AI, no
# clock tick, nothing. A "playthrough" was played against a stationary board for the whole match,
# and the playtest reports read like real engagements because the counters in them are derived from
# the DRIVER's own attacks during resolution -- Law #2's counter machinery working correctly, and
# never an enemy taking a turn. Two consecutive endturn frames from a logged run, back when endturn
# still redrew the board, were byte-identical across the hand-off.
#
# The cases below are about the WIRE, which is the part that was missing: the decision itself is
# AIController's and is already covered by tests/ai/. What is new is that the headless session
# reaches it at all, and stops when it should.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _board: Dictionary
var _session


func before_test() -> void:
	_board = BoardBuilder.build(self)
	auto_free(_board.root)
	BoardBuilder.paint_rect(_board.grid, Rect2i(-2, -2, 16, 16))
	var p := BoardBuilder.spawn(_board, _data("P1", PLAYER), Vector2i(0, 0))     # -> A
	var e := BoardBuilder.spawn(_board, _data("E1", ENEMY), Vector2i(8, 0))      # -> a, far away
	BoardBuilder.arm(p, 6)
	BoardBuilder.arm(e, 4)
	_session = PlaySession.new(_board)


func _data(name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), name, fac)


func _declare_ai(factions: Array) -> void:
	# ai_factions is the board's own declaration (#150), not a new flag. A fixture board has no
	# ScenarioData, so one is attached here exactly as a loaded mission would carry it.
	var data := ScenarioData.new()
	var list: Array[Team.Faction] = []
	for f in factions:
		list.append(f)
	data.ai_factions = list
	_session.scenario_data = data


# ==============================================================================
#  The wire
# ==============================================================================

func test_a_declared_ai_faction_actually_moves_on_its_turn() -> void:
	_declare_ai([ENEMY])
	var enemy: Unit = _session.unit_by_handle("a")
	var before: Vector2i = enemy.movement.cell

	var res: Dictionary = _session.end_turn()

	assert_bool(res.ok).is_true()
	assert_vector(enemy.movement.cell).override_failure_message(
		("the enemy did not move on its own turn -- this is the exact state #665 found: end_turn "
		+ "advanced the faction and the opponent sat still")).is_not_equal(before)


func test_the_hand_off_comes_back_to_the_player() -> void:
	# The AI turn is run INSIDE end_turn and handed on, so one call returns the driver to its own
	# turn rather than leaving it on the enemy's.
	_declare_ai([ENEMY])
	var res: Dictionary = _session.end_turn()
	assert_str(str(res.faction)).override_failure_message(
		"end_turn left the board on a faction the driver cannot command").is_equal("PLAYER")


func test_what_the_opponent_did_is_reported() -> void:
	# The events are the whole point of running it: an AI turn that mutated the board silently
	# would be the #664 problem with extra steps.
	_declare_ai([ENEMY])
	var res: Dictionary = _session.end_turn()
	assert_array(res.get("ai_events", [])).override_failure_message(
		"the enemy acted and said nothing about it").is_not_empty()


func test_a_faction_the_board_does_not_declare_ai_stays_still() -> void:
	# The inverse, and the guard on every existing fixture: a board that declares nobody -- which
	# is every test board built by BoardBuilder -- must behave exactly as it did before #665.
	_declare_ai([])
	var enemy: Unit = _session.unit_by_handle("a")
	var before: Vector2i = enemy.movement.cell
	_session.end_turn()
	assert_vector(enemy.movement.cell).override_failure_message(
		"an undeclared faction took an AI turn").is_equal(before)


func test_a_board_with_no_scenario_data_at_all_is_unaffected() -> void:
	# BoardBuilder boards carry no ScenarioData. Reading ai_factions off null must not crash.
	_session.scenario_data = null
	var enemy: Unit = _session.unit_by_handle("a")
	var before: Vector2i = enemy.movement.cell
	var res: Dictionary = _session.end_turn()
	assert_bool(res.ok).is_true()
	assert_vector(enemy.movement.cell).is_equal(before)


func test_the_ai_turn_terminates_rather_than_re_offering_a_squad() -> void:
	# #103's lesson, headless: a squad whose archetype queues nothing must still be marked spent,
	# or the faction's turn never ends. Driven by ending several turns in a row -- if a squad were
	# re-offered forever the first call would not return at all.
	_declare_ai([ENEMY])
	for i in 3:
		var res: Dictionary = _session.end_turn()
		assert_bool(res.ok).override_failure_message(
			"turn %d did not complete" % i).is_true()
	# The invariant is that the board stops somewhere the driver can act FROM -- not that it stops
	# on PLAYER. It legitimately stops on the enemy once the mission is over, because end_turn
	# refuses to hand off a finished board (that rule predates #665). Asserting PLAYER outright is
	# what this case did first and it failed on a real VICTORY, which is the content-dependence
	# tests/README #9 warns about: the fixture is one unit against a rushdown and the counter-kill
	# arrives on turn 3.
	var faction := str(_session.status().faction)
	assert_bool(faction == "PLAYER" or _session.mission_tag() != "").override_failure_message(
		("the board stopped on %s with the mission still running -- the hand-off is stuck"
		% faction)).is_true()
