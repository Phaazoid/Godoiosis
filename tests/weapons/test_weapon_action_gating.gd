# Weapon Action menu gating (2026-07-24 refactor): Unit.has_weapon_actions() must reflect what's
# ACTUALLY usable right now, not merely what the weapon carries. The bug this pins: a Kinetic Mace
# always carries Blowback in extra_attacks, so an existence-only check lit up the Weapon Action
# button even at 0 charge, before Blowback could fire. get_weapon_secondary_attacks() itself is
# existence-only on purpose (the submenu still LISTS an unfireable secondary, disabled) — the gate
# is the one place fireability must be checked.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


func _mace_unit() -> Unit:
	var unit := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	var blowback := WeaponAttackData.new()
	blowback.display_name = "Blowback"
	blowback.requires_readiness = true   # the authored gate, not knockback (#108)
	blowback.consumes_readiness = true
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.KINETIC_MACE
	template.main_attack = WeaponAttackData.new()
	var extras: Array[WeaponAttackData] = [blowback]
	template.extra_attacks = extras
	unit.equipped_weapon = WeaponInstance.make(template)
	return unit


func test_uncharged_mace_has_no_weapon_actions() -> void:
	# 0 charge: Blowback exists but can't fire, and the mace has no self-ability (no rev/reload) —
	# the button must NOT light up.
	var unit := _mace_unit()
	assert_bool(unit.has_weapon_actions()).is_false()


func test_charged_mace_has_a_weapon_action() -> void:
	var unit := _mace_unit()
	(unit.get_equipped_weapon() as KineticMaceWeaponInstance).charge = 1
	assert_bool(unit.has_weapon_actions()).is_true()


func test_secondary_attacks_still_list_regardless_of_fireability() -> void:
	# get_weapon_secondary_attacks() is the SUBMENU CONTENTS query (existence-only) — Law #2 wants
	# an unfireable pick shown-disabled, not hidden, once something else has opened the submenu.
	# Only has_weapon_actions() (the button GATE) needs the fireability filter.
	var unit := _mace_unit()
	assert_int(unit.get_weapon_secondary_attacks().size()).is_equal(1)


func test_chainsword_shows_weapon_action_via_rev_with_no_secondary_attacks() -> void:
	# A Chainsword has no extra attacks at all — its Weapon Action entry exists purely because
	# can_rev_weapon() is true. Guards the "OR a self-ability" half of the gate.
	var unit := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0))   # default CHAINSWORD weapon
	assert_array(unit.get_weapon_secondary_attacks()).is_empty()
	assert_bool(unit.has_weapon_actions()).is_true()


func test_bare_weapon_with_nothing_extra_has_no_weapon_actions() -> void:
	# A weapon with no secondaries and no self-ability. The fixture default (CHAINSWORD) still revs
	# and the Carbine now reloads (#84), so this needs the one family left with no signature at all:
	# Chemical Spitter, still a pure pass-through pending the materia pass.
	var unit := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHEMICAL_SPITTER
	template.main_attack = WeaponAttackData.new()
	unit.equipped_weapon = WeaponInstance.make(template)
	assert_bool(unit.has_weapon_actions()).is_false()


# #413 made Overwatch a WEAPON action, so the gate has a third clause -- and it follows the same
# rule as the other two: a watchable attack the unit could fire RIGHT NOW opens the row, one it
# cannot does not open it alone. Both halves, because the fireability filter IS the rule.
func test_a_watchable_attack_opens_the_weapon_row_only_when_it_can_fire() -> void:
	var unit := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHEMICAL_SPITTER   # the one family with no signature
	template.main_attack = WeaponAttackData.new()
	unit.equipped_weapon = WeaponInstance.make(template)
	assert_bool(unit.has_weapon_actions()).is_false()   # the baseline: nothing to do in the slice

	template.main_attack.can_overwatch = true
	assert_bool(unit.has_weapon_actions()).is_true()

	# The unfireable half: Blowback is the only watchable attack and the mace has no charge, so the
	# row must stay shut -- it still LISTS, greyed, once a self-ability opens the slice.
	var mace := _mace_unit()
	var weapon := mace.get_equipped_weapon() as WeaponInstance
	weapon.template.extra_attacks[0].can_overwatch = true
	assert_bool(mace.has_weapon_actions()).is_false()
