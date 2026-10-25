# UnitState.copy is the body a resolve pass writes to (#1480), so it must carry every field the live
# body has, and it must stay apart from the live one. A field the copy forgets is a fresh Law #2
# break: the pass would answer from a default while execution answers from the real value.
#
# The tables (tests/support/unit_state_fields.gd, shared with the no-live-write law) classify every
# SCRIPT VARIABLE of every copied class, and the law refuses a field no table names. A new var fails
# here until someone says how a copy treats it.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const Fields := preload("res://tests/support/unit_state_fields.gd")


static func _script_vars(obj: Object) -> Array[String]:
	var names: Array[String] = []
	for prop in obj.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(prop["name"])
	return names


func _assert_classified(obj: Object, table: Dictionary, what: String) -> void:
	var unknown: Array[String] = []
	for name in _script_vars(obj):
		if not table.has(name):
			unknown.append(name)
	assert_array(unknown).override_failure_message(
			"%s has fields no table says how a copy treats: %s" % [what, unknown]).is_empty()


# Seeds every field of `obj` in `table` away from what a fresh `blank` holds, so a copy that
# forgot a field cannot pass by both being at the default.
func _assert_seeded(obj: Object, blank: Object, table: Dictionary, what: String) -> void:
	for name in table:
		if not name in obj or table[name] == Fields.Kind.CHECKED:
			continue
		assert_bool(obj.get(name) != blank.get(name)).override_failure_message(
				"fixture: %s.%s is at its default, so the copy is not tested on it" % [what, name]).is_true()


func _assert_carried(live: Object, copy: Object, table: Dictionary, what: String) -> void:
	for name in table:
		if not name in live:
			continue
		var a: Variant = live.get(name)
		var b: Variant = copy.get(name)
		match table[name]:
			Fields.Kind.EQUAL:
				assert_bool(a == b).override_failure_message("%s.%s: the copy holds %s, the live body %s"
						% [what, name, b, a]).is_true()
			Fields.Kind.OWN:
				assert_bool(a == b).override_failure_message("%s.%s: the copy's contents differ"
						% [what, name]).is_true()
				assert_bool(is_same(a, b)).override_failure_message(
						"%s.%s: the copy shares the live container" % [what, name]).is_false()
			Fields.Kind.SHARED:
				assert_bool(is_same(a, b)).override_failure_message(
						"%s.%s: the copy has its own, where the field is shared" % [what, name]).is_true()
			Fields.Kind.TWIN:
				_assert_twin(a, b, "%s.%s" % [what, name])


func _assert_twin(live: Variant, twin: Variant, what: String) -> void:
	assert_object(twin).override_failure_message("%s: the copy holds no weapon" % what).is_not_null()
	if twin == null:
		return
	assert_bool(is_same(live, twin)).override_failure_message(
			"%s: the copy holds the LIVE weapon, so a pass would write it" % what).is_false()
	assert_str((twin as Object).get_class()).is_equal((live as Object).get_class())
	assert_object((twin as Object).get_script()).is_same((live as Object).get_script())
	_assert_carried(live, twin, Fields.WEAPON, what)


# A family's instance with every one of its fields seeded off its default.
func _seeded_weapon(type: WeaponData.WeaponType) -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = type
	template.main_attack = WeaponAttackData.new()
	var w := WeaponInstance.make(template)
	w.display_name = "Seeded %s" % WeaponData.WeaponType.keys()[type]
	w.icon = PlaceholderTexture2D.new()
	w.description = "seeded"
	w.weight = 3
	w.limb_kind = WeaponData.LimbKind.LEG
	var fitted: Array[WeaponModData] = [WeaponModData.new()]
	w.spaces = [fitted]
	var seeds := {"shots_remaining": 2, "revved_turns_remaining": 2, "charges": 2, "charge": 2, "ready": false}
	for name in seeds:
		if name in w:
			w.set(name, seeds[name])
	return w


func _families() -> Array[WeaponData.WeaponType]:
	var mapped: Array[WeaponData.WeaponType] = []
	for type: WeaponData.WeaponType in WeaponData.WeaponType.values():
		if WeaponInstance._instance_for(type) != null:
			mapped.append(type)
	return mapped


# One body with every UnitState and UnitInstance field seeded, carrying every family. The prosthetic is
# carried, held AND fitted, which is the one object three links must keep naming once copied.
func _seeded_unit() -> Dictionary:
	var unit := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	var state := unit.state
	# Every family at once is more than a unit's slots hold; the copy keeps whatever list it is handed,
	# an empty slot (null) included, at its index.
	state.inventory.clear()
	state.inventory.append(null)
	var weapons: Array[WeaponInstance] = []
	for type in _families():
		var w := _seeded_weapon(type)
		weapons.append(w)
		state.inventory.append(w)
	var prosthetic: WeaponInstance = null
	for w in weapons:
		if w is ProstheticWeaponInstance:
			prosthetic = w
	var armor := ArmorData.new()
	state.inventory.append(armor)
	state.equipped_weapon = prosthetic
	state.worn_armor = armor
	state.attunement = VialData.new()
	state.element_states.append(Elemental.State.WET)
	state.stat_effects.append(StatEffect.make("Seeded", {Stats.Stat.STR: 1}))
	state.lifecycle_state = Unit.LifecycleState.DOWNED
	state.wounded = true
	state.in_crisis = true
	state.crisis_surge_pending = true
	state.downed_turns_remaining = 2

	var instance := state.instance
	instance.stats[Stats.Stat.STR] = 9
	instance.aura[Elemental.Element.FIRE] = 2
	instance.affinity.append(Elemental.Element.FIRE)
	instance.is_alkahest_affine = true
	instance.current_hp = 7
	instance.weapon_proficiency[WeaponData.WeaponType.CHAINSWORD] = 1
	instance.jobs.append("seeded")
	instance.permadead = true
	var fitting: UnitInstance.LimbFitting = instance.limbs[UnitInstance.LimbSlot.ARM_R]
	fitting.state = UnitInstance.LimbState.PROSTHETIC
	fitting.prosthetic_stat = 3
	fitting.prosthetic_item = prosthetic
	return {"unit": unit, "prosthetic": prosthetic, "armor": armor}


# ==============================================================================
#  Every field is classified
# ==============================================================================

func test_every_field_of_a_copied_class_is_classified() -> void:
	var unit := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	_assert_classified(unit.state, Fields.UNIT_STATE, "UnitState")
	_assert_classified(unit.state.instance, Fields.UNIT_INSTANCE, "UnitInstance")
	_assert_classified(unit.state.instance.limbs[UnitInstance.LimbSlot.ARM_R], Fields.LIMB_FITTING, "LimbFitting")
	for type in _families():
		_assert_classified(_seeded_weapon(type), Fields.WEAPON, WeaponData.WeaponType.keys()[type])


# ==============================================================================
#  Every field is carried
# ==============================================================================

func test_a_copy_carries_every_field() -> void:
	var seeded := _seeded_unit()
	var live: UnitState = (seeded["unit"] as Unit).state
	var blank := UnitState.new(null)
	var fresh := UnitInstance.new()
	_assert_seeded(live, blank, Fields.UNIT_STATE, "UnitState")
	_assert_seeded(live.instance, fresh, Fields.UNIT_INSTANCE, "UnitInstance")
	_assert_seeded(live.instance.limbs[UnitInstance.LimbSlot.ARM_R], UnitInstance.LimbFitting.new(),
			Fields.LIMB_FITTING, "LimbFitting")

	var copy := live.copy()

	_assert_carried(live, copy, Fields.UNIT_STATE, "UnitState")
	assert_bool(is_same(live.instance, copy.instance)).override_failure_message(
			"the copy shares the live UnitInstance").is_false()
	_assert_carried(live.instance, copy.instance, Fields.UNIT_INSTANCE, "UnitInstance")
	for slot in live.instance.limbs:
		assert_bool(is_same(live.instance.limbs[slot], copy.instance.limbs[slot])).override_failure_message(
				"the copy shares a live LimbFitting").is_false()
		var what := "LimbFitting[%s]" % UnitInstance.LIMB_SHORT[slot]
		if live.instance.limbs[slot].prosthetic_item != null:
			_assert_carried(live.instance.limbs[slot], copy.instance.limbs[slot], Fields.LIMB_FITTING, what)
		else:
			assert_int(copy.instance.limbs[slot].state).is_equal(live.instance.limbs[slot].state)
	assert_int(copy.inventory.size()).is_equal(live.inventory.size())
	for i in live.inventory.size():
		if live.inventory[i] is WeaponInstance:
			var weapon := live.inventory[i] as WeaponInstance
			var blank_weapon := WeaponInstance._instance_for(weapon.template.weapon_type)
			_assert_seeded(weapon, blank_weapon, Fields.WEAPON, "inventory[%d]" % i)
			_assert_twin(live.inventory[i], copy.inventory[i], "inventory[%d]" % i)
		else:
			assert_object(copy.inventory[i]).is_same(live.inventory[i])


# ==============================================================================
#  One object stays one object
# ==============================================================================

func test_every_link_to_a_carried_weapon_names_the_same_twin() -> void:
	var seeded := _seeded_unit()
	var live: UnitState = (seeded["unit"] as Unit).state
	var prosthetic: WeaponInstance = seeded["prosthetic"]
	var copy := live.copy()

	var twin: Item = copy.inventory[live.inventory.find(prosthetic)]
	assert_object(copy.equipped_weapon).override_failure_message(
			"the copy's hand holds a different object from its inventory's").is_same(twin)
	assert_object(copy.instance.limbs[UnitInstance.LimbSlot.ARM_R].prosthetic_item).override_failure_message(
			"the copy's fitted prosthetic is a different object from its inventory's").is_same(twin)
	assert_object(copy.stat_effects[0]).is_same(live.stat_effects[0])


# A fixture's bare WeaponInstance.new() has no family to copy into, so it is shared rather than twinned.
func test_a_template_less_weapon_is_shared() -> void:
	var unit := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	var bare := WeaponInstance.new()
	unit.state.inventory[0] = bare
	unit.state.equipped_weapon = bare

	var copy := unit.state.copy()

	assert_object(copy.inventory[0]).is_same(bare)
	assert_object(copy.equipped_weapon).is_same(bare)


# ==============================================================================
#  The copy stays apart
# ==============================================================================

func test_writing_the_copy_leaves_the_live_body_alone() -> void:
	var seeded := _seeded_unit()
	var unit: Unit = seeded["unit"]
	var live := unit.state
	var hp := live.instance.current_hp
	var states := live.element_states.duplicate()
	var str_stat: int = live.instance.stats[Stats.Stat.STR]
	var aura: int = live.instance.aura[Elemental.Element.FIRE]
	var carried := live.inventory.size()
	var next := live.instance.next_maim_slot()
	assert_int(next).override_failure_message("fixture: the body has no limb left to take").is_not_equal(-1)
	var weapon_at := -1
	for i in live.inventory.size():
		if live.inventory[i] is SpringspearWeaponInstance:
			weapon_at = i
	assert_int(weapon_at).override_failure_message("fixture: no family with a battle flag").is_not_equal(-1)

	var copy := live.copy()
	(copy.inventory[weapon_at] as SpringspearWeaponInstance).ready = true
	copy.set_current_hp(1)
	copy.element_states.append(Elemental.State.CHILLED)
	copy.instance.stats[Stats.Stat.STR] += 5
	copy.lose_next_limb()
	copy.worn_armor = null
	copy.inventory.clear()
	copy.lifecycle_state = Unit.LifecycleState.DEAD

	assert_bool((live.inventory[weapon_at] as SpringspearWeaponInstance).ready).is_false()
	assert_int(live.instance.current_hp).is_equal(hp)
	assert_array(live.element_states).is_equal(states)
	assert_int(live.instance.stats[Stats.Stat.STR]).is_equal(str_stat)
	assert_int(live.instance.aura[Elemental.Element.FIRE]).override_failure_message(
			"the copy's limb tax reached the live aura").is_equal(aura)
	assert_int(live.instance.limbs[next].state).override_failure_message(
			"the copy's lost limb reached the live body").is_equal(UnitInstance.LimbState.NATURAL)
	assert_object(live.worn_armor).is_same(seeded["armor"])
	assert_int(live.inventory.size()).is_equal(carried)
	assert_int(live.lifecycle_state).is_equal(Unit.LifecycleState.DOWNED)
