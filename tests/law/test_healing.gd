# Healing: an attack authored with `heals = true` reinterprets the SAME base-damage number
# (power + scaling/aura) as HP restored instead of removed — one number, two meanings, never
# both on one attack. It short-circuits _resolve_one before every stage below base damage:
# DEF is skipped by never being ASKED (ignores it by construction, not a bypass flag — DEF only
# stops harm, and a heal never is), and elemental reactions/insulation, the Iron Will cap, the
# lethality ladder, and knockback are all questions about being hurt that a heal never raises.
# `damage` stays untouched at its 0 default (the existing floor-at-0 invariant, test_damage_floor.gd,
# is undisturbed — a heal is new additive surface, not a sign-flip of damage); the restored total
# lives on the new `ResolvedOutcome.heal_amount` field, capped at the target's real (gear-inclusive)
# max HP via the same clamp `set_current_hp` already enforces at execution time.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _make_armor(def_power: int) -> ArmorData:
	var armor := ArmorData.new()
	armor.def_power = def_power
	return armor


# A healer's weapon attack authored to heal instead of damage. `hits_allies` is set because a
# real heal is always authored ally-splash-capable (RulesService.gather_attack_victims'
# targeting gate) — unenforced at this resolver layer, but faithful to real content.
func _heal_attack(healer: Unit, target: Unit, power: int) -> AttackAction:
	var weapon := H.make_weapon(power)
	weapon.template.main_attack.heals = true
	weapon.template.main_attack.hits_allies = true
	healer.equipped_weapon = weapon
	return H.stamped_attack(healer, target)


func test_heal_restores_hp_instead_of_removing_it() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	# MHP overridden well above the -12 offset below -- the fixture's untuned default (10, per
	# TEST_TUNING) sits BELOW it, which silently clamped current_hp to 0 instead of "12 below
	# max" and made this test assert the wrong post-heal number.
	var target := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.MHP: 20})
	var max_hp := target.get_max_hp()
	target.set_current_hp(max_hp - 12)

	var attack := _heal_attack(healer, target, 6)   # base 10 (power 6 + STR 4)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.heal_amount).is_equal(10)
	assert_int(attack.resolved.damage).is_equal(0)
	assert_int(attack.resolved.target_hp_after).is_equal(max_hp - 2)


# A caster aiming Heal at their own cell (#123) -- legal only because `hits_self` is set, the
# same eligibility gate RulesService.is_attack_victim applies to gather_attack_victims/
# aim_finds_a_target. This proves the flag actually restores HP end to end through the resolver,
# not just that the predicate returns true.
func test_self_aimed_heal_with_hits_self_restores_the_casters_own_hp() -> void:
	var caster := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4, Stats.Stat.MHP: 20})
	var max_hp := caster.get_max_hp()
	caster.set_current_hp(max_hp - 12)

	var attack := _heal_attack(caster, caster, 6)   # base 10 (power 6 + STR 4)
	attack.fired_attack.hits_self = true
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.heal_amount).is_equal(10)
	assert_int(attack.resolved.target_hp_after).is_equal(max_hp - 2)


func test_heal_caps_at_max_hp_no_overheal() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 40})
	var target := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	var max_hp := target.get_max_hp()
	target.set_current_hp(max_hp - 3)   # less room left than the incoming heal

	var attack := _heal_attack(healer, target, 20)   # base way past what's missing
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.target_hp_after).is_equal(max_hp)   # clamped, never overshot


func test_heal_ignores_all_def() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.CON: 5})
	target.worn_armor = _make_armor(40)   # would floor an equal-sized damage hit at 0 (test_def_mitigation)
	var max_hp := target.get_max_hp()
	target.set_current_hp(max_hp - 50 if max_hp > 50 else 0)

	var attack := _heal_attack(healer, target, 6)   # base 10 (power 6 + STR 4)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.heal_amount).is_equal(10)   # full amount -- DEF was never asked


func test_heal_never_triggers_lethality_or_elemental_reactions() -> void:
	# A reaction that would have overkilled a damage attack must not fire at all on a heal --
	# the elemental stage is skipped entirely, not merely a no-op that happens to add nothing.
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	target.set_current_hp(1)   # a damage hit here would predict a kill

	var weapon := H.make_weapon(6)
	weapon.template.main_attack.heals = true
	weapon.template.main_attack.hits_allies = true
	weapon.template.main_attack.elemental_damage_type = Elemental.Element.FIRE
	healer.equipped_weapon = weapon
	var attack := H.stamped_attack(healer, target)

	var reaction := ElementalReaction.new()
	reaction.incoming_element = Elemental.Element.FIRE
	reaction.damage_bonus = 1000   # would massively overkill a damage attack
	var reactions: Array[ElementalReaction] = [reaction]

	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan, reactions)

	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.NONE)
	assert_array(attack.resolved.states_added).is_empty()
	assert_int(attack.resolved.heal_amount).is_equal(10)   # the reaction bonus never touched it


func test_heal_execution_matches_preview() -> void:
	# Law #2: replaying the resolved outcome must land HP on exactly what was previewed.
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	target.set_current_hp(5)

	var attack := _heal_attack(healer, target, 6)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	target.heal(attack.resolved.heal_amount)
	assert_int(target.get_current_hp()).is_equal(attack.resolved.target_hp_after)


# --- the readout seam: "what was HP before this hit?" ---
# Both outcome renderers need it (the queue row's icon overlay and AttackAction.get_outcome_summary),
# and it went through two wrong shapes before landing on a RECORDED field. Every case below is a
# real resolve, never a hand-built ResolvedOutcome: the two broken versions were both plausible
# arithmetic over the other fields, so a test that sets those fields by hand can only re-assert the
# formula it is supposed to be checking.

func test_queue_readout_of_a_heal_shows_the_real_hp_change() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.MHP: 20})
	target.set_current_hp(5)

	var attack := _heal_attack(healer, target, 6)   # base 10 (power 6 + STR 4)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.hp_before).is_equal(5)
	assert_int(attack.resolved.target_hp_after).is_equal(15)


func test_queue_readout_of_a_damage_hit_shows_the_real_hp_change() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20})
	target.set_current_hp(20)

	var attack := H.stamped_attack(attacker, target)   # base 7 (power 3 + STR 4)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.hp_before).is_equal(20)
	assert_int(attack.resolved.target_hp_after).is_equal(13)


func test_a_wasted_overheal_reports_the_hp_it_actually_started_from() -> void:
	# THE regression (reported in-game 2026-07-30). A heal is CLAMPED at max HP, so heal_amount is
	# the amount ATTEMPTED, not the delta applied -- which means hp_before can never be recovered by
	# subtracting it from target_hp_after. A full-HP unit healed for 5 stored after=20/heal=5 and
	# read back a pre-hit 15, inventing 5 points of damage that never landed and making a heal that
	# does nothing draw "15 -> 20" as though it had topped the unit back up.
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 1})
	var target := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.MHP: 20})
	var max_hp := target.get_max_hp()
	assert_int(target.get_current_hp()).is_equal(max_hp)   # starts full: every point is wasted

	var attack := _heal_attack(healer, target, 4)   # base 5 (power 4 + STR 1)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.heal_amount).is_equal(5)          # the magnitude is still reported...
	assert_int(attack.resolved.hp_before).is_equal(max_hp)       # ...but nothing moved
	assert_int(attack.resolved.target_hp_after).is_equal(max_hp)


func test_a_heal_reports_the_hp_before_its_own_phase_not_after_the_counters() -> void:
	# The in-game report, whole: Torv attacks someone who counters him for 7 (20 -> 13), and a heal
	# on Torv is queued in the same plan. Attacks resolve BEFORE counters (R7), so the heal lands
	# while Torv is still untouched and genuinely does nothing -- and the row has to say so. The old
	# derivation drew "15 -> 20", which reads as a heal that fired after the counter AND undid it.
	var torv := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 20, Stats.Stat.STR: 1})
	var enemy := H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(1, 0), {Stats.Stat.STR: 4})
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1), {Stats.Stat.STR: 1})
	assert_int(torv.get_current_hp()).is_equal(20)

	var torvs_swing := H.stamped_attack(torv, enemy)
	var heal := _heal_attack(healer, torv, 4)          # base 5, entirely wasted at full HP
	# A real CounterAttackAction, built the way SquadManager derives one -- plan.counters is typed
	# to it, and it is what carries the counter into the second (post-attack) resolver phase.
	var counter := CounterAttackAction.new()
	counter.init_counter(enemy, torv, enemy.movement.cell, torvs_swing)
	counter.fired_attack = enemy.get_counter_attack()   # base 7 (power 3 + STR 4)

	var plan := ResolvedPlan.new()
	plan.attacks.append(torvs_swing)
	plan.attacks.append(heal)
	plan.counters.append(counter)
	PlanResolver.resolve(plan)

	# the heal ran in the attack phase, against an undamaged Torv
	assert_int(heal.resolved.hp_before).is_equal(20)
	assert_int(heal.resolved.target_hp_after).is_equal(20)
	# and the counter, resolving after it, still reads the full 20 -> 13
	assert_int(counter.resolved.hp_before).is_equal(20)
	assert_int(counter.resolved.target_hp_after).is_equal(13)


func test_hp_before_threads_across_two_hits_in_one_pass() -> void:
	# It is the THREADED pre-hit HP (R4), not the live board value: the second hit of a pass must
	# report what the first one left behind, or two rows both claim to start from full HP.
	var first := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var second := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 30})
	target.set_current_hp(30)

	var plan := ResolvedPlan.new()
	plan.attacks.append(H.stamped_attack(first, target))    # 30 -> 23
	plan.attacks.append(H.stamped_attack(second, target))   # 23 -> 16
	PlanResolver.resolve(plan)

	assert_int(plan.attacks[0].resolved.hp_before).is_equal(30)
	assert_int(plan.attacks[1].resolved.hp_before).is_equal(23)
	assert_int(plan.attacks[1].resolved.target_hp_after).is_equal(16)

func test_transmutation_carving_can_heal_too() -> void:
	# `heals` lives on the shared AttackData base, so a carving qualifies exactly like a weapon
	# attack does -- no per-kind special-casing needed (alchemy-kit.md's "Soul Dew" is exactly
	# this shape: an alchemy-side heal, not a weapon-only mechanism).
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var target := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	target.set_current_hp(5)

	var carving := TransmutationData.new()
	carving.power = 8
	carving.heals = true
	carving.hits_allies = true
	healer.active_attack = carving
	var attack := H.stamped_attack(healer, target)

	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.heal_amount).is_equal(8)   # power + 0 aura (no sigils inscribed)
	assert_int(attack.resolved.damage).is_equal(0)
