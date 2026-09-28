# The gauge seam (#1045): a weapon's live count as numbers -- rounds, charge, a wound spring, a tank,
# rev turns left -- and WHICH attack rows print it. Every maximum is read off the family's own
# constant, never typed: those are tuning values and must stay free to move (tests/README.md #8).
#
# What this suite owns is the DATA answer. That the ring actually shows it is the wire, pinned in
# tests/ui/test_menu_catalogue_rows.gd; how it is coloured is pure, pinned in test_radial_geometry.gd.
extends GdUnitTestSuite


func _template(type: WeaponData.WeaponType) -> WeaponData:
	var template := WeaponData.new()
	template.weapon_type = type
	template.main_attack = WeaponAttackData.new()
	return template


func _attack(requires: bool, consumes: bool, builds: bool) -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.requires_readiness = requires
	a.consumes_readiness = consumes
	a.builds_readiness = builds
	return a


func _label(g: WeaponGauge) -> String:
	return g.label() if g != null else "<none>"


# ==============================================================================
#  Each family's count tracks its state
# ==============================================================================

func test_the_carbine_counts_its_magazine() -> void:
	var shot := _attack(true, true, false)
	var template := _template(WeaponData.WeaponType.CARBINE)
	template.main_attack = shot
	var carbine := WeaponInstance.make(template) as CarbineWeaponInstance

	var full := carbine.gauge()
	assert_int(full.kind).is_equal(WeaponGauge.Kind.STOCK)
	assert_int(full.current).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE)
	assert_int(full.maximum).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE)

	carbine.consume_readiness_for(shot)
	assert_int(carbine.gauge().current).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE - 1)
	carbine.reload(null)
	assert_int(carbine.gauge().current).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE)


func test_the_mace_counts_its_charge() -> void:
	var smash := _attack(false, false, true)
	var mace := WeaponInstance.make(_template(WeaponData.WeaponType.KINETIC_MACE)) as KineticMaceWeaponInstance

	assert_int(mace.gauge().current).is_equal(0)
	assert_int(mace.gauge().maximum).is_equal(KineticMaceWeaponInstance.MAX_CHARGE)
	mace.consume_readiness_for(smash)
	assert_int(mace.gauge().current).is_equal(1)


func test_the_spear_is_a_one_deep_stock() -> void:
	var spring := _attack(true, true, false)
	var spear := WeaponInstance.make(_template(WeaponData.WeaponType.SPRINGSPEAR)) as SpringspearWeaponInstance

	assert_str(_label(spear.gauge())).is_equal("1/1")
	spear.consume_readiness_for(spring)
	assert_str(_label(spear.gauge())).is_equal("0/1")


func test_the_spitter_counts_its_tank() -> void:
	var spitter := WeaponInstance.make(_template(WeaponData.WeaponType.CHEMICAL_SPITTER)) as ChemicalSpitterWeaponInstance

	assert_int(spitter.gauge().current).is_equal(0)
	assert_int(spitter.gauge().maximum).is_equal(ChemicalSpitterWeaponInstance.TANK_SIZE)
	spitter.charges = 2
	assert_int(spitter.gauge().current).is_equal(2)


# A timer, not a stock -- and none at all while the sword is idle, so an unrevved Slash prints nothing.
func test_the_chainsword_runs_a_timer_only_while_revved() -> void:
	var sword := WeaponInstance.make(_template(WeaponData.WeaponType.CHAINSWORD)) as ChainswordWeaponInstance

	assert_object(sword.gauge()).is_null()
	sword.rev()
	var revved := sword.gauge()
	assert_int(revved.kind).is_equal(WeaponGauge.Kind.TIMER)
	assert_int(revved.current).is_equal(ChainswordWeaponInstance.REV_DURATION_TURNS)
	sword.tick_rev()
	assert_int(sword.gauge().current).is_equal(ChainswordWeaponInstance.REV_DURATION_TURNS - 1)
	for _i in range(ChainswordWeaponInstance.REV_DURATION_TURNS):
		sword.tick_rev()
	assert_object(sword.gauge()).is_null()


func test_a_family_with_no_count_has_no_gauge() -> void:
	for type: WeaponData.WeaponType in [WeaponData.WeaponType.DRILL, WeaponData.WeaponType.PROSTHETIC]:
		var weapon := WeaponInstance.make(_template(type))
		assert_object(weapon.gauge()) \
			.override_failure_message("%s grew a gauge it has no state for" % WeaponData.WeaponType.keys()[type]) \
			.is_null()


# ==============================================================================
#  Which attack rows print it
# ==============================================================================

# The readiness families answer by the three authored flags (#108), each one on its own.
func test_a_readiness_row_shows_the_count_and_an_unflagged_row_does_not() -> void:
	var carbine := WeaponInstance.make(_template(WeaponData.WeaponType.CARBINE))
	for flagged: WeaponAttackData in [_attack(true, false, false), _attack(false, true, false), _attack(false, false, true)]:
		assert_object(carbine.attack_gauge(null, flagged)) \
			.override_failure_message("a flag-authored attack printed no count").is_not_null()
	assert_object(carbine.attack_gauge(null, _attack(false, false, false))) \
		.override_failure_message("an attack outside the economy printed the magazine").is_null()


# The tank changes what the MAIN becomes, and no flag says so -- so it rides the main, under BOTH forms.
func test_the_spitters_tank_rides_its_main_in_either_form() -> void:
	var template := _template(WeaponData.WeaponType.CHEMICAL_SPITTER)
	var charged := WeaponAttackData.new()
	template.main_attack.empowered_form = charged
	var extra := WeaponAttackData.new()
	template.extra_attacks = [extra]
	var spitter := WeaponInstance.make(template) as ChemicalSpitterWeaponInstance

	assert_object(spitter.attack_gauge(null, template.main_attack)).is_not_null()
	assert_object(spitter.attack_gauge(null, charged)).is_not_null()
	assert_object(spitter.attack_gauge(null, extra)) \
		.override_failure_message("the tank printed on an attack it never changes").is_null()


# Rev makes every attack from the weapon ignore DEF, so every attack row shows the timer -- none of the
# Chainsword's attacks author a readiness flag, which is why the flag rule cannot answer here.
func test_the_rev_timer_rides_every_chainsword_attack() -> void:
	var sword := WeaponInstance.make(_template(WeaponData.WeaponType.CHAINSWORD)) as ChainswordWeaponInstance
	var plain := _attack(false, false, false)
	assert_object(sword.attack_gauge(null, plain)).is_null()
	sword.rev()
	assert_int(sword.attack_gauge(null, plain).kind).is_equal(WeaponGauge.Kind.TIMER)


func test_a_rune_prints_no_count() -> void:
	var rune := RuneData.new()
	assert_object(rune.attack_gauge(null, TransmutationData.new())).is_null()


# ==============================================================================
#  The label, and the one answer
# ==============================================================================

func test_a_stock_reads_as_a_fraction_and_a_timer_as_turns() -> void:
	assert_str(WeaponGauge.stock(4, 6).label()).is_equal("4/6")
	assert_str(WeaponGauge.timer(1, 3).label()).is_equal("1 turn")
	assert_str(WeaponGauge.timer(2, 3).label()).is_equal("2 turns")


# status_text's numbers come FROM the gauge, so the Inspect sentence and the ring can never disagree
# about how many rounds there are (the issue's "keep one answer").
func test_the_status_sentence_quotes_the_gauge() -> void:
	var carbine := WeaponInstance.make(_template(WeaponData.WeaponType.CARBINE)) as CarbineWeaponInstance
	carbine.shots_remaining = 1
	var mace := WeaponInstance.make(_template(WeaponData.WeaponType.KINETIC_MACE)) as KineticMaceWeaponInstance
	mace.charge = 2
	var spitter := WeaponInstance.make(_template(WeaponData.WeaponType.CHEMICAL_SPITTER)) as ChemicalSpitterWeaponInstance
	spitter.charges = 1
	var sword := WeaponInstance.make(_template(WeaponData.WeaponType.CHAINSWORD)) as ChainswordWeaponInstance
	sword.rev()

	for weapon: WeaponInstance in [carbine, mace, spitter, sword]:
		assert_str(weapon.status_text()).contains(weapon.gauge().label())
