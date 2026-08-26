# Mission LOSE conditions and the turn clock (#101) — the half of the mission loop that is about
# what the player fails to prevent rather than what they achieve.
#
# What is pinned here, and why each one could go wrong silently:
#
#   * the clock advances ONCE per round, driven through the real end_turn sequence — an off-by-one
#     here is invisible to any test that calls advance_round() itself
#   * defeat lands AT the boundary, not a turn early or late
#   * a squad wiped on the round the clock expires reports SQUAD_LOST, not ROUND_LIMIT — two
#     conditions true in one evaluate, and the banner may only name one
#   * a met objective on the final round WINS: the clock must not steal a win that was earned
#   * ROUND_LIMIT declared with no limit is a BROKEN board, said out loud rather than dropped
#   * the round count survives a save→load round trip through the real writer
#
# Nothing here pins a TUNED value. The urgency threshold and tint are GameKnobs rows; the panel
# cases in tests/ui/test_mission_status_panel.gd read them off the statics rather than as literals.
#
# Uses test_mission_controller.gd's fixture — the real game scene, instanced as "Main" under /root
# (see tests/README.md → Testing the game scene).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

var _main: Node
var game: Node2D
var mc: MissionController


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	mc = game.mission_controller
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()
	await await_idle_frame()   # #114 orphan workaround


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


# Both sides up, so the board is a MISSION and not a dev scratchpad -- `contested` latches and
# evaluate() will actually answer. Every clock case needs this or nothing can ever fire.
func _contest() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.ENEMY, Vector2i(5, 5))
	mc.check()   # latch `contested` while both are standing


func _clock(limit: int) -> void:
	var typed: Array[MissionRules.LoseCondition] = [MissionRules.LoseCondition.ROUND_LIMIT]
	mc.set_lose_conditions(typed, limit)


func _objectives(list: Array) -> void:
	var typed: Array[MissionRules.Objective] = []
	typed.assign(list)
	mc.set_objectives(typed)


# ONE full round of the real cycle. Two factions are on the board, so the cycle wraps every second
# hand-off -- deliberately driven through game.end_turn rather than advance_round(), because the
# thing most likely to be wrong is WHEN the count moves, and calling the counter directly cannot
# see that.
func _play_a_round() -> void:
	await game.end_turn()
	await game.end_turn()


# ==============================================================================
#  The clock advances with the ROUND, once
# ==============================================================================

func test_a_full_cycle_advances_the_clock_exactly_once() -> void:
	_contest()
	_clock(10)
	assert_int(mc.rounds_elapsed()).is_equal(0)

	await game.end_turn()   # PLAYER -> ENEMY: the cycle has not wrapped yet
	assert_int(mc.rounds_elapsed()) \
		.override_failure_message("the clock ticked on a HAND-OFF, not on a round") \
		.is_equal(0)

	await game.end_turn()   # ENEMY -> PLAYER: the cycle wraps here
	assert_int(mc.rounds_elapsed()).is_equal(1)

	await _play_a_round()
	assert_int(mc.rounds_elapsed()).is_equal(2)


func test_the_countdown_is_the_limit_minus_the_rounds_played() -> void:
	_contest()
	_clock(3)
	assert_int(mc.rounds_remaining()).is_equal(3)
	await _play_a_round()
	assert_int(mc.rounds_remaining()).is_equal(2)


# No clock authored = no countdown, whatever the count says. Guards the sentinel: a board that
# never declared a limit must not read as one that declared zero rounds.
func test_no_authored_clock_never_runs_out() -> void:
	_contest()
	await _play_a_round()
	assert_int(mc.rounds_remaining()).is_equal(0)
	assert_bool(mc.is_over()) \
		.override_failure_message("a board with no clock ended on its own") \
		.is_false()


# ==============================================================================
#  Defeat lands AT the boundary
# ==============================================================================

func test_the_mission_survives_the_second_to_last_round_and_is_lost_on_the_last() -> void:
	_contest()
	_clock(2)

	await _play_a_round()
	assert_bool(mc.is_over()) \
		.override_failure_message("lost a round EARLY -- the boundary comparison is off by one") \
		.is_false()

	await _play_a_round()
	assert_bool(mc.is_over()) \
		.override_failure_message("survived past the limit -- the clock never fired") \
		.is_true()
	assert_int(mc.outcome).is_equal(MissionRules.Outcome.DEFEAT)


func test_the_expired_clock_names_itself_on_the_banner() -> void:
	_contest()
	_clock(1)
	await _play_a_round()
	assert_str(MissionRules.defeat_reason(mc.failure_for(game._board()))) \
		.is_equal(MissionRules.defeat_reason(MissionRules.LoseCondition.ROUND_LIMIT))
	assert_str(MissionRules.defeat_reason(MissionRules.LoseCondition.ROUND_LIMIT)).is_not_empty()


# ==============================================================================
#  Two conditions in one evaluate — the banner may only name ONE
# ==============================================================================

# The wipe outranks the clock, matching evaluate's own order: the squad is the more concrete thing
# that happened. Both are true here, so a reason lookup that asked the LIST first would say Time.
func test_a_squad_wiped_on_the_expiry_round_reports_the_squad_not_the_clock() -> void:
	var player := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.ENEMY, Vector2i(5, 5))
	mc.check()
	_clock(1)
	mc._rounds_elapsed = 1   # the clock is expired AND the squad is about to fall, in one check()
	player.die()

	assert_int(mc.failure_for(game._board())) \
		.override_failure_message("the clock outranked the wipe -- the banner would name the wrong thing") \
		.is_equal(MissionRules.LoseCondition.SQUAD_LOST)


# The other side of the same order: a met objective on the FINAL round is a win. The clock is asked
# after every victory path for exactly this, or finishing in time would read as finishing too late.
func test_meeting_the_objective_on_the_last_round_still_wins() -> void:
	_contest()
	_objectives([MissionRules.Objective.ROUT])
	_clock(1)
	mc._rounds_elapsed = 1   # the clock has run out...

	for unit: Unit in game._board().units:
		if unit.get_faction() == Team.Faction.ENEMY:
			unit.die()       # ...and the objective is met in the same breath
	mc.check()

	assert_int(mc.outcome) \
		.override_failure_message("the clock stole a win the player earned on the last round") \
		.is_equal(MissionRules.Outcome.VICTORY)


# ==============================================================================
#  A declared condition with nothing to fire on is a BROKEN board
# ==============================================================================

func test_a_clock_with_no_limit_is_reported_rather_than_dropped() -> void:
	_contest()
	_clock(0)

	assert_array(mc.lose_conditions_missing_setup()) \
		.override_failure_message("a limitless ROUND_LIMIT was silently dropped -- a broken map became a playable one") \
		.contains([MissionRules.LoseCondition.ROUND_LIMIT])

	var blocks: Array[String] = []
	for finding: Dictionary in BoardLint.check(game):
		if finding["severity"] == BoardLint.Severity.BLOCKS:
			blocks.append(finding["text"])
	assert_array(blocks) \
		.override_failure_message("Check board said nothing about a lose condition that cannot work") \
		.is_not_empty()


# ...and it must not END the mission either: unset is broken, not instantly lost.
func test_a_clock_with_no_limit_does_not_fire() -> void:
	_contest()
	_clock(0)
	await _play_a_round()
	assert_bool(mc.is_over()) \
		.override_failure_message("an unset clock lost the mission on its own") \
		.is_false()


# ==============================================================================
#  Persistence — the count is battle state, the limit is authored
# ==============================================================================

func test_the_clock_survives_a_save_and_load_through_the_real_writer() -> void:
	_contest()
	_clock(5)
	await _play_a_round()
	var played: int = mc.rounds_elapsed()
	assert_int(played).is_greater(0)   # non-vacuity: a 0 would round-trip past a broken capture

	var snapshot: ScenarioData = game.scenario_manager.capture_scenario("__clock")
	game.scenario_manager.apply_scenario(snapshot)
	await await_idle_frame()

	assert_int(mc.round_limit).is_equal(5)
	assert_array(mc.lose_conditions).contains([MissionRules.LoseCondition.ROUND_LIMIT])
	assert_int(mc.rounds_elapsed()) \
		.override_failure_message("the round count did not survive the round trip -- a resumed save restarts the clock") \
		.is_equal(played)


# Mission START is a blank slate (#87): the clock resets with the rest of the battle state, or a
# Retry begins already out of time.
func test_reset_clears_the_clock_and_what_it_was_authored_with() -> void:
	_contest()
	_clock(3)
	await _play_a_round()

	mc.reset()

	assert_int(mc.rounds_elapsed()).is_equal(0)
	assert_int(mc.round_limit).is_equal(0)
	assert_array(mc.lose_conditions).is_empty()


# ==============================================================================
#  The pure rule
# ==============================================================================

func test_a_limit_of_zero_means_no_limit_at_any_round_count() -> void:
	assert_bool(MissionRules.round_limit_reached(0, 0)).is_false()
	assert_bool(MissionRules.round_limit_reached(999, 0)).is_false()
	assert_int(MissionRules.rounds_remaining(999, 0)).is_equal(0)


func test_the_countdown_and_the_predicate_agree_at_every_step() -> void:
	# One is derived from the other, so this cannot drift -- which is the property being pinned.
	for played in range(0, 6):
		assert_bool(MissionRules.round_limit_reached(played, 3)) \
			.override_failure_message("round %d: the countdown and the predicate disagree" % played) \
			.is_equal(MissionRules.rounds_remaining(played, 3) <= 0)


# Every AUTHORABLE condition needs banner wording, or a mission ends with a blank card.
func test_every_authorable_condition_has_a_defeat_reason() -> void:
	var wordless: Array[String] = []
	for condition: MissionRules.LoseCondition in MissionRules.AUTHORABLE:
		if MissionRules.defeat_reason(condition).is_empty():
			wordless.append(MissionRules.LoseCondition.keys()[condition])
	assert_array(wordless).override_failure_message(
		"Lose conditions with no banner wording: %s" % ", ".join(wordless)).is_empty()
	# The floor is not authorable but still ends missions, so it needs one too.
	assert_str(MissionRules.defeat_reason(MissionRules.LoseCondition.SQUAD_LOST)).is_not_empty()


# The sentinel is not a reason: an ONGOING mission must not be able to describe its own defeat.
func test_the_sentinel_has_no_wording() -> void:
	assert_str(MissionRules.defeat_reason(MissionRules.LoseCondition.NONE)).is_empty()
