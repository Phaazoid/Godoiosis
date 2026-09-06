# A save is a true MID-BATTLE snapshot (#87): ScenarioUnitEntry round-trips the BATTLE-scoped
# layer alongside the persistent UnitInstance one that test_scenario_manager.gd already pins.
#
# The reason this is a whole suite rather than a few more cases next door: battle state is
# deliberately NOT @export where it lives, on either side. Weapon readiness/charge/rev/ammo are
# plain vars on WeaponInstance subclasses so make()/copy_for_grant() re-arm a weapon every mission;
# lifecycle, element states, Crisis and rally are plain vars on the transient Unit for the same
# reason. So none of it rides along for free — every field here is captured EXPLICITLY, and a field
# someone forgets fails silently and invisibly (the whole layer was silently absent from saves for
# a year, noticed only when a Kinetic Mace lost its charge across an F2 reset).
#
# The two structural traps each get a falsifier rather than a happy-path assertion:
#   * a restore must replay the RESULT, never the event — _go_downed() would emit went_downed and
#     re-spend Will, apply_stat_effect() would reseed a countdown from its duration
#   * order inside apply_unit_state is load-bearing — effects settle BEFORE gear (or a restored
#     debuff strips armour the save says is worn) and BEFORE HP (a +CON effect moves the ceiling)
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


# A weapon of a specific FAMILY, so the dispatch in WeaponInstance.make() hands back the subclass
# whose signature mechanic we're actually testing. Ad-hoc template, same throwaway shape as
# H.make_weapon's.
func _family_weapon(type: WeaponData.WeaponType) -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = type
	template.main_attack = WeaponAttackData.new()
	return WeaponInstance.make(template)


# Capture from `from`, apply onto a fresh unit, hand back the loaded unit. Every case here is the
# same round trip, so the shape lives in one place and each test states only what it cares about.
func _round_trip(from: Unit) -> Unit:
	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(from)
	var loaded: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(9, 9), {}, false)
	entry.apply_unit_state(loaded)
	return loaded


# Put a unit DOWN, not dead: exactly lethal damage lands on the down rung, while anything more
# than OVERKILL_CEILING past its HP kills outright (LethalityRules.predict).
func _down(unit: Unit) -> void:
	unit.take_damage(unit.get_current_hp())
	assert_bool(unit.is_downed()).is_true()   # the fixture's own setup, not the assertion under test


func _plate() -> ArmorData:
	var armor := ArmorData.new()
	armor.display_name = "Plate"
	armor.def_power = 6
	armor.stat_minimums[Stats.Stat.CON] = 6
	return armor


# ==============================================================================
#  Weapon battle state — the per-instance half
# ==============================================================================

func test_a_family_with_no_signature_mechanic_reports_nothing() -> void:
	# The base pair is empty on purpose, so ScenarioUnitEntry never special-cases a family and a
	# pass-through weapon costs a save nothing at all.
	var spitter := _family_weapon(WeaponData.WeaponType.CHEMICAL_SPITTER)
	assert_bool(spitter.capture_battle_state().is_empty()).is_true()

	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	a.add_item(spitter)
	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(a)

	assert_bool(entry.weapon_battle_states.is_empty()).is_true()


func test_springspear_readiness_round_trips() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var spear := _family_weapon(WeaponData.WeaponType.SPRINGSPEAR) as SpringspearWeaponInstance
	a.add_item(spear)
	spear.ready = false   # spent this battle

	var loaded := _round_trip(a)

	var reloaded := loaded.inventory[0] as SpringspearWeaponInstance
	assert_object(reloaded).is_not_null()
	assert_bool(reloaded.ready).is_false()


func test_carbine_magazine_round_trips() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var carbine := _family_weapon(WeaponData.WeaponType.CARBINE) as CarbineWeaponInstance
	a.add_item(carbine)
	carbine.shots_remaining = 1   # a partly-spent magazine, not just empty-or-full

	var loaded := _round_trip(a)

	assert_int((loaded.inventory[0] as CarbineWeaponInstance).shots_remaining).is_equal(1)


func test_kinetic_mace_charge_round_trips() -> void:
	# The literal report that opened #87: a mace's banked charge did not survive a save/load.
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var mace := _family_weapon(WeaponData.WeaponType.KINETIC_MACE) as KineticMaceWeaponInstance
	a.add_item(mace)
	mace.charge = 2

	var loaded := _round_trip(a)

	assert_int((loaded.inventory[0] as KineticMaceWeaponInstance).charge).is_equal(2)


func test_chainsword_rev_keeps_its_remaining_count_not_a_fresh_duration() -> void:
	# The COUNT rides along, not "is it revved". Restoring a full REV_DURATION_TURNS would hand the
	# player a free refresh — the entire cost side of the ability — for the price of a reload.
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var saw := _family_weapon(WeaponData.WeaponType.CHAINSWORD) as ChainswordWeaponInstance
	a.add_item(saw)
	saw.rev()
	saw.tick_rev()
	saw.tick_rev()
	assert_int(saw.revved_turns_remaining).is_equal(1)

	var loaded := _round_trip(a)

	var reloaded := loaded.inventory[0] as ChainswordWeaponInstance
	assert_int(reloaded.revved_turns_remaining).is_equal(1)
	assert_bool(reloaded.is_revved()).is_true()
	reloaded.tick_rev()
	assert_bool(reloaded.is_revved()).is_false()   # and it still expires on schedule


func test_two_weapons_of_one_family_stay_independent_through_a_save() -> void:
	# The identity requirement, and the same shape the TorvArm/TorvLeg prosthetic bug had: a unit
	# can carry two of a family, and the INVENTORY INDEX is the only thing that says which physical
	# weapon a magazine belongs to. Matching by family would collapse both onto one answer.
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var full := _family_weapon(WeaponData.WeaponType.CARBINE) as CarbineWeaponInstance
	var dry := _family_weapon(WeaponData.WeaponType.CARBINE) as CarbineWeaponInstance
	a.add_item(full)
	a.add_item(dry)
	dry.shots_remaining = 0

	var loaded := _round_trip(a)

	assert_int((loaded.inventory[0] as CarbineWeaponInstance).shots_remaining).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE)
	assert_int((loaded.inventory[1] as CarbineWeaponInstance).shots_remaining).is_equal(0)


func test_an_unsaved_weapon_state_loads_freshly_armed() -> void:
	# A pre-#87 scenario: the entry carries an inventory but no battle states. Each family's
	# apply_battle_state default has to match what make() builds, or old saves would load spent.
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var carbine := _family_weapon(WeaponData.WeaponType.CARBINE) as CarbineWeaponInstance
	a.add_item(carbine)
	carbine.shots_remaining = 0

	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(a)
	entry.weapon_battle_states = {}   # ... as an older save would have it
	var loaded: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(9, 9), {}, false)
	entry.apply_unit_state(loaded)

	assert_int((loaded.inventory[0] as CarbineWeaponInstance).shots_remaining).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE)


func test_battle_state_survives_a_real_disk_round_trip() -> void:
	# Everything else here is in-memory. The nested Dictionary is the part only a real
	# ResourceSaver/load pass can vouch for — a typed Dictionary[int, Dictionary] has to come back
	# as one, with its inner keys intact, or the whole seam is a no-op the moment it hits a file.
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var mace := _family_weapon(WeaponData.WeaponType.KINETIC_MACE) as KineticMaceWeaponInstance
	a.add_item(mace)
	mace.charge = 3
	a.apply_stat_effect(StatEffect.make("Crisis", {Stats.Stat.STR: 5}, 3))
	a.stat_effects[0].turns_remaining = 1
	a.add_element_state(Elemental.State.WET)
	a.rally_count = 2

	var entry := ScenarioUnitEntry.new()
	entry.unit_data = a.unit_data
	entry.capture_unit_state(a)
	var scenario := ScenarioData.new()
	scenario.unit_entries.append(entry)
	var path := "user://__diagnostic_battle_state.tres"
	scenario.take_over_path(path)
	assert_int(ResourceSaver.save(scenario, path)).is_equal(OK)

	var reloaded: ScenarioData = load(path)
	var loaded: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(9, 9), {}, false)
	reloaded.unit_entries[0].apply_unit_state(loaded)

	assert_int((loaded.inventory[0] as KineticMaceWeaponInstance).charge).is_equal(3)
	assert_int(loaded.stat_effects.size()).is_equal(1)
	assert_int(loaded.stat_effects[0].turns_remaining).is_equal(1)
	assert_int(loaded.stat_effects[0].get_modifier(Stats.Stat.STR)).is_equal(5)
	assert_array(loaded.element_states).contains_exactly([Elemental.State.WET])
	assert_int(loaded.rally_count).is_equal(2)

	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("__diagnostic_battle_state.tres")


# ==============================================================================
#  Unit body state
# ==============================================================================

func test_element_states_round_trip() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	a.add_element_state(Elemental.State.WET)

	var loaded := _round_trip(a)

	assert_array(loaded.element_states).contains_exactly([Elemental.State.WET])


func test_element_states_are_copied_not_shared() -> void:
	# Two units loaded from one scenario must not end up pointing at one array.
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	a.add_element_state(Elemental.State.WET)

	var loaded := _round_trip(a)
	loaded.remove_element_state(Elemental.State.WET)

	assert_array(a.element_states).contains_exactly([Elemental.State.WET])


func test_a_chilled_unit_round_trips_with_its_clock() -> void:
	# CHILLED is a PAIRED state: the marker and its StatEffect save as the two facts they are,
	# and both restore paths bypass the element-state doors on purpose (a restore replays the
	# RESULT) — so a load must come back with exactly ONE chill effect, mid-count, never a
	# fresh re-application reseeded from its duration.
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var applied: int = Elemental.STATE_DEFAULT_TURNS[Elemental.State.CHILLED] + 1
	a.add_element_state(Elemental.State.CHILLED, applied)
	a.tick_stat_effects()   # mid-count

	var loaded := _round_trip(a)

	assert_bool(loaded.element_states.has(Elemental.State.CHILLED)).is_true()
	var source := Elemental.state_effect_source(Elemental.State.CHILLED)
	var count := 0
	var remaining := -1
	for effect in loaded.stat_effects:
		if effect.source_name == source:
			count += 1
			remaining = effect.turns_remaining
	assert_int(count).is_equal(1)
	assert_int(remaining).is_equal(applied - 1)


func test_a_downed_unit_reloads_downed_with_its_clock() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	_down(a)
	a.tick_downed_countdown()
	assert_int(a.downed_turns_remaining).is_equal(2)

	var loaded := _round_trip(a)

	assert_bool(loaded.is_downed()).is_true()
	assert_int(loaded.downed_turns_remaining).is_equal(2)
	assert_bool(loaded.downed_sprite.visible).is_true()   # the sprite is part of the restored result
	assert_bool(loaded.map_sprite.visible).is_false()


func test_restoring_a_down_replays_the_result_not_the_event() -> void:
	# THE structural trap. Routing a restore through _go_downed() would emit went_downed — which
	# ejects the unit from a squad the loader has not rebuilt yet — and spend Will a SECOND time,
	# so a unit could reload maimed for a down it already paid for.
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	_down(a)
	var will_after_the_down: int = a.unit_instance.get_current_will()
	assert_int(will_after_the_down).is_less(a.unit_instance.get_max_will())   # a down really was paid for

	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(a)
	var loaded: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(9, 9), {}, false)
	var downed_signals: Array[Unit] = []
	loaded.went_downed.connect(func(u: Unit) -> void: downed_signals.append(u))

	entry.apply_unit_state(loaded)

	assert_array(downed_signals).is_empty()
	assert_int(loaded.unit_instance.get_current_will()).is_equal(will_after_the_down)


func test_an_active_unit_reloads_active_with_no_downed_sprite() -> void:
	# The default direction of the same field: ACTIVE is also what an unsaved entry means, so this
	# guards the sentinel as well as the round trip.
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)

	var loaded := _round_trip(a)

	assert_bool(loaded.is_active()).is_true()
	assert_int(loaded.downed_turns_remaining).is_equal(-1)
	assert_bool(loaded.downed_sprite.visible).is_false()


func test_crisis_flags_and_rally_count_round_trip() -> void:
	# All three are battle-long commitments: in_crisis locks Will at 0 and removes the safety net,
	# crisis_surge_pending spans a turn boundary, and rally_count is the diminishing-returns
	# counter. Reloading any of them clean hands back a gambit the player already spent.
	# (crisis_offered_pending left this list with #158 -- no offer exists to be pending.)
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	a.in_crisis = true
	a.crisis_surge_pending = true
	a.rally_count = 2

	var loaded := _round_trip(a)

	assert_bool(loaded.in_crisis).is_true()
	assert_bool(loaded.crisis_surge_pending).is_true()
	assert_int(loaded.rally_count).is_equal(2)
	assert_bool(loaded.can_rally()).is_false()   # and the rules downstream read the restored state


# ==============================================================================
#  Stat effects (#112) — the temporary-stat layer
# ==============================================================================

func test_stat_effects_round_trip_with_their_remaining_countdown() -> void:
	# The falsifier for the obvious implementation: apply_stat_effect() calls instantiate(), which
	# reseeds turns_remaining from `duration`. Restoring through it would hand a 1-turn-left Crisis
	# surge back with all three turns.
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	a.apply_stat_effect(StatEffect.make("Crisis", {Stats.Stat.STR: 5}, 3))
	a.tick_stat_effects()
	a.tick_stat_effects()
	assert_int(a.stat_effects[0].turns_remaining).is_equal(1)

	var loaded := _round_trip(a)

	assert_int(loaded.stat_effects.size()).is_equal(1)
	assert_int(loaded.stat_effects[0].turns_remaining).is_equal(1)
	assert_str(loaded.stat_effects[0].source_name).is_equal("Crisis")


func test_a_restored_effect_still_expires_on_schedule() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	a.apply_stat_effect(StatEffect.make("Crisis", {Stats.Stat.STR: 5}, 3))
	a.tick_stat_effects()
	a.tick_stat_effects()

	var loaded := _round_trip(a)
	assert_int(loaded.get_effective_stat(Stats.Stat.STR)).is_equal(a.get_effective_stat(Stats.Stat.STR))

	loaded.tick_stat_effects()

	assert_array(loaded.stat_effects).is_empty()
	assert_bool(loaded.has_stat_effect_from("Crisis")).is_false()


func test_a_permanent_effect_stays_permanent() -> void:
	# PERMANENT is -1, the same sentinel a fresh StatEffect carries — so this also proves the
	# countdown is genuinely being written rather than left at its default.
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	a.apply_stat_effect(StatEffect.make("Brand", {Stats.Stat.DEX: -1}))

	var loaded := _round_trip(a)
	loaded.tick_stat_effects()

	assert_int(loaded.stat_effects.size()).is_equal(1)
	assert_int(loaded.stat_effects[0].turns_remaining).is_equal(StatEffect.PERMANENT)


func test_saved_effects_are_copies_not_the_live_ones() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	a.apply_stat_effect(StatEffect.make("Crisis", {Stats.Stat.STR: 5}, 3))

	var loaded := _round_trip(a)
	loaded.stat_effects[0].turns_remaining = 99

	assert_int(a.stat_effects[0].turns_remaining).is_equal(3)


func test_restored_effects_settle_before_hp_is_written_back() -> void:
	# Ordering, half one: a +CON effect raises max HP, and the saved current_hp was measured
	# against the SURGED max. Settle the effects after the HP write and the clamp silently sheds
	# the difference — the same data-losing round trip #106 fixed for gear.
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var bare_max: int = a.get_max_hp()
	a.apply_stat_effect(StatEffect.make("Tonic", {Stats.Stat.CON: 6}, 3))
	var surged_max: int = a.get_max_hp()
	assert_int(surged_max).is_greater(bare_max)
	a.set_current_hp(surged_max)

	var loaded := _round_trip(a)

	assert_int(loaded.get_max_hp()).is_equal(surged_max)
	assert_int(loaded.get_current_hp()).is_equal(surged_max)


func test_a_restored_debuff_does_not_strip_saved_armor() -> void:
	# Ordering, half two: restore_stat_effects settles, and settling enforces the wear gates. Run
	# it AFTER the armour is assigned and a restored debuff quietly undresses a unit the save says
	# was wearing plate — the same "a save is authoritative" rule worn_armor_index already follows.
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.CON: 8}, false)
	a.add_item(_plate())
	assert_bool(a.wear_armor(0)).is_true()
	a.apply_stat_effect(StatEffect.make("Chill", {Stats.Stat.CON: -5}, 3))
	a.worn_armor = a.inventory[0] as ArmorData   # the gate stripped it live; the save records it worn

	var loaded := _round_trip(a)

	assert_object(loaded.worn_armor).is_not_null()
	assert_object(loaded.worn_armor).is_same(loaded.inventory[0])
	assert_bool(loaded.worn_armor.can_equip(loaded)).is_false()   # illegal, and kept anyway


# ==============================================================================
#  The additive-default contract — a pre-#87 save must load exactly as it used to
# ==============================================================================

func test_new_entry_battle_state_defaults_read_as_unsaved() -> void:
	var entry := ScenarioUnitEntry.new()
	assert_bool(entry.weapon_battle_states.is_empty()).is_true()
	assert_bool(entry.element_states.is_empty()).is_true()
	assert_bool(entry.stat_effects.is_empty()).is_true()
	assert_int(entry.lifecycle_state).is_equal(Unit.LifecycleState.ACTIVE)
	assert_int(entry.downed_turns_remaining).is_equal(-1)
	assert_bool(entry.in_crisis).is_false()
	assert_bool(entry.crisis_surge_pending).is_false()
	assert_int(entry.rally_count).is_equal(0)
	assert_bool(entry.squad_has_acted).is_false()


func test_applying_a_default_entry_leaves_a_healthy_unit_alone() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)

	ScenarioUnitEntry.new().apply_unit_state(unit)

	assert_bool(unit.is_active()).is_true()
	assert_int(unit.downed_turns_remaining).is_equal(-1)
	assert_bool(unit.element_states.is_empty()).is_true()
	assert_bool(unit.stat_effects.is_empty()).is_true()
	assert_bool(unit.in_crisis).is_false()
	assert_int(unit.rally_count).is_equal(0)
	assert_int(unit.get_current_hp()).is_equal(unit.get_max_hp())


# ==============================================================================
#  The armed watch (#413) — and which LIST its index means (#590)
# ==============================================================================

# The watch is stored as an INDEX, so the capture and the restore have to agree about the list they
# are indexing into. Since #590 that list is the unit's WATCH view: a watch attack is watch-only, so
# it is not in get_selectable_attacks() at all and an index into that list resolves to nothing.
# Nothing pinned this before -- the round trip had no watch case, so both halves could have gone on
# reading the fireable list and every suite would have stayed green while a saved watch quietly
# lapsed on load.
func test_an_armed_watch_round_trips_with_the_attack_it_was_aimed_with() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var weapon := _family_weapon(WeaponData.WeaponType.CARBINE)
	weapon.template.main_attack.display_name = "Shot"
	var watch := WeaponAttackData.new()
	watch.display_name = "Overwatch"
	watch.can_overwatch = true
	weapon.template.extra_attacks = [watch]
	a.add_item(weapon)

	var footprint: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]
	a.arm_watch(Vector2i.ZERO, Vector2i(2, 0), footprint, watch)
	assert_object(a.watch).is_not_null()   # the fixture's own setup, not the assertion under test

	var loaded := _round_trip(a)

	assert_object(loaded.watch).override_failure_message(
			"the armed watch did not survive the save at all").is_not_null()
	assert_object(loaded.watch.attack).override_failure_message(
			"the watch came back aimed with a different attack -- the stored index resolved elsewhere"
			).is_same(watch)
	assert_array(loaded.watch.footprint).is_equal(footprint)
	assert_int(loaded.watch.anchor_cell.x).is_equal(0)
	assert_int(loaded.watch.aim_cell.x).is_equal(2)


# --- what the pipe CARRIES (#697) ----------------------------------------------------------------

# capture_unit_state used to drop any inventory entry that was not an EquippableData, with a
# push_warning and nothing else -- the narrow authoring type showing through as a rule. #697 widened
# the three doors to Item and deleted the refusal, so THIS is the case that stands where the warning
# was: a carried non-equippable has to come back.
func test_a_carried_non_equippable_survives_the_save() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var vial := VialData.new()
	vial.element = Elemental.Element.FIRE
	vial.display_name = "Vial of Sulfur"
	assert_bool(a.add_item(vial)).is_true()

	var loaded := _round_trip(a)

	var carried: Array = loaded.inventory.filter(func(i): return i is VialData)
	assert_array(carried).override_failure_message(
			"the vial was dropped by the save -- the pipe is still narrower than it claims").is_not_empty()
	assert_int((carried[0] as VialData).element).is_equal(Elemental.Element.FIRE)

# A vial is carried, never slotted, so a save must not come back with one in the weapon slot.
func test_a_carried_vial_is_not_restored_as_a_weapon() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var vial := VialData.new()
	vial.element = Elemental.Element.WATER
	vial.display_name = "Vial of Mercury"
	a.add_item(vial)

	assert_bool(_round_trip(a).has_equipped_weapon()).is_false()

# The burned charge is battle state and rides the save. One that evaporated across a mid-battle load
# would eat a scarce item with no message anywhere -- silently, which is this suite's whole subject.
func test_the_vial_charge_round_trips() -> void:
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var vial := VialData.new()
	vial.element = Elemental.Element.EARTH
	vial.display_name = "Vial of Salt"
	a.add_item(vial)
	assert_str(a.use_vial(a.inventory.find(vial))).is_equal("")

	var loaded := _round_trip(a)

	assert_object(loaded.attunement).override_failure_message(
			"the charge was spent by the save -- a burned vial vanished for nothing").is_not_null()
	assert_array(loaded.attunement_elements()).is_equal([Elemental.Element.EARTH])
