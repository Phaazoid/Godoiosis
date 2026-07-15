# The 0-damage floor as a Law #2 guard (#55, stats.md CON riders): damage clamps at 0
# (never negative, never a heal), 0 is a LEGAL outcome, and a 0-damage hit is still a
# HIT — on-hit effects fire, and a downed target still dies to it (any hit on downed
# kills; ratified 2026-07-14). Preview and execution read the same resolver number.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# A hostile reaction that drags computed damage negative: FIRE, flat bonus, no states.
func _drain_reaction(bonus: int, adds_wet: bool = false) -> ElementalReaction:
	var reaction := ElementalReaction.new()
	reaction.incoming_element = Elemental.Element.FIRE
	reaction.damage_bonus = bonus
	if adds_wet:
		var adds: Array[Elemental.State] = [Elemental.State.WET]
		reaction.add_states = adds
	return reaction

func _fire_attack(attacker: Unit, target: Unit) -> AttackAction:
	var weapon := H.make_weapon(6)
	weapon.elemental_damage_type = Elemental.Element.FIRE
	attacker.equipped_weapon = weapon
	return AttackAction.create(attacker, attacker.movement.cell, target, target.movement.cell)

func test_negative_damage_floors_at_zero_and_never_heals() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20})
	var start_hp := target.get_current_hp()

	var attack := _fire_attack(attacker, target)   # base 10 (power 6 + STR 4)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	var reactions: Array[ElementalReaction] = [_drain_reaction(-100)]
	PlanResolver.resolve(plan, reactions)

	# Preview: exactly 0, honestly shown, survivable.
	assert_int(attack.resolved.damage).is_equal(0)
	assert_int(attack.resolved.target_hp_after).is_equal(start_hp)
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.NONE)

	# Execution seam: applying the resolved number leaves HP byte-identical — no heal.
	target.combat.apply_damage(attack.resolved.damage)
	assert_int(target.get_current_hp()).is_equal(start_hp)

func test_exactly_zero_is_a_legal_outcome() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20})

	var attack := _fire_attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	var reactions: Array[ElementalReaction] = [_drain_reaction(-10)]   # base 10 - 10 = exactly 0
	PlanResolver.resolve(plan, reactions)

	assert_int(attack.resolved.damage).is_equal(0)
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.NONE)

func test_zero_damage_hit_still_triggers_on_hit_effects() -> void:
	# The bait-out rider: a 0-damage hit is still a HIT. The resolver must not early-out —
	# reaction state deltas apply, so future one-use defensives/on-hit reactions consume.
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20})

	var attack := _fire_attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	var reactions: Array[ElementalReaction] = [_drain_reaction(-100, true)]
	PlanResolver.resolve(plan, reactions)

	assert_int(attack.resolved.damage).is_equal(0)
	assert_bool(attack.resolved.skipped).is_false()
	assert_array(attack.resolved.states_added).contains([Elemental.State.WET])

func test_zero_damage_hit_on_downed_target_previews_kill() -> void:
	# Any hit on a downed unit kills it — even a 0-damage one (it IS a hit). The queue
	# must show the skull for it (Law #2 mirrors Unit.take_damage's DOWNED branch).
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20})
	target.lifecycle_state = Unit.LifecycleState.DOWNED

	var attack := _fire_attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	var reactions: Array[ElementalReaction] = [_drain_reaction(-100)]
	PlanResolver.resolve(plan, reactions)

	assert_int(attack.resolved.damage).is_equal(0)
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)
