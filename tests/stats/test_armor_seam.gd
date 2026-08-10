# The DEF x CON seam at the Unit level (#55): worn armor scaled by CON, zero DEF when naked,
# and the wear gates. Gates generalized 2026-07-24 from #55's single con_requirement to
# stat_minimums/stat_maximums -- a piece can demand a floor on one stat and a ceiling on another.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

func _make_armor(def_power: int, minimums: Dictionary = {}, flat_def: int = 0) -> ArmorData:
	var armor := ArmorData.new()
	armor.def_power = def_power
	armor.flat_def = flat_def
	for stat in minimums:
		armor.stat_minimums[stat] = minimums[stat]
	return armor

func test_naked_unit_has_zero_def_regardless_of_con() -> void:
	var unit := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 9})
	assert_int(unit.get_effective_def()).is_equal(0)

func test_worn_armor_scales_with_con() -> void:
	# The Unit-side wiring: the worn piece and the wearer's CON reach get_effective_def through
	# Stats.armor_def. Expected via that same doctrine function, never a literal (2026-08-10
	# sweep: CON_DEF_FACTOR is playtest-tunable), and the scaling claim itself is the comparison.
	var average := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 5})
	average.worn_armor = _make_armor(10)
	assert_int(average.get_effective_def()).is_equal(Stats.armor_def(10, 5))

	var sturdy := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(1, 0), {Stats.Stat.CON: 8})
	sturdy.worn_armor = _make_armor(10)
	assert_int(sturdy.get_effective_def()).is_equal(Stats.armor_def(10, 8))
	assert_int(sturdy.get_effective_def()).is_greater(average.get_effective_def())

func test_flat_def_does_not_scale_with_con() -> void:
	# The un-scaled term: identical on every body, so a CON-gated piece can pay out without
	# double-dipping the stat that already gated it.
	var frail := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 1})
	frail.worn_armor = _make_armor(0, {}, 3)
	assert_int(frail.get_effective_def()).is_equal(3)

	var sturdy := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(1, 0), {Stats.Stat.CON: 9})
	sturdy.worn_armor = _make_armor(0, {}, 3)
	assert_int(sturdy.get_effective_def()).is_equal(3)

func test_flat_and_scaled_terms_sum() -> void:
	# flat + scaled, expected off the scaled term alone (2026-08-10 sweep: no literal may ride
	# CON_DEF_FACTOR) -- the claim is the SUM, so only the +2 is this case's own.
	var unit := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 5})
	unit.worn_armor = _make_armor(10, {}, 2)
	assert_int(unit.get_effective_def()).is_equal(Stats.armor_def(10, 5) + 2)

func test_zero_con_still_earns_the_flat_term_only() -> void:
	# The "multiplier with no base" doctrine holds for the SCALED half: CON 0 zeroes it
	# entirely, and only the flat term survives.
	var unit := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 0})
	unit.worn_armor = _make_armor(10, {}, 4)
	assert_int(unit.get_effective_def()).is_equal(4)

# --- wear gates ---

func test_heavy_armor_con_gate() -> void:
	var heavy := _make_armor(12, {Stats.Stat.CON: 7})
	var weak := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 5})
	var strong := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(1, 0), {Stats.Stat.CON: 8})
	assert_bool(heavy.can_equip(weak)).is_false()
	assert_bool(heavy.can_equip(strong)).is_true()

func test_ungated_armor_admits_anyone() -> void:
	var light := _make_armor(3)   # no minimums, no maximums = no gate
	var frail := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 0})
	assert_bool(light.can_equip(frail)).is_true()

func test_stat_maximum_is_an_inverted_gate() -> void:
	var bulky := _make_armor(2)
	bulky.stat_maximums[Stats.Stat.DEX] = 4
	var nimble := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.DEX: 5})
	var slow := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(1, 0), {Stats.Stat.DEX: 4})
	assert_bool(bulky.can_equip(nimble)).is_false()
	assert_bool(bulky.can_equip(slow)).is_true()   # the boundary value passes

func test_minimum_and_maximum_gates_compose() -> void:
	# A piece can demand a floor on one stat and a ceiling on another at once.
	var braced := _make_armor(4, {Stats.Stat.CON: 6})
	braced.stat_maximums[Stats.Stat.DEX] = 4
	var qualified := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 7, Stats.Stat.DEX: 3})
	var too_nimble := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(1, 0), {Stats.Stat.CON: 7, Stats.Stat.DEX: 6})
	var too_weak := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(2, 0), {Stats.Stat.CON: 4, Stats.Stat.DEX: 3})
	assert_bool(braced.can_equip(qualified)).is_true()
	assert_bool(braced.can_equip(too_nimble)).is_false()
	assert_bool(braced.can_equip(too_weak)).is_false()

func test_requirement_text_reads_both_directions() -> void:
	var braced := _make_armor(4, {Stats.Stat.CON: 6})
	braced.stat_maximums[Stats.Stat.DEX] = 4
	var text := braced.requirement_text()
	assert_str(text).contains("CON 6+")
	assert_str(text).contains("DEX 4 or less")
	assert_str(_make_armor(3).requirement_text()).is_equal("")   # ungated = nothing to say
