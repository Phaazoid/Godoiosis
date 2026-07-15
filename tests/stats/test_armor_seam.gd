# The DEF x CON seam at the Unit level (#55): worn fixture armor scaled by CON,
# zero DEF when naked, and the heavy-armor CON gate stub. Armor CONTENT is a later
# pass — one fixture item proves the math end-to-end.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

func _make_armor(def_power: int, con_requirement: int = 0) -> ArmorData:
	var armor := ArmorData.new()
	armor.def_power = def_power
	armor.con_requirement = con_requirement
	return armor

func test_naked_unit_has_zero_def_regardless_of_con() -> void:
	var unit := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 9})
	assert_int(unit.get_effective_def()).is_equal(0)

func test_worn_armor_scales_with_con() -> void:
	var average := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 5})
	average.worn_armor = _make_armor(10)
	assert_int(average.get_effective_def()).is_equal(10)   # printed value on the default body

	var sturdy := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(1, 0), {Stats.Stat.CON: 8})
	sturdy.worn_armor = _make_armor(10)
	assert_int(sturdy.get_effective_def()).is_equal(16)

func test_heavy_armor_con_gate() -> void:
	var heavy := _make_armor(12, 7)
	var weak := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 5})
	var strong := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(1, 0), {Stats.Stat.CON: 8})
	assert_bool(heavy.can_equip(weak)).is_false()
	assert_bool(heavy.can_equip(strong)).is_true()

func test_ungated_armor_admits_anyone() -> void:
	var light := _make_armor(3)   # con_requirement 0 = no gate
	var frail := H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 0})
	assert_bool(light.can_equip(frail)).is_true()
