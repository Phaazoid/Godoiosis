# Carbine magazine (#84, sixth family signature): the #73 readiness bool generalized to a COUNTER.
# The Springspear spends readiness on a SECONDARY (Spring) and keeps a free main (Stab); the Carbine
# spends it on the MAIN and has no secondary at all, so an empty magazine leaves the weapon with
# nothing to fire until a Reload main action. That difference is what this suite pins — the shared
# seam (is_attack_fireable / consume_readiness_for / can_reload / reload) is unchanged, only the
# family's reading of it. Also covers the two gates the empty state newly reaches: the Attack menu
# entry (Unit.can_fire_default_attack) and countering (Unit.attack_source_can_counter).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

# A Carbine-shaped template: one main attack that both requires and consumes a shot, no extras.
# `ranged` adds the real min/max 2 pattern; the default pattern-less shape keeps reach at
# Manhattan 1 for the tests that only care about ammo.
func _carbine_template(ranged: bool = false) -> WeaponData:
	var shot := WeaponAttackData.new()
	shot.display_name = "Shot"
	shot.power = 4
	shot.requires_readiness = true
	shot.consumes_readiness = true
	if ranged:
		var pattern := ManhattanRangePattern.new()
		pattern.max_range = 2
		pattern.min_range = 2
		shot.attack_pattern = pattern
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CARBINE
	t.main_attack = shot
	t.scaling_blend = {Stats.Stat.STR: 100}
	return t

func _carbine(ranged: bool = false) -> CarbineWeaponInstance:
	return WeaponInstance.make(_carbine_template(ranged)) as CarbineWeaponInstance

# Fire `count` shots through the post-fire hook (the same call AttackAction.execute makes).
func _fire(weapon: CarbineWeaponInstance, count: int) -> void:
	for _i in range(count):
		weapon.consume_readiness_for(weapon.template.main_attack)

# --- the magazine state machine ---

func test_starts_with_a_full_magazine() -> void:
	var w := _carbine()
	assert_int(w.shots_remaining).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE)
	assert_bool(w.can_reload()).is_false()   # nothing to top off
	assert_bool(w.is_attack_fireable(w.template.main_attack)).is_true()

func test_a_partial_magazine_still_fires_and_can_top_off() -> void:
	# The deliberate difference from a bool: one spent shot is not "spent". You may still fire,
	# AND you may choose to burn a turn reloading early rather than get caught empty.
	var w := _carbine()
	_fire(w, 1)
	assert_int(w.shots_remaining).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE - 1)
	assert_bool(w.is_attack_fireable(w.template.main_attack)).is_true()
	assert_bool(w.can_reload()).is_true()

func test_an_empty_magazine_cannot_fire() -> void:
	var w := _carbine()
	_fire(w, CarbineWeaponInstance.MAGAZINE_SIZE)
	assert_int(w.shots_remaining).is_equal(0)
	assert_bool(w.is_attack_fireable(w.template.main_attack)).is_false()
	assert_bool(w.can_reload()).is_true()

func test_reload_refills_the_whole_magazine() -> void:
	var w := _carbine()
	_fire(w, CarbineWeaponInstance.MAGAZINE_SIZE)
	w.reload()
	assert_int(w.shots_remaining).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE)
	assert_bool(w.is_attack_fireable(w.template.main_attack)).is_true()
	assert_bool(w.can_reload()).is_false()

func test_shots_never_go_negative() -> void:
	var w := _carbine()
	_fire(w, CarbineWeaponInstance.MAGAZINE_SIZE + 3)
	assert_int(w.shots_remaining).is_equal(0)

func test_an_attack_that_does_not_require_readiness_fires_on_empty() -> void:
	# The same authored knob Stab.requires_readiness is: a future mod-granted bayonet poke could
	# stay usable with the magazine dry. Nothing authors this on the Carbine today.
	var w := _carbine()
	_fire(w, CarbineWeaponInstance.MAGAZINE_SIZE)
	var melee := WeaponAttackData.new()
	melee.display_name = "Bayonet"
	assert_bool(w.is_attack_fireable(melee)).is_true()

func test_two_carbines_track_their_magazines_independently() -> void:
	# The bug the whole subclass seam exists to prevent (#73), re-pinned for a counter.
	var a := _carbine()
	var b := _carbine()
	_fire(a, CarbineWeaponInstance.MAGAZINE_SIZE)
	assert_int(a.shots_remaining).is_equal(0)
	assert_int(b.shots_remaining).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE)

func test_a_copied_carbine_starts_loaded() -> void:
	# Battle-scoped: shots_remaining is not @export'ed, so copy_equippable/make hand back a fresh
	# magazine every mission — the same reset trick SpringspearWeaponInstance.ready uses.
	var w := _carbine()
	_fire(w, CarbineWeaponInstance.MAGAZINE_SIZE)
	var copy := w.copy_equippable() as CarbineWeaponInstance
	assert_int(copy.shots_remaining).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE)
	assert_object(copy.template).is_same(w.template)   # template stays shared

# --- status readout (#44: the player must SEE the state their decisions turn on) ---

func test_status_text_reports_the_count_and_changes_as_it_drains() -> void:
	var w := _carbine()
	var full := w.status_text()
	_fire(w, 1)
	assert_str(w.status_text()).is_not_equal(full)   # a counter must be visible, not just empty/not
	_fire(w, CarbineWeaponInstance.MAGAZINE_SIZE - 1)
	assert_str(w.status_text().to_lower()).contains("reload")   # names the fix when it's empty

# --- reload_label: one order, per-family wording ---

func test_reload_label_defaults_to_reload_and_springspear_overrides_it() -> void:
	assert_str(_carbine().reload_label()).is_equal("Reload")
	var spear_template := WeaponData.new()
	spear_template.weapon_type = WeaponData.WeaponType.SPRINGSPEAR
	spear_template.main_attack = WeaponAttackData.new()
	assert_str(WeaponInstance.make(spear_template).reload_label()).is_equal("Spring Load")

# --- Unit-level gates the empty magazine newly reaches ---

func _armed_unit(ranged: bool = false, faction: Team.Faction = PLAYER, cell: Vector2i = Vector2i(0, 0)) -> Unit:
	var unit := H.spawn_unit(self, faction, cell, {}, false)
	unit.equipped_weapon = _carbine(ranged)
	return unit

func test_empty_carbine_cannot_fire_its_default_attack() -> void:
	# Attack always fires the DEFAULT attack since the 2026-07-24 menu refactor, so the menu entry
	# has to gate on that one attack — otherwise the player opens targeting for an order
	# AttackAction.actor_can_perform will then refuse (Law #3).
	var unit := _armed_unit()
	assert_bool(unit.can_fire_default_attack()).is_true()
	_fire(unit.get_equipped_weapon() as CarbineWeaponInstance, CarbineWeaponInstance.MAGAZINE_SIZE)
	assert_bool(unit.can_fire_default_attack()).is_false()
	assert_bool(unit.has_any_fireable_attack()).is_false()   # no secondary to fall back on

func test_weapon_action_appears_only_once_there_is_something_to_reload() -> void:
	var unit := _armed_unit()
	assert_bool(unit.has_weapon_actions()).is_false()   # nothing to reload, no secondaries
	_fire(unit.get_equipped_weapon() as CarbineWeaponInstance, 1)
	assert_bool(unit.has_weapon_actions()).is_true()    # top-off is a real choice
	assert_bool(unit.can_reload_weapon()).is_true()

func test_reload_action_rearms_a_carbine_through_the_generic_seam() -> void:
	var unit := _armed_unit()
	var weapon := unit.get_equipped_weapon() as CarbineWeaponInstance
	_fire(weapon, CarbineWeaponInstance.MAGAZINE_SIZE)

	var action := ReloadAction.new()
	action.init(unit)
	assert_bool(action.actor_can_perform()).is_true()
	action.execute()

	assert_int(weapon.shots_remaining).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE)
	assert_bool(action.actor_can_perform()).is_false()   # full again — nothing left to reload

# --- countering on an empty magazine (dev call 2026-07-25: a shot is a shot) ---

func test_an_empty_carbine_cannot_counter() -> void:
	var unit := _armed_unit()
	assert_bool(unit.attack_source_can_counter()).is_true()
	_fire(unit.get_equipped_weapon() as CarbineWeaponInstance, CarbineWeaponInstance.MAGAZINE_SIZE)
	assert_bool(unit.attack_source_can_counter()).is_false()

func test_a_spent_springspear_can_no_longer_counter_with_stab() -> void:
	# The latent hole the Carbine exposed: Stab.requires_readiness is true, so the MENU refuses it
	# on a sprung spear — but attack_source_can_counter only read can_counter, so the spear kept
	# countering with an attack it couldn't otherwise fire. Same fix, both families.
	var unit := H.spawn_unit(self, PLAYER, Vector2i(0, 0), {}, false)
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.SPRINGSPEAR
	var stab := WeaponAttackData.new()
	stab.display_name = "Stab"
	stab.requires_readiness = true
	var spring := WeaponAttackData.new()
	spring.display_name = "Spring"
	spring.requires_readiness = true
	spring.consumes_readiness = true
	t.main_attack = stab
	t.extra_attacks = [spring] as Array[WeaponAttackData]
	var spear := WeaponInstance.make(t) as SpringspearWeaponInstance
	unit.equipped_weapon = spear

	assert_bool(unit.attack_source_can_counter()).is_true()
	spear.consume_readiness_for(spring)
	assert_bool(unit.attack_source_can_counter()).is_false()

func test_a_family_with_no_readiness_economy_counters_exactly_as_before() -> void:
	# Regression guard on the shared gate: the fireability term must be invisible to every weapon
	# that never gates anything (the base WeaponInstance no-op).
	var unit := H.spawn_unit(self, PLAYER, Vector2i(0, 0))   # fixture default: plain Chainsword
	assert_bool(unit.attack_source_can_counter()).is_true()

# --- reach: min_range 2 means a carbine cannot counter what closes on it ---

func test_carbine_counter_reach_excludes_the_adjacent_attacker() -> void:
	var sm := H.make_manager(self)
	var defender := H.spawn_solo(self, sm, ENEMY, Vector2i(0, 0), {}, false)
	defender.equipped_weapon = _carbine(true)
	var adjacent := H.spawn_solo(self, sm, PLAYER, Vector2i(1, 0))
	assert_bool(sm.can_counter(defender, adjacent)).is_false()   # inside the min range

func test_carbine_counters_at_exactly_range_two() -> void:
	var sm := H.make_manager(self)
	var defender := H.spawn_solo(self, sm, ENEMY, Vector2i(0, 0), {}, false)
	defender.equipped_weapon = _carbine(true)
	var standoff := H.spawn_solo(self, sm, PLAYER, Vector2i(2, 0))
	assert_bool(sm.can_counter(defender, standoff)).is_true()
