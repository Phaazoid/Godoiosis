# A swing at a target an earlier hit in the SAME pass already killed WHIFFS, and still spends (#1350;
# dev, 2026-10-21: "It should whiff and still spend, and the preview should reflect that").
#
# The resolver decides it -- ResolvedOutcome.whiffed -- and these are the resolver's own readers of that
# answer: the whiff keeps its aim green, a downed body is still an ordinary target, a path swing stops at
# the body and whiffs, a Guard does not step in front of a whiff, a whiff drops no payload, provokes no
# counter and threatens nobody, and a later hit on a Crisis unit the pass killed whiffs rather than
# wearing KILLED (dev, 2026-10-22). The SPEND runs through both executors, so it is pinned where both
# run: tests/flow/test_execute_two_hosts.gd.
#
# Every case kills its target through a REAL first hit in the same resolve, never a hand-set lifecycle:
# the bug is an ordering one, and a target dead before the pass began is not this rule.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

# A west of the target and B south of it, two apart, so they share a squad and both reach it.
const FOE_CELL := Vector2i(1, 0)
const A_CELL := Vector2i(0, 0)
const B_CELL := Vector2i(1, 1)
# On a 1-HP target this overkills past LethalityRules.OVERKILL_CEILING, so the first hit KILLS.
const KILLING_POWER := 40

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _board() -> BoardContext:
	return _sm.board_source.call()


# A (the killer, leading) and B in one squad. `b_attack` replaces B's main when given.
func _attackers(b_attack: WeaponAttackData = null, b_cell := B_CELL) -> Array[Unit]:
	var a := H.spawn_solo(self, _sm, PLAYER, A_CELL, {}, true, KILLING_POWER)
	var b := H.spawn_solo(self, _sm, PLAYER, b_cell)
	if b_attack != null:
		(b.get_equipped_weapon() as WeaponInstance).template.main_attack = b_attack
	_sm.join_squad(b, a.squad)
	return [a, b]


func _foe(cell := FOE_CELL) -> Unit:
	var foe := H.spawn_solo(self, _sm, ENEMY, cell, {}, false)
	foe.set_current_hp(1)
	return foe


# A swings at the foe, then B: queued in that order, resolved as one plan.
func _resolve_both(a: Unit, b: Unit, foe: Unit) -> ResolvedPlan:
	a.squad._queue_action(H.stamped_attack(a, foe))
	b.squad._queue_action(H.stamped_attack(b, foe))
	return _sm.resolve_plan(a.squad, _board())


func _hits_by(plan: ResolvedPlan, actor: Unit) -> Array[AttackAction]:
	var hits: Array[AttackAction] = []
	for atk in plan.attacks:
		if atk.actor == actor:
			hits.append(atk)
	return hits


# B's one hit, after asserting the first blow really killed -- or every case passes for the wrong reason.
func _b_hit(plan: ResolvedPlan, b: Unit, foe: Unit) -> AttackAction:
	assert_int(PlanResolver.projected_lifecycle(foe, plan.hypo)) \
		.override_failure_message("fixture: A's blow did not kill the foe").is_equal(Unit.LifecycleState.DEAD)
	var hits := _hits_by(plan, b)
	assert_int(hits.size()).override_failure_message("fixture: B's aim expanded to %d hits" % hits.size()).is_equal(1)
	return hits[0]


# ==============================================================================
#  The whiff itself
# ==============================================================================

# The heart of it: the second hit lands nothing and reads no HP, but keeps its target -- which is what
# keeps the AIM green. A whiff the pass made is legal; the whiff clause still refuses an aim at a cell
# that is already empty, and this must not turn into that.
func test_a_second_hit_on_a_body_the_pass_killed_whiffs_and_stays_legal() -> void:
	var pair := _attackers()
	var foe := _foe()
	var plan := _resolve_both(pair[0], pair[1], foe)
	var hit := _b_hit(plan, pair[1], foe)

	assert_bool(hit.resolved.whiffed).override_failure_message("the second hit did not whiff").is_true()
	assert_bool(hit.resolved.skipped).override_failure_message("a whiff is fired, not skipped").is_false()
	assert_bool(hit.resolved.reads_hp).override_failure_message("a whiff printed an HP reading").is_false()
	assert_int(hit.resolved.damage).is_equal(0)
	assert_int(hit.resolved.lethality).is_equal(ResolvedOutcome.Lethality.NONE)
	assert_object(hit.target).override_failure_message("the whiff lost its target").is_same(foe)

	_sm.validate_squad_plan(pair[0].squad, plan)
	assert_bool(_sm.squad_has_invalid_actions(pair[0].squad)) \
		.override_failure_message("a whiff the pass made reddened the plan").is_false()


# A DOWNED body is not a whiff: it is an ordinary target, there to be finished (gather ruling 9). Only a
# body the pass has KILLED is gone.
func test_a_hit_on_a_downed_body_lands() -> void:
	var b := H.spawn_solo(self, _sm, PLAYER, B_CELL, {}, true, KILLING_POWER)
	var foe := _foe()
	foe.take_damage(foe.get_current_hp())
	assert_bool(foe.is_downed()).override_failure_message("fixture: the foe is not downed").is_true()
	b.squad._queue_action(H.stamped_attack(b, foe))
	var plan := _sm.resolve_plan(b.squad, _board())

	var hit := _hits_by(plan, b)[0]
	assert_bool(hit.resolved.whiffed).override_failure_message("a hit on a downed body whiffed").is_false()
	assert_int(hit.resolved.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)


# A Crisis unit the pass killed takes no second KILLED (dev, 2026-10-22: each row shows what its hit
# does -- the Crisis entry, then the kill, then whiffs). The retired 06-26 rule flagged every hit that
# alone would have killed it from pass-start HP.
func test_a_later_hit_on_a_crisis_unit_the_pass_killed_whiffs() -> void:
	var pair := _attackers()
	var foe := _foe()
	foe.in_crisis = true
	var plan := _resolve_both(pair[0], pair[1], foe)
	var hit := _b_hit(plan, pair[1], foe)

	assert_bool(hit.resolved.whiffed).override_failure_message("the hit after the Crisis kill did not whiff").is_true()
	assert_int(hit.resolved.lethality) \
		.override_failure_message("a hit on a Crisis unit the pass already killed still wears KILLED") \
		.is_equal(ResolvedOutcome.Lethality.NONE)


# ==============================================================================
#  Its readers
# ==============================================================================

# A single-target swing takes the first valid body on its path and stops there (#1057) -- and a body the
# pass killed is still the first body. It whiffs there; it does NOT reach through to the unit behind.
func test_a_path_swing_stops_at_the_body_the_pass_killed() -> void:
	var lance := WeaponAttackData.new()
	lance.max_range = 0
	lance.attack_shape = P.pathed([[Vector2i(0, -1), Vector2i(0, -2)] as Array[Vector2i]] as Array[Array])
	lance.swing = true
	# B south of the foe, swinging north: the path takes the foe's cell, then the cell behind it.
	var pair := _attackers(lance, Vector2i(1, 1))
	var foe := _foe()
	var behind := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, -1), {}, false)
	var plan := _resolve_both(pair[0], pair[1], foe)
	var hit := _b_hit(plan, pair[1], foe)

	assert_object(hit.target).override_failure_message("the swing reached past the body").is_same(foe)
	assert_bool(hit.resolved.whiffed).is_true()
	assert_int(PlanResolver.projected_hp(behind, plan.hypo)) \
		.override_failure_message("the unit behind the body was hit").is_equal(behind.get_current_hp())


# A Guard does not step in front of a blow aimed at a body the pass killed: there is nobody to guard,
# and substituting would turn the whiff into a hit on the bodyguard. A's blow PIERCES, so the ward is
# still unspent when B's ordinary hit arrives.
func test_a_guard_does_not_step_in_front_of_a_whiff() -> void:
	var pair := _attackers()
	var a: Unit = pair[0]
	(a.get_equipped_weapon() as WeaponInstance).template.main_attack.pierces_guard = true
	var foe := _foe()
	var blocker := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {}, false)
	blocker.arm_guard(foe, blocker.get_guard_range())
	assert_object(blocker.guard).override_failure_message("fixture: the guard did not arm").is_not_null()
	var plan := _resolve_both(a, pair[1], foe)
	var hit := _b_hit(plan, pair[1], foe)

	assert_object(hit.target).override_failure_message("the bodyguard stepped in front of a whiff").is_same(foe)
	assert_object(hit.blocked_for).is_null()
	assert_bool(hit.resolved.whiffed).is_true()
	for guard in plan.guards:
		if guard.blocker == blocker:
			assert_bool(guard.spent).override_failure_message("the ward was spent on a whiff").is_false()


# A whiff is a miss, and a miss drops nothing (#1058 ruling 45).
func test_a_whiff_drops_no_payload() -> void:
	var carrier := WeaponAttackData.new()
	carrier.display_name = "Carrier"
	carrier.power = 1
	P.point(carrier, 1)
	var bomb := WeaponAttackData.new()
	bomb.display_name = "Bomb"
	bomb.power = 1
	bomb.targets = EquippableData.TargetMode.BOTH
	P.point(bomb, 1)
	carrier.payload = bomb
	var pair := _attackers(carrier)
	var foe := _foe()
	var plan := _resolve_both(pair[0], pair[1], foe)
	var hit := _b_hit(plan, pair[1], foe)
	assert_bool(hit.resolved.whiffed).is_true()

	for atk in plan.attacks:
		assert_object(atk.dropped_by).override_failure_message("a whiff dropped a payload").is_null()


# A reaction answers a HIT (#767), and a whiff hit nobody. Asked of the derivation directly: in ordinary
# play the blow that killed the target has already spent its squad's one reaction, so no end-to-end
# pass can see this -- only a watch shot's splash kills without drawing one.
func test_a_whiff_provokes_no_counter() -> void:
	var b := H.spawn_solo(self, _sm, PLAYER, B_CELL)
	var foe := _foe()
	var mate := H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 1))   # beside B, so it could answer
	_sm.join_squad(mate, foe.squad)
	var hit := H.stamped_attack(b, foe)
	hit.resolved = ResolvedOutcome.new()
	var attacks: Array[AttackAction] = [hit]

	assert_int(_sm.calculate_reactions_for_squad(b.squad, attacks, _board(), {}).size()) \
		.override_failure_message("fixture: the foe's squadmate would not answer a landed hit").is_greater(0)
	hit.resolved.whiffed = true
	assert_int(_sm.calculate_reactions_for_squad(b.squad, attacks, _board(), {}).size()) \
		.override_failure_message("a whiff drew a counter").is_equal(0)


# The threat readout lists what a plan would DO to somebody, and a whiff does nothing to anybody.
func test_a_whiff_threatens_nobody() -> void:
	var pair := _attackers()
	var foe := _foe()
	var plan := _resolve_both(pair[0], pair[1], foe)
	var hit := _b_hit(plan, pair[1], foe)
	assert_bool(hit.resolved.whiffed).is_true()

	assert_object(AIController._intent_for(hit, plan, {})) \
		.override_failure_message("a whiff showed up as a threat").is_null()
