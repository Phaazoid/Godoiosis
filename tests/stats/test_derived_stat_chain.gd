# Every DERIVED readout must consume the FINISHED effective stat — gear stage included (#106).
#
# stats.md's chain is base -> limb -> jobs -> temporary effects -> gear, and its last stage lives on
# Unit (worn_armor), one layer above UnitInstance. Three readouts derive off that chain. MOV was
# migrated to take the finished value on 2026-07-27; max HP and effective LDR were not, so they
# rebuilt the chain locally from inside UnitInstance and silently stopped one stage short.
#
# THE LAW THIS FILE PINS: a stat's chain is expressed once, at the layer that can see every stage.
# Add a stage to Unit.get_effective_stat and every case below still has to pass — which is the
# only thing standing between a new stage and quietly missing a derivation. Add a derivation and
# it gets a case here.
#
# The bug was invisible on main for one reason only: the single authored stat modifier in the game
# is RivetedMail's DEX -1, and neither max HP nor LDR reads DEX. The first armor to author CON or
# PER would have made it real with no error and no failing test.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


# Band-crossing amounts are deliberate: a modifier that stays inside a rung proves nothing,
# because bands are coarse on purpose (stats.md).
func _armor(mods: Dictionary, def_power: int = 0) -> ArmorData:
	var armor := ArmorData.new()
	armor.def_power = def_power
	for stat in mods:
		armor.stat_modifiers[stat] = mods[stat]
	return armor


# --- one case per derivation ---

func test_gear_con_reaches_max_hp() -> void:
	# CON 5 -> 10 crosses con_mhp_band (0 -> +2). The same +CON already moved DEF, which is what
	# made the split visible: one armor, two CON-driven readouts, only one of them listening.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO,
		{Stats.Stat.CON: 5, Stats.Stat.MHP: 20}, false)
	assert_int(unit.get_max_hp()).is_equal(20)

	unit.worn_armor = _armor({Stats.Stat.CON: 5})

	assert_int(unit.get_effective_stat(Stats.Stat.CON)).is_equal(10)
	assert_int(unit.get_max_hp()).is_equal(22)


func test_gear_dex_reaches_mov() -> void:
	# The control case — MOV already took the finished value, and this is what the other two
	# were migrated to match. If this one ever regresses, all three are wrong together.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.DEX: 6}, false)
	var before := unit.get_mov()
	unit.worn_armor = _armor({Stats.Stat.DEX: -3})
	assert_int(unit.get_mov()).is_less(before)


func test_gear_per_reaches_the_ldr_band() -> void:
	# PER 5 -> 10 crosses per_ldr_band (0 -> +1). Before #106 the inspect panel printed the VALUE
	# from the gear-less derivation and the BAND TERM from the gear-inclusive stat, so the readout
	# contradicted its own tooltip: "LDR 5" over "LDR 5 +1 PER band".
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO,
		{Stats.Stat.LDR: 5, Stats.Stat.PER: 5}, false)
	assert_int(unit.get_effective_ldr()).is_equal(5)

	unit.worn_armor = _armor({Stats.Stat.PER: 5})

	assert_int(unit.get_effective_ldr()).is_equal(6)
	assert_int(Stats.per_ldr_band(unit.get_effective_stat(Stats.Stat.PER))).is_equal(1)   # agrees with the value


func test_gear_con_reaches_def() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.CON: 5}, false)
	unit.worn_armor = _armor({Stats.Stat.CON: 5}, 4)
	assert_int(unit.get_effective_def()).is_equal(Stats.armor_def(4, 10))


# The band table itself, moved off tests/stats/test_unit_instance_stats.gd when the derivation
# moved up to Unit (#106). Same three rungs, now read through the full chain.
func test_effective_ldr_consumes_per_band() -> void:
	for per_and_expected: Array in [[9, 6], [5, 5], [2, 4]]:
		var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO,
			{Stats.Stat.LDR: 5, Stats.Stat.PER: per_and_expected[0]}, false)
		assert_int(unit.get_effective_ldr()).is_equal(per_and_expected[1])


# --- LDR is not cosmetic ---

func test_gear_ldr_reaches_squad_capacity() -> void:
	# Squad.max_size() is 1 + eLDR/MEMBER_LDR_COST, so a gear-less eLDR silently caps how many
	# units a leader can field. LDR 3 -> 6 buys two more slots at cost 2.
	var manager: SquadManager = H.make_manager(self)
	var leader: Unit = H.spawn_solo(self, manager, Team.Faction.PLAYER, Vector2i.ZERO,
		{Stats.Stat.LDR: 3}, false)
	assert_int(leader.squad.max_size()).is_equal(1 + 3 / Squad.MEMBER_LDR_COST)

	leader.worn_armor = _armor({Stats.Stat.LDR: 3})

	assert_int(leader.squad.max_size()).is_equal(1 + 6 / Squad.MEMBER_LDR_COST)


# --- the clamp inherits whatever max HP reads ---

func test_a_heal_can_fill_gear_granted_hp() -> void:
	# set_current_hp clamps to max, so a gear-less max is not just a wrong readout: it is a
	# ceiling. Before #106 the surplus HP that +CON armor grants could never be occupied.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO,
		{Stats.Stat.CON: 5, Stats.Stat.MHP: 20}, false)
	unit.worn_armor = _armor({Stats.Stat.CON: 5})

	unit.set_current_hp(999)

	assert_int(unit.get_current_hp()).is_equal(22)


func test_removing_armor_clamps_hp_back_down() -> void:
	# The other side of the same ceiling: taking the armor off must not leave a unit above max.
	# Nothing re-clamps on unequip, so the guarantee is that the NEXT write settles it.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO,
		{Stats.Stat.CON: 5, Stats.Stat.MHP: 20}, false)
	unit.worn_armor = _armor({Stats.Stat.CON: 5})
	unit.set_current_hp(22)

	unit.worn_armor = null
	unit.set_current_hp(unit.get_current_hp())

	assert_int(unit.get_current_hp()).is_equal(20)


func test_damage_is_taken_against_the_gear_aware_max() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO,
		{Stats.Stat.CON: 5, Stats.Stat.MHP: 20}, false)
	unit.worn_armor = _armor({Stats.Stat.CON: 5})
	unit.set_current_hp(22)

	unit.take_damage(3)

	assert_int(unit.get_current_hp()).is_equal(19)


# --- the save/load path (not listed in #106; found by probing apply_unit_state) ---

func test_round_trip_keeps_gear_granted_hp() -> void:
	# ScenarioUnitEntry.apply_unit_state restores worn_armor BEFORE it writes HP, so the HP write
	# has to see gear. While it went through UnitInstance directly, every save/load of an armored
	# unit quietly shed the band's worth of HP -- a data-losing round trip, not just a bad readout.
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO,
		{Stats.Stat.CON: 5, Stats.Stat.MHP: 20}, false)
	a.worn_armor = _armor({Stats.Stat.CON: 5})
	a.set_current_hp(22)

	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(a)
	assert_int(entry.current_hp).is_equal(22)

	var b: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(1, 0),
		{Stats.Stat.CON: 5, Stats.Stat.MHP: 20}, false)
	entry.apply_unit_state(b)

	assert_object(b.worn_armor).is_not_null()
	assert_int(b.get_max_hp()).is_equal(22)
	assert_int(b.get_current_hp()).is_equal(22)


# --- the gate doctrine is unchanged: gates ask about the BODY, derivations ask about the OUTFIT ---

func test_wear_gates_still_ignore_the_wearers_own_gear() -> void:
	# #106 widened what READS gear; it must not widen what GATES on it. ArmorData.can_equip
	# deliberately reads UnitInstance.get_effective_stat (pre-gear) so equip legality can't
	# depend on swap order -- see tests/stats/test_gear_stat_modifiers.gd for the full doctrine.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.CON: 5}, false)
	var gated := ArmorData.new()
	gated.stat_minimums[Stats.Stat.CON] = 8
	assert_bool(gated.can_equip(unit)).is_false()

	unit.worn_armor = _armor({Stats.Stat.CON: 5})            # effective CON is now 10...
	assert_int(unit.get_effective_stat(Stats.Stat.CON)).is_equal(10)
	assert_bool(gated.can_equip(unit)).is_false()            # ...but the gate still says no
