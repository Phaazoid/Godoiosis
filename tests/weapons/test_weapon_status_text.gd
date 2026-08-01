# The status seam (#44): every family with battle state can report it as text, so the player can
# SEE the state their decisions turn on. Presentation-only -- nothing in the rules reads these
# strings -- so these tests pin BEHAVIOUR-TO-TEXT correspondence, not exact wording: each test
# asserts the string changes with the state and names the thing that matters.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


func _instance_of(type: WeaponData.WeaponType) -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = type
	template.main_attack = WeaponAttackData.new()
	return WeaponInstance.make(template)


# The scope rule — a family reports status text EXACTLY when it has battle state — is a base-class
# property covering all seven families, and lives in tests/weapons/test_weapon_family_seam.gd
# (2026-08-01) alongside the rest of the seam. So does per-instance independence. What stays here is
# what no generic test can check: that each family's string actually tracks the state it claims to.


func test_chainsword_status_tracks_the_rev_timer() -> void:
	var sword := _instance_of(WeaponData.WeaponType.CHAINSWORD) as ChainswordWeaponInstance
	var idle := sword.status_text()
	sword.rev()
	var revved := sword.status_text()

	assert_str(idle).is_not_equal(revved)
	assert_str(revved).contains(str(ChainswordWeaponInstance.REV_DURATION_TURNS))

	sword.tick_rev()
	assert_str(sword.status_text()).is_not_equal(revved)   # the countdown is visible, not just on/off


func test_chainsword_status_returns_to_idle_when_the_rev_lapses() -> void:
	var sword := _instance_of(WeaponData.WeaponType.CHAINSWORD) as ChainswordWeaponInstance
	var idle := sword.status_text()
	sword.rev()
	for _i in range(ChainswordWeaponInstance.REV_DURATION_TURNS):
		sword.tick_rev()
	assert_str(sword.status_text()).is_equal(idle)


func test_mace_status_tracks_charge() -> void:
	var mace := _instance_of(WeaponData.WeaponType.KINETIC_MACE) as KineticMaceWeaponInstance
	var empty := mace.status_text()
	mace.charge = 2
	var charged := mace.status_text()

	assert_str(empty).is_not_equal(charged)
	assert_str(charged).contains("2")
	assert_str(charged).contains(str(KineticMaceWeaponInstance.MAX_CHARGE))


func test_mace_status_calls_out_that_blowback_is_unavailable() -> void:
	# The decision-critical case: 0 charge is not merely "less", it's a locked option.
	var mace := _instance_of(WeaponData.WeaponType.KINETIC_MACE) as KineticMaceWeaponInstance
	assert_str(mace.status_text().to_lower()).contains("blowback")
	mace.charge = 1
	assert_str(mace.status_text().to_lower()).not_contains("blowback")


func test_springspear_status_tracks_readiness() -> void:
	var spear := _instance_of(WeaponData.WeaponType.SPRINGSPEAR) as SpringspearWeaponInstance
	var loaded := spear.status_text()
	spear.ready = false
	var spent := spear.status_text()

	assert_str(loaded).is_not_equal(spent)
	assert_str(spent.to_lower()).contains("spring load")   # names the fix, not just the problem


func test_status_text_never_reaches_the_rules() -> void:
	# Guard against this seam drifting into gameplay: a revved sword's DEF-pierce must come from
	# ignores_def(), never from anything parsing the display string.
	var sword := _instance_of(WeaponData.WeaponType.CHAINSWORD) as ChainswordWeaponInstance
	sword.rev()
	assert_bool(sword.ignores_def()).is_true()
	sword.revved_turns_remaining = 0
	assert_bool(sword.ignores_def()).is_false()
