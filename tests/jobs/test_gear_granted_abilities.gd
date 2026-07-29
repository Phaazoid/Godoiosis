# Gear as an ability source (#90): a unit's live kit is everything PERSISTENT (innate + jobs, on
# UnitInstance) UNION whatever worn gear grants. Derived live off worn_armor, never stored — the
# same rule the gear stat tax follows (tests/stats/test_gear_stat_modifiers.gd) for the same
# reason: a stored mirror would restore worn_armor on load and silently lose what it granted.
#
# Unit is THE answer here. UnitInstance's version is the persistent inner layer and is asserted
# to stay ignorant of gear, because a reader that stopped at it would work in some systems and
# not others — the split-brain this seam exists to make unrepresentable.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const F := preload("res://tests/support/job_fixtures.gd")

var _tank: JobData
var _tank_snap: Dictionary

func before_test() -> void:
	_tank = JobCatalog.get_job("tank")
	_tank_snap = F.snapshot(_tank)

func after_test() -> void:
	F.restore(_tank, _tank_snap)

func _ability(id: Abilities.Id) -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	return a

func _granting_armor(id: Abilities.Id) -> ArmorData:
	var armor := ArmorData.new()
	armor.granted_abilities = [_ability(id)]
	return armor

func _count(unit: Unit, id: Abilities.Id) -> int:
	var n := 0
	for ability in unit.get_live_abilities():
		if ability.id == id:
			n += 1
	return n


func test_a_bare_unit_has_no_abilities() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0))
	assert_int(unit.get_live_abilities().size()).is_equal(0)
	assert_bool(unit.has_live_ability(Abilities.Id.IRON_WILL)).is_false()


func test_worn_gear_grants_its_abilities() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0))
	unit.worn_armor = _granting_armor(Abilities.Id.IRON_WILL)
	assert_bool(unit.has_live_ability(Abilities.Id.IRON_WILL)).is_true()


func test_removing_gear_takes_the_grant_with_it() -> void:
	# Live derivation, not a stored mirror: dropping the piece must leave nothing behind.
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0))
	unit.worn_armor = _granting_armor(Abilities.Id.IRON_WILL)
	unit.worn_armor = null
	assert_bool(unit.has_live_ability(Abilities.Id.IRON_WILL)).is_false()


func test_carrying_armor_without_wearing_it_grants_nothing() -> void:
	# Armor rides the SAME inventory as weapons but fills a different slot (#89). Holding the
	# piece is not wearing it, and only the worn one contributes.
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0))
	unit.add_item(_granting_armor(Abilities.Id.IRON_WILL))
	assert_bool(unit.has_live_ability(Abilities.Id.IRON_WILL)).is_false()


func test_a_gear_grant_never_reaches_the_persistent_instance() -> void:
	# The persistence seam: gear is transient state on Unit, so nothing it grants may be visible
	# to UnitInstance. If this ever fails, a save/load either loses the grant or duplicates it.
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0))
	unit.worn_armor = _granting_armor(Abilities.Id.IRON_WILL)
	assert_bool(unit.has_live_ability(Abilities.Id.IRON_WILL)).is_true()
	assert_int(unit.unit_instance.get_live_abilities().size()).is_equal(0)


func test_gear_composes_with_a_job_pool() -> void:
	_tank.ability_pool = [_ability(Abilities.Id.TAUNT)]
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0))
	unit.unit_instance.add_job("tank")
	unit.worn_armor = _granting_armor(Abilities.Id.IRON_WILL)
	assert_bool(unit.has_live_ability(Abilities.Id.TAUNT)).is_true()
	assert_bool(unit.has_live_ability(Abilities.Id.IRON_WILL)).is_true()


func test_the_same_ability_from_job_and_gear_appears_once() -> void:
	# One merge for all three sources, so gear cannot dedupe differently from jobs.
	_tank.ability_pool = [_ability(Abilities.Id.TAUNT)]
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0))
	unit.unit_instance.add_job("tank")
	unit.worn_armor = _granting_armor(Abilities.Id.TAUNT)
	assert_int(_count(unit, Abilities.Id.TAUNT)).is_equal(1)


func test_gear_grants_stack_with_innate_abilities() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0))
	unit.unit_instance.data.innate_abilities = [_ability(Abilities.Id.WATERWALK)]
	unit.worn_armor = _granting_armor(Abilities.Id.IRON_WILL)
	assert_bool(unit.has_live_ability(Abilities.Id.WATERWALK)).is_true()
	assert_bool(unit.has_live_ability(Abilities.Id.IRON_WILL)).is_true()


func test_armor_granting_nothing_leaves_the_kit_alone() -> void:
	# The overwhelmingly common case: granted_abilities defaults empty, so plain armor is inert
	# here and every existing .tres stays correct without touching it.
	_tank.ability_pool = [_ability(Abilities.Id.TAUNT)]
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0))
	unit.unit_instance.add_job("tank")
	unit.worn_armor = ArmorData.new()
	assert_int(unit.get_live_abilities().size()).is_equal(1)
	assert_bool(unit.has_live_ability(Abilities.Id.TAUNT)).is_true()


func test_a_wear_gate_strip_drops_the_grant() -> void:
	# Forced unequip (#112): gear you no longer qualify for comes off inside _settle_stat_change.
	# Its grants must leave with it — which they do for free, because the kit is derived rather
	# than cached. There is no invalidation step here, and that is the design.
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.DEX: 5})
	var demanding := _granting_armor(Abilities.Id.WATERWALK)
	demanding.stat_minimums[Stats.Stat.DEX] = 5
	unit.worn_armor = demanding
	assert_bool(unit.has_live_ability(Abilities.Id.WATERWALK)).is_true()

	unit.apply_stat_effect(StatEffect.make("Chill", {Stats.Stat.DEX: -1}))
	assert_object(unit.worn_armor).is_null()
	assert_bool(unit.has_live_ability(Abilities.Id.WATERWALK)).is_false()
