# GEAR'S MASS HAS ONE HOME: Item.weight (#120).
#
# A unit's weight is its body (the BLD stat) plus the mass of what it carries. BLD is a stat, so
# the gear stage of the effective-stat chain could reach it too -- an armour piece or a fitted mod
# listing BLD in its stat_modifiers would be a SECOND way for gear to add mass, and the two would
# disagree the day one of them is retuned (Law #4). So no authored piece may name it: a heavy piece
# says so in its own `weight`. Stats.GEAR_EXCLUDED is the declared list, and the mod editor reads it
# too so it never offers what this law refuses.
#
# Jobs and temporary effects MAY move BLD -- they change the body, which is what BLD is.
extends GdUnitTestSuite


func _offenders(pieces: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for key in pieces:
		var modifiers: Dictionary = pieces[key].stat_modifiers
		for stat: Stats.Stat in Stats.GEAR_EXCLUDED:
			if modifiers.has(stat):
				found.append("%s (%s)" % [key, Stats.Stat.keys()[stat]])
	return found


func test_the_body_weight_is_excluded_from_gear() -> void:
	assert_bool(Stats.GEAR_EXCLUDED.has(Stats.Stat.BLD)).override_failure_message(
		"BLD left GEAR_EXCLUDED, so gear could add mass twice and the cases below check nothing").is_true()


func test_no_armour_adds_mass_through_a_stat() -> void:
	var pieces := ArmorCatalog.get_variants()
	assert_bool(pieces.is_empty()).override_failure_message(
		"no armour was found, so this law checked nothing").is_false()
	var offenders := _offenders(pieces)
	assert_array(offenders).override_failure_message(
		"armour names a body-only stat in stat_modifiers -- author its mass as `weight` instead: %s"
		% ", ".join(offenders)).is_empty()


func test_no_mod_adds_mass_through_a_stat() -> void:
	var mods := WeaponModCatalog.get_mods()
	assert_bool(mods.is_empty()).override_failure_message(
		"no weapon mods were found, so this law checked nothing").is_false()
	var offenders := _offenders(mods)
	assert_array(offenders).override_failure_message(
		"a weapon mod names a body-only stat in stat_modifiers -- author its mass as `weight` instead: %s"
		% ", ".join(offenders)).is_empty()
