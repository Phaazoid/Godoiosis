# Guard (#414, docs/design/standing-reactions.md): TOTAL VICTIM SUBSTITUTION. A damaging hit aimed at
# a warded unit resolves against the blocker instead — the blocker's DEF and armour plus the brace
# bonus, the ENTIRE payload, from the blocker's own cell — and the ward takes nothing.
#
# The mechanism is a victim rewrite on the DERIVED action inside the resolve pass, which is what
# makes "every pipeline stage just runs with a different victim" literal rather than aspirational.
# So these cases assert the STAGES, not the headline: whose armour mitigated, whose cell the shove
# was measured from, whose HP the rung was read against. A test that only checked "the blocker lost
# HP" would pass against an implementation that copied a number across and got every stage wrong.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


# attacker STR 4 + weapon power 6 = base 10, the same arithmetic test_def_mitigation.gd uses.
func _attacker(cell: Vector2i) -> Unit:
	return H.spawn_solo(self, _sm, ENEMY, cell, {Stats.Stat.STR: 4}, true, 6)


# Weaponless on purpose: a fixture defender that cannot counter keeps the plan to the one hit.
func _defender(cell: Vector2i, hp := 40) -> Unit:
	return H.spawn_solo(self, _sm, PLAYER, cell, {Stats.Stat.MHP: hp}, false)


func _flat_armor(flat_def: int) -> ArmorData:
	var armor := ArmorData.new()
	armor.flat_def = flat_def   # flat, so the expectation never rides CON or CON_DEF_FACTOR
	return armor


func _brace_armor() -> ArmorData:
	var ability := AbilityData.new()
	ability.id = Abilities.Id.BRACE
	var armor := ArmorData.new()
	armor.granted_abilities = [ability]
	return armor


func _resolve(plan: ResolvedPlan, board: BoardContext = null) -> void:
	var no_reactions: Array[ElementalReaction] = []
	var no_terrain: Array[TerrainReaction] = []
	PlanResolver.resolve(plan, no_reactions, board, no_terrain)


func _guarded_plan(blocker: Unit, ward: Unit, ward_range := 1) -> ResolvedPlan:
	var plan := ResolvedPlan.new()
	plan.guards.append(GuardWard.arm(blocker, ward, ward_range))
	return plan


func _board_with(units_in: Array) -> BoardContext:
	var units: Array[Unit] = []
	units.assign(units_in)
	return BoardContext.new(_sm.grid, units, _sm)


# --- the substitution itself ---------------------------------------------------------------

func test_the_blocker_takes_the_hit_and_the_ward_is_never_touched() -> void:
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))

	var plan := _guarded_plan(blocker, ward)
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_object(atk.target).is_same(blocker)          # the victim really moved
	assert_object(atk.blocked_for).is_same(ward)        # and the aim is still recorded
	assert_int(atk.resolved.damage).is_equal(10)
	assert_int(atk.resolved.hp_before).is_equal(blocker.get_current_hp())
	# The ward has no threaded entry at all: nothing in the pass ever reached it.
	assert_bool(plan.hypo.has(ward)).is_false()


func test_an_unguarded_hit_is_untouched() -> void:
	# The control the three pass-through cases below are measured against.
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))

	var plan := ResolvedPlan.new()
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_object(atk.target).is_same(ward)
	assert_object(atk.blocked_for).is_null()
	assert_int(atk.resolved.brace_bonus).is_equal(0)


# --- the stages run with the NEW victim, not the old one ------------------------------------

func test_the_blockers_armour_mitigates_and_the_wards_does_not() -> void:
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))
	ward.worn_armor = _flat_armor(4)     # the ward's plate is irrelevant: it is not being hit

	var plan := _guarded_plan(blocker, ward)
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_int(atk.resolved.damage).is_equal(10)   # unmitigated -- the BLOCKER is naked


func test_the_blockers_own_armour_does_mitigate() -> void:
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))
	blocker.worn_armor = _flat_armor(4)

	var plan := _guarded_plan(blocker, ward)
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_int(atk.resolved.damage).is_equal(10 - blocker.get_effective_def())
	assert_int(blocker.get_effective_def()).is_equal(4)


func test_the_brace_bonus_is_added_on_top_of_the_blockers_def() -> void:
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))
	blocker.worn_armor = _brace_armor()

	var plan := _guarded_plan(blocker, ward)
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_int(atk.resolved.brace_bonus).is_equal(Abilities.BRACE_DEF_BONUS)
	assert_int(atk.resolved.damage).is_equal(10 - Abilities.BRACE_DEF_BONUS)


func test_the_brace_bonus_only_applies_to_a_hit_that_was_actually_blocked() -> void:
	# Same kit, no Guard: Brace is a block-quality knob, never standing DEF.
	var attacker := _attacker(Vector2i(0, 0))
	var victim := _defender(Vector2i(1, 0))
	victim.worn_armor = _brace_armor()

	var plan := ResolvedPlan.new()
	var atk := H.stamped_attack(attacker, victim)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_int(atk.resolved.brace_bonus).is_equal(0)
	assert_int(atk.resolved.damage).is_equal(10)


func test_the_shove_is_measured_from_the_blockers_cell() -> void:
	# The payload is the WHOLE payload, resolved from the blocker's own cell: attacker at 0,
	# ward at 1, blocker at 2, so the knockback direction is attacker -> BLOCKER and the blocker
	# is the one who moves. Aimed at the ward's cell it would have pushed the ward instead.
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack.knockback = 1

	var plan := _guarded_plan(blocker, ward)
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan, _board_with([attacker, ward, blocker]))

	assert_bool(atk.resolved.knockback_applied).is_true()
	assert_that(atk.resolved.knockback_from).is_equal(Vector2i(2, 0))
	assert_that(atk.resolved.knockback_to).is_equal(Vector2i(3, 0))
	assert_bool(plan.hypo.has(ward)).is_false()   # the ward never moved and never will


func test_the_lethality_rung_is_read_against_the_blocker() -> void:
	# A hit that would barely scratch the ward fells the blocker who steps in front of it —
	# "bodyguarding with a second medic is a sacrifice", the doc's own words, as a rung.
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0), 60)
	var blocker := _defender(Vector2i(2, 0), 8)

	var plan := _guarded_plan(blocker, ward)
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_that(atk.resolved.lethality).is_not_equal(ResolvedOutcome.Lethality.NONE)
	# And the ward, on the identical hit, would have shrugged it off.
	assert_that(LethalityRules.predict(LethalityRules.situation_for(ward), atk.resolved.damage)) \
		.is_equal(ResolvedOutcome.Lethality.NONE)


# --- what passes through ---------------------------------------------------------------------

func test_a_heal_passes_through_to_its_target() -> void:
	# Nobody wants the tank intercepting the medic's heal.
	var healer := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))
	(healer.get_equipped_weapon() as WeaponInstance).template.main_attack.heals = true
	ward.take_damage(5)

	var plan := _guarded_plan(blocker, ward)
	var atk := H.stamped_attack(healer, ward)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_object(atk.target).is_same(ward)
	assert_object(atk.blocked_for).is_null()
	assert_int(atk.resolved.heal_amount).is_greater(0)


func test_a_pure_utility_attack_passes_through() -> void:
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack.deals_no_damage = true

	var plan := _guarded_plan(blocker, ward)
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_object(atk.target).is_same(ward)
	assert_object(atk.blocked_for).is_null()


func test_the_pierce_flag_ignores_the_guard() -> void:
	# The first entry in Guard's authored counterplay set.
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack.pierces_guard = true

	var plan := _guarded_plan(blocker, ward)
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_object(atk.target).is_same(ward)
	assert_object(atk.blocked_for).is_null()
	assert_int(atk.resolved.damage).is_equal(10)


func test_a_substituted_hit_is_never_guard_bait() -> void:
	# No substitution chains (ON HOLD, not buried). The blocker has a bodyguard of its own; the
	# hit it absorbed stops with it rather than walking down the conga line.
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))
	var blocker := _defender(Vector2i(2, 0))
	var second := _defender(Vector2i(3, 0))

	var plan := _guarded_plan(blocker, ward)
	plan.guards.append(GuardWard.arm(second, blocker, 1))
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_object(atk.target).is_same(blocker)
	assert_bool(plan.hypo.has(second)).is_false()


func test_a_guard_cannot_shield_someone_from_its_own_swing() -> void:
	# Only reachable through an AoE counter — a unit gets one main action, so it can never both
	# Guard and attack in the same turn — and absorbing your own attack for somebody is incoherent.
	var attacker := _attacker(Vector2i(0, 0))
	var ward := _defender(Vector2i(1, 0))

	var plan := _guarded_plan(attacker, ward)
	var atk := H.stamped_attack(attacker, ward)
	plan.attacks.append(atk)
	_resolve(plan)

	assert_object(atk.target).is_same(ward)
	assert_object(atk.blocked_for).is_null()
