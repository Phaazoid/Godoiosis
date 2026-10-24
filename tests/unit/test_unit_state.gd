# UnitState (#1480 stage 1): a unit's live battle state and the body rules that read it, moved off the
# Unit node, which forwards to it. These pin the FORWARDING, the move's riskiest assumption: an
# in-place write through a Unit getter must land in the state's own array, an assignment must be what
# the state holds, and the state settles without the readout signal. The rules that moved are pinned
# by their own suites (test_derived_stat_chain, test_stat_effects, test_previewed_stats, ...), which
# reach them through the forwarders.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


func test_a_unit_owns_a_state_that_points_back_at_it() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	assert_object(unit.state).is_not_null()
	assert_object(unit.state.unit).is_same(unit)
	assert_object(unit.state.instance).is_same(unit.unit_instance)


func test_the_state_exists_before_the_unit_enters_the_tree() -> void:
	# Suites build a bare Unit.new() that never enters the tree, so _ready never runs for them.
	var unit: Unit = auto_free(Unit.new())
	assert_object(unit.state).is_not_null()
	assert_object(unit.state.unit).is_same(unit)


func test_an_in_place_write_through_the_unit_lands_in_the_state() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var item := ArmorData.new()

	unit.inventory[2] = item
	unit.element_states.append(Elemental.State.WET)
	unit.stat_effects.append(StatEffect.make("Test", {Stats.Stat.STR: 1}, StatEffect.PERMANENT))

	assert_object(unit.state.inventory[2]).is_same(item)
	assert_bool(unit.state.element_states.has(Elemental.State.WET)).is_true()
	assert_int(unit.state.stat_effects.size()).is_equal(1)
	# The getters hand back the state's own arrays, never copies.
	assert_bool(is_same(unit.inventory, unit.state.inventory)).is_true()
	assert_bool(is_same(unit.element_states, unit.state.element_states)).is_true()
	assert_bool(is_same(unit.stat_effects, unit.state.stat_effects)).is_true()


func test_an_assignment_through_the_unit_is_what_the_state_holds() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	var armor := ArmorData.new()
	var body := UnitInstance.new()

	unit.worn_armor = armor
	unit.lifecycle_state = Unit.LifecycleState.DOWNED
	unit.wounded = true
	unit.downed_turns_remaining = 2
	unit.downed_turns_remaining -= 1
	unit.unit_instance = body

	assert_object(unit.state.worn_armor).is_same(armor)
	assert_int(unit.state.lifecycle_state).is_equal(Unit.LifecycleState.DOWNED)
	assert_bool(unit.state.wounded).is_true()
	assert_int(unit.state.downed_turns_remaining).is_equal(1)
	assert_object(unit.state.instance).is_same(body)

	# And the other way: a write to the state is what the Unit reads.
	unit.state.in_crisis = true
	assert_bool(unit.in_crisis).is_true()


func test_the_state_settles_silently_and_the_unit_door_emits() -> void:
	# UnitState.settle is the gates, then the HP re-clamp, and emits nothing: stats_changed is the
	# Unit's, fired by _settle_stat_change after it.
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.CON: 5}, false)
	var bare_max := unit.get_max_hp()
	var armor := ArmorData.new()
	armor.stat_modifiers[Stats.Stat.CON] = 5
	armor.stat_minimums[Stats.Stat.STR] = unit.get_body_stat(Stats.Stat.STR) + 1   # a gate this body fails
	unit.worn_armor = armor   # assigned past the gate, the way a save or the Unit Editor puts it on
	var worn_max := unit.get_max_hp()
	assert_int(worn_max).override_failure_message(
			"the +CON piece should lift max HP, or the re-clamp below proves nothing").is_greater(bare_max)
	unit.set_current_hp(worn_max)
	var fired := [0]
	unit.stats_changed.connect(func() -> void: fired[0] += 1)

	unit.state.settle()

	assert_object(unit.worn_armor).is_null()
	assert_int(unit.get_current_hp()).is_equal(bare_max)
	assert_int(fired[0]).is_equal(0)

	unit.remove_armor()
	assert_int(fired[0]).is_equal(1)
