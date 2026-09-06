# Joint attack selection (#117): a candidate is scored by what it adds to the SQUAD'S PLAN, and the
# squad's attacks are chosen together rather than member by member.
#
# What that buys, one case each below: focus fire (nobody re-spends on a body the plan already
# downed), finishing (the second member secures a down the first started), opening a combo (a
# damageless set-up is priced by the swing behind it), counter awareness (a candidate handing the
# enemy a lethal reply is refused), and the board being left as a REAL resolve left it.
#
# Fixture conventions follow tests/ai/test_ai_tactics.gd: the Play API's headless board_builder over
# real TestTiles terrain, pattern-less weapons so Reach falls back to Manhattan 1 (adjacency IS
# reach), baseline MHP 10 and weapon power 3.
#
# THE GEOMETRY, used by most cases below. With Manhattan-1 reach, two members share exactly two
# common neighbours when they sit diagonally -- which is the smallest board on which both members
# can reach both enemies, i.e. the smallest board where "who hits whom" is a real choice:
#
#   x     0   1
#   y=0   A   M1
#   y=1   M2  B
#
# A(0,0) and B(1,1) are each orthogonally adjacent to both M1(1,0) and M2(0,1).
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

const M1_CELL := Vector2i(1, 0)
const M2_CELL := Vector2i(0, 1)
const A_CELL := Vector2i(0, 0)
const B_CELL := Vector2i(1, 1)


func _build_board(size := Rect2i(0, 0, 6, 6)) -> Dictionary:
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


# A body, through the DOOR that makes one. Setting `lifecycle_state` by hand is half a down: the
# real thing clings at 1 HP (Unit._go_downed), and the scoring pass reads that HP through the
# overkill clamp -- so a hand-set body is priced at its FULL bar and every "a body loses head to
# head" case here would be measuring a state the game cannot produce. force_down is the dev bypass
# built for exactly this: DOWNED with no Will spend, no maim and no Crisis. Nothing listens to
# `went_downed` on a board_builder fixture (the game wires it at game.spawn_unit).
func _down(unit: Unit) -> void:
	unit.force_down()


# A two-member PLAYER squad on the diagonal, M1 as leader. Returns [M1, M2] in member order.
func _pair(board: Dictionary) -> Array[Unit]:
	var m1: Unit = _spawn(board, PLAYER, M1_CELL)
	var m2: Unit = _spawn(board, PLAYER, M2_CELL)
	board.squad_manager.join_squad(m2, m1.squad)
	var members: Array[Unit] = [m1, m2]
	return members


# Everything the queue says about who is attacking whom, in queue order.
func _attack_aims(squad: Squad) -> Array[String]:
	var aims: Array[String] = []
	for action in squad.action_queue:
		if action.action_type == BaseAction.ActionType.ATTACK:
			aims.append("%s->%s" % [action.actor.get_unit_name(), str((action as AttackAction).target_cell)])
	return aims


# The queued attacks themselves, in queue order -- for the cases that assert on WHO acted, which a
# name cannot carry (every fixture unit is called "Unit").
func _attacks_in_order(squad: Squad) -> Array[AttackAction]:
	var out: Array[AttackAction] = []
	for action in squad.action_queue:
		if action.action_type == BaseAction.ActionType.ATTACK:
			out.append(action as AttackAction)
	return out


# A pattern-less weapon that SHOVES, so a resolve has a projection to publish and the case below
# can tell a hypothetical's board from the real one.
func _shoving_weapon() -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 3
	template.main_attack.knockback = 1
	return WeaponInstance.make(template)


func _damage_to(plan: ResolvedPlan, victim: Unit) -> int:
	var total := 0
	for a in plan.attacks:
		if a.target == victim and a.resolved != null:
			total += a.resolved.damage
	return total


func _aim_count(squad: Squad, cell: Vector2i) -> int:
	var n := 0
	for action in squad.action_queue:
		if action.action_type == BaseAction.ActionType.ATTACK and (action as AttackAction).target_cell == cell:
			n += 1
	return n


# --- Focus fire: the plan is visible, so nobody re-spends on a body it already downed -----------

# The double-spend #117 names, and the one the shipped Castle Assault board reproduces: two members
# aiming the same target while a second enemy goes untouched. Scored independently, A is the better
# target for BOTH (a predicted down outranks damage), and the second member cannot see that the
# first already took it.
func test_the_second_member_does_not_spend_its_action_on_a_target_the_first_already_downs() -> void:
	var board: Dictionary = _build_board()
	var pair := _pair(board)
	var a: Unit = _spawn(board, ENEMY, A_CELL)
	a.set_current_hp(3)                      # one hit downs A
	var _b: Unit = _spawn(board, ENEMY, B_CELL)   # untouched, at full 10

	AITactics.queue_main_actions_for_squad(pair[0].squad, _context(board), board.squad_manager)

	assert_int(_aim_count(pair[0].squad, A_CELL)).override_failure_message(
			"both members spent their action on A: %s" % str(_attack_aims(pair[0].squad))).is_equal(1)
	assert_int(_aim_count(pair[0].squad, B_CELL)).override_failure_message(
			"nobody engaged the second enemy: %s" % str(_attack_aims(pair[0].squad))).is_equal(1)


# The same rule read the other way: a member that can SECURE a down its squadmate started prefers
# that to fresh damage elsewhere. One swing does not fell a healthy unit here, so the finish is
# visible only against the plan.
#
# The geometry is what gives the case teeth. C is reachable by M2 ALONE, so M1's swing is forced
# onto A, and C is spawned FIRST so board order points at it -- scored independently, M2 rates C
# and A identically (both untouched, as far as it can see) and takes C on the tie.
func test_the_second_member_secures_the_down_the_first_started() -> void:
	var board: Dictionary = _build_board()
	var pair := _pair(board)
	var c: Unit = _spawn(board, ENEMY, Vector2i(0, 2))   # M2's neighbour only; FIRST in board order
	var _a: Unit = _spawn(board, ENEMY, A_CELL)          # reachable by both, at full HP

	AITactics.queue_main_actions_for_squad(pair[0].squad, _context(board), board.squad_manager)

	assert_int(_aim_count(pair[0].squad, A_CELL)).override_failure_message(
			"the second member took a fresh target instead of finishing A: %s" % str(_attack_aims(pair[0].squad))).is_equal(2)
	assert_int(_aim_count(pair[0].squad, c.movement.cell)).is_equal(0)


# Overkill is the other half of focus fire, and the half a per-hit removal count cannot express:
# the ladder answers KILLED for ANY damaging hit on a downed body, so counting removals per hit
# re-pays the second member for finishing what the first downed.
#
# THE PREFERENCE is pinned above, by the case that gives the second member somewhere else to go --
# the clamp is what makes a fresh enemy outrank a corpse. What THIS case pins is the declared
# consequence of dropping the bar (#711): with nowhere else to go, the wasted swing is taken. It
# used to assert the opposite, and that was the bar speaking rather than the clamp.
func test_a_body_is_still_swung_at_when_it_is_the_only_thing_in_reach() -> void:
	var board: Dictionary = _build_board()
	var pair := _pair(board)
	var a: Unit = _spawn(board, ENEMY, A_CELL)
	a.set_current_hp(3)

	AITactics.queue_main_actions_for_squad(pair[0].squad, _context(board), board.squad_manager)

	assert_int(_aim_count(pair[0].squad, A_CELL)).override_failure_message(
			"a member idled with a reachable target: %s" % str(_attack_aims(pair[0].squad))).is_equal(2)


# --- The dev's counter ruling (2026-09-02) ------------------------------------------------------

# A reaction's DAMAGE is not scored, only its removals. Priced at par it cancels exactly -- two
# units carrying the same weapon trade 3 for 3 -- so every even exchange scores (0,0), which is
# below the bar to queue at all, and a squad facing mirror-statted enemies would decline every
# attack and reload instead. This is the case that ruling exists for.
func test_an_even_trade_is_still_worth_taking() -> void:
	var board: Dictionary = _build_board()
	var attacker: Unit = _spawn(board, PLAYER, M1_CELL)
	var _foe: Unit = _spawn(board, ENEMY, A_CELL)   # same weapon, same stats: 3 for 3

	AITactics.queue_main_actions_for_squad(attacker.squad, _context(board), board.squad_manager)

	assert_int(_aim_count(attacker.squad, A_CELL)).override_failure_message(
			"the squad refused an even trade and did nothing").is_equal(1)


# ...but a reaction that FELLS one of ours is a real loss and does count. Both enemies take the
# same damage; only X can answer, and its counter downs the attacker outright. X is spawned FIRST
# so board order would choose it if counters were invisible.
func test_a_target_whose_counter_would_fell_the_attacker_is_avoided() -> void:
	var board: Dictionary = _build_board()
	var attacker: Unit = _spawn(board, PLAYER, M1_CELL)
	attacker.set_current_hp(3)                      # a 3-damage counter takes it off its feet
	var x: Unit = _spawn(board, ENEMY, A_CELL)      # armed -> counters
	var y: Unit = _spawn(board, ENEMY, Vector2i(2, 0), false)   # weaponless -> C6, cannot counter

	AITactics.queue_main_actions_for_squad(attacker.squad, _context(board), board.squad_manager)

	assert_int(_aim_count(attacker.squad, y.movement.cell)).override_failure_message(
			"the AI walked into the lethal counter from %s instead of hitting the harmless %s" % [
				x.get_unit_name(), y.get_unit_name()]).is_equal(1)
	assert_int(_aim_count(attacker.squad, x.movement.cell)).is_equal(0)


# --- Opening a combo: the lookahead (dev fork, pairs in v1, 2026-09-02) -------------------------

# A pattern-less weapon whose main carries `element` -- and, optionally, deals no damage at all,
# which is what a pure set-up is (Splash is authored exactly this way).
func _elemental_weapon(element: Elemental.Element, power: int, no_damage := false) -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = power
	template.main_attack.elemental_damage_type = element
	template.main_attack.deals_no_damage = no_damage
	return WeaponInstance.make(template)


# THE CASE THE OLD CHOOSER COULD NOT REACH AT ALL. A soak deals no damage, so on its own it scores
# (0,0) and a candidate must BEAT (0,0) to queue -- the AI was structurally unable to author the
# first half of a combo, however good the second half was. Water sets WET; SHOCK into WET is
# Electrocuted, +5 (Resources/Reactions/{water_sets_wet,shock_wet_electrocute}.tres).
func test_a_damageless_soak_is_queued_first_because_the_shock_behind_it_electrocutes() -> void:
	var board: Dictionary = _build_board()
	var pair := _pair(board)
	pair[0].equipped_weapon = _elemental_weapon(Elemental.Element.WATER, 0, true)
	pair[1].equipped_weapon = _elemental_weapon(Elemental.Element.SHOCK, 3)
	var foe: Unit = _spawn(board, ENEMY, A_CELL, false)   # unarmed: keep the reaction ledger out of it
	var context: BoardContext = _context(board)

	# What the shock does DRY, measured on this board rather than typed in -- the electrocute bonus
	# and the fixture's own scaling are both authored numbers this suite must not pin.
	var dry_only: Array[BaseAction] = [H.stamped_attack(pair[1], foe)]
	var dry := _damage_to(board.squad_manager.resolve_hypothetical(pair[0].squad, dry_only, context), foe)
	board.squad_manager.resolve_plan(pair[0].squad, context)

	AITactics.queue_main_actions_for_squad(pair[0].squad, context, board.squad_manager)

	var ordered := _attacks_in_order(pair[0].squad)
	assert_int(ordered.size()).override_failure_message(
			"expected both halves of the combo, got %s" % str(_attack_aims(pair[0].squad))).is_equal(2)
	assert_object(ordered[0].actor).override_failure_message(
			"the soak was not queued first, so the shock fired dry").is_same(pair[0])

	var wet := _damage_to(board.squad_manager.resolve_plan(pair[0].squad, context), foe)
	assert_int(wet).override_failure_message(
			"the shock landed dry (%d) -- the soak did not reach it" % wet).is_greater(dry)


# --- Law #1: the tie-break is declared, not incidental -------------------------------------------

# Every candidate scores alike here, so the ORDER is the whole answer, and it has to be declared
# rather than incidental (Law #1). Asserted on the actor OBJECT, never its name: fixture units are
# all called "Unit", so a string compare would pass whichever member went first.
func test_a_tie_keeps_member_order_then_board_order() -> void:
	var board: Dictionary = _build_board()
	var pair := _pair(board)
	var a: Unit = _spawn(board, ENEMY, A_CELL)    # identical, full HP, and FIRST in board order
	var _b: Unit = _spawn(board, ENEMY, B_CELL)

	AITactics.queue_main_actions_for_squad(pair[0].squad, _context(board), board.squad_manager)

	var ordered := _attacks_in_order(pair[0].squad)
	assert_int(ordered.size()).is_equal(2)
	assert_object(ordered[0].actor).override_failure_message(
			"the first order was not the first member's").is_same(pair[0])
	assert_that(ordered[0].target_cell).override_failure_message(
			"the tie did not fall to the first enemy in board order").is_equal(a.movement.cell)


# --- The board a scoring pass leaves behind ------------------------------------------------------

# _resolve_actions is NOT pure: it publishes projections onto units and stamps the plan cache. The
# cache half is structural -- only resolve_plan, whose array IS the real queue, may write it, or
# the queue gate's rescue clause could be handed a hypothetical as "the already-queued prefix".
func test_a_hypothetical_resolve_never_becomes_the_squads_stored_plan() -> void:
	var board: Dictionary = _build_board()
	var attacker: Unit = _spawn(board, PLAYER, M1_CELL)
	var foe: Unit = _spawn(board, ENEMY, A_CELL)
	var context: BoardContext = _context(board)

	var real: ResolvedPlan = board.squad_manager.resolve_plan(attacker.squad, context)
	var candidate: Array[BaseAction] = [H.stamped_attack(attacker, foe)]
	board.squad_manager.resolve_hypothetical(attacker.squad, candidate, context)

	assert_object(board.squad_manager.resolved_plan_for(attacker.squad)).override_failure_message(
			"a hypothetical resolve overwrote the squad's stored plan").is_same(real)


# The projections half: a scoring pass runs many hypotheticals and the LAST one is not the queue,
# so the pass has to finish on a real resolve or the board is left dressed for a plan nobody gave.
#
# A SHOVING attack must still be queueable, and it very nearly was not. queue_action's whiff gate
# (SquadPlanValidator.aim_finds_a_target) reads PUBLISHED KNOCKBACK, and it is
# correct there only because that knockback belongs to the already-queued aims. A scoring pass
# publishes a candidate's shove too -- so the gate went looking for the target on the cell the
# scoring resolve had thrown it to, found nobody, and refused the winner as a whiff. Every attack
# that knocks its target back was unqueueable by the joint pass, and no fixture with a plain weapon
# could see it. The pass now restores the real plan before it queues.
func test_a_shoving_attack_is_still_queued() -> void:
	var board: Dictionary = _build_board()
	var attacker: Unit = _spawn(board, PLAYER, Vector2i(0, 0))
	attacker.equipped_weapon = _shoving_weapon()
	var foe: Unit = _spawn(board, ENEMY, Vector2i(1, 0))

	AITactics.queue_main_actions_for_squad(attacker.squad, _context(board), board.squad_manager)

	assert_int(_aim_count(attacker.squad, foe.movement.cell)).override_failure_message(
			"the shove the scoring pass published made its own winner look like a whiff").is_equal(1)


# The projections half: a scoring pass runs many hypotheticals and the LAST one is not the queue,
# so the pass has to finish on a real resolve or the board is left dressed for a plan nobody gave.
#
# The LOSER has to publish something DIFFERENT from the winner, or the assertion cannot fail
# whatever the code does. One shoving attacker, two reachable enemies: the frail one is a removal
# and wins, the tough one is only damage and loses -- and each candidate's resolve shoves its own
# target a different way, so a leftover projection is visible as the tough enemy standing where
# nothing in the queued plan ever put it.
#
# DECLARED: the TRAILING restore is still unpinned, and this fixture cannot pin it either. With no
# bar (#711) the joint loop always queues whatever it scored, so the round that finally breaks it
# opens with a REAL resolve and no hypothetical is ever the last word. What is asserted here is the
# invariant itself -- a refactor dropping that top-of-loop resolve reds this case.
func test_scoring_leaves_the_board_where_a_real_resolve_would() -> void:
	var board: Dictionary = _build_board()
	var attacker: Unit = _spawn(board, PLAYER, Vector2i(0, 0))
	attacker.equipped_weapon = _shoving_weapon()
	var frail: Unit = _spawn(board, ENEMY, Vector2i(1, 0))
	frail.set_current_hp(3)                                 # one hit fells it: a removal, so it wins
	var tough: Unit = _spawn(board, ENEMY, Vector2i(0, 1))  # damage only, so its candidate LOSES
	var context: BoardContext = _context(board)

	AITactics.queue_main_actions_for_squad(attacker.squad, context, board.squad_manager)
	assert_int(_aim_count(attacker.squad, frail.movement.cell)).override_failure_message(
			"the fixture no longer picks the frail target, so no losing candidate was scored last"
			).is_equal(1)
	assert_int(_aim_count(attacker.squad, tough.movement.cell)).is_equal(0)

	var after_pass := {}
	for unit in context.units:
		after_pass[unit] = unit.get_projected_destination()
	board.squad_manager.resolve_plan(attacker.squad, context)
	for unit in context.units:
		assert_that(after_pass[unit]).override_failure_message(
				"a unit sat at a DECLINED candidate's projection after the pass") \
			.is_equal(unit.get_projected_destination())


# --- The one comparison a body wins (dev ruling, 2026-09-03) -------------------------------------

# THE CORNER WHERE TWO RULINGS MEET, and the dev settled it with the score. The rescue window says
# felling someone standing is worth more than finishing a corpse (2026-09-02); #720 says a body is an
# ordinary target that loses head to head. Here the standing target's counter FELLS the attacker, so
# the two rulings point opposite ways -- and the arithmetic decides: a free finish scores (0,+1,0)
# against a suicidal swing at (-1,3,-3), and a removal on our own side is the first term.
#
# This SUPERSEDES the assertion this case carried until #720, which was that the body is never
# touched while anyone stands in reach. That was #57's precedence as a gate; what is left is the
# ranking, and a swing that trades our unit for three chip damage is the one thing it loses to.
func test_a_free_finish_outranks_a_swing_that_would_fell_the_attacker() -> void:
	var board: Dictionary = _build_board()
	var attacker: Unit = _spawn(board, PLAYER, Vector2i(0, 0))
	attacker.set_current_hp(3)                              # the counter takes it off its feet
	var body: Unit = _spawn(board, ENEMY, Vector2i(1, 0))
	_down(body)
	var armed: Unit = _spawn(board, ENEMY, Vector2i(0, 1))  # standing, and its answer is lethal

	AITactics.queue_main_actions_for_squad(attacker.squad, _context(board), board.squad_manager)

	assert_int(_aim_count(attacker.squad, body.movement.cell)).override_failure_message(
			"the AI threw itself at a standing target rather than take the finish in front of it"
			).is_equal(1)
	assert_int(_aim_count(attacker.squad, armed.movement.cell)).override_failure_message(
			"the AI took the swing that gets it killed for three chip damage").is_equal(0)


# ...and the plan-vs-live half, which is why the candidate filter reads the PLAN. Planning does not
# execute, so a unit a squadmate fells THIS round is still is_active() on the board -- and the score
# has to price M2's options against what the squad is really doing, not against a board where A is
# still healthy. M1 can reach only A; M2 can reach A and the old body, so once M1 has downed A the
# body is worth more than a second swing at someone already down (+1 against the clamp's nothing).
#
# The wording this comment carried until #720 described a gate rather than a score -- reading A live
# "wedged pass 2 shut". There are no passes now; what would break is the ranking, in the same
# direction and for the same reason.
func test_a_squadmate_felled_this_round_is_not_a_standing_target_any_more() -> void:
	var board: Dictionary = _build_board()
	var m1: Unit = _spawn(board, PLAYER, Vector2i(2, 0))    # reaches A only
	var m2: Unit = _spawn(board, PLAYER, Vector2i(1, 1))    # reaches A and the body
	board.squad_manager.join_squad(m2, m1.squad)
	var a: Unit = _spawn(board, ENEMY, Vector2i(1, 0), false)
	a.set_current_hp(3)                                     # one hit fells it
	var body: Unit = _spawn(board, ENEMY, Vector2i(1, 2), false)
	_down(body)

	AITactics.queue_main_actions_for_squad(m1.squad, _context(board), board.squad_manager)

	assert_int(_aim_count(m1.squad, a.movement.cell)).override_failure_message(
			"the squad did not fell A first: %s" % str(_attack_aims(m1.squad))).is_equal(1)
	assert_int(_aim_count(m1.squad, body.movement.cell)).override_failure_message(
			"the second member idled beside the body -- it read A as still standing: %s" % str(_attack_aims(m1.squad))).is_equal(1)


# --- The exchange tie-break (dev, 2026-09-02, from playtest) -------------------------------------

# "When all else is even, they should go for optimal exchanges." Both targets take the same damage
# and neither falls, so the score's two higher terms tie exactly and z is the whole answer: prefer
# the one that cannot hit back. The armed one is spawned FIRST so board order would take it.
#
# This is also what stops the ATTACK pick undoing the TARGET pick: choose_engagement_target walks
# the squad to the harmless enemy, and if the dangerous one is still in reach from the settled
# cell, a scorer without z ties on damage and re-selects exactly what layer 1 avoided.
func test_between_equal_targets_the_one_that_cannot_answer_is_chosen() -> void:
	var board: Dictionary = _build_board()
	var attacker: Unit = _spawn(board, PLAYER, M1_CELL)
	var answerer: Unit = _spawn(board, ENEMY, A_CELL)            # armed: counters for real damage
	var harmless: Unit = _spawn(board, ENEMY, Vector2i(2, 0), false)   # unarmed: C6, no counter

	AITactics.queue_main_actions_for_squad(attacker.squad, _context(board), board.squad_manager)

	assert_int(_aim_count(attacker.squad, harmless.movement.cell)).override_failure_message(
			"the attack pick took the target that hits back, on an otherwise even trade").is_equal(1)
	assert_int(_aim_count(attacker.squad, answerer.movement.cell)).is_equal(0)


# --- No floor: the score ORDERS, it never gates (#711, dev 2026-09-02) ---------------------------

# "The AI should ALWAYS attack if there is an option to, and if all the options are weighed bad, it
# has to pick its least bad option." The attacker cannot survive the reply, so its only candidate
# scores a NEGATIVE removal -- which under the old bar was refused, leaving it to idle in reach.
func test_the_least_bad_option_is_taken_when_every_trade_loses() -> void:
	var board: Dictionary = _build_board()
	var attacker: Unit = _spawn(board, PLAYER, M1_CELL)
	attacker.set_current_hp(3)                            # the counter takes it off its feet
	var armed: Unit = _spawn(board, ENEMY, A_CELL)        # and its answer is lethal

	AITactics.queue_main_actions_for_squad(attacker.squad, _context(board), board.squad_manager)

	assert_int(_aim_count(attacker.squad, armed.movement.cell)).override_failure_message(
			"the AI idled in reach rather than take a losing trade -- the scoring bar is back"
			).is_equal(1)


# THE PLAYTEST SYMPTOM #117 filed as "the enemy won't attack my tank". C1/C4 make a defending party
# react ONCE per plan, to the FIRST attack against it, and every member of that party answers -- so
# the whole bill lands on whichever candidate is scored first and nothing is left to charge it
# against. Under the bar no candidate netted positive and the squad queued NOTHING, however plainly
# the follow-ups won; the second attack is free, because the party has already reacted.
func test_a_squad_opens_on_a_counter_capable_party_instead_of_freezing() -> void:
	var board: Dictionary = _build_board()
	var pair := _pair(board)
	pair[0].set_current_hp(3)
	pair[1].set_current_hp(3)
	var a: Unit = _spawn(board, ENEMY, A_CELL)
	var b: Unit = _spawn(board, ENEMY, B_CELL)
	board.squad_manager.join_squad(b, a.squad)            # one party, so C1/C4 gate them together

	AITactics.queue_main_actions_for_squad(pair[0].squad, _context(board), board.squad_manager)

	assert_int(_attacks_in_order(pair[0].squad).size()).override_failure_message(
			"the squad froze: the opener's counter bill still vetoes the first attack"
			).is_greater(0)


# The lookahead's floor was Vector3i.ZERO and the caller REPLACED the solo score with it, which was
# invisible while the bar refused zero anyway. With no bar it LAUNDERS a negative into a zero: the
# damageless soak below is really (-1, 0, ...) and comes back (0,0,0), which then outranks an honest
# plain swing at (-1, 8, ...) on the first term. The unit dies either way; the difference is whether
# it deals damage on the way out. Nothing follows the soak here -- a set-up with no follow-up is
# worth what it does alone, which is nothing.
func test_a_setup_with_no_follow_up_does_not_outrank_a_better_plain_swing() -> void:
	var board: Dictionary = _build_board()
	var attacker: Unit = _spawn(board, PLAYER, M1_CELL)
	attacker.equipped_weapon = _elemental_weapon(Elemental.Element.WATER, 0, true)
	var plain: WeaponAttackData = WeaponAttackData.new()
	plain.power = 3                                       # 8 damage: real, and short of felling a 10 HP foe
	var extras: Array[WeaponAttackData] = [plain]
	attacker.equipped_weapon.template.extra_attacks = extras
	attacker.set_current_hp(3)                            # so BOTH candidates score a negative removal
	var _armed: Unit = _spawn(board, ENEMY, A_CELL)

	AITactics.queue_main_actions_for_squad(attacker.squad, _context(board), board.squad_manager)

	var ordered := _attacks_in_order(attacker.squad)
	assert_int(ordered.size()).override_failure_message("no attack was queued at all").is_equal(1)
	if ordered.is_empty():
		return
	assert_object(ordered[0].fired_attack).override_failure_message(
			"the soak won: a losing set-up was laundered to (0,0,0) and outranked a real swing"
			).is_same(plain)


# --- A body in the blast is a BONUS, never a reason to aim elsewhere (#716, dev 2026-09-03) ------

# Reported from play: a general with an AoE had two options that both hit an upright enemy, and only
# one of them ALSO caught a downed one. It took the option that hit nobody extra -- "playing for the
# wrong team". The score used to skip damage on an already-downed victim during pass 1, so both
# candidates priced identically and the tie fell to candidate order.
#
# That skip was a SECOND spelling of #57's precedence: _attack_candidates already refuses to AIM at
# a body while anyone is standing, which is the whole rule. Both aims here are at the UPRIGHT enemy,
# so the precedence is not in play at all -- only whether the extra corpse in the blast is worth
# anything. It is worth exactly +1 (a downed unit clings at 1 HP and the overkill clamp binds), which
# is enough to break a tie and not enough to outrank felling someone standing.
func test_an_aoe_that_also_catches_a_body_beats_the_same_shot_that_does_not() -> void:
	var board: Dictionary = _build_board()
	var attacker: Unit = _spawn(board, PLAYER, Vector2i(0, 0))
	var weapon: WeaponInstance = attacker.get_equipped_weapon() as WeaponInstance
	var sweep: WeaponAttackData = WeaponAttackData.new()
	sweep.power = 3                                    # same power as main: the ONLY difference is reach
	P.line(sweep, 2)    # length 2 -- the aimed cell and one beyond
	var extras: Array[WeaponAttackData] = [sweep]
	weapon.template.extra_attacks = extras
	var upright: Unit = _spawn(board, ENEMY, Vector2i(1, 0))
	var body: Unit = _spawn(board, ENEMY, Vector2i(2, 0), false)
	_down(body)

	AITactics.queue_main_actions_for_squad(attacker.squad, _context(board), board.squad_manager)

	var ordered := _attacks_in_order(attacker.squad)
	assert_int(ordered.size()).override_failure_message("no attack was queued at all").is_equal(1)
	if ordered.is_empty():
		return
	assert_that(ordered[0].target_cell).override_failure_message(
			"the aim left the standing enemy, so #57's precedence is what is being measured, not this"
			).is_equal(upright.movement.cell)
	assert_object(ordered[0].fired_attack).override_failure_message(
			"the AI took the shot that spares the corpse, over the identical one that also finishes it"
			).is_same(sweep)


# --- A target the plan has already KILLED is not a target (#719, dev 2026-09-03) ----------------

# Reported from play: the defending leader fired her 6-long line down the middle of her own party,
# into a player unit her squadmates had already finished this round. Logged marginal (0, -20, 0) --
# ten to her own archer, ten to her own general, and ten to a corpse. She took it because with no
# bar (#711) a squad's only option is taken however bad it is, and it was her only option because
# the dead unit was still being offered as one.
#
# The offer came from the SECOND pass: it admitted anyone `is_downed()` on the LIVE board and never
# asked the plan's hypo, while pass 1 had asked it since #117. One filter with the hypo clause, one
# without -- the duplicate-filter shape #716 was, drifting the same way.
#
# HYPO-DOWNED IS STILL A TARGET and that is the whole distinction: finishing a body is intended when
# nothing else is in reach, and the case above pins it. What is gone is aiming at somebody the plan
# has already taken off the board entirely.
func test_a_target_the_plan_has_already_killed_is_not_aimed_at() -> void:
	var board: Dictionary = _build_board()
	var body: Unit = _spawn(board, ENEMY, Vector2i(0, 0), false)
	_down(body)
	var m1: Unit = _spawn(board, PLAYER, Vector2i(1, 0))    # adjacent: finishes the body, hypo DEAD
	var m2: Unit = _spawn(board, PLAYER, Vector2i(2, 0))
	board.squad_manager.join_squad(m2, m1.squad)

	# M2's line sweeps its own squadmate on the way to the body, and the body is its only enemy --
	# so if the corpse still counts, this is the only candidate it has and it fires.
	var weapon: WeaponInstance = m2.get_equipped_weapon() as WeaponInstance
	var lance: WeaponAttackData = WeaponAttackData.new()
	lance.power = 3
	lance.hits_allies = true
	P.line(lance, 2)   # length 2: (1,0) then (0,0)
	var extras: Array[WeaponAttackData] = [lance]
	weapon.template.extra_attacks = extras

	AITactics.queue_main_actions_for_squad(m1.squad, _context(board), board.squad_manager)

	assert_int(_aim_count(m1.squad, body.movement.cell)).override_failure_message(
			"a second swing was aimed at a unit the plan had already killed: %s" % str(_attack_aims(m1.squad))
			).is_equal(1)
	var ordered := _attacks_in_order(m1.squad)
	assert_int(ordered.size()).is_equal(1)
	if ordered.is_empty():
		return
	assert_object(ordered[0].actor).override_failure_message(
			"the finisher is no longer the one that queued -- the fixture stopped measuring #719"
			).is_same(m1)


# --- Where a shoved target IS, versus where it WAS (#709) ---------------------------------------

# A pattern-less weapon that shoves for a chosen power -- the pair below needs a shover that LOSES
# the argmax, which _shoving_weapon's fixed 3 cannot express.
func _shoving_weapon_of(power: int) -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = power
	template.main_attack.knockback = 1
	return WeaponInstance.make(template)


# THE AIM FOLLOWS THE SHOVE. A queued squadmate's knockback moves the target inside the plan, and
# the candidate builder used to read `other.movement.cell` -- where the enemy stands on the LIVE
# board, which the plan has already left behind.
#
# The fixture is built so the two answers are not merely different but DISJOINT: B cannot reach E
# where it stands (Manhattan 2 away) and can reach only where the shove puts it. So this measures
# the direction that is invisible today rather than one that merely mis-aims -- a shove that pulls
# a target INTO a squadmate's reach produces a candidate that did not exist before.
#
# A(0,0) shoves E(1,0) to (2,0); B(2,1) is adjacent to the landing cell and nothing else.
func test_a_squadmate_aims_where_the_plans_shove_puts_the_target() -> void:
	var board: Dictionary = _build_board()
	var a: Unit = _spawn(board, PLAYER, Vector2i(0, 0))
	a.equipped_weapon = _shoving_weapon()
	var b: Unit = _spawn(board, PLAYER, Vector2i(2, 1))
	board.squad_manager.join_squad(b, a.squad)
	var e: Unit = _spawn(board, ENEMY, Vector2i(1, 0), false)

	AITactics.queue_main_actions_for_squad(a.squad, _context(board), board.squad_manager)

	assert_int(_aim_count(a.squad, Vector2i(2, 0))).override_failure_message(
			"nobody aimed at the cell the plan's own shove throws %s to -- aims were %s" % [
				e.get_unit_name(), str(_attack_aims(a.squad))]).is_equal(1)


# THE SAME READ, ONE LAYER DOWN: a candidate list must be built against the REAL plan, never
# against whatever the last hypothetical published.
#
# `_best_candidate_for` resolves a hypothetical per candidate and the joint pass restores only
# before it queues, so the member iterated SECOND used to have its candidates built while the
# first member's last rejected hypothetical was still published on the board. That is not a
# projected read at all -- it is a read of a plan nobody gave.
#
# A is the leader and iterates first, but its power-1 shove LOSES the argmax to B's honest 3, so
# the winner is decided by a list that must have been built before A ever probed. Under the old
# order B's list is built with E shoved to (3,0), which B cannot reach: B builds nothing, A wins
# by default, and the squad's better attack is never authored.
func test_a_candidate_list_is_built_against_the_plan_not_a_rejected_hypothetical() -> void:
	var board: Dictionary = _build_board()
	var a: Unit = _spawn(board, PLAYER, Vector2i(1, 0))
	a.equipped_weapon = _shoving_weapon_of(1)
	var b: Unit = _spawn(board, PLAYER, Vector2i(2, 1))
	board.squad_manager.join_squad(b, a.squad)
	var e: Unit = _spawn(board, ENEMY, Vector2i(2, 0), false)

	AITactics.queue_main_actions_for_squad(a.squad, _context(board), board.squad_manager)

	var by_b := 0
	for action in a.squad.action_queue:
		if action.action_type == BaseAction.ActionType.ATTACK and action.actor == b:
			by_b += 1
			assert_vector((action as AttackAction).target_cell).override_failure_message(
					"B aimed at a cell only a rejected hypothetical ever put %s on" % e.get_unit_name()
					).is_equal(Vector2i(2, 0))
	assert_int(by_b).override_failure_message(
			"B never attacked: its candidates were built against A's published shove -- aims were %s"
			% str(_attack_aims(a.squad))).is_equal(1)


# --- Crisis, which the AI does not see (#708) ---------------------------------------------------

# Arm the gambit the way content does, mirroring tests/rules/test_crisis_preview.gd's helper: the
# Berserker job's pool carries the ability, so this exercises jobs -> JobCatalog -> ability kit
# rather than hand-stamping a flag.
func _arm_crisis(unit: Unit) -> void:
	unit.unit_instance.jobs.append("berserker")
	assert_bool(unit.has_live_ability(Abilities.Id.CRISIS)) \
		.override_failure_message("fixture: the Berserker job did not arm Crisis").is_true()


# THE AI IS BLIND TO CRISIS (dev ruling, 2026-09-04): a hit the ladder sentences to CRISIS is priced
# at the damage it WOULD have done, and at the removal it WOULD have earned, if the gambit did not
# exist. His words: "the ai simply won't see crisis mode until they have to react to a unit
# currently in it."
#
# It scored (0,0,0) before -- the damage was skipped outright and CRISIS threads ACTIVE, so no
# removal either -- which under #711's no-bar rule is not a refusal but a losing candidate: any
# ordinary target outranks it, so a full-Will Berserker was the LAST thing an AI would swing at.
# That is the shape #708 filed; its own "a neutral verdict means never" reading died with the bar.
#
# Both targets are UNARMED, and that is load-bearing rather than tidy. A Crisis'd defender is still
# ACTIVE, so it COUNTERS where a downed one cannot -- and the AI is deliberately sighted to that
# reply (dev, same day), so an armed pair would separate on the counter term z and this case would
# pin the opposite of the ruling. The blindness is to the gambit, never to what it draws.
#
# The armed one is spawned FIRST so it leads board order: after the fix both candidates score
# identically and the tie falls to that order, so the assertion can only pass if the scores really
# tie -- it cannot be satisfied by a preference that happens to point the right way.
func test_a_crisis_armed_target_is_priced_like_any_other_kill() -> void:
	var board: Dictionary = _build_board()
	var attacker: Unit = _spawn(board, PLAYER, M1_CELL)
	attacker.equipped_weapon = H.make_weapon(5)   # power 5 + fixture STR 5 = MHP 10: fells exactly, no overkill
	# WIL is NOT in squad_fixtures' TEST_TUNING, so a baseline unit sits below CRISIS_WILL_GATE and
	# the ability alone arms nothing -- the rung comes back DOWNED and this case measures an ordinary
	# kill that passes whatever the scorer does. It did, before the override and the pin below.
	var armed: Unit = BB.spawn(board, H.make_unit_data({Stats.Stat.WIL: UnitInstance.MAX_WILL}, ENEMY), A_CELL)
	_arm_crisis(armed)
	var plain: Unit = _spawn(board, ENEMY, B_CELL, false)

	AITactics.queue_main_actions_for_squad(attacker.squad, _context(board), board.squad_manager)

	assert_int(_aim_count(attacker.squad, A_CELL)).override_failure_message(
			"the AI passed over the Berserker at %s for %s -- it is still seeing the gambit; aims were %s" % [
				str(A_CELL), plain.get_unit_name(), str(_attack_aims(attacker.squad))]).is_equal(1)
	assert_int(_aim_count(attacker.squad, B_CELL)).is_equal(0)

	# THE PRECONDITION, ASSERTED THROUGH THE RESOLVER RATHER THAN RESTATED. Whether this fixture is
	# measuring Crisis at all is exactly what a hand-set Will got wrong, and no assertion about the
	# AI's choice can tell a blind scorer from a fixture that never armed the gambit.
	var plan: ResolvedPlan = board.squad_manager.resolve_plan(attacker.squad, _context(board))
	var rung := ResolvedOutcome.Lethality.NONE
	for a in plan.attacks:
		if a.target == armed and a.resolved != null:
			rung = a.resolved.lethality
	assert_that(rung).override_failure_message(
			"fixture: the queued hit sentenced the Berserker to %s, not CRISIS -- this measured an ordinary kill"
			% ResolvedOutcome.Lethality.keys()[rung]).is_equal(ResolvedOutcome.Lethality.CRISIS)
