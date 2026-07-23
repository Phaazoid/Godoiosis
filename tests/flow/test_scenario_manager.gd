# Scenario persistence guards. Part 1 (#13): a unit whose resource no longer resolves loads
# back as null and valid_entries drops it (with a push_error) so load_scenario never
# null-derefs. Part 2 (#83): ScenarioUnitEntry.capture_unit_state/apply_unit_state round-trip
# the UnitInstance side of the persistence seam — stats, HP, Will, inventory (shared-template
# rule), limbs (prosthetic re-link), proficiency, aura — and a default entry (= a pre-#83
# save) applies as a no-op, keeping initialize()'s result.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

# A minimal installable prosthetic: PROSTHETIC-family template with a built-in stat,
# instance defaulting to ARM kind (mirrors H.make_weapon's ad-hoc-template pattern).
func _make_prosthetic(stat: int) -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.PROSTHETIC
	template.main_attack = WeaponAttackData.new()
	template.built_in_stat = stat
	return WeaponInstance.make(template)

# --- valid_entries (#13) ---

func test_valid_entries_skips_null_unit_data() -> void:
	var scenario := ScenarioData.new()
	var good := ScenarioUnitEntry.new()
	good.unit_data = UnitData.new()
	scenario.unit_entries.append(ScenarioUnitEntry.new())  # unit_data left null = unresolved
	scenario.unit_entries.append(good)

	var kept := ScenarioManager.valid_entries(scenario)

	assert_int(kept.size()).is_equal(1)
	assert_object(kept[0]).is_same(good)

func test_valid_entries_keeps_all_when_none_missing() -> void:
	var scenario := ScenarioData.new()
	var a := ScenarioUnitEntry.new()
	a.unit_data = UnitData.new()
	var b := ScenarioUnitEntry.new()
	b.unit_data = UnitData.new()
	scenario.unit_entries.append(a)
	scenario.unit_entries.append(b)

	assert_int(ScenarioManager.valid_entries(scenario).size()).is_equal(2)

# --- additive-export safety (#58/#61 jobs, extended #83) ---

func test_new_entry_defaults_to_jobless() -> void:
	# Pins the additive-export safety net: an old scenario's entries, which never wrote this
	# field, load with exactly this default — load_scenario needs no migration.
	var entry := ScenarioUnitEntry.new()
	assert_bool(entry.jobs.is_empty()).is_true()

func test_new_entry_instance_state_defaults_read_as_unsaved() -> void:
	# Every #83 field's default must mean "not saved": empty dicts apply as no-ops, -1
	# sentinels skip the HP/Will writes, empty inventory + -1 index leave the unit unarmed.
	var entry := ScenarioUnitEntry.new()
	assert_bool(entry.stats.is_empty()).is_true()
	assert_int(entry.current_hp).is_equal(-1)
	assert_int(entry.current_will).is_equal(-1)
	assert_bool(entry.inventory.is_empty()).is_true()
	assert_int(entry.equipped_index).is_equal(-1)
	assert_bool(entry.weapon_proficiency.is_empty()).is_true()
	assert_bool(entry.aura.is_empty()).is_true()
	assert_bool(entry.limb_states.is_empty()).is_true()
	assert_bool(entry.limb_prosthetic_stats.is_empty()).is_true()
	assert_bool(entry.limb_prosthetic_items.is_empty()).is_true()

func test_apply_default_entry_keeps_initialize_state() -> void:
	# A pre-#83 save: applying an untouched entry must change nothing initialize() built.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var entry := ScenarioUnitEntry.new()

	entry.apply_unit_state(unit)

	var inst: UnitInstance = unit.unit_instance
	assert_int(inst.current_hp).is_equal(inst.get_max_hp())
	assert_int(inst.current_will).is_equal(inst.get_max_will())
	assert_int(inst.get_base_stat(Stats.Stat.STR)).is_equal(H.baseline_stats()[Stats.Stat.STR])
	assert_bool(unit.has_equipped_weapon()).is_false()

# --- stats / HP / Will / jobs round-trip (#83) ---

func test_capture_apply_round_trips_stats_hp_will_jobs() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	a.unit_instance.stats[Stats.Stat.STR] = 9
	a.unit_instance.stats[Stats.Stat.MHP] = 12
	a.unit_instance.set_current_hp(7)
	a.unit_instance.set_current_will(2)
	a.unit_instance.jobs = ["test_job_83"]  # persistence only; catalog validity is #9's concern

	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(a)
	var b: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(1, 0), {}, false)
	entry.apply_unit_state(b)

	assert_int(b.unit_instance.get_base_stat(Stats.Stat.STR)).is_equal(9)
	assert_int(b.unit_instance.get_base_stat(Stats.Stat.MHP)).is_equal(12)
	assert_int(b.unit_instance.current_hp).is_equal(7)
	assert_int(b.unit_instance.current_will).is_equal(2)
	assert_array(b.unit_instance.jobs).contains_exactly(["test_job_83"])

func test_apply_clamps_hp_and_will_to_edited_maxes() -> void:
	# Saved HP/Will can exceed the maxes the (possibly edited) saved stats produce — the
	# setters clamp. And HP floors at 1 on apply: a load must never fire died().
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var entry := ScenarioUnitEntry.new()
	entry.stats = unit.unit_instance.stats.duplicate()
	entry.stats[Stats.Stat.MHP] = 4
	entry.current_hp = 99
	entry.current_will = 99

	entry.apply_unit_state(unit)

	assert_int(unit.unit_instance.current_hp).is_equal(unit.unit_instance.get_max_hp())
	assert_int(unit.unit_instance.current_will).is_equal(unit.unit_instance.get_max_will())

	entry.current_hp = 0
	entry.apply_unit_state(unit)
	assert_int(unit.unit_instance.current_hp).is_equal(1)
	assert_int(unit.lifecycle_state).is_equal(Unit.LifecycleState.ACTIVE)

# --- inventory + equipped_index round-trip (#83) ---

func test_inventory_round_trips_and_template_stays_shared() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var first: WeaponInstance = H.make_weapon(3)
	var second: WeaponInstance = H.make_weapon(5)
	a.add_item(first)   # auto-equips
	a.add_item(second)
	a.equip_weapon_from_inventory(1)

	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(a)
	var b: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(1, 0), {}, false)
	entry.apply_unit_state(b)

	var loaded_first := b.inventory[0] as WeaponInstance
	var loaded_second := b.inventory[1] as WeaponInstance
	assert_object(loaded_first).is_not_null()
	assert_object(loaded_second).is_not_null()
	# the copy_equippable guarantee, through BOTH copies (capture + apply): the loaded
	# instance still SHARES its family template — never a deep-dup fork
	assert_object(loaded_first.template).is_same(first.template)
	assert_object(loaded_second.template).is_same(second.template)
	# the save's explicit equip choice wins over add_item's auto-equip of slot 0
	assert_object(b.get_equipped_weapon()).is_same(loaded_second)

func test_unarmed_with_inventory_stays_unarmed() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	a.add_item(H.make_weapon())
	a.unequip_weapon()

	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(a)
	var b: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(1, 0), {}, false)
	entry.apply_unit_state(b)

	assert_int(entry.equipped_index).is_equal(-1)
	assert_object(b.inventory[0]).is_not_null()
	assert_bool(b.has_equipped_weapon()).is_false()

func test_fixture_style_direct_equip_is_captured() -> void:
	# H.spawn_unit sets equipped_weapon directly, bypassing inventory — capture appends it
	# instead of silently dropping the weapon.
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, true, 4)

	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(a)
	var b: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(1, 0), {}, false)
	entry.apply_unit_state(b)

	assert_int(entry.inventory.size()).is_equal(1)
	assert_int(entry.equipped_index).is_equal(0)
	var loaded := b.get_equipped_weapon() as WeaponInstance
	assert_object(loaded).is_not_null()
	assert_int(loaded.template.main_attack.power).is_equal(4)

# --- rider round-trips (#83): proficiency, aura, limbs ---

func test_weapon_proficiency_round_trips() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	a.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 1)

	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(a)
	var b: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(1, 0), {}, false)
	entry.apply_unit_state(b)

	assert_int(b.unit_instance.get_proficiency(WeaponData.WeaponType.CHAINSWORD)).is_equal(1)
	# an unsaved family still reads the default
	assert_int(b.unit_instance.get_proficiency(WeaponData.WeaponType.DRILL)).is_equal(UnitInstance.DEFAULT_PROFICIENCY)

func test_aura_round_trips() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	a.unit_instance.aura = {Elemental.Element.WATER: 3, Elemental.Element.FIRE: 0}

	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(a)
	var b: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(1, 0), {}, false)
	entry.apply_unit_state(b)

	assert_int(b.unit_instance.get_element_aura(Elemental.Element.WATER)).is_equal(3)
	# a zeroed pool (the maim tax floor) is real saved state, not a dropped key
	assert_bool(b.unit_instance.aura.has(Elemental.Element.FIRE)).is_true()
	assert_int(b.unit_instance.get_element_aura(Elemental.Element.FIRE)).is_equal(0)

func test_limb_states_round_trip() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var arm: UnitInstance.LimbFitting = a.unit_instance.limbs[UnitInstance.LimbSlot.ARM_R]
	arm.state = UnitInstance.LimbState.EMPTY
	var leg: UnitInstance.LimbFitting = a.unit_instance.limbs[UnitInstance.LimbSlot.LEG_L]
	leg.state = UnitInstance.LimbState.PROSTHETIC
	leg.prosthetic_stat = 4   # dev-editor placeholder fitting, no real item

	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(a)
	var b: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(1, 0), {}, false)
	entry.apply_unit_state(b)

	var inst: UnitInstance = b.unit_instance
	assert_int(inst.limbs[UnitInstance.LimbSlot.ARM_R].state).is_equal(UnitInstance.LimbState.EMPTY)
	assert_int(inst.limbs[UnitInstance.LimbSlot.LEG_L].state).is_equal(UnitInstance.LimbState.PROSTHETIC)
	assert_int(inst.limbs[UnitInstance.LimbSlot.LEG_L].prosthetic_stat).is_equal(4)
	assert_int(inst.limbs[UnitInstance.LimbSlot.ARM_L].state).is_equal(UnitInstance.LimbState.NATURAL)
	assert_bool(inst.has_missing_arm()).is_true()

func test_installed_prosthetic_relinks_to_carried_template() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var prosthetic: WeaponInstance = _make_prosthetic(7)
	a.add_item(prosthetic)
	assert_bool(a.unit_instance.install_prosthetic(UnitInstance.LimbSlot.ARM_L, prosthetic)).is_true()

	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(a)
	var b: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(1, 0), {}, false)
	entry.apply_unit_state(b)

	var carried := b.inventory[0] as WeaponInstance
	assert_object(carried).is_not_null()
	var fitting: UnitInstance.LimbFitting = b.unit_instance.limbs[UnitInstance.LimbSlot.ARM_L]
	assert_int(fitting.state).is_equal(UnitInstance.LimbState.PROSTHETIC)
	# the re-link contract: the fitting points at the CARRIED copy's shared template (which
	# IS the original template — copy_equippable never forks it), so built_in_stat reads live
	assert_object(fitting.prosthetic_item).is_same(carried.template)
	assert_object(fitting.prosthetic_item).is_same(prosthetic.template)
	assert_bool(b.unit_instance.is_installed_prosthetic(carried.template)).is_true()
	assert_int(b.unit_instance.limb_stat(UnitInstance.LimbSlot.ARM_L)).is_equal(7)
