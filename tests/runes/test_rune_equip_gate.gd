# #157: a rune a unit can channel NOTHING from is carryable, never wieldable — refused at every
# equip door, and forcibly unequipped (to inventory) when a maim's aura tax kills it mid-battle.
#
# The gate is "at least ONE channelable carving", never "all": a one-of-three rune is good gear.
# Two decided forks pinned here (dev, 2026-08-10): the gate applies to EVERYONE (no affinity
# exemption — a no-affinity unit and a blank rune both refuse), and scenario load bypasses it
# (a save is authoritative, the #89 armor precedent).
#
# The maim case is driven end to end through take_damage, not by calling the settle directly —
# a direct settle call could not see whether _go_downed actually reaches it (the issue's own ask).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const FIRE := Elemental.Element.FIRE

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

func _alchemist(aura: Dictionary[Elemental.Element, int], affinity: Array[Elemental.Element], cell: Vector2i = Vector2i.ZERO) -> Unit:
	var u: Unit = H.spawn_solo(self, _sm, Team.Faction.PLAYER, cell, {}, false)
	u.unit_instance.aura = aura
	u.unit_instance.affinity = affinity
	return u

func _carving(sigils: Array[Elemental.Element]) -> TransmutationData:
	var t: TransmutationData = TransmutationData.new()
	t.power = 5
	t.sigils.assign(sigils)
	return t

func _rune(carvings: Array[TransmutationData], size: RuneData.Size = RuneData.Size.LARGE) -> RuneData:
	var rune: RuneData = RuneData.new()
	rune.size = size
	for c: TransmutationData in carvings:
		assert_bool(rune.inscribe(c)).override_failure_message("fixture carving failed to inscribe").is_true()
	return rune

# A single-FIRE-sigil carving on a SMALL rune: channelable iff the wielder has FIRE aura >= 1.
func _single_carving_rune() -> RuneData:
	var carvings: Array[TransmutationData] = [_carving([FIRE])]
	return _rune(carvings, RuneData.Size.SMALL)

# ==============================================================================

# Zero aura in the temper element: both explicit doors refuse, hands stay empty.
func test_a_dead_rune_is_refused_at_both_equip_doors() -> void:
	var u: Unit = _alchemist({ FIRE: 0 }, [FIRE])
	var rune: RuneData = _single_carving_rune()
	assert_bool(u.add_item(rune)).is_true()

	assert_bool(u.set_equipped_weapon(rune)).is_false()
	assert_bool(u.equip_weapon_from_inventory(0)).is_false()
	assert_object(u.get_equipped_weapon()).is_null()

# The third door: add_item's auto-equip. The pickup succeeds — the rune lands CARRIED — but the
# unit is not armed with a source whose menus would silently vanish.
func test_a_dead_rune_lands_carried_not_equipped() -> void:
	var u: Unit = _alchemist({ FIRE: 0 }, [FIRE])
	var rune: RuneData = _single_carving_rune()

	assert_bool(u.add_item(rune)).is_true()
	assert_bool(u.inventory.has(rune)).is_true()
	assert_object(u.get_equipped_weapon()).is_null()

# Boundary: exactly enough aura equips, through auto-equip and the explicit door alike.
func test_exactly_enough_aura_equips() -> void:
	var u: Unit = _alchemist({ FIRE: 1 }, [FIRE])
	var rune: RuneData = _single_carving_rune()

	assert_bool(u.add_item(rune)).is_true()
	assert_object(u.get_equipped_weapon()).is_same(rune)   # auto-equip passed the gate

	u.unequip_weapon()
	assert_bool(u.equip_weapon_from_inventory(0)).is_true()
	assert_object(u.get_equipped_weapon()).is_same(rune)

# The partial case the gate's threshold exists for: one channelable carving of three is good gear.
func test_one_channelable_carving_of_three_equips() -> void:
	var u: Unit = _alchemist({ FIRE: 1 }, [FIRE])
	var carvings: Array[TransmutationData] = [
		_carving([FIRE]),                  # needs FIRE 1 — channelable
		_carving([FIRE, FIRE]),            # needs FIRE 2 — not
		_carving([FIRE, FIRE, FIRE]),      # needs FIRE 3 — not
	]
	var rune: RuneData = _rune(carvings)
	assert_int(rune.channelable(u).size()).override_failure_message("premise: exactly one carving channelable").is_equal(1)

	assert_bool(u.add_item(rune)).is_true()
	assert_object(u.get_equipped_weapon()).is_same(rune)

# Fork decision 1: gate EVERYONE. No affinity at all (the Rebecca rule's subject) still refuses —
# she can carry a rune, never wield one.
func test_a_no_affinity_unit_is_refused() -> void:
	var no_aura: Dictionary[Elemental.Element, int] = {}
	var no_affinity: Array[Elemental.Element] = []
	var u: Unit = _alchemist(no_aura, no_affinity)
	var rune: RuneData = _single_carving_rune()

	assert_bool(u.add_item(rune)).is_true()
	assert_object(u.get_equipped_weapon()).is_null()
	assert_bool(u.set_equipped_weapon(rune)).is_false()

# A blank (uncarved) rune has nothing to channel, so it refuses for everyone — a consequence of
# the rule's literal text, pinned deliberately.
func test_a_blank_rune_is_refused_even_for_a_capable_alchemist() -> void:
	var u: Unit = _alchemist({ FIRE: 3 }, [FIRE])
	var blank: RuneData = RuneData.new()

	assert_bool(u.add_item(blank)).is_true()
	assert_object(u.get_equipped_weapon()).is_null()
	assert_bool(u.set_equipped_weapon(blank)).is_false()

# Weapons are untouched by the gate (can_equip defaults true) — the fixture chainsword still
# equips through every door.
func test_a_weapon_is_untouched_by_the_gate() -> void:
	var u: Unit = H.spawn_solo(self, _sm, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var weapon: WeaponInstance = H.make_weapon()

	assert_bool(u.add_item(weapon)).is_true()
	assert_object(u.get_equipped_weapon()).is_same(weapon)

# The force-unequip, end to end: a legally-equipped wielder goes down unable to afford the Will
# cost, the maim's aura tax (-1 off the highest pool) kills the rune's temper depth, and the
# settle _go_downed already runs strips the rune — off the slot, still in inventory.
func test_a_maim_that_kills_the_rune_strips_it_to_inventory() -> void:
	var u: Unit = _alchemist({ FIRE: 1 }, [FIRE])
	var rune: RuneData = _single_carving_rune()
	assert_bool(u.add_item(rune)).is_true()
	assert_object(u.get_equipped_weapon()).is_same(rune)   # equipped legally

	u.unit_instance.set_current_will(0)                    # can't afford the down -> the rotation maims
	u.take_damage(u.get_current_hp())                      # overkill 0 -> a would-be-down rung, never KILLED

	assert_bool(u.is_downed()).override_failure_message("fixture failed to DOWN the unit").is_true()
	assert_int(u.get_element_aura(FIRE)).override_failure_message("the maim aura tax did not land").is_equal(0)
	assert_object(u.get_equipped_weapon()).override_failure_message("the dead rune was not stripped").is_null()
	assert_bool(u.inventory.has(rune)).override_failure_message("the stripped rune left inventory").is_true()

# Fork decision 2 / the #89 armor precedent: a save is authoritative — load assigns the slot
# directly and never re-runs the gate, even when the saved aura can no longer channel anything.
func test_scenario_load_never_regates_the_equipped_rune() -> void:
	var a: Unit = _alchemist({ FIRE: 1 }, [FIRE])
	var rune: RuneData = _single_carving_rune()
	assert_bool(a.add_item(rune)).is_true()
	assert_object(a.get_equipped_weapon()).is_same(rune)

	var entry: ScenarioUnitEntry = ScenarioUnitEntry.new()
	entry.capture_unit_state(a)
	entry.aura[FIRE] = 0   # the save says: aura gone, rune still equipped

	var b: Unit = H.spawn_solo(self, _sm, Team.Faction.PLAYER, Vector2i(2, 0), {}, false)
	entry.apply_unit_state(b)

	assert_int(b.get_element_aura(FIRE)).is_equal(0)
	var loaded: RuneData = b.get_equipped_weapon() as RuneData
	assert_object(loaded).override_failure_message("load re-ran the equip gate; a save is authoritative").is_not_null()
