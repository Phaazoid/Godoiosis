# DROWNING (#1657): in water too deep to stand in, alive. Out of action and on a rescue clock like a
# down, but not a down: no health lost, no wound, and never the Crisis gambit. These cases drive the
# live body's doors (Unit.go_under and the ones it meets); how a pass gets a body into the water, and
# that the plan's twin agrees, is test_falls and test_melt_sinks; that both hosts eject a drowner at
# the pass end is test_execute_two_hosts.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


func _unit(mhp := 20) -> Unit:
	return H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.MHP: mhp}, false)


func _armed(mhp := 20) -> Unit:
	var unit := _unit(mhp)
	unit.unit_instance.jobs.append("berserker")
	assert_bool(unit.has_live_ability(Abilities.Id.CRISIS)).override_failure_message(
			"fixture: the berserker job no longer arms Crisis").is_true()
	return unit


func _under(unit: Unit) -> void:
	unit.go_under()
	assert_bool(unit.is_drowning()).override_failure_message("fixture: the unit did not go under").is_true()


# --- going under ---------------------------------------------------------------------------------

func test_going_under_keeps_health_and_starts_the_drowning_clock() -> void:
	var unit := _unit()
	unit.set_current_hp(13)
	var under: Array[Unit] = []
	var downs: Array[Unit] = []
	unit.went_under.connect(func(u: Unit) -> void: under.append(u))
	unit.went_downed.connect(func(u: Unit) -> void: downs.append(u))

	unit.go_under()

	assert_bool(unit.is_drowning()).is_true()
	assert_bool(unit.is_active()).override_failure_message("a drowning unit still counts as standing").is_false()
	assert_bool(unit.awaits_rescue()).is_true()
	assert_int(unit.get_current_hp()).override_failure_message("the water took health").is_equal(13)
	assert_int(unit.downed_turns_remaining).is_equal(Unit.DROWNING_TURNS)
	assert_bool(unit.wounded).override_failure_message("going under wounded the unit, as only a down does").is_false()
	assert_array(under).contains_exactly([unit])
	assert_array(downs).override_failure_message("going under announced a down").is_empty()


# The #1657 report, at the body's own door: the water is never a would-be-down, armed or not.
func test_an_armed_unit_goes_under_without_the_gambit() -> void:
	var unit := _armed()

	unit.go_under()

	assert_bool(unit.is_drowning()).is_true()
	assert_bool(unit.in_crisis).override_failure_message("going under fired Crisis (#1657)").is_false()
	assert_bool(unit.crisis_surge_pending).is_false()
	assert_int(unit.get_current_hp()).is_equal(unit.get_max_hp())


# Pick 2: a downed body that goes into the water stays down, on the water's one turn.
func test_a_downed_body_in_the_water_stays_down_on_one_turn() -> void:
	var unit := _unit()
	unit.take_damage(unit.get_current_hp())
	assert_bool(unit.is_downed()).override_failure_message("fixture: the unit did not go down").is_true()
	var under: Array[Unit] = []
	unit.went_under.connect(func(u: Unit) -> void: under.append(u))

	unit.go_under()

	assert_bool(unit.is_downed()).override_failure_message("the water turned a down into a drowning").is_true()
	assert_int(unit.downed_turns_remaining).is_equal(Unit.DOWNED_IN_WATER_TURNS)
	assert_array(under).override_failure_message("a body already down announced going under").is_empty()


# A heal stopped the clock on land; the water starts it again.
func test_the_water_restarts_a_clock_a_heal_stopped() -> void:
	var unit := _unit()
	unit.take_damage(unit.get_current_hp())
	unit.heal(5)
	assert_int(unit.downed_turns_remaining).override_failure_message("fixture: the heal did not stop the clock") \
		.is_equal(-1)

	unit.go_under()

	assert_int(unit.downed_turns_remaining).is_equal(Unit.DOWNED_IN_WATER_TURNS)


func test_going_under_twice_changes_nothing() -> void:
	var unit := _unit()
	_under(unit)
	unit.tick_downed_countdown()
	var clock := unit.downed_turns_remaining
	unit.go_under()
	assert_int(unit.downed_turns_remaining).override_failure_message("going under twice reset the clock") \
		.is_equal(clock)


# --- the clock -----------------------------------------------------------------------------------

func test_the_drowning_clock_ticks_down_and_kills() -> void:
	var unit := _unit()
	_under(unit)
	for turn in Unit.DROWNING_TURNS - 1:
		unit.tick_downed_countdown()
		assert_bool(unit.is_drowning()).override_failure_message("drowned early, at tick %d" % (turn + 1)).is_true()
	unit.tick_downed_countdown()
	assert_bool(unit.is_dead()).override_failure_message("the clock ran out and the unit is still treading water") \
		.is_true()


# Pick 4: a heal restores health, never the clock -- only a rescue gets you out of the lake.
func test_a_heal_mends_a_drowner_but_the_clock_runs() -> void:
	var unit := _unit()
	unit.set_current_hp(5)
	_under(unit)

	unit.heal(6)

	assert_int(unit.get_current_hp()).is_equal(11)
	assert_int(unit.downed_turns_remaining).override_failure_message("a heal stopped a drowning clock") \
		.is_equal(Unit.DROWNING_TURNS)
	assert_bool(unit.is_drowning()).is_true()


# --- a blow in the water -------------------------------------------------------------------------

# Pick 1: a blow that would down a drowner downs it, in the water, on the water's clock.
func test_a_blow_that_downs_a_drowner_downs_it_on_the_waters_clock() -> void:
	var unit := _unit()
	_under(unit)

	unit.take_damage(unit.get_current_hp())

	assert_bool(unit.is_downed()).is_true()
	assert_bool(unit.wounded).is_true()
	assert_int(unit.downed_turns_remaining).is_equal(Unit.DOWNED_IN_WATER_TURNS)


# A BLOW can still fire the gambit; it stands you up, it does not swim you out.
func test_a_blow_that_fires_crisis_in_the_water_leaves_the_unit_drowning() -> void:
	var unit := _armed()
	_under(unit)

	unit.take_damage(unit.get_current_hp())

	assert_bool(unit.in_crisis).override_failure_message("a would-be-down blow on an armed drowner skipped the gambit") \
		.is_true()
	assert_bool(unit.is_drowning()).override_failure_message("the gambit pulled the unit out of the water").is_true()
	assert_int(unit.get_current_hp()).is_equal(Abilities.CRISIS_REVIVE_HP)
	assert_int(unit.downed_turns_remaining).override_failure_message("the gambit stopped the drowning clock") \
		.is_equal(Unit.DROWNING_TURNS)


# --- out of it -----------------------------------------------------------------------------------

func test_a_drowner_cannot_be_commanded() -> void:
	var unit := _unit()
	_under(unit)
	assert_str(RulesService.standing_block_reason(unit)).contains("drowning")
	assert_str(RulesService.command_block_reason(unit, Team.Faction.PLAYER)).is_not_empty()


# Pick 3: a rescue brings a drowner back up at its own health, and unwounded.
func test_a_rescued_drowner_stands_at_its_health_unwounded() -> void:
	var unit := _unit()
	unit.set_current_hp(14)
	_under(unit)

	unit.revive()

	assert_bool(unit.is_active()).is_true()
	assert_int(unit.get_current_hp()).is_equal(14)
	assert_bool(unit.wounded).override_failure_message("a rescue from the water left a wound").is_false()
	assert_int(unit.downed_turns_remaining).is_equal(-1)


# --- a save --------------------------------------------------------------------------------------

func test_a_drowner_reloads_drowning_with_its_clock_and_no_event() -> void:
	var unit := _unit()
	unit.set_current_hp(9)
	_under(unit)
	unit.tick_downed_countdown()
	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(unit)
	var loaded: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(9, 9), {Stats.Stat.MHP: 20}, false)
	var under: Array[Unit] = []
	loaded.went_under.connect(func(u: Unit) -> void: under.append(u))

	entry.apply_unit_state(loaded)

	assert_bool(loaded.is_drowning()).is_true()
	assert_int(loaded.downed_turns_remaining).is_equal(Unit.DROWNING_TURNS - 1)
	assert_int(loaded.get_current_hp()).is_equal(9)
	assert_bool(loaded.wounded).is_false()
	assert_bool(loaded.downed_sprite.visible).override_failure_message("a reloaded drowner is drawn standing") \
		.is_true()
	assert_array(under).override_failure_message("a restore replayed the event, not the result").is_empty()
