# WHO the squad fights (#117, dev ruling 2026-09-02) -- TWO SYSTEMS forked on one question: is
# anybody attackable this turn?
#
#   somebody is -> the best EXCHANGE wins, and distance is only the tie-break
#   nobody is   -> pursue the NEAREST, exactly as before
#
# The reported case: an enemy adjacent to a spearman that could counter, with a mage one step
# beyond that could not, and it took the spearman -- because target selection had already been
# made by route distance before anything was scored.
#
# Pursuit stays nearest deliberately. It is Rushdown's identity (a rusher that hunts the softest
# target across the board is BALANCED wearing the wrong name), it rewards the player for screening
# a mage behind a frontline, and "whoever is closest" is a rule you can bait and funnel where
# "its best target" is a computation you cannot see.
#
# Fixture conventions follow tests/ai/test_ai_tactics.gd: the Play API's headless board_builder over
# real TestTiles terrain, pattern-less weapons (Reach falls back to Manhattan 1, so adjacency IS
# reach), MOV 4, and an UNARMED unit cannot counter at all (C6).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _build_board(size := Rect2i(0, 0, 10, 10)) -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, size)
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i, armed := true) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data({}, faction), cell)
	if armed:
		unit.equipped_weapon = H.make_weapon()
	return unit


func _context(board: Dictionary) -> BoardContext:
	var units: Array[Unit] = []
	for child in board.units_root.get_children():
		units.append(child as Unit)
	return BoardContext.new(board.grid, units, board.squad_manager)


func _choose(board: Dictionary, leader: Unit, within = null, allowed = null) -> Unit:
	return AITactics.choose_engagement_target(leader, _context(board), board.squad_manager, within, allowed)


# --- The dev's repro ----------------------------------------------------------------------------

# THE reported case. `answerer` is ADJACENT and counters; `harmless` is a step further and cannot
# (unarmed, C6). Both are attackable this turn -- the mage costs one move -- so distance must not
# decide. Mutant: drop the exchange term and the adjacent one wins on hops.
func test_when_both_are_attackable_this_turn_the_one_that_cannot_answer_wins() -> void:
	var board: Dictionary = _build_board()
	var leader: Unit = _spawn(board, PLAYER, Vector2i(2, 2))
	var answerer: Unit = _spawn(board, ENEMY, Vector2i(3, 2))            # adjacent, armed
	var harmless: Unit = _spawn(board, ENEMY, Vector2i(5, 2), false)     # a step away, unarmed

	assert_object(_choose(board, leader)).override_failure_message(
			"the squad went for the nearer target that can hit back").is_same(harmless)
	assert_object(_choose(board, leader)).is_not_same(answerer)


# ...and the other system, untouched. Nobody is reachable this turn (MOV 4, and both sit well
# beyond a firing position), so this is PURSUIT and the nearest is the right answer even though it
# is the one that can answer. Mutant: apply the exchange term unconditionally and it sets off
# across the board after the harmless one.
func test_when_nobody_is_attackable_this_turn_it_still_pursues_the_nearest() -> void:
	var board: Dictionary = _build_board(Rect2i(0, 0, 30, 6))
	var leader: Unit = _spawn(board, PLAYER, Vector2i(0, 2))
	var near: Unit = _spawn(board, ENEMY, Vector2i(12, 2))               # armed, and much closer
	var _far: Unit = _spawn(board, ENEMY, Vector2i(28, 2), false)        # unarmed, far out of reach

	assert_object(_choose(board, leader)).override_failure_message(
			"pursuit stopped going for the nearest -- Rushdown's identity is the ruling").is_same(near)


# Every candidate alike: the order is the whole answer, and it is declared (Law #1).
func test_a_tie_among_reachable_targets_falls_to_route_distance() -> void:
	var board: Dictionary = _build_board()
	var leader: Unit = _spawn(board, PLAYER, Vector2i(2, 2))
	var near: Unit = _spawn(board, ENEMY, Vector2i(3, 2))
	var _far: Unit = _spawn(board, ENEMY, Vector2i(2, 5))

	assert_object(_choose(board, leader)).override_failure_message(
			"identical candidates did not fall to the nearer one").is_same(near)


# --- The Sentry's two leashes -------------------------------------------------------------------

# `allowed` (zone + post) says which cells this sentry may fight FROM, so a target it could only
# attack by stepping outside is not ENGAGEABLE -- it drops out of the exchange ranking rather than
# out of the answer, since an empty engageable set falls through to pursuit as it always did.
#
# `tempting` is unarmed and would win the exchange outright; `reachable` is armed and would lose.
# Inside the leash only `reachable` can be fought, so it must win anyway. Mutant: drop `allowed`
# from the reachable set and the sentry picks the softer target it cannot legally reach.
#
# `tempting` sits at (5,2) rather than further out FOR A REASON, and the first draft got it wrong:
# at (6,2) it was not engageable at all -- its firing cell is beyond this unit's move range -- so
# the leash was never what excluded it and the case passed against a mutant that ignored the leash
# entirely. The lure has to be genuinely reachable for the leash to be the thing under test.
func test_a_sentry_ranks_only_the_targets_its_leash_lets_it_fight() -> void:
	var board: Dictionary = _build_board()
	var leader: Unit = _spawn(board, PLAYER, Vector2i(2, 2))
	var reachable: Unit = _spawn(board, ENEMY, Vector2i(3, 2))          # armed; fought from (2,2)
	var tempting: Unit = _spawn(board, ENEMY, Vector2i(5, 2), false)    # unarmed; fought from (4,2)
	var leash := {}
	for x in range(1, 4):
		for y in range(1, 4):
			leash[Vector2i(x, y)] = true

	assert_object(_choose(board, leader, null, leash)).override_failure_message(
			"the sentry chose a target it can only fight from outside its leash").is_same(reachable)
	assert_object(_choose(board, leader, null, leash)).is_not_same(tempting)


# ...and `within` is the OTHER leash, testing the enemy's OWN cell -- the same question
# _nearest_enemy_matching asks. Without it a sentry engages an enemy standing outside its zone
# because a cell inside the zone can reach it: a lured sentry, which is what the archetype exists
# to refuse. Mutant: apply `within` to the pursuit fallback only.
func test_a_sentry_never_engages_an_enemy_standing_outside_its_zone() -> void:
	var board: Dictionary = _build_board()
	var leader: Unit = _spawn(board, PLAYER, Vector2i(2, 2))
	var _lure: Unit = _spawn(board, ENEMY, Vector2i(4, 2), false)   # reachable, but not in the zone
	var zone := {}
	for y in range(1, 4):
		zone[Vector2i(2, y)] = true   # the enemy's cell (4,2) is deliberately NOT in it

	assert_object(_choose(board, leader, zone, null)).override_failure_message(
			"the sentry was lured out by an enemy standing outside its own zone").is_null()
