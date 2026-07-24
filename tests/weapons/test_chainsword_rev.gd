# Chainsword Rev (#84): the family's signature main-action mechanic. Rev state lives on the
# WEAPON instance (mirroring #73's readiness seam on SpringWeaponInstance) so two chainswords
# in one inventory rev independently, and it resets every mission via make()/copy_equippable().
# Covers the state machine (rev -> ticks down -> expires -> refresh), the DEF-pierce accessor
# (ignores_def), the base-class no-op defaults (no other family revs), and the battle-scoped
# reset on copy. The resolver-side effect (revved attacks pierce DEF) is proven end-to-end in
# tests/law/test_def_mitigation.gd.
extends GdUnitTestSuite


func _chainsword() -> ChainswordWeaponInstance:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = WeaponAttackData.new()
	return WeaponInstance.make(t) as ChainswordWeaponInstance


func test_fresh_chainsword_is_not_revved() -> void:
	var w := _chainsword()
	assert_bool(w.is_revved()).is_false()
	assert_bool(w.ignores_def()).is_false()
	assert_bool(w.can_rev()).is_true()


func test_rev_arms_the_full_duration_and_pierces_def() -> void:
	var w := _chainsword()
	w.rev()
	assert_int(w.revved_turns_remaining).is_equal(ChainswordWeaponInstance.REV_DURATION_TURNS)
	assert_bool(w.is_revved()).is_true()
	assert_bool(w.ignores_def()).is_true()


func test_tick_counts_down_and_expires() -> void:
	var w := _chainsword()
	w.rev()
	for i in range(ChainswordWeaponInstance.REV_DURATION_TURNS):
		assert_bool(w.is_revved()).is_true()   # revved through each of its turns
		w.tick_rev()
	assert_bool(w.is_revved()).is_false()      # expired after DURATION ticks
	assert_bool(w.ignores_def()).is_false()


func test_tick_never_goes_negative() -> void:
	var w := _chainsword()
	w.tick_rev()   # ticking an un-revved weapon is a no-op, never negative
	assert_int(w.revved_turns_remaining).is_equal(0)


func test_re_rev_refreshes_the_full_duration() -> void:
	var w := _chainsword()
	w.rev()
	w.tick_rev()
	w.tick_rev()
	assert_int(w.revved_turns_remaining).is_equal(ChainswordWeaponInstance.REV_DURATION_TURNS - 2)
	w.rev()
	assert_int(w.revved_turns_remaining).is_equal(ChainswordWeaponInstance.REV_DURATION_TURNS)


func test_rev_state_does_not_survive_a_copy() -> void:
	# Battle-scoped: copy_equippable() hands back a fresh weapon, so a new mission starts un-revved.
	var w := _chainsword()
	w.rev()
	var fresh := w.copy_equippable() as ChainswordWeaponInstance
	assert_bool(fresh.is_revved()).is_false()


func test_two_chainswords_rev_independently() -> void:
	# The whole point of state-on-the-instance (the #73 bug this seam fixes): one revving must
	# not leak onto the other one in the same inventory.
	var a := _chainsword()
	var b := _chainsword()
	a.rev()
	assert_bool(a.is_revved()).is_true()
	assert_bool(b.is_revved()).is_false()


func test_a_non_chainsword_family_never_revs_or_pierces() -> void:
	# Base WeaponInstance's no-op rev surface: every other family is completely unaffected.
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.SPRINGSPEAR
	t.main_attack = WeaponAttackData.new()
	var w := WeaponInstance.make(t)
	assert_bool(w.can_rev()).is_false()
	assert_bool(w.ignores_def()).is_false()
	w.rev()        # no-op on the base class
	w.tick_rev()   # no-op on the base class
	assert_bool(w.ignores_def()).is_false()
