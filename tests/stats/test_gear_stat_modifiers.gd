# The "-> gear" tail of the effective-stat chain (stats.md: "Effective stat = base -> limb
# substitution -> job nudge -> gear"). Documented since #56/#58 but only built 2026-07-24, when
# armor with a stat tax became real content. Two things are easy to get wrong and are pinned
# here: the tax must reach DERIVED readouts (the DEX->MOV band), and wear gates must NOT read
# it back (or which armor you can wear would depend on which armor you have on).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


func _taxing_armor(stat: Stats.Stat, amount: int, def_power: int = 0) -> ArmorData:
	var armor := ArmorData.new()
	armor.def_power = def_power
	armor.stat_modifiers[stat] = amount
	return armor


func test_worn_gear_shifts_the_effective_stat() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.DEX: 6})
	assert_int(unit.get_effective_stat(Stats.Stat.DEX)).is_equal(6)
	unit.worn_armor = _taxing_armor(Stats.Stat.DEX, -1)
	assert_int(unit.get_effective_stat(Stats.Stat.DEX)).is_equal(5)


func test_removing_gear_restores_the_stat() -> void:
	# Live derivation, not a stored mirror: dropping the armor must leave nothing behind.
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.DEX: 6})
	unit.worn_armor = _taxing_armor(Stats.Stat.DEX, -1)
	unit.worn_armor = null
	assert_int(unit.get_effective_stat(Stats.Stat.DEX)).is_equal(6)


func test_gear_never_writes_into_the_crisis_modifier_bag() -> void:
	# unit_instance.stat_modifiers is a STATEFUL add/subtract bag (Crisis surge) and is not
	# serialized. If armor pushed into it, a save/load would restore worn_armor but lose the
	# tax -- silently desyncing the stat. Gear must stay purely derived.
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.DEX: 6})
	unit.worn_armor = _taxing_armor(Stats.Stat.DEX, -1)
	assert_int(unit.unit_instance.stat_modifiers.get(Stats.Stat.DEX, 0)).is_equal(0)
	assert_int(unit.unit_instance.get_effective_stat(Stats.Stat.DEX)).is_equal(6)   # pre-gear, untouched


func test_a_dex_tax_can_cost_a_point_of_mov() -> void:
	# DEX 6 sits one point into the high MOV rung (dex_mov_band: 6-8 = +1), so a -1 tax drops
	# the wearer back to the mid rung. The tax reaching a DERIVED readout is the whole point.
	var nimble: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.DEX: 6})
	var before := nimble.get_mov()
	nimble.worn_armor = _taxing_armor(Stats.Stat.DEX, -1)
	assert_int(nimble.get_mov()).is_equal(before - 1)


func test_a_dex_tax_inside_a_band_costs_no_mov() -> void:
	# Bands are coarse ON PURPOSE (stats.md) -- default DEX 5 taxed to 4 stays in the same rung,
	# so the same armor is free for one unit and costly for another. That jaggedness is a goal.
	var average: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.DEX: 5})
	var before := average.get_mov()
	average.worn_armor = _taxing_armor(Stats.Stat.DEX, -1)
	assert_int(average.get_mov()).is_equal(before)


func test_wear_gates_ignore_the_wearers_own_gear_tax() -> void:
	# A DEX-ceiling piece must not become wearable just because you happen to have a -DEX piece
	# on. Gates ask about the BODY (base -> limb -> job), never the outfit -- otherwise
	# equip legality is swap-order-dependent and unexplainable to a player.
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.DEX: 5})
	var ceiling := ArmorData.new()
	ceiling.stat_maximums[Stats.Stat.DEX] = 4
	assert_bool(ceiling.can_equip(unit)).is_false()

	unit.worn_armor = _taxing_armor(Stats.Stat.DEX, -1)   # effective DEX is now 4...
	assert_int(unit.get_effective_stat(Stats.Stat.DEX)).is_equal(4)
	assert_bool(ceiling.can_equip(unit)).is_false()       # ...but the gate still says no


func test_gear_tax_composes_with_the_crisis_surge() -> void:
	# Two different layers of the same chain: the surge lands in unit_instance's bag, the tax
	# rides on top from gear. Both must show up in the one number the game reads.
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.DEX: 6})
	unit.unit_instance.stat_modifiers[Stats.Stat.DEX] = 2   # stand in for a surge
	unit.worn_armor = _taxing_armor(Stats.Stat.DEX, -1)
	assert_int(unit.get_effective_stat(Stats.Stat.DEX)).is_equal(7)


func test_a_taxing_armor_still_pays_its_def() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 5, Stats.Stat.DEX: 6})
	unit.worn_armor = _taxing_armor(Stats.Stat.DEX, -1, 4)
	assert_int(unit.get_effective_def()).is_equal(4)
	assert_int(unit.get_effective_stat(Stats.Stat.DEX)).is_equal(5)


func test_modifier_text_signs_the_tax() -> void:
	assert_str(_taxing_armor(Stats.Stat.DEX, -1).modifier_text()).is_equal("DEX -1")
	assert_str(_taxing_armor(Stats.Stat.CON, 2).modifier_text()).is_equal("CON +2")
	assert_str(ArmorData.new().modifier_text()).is_equal("")   # untaxed = nothing to say


func test_initialize_clears_the_crisis_modifier_bag() -> void:
	# stat_modifiers is BATTLE-scoped (the Crisis surge) but lives on the PERSISTENT instance,
	# and ScenarioUnitEntry never captures it. Before 2026-07-26 initialize() reset hp/will but
	# not this bag, so a unit whose surge was still applied at battle's end would carry +5 to
	# every scaling stat forever once instances survive missions. initialize() owns the reset.
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.STR: 6})
	unit.unit_instance.stat_modifiers[Stats.Stat.STR] = 5   # stand in for an applied surge
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(11)

	unit.unit_instance.initialize()   # what the next battle does
	assert_bool(unit.unit_instance.stat_modifiers.is_empty()).is_true()
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(6)
