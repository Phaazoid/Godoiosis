# AI weapon-routine coverage (#726): every weapon family must DECLARE its AI routine -- the bare
# AIWeaponRoutine is a legal declaration, absence is red. The action registry's AI column
# (test_ai_action_coverage.gd) has its sibling here for FAMILIES: a new WeaponType turns this suite
# red until somebody says what the AI should hold back on with it, even when the answer is
# "nothing". Also pins the contract's floor: the base routine never says no, and a slot with no
# family (a rune, an empty hand) resolves to it.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


func test_every_family_declares_a_routine() -> void:
	var table: Dictionary = AIWeaponRoutine.table()
	for family in WeaponData.WeaponType.values():
		var label: String = WeaponData.WeaponType.keys()[family]
		assert_bool(table.has(family)) \
			.override_failure_message("weapon family %s has no AI routine declared -- declare one, even the inert base (#726)" % [label]) \
			.is_true()
		if table.has(family):
			assert_bool(table[family] is AIWeaponRoutine) \
				.override_failure_message("weapon family %s declares something that is not an AIWeaponRoutine" % [label]) \
				.is_true()


func test_the_base_routine_never_says_no() -> void:
	var routine := AIWeaponRoutine.new()
	var sm: SquadManager = H.make_manager(self)
	var unit: Unit = H.spawn_solo(self, sm, Team.Faction.ENEMY, Vector2i(0, 0))
	var units: Array[Unit] = [unit]
	var board := BoardContext.new(sm.grid, units, sm)
	for verb in AIWeaponRoutine.WEAPON_VERBS:
		assert_bool(routine.allows_preparation(unit, verb, board)).is_true()
	assert_bool(routine.defers_candidate(unit, null, null, Vector3i.ZERO)).is_false()


func test_a_slot_with_no_family_resolves_to_the_base() -> void:
	var sm: SquadManager = H.make_manager(self)
	var unarmed: Unit = H.spawn_solo(self, sm, Team.Faction.ENEMY, Vector2i(0, 0), {}, false)
	assert_bool(AIWeaponRoutine.for_unit(unarmed).get_script() == AIWeaponRoutine).is_true()
	var caster: Unit = H.spawn_solo(self, sm, Team.Faction.ENEMY, Vector2i(1, 0), {}, false)
	caster.equipped_weapon = RuneData.new()
	assert_bool(AIWeaponRoutine.for_unit(caster).get_script() == AIWeaponRoutine).is_true()


func test_a_family_with_a_rule_resolves_to_its_own_routine() -> void:
	assert_bool(AIWeaponRoutine.for_family(WeaponData.WeaponType.DRILL) is DrillWeaponRoutine).is_true()
	assert_bool(AIWeaponRoutine.for_family(WeaponData.WeaponType.SPRINGSPEAR) is SpringspearWeaponRoutine).is_true()
	# And the dispatch reads the equipped weapon's family, not a hand-picked one.
	var sm: SquadManager = H.make_manager(self)
	var digger: Unit = H.spawn_solo(self, sm, Team.Faction.ENEMY, Vector2i(0, 0), {}, false)
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.DRILL
	template.main_attack = WeaponAttackData.new()
	digger.equipped_weapon = WeaponInstance.make(template)
	assert_bool(AIWeaponRoutine.for_unit(digger) is DrillWeaponRoutine).is_true()
