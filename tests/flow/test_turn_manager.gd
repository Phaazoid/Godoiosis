# TurnManager — the N-faction turn cycle (rebuilt 2026-06-24, first covered 2026-08-01).
#
# This had NO dedicated suite: it was exercised only incidentally through the Play API and one
# terrain burnout test, despite being the thing that decides who acts and when, and despite
# carrying two consequences the architecture notes call out explicitly — turn order follows
# ENUM-DECLARATION order (so the enum is append-only for save compat, and a newly added faction
# acts last), and presence IS eligibility (a faction with units on the board takes a turn, full
# stop).
#
# It needs no scene and no board: end_turn() takes the present factions as a parameter, which is
# what makes the whole cycle testable as pure logic. That parameter is also the design — the
# manager never scans the board itself, so a wiped faction drops out for free and a newly spawned
# one enrols at the next hand-off, with no bookkeeping either side.
extends GdUnitTestSuite

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const NEUTRAL := Team.Faction.NEUTRAL
const ALLY := Team.Faction.ALLY
const OTHER := Team.Faction.OTHER

var _tm: TurnManager
var _started: Array[Team.Faction] = []
var _rounds := 0


func before_test() -> void:
	_tm = auto_free(TurnManager.new())
	_started.clear()
	_rounds = 0
	_tm.turn_started.connect(func(faction: Team.Faction) -> void: _started.append(faction))
	_tm.round_completed.connect(func() -> void: _rounds += 1)


func _present(factions: Array) -> Array[Team.Faction]:
	var typed: Array[Team.Faction] = []
	for faction: Team.Faction in factions:
		typed.append(faction)
	return typed


# --- starting state ---

func test_a_new_manager_starts_on_the_player_faction() -> void:
	assert_that(_tm.active_faction()).is_equal(PLAYER)


func test_set_active_faction_works_before_any_cycle_exists() -> void:
	# Scenario load restores whose turn it was, and it lands before anything has computed a cycle.
	_tm.set_active_faction(ALLY)
	assert_that(_tm.active_faction()).is_equal(ALLY)
	assert_array(_tm.turn_order).is_empty()
	assert_array(_started).is_empty()   # a pure state set, not a hand-off


# --- the hand-off ---

func test_end_turn_advances_to_the_next_present_faction() -> void:
	_tm.set_active_faction(PLAYER)
	_tm.end_turn(_present([PLAYER, ENEMY]))
	assert_that(_tm.active_faction()).is_equal(ENEMY)


func test_end_turn_announces_the_faction_that_just_became_active() -> void:
	_tm.set_active_faction(PLAYER)
	_tm.end_turn(_present([PLAYER, ENEMY]))
	assert_array(_started).contains_exactly([ENEMY])


func test_turn_order_follows_the_enum_not_the_callers_order() -> void:
	# The documented trade-off: Team.all_factions() is the single source of truth, so the cycle is
	# enum-declaration order regardless of what order the board hands them over in. That is what
	# makes Team.Faction append-only for save compat — and why a faction added later acts LAST.
	_tm.set_active_faction(PLAYER)
	_tm.end_turn(_present([OTHER, ENEMY, PLAYER]))   # deliberately scrambled
	assert_array(_tm.turn_order).contains_exactly([PLAYER, ENEMY, OTHER])
	assert_that(_tm.active_faction()).is_equal(ENEMY)   # enum-next, not caller-next


func test_the_last_declared_faction_acts_last_in_any_cycle() -> void:
	# The append-only consequence stated directly: whatever sits at the end of the enum sorts to
	# the end of the cycle, so adding a faction never reorders the existing ones.
	_tm.set_active_faction(PLAYER)
	_tm.end_turn(_present([OTHER, PLAYER, NEUTRAL, ALLY, ENEMY]))
	assert_that(_tm.turn_order[_tm.turn_order.size() - 1]).is_equal(OTHER)


# --- the cycle rebuilds itself from what is on the board ---

func test_a_faction_with_no_units_drops_out_of_the_cycle() -> void:
	# Wiped factions are simply absent from `present`, so they cost nothing to remove.
	_tm.set_active_faction(PLAYER)
	_tm.end_turn(_present([PLAYER, ALLY]))   # ENEMY has been wiped
	assert_array(_tm.turn_order).not_contains([ENEMY])
	assert_that(_tm.active_faction()).is_equal(ALLY)


func test_a_newly_present_faction_enrols_at_the_next_handoff() -> void:
	_tm.set_active_faction(PLAYER)
	_tm.end_turn(_present([PLAYER, ENEMY]))          # ALLY not on the board yet
	assert_array(_tm.turn_order).not_contains([ALLY])

	_tm.end_turn(_present([PLAYER, ENEMY, ALLY]))    # reinforcements arrive
	assert_array(_tm.turn_order).contains([ALLY])
	assert_that(_tm.active_faction()).is_equal(ALLY)


func test_turn_order_records_the_cycle_that_was_last_computed() -> void:
	_tm.set_active_faction(PLAYER)
	_tm.end_turn(_present([PLAYER, ENEMY, ALLY]))
	assert_array(_tm.turn_order).contains_exactly([PLAYER, ENEMY, ALLY])
	_tm.end_turn(_present([PLAYER, ENEMY]))
	assert_array(_tm.turn_order).contains_exactly([PLAYER, ENEMY])


# --- rounds ---

func test_advancing_mid_cycle_does_not_complete_a_round() -> void:
	_tm.set_active_faction(PLAYER)
	_tm.end_turn(_present([PLAYER, ENEMY, ALLY]))   # -> ENEMY
	assert_int(_rounds).is_equal(0)


func test_wrapping_past_the_last_faction_completes_a_round() -> void:
	_tm.set_active_faction(ALLY)
	_tm.end_turn(_present([PLAYER, ENEMY, ALLY]))   # ALLY is last -> wraps to PLAYER
	assert_that(_tm.active_faction()).is_equal(PLAYER)
	assert_int(_rounds).is_equal(1)


func test_a_full_lap_completes_exactly_one_round() -> void:
	# The end-to-end shape: three hand-offs across three factions, one round boundary, and every
	# faction announced once.
	var board := _present([PLAYER, ENEMY, ALLY])
	_tm.set_active_faction(PLAYER)
	for _i in range(3):
		_tm.end_turn(board)
	assert_that(_tm.active_faction()).is_equal(PLAYER)
	assert_int(_rounds).is_equal(1)
	assert_array(_started).contains_exactly([ENEMY, ALLY, PLAYER])


func test_a_lone_faction_keeps_the_turn_and_completes_a_round_each_handoff() -> void:
	# A one-faction board (the dev sandbox, or the last survivors) must still tick rounds, since
	# round_completed is what drives per-round board effects like burnout.
	_tm.set_active_faction(PLAYER)
	_tm.end_turn(_present([PLAYER]))
	assert_that(_tm.active_faction()).is_equal(PLAYER)
	assert_int(_rounds).is_equal(1)
	_tm.end_turn(_present([PLAYER]))
	assert_int(_rounds).is_equal(2)


# --- the edges ---

func test_an_empty_board_leaves_the_active_faction_alone_and_announces_nothing() -> void:
	# Nobody left to hand off to. It must not advance, wrap, or fire a round — game.gd's own
	# all-downed guard depends on this being inert rather than looping.
	_tm.set_active_faction(ENEMY)
	_tm.end_turn(_present([]))
	assert_that(_tm.active_faction()).is_equal(ENEMY)
	assert_array(_started).is_empty()
	assert_int(_rounds).is_equal(0)


func test_a_faction_wiped_on_its_own_turn_hands_off_to_the_head_of_the_cycle() -> void:
	# The active faction is absent from the rebuilt cycle, so find() returns -1 and the manager
	# lands on index 0 rather than stalling or erroring. Pinned because it is reachable in play —
	# a faction can lose its last unit during its own resolution pass — and because it takes the
	# round_completed branch on the way, which is not obvious from the arithmetic.
	_tm.set_active_faction(NEUTRAL)
	_tm.end_turn(_present([PLAYER, ENEMY]))
	assert_that(_tm.active_faction()).is_equal(PLAYER)
	assert_int(_rounds).is_equal(1)


func test_presence_is_eligibility_even_for_a_non_combat_faction() -> void:
	# Documented consequence, not an accident: NEUTRAL/OTHER take turns purely by having a unit on
	# the board. If scenery factions ever need to sit out, that is an explicit opt-out to add here
	# — nothing in the cycle distinguishes them today.
	_tm.set_active_faction(PLAYER)
	_tm.end_turn(_present([PLAYER, NEUTRAL]))
	assert_that(_tm.active_faction()).is_equal(NEUTRAL)
