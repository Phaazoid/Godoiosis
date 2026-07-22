# Readiness seam (#73): the WeaponInstance subclass design that fixes the two-spears-in-one-
# inventory bug — readiness lives on the WEAPON instance, not the Unit, so two spears track
# independently. Covers: base WeaponInstance's no-op defaults (every other family stays
# unaffected), WeaponInstance.make()'s weapon_type dispatch, SpringWeaponInstance's state
# machine under both balance-knob variants (Stab.requires_readiness true/false), the actual
# bug this design fixes (inventory-swap independence), and the two legality gates
# (AttackAction.actor_can_perform, SpringLoadAction). AttackAction.execute()'s readiness
# spend is a few lines gated only on is_secondary_hit/fired_attack type (no resolved/damage
# dependency) — per tests/law/test_resolution_laws.gd's own precedent, execute()'s animation
# await is bypassed everywhere in this suite; consume_readiness_for is exercised directly
# below instead of through a real execute() call.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

func _attack(display_name: String, requires: bool = false, consumes: bool = false) -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.display_name = display_name
	a.requires_readiness = requires
	a.consumes_readiness = consumes
	return a

# A Springspear-shaped template: main = Stab, extra = Spring. `stab_requires` toggles the
# balance knob under test (#73's "prevent all attacks vs. just re-Spring" caveat).
func _spring_template(stab_requires: bool) -> WeaponData:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.SPRINGSPEAR
	t.main_attack = _attack("Stab", stab_requires, false)
	t.extra_attacks = [_attack("Spring", true, true)]
	t.scaling_blend = {Stats.Stat.STR: 100}
	return t

func _plain_template() -> WeaponData:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = _attack("Slash")
	t.scaling_blend = {Stats.Stat.STR: 100}
	return t

# --- base WeaponInstance: every non-Springspear family is unaffected ---

func test_make_returns_plain_weapon_instance_for_an_unmapped_family() -> void:
	var w := WeaponInstance.make(_plain_template())
	assert_bool(w is SpringWeaponInstance).is_false()

func test_base_weapon_instance_defaults_never_gate_anything() -> void:
	var w := WeaponInstance.make(_plain_template())
	assert_bool(w.is_attack_fireable(_attack("x", true, true))).is_true()
	assert_bool(w.can_reload()).is_false()
	w.reload()                                          # no-op, must not error
	w.consume_readiness_for(_attack("x", true, true))   # no-op, must not error
	assert_bool(w.can_reload()).is_false()              # still nothing to reload

# --- WeaponInstance.make() dispatch ---

func test_make_returns_spring_weapon_instance_for_springspear() -> void:
	var w := WeaponInstance.make(_spring_template(true))
	assert_bool(w is SpringWeaponInstance).is_true()

# --- SpringWeaponInstance state machine ---

func test_starts_ready() -> void:
	var w := WeaponInstance.make(_spring_template(true)) as SpringWeaponInstance
	assert_bool(w.can_reload()).is_false()   # nothing to reload while already ready

func test_while_ready_every_attack_is_fireable() -> void:
	var t := _spring_template(true)
	var w := WeaponInstance.make(t) as SpringWeaponInstance
	assert_bool(w.is_attack_fireable(t.main_attack)).is_true()
	assert_bool(w.is_attack_fireable(t.extra_attacks[0])).is_true()

func test_firing_spring_consumes_readiness() -> void:
	var t := _spring_template(true)
	var w := WeaponInstance.make(t) as SpringWeaponInstance
	w.consume_readiness_for(t.extra_attacks[0])
	assert_bool(w.can_reload()).is_true()

func test_firing_stab_never_consumes_readiness() -> void:
	var t := _spring_template(true)
	var w := WeaponInstance.make(t) as SpringWeaponInstance
	w.consume_readiness_for(t.main_attack)
	assert_bool(w.can_reload()).is_false()   # Stab doesn't consume — still ready

# --- the balance knob: Stab.requires_readiness true (issue-as-written) vs false ---

func test_all_locks_variant_blocks_stab_while_unready() -> void:
	var t := _spring_template(true)   # Stab.requires_readiness = true
	var w := WeaponInstance.make(t) as SpringWeaponInstance
	w.consume_readiness_for(t.extra_attacks[0])
	assert_bool(w.is_attack_fireable(t.main_attack)).is_false()
	assert_bool(w.is_attack_fireable(t.extra_attacks[0])).is_false()

func test_spring_only_variant_leaves_stab_fireable_while_unready() -> void:
	var t := _spring_template(false)   # Stab.requires_readiness = false
	var w := WeaponInstance.make(t) as SpringWeaponInstance
	w.consume_readiness_for(t.extra_attacks[0])
	assert_bool(w.is_attack_fireable(t.main_attack)).is_true()
	assert_bool(w.is_attack_fireable(t.extra_attacks[0])).is_false()   # re-Spring still blocked

func test_reload_restores_fireability() -> void:
	var t := _spring_template(true)
	var w := WeaponInstance.make(t) as SpringWeaponInstance
	w.consume_readiness_for(t.extra_attacks[0])
	w.reload()
	assert_bool(w.can_reload()).is_false()
	assert_bool(w.is_attack_fireable(t.main_attack)).is_true()
	assert_bool(w.is_attack_fireable(t.extra_attacks[0])).is_true()

# --- the bug this design fixes: two spears in one inventory track readiness independently ---

func test_two_spears_in_one_inventory_track_readiness_independently() -> void:
	var unit := H.spawn_unit(self, PLAYER, Vector2i(0, 0), {}, false)
	var t1 := _spring_template(true)
	var t2 := _spring_template(true)
	var spear_a := WeaponInstance.make(t1) as SpringWeaponInstance
	var spear_b := WeaponInstance.make(t2) as SpringWeaponInstance
	unit.add_item(spear_a)   # slot 0, auto-equips
	unit.add_item(spear_b)   # slot 1

	unit.equip_weapon_from_inventory(0)
	spear_a.consume_readiness_for(t1.extra_attacks[0])   # spear A fires Spring, goes unready

	unit.equip_weapon_from_inventory(1)                                # swap to spear B
	assert_bool(unit.is_attack_fireable(t2.main_attack)).is_true()     # B is untouched
	assert_bool(unit.can_reload_weapon()).is_false()                  # nothing to reload on B

	unit.equip_weapon_from_inventory(0)                                # swap back to spear A
	assert_bool(unit.is_attack_fireable(t1.main_attack)).is_false()    # A is still sprung
	assert_bool(unit.can_reload_weapon()).is_true()

# --- Unit delegators (what the menu gate actually reads) ---

func test_unit_has_any_fireable_attack_reflects_readiness() -> void:
	var t := _spring_template(true)
	var unit := H.spawn_unit(self, PLAYER, Vector2i(0, 0), {}, false)
	var spear := WeaponInstance.make(t) as SpringWeaponInstance
	unit.add_item(spear)
	assert_bool(unit.has_any_fireable_attack()).is_true()
	spear.consume_readiness_for(t.extra_attacks[0])
	assert_bool(unit.has_any_fireable_attack()).is_false()   # all-locks: nothing left to fire

# --- AttackAction.actor_can_perform: the Law #3 queue-time gate (menu-independent) ---

func test_attack_action_refuses_to_queue_an_unfireable_pick() -> void:
	var t := _spring_template(true)
	var unit := H.spawn_unit(self, PLAYER, Vector2i(0, 0), {}, false)
	var spear := WeaponInstance.make(t) as SpringWeaponInstance
	unit.add_item(spear)
	spear.consume_readiness_for(t.extra_attacks[0])   # now unready, all-locks variant

	var attack := AttackAction.create(unit, unit.movement.cell, null, Vector2i(1, 0))
	attack.fired_attack = t.main_attack
	assert_bool(attack.actor_can_perform()).is_false()

func test_attack_action_allows_a_fireable_pick() -> void:
	var t := _spring_template(false)   # Stab stays fireable while unready
	var unit := H.spawn_unit(self, PLAYER, Vector2i(0, 0), {}, false)
	var spear := WeaponInstance.make(t) as SpringWeaponInstance
	unit.add_item(spear)
	spear.consume_readiness_for(t.extra_attacks[0])

	var attack := AttackAction.create(unit, unit.movement.cell, null, Vector2i(1, 0))
	attack.fired_attack = t.main_attack
	assert_bool(attack.actor_can_perform()).is_true()

# --- SpringLoadAction ---

func test_spring_load_actor_can_perform_requires_unready() -> void:
	var t := _spring_template(true)
	var unit := H.spawn_unit(self, PLAYER, Vector2i(0, 0), {}, false)
	var spear := WeaponInstance.make(t) as SpringWeaponInstance
	unit.add_item(spear)

	var action := SpringLoadAction.new()
	action.init(unit)
	assert_bool(action.actor_can_perform()).is_false()   # already ready — nothing to load

	spear.consume_readiness_for(t.extra_attacks[0])
	assert_bool(action.actor_can_perform()).is_true()

func test_spring_load_execute_restores_readiness() -> void:
	var t := _spring_template(true)
	var unit := H.spawn_unit(self, PLAYER, Vector2i(0, 0), {}, false)
	var spear := WeaponInstance.make(t) as SpringWeaponInstance
	unit.add_item(spear)
	spear.consume_readiness_for(t.extra_attacks[0])

	var action := SpringLoadAction.new()
	action.init(unit)
	action.execute()

	assert_bool(unit.can_reload_weapon()).is_false()
	assert_bool(unit.is_attack_fireable(t.main_attack)).is_true()
