# DEF mitigation (#84): DEF finally reduces damage in the resolver. Before this it was a
# display-only readout (Unit.get_effective_def fed the inspect panel and nothing else) — the
# resolver never subtracted it. Now a flat gear+terrain reduction subtracts AFTER elemental
# scaling and BEFORE the 0-floor (Law: 0-damage hits are legal), with Iron Will still the last
# clamp. A revved Chainsword attacker pierces it entirely — the payload of the family's Rev
# mechanic. Terrain Cover is still 0 in code (no Cover pass yet), so armor is the live term.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _make_armor(def_power: int) -> ArmorData:
	var armor := ArmorData.new()
	armor.def_power = def_power
	return armor


# A plain physical attack, base = power + STR. make_weapon() yields a Chainsword instance (#82),
# so the same helper covers both the mitigated and the revved-pierce cases.
func _attack(attacker: Unit, target: Unit) -> AttackAction:
	attacker.equipped_weapon = H.make_weapon(6)
	return AttackAction.create(attacker, attacker.movement.cell, target, target.movement.cell)


func test_def_subtracts_from_damage() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	target.worn_armor = _make_armor(4)   # DEF 4 at CON 5 (armor_def(4,5) == 4)

	var attack := _attack(attacker, target)   # base 10 (power 6 + STR 4)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.damage).is_equal(6)   # 10 - 4 DEF


func test_naked_target_takes_full_damage() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20})

	var attack := _attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.damage).is_equal(10)   # no armor -> no mitigation


func test_revved_chainsword_pierces_def() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	target.worn_armor = _make_armor(4)

	var attack := _attack(attacker, target)
	(attacker.equipped_weapon as ChainswordWeaponInstance).rev()
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.damage).is_equal(10)   # DEF ignored entirely while revved


func test_def_never_drives_damage_below_zero() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	target.worn_armor = _make_armor(40)   # DEF far above the incoming hit

	var attack := _attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.damage).is_equal(0)   # floored at 0, never negative, never a heal
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.NONE)
