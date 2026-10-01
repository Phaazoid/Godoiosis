# Crisis as an equipped ability (#158): the gambit is ARMED by holding Abilities.Id.CRISIS (the
# Berserker job's signature), and an unwounded would-be-down then enters Crisis DIRECTLY inside
# take_damage -- the unit never transits DOWNED, emits no went_downed, and queues no ejection.
# This replaced the live interrupt (CrisisPrompt + OrderExecutor's between-hits offer poll), which
# was the game's only mid-execution input seam; with it gone, execution is pure playback and the
# preview's CRISIS rung and execution's are literally the same computation.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

# An unwounded berserker one exact-lethal hit from the gambit: MHP 10 so take_damage(10) is a
# would-be-down with zero overkill.
func _armed_unit() -> Unit:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.MHP: 10}, false)
	unit.unit_instance.jobs.append("berserker")
	return unit

func test_the_berserker_job_arms_crisis() -> void:
	var unit := _armed_unit()
	assert_bool(unit.has_live_ability(Abilities.Id.CRISIS)).is_true()
	unit.unit_instance.jobs.clear()
	assert_bool(unit.has_live_ability(Abilities.Id.CRISIS)) \
		.override_failure_message("the kit is derived live -- dropping the job must disarm").is_false()

func test_an_armed_unwounded_unit_enters_crisis_instead_of_downing() -> void:
	var unit := _armed_unit()
	var downs: Array[Unit] = []
	unit.went_downed.connect(func(u: Unit): downs.append(u))

	unit.take_damage(unit.get_current_hp())   # exact-lethal: would-be-down, zero overkill

	assert_bool(unit.is_active()).override_failure_message("the gambit must stand, not down").is_true()
	assert_bool(unit.in_crisis).is_true()
	assert_int(unit.get_current_hp()).is_equal(Abilities.CRISIS_REVIVE_HP)
	assert_bool(unit.wounded) \
		.override_failure_message("the gambit wounded the unit -- only a down does (#1174)").is_false()
	assert_bool(unit.crisis_surge_pending).is_true()
	assert_int(unit.downed_turns_remaining).is_equal(-1)
	# The load-bearing negative: no down was ever emitted, so nothing queued this unit for
	# ejection -- the old path went DOWNED first and got stood back up between hits.
	assert_int(downs.size()) \
		.override_failure_message("a Crisis entry must not transit DOWNED (went_downed fired)").is_equal(0)

func test_a_disarmed_unit_downs_like_anyone_else() -> void:
	# Same unit, same hit -- only the ability is gone. Unwounded without the gambit is just a down.
	var unit := _armed_unit()
	unit.unit_instance.jobs.clear()

	unit.take_damage(unit.get_current_hp())

	assert_bool(unit.is_downed()).is_true()
	assert_bool(unit.in_crisis).is_false()

func test_a_second_would_be_down_in_crisis_is_death() -> void:
	# The no-safety-net rider survives the re-homing untouched: in_crisis + a lethal hit = gone.
	var unit := _armed_unit()
	unit.take_damage(unit.get_current_hp())
	assert_bool(unit.in_crisis).is_true()

	unit.take_damage(Abilities.CRISIS_REVIVE_HP)

	assert_bool(unit.is_dead()) \
		.override_failure_message("a would-be-down in Crisis must be death, not a down").is_true()

# The gate at EXECUTION (#1174): a unit that has gone down this battle downs again, armed or not.
# Armed only after the first down, or that down would have been the gambit.
func test_a_wounded_armed_unit_downs_instead() -> void:
	var unit := _armed_unit()
	unit.unit_instance.jobs.clear()
	unit.take_damage(unit.get_current_hp())
	unit.revive()
	unit.set_current_hp(unit.get_max_hp())
	unit.unit_instance.jobs.append("berserker")
	assert_bool(unit.wounded).override_failure_message("fixture: the first down did not wound").is_true()

	unit.take_damage(unit.get_current_hp())

	assert_bool(unit.is_downed()).is_true()
	assert_bool(unit.in_crisis).override_failure_message("a wounded unit fired the gambit").is_false()
