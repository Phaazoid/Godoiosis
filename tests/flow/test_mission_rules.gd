# MissionRules — the win/lose predicate (#96 slice 1).
#
# The whole point of extracting this as a pure static is that it can be exercised without a
# game scene, a turn cycle, or a banner: build a board, ask what the mission's state is. The
# in-game MissionController adds exactly two things on top (the ended-latch and the `contested`
# latch) — everything below is the rule itself.
#
# Mirrors test_board_census.gd's fixture shape; MissionRules reads BoardContext's census and
# nothing else.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const ALLY := Team.Faction.ALLY
const NEUTRAL := Team.Faction.NEUTRAL

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

func _board() -> BoardContext:
	var units: Array[Unit] = []
	for squad in _sm.squads:
		for member in squad.get_members():
			if not units.has(member):
				units.append(member)
	return BoardContext.new(_sm.grid, units, _sm)

# Every mission-in-progress board is contested; passing this explicitly keeps each test's
# subject to the one thing it is about.
func _evaluate_contested() -> MissionRules.Outcome:
	return MissionRules.evaluate(_board(), true)

# ---- the ordinary case ----

func test_a_live_board_is_ongoing() -> void:
	H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))

	assert_int(_evaluate_contested()).is_equal(MissionRules.Outcome.ONGOING)

func test_one_downed_player_unit_does_not_end_a_mission_while_another_stands() -> void:
	var downed := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	downed.lifecycle_state = Unit.LifecycleState.DOWNED
	H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))

	assert_int(_evaluate_contested()).is_equal(MissionRules.Outcome.ONGOING)

# ---- victory: the hostiles stop being commandable, however that happened ----

func test_all_enemies_downed_is_a_victory() -> void:
	H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var enemy := H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))
	enemy.lifecycle_state = Unit.LifecycleState.DOWNED

	assert_int(_evaluate_contested()).is_equal(MissionRules.Outcome.VICTORY)

func test_all_enemies_dead_is_a_victory() -> void:
	H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var enemy := H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))
	enemy.lifecycle_state = Unit.LifecycleState.DEAD

	assert_int(_evaluate_contested()).is_equal(MissionRules.Outcome.VICTORY)

# ---- defeat: no player unit left standing ----

func test_all_player_units_downed_is_a_defeat() -> void:
	var player := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	player.lifecycle_state = Unit.LifecycleState.DOWNED
	H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))

	assert_int(_evaluate_contested()).is_equal(MissionRules.Outcome.DEFEAT)

func test_all_player_units_dead_is_a_defeat() -> void:
	var player := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	player.lifecycle_state = Unit.LifecycleState.DEAD
	H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))

	assert_int(_evaluate_contested()).is_equal(MissionRules.Outcome.DEFEAT)

# The documented tie-break: a wipe you don't survive is not a win.
func test_mutual_destruction_is_a_defeat_not_a_victory() -> void:
	var player := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var enemy := H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))
	player.lifecycle_state = Unit.LifecycleState.DEAD
	enemy.lifecycle_state = Unit.LifecycleState.DEAD

	assert_int(_evaluate_contested()).is_equal(MissionRules.Outcome.DEFEAT)

# ---- hostility is Team's call, not MissionRules' ----

func test_a_surviving_neutral_does_not_block_victory() -> void:
	H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	H.spawn_solo(self, _sm, NEUTRAL, Vector2i(2, 0))
	var enemy := H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))
	enemy.lifecycle_state = Unit.LifecycleState.DEAD

	assert_int(_evaluate_contested()).is_equal(MissionRules.Outcome.VICTORY)

func test_an_ally_faction_is_not_a_hostile() -> void:
	H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	H.spawn_solo(self, _sm, ALLY, Vector2i(1, 0))

	assert_bool(MissionRules.has_active_hostiles(_board())).is_false()

func test_an_active_enemy_is_a_hostile() -> void:
	H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))

	assert_bool(MissionRules.has_active_hostiles(_board())).is_true()

func test_a_downed_enemy_is_not_an_active_hostile() -> void:
	var enemy := H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))
	enemy.lifecycle_state = Unit.LifecycleState.DOWNED

	assert_bool(MissionRules.has_active_hostiles(_board())).is_false()

# ---- authored objectives (#96 slices 3-4) ----
#
# The objective's PROGRESS is computed by MissionController (it needs zones and battle-scoped
# capture state); MissionRules only decides what a given verdict means. These pin that meaning,
# which is where the two easy mistakes live: a met objective must win even with enemies alive,
# and a pending one must NOT win just because the board happens to be routed.

func test_a_met_objective_wins_even_with_hostiles_still_standing() -> void:
	H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))

	assert_int(MissionRules.evaluate(_board(), true, MissionRules.Progress.MET)).is_equal(MissionRules.Outcome.VICTORY)

# The rule the dev called on 2026-07-28: a scenario that authors an objective is won by THAT and
# nothing else. Routing the enemy on a capture map does not win it.
func test_a_pending_objective_is_not_won_by_routing_the_enemy() -> void:
	H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var enemy := H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))
	enemy.lifecycle_state = Unit.LifecycleState.DEAD

	assert_int(MissionRules.evaluate(_board(), true, MissionRules.Progress.PENDING)).is_equal(MissionRules.Outcome.ONGOING)

# NONE is not PENDING: a scenario with nothing authored is a plain rout map, which is what every
# board saved before objectives existed still is.
func test_no_authored_objective_falls_back_to_rout() -> void:
	H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var enemy := H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))
	enemy.lifecycle_state = Unit.LifecycleState.DEAD

	assert_int(MissionRules.evaluate(_board(), true, MissionRules.Progress.NONE)).is_equal(MissionRules.Outcome.VICTORY)

func test_defeat_still_beats_a_completed_objective() -> void:
	var player := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))
	player.lifecycle_state = Unit.LifecycleState.DOWNED

	assert_int(MissionRules.evaluate(_board(), true, MissionRules.Progress.MET)).is_equal(MissionRules.Outcome.DEFEAT)

# ---- the `contested` latch: a dev scratch board is not a mission ----
#
# Without it, a board holding only enemies reads "the player has no active units" — which is
# true, and is NOT a defeat, because the player was never there. The board alone cannot tell
# the two apart, so the caller latches it.

func test_an_enemies_only_board_is_not_a_defeat() -> void:
	H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))

	assert_int(MissionRules.evaluate(_board(), false)).is_equal(MissionRules.Outcome.ONGOING)

func test_a_player_only_board_is_not_a_victory() -> void:
	H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))

	assert_int(MissionRules.evaluate(_board(), false)).is_equal(MissionRules.Outcome.ONGOING)

func test_an_empty_board_is_not_an_outcome() -> void:
	assert_int(MissionRules.evaluate(_board(), false)).is_equal(MissionRules.Outcome.ONGOING)

func test_is_contested_is_true_only_when_both_sides_can_act() -> void:
	H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))

	assert_bool(MissionRules.is_contested(_board())).is_true()

func test_is_contested_is_false_when_only_the_player_is_present() -> void:
	H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))

	assert_bool(MissionRules.is_contested(_board())).is_false()

func test_is_contested_is_false_while_the_players_only_unit_is_downed() -> void:
	var player := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	player.lifecycle_state = Unit.LifecycleState.DOWNED
	H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))

	assert_bool(MissionRules.is_contested(_board())).is_false()

# Once latched, the outcome fires even though the board is no longer contested — which is the
# entire reason the latch is the caller's state and not a live read.
func test_a_latched_mission_still_ends_when_the_board_is_no_longer_contested() -> void:
	var player := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	H.spawn_solo(self, _sm, ENEMY, Vector2i(4, 0))
	assert_bool(MissionRules.is_contested(_board())).is_true()

	player.lifecycle_state = Unit.LifecycleState.DOWNED

	assert_bool(MissionRules.is_contested(_board())).is_false()
	assert_int(_evaluate_contested()).is_equal(MissionRules.Outcome.DEFEAT)
