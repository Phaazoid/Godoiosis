# Reactive healing (#148) — squad-system.md C8/C9/C10, plus C5's trigger half (#767).
#
# Being attacked grants every unit in the defending party ONE main-attack-shaped reaction (C1,
# unchanged). What #148 adds is that the reaction's KIND forks on its source's AttackData.heals:
# a damaging source strikes the attacking party, a healing one turns inward and heals its own
# side. Before this, a healer countered and the resolver's heal branch — which has no friend/foe
# check — restored HP to the ATTACKER.
#
# Three rules carry the weight, and each has its own case below because each was independently
# get-wrong-able:
#   * a healing reaction can never touch an enemy, at the target pick OR in an AoE splash
#   * "below max HP" is a FILTER and "lowest HP" is the SORT — collapse them into one comparison
#     and a full 19/19 unit outranks a hurt 20/23 one
#   * every HP read comes off the THREADED HYPOTHETICAL, not the live board: the attacks have
#     already resolved into the hypo and onto nothing else, so a live read heals whoever was
#     hurt BEFORE the swing
#
# The last section is #767's and belongs to C5 rather than to #148: what may TRIGGER a reaction at
# all. It lives here because the trigger's only observable leak was heal-shaped — a damaging
# squadmate is refused by choose_counter_target whatever the trigger was, so a healer is the only
# witness this file could ever have called.
#
# Weapons are pattern-less => Reach falls back to Manhattan 1 (the caster's own cell included),
# so reach is grid-free: distance <= 1 can be healed, >= 2 cannot. Base damage is power + STR
# (WeaponData's default scaling_blend is 100% STR), the same arithmetic tests/law/test_healing.gd
# uses — so the fixture's power-3 weapon on STR 5 lands 8.
#
# No fixture unit holds the Crisis ability (#158), so a would-be-down in the R7 case is a plain
# DOWNED rather than a CRISIS that stands the unit back up at revive HP. (This comment used to
# lean on the player-faction stance short-circuit; the ability read replaced it.)
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

# The attacked squad's LEADER: LDR 9 buys capacity for four members (leader + floor(eLDR / 2)) so
# join_squad doesn't push_warning, and MHP 30 means the incoming 8 leaves it HURT AND STANDING.
# That second half is load-bearing: a downed unit is not a heal candidate (C9), so a defender that
# falls to the attack would make these cases pass for the wrong reason.
const TOUGH_LEADER := {Stats.Stat.LDR: 9, Stats.Stat.MHP: 30}

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# Author `unit`'s weapon as a heal: the same shape tests/law/test_healing.gd uses, plus hits_self
# when the case needs the caster to be its own target (#123's flag, which C9 reads rather than
# re-deriving "can this heal reach me").
func _make_healer(unit: Unit, power: int = 4, hits_self: bool = false) -> void:
	var weapon := H.make_weapon(power)
	weapon.template.main_attack.heals = true
	weapon.template.main_attack.hits_allies = true
	weapon.template.main_attack.hits_self = hits_self
	if hits_self:
		# Reaching your own cell is a RANGE question and hits_self is a VICTIM one, so a healer that
		# patches itself needs both. It used to need only the flag, because an attack with no
		# geometry fell back to a Manhattan-1 ring that happened to include the origin; since #808
		# every attack has a real range and min_range 1 means adjacent, so the self-aim is authored.
		weapon.template.main_attack.min_range = 0
	unit.equipped_weapon = weapon

# Queue one real attack and resolve the attacker's whole plan — the production path, so victim
# gathering, the shared hypo and the reaction derivation all run exactly as they do in game.
func _resolve_attack_on(attacker: Unit, target: Unit, units: Array[Unit]) -> ResolvedPlan:
	attacker.squad._queue_action(H.stamped_attack(attacker, target))
	return _sm.resolve_plan(attacker.squad, BoardContext.new(_sm.grid, units, _sm))

func _reactions_by_actor(plan: ResolvedPlan, actor: Unit) -> Array[CounterAttackAction]:
	var found: Array[CounterAttackAction] = []
	for reaction in plan.counters:
		if reaction.actor == actor:
			found.append(reaction)
	return found


# --- C8: a healer's reaction turns inward ---

# The headline case, and the shape the dev described: the healer stands TWO cells from the
# attacker, so under C2/C5/C6 it could not counter at all — it reacts anyway, because a healing
# reaction needs a valid heal target rather than an enemy in reach.
func test_a_reacting_healer_heals_a_hurt_squadmate_and_never_the_attacker() -> void:
	var attacker := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var defender := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), TOUGH_LEADER)
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0))
	_sm.join_squad(healer, defender.squad)
	_make_healer(healer)
	defender.set_current_hp(20)

	var plan := _resolve_attack_on(attacker, defender, [attacker, defender, healer] as Array[Unit])

	var heals := _reactions_by_actor(plan, healer)
	assert_int(heals.size()).is_equal(1)
	assert_object(heals[0].target).is_same(defender)
	assert_int(heals[0].resolved.heal_amount).is_greater(0)
	# The attacker is not a victim of any reaction — neither healed nor hit by the healer.
	for reaction in heals:
		assert_object(reaction.target).is_not_same(attacker)
	_break_volleys(plan)

# hits_self (#123) is what makes the caster its own legal target, and min_range 0 is what puts its
# own cell in reach -- see _make_healer. A lone attacked healer with nobody else to help patches itself up.
func test_a_healer_heals_itself_when_it_is_the_only_valid_target() -> void:
	var attacker := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), TOUGH_LEADER)
	_make_healer(healer, 4, true)
	healer.set_current_hp(20)

	var plan := _resolve_attack_on(attacker, healer, [attacker, healer] as Array[Unit])

	var heals := _reactions_by_actor(plan, healer)
	assert_int(heals.size()).is_equal(1)
	assert_object(heals[0].target).is_same(healer)
	_break_volleys(plan)

# Control for the case above: without hits_self the caster is not its own victim, so a lone healer
# with no hurt ally simply does not react. There is no fall-back to swinging at the attacker — a
# healing main cannot hurt anything.
func test_a_healer_that_cannot_target_itself_does_not_react_alone() -> void:
	var attacker := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), TOUGH_LEADER)
	_make_healer(healer, 4, false)
	healer.set_current_hp(20)

	var plan := _resolve_attack_on(attacker, healer, [attacker, healer] as Array[Unit])

	assert_array(plan.counters).is_empty()
	_break_volleys(plan)

# The splash, one layer below the target pick. An AoE heal whose blast covers the attacker picks
# the right ALLY and then, without the allies_only gate, tops the attacker up anyway — because an
# enemy inside a footprint is an ordinary victim. A player-AIMED heal keeps that splash on purpose
# (dev call); only the derived reaction is restricted.
func test_an_aoe_reaction_heal_does_not_heal_the_enemy_in_its_blast() -> void:
	var attacker := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var defender := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), TOUGH_LEADER)
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0))
	_sm.join_squad(healer, defender.squad)
	_make_healer(healer)
	# The aimed cell plus the one beyond it, along the aim -- a two-cell blast, so the test exercises
	# the volley and not the geometry. A stamp turns with the aim, which on this axis-aligned board is
	# exactly what the retired hand-rolled pattern spelled as a fixed world direction.
	var blast: Array[Vector2i] = [Vector2i.ZERO, Vector2i(0, -1)]
	P.stamped((healer.get_equipped_weapon() as WeaponInstance).template.main_attack, 3, blast)
	defender.set_current_hp(20)

	var plan := _resolve_attack_on(attacker, defender, [attacker, defender, healer] as Array[Unit])

	# The blast is {the aimed cell, the cell left of it} = {(1,0), (0,0)} — the attacker stands
	# inside it and is still not a victim.
	var healed: Array[Unit] = []
	for reaction in _reactions_by_actor(plan, healer):
		healed.append(reaction.target)
	assert_array(healed).contains_exactly([defender])
	_break_volleys(plan)


# --- C9: who gets the heal ---

# The dev's own case, verbatim: a unit at full 19/19 must not beat a hurt 20/23. "Below max HP" is
# a FILTER; "lowest HP" is the SORT. Collapse them into one comparison and the full unit wins.
func test_a_full_hp_ally_never_beats_a_hurt_one_with_more_hp() -> void:
	var attacker := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var defender := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.LDR: 9, Stats.Stat.MHP: 40})
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0))
	var full := H.spawn_solo(self, _sm, PLAYER, Vector2i(3, 0), {Stats.Stat.MHP: 19})
	var hurt := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 1), {Stats.Stat.MHP: 23})
	for member in [healer, full, hurt]:
		_sm.join_squad(member, defender.squad)
	_make_healer(healer)
	assert_int(full.get_current_hp()).is_equal(19)   # full, and the LOWEST absolute HP in reach
	hurt.set_current_hp(20)

	var plan := _resolve_attack_on(attacker, defender, [attacker, defender, healer, full, hurt] as Array[Unit])

	var heals := _reactions_by_actor(plan, healer)
	assert_int(heals.size()).is_equal(1)
	assert_object(heals[0].target).is_same(hurt)
	_break_volleys(plan)

# A downed ally is skipped outright, not merely deprioritised (dev call): a heal moves HP but never
# lifts lifecycle_state, so healing a body accomplishes nothing — and a downed unit clings at 1 HP,
# which wins every lowest-HP comparison, so it would eat the squad's whole reaction.
func test_a_downed_ally_is_never_the_heal_target() -> void:
	var attacker := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var defender := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), TOUGH_LEADER)
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0))
	var body := H.spawn_solo(self, _sm, PLAYER, Vector2i(3, 0))
	_sm.join_squad(healer, defender.squad)
	_sm.join_squad(body, defender.squad)
	_make_healer(healer)
	body.take_damage(body.get_current_hp())          # goes down: clings at 1 HP, the lowest in reach
	assert_bool(body.is_downed()).is_true()
	defender.set_current_hp(20)

	var plan := _resolve_attack_on(attacker, defender, [attacker, defender, healer, body] as Array[Unit])

	var heals := _reactions_by_actor(plan, healer)
	assert_int(heals.size()).is_equal(1)
	assert_object(heals[0].target).is_same(defender)
	_break_volleys(plan)

# THE trap. The reaction is derived AFTER the attacks have resolved, but their damage lives only in
# the threaded hypothetical — the board still reads pre-attack HP. Here the defender starts FULL and
# this pass's own hit knocks it below the scratched ally. Read live, the healer sees a full defender,
# filters it out, and patches the ally instead; read off the hypo it heals the unit that just took
# the swing, which is the entire point of the feature.
func test_the_heal_target_is_judged_on_this_passs_damage_not_the_live_board() -> void:
	var attacker := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var defender := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.LDR: 9})
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0))
	var scratched := H.spawn_solo(self, _sm, PLAYER, Vector2i(3, 0))
	_sm.join_squad(healer, defender.squad)
	_sm.join_squad(scratched, defender.squad)
	_make_healer(healer)
	var max_hp := defender.get_max_hp()
	assert_int(defender.get_current_hp()).is_equal(max_hp)   # full on the live board
	scratched.set_current_hp(max_hp - 1)                     # live, the only hurt unit in reach

	var plan := _resolve_attack_on(attacker, defender, [attacker, defender, healer, scratched] as Array[Unit])

	assert_int(plan.attacks[0].resolved.target_hp_after).is_less(scratched.get_current_hp())
	var heals := _reactions_by_actor(plan, healer)
	assert_int(heals.size()).is_equal(1)
	assert_object(heals[0].target).is_same(defender)
	_break_volleys(plan)

# Nobody hurt, nobody healed: the filter leaves no candidate, so the squad's healer contributes no
# reaction row at all rather than an inert one. (A 0-power, STR-0 attacker leaves everyone full.)
func test_a_healer_with_no_hurt_ally_does_not_react() -> void:
	var attacker := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0), {Stats.Stat.STR: 0}, true, 0)
	var defender := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), TOUGH_LEADER)
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0))
	_sm.join_squad(healer, defender.squad)
	_make_healer(healer)

	var plan := _resolve_attack_on(attacker, defender, [attacker, defender, healer] as Array[Unit])

	assert_int(plan.attacks[0].resolved.damage).is_equal(0)   # everyone still full
	assert_array(_reactions_by_actor(plan, healer)).is_empty()
	_break_volleys(plan)


# --- C10 / C1 / R7: the reaction as a whole ---

# Healing reactions are emitted after the damaging ones, so resolve_counters (which walks the list
# in order) lands a heal AFTER any counter that ally-splashed its own squad. That ordering is why
# #148 needed no separate post-counter stage, and nothing else pins it.
func test_healing_reactions_resolve_after_damaging_ones() -> void:
	var attacker := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var fighter := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), TOUGH_LEADER)
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0))
	_sm.join_squad(healer, fighter.squad)
	_make_healer(healer)
	fighter.set_current_hp(20)

	var plan := _resolve_attack_on(attacker, fighter, [attacker, fighter, healer] as Array[Unit])

	assert_int(plan.counters.size()).is_equal(2)
	assert_object(plan.counters[0].actor).is_same(fighter)    # the strike, adjacent to the attacker
	assert_object(plan.counters[0].target).is_same(attacker)
	assert_object(plan.counters[1].actor).is_same(healer)     # the heal, after it
	assert_object(plan.counters[1].target).is_same(fighter)
	_break_volleys(plan)

# R7 liveness, unchanged by #148: a reactor felled by the attack it is reacting to does not act.
# The row is derived and then marked skipped, exactly as a counter is, so the queue hides it.
func test_a_healer_downed_by_the_attack_does_not_react() -> void:
	var attacker := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.LDR: 9})
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0))
	_sm.join_squad(ally, healer.squad)
	_make_healer(healer)
	ally.set_current_hp(1)
	healer.set_current_hp(2)   # the incoming 8 takes this under

	var plan := _resolve_attack_on(attacker, healer, [attacker, healer, ally] as Array[Unit])

	var heals := _reactions_by_actor(plan, healer)
	assert_int(heals.size()).is_equal(1)
	assert_bool(heals[0].resolved.skipped).is_true()
	_break_volleys(plan)

# Law #2: the queue row promises a number, and replaying the pass must move exactly that much HP.
# Replayed the way AttackAction.execute does it minus the lunge animation — take_damage for the
# attack, heal for the reaction — so the arithmetic the panel drew is the arithmetic that lands.
# Also pins the row's text, which forks on the same `heals` flag rather than storing a kind.
func test_the_previewed_heal_is_the_hp_execution_actually_moves() -> void:
	var attacker := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var defender := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), TOUGH_LEADER)
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0))
	_sm.join_squad(healer, defender.squad)
	_make_healer(healer)
	defender.set_current_hp(20)

	var plan := _resolve_attack_on(attacker, defender, [attacker, defender, healer] as Array[Unit])

	var reaction := _reactions_by_actor(plan, healer)[0]
	assert_str(reaction.get_description()).contains("heals")
	defender.take_damage(plan.attacks[0].resolved.damage)
	defender.heal(reaction.resolved.heal_amount)
	assert_int(defender.get_current_hp()).is_equal(reaction.resolved.target_hp_after)
	_break_volleys(plan)


# --- C5 trigger half: a reaction answers a HOSTILE hit (#767) --------------------------------

# THE REPORTED BUG, whole (in-game report 2026-09-05, build 0.136.0): the player queues a heal and
# the healer heals TWICE. A heal is an ordinary AttackAction whose target is an ALLY, so the walk
# over plan.attacks made the healer's own squad the defending party and handed it a free reaction.
#
# The shape is the report's: a healer and TWO hurt squadmates. The second wounded unit is what
# keeps this case honest -- with only one, the queued heal itself lifts the only candidate out of
# range of C9's "below max HP" filter and the case would pass on an empty candidate set rather than
# on the gate. wounded_b is never touched by the plan, so a reaction has somewhere to land right up
# until the gate refuses to derive one.
func test_a_squads_own_heal_draws_no_reaction_from_itself() -> void:
	var wounded_a := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), TOUGH_LEADER)
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0), TOUGH_LEADER)
	var wounded_b := H.spawn_solo(self, _sm, PLAYER, Vector2i(3, 0), TOUGH_LEADER)
	_sm.join_squad(healer, wounded_a.squad)
	_sm.join_squad(wounded_b, wounded_a.squad)
	_make_healer(healer)
	wounded_a.set_current_hp(10)
	wounded_b.set_current_hp(10)

	var units := [wounded_a, healer, wounded_b] as Array[Unit]
	var plan := _resolve_attack_on(healer, wounded_a, units)

	# The heal itself still happens -- a case that passed because nothing resolved would be no case.
	assert_int(plan.attacks.size()).is_equal(1)
	assert_object(plan.attacks[0].target).is_same(wounded_a)
	assert_int(plan.attacks[0].resolved.heal_amount).is_greater(0)
	# ...and the squad answers its own heal with nothing. wounded_b is still at 10/30 here, so the
	# pre-#767 derivation had a perfectly good second target and took it.
	assert_int(plan.counters.size()).is_equal(0)
	_break_volleys(plan)

# The dev's own example of the nonsense this opens: "being able to blow your own unit a tile to
# double their output." Same gate, damaging source -- an attack aimed at a squadmate. Deliberately
# NO enemy on the board, so `counters` empty is exact rather than a claim about which reactions
# survived; a squad hitting itself is the whole trigger under test.
func test_a_friendly_fire_hit_draws_no_reaction_from_the_attackers_own_squad() -> void:
	var splasher := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), TOUGH_LEADER)
	var victim := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), TOUGH_LEADER)
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0), TOUGH_LEADER)
	_sm.join_squad(victim, splasher.squad)
	_sm.join_squad(healer, splasher.squad)
	_make_healer(healer)
	(splasher.get_equipped_weapon() as WeaponInstance).template.main_attack.hits_allies = true

	var units := [splasher, victim, healer] as Array[Unit]
	var plan := _resolve_attack_on(splasher, victim, units)

	# MHP 30 taking base 8 (power 3 + STR 5) leaves the victim HURT AND STANDING -- a live heal
	# candidate, which is what the healer would have answered with before the gate.
	assert_int(plan.attacks[0].resolved.damage).is_greater(0)
	assert_int(PlanResolver.projected_hp(victim, plan.hypo)).is_between(1, 29)
	assert_int(plan.counters.size()).is_equal(0)
	_break_volleys(plan)

# THE GATE IS FACTION-SHAPED, NOT SQUAD-SHAPED -- and this case is the only thing that says so.
# Found by mutating: "defender_squad != attacking_squad" is the tempting symptom patch, and it
# survives every other case in this section, because in all of them the two squads are the same
# object. Two FRIENDLY squads is the board that separates them: one squad's healer patches the
# other's wounded, the squads differ, and the units are still not enemies. Under the symptom patch
# squad B answers with a free heal of its own; under the rule the dev actually gave, nothing.
func test_a_heal_across_two_friendly_squads_draws_no_reaction() -> void:
	var healer_a := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	var wounded_b := H.spawn_solo(self, _sm, PLAYER, Vector2i(2, 0), TOUGH_LEADER)
	var healer_b := H.spawn_solo(self, _sm, PLAYER, Vector2i(3, 0), TOUGH_LEADER)
	_sm.join_squad(healer_b, wounded_b.squad)
	_make_healer(healer_a)
	_make_healer(healer_b)
	wounded_b.set_current_hp(10)

	var units := [healer_a, wounded_b, healer_b] as Array[Unit]
	var plan := _resolve_attack_on(healer_a, wounded_b, units)

	# 10 + 9 = 19 of 30, so squad B's own healer still has a hurt squadmate in reach -- the derived
	# reaction had somewhere to go and the gate is what stopped it, not an empty candidate set.
	assert_int(plan.attacks[0].resolved.heal_amount).is_greater(0)
	assert_int(PlanResolver.projected_hp(wounded_b, plan.hypo)).is_between(11, 29)
	assert_int(_reactions_by_actor(plan, healer_b).size()).is_equal(0)
	assert_int(plan.counters.size()).is_equal(0)
	_break_volleys(plan)

# THE FORK THE DEV PICKED, pinned (ruling 2026-09-05): the gate is "actor and target are enemies",
# NOT "a heal never triggers". Healing an enemy is authored canon (C8's note that a player-AIMED
# heal keeps its enemy splash), and being healed by an enemy is still being acted upon by one -- so
# the enemy's own reaction survives. Under the rejected route this case reads zero.
func test_a_heal_aimed_at_an_enemy_still_draws_their_reaction() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), TOUGH_LEADER)
	_make_healer(healer)
	foe.set_current_hp(10)

	var plan := _resolve_attack_on(healer, foe, [healer, foe] as Array[Unit])

	assert_object(plan.attacks[0].target).is_same(foe)
	assert_int(plan.attacks[0].resolved.heal_amount).is_greater(0)
	assert_int(plan.counters.size()).is_equal(1)
	assert_object(plan.counters[0].actor).is_same(foe)
	assert_object(plan.counters[0].target).is_same(healer)
	_break_volleys(plan)


# A fixed 2-cell blast (the aimed cell + the cell to its LEFT), borrowed from test_counter_aoe.gd:
# exercises the reaction volley's victim gather rather than real pattern geometry.
# Volley siblings link into a shared self-referential array (a RefCounted cycle, #35) — break both
# lists so the derived plan doesn't leak after the test.
func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for ctr in plan.counters:
		ctr.volley = empty
