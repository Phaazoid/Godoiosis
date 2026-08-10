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


func test_gear_is_derived_and_stores_nothing() -> void:
	# Gear must stay purely DERIVED: if wearing a piece stored its tax anywhere, a save/load would
	# restore worn_armor and re-apply it, or lose it, and the stat would silently desync. Nothing
	# below the Unit sees the tax, and no stored effect is created by wearing.
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.DEX: 6})
	unit.worn_armor = _taxing_armor(Stats.Stat.DEX, -1)
	assert_bool(unit.stat_effects.is_empty()).is_true()
	assert_int(unit.unit_instance.get_effective_stat(Stats.Stat.DEX)).is_equal(6)   # pre-gear, untouched
	assert_int(unit.get_body_stat(Stats.Stat.DEX)).is_equal(6)                      # body excludes gear


func test_a_dex_tax_can_cost_a_point_of_mov() -> void:
	# DEX authored one point past the rung threshold (2026-08-10 sweep -- the threshold is
	# playtest-tunable, so the POSITION is authored, never the number), so a -1 tax drops the
	# wearer back a rung. The tax reaching a DERIVED readout is the whole point.
	var nimble: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0),
		{Stats.Stat.DEX: Stats.DEX_MOV_MID_MAX + 1})
	var before := nimble.get_mov()
	nimble.worn_armor = _taxing_armor(Stats.Stat.DEX, -1)
	assert_int(nimble.get_mov()).is_equal(before - 1)


func test_a_dex_tax_inside_a_band_costs_no_mov() -> void:
	# Bands are coarse ON PURPOSE (stats.md) -- a top-of-rung DEX taxed one stays in its rung,
	# so the same armor is free for one unit and costly for another. That jaggedness is a goal.
	# Premise: the rung really is at least two wide, or this case is measuring nothing.
	assert_int(Stats.dex_mov_band(Stats.DEX_MOV_MID_MAX - 1)).is_equal(Stats.dex_mov_band(Stats.DEX_MOV_MID_MAX))
	var average: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0),
		{Stats.Stat.DEX: Stats.DEX_MOV_MID_MAX})
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


func test_gear_tax_composes_with_a_temporary_effect() -> void:
	# Two adjacent stages of the same chain: the effect is STORED on the unit, the tax is DERIVED
	# from the worn piece. Both must show up in the one number the game reads.
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.DEX: 6})
	unit.apply_stat_effect(StatEffect.make("Tonic", {Stats.Stat.DEX: 2}))
	unit.worn_armor = _taxing_armor(Stats.Stat.DEX, -1)
	assert_int(unit.get_effective_stat(Stats.Stat.DEX)).is_equal(7)


func test_a_taxing_armor_still_pays_its_def() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 5, Stats.Stat.DEX: 6})
	unit.worn_armor = _taxing_armor(Stats.Stat.DEX, -1, 4)
	# Expected DEF via the doctrine function (2026-08-10 sweep -- CON_DEF_FACTOR is playtest-
	# tunable); this case's own claim is only that the tax doesn't eat the payout.
	assert_int(unit.get_effective_def()).is_equal(Stats.armor_def(4, unit.get_effective_stat(Stats.Stat.CON)))
	assert_int(unit.get_effective_def()).is_greater(0)
	assert_int(unit.get_effective_stat(Stats.Stat.DEX)).is_equal(5)


func test_modifier_text_signs_the_tax() -> void:
	assert_str(_taxing_armor(Stats.Stat.DEX, -1).modifier_text()).is_equal("DEX -1")
	assert_str(_taxing_armor(Stats.Stat.CON, 2).modifier_text()).is_equal("CON +2")
	assert_str(ArmorData.new().modifier_text()).is_equal("")   # untaxed = nothing to say


func test_temporary_effects_never_reach_the_persistent_instance() -> void:
	# This case used to guard initialize()'s reset of UnitInstance.stat_modifiers — a BATTLE-scoped
	# bag parked on the PERSISTENT instance, which had already gone permanent once by being missed.
	# #112 removed the hazard instead of guarding it: temporary effects live on the transient Unit,
	# so they cannot outlive a battle and there is no reset to forget. The instance is now
	# base -> limb -> jobs and nothing else, which is why re-initializing changes nothing here.
	var unit: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.STR: 6})
	unit.apply_stat_effect(StatEffect.make("Surge", {Stats.Stat.STR: 5}))
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(11)
	assert_int(unit.unit_instance.get_effective_stat(Stats.Stat.STR)).is_equal(6)

	unit.unit_instance.initialize()   # what the next battle does
	assert_int(unit.unit_instance.get_effective_stat(Stats.Stat.STR)).is_equal(6)
