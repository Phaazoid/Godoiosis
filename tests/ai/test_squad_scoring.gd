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
# re-pays the second member for finishing what the first downed. Here there is nowhere else to go,
# so the question is only whether the wasted swing is still worth taking -- it is not.
func test_a_second_swing_at_a_body_the_plan_already_downed_is_declined() -> void:
	var board: Dictionary = _build_board()
	var pair := _pair(board)
	var a: Unit = _spawn(board, ENEMY, A_CELL)
	a.set_current_hp(3)

	AITactics.queue_main_actions_for_squad(pair[0].squad, _context(board), board.squad_manager)

	assert_int(_aim_count(pair[0].squad, A_CELL)).override_failure_message(
			"a member spent its action overkilling a body: %s" % str(_attack_aims(pair[0].squad))).is_equal(1)


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
# so the pass has to finish on a real resolve. Two members and one 3 HP enemy is the shape that
# reaches it -- the second member's only candidate is refused, so the loop breaks with a rejected
# hypothetical as the last thing resolved.
func test_scoring_leaves_the_board_where_a_real_resolve_would() -> void:
	var board: Dictionary = _build_board()
	var pair := _pair(board)
	var a: Unit = _spawn(board, ENEMY, A_CELL)
	a.set_current_hp(3)
	var context: BoardContext = _context(board)

	AITactics.queue_main_actions_for_squad(pair[0].squad, context, board.squad_manager)

	var after_pass := {}
	for unit in context.units:
		after_pass[unit] = unit.get_projected_destination()
	board.squad_manager.resolve_plan(pair[0].squad, context)
	for unit in context.units:
		assert_that(after_pass[unit]).override_failure_message(
				"%s sat at a HYPOTHETICAL's projection after the pass" % unit.get_unit_name()) \
			.is_equal(unit.get_projected_destination())
