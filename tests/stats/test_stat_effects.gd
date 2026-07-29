# The ONE seam for temporary stat modifiers (#112): StatEffect, its storage on Unit, the
# body-vs-effective split that wear gates read, forced unequip when a gate stops passing, and the
# faction-turn-start expiry tick.
#
# It replaced UnitInstance.stat_modifiers — a stateful add/subtract bag whose only user was the
# Crisis surge via a hand-balanced +5/-5 pair. That pair is the shape this file exists to prevent:
# a source is now RETIRED, never subtracted, so an effect cannot leak.
#
# The two rules most worth not breaking:
#   * gates read get_body_stat (base -> limb -> jobs -> effects) and NEVER gear. That is what keeps
#     forced unequip to a single pass — removing a piece can't change another piece's answer.
#   * expiry ticks at the owning faction's TURN START, so a 3-turn effect covers three of THIS
#     unit's turns rather than three passes of everyone.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


func _effect(mods: Dictionary[Stats.Stat, int], turns: int = StatEffect.PERMANENT, source: String = "Test") -> StatEffect:
	return StatEffect.make(source, mods, turns)


func _armor(mods: Dictionary[Stats.Stat, int], def_power: int = 0) -> ArmorData:
	var armor := ArmorData.new()
	armor.def_power = def_power
	armor.stat_modifiers = mods
	return armor


func _gated_armor(stat: Stats.Stat, minimum: int) -> ArmorData:
	var armor := ArmorData.new()
	armor.stat_minimums[stat] = minimum
	return armor


# --- the contribution itself ---

func test_an_effect_shifts_the_effective_stat() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.STR: 5}, false)
	unit.apply_stat_effect(_effect({Stats.Stat.STR: 3}))
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(8)


func test_retiring_the_source_removes_the_contribution() -> void:
	# Removal retires a SOURCE, never subtracts a delta — the leak shape the old +5/-5 Crisis pair
	# had. Anything that forgets to remove leaves an effect, not a corrupted number.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.STR: 5}, false)
	unit.apply_stat_effect(_effect({Stats.Stat.STR: 3}, StatEffect.PERMANENT, "Tonic"))
	unit.remove_stat_effects_from("Tonic")
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(5)
	assert_bool(unit.has_stat_effect_from("Tonic")).is_false()


func test_effects_stack_additively() -> void:
	# Dev call 2026-07-28: additive only for now. A source that imposes a CAP is unsupported.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.STR: 5}, false)
	unit.apply_stat_effect(_effect({Stats.Stat.STR: 3}))
	unit.apply_stat_effect(_effect({Stats.Stat.STR: 2}))
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(10)


func test_one_effect_can_move_several_stats() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO,
		{Stats.Stat.STR: 5, Stats.Stat.DEX: 5}, false)
	unit.apply_stat_effect(_effect({Stats.Stat.STR: 2, Stats.Stat.DEX: -1}))
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(7)
	assert_int(unit.get_effective_stat(Stats.Stat.DEX)).is_equal(4)


func test_applying_copies_the_template() -> void:
	# Two units drinking the same authored tonic must not share one countdown.
	var template := _effect({Stats.Stat.STR: 2}, 3)
	var a: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var b: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(1, 0), {}, false)
	a.apply_stat_effect(template)
	b.apply_stat_effect(template)

	a.tick_stat_effects()

	assert_int(a.stat_effects[0].turns_remaining).is_equal(2)
	assert_int(b.stat_effects[0].turns_remaining).is_equal(3)
	assert_int(template.turns_remaining).is_equal(StatEffect.PERMANENT)   # the template is untouched


# --- effects reach derived readouts, exactly like gear does (#106) ---

func test_an_effect_reaches_max_hp() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO,
		{Stats.Stat.CON: 5, Stats.Stat.MHP: 20}, false)
	assert_int(unit.get_max_hp()).is_equal(20)
	unit.apply_stat_effect(_effect({Stats.Stat.CON: 5}))
	assert_int(unit.get_max_hp()).is_equal(22)


func test_an_effect_reaches_mov() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.DEX: 6}, false)
	var before := unit.get_mov()
	unit.apply_stat_effect(_effect({Stats.Stat.DEX: -3}))
	assert_int(unit.get_mov()).is_less(before)


# --- body vs effective: the split gates read ---

func test_body_stat_includes_effects_but_excludes_gear() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.CON: 5}, false)
	unit.apply_stat_effect(_effect({Stats.Stat.CON: 2}))
	unit.worn_armor = _armor({Stats.Stat.CON: 3})

	assert_int(unit.get_body_stat(Stats.Stat.CON)).is_equal(7)        # base + effect
	assert_int(unit.get_effective_stat(Stats.Stat.CON)).is_equal(10)  # ...+ gear


func test_the_pipeline_order_is_base_limb_jobs_effects_gear() -> void:
	# Moved from tests/stats/test_limb_slots.gd when the modifier stage left UnitInstance (#112).
	# Limb substitution happens BELOW the effect stage: one empty arm halves STR first, and the
	# effect lands on the halved value, not the raw one.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.STR: 7}, false)
	var fitting: UnitInstance.LimbFitting = unit.unit_instance.limbs[UnitInstance.LimbSlot.ARM_L]
	fitting.state = UnitInstance.LimbState.EMPTY

	unit.apply_stat_effect(_effect({Stats.Stat.STR: 2}))

	assert_int(unit.unit_instance.get_effective_stat(Stats.Stat.STR)).is_equal(4)   # ceil(7/2)
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(6)                 # + 2


# --- gates read effects (dev call 2026-07-28, amending #55/#89) ---

func test_a_buff_can_unlock_a_gated_armor() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.CON: 5}, false)
	var heavy := _gated_armor(Stats.Stat.CON, 8)
	assert_bool(heavy.can_equip(unit)).is_false()

	unit.apply_stat_effect(_effect({Stats.Stat.CON: 3}))

	assert_bool(heavy.can_equip(unit)).is_true()


func test_gates_still_ignore_the_wearers_own_gear() -> void:
	# The half of the doctrine that did NOT change: a piece's own tax must not move its own gate,
	# or equip legality becomes swap-order-dependent. It is also what stops forced unequip from
	# cascading — see the two tests below.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.CON: 5}, false)
	var heavy := _gated_armor(Stats.Stat.CON, 8)
	unit.worn_armor = _armor({Stats.Stat.CON: 5})
	assert_int(unit.get_effective_stat(Stats.Stat.CON)).is_equal(10)
	assert_bool(heavy.can_equip(unit)).is_false()


# --- forced unequip ---

func test_losing_the_buff_strips_the_armor_it_qualified_for() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.CON: 5}, false)
	unit.apply_stat_effect(_effect({Stats.Stat.CON: 3}, StatEffect.PERMANENT, "Tonic"))
	unit.inventory[0] = _gated_armor(Stats.Stat.CON, 8)
	assert_bool(unit.wear_armor(0)).is_true()

	unit.remove_stat_effects_from("Tonic")

	assert_object(unit.worn_armor).is_null()
	assert_object(unit.inventory[0]).is_not_null()   # still CARRIED, just not worn


func test_a_debuff_strips_armor_the_wearer_qualified_for_unaided() -> void:
	# The tactical half: debuffing an enemy under a gate takes their kit off.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.CON: 8}, false)
	unit.inventory[0] = _gated_armor(Stats.Stat.CON, 8)
	assert_bool(unit.wear_armor(0)).is_true()

	unit.apply_stat_effect(_effect({Stats.Stat.CON: -1}))

	assert_object(unit.worn_armor).is_null()


func test_armor_cannot_bootstrap_its_own_gate() -> void:
	# Gates never read gear, so a piece that GRANTS +CON can't keep itself on once the buff that
	# qualified it lapses. If this ever fails, gates started reading the finished stat and forced
	# unequip has become a cascade with a termination question.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.CON: 5}, false)
	var self_feeding := _gated_armor(Stats.Stat.CON, 8)
	self_feeding.stat_modifiers[Stats.Stat.CON] = 3
	unit.apply_stat_effect(_effect({Stats.Stat.CON: 3}, StatEffect.PERMANENT, "Tonic"))
	unit.inventory[0] = self_feeding
	assert_bool(unit.wear_armor(0)).is_true()

	unit.remove_stat_effects_from("Tonic")

	assert_object(unit.worn_armor).is_null()


func test_authored_bulwark_plate_needs_a_buff_and_loses_it_with_one() -> void:
	# Against REAL content, not a fixture: Bulwark Plate gates on CON 8. A CON-5 unit can't wear it
	# unaided, a tonic qualifies them, and losing the tonic takes it back off.
	var plate: ArmorData = ArmorCatalog.get_editable()["Bulwark Plate"]
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.CON: 5}, false)
	unit.inventory[0] = plate
	assert_bool(unit.wear_armor(0)).is_false()

	unit.apply_stat_effect(_effect({Stats.Stat.CON: 3}, StatEffect.PERMANENT, "Tonic"))
	assert_bool(unit.wear_armor(0)).is_true()

	unit.remove_stat_effects_from("Tonic")
	assert_object(unit.worn_armor).is_null()


func test_a_buff_can_knock_off_a_ceiling_gated_harness() -> void:
	# The inverted case, and the one that shows why gates are two-sided: Ballast Harness demands
	# DEX <= 4, so a DEX BUFF — normally a gift — tangles the wearer out of their own armour.
	var harness: ArmorData = ArmorCatalog.get_editable()["Ballast Harness"]
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.DEX: 4}, false)
	unit.inventory[0] = harness
	assert_bool(unit.wear_armor(0)).is_true()

	unit.apply_stat_effect(_effect({Stats.Stat.DEX: 2}))

	assert_object(unit.worn_armor).is_null()


func test_an_ungated_armor_is_never_stripped() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.CON: 5}, false)
	unit.inventory[0] = _armor({Stats.Stat.DEX: -1}, 4)
	assert_bool(unit.wear_armor(0)).is_true()

	unit.apply_stat_effect(_effect({Stats.Stat.CON: -3}))

	assert_object(unit.worn_armor).is_not_null()


func test_stripping_armor_settles_hp_against_the_new_max() -> void:
	# The full settle chain in one case: an effect lapses -> the gate fails -> armour comes off ->
	# CON drops -> max HP drops -> current HP re-clamps. Order is load-bearing.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO,
		{Stats.Stat.CON: 5, Stats.Stat.MHP: 20}, false)
	unit.apply_stat_effect(_effect({Stats.Stat.CON: 3}, StatEffect.PERMANENT, "Tonic"))
	var plate := _gated_armor(Stats.Stat.CON, 8)
	plate.stat_modifiers[Stats.Stat.CON] = 2
	unit.inventory[0] = plate
	assert_bool(unit.wear_armor(0)).is_true()
	assert_int(unit.get_max_hp()).is_equal(22)     # CON 5+3+2 = 10 -> band +2
	unit.set_current_hp(22)

	unit.remove_stat_effects_from("Tonic")

	assert_object(unit.worn_armor).is_null()
	assert_int(unit.get_max_hp()).is_equal(20)
	assert_int(unit.get_current_hp()).is_equal(20)


# --- expiry ---

func test_a_timed_effect_lasts_exactly_its_duration() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.STR: 5}, false)
	unit.apply_stat_effect(_effect({Stats.Stat.STR: 3}, 3))

	for i in 2:
		unit.tick_stat_effects()
		assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(8)   # still up after 2 ticks

	unit.tick_stat_effects()
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(5)
	assert_bool(unit.stat_effects.is_empty()).is_true()


func test_a_permanent_effect_never_expires() -> void:
	# PERMANENT is the shape a future gear- or terrain-BOUND effect would use if it ever had to be
	# stored rather than derived. Nothing removes it but an explicit retire.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.STR: 5}, false)
	unit.apply_stat_effect(_effect({Stats.Stat.STR: 3}, StatEffect.PERMANENT))
	for i in 10:
		unit.tick_stat_effects()
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(8)


# --- Crisis, migrated onto the seam ---

func test_crisis_surge_applies_on_the_next_turn_start() -> void:
	# Primed on ENTRY, applied at the NEXT turn start — the entry pass stays "survives standing"
	# only (will-and-death.md ripple containment). That timing did not change with #112.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.STR: 5}, false)
	unit.enter_crisis()
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(5)

	unit.advance_crisis_surge()

	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(5 + Unit.CRISIS_SURGE)
	assert_bool(unit.has_stat_effect_from(Unit.CRISIS_SURGE_SOURCE)).is_true()


func test_crisis_surge_runs_for_three_turns() -> void:
	# Raised from 1 turn to 3 on 2026-07-28 (dev): a gambit this costly should feel powerful.
	# Ticks in the same order game._run_turn_start_ticks uses — tick FIRST, then advance, so the
	# turn the surge lands on is not immediately spent.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.STR: 5}, false)
	unit.enter_crisis()

	var surged: Array[bool] = []
	for turn in 5:
		unit.tick_stat_effects()
		unit.advance_crisis_surge()
		surged.append(unit.get_effective_stat(Stats.Stat.STR) > 5)

	assert_array(surged).contains_exactly([true, true, true, false, false])


func test_the_surge_cannot_leak() -> void:
	# The whole reason the bag went away: the old +5/-5 pair had to be balanced by hand, and a
	# missed clear made the surge permanent. Expiry now retires a source, so there is no subtraction
	# to forget and no way to over-apply.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.STR: 5}, false)
	unit.enter_crisis()
	unit.advance_crisis_surge()
	unit.advance_crisis_surge()   # a second call must not stack a second surge
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(5 + Unit.CRISIS_SURGE)

	for turn in 4:
		unit.tick_stat_effects()
	assert_int(unit.get_effective_stat(Stats.Stat.STR)).is_equal(5)
	assert_bool(unit.stat_effects.is_empty()).is_true()


# --- the signal ---

func test_stats_changed_fires_on_apply_and_retire() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var fired := [0]
	unit.stats_changed.connect(func() -> void: fired[0] += 1)

	unit.apply_stat_effect(_effect({Stats.Stat.STR: 1}, StatEffect.PERMANENT, "Tonic"))
	assert_int(fired[0]).is_equal(1)

	unit.remove_stat_effects_from("Tonic")
	assert_int(fired[0]).is_equal(2)


func test_stats_changed_does_not_fire_when_nothing_changed() -> void:
	# A no-op retire must stay silent, or every listener repaints on every turn tick for nothing.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var fired := [0]
	unit.stats_changed.connect(func() -> void: fired[0] += 1)

	unit.remove_stat_effects_from("NothingLikeThis")
	unit.tick_stat_effects()

	assert_int(fired[0]).is_equal(0)


func test_wearing_and_removing_armor_fires_stats_changed() -> void:
	# Gear is derived, not stored, but it still MOVES the effective stat — so it settles through
	# the same hook. Before #112 the inspect panel never repainted its stat grid on an armour swap.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	unit.inventory[0] = _armor({Stats.Stat.DEX: -1})
	var fired := [0]
	unit.stats_changed.connect(func() -> void: fired[0] += 1)

	assert_bool(unit.wear_armor(0)).is_true()
	unit.remove_armor()

	assert_int(fired[0]).is_equal(2)
