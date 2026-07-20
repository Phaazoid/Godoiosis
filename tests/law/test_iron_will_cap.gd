# Iron Will (Passive, #61, jobs.md "The ability chassis"): a deterministic per-hit damage cap
# on the holder, applied in PlanResolver right after the 0-damage floor so it actually protects
# from a would-be down/kill, not just the displayed number (Law #2). Preview and execution read
# the same resolver number — the same guarantee test_damage_floor.gd relies on for the floor.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const F := preload("res://tests/support/job_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager
var _tank: JobData
var _tank_snap: Dictionary

func before_test() -> void:
	_sm = H.make_manager(self)
	_tank = JobCatalog.get_job("tank")
	_tank_snap = F.snapshot(_tank)

func after_test() -> void:
	F.restore(_tank, _tank_snap)

func _give_iron_will(unit: Unit) -> void:
	var ability := AbilityData.new()
	ability.id = Abilities.Id.IRON_WILL
	_tank.ability_pool = [ability]
	unit.unit_instance.add_job("tank")

func _attack(attacker: Unit, target: Unit) -> AttackAction:
	return AttackAction.create(attacker, attacker.movement.cell, target, target.movement.cell)

func test_iron_will_caps_damage_above_the_cap() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 20}, true, 20)
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	_give_iron_will(target)

	var plan := ResolvedPlan.new()
	plan.attacks.append(_attack(attacker, target))
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_int(plan.attacks[0].resolved.damage).is_equal(Abilities.IRON_WILL_DAMAGE_CAP)

func test_iron_will_does_not_raise_a_hit_below_the_cap() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 1}, true, 1)
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	_give_iron_will(target)

	var plan := ResolvedPlan.new()
	plan.attacks.append(_attack(attacker, target))
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	var damage: int = plan.attacks[0].resolved.damage
	assert_bool(damage < Abilities.IRON_WILL_DAMAGE_CAP).is_true()

func test_iron_will_protects_from_a_would_be_down() -> void:
	# The load-bearing placement check: the cap must land BEFORE lethality is predicted, or it
	# would only shrink the displayed number without actually saving the holder.
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 20}, true, 20)
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 10})
	_give_iron_will(target)

	var plan := ResolvedPlan.new()
	plan.attacks.append(_attack(attacker, target))
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_that(plan.attacks[0].resolved.lethality).is_equal(ResolvedOutcome.Lethality.NONE)

func test_iron_will_composes_with_the_zero_floor() -> void:
	# A hit that would floor to 0 anyway stays 0 — the cap never raises it back up.
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20})
	_give_iron_will(target)
	var weapon := H.make_weapon(6)
	weapon.template.main_attack.elemental_damage_type = Elemental.Element.FIRE
	attacker.equipped_weapon = weapon

	var drain := ElementalReaction.new()
	drain.incoming_element = Elemental.Element.FIRE
	drain.damage_bonus = -100

	var plan := ResolvedPlan.new()
	plan.attacks.append(_attack(attacker, target))
	var reactions: Array[ElementalReaction] = [drain]
	PlanResolver.resolve(plan, reactions)

	assert_int(plan.attacks[0].resolved.damage).is_equal(0)
