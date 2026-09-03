# How a BODY ranks, in both layers that pick a fight (#57 fork 3, rewritten by #720, dev 2026-09-03).
#
# A downed unit used to be an ABSOLUTE last resort: every selector answered about the standing first
# and consulted bodies only if that found nobody. His ruling, from playtest: "It should be the same
# level of prioritization as other attacks, it just loses to other attacks in the head to head."
#
# So there is no fall-through left anywhere -- one ranking per layer, with a body in it:
#
#   PURSUIT (nearest_enemy)          route hops > still standing > straight-line distance
#   ENGAGEMENT (choose_engagement_)  still standing > cannot answer me > route hops
#   ATTACK (the scored pass)         the score, and nothing else -- see test_squad_scoring.gd
#
# What made the old rule safe to delete is that the SCORE was already saying it, more precisely: a
# downed unit clings at 1 HP, so the overkill clamp prices finishing one at exactly +1 and it earns
# no removal. It loses to any real swing without a gate on top. What the gate added was the thirteen
# rounds of Castle Assault in which five attackers revved beside a downed general nobody would walk
# to -- because the layer that decides where to STAND could not see him at all.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const ATTACK_ONLY: Array = [BaseAction.ActionType.ATTACK]


func _build_board(size := Rect2i(0, 0, 8, 3)) -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, size)
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data({}, faction), cell)
	unit.equipped_weapon = H.make_weapon()
	return unit


func _context(board: Dictionary) -> BoardContext:
	var units: Array[Unit] = []
	for child in board.units_root.get_children():
		units.append(child as Unit)
	return BoardContext.new(board.grid, units, board.squad_manager)


# A body, through the DOOR that makes one. Setting `lifecycle_state` by hand is half a down: the real
# thing clings at 1 HP (Unit._go_downed), and the attack cases below are decided by exactly that HP
# through the overkill clamp -- hand-set, a body is priced at its full bar and outranks a standing
# target the ruling says it must lose to. force_down is the dev bypass built for this: DOWNED with no
# Will spend, no maim, no Crisis. Nothing listens to `went_downed` on a board_builder fixture.
func _down(unit: Unit) -> void:
	unit.force_down()


func _aim_count(squad: Squad, cell: Vector2i) -> int:
	var n := 0
	for action in squad.action_queue:
		if action.action_type == BaseAction.ActionType.ATTACK and (action as AttackAction).target_cell == cell:
			n += 1
	return n


func _move_destination(squad: Squad) -> Variant:
	for action in squad.action_queue:
		if action.action_type == BaseAction.ActionType.MOVE:
			return action.get_destination()
	return null


# --- PURSUIT: one walk, ranked -------------------------------------------------------------------

# The flip. This case asserted the opposite until #720, and the fixture is the reported bug in
# miniature: the body is one step away and the standing enemy is five, and the old rule walked past
# the body every turn forever.
func test_nearest_enemy_takes_the_nearer_body_over_a_distant_standing_enemy() -> void:
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var downed_close: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 0))
	_down(downed_close)
	var _active_far: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(5, 0))

	assert_object(AITactics.nearest_enemy(player, _context(board))).override_failure_message(
			"the squad walked past a body at its feet to chase somebody five cells away"
			).is_same(downed_close)


func test_nearest_enemy_takes_a_body_when_it_is_the_only_enemy_left() -> void:
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var downed: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(2, 0))
	_down(downed)

	assert_object(AITactics.nearest_enemy(player, _context(board))).is_same(downed)


# The head-to-head the ruling names, at the one moment it can be observed: equal route, so the
# standing term is the whole answer. DECLARED unpinned before the fix -- the old two-walk order made
# this pass trivially, since standing always won. What it guards is the ORDER of the new ranking, and
# a mutant dropping the standing term reds it (the body is spawned first, so board order takes it).
func test_a_standing_enemy_wins_a_hop_tie_against_a_body() -> void:
	var board: Dictionary = _build_board(Rect2i(0, 0, 8, 8))
	var hunter: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var body: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(2, 0))
	_down(body)
	var standing: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 2))

	assert_object(AITactics.nearest_enemy(hunter, _context(board))).override_failure_message(
			"a body outranked somebody on their feet at the same distance").is_same(standing)


# The leash is unaffected by any of this, and it has to be asserted with a body in the ranking rather
# than assumed: `within` tests the enemy's OWN cell, so the standing enemy outside the zone drops out
# even though it is nearer, and the body inside is the answer. Mutant: drop `within` -> the standing
# one wins on hops.
func test_the_zone_filter_still_applies_now_that_bodies_are_ranked() -> void:
	var board: Dictionary = _build_board()
	var sentry: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var _outside: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 0))   # standing, nearer, out of zone
	var inside: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 0))
	_down(inside)

	var within := {}
	for x in range(2, 5):
		within[Vector2i(x, 0)] = true

	assert_object(AITactics.nearest_enemy(sentry, _context(board), within)).override_failure_message(
			"the sentry was lured out of its zone by an enemy the leash excludes").is_same(inside)


# --- The whole walk: reach the body, then kill it -------------------------------------------------

# THE REPORTED BUG, end to end through the archetype. Five attackers spent thirteen rounds revving
# two cells from a downed general who was holding the gate shut, because the only enemies pursuit
# would look at were archers behind a wall it had no route to -- so every candidate cell scored
# UNREACHABLE, the straight-line fallback answered with the cell the squad was already on, and the
# attack pass then found nothing in reach. Both halves have to work for this to pass: something must
# rank the body, and the approach must then walk to it.
#
# DECLARED: this does not isolate either half. Fixing pursuit alone or engagement alone is enough to
# green it, because on this board they agree -- the unit cases above and in test_target_selection.gd
# are what pin them separately. What this one is for is the walk, which neither of those can see.
func test_a_squad_closes_on_a_body_it_can_reach_instead_of_a_sealed_off_enemy() -> void:
	var board: Dictionary = _build_board(Rect2i(0, 0, 7, 3))
	for y in range(0, 3):
		board.grid.erase_cell(Vector2i(2, y))          # a wall with no way round it
	var rusher: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1))
	var body: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(5, 1))
	_down(body)
	var _sealed: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 1))   # standing, unreachable forever

	RushdownArchetype.take_squad_turn(rusher.squad, _context(board), board.squad_manager)

	assert_that(_move_destination(rusher.squad)).override_failure_message(
			"the squad never stepped to the body -- it pursued the enemy behind the wall"
			).is_equal(Vector2i(4, 1))
	assert_int(_aim_count(rusher.squad, body.movement.cell)).override_failure_message(
			"the squad reached the body and revved beside it").is_equal(1)


# --- ATTACK: the score alone, and it still prefers the standing ----------------------------------

func test_attack_prefers_active_target_in_reach() -> void:
	# AI attacks aim at a CELL (target null; victims derive at resolve time, #15) -- assert on
	# target_cell. The downed unit sits closer in board order AND in distance, and since #720 nothing
	# stops it being aimed at; what keeps the standing enemy the answer is the arithmetic. A body at
	# 1 HP is worth +1 damage, a healthy enemy the weapon's full 3.
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var downed_adjacent: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 0))
	_down(downed_adjacent)
	var active_in_reach: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 1))   # pattern-less: Manhattan 1

	assert_bool(AITactics.queue_main_action(player, _context(board), board.squad_manager, ATTACK_ONLY)).is_true()
	var queued: AttackAction = player.squad.action_queue[0]
	assert_that(queued.target_cell).is_equal(active_in_reach.movement.cell)

func test_attack_finishes_downed_when_nothing_active_in_reach() -> void:
	# Fork 3's surviving half: finishing a body off is intended, and it is what the +1 buys when
	# there is nothing better to spend the action on.
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var downed_adjacent: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 0))
	_down(downed_adjacent)

	assert_bool(AITactics.queue_main_action(player, _context(board), board.squad_manager, ATTACK_ONLY)).is_true()
	var queued: AttackAction = player.squad.action_queue[0]
	assert_that(queued.target_cell).is_equal(downed_adjacent.movement.cell)

func test_attack_declines_when_only_downed_out_of_reach() -> void:
	var board: Dictionary = _build_board()
	var player: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(0, 0))
	var downed_far: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(5, 0))
	_down(downed_far)

	assert_bool(AITactics.queue_main_action(player, _context(board), board.squad_manager, ATTACK_ONLY)).is_false()
	assert_array(player.squad.action_queue).is_empty()
