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


func _paint(zone_name: String, kind: ZoneManager.Kind, cells: Array) -> void:
	for cell: Vector2i in cells:
		game.zone_manager.paint_cell(zone_name, kind, cell)


func _defend(cells: Array, zone_name := "The Cargo") -> void:
	_paint(zone_name, ZoneManager.Kind.DEFEND, cells)
	var typed: Array[MissionRules.LoseCondition] = [MissionRules.LoseCondition.POINT_LOST]
	mc.set_lose_conditions(typed, 0)


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


# ==============================================================================
#  The defended point (#571) -- PRESENCE, not capture
# ==============================================================================
#
# The cargo is painted clear of _contest()'s own units: that helper parks an ENEMY on (5,5) to latch
# `contested`, and a zone painted under it would be breached before the case had begun.

func test_a_hostile_standing_on_the_cargo_loses_the_mission() -> void:
	_contest()
	_defend([Vector2i(10, 10), Vector2i(11, 10)])
	assert_bool(mc.is_over()) \
		.override_failure_message("the mission ended before anybody reached the cargo") \
		.is_false()

	_spawn(Team.Faction.ENEMY, Vector2i(11, 10))
	mc.check()
	assert_int(mc.outcome).is_equal(MissionRules.Outcome.DEFEAT)
	# The banner has to name THIS reason -- a defeat reporting the wrong one is exactly what #101's
	# "_failed_by is set beside outcome" rule exists to stop.
	assert_str(MissionRules.defeat_reason(mc._failed_by)) \
		.is_equal(MissionRules.defeat_reason(MissionRules.LoseCondition.POINT_LOST))


# The gate that decides WHOSE presence matters, and the likeliest way to get this rule backwards:
# without it the player loses the mission by standing on the thing they are defending.
func test_the_player_may_stand_on_their_own_cargo() -> void:
	_contest()
	_defend([Vector2i(10, 10)])
	_spawn(Team.Faction.PLAYER, Vector2i(10, 10))
	mc.check()
	assert_bool(mc.is_over()) \
		.override_failure_message("defending the cargo lost the mission") \
		.is_false()


# The declared call (dev, 2026-09-11): "if an enemy makes it that close" is about ARRIVAL, so a body
# on the cargo still counts. Through the domain's own door -- a hand-set lifecycle_state leaves the
# unit at FULL HP, a state the game cannot produce.
func test_a_downed_hostile_on_the_cargo_still_loses_it() -> void:
	_contest()
	_defend([Vector2i(10, 10)])
	var intruder := _spawn(Team.Faction.ENEMY, Vector2i(10, 10))
	intruder.force_down()
	mc.check()
	assert_int(mc.outcome) \
		.override_failure_message("a hostile that reached the cargo and then fell stopped counting") \
		.is_equal(MissionRules.Outcome.DEFEAT)


# The boundary a zone-membership bug walks straight through: one cell out is out.
func test_a_hostile_beside_the_cargo_loses_nothing() -> void:
	_contest()
	_defend([Vector2i(10, 10)])
	_spawn(Team.Faction.ENEMY, Vector2i(11, 10))
	mc.check()
	assert_bool(mc.is_over()) \
		.override_failure_message("standing NEXT to the cargo lost the mission") \
		.is_false()


# objectives_missing_geometry's rule, one list over: declared with nothing painted is a BROKEN board
# that says so out loud, never a clause quietly dropped.
func test_declared_with_no_zone_painted_is_reported_as_broken() -> void:
	var typed: Array[MissionRules.LoseCondition] = [MissionRules.LoseCondition.POINT_LOST]
	mc.set_lose_conditions(typed, 0)
	assert_array(mc.lose_conditions_missing_setup()) \
		.contains([MissionRules.LoseCondition.POINT_LOST])
	# ...and it stops being broken the moment the cargo exists.
	_paint("The Cargo", ZoneManager.Kind.DEFEND, [Vector2i(10, 10)])
	assert_array(mc.lose_conditions_missing_setup()).is_empty()


# A board may paint the zone without declaring the condition -- decorative geometry, exactly as a
# CAPTURE zone can be. That is #96 doctrine: what a mission REQUIRES is the authored list, never
# what happens to be painted.
func test_an_undeclared_zone_is_only_scenery() -> void:
	_contest()
	_paint("The Cargo", ZoneManager.Kind.DEFEND, [Vector2i(10, 10)])
	_spawn(Team.Faction.ENEMY, Vector2i(10, 10))
	mc.check()
	assert_bool(mc.is_over()) \
		.override_failure_message("a painted zone fired a condition the mission never declared") \
		.is_false()


# THE WIRE, end to end (#571). Every case above pins one layer: the archetype suite pins that
# Rushdown aims at the cargo, the cases above pin that a hostile standing on it loses the mission.
# Neither can see the JOIN -- that the move is actually executed and that a pass-end check() runs
# afterwards to notice. A signal with no listener is legal GDScript, and #103 sat in exactly that
# gap for thirteen months.
#
# Driven through the real AIController, so the chain is: archetype plans -> group move queued ->
# OrderExecutor walks it -> OrderExecutor's own check() -> DEFEAT naming POINT_LOST.
func test_the_ai_walking_onto_the_cargo_ends_the_mission() -> void:
	_contest()
	_defend([Vector2i(10, 10)])
	var rusher := _spawn(Team.Faction.ENEMY, Vector2i(8, 10))   # two steps off the cargo
	assert_int(rusher.squad.archetype) \
		.override_failure_message("the fixture's enemy is not a rusher, so nothing walks at the cargo") \
		.is_equal(AIArchetype.Type.FACTION_DEFAULT)
	assert_bool(mc.is_over()).is_false()

	await game.ai_controller.take_faction_turn(Team.Faction.ENEMY)

	assert_int(mc.outcome) \
		.override_failure_message("the AI reached the cargo (or failed to) and the mission did not end") \
		.is_equal(MissionRules.Outcome.DEFEAT)
	assert_str(MissionRules.defeat_reason(mc._failed_by)) \
		.is_equal(MissionRules.defeat_reason(MissionRules.LoseCondition.POINT_LOST))


# ==============================================================================
#  The protected unit (#572) -- a LATCH, because a corpse cannot be asked
# ==============================================================================

func _protect() -> void:
	var typed: Array[MissionRules.LoseCondition] = [MissionRules.LoseCondition.PROTECTED_UNIT_LOST]
	mc.set_lose_conditions(typed, 0)


# The rule, through the domain's own door: every death path in the game reaches Unit.die().
func test_the_protected_unit_dying_loses_the_mission() -> void:
	_contest()
	var vip := _spawn(Team.Faction.PLAYER, Vector2i(10, 10))
	vip.must_survive = true
	_protect()
	assert_bool(mc.is_over()) \
		.override_failure_message("the mission ended before the VIP was touched") \
		.is_false()

	vip.die()
	mc.check()
	assert_int(mc.outcome).is_equal(MissionRules.Outcome.DEFEAT)
	assert_str(MissionRules.defeat_reason(mc._failed_by)) \
		.is_equal(MissionRules.defeat_reason(MissionRules.LoseCondition.PROTECTED_UNIT_LOST))


# Fork B, called DEATH ONLY. A down is recoverable -- RescueAction revives to 1 HP and ACTIVE -- and
# losing on one would make the downed clock a second, invisible timer on the whole mission.
func test_the_protected_unit_going_down_loses_nothing() -> void:
	_contest()
	var vip := _spawn(Team.Faction.PLAYER, Vector2i(10, 10))
	vip.must_survive = true
	_protect()

	vip.force_down()
	mc.check()
	assert_bool(mc.is_over()) \
		.override_failure_message("a DOWN ended the mission -- fork B was called death only") \
		.is_false()
	# ...and the row still names them, because they are still alive to be protected.
	assert_array(mc.protected_units(game._board())).contains([vip])


# An ordinary casualty is an ordinary casualty. Without the flag check the first death of the battle
# would end it, which is the loudest possible way to get this wrong and the easiest to not notice on
# a board where the VIP happens to die first anyway.
func test_an_unflagged_unit_dying_loses_nothing() -> void:
	_contest()
	var vip := _spawn(Team.Faction.PLAYER, Vector2i(10, 10))
	vip.must_survive = true
	var bystander := _spawn(Team.Faction.PLAYER, Vector2i(9, 10))
	_protect()

	bystander.die()
	mc.check()
	assert_bool(mc.is_over()) \
		.override_failure_message("a unit nobody was protecting ended the mission") \
		.is_false()


# Declared with nobody flagged is lose_conditions_missing_setup's rule, one condition over.
func test_declared_with_nobody_flagged_is_reported_as_broken() -> void:
	_contest()
	_protect()
	assert_array(mc.lose_conditions_missing_setup()) \
		.contains([MissionRules.LoseCondition.PROTECTED_UNIT_LOST])

	var vip := _spawn(Team.Faction.PLAYER, Vector2i(10, 10))
	vip.must_survive = true
	assert_array(mc.lose_conditions_missing_setup()).is_empty()


# THE CLAUSE THAT IS NOT DECORATION. Once the VIP is dead there is genuinely nobody flagged on the
# board -- Unit.die() frees the node -- so the naive predicate flips to "nothing to fire on" at the
# exact instant the condition FIRED, and the HUD reports a broken board for the one thing that
# worked.
func test_a_fired_condition_is_not_reported_as_broken() -> void:
	_contest()
	var vip := _spawn(Team.Faction.PLAYER, Vector2i(10, 10))
	vip.must_survive = true
	_protect()

	vip.die()
	mc.check()
	assert_array(mc.lose_conditions_missing_setup()) \
		.override_failure_message("the condition reported itself unset the moment it fired") \
		.is_empty()


# THE WIRE (#572). The latch hangs off game._on_unit_died, and a signal with no listener is legal
# GDScript -- #103 sat in exactly that gap for thirteen months. Driven through take_damage rather
# than die() so the whole real chain runs: damage -> LethalityRules names the rung -> die() ->
# unit_died -> the handler -> the latch.
func test_the_death_signal_actually_reaches_the_latch() -> void:
	_contest()
	var vip := _spawn(Team.Faction.PLAYER, Vector2i(10, 10))
	vip.must_survive = true
	vip.force_down()   # a body takes the permanent path on the next hit
	_protect()

	vip.take_damage(999)
	# The LIFECYCLE, not is_instance_valid: die() queue_frees, which does not land until end of
	# frame, so a validity check here reads TRUE on a unit that is already dead. die() sets the
	# state synchronously, and that is the fact the latch actually hangs off.
	assert_int(vip.lifecycle_state) \
		.override_failure_message("the fixture did not kill the VIP, so nothing is being pinned") \
		.is_equal(Unit.LifecycleState.DEAD)
	mc.check()
	assert_int(mc.outcome) \
		.override_failure_message("the VIP died through the real damage path and nothing noticed") \
		.is_equal(MissionRules.Outcome.DEFEAT)


# reset() is mission START (#87): the latch is battle-scoped, so a board that lost its VIP must not
# come back already lost. It is the one piece of #572 state that could strand a mission unplayable.
func test_the_latch_clears_on_mission_start() -> void:
	_contest()
	var vip := _spawn(Team.Faction.PLAYER, Vector2i(10, 10))
	vip.must_survive = true
	_protect()
	vip.die()
	mc.check()
	assert_bool(mc.is_over()).is_true()

	# Through the REAL door -- clear_board is what calls reset(), and it is the one every exit takes
	# (F2, a board swap, Load Game, Mission Select). Calling reset() alone would leave the old units
	# standing and the re-spawn would land on an occupied cell.
	game.scenario_manager.clear_board()
	_contest()
	_protect()
	var replacement := _spawn(Team.Faction.PLAYER, Vector2i(10, 10))
	replacement.must_survive = true
	mc.check()
	assert_bool(mc.is_over()) \
		.override_failure_message("a restarted mission opened already lost") \
		.is_false()
