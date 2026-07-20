# The live kit (#61, jobs.md "The ability chassis"): a unit's live abilities are the union of
# every held job's ability_pool, de-duplicated by id, with no training/unlock layer — holding
# the job is the whole gate. Coupled to the real "scout"/"tank" jobs (see job_fixtures.gd);
# their ability_pool is set per test and restored after.
extends GdUnitTestSuite

const F := preload("res://tests/support/job_fixtures.gd")

var _tank: JobData
var _tank_snap: Dictionary
var _scout: JobData
var _scout_snap: Dictionary

func before_test() -> void:
	_tank = JobCatalog.get_job("tank")
	_tank_snap = F.snapshot(_tank)
	_scout = JobCatalog.get_job("scout")
	_scout_snap = F.snapshot(_scout)

func after_test() -> void:
	F.restore(_tank, _tank_snap)
	F.restore(_scout, _scout_snap)

func _ability(id: Abilities.Id) -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	return a

func test_live_kit_is_empty_with_no_jobs() -> void:
	var inst := F.make_instance()
	assert_int(inst.get_live_abilities().size()).is_equal(0)
	assert_bool(inst.has_live_ability(Abilities.Id.IRON_WILL)).is_false()

func test_live_kit_unions_a_single_jobs_pool() -> void:
	_tank.ability_pool = [_ability(Abilities.Id.IRON_WILL), _ability(Abilities.Id.TAUNT)]
	var inst := F.make_instance()
	inst.add_job("tank")
	assert_bool(inst.has_live_ability(Abilities.Id.IRON_WILL)).is_true()
	assert_bool(inst.has_live_ability(Abilities.Id.TAUNT)).is_true()
	assert_bool(inst.has_live_ability(Abilities.Id.INTIMIDATION)).is_false()

func test_live_kit_unions_across_multiple_jobs() -> void:
	_tank.ability_pool = [_ability(Abilities.Id.IRON_WILL)]
	_scout.ability_pool = [_ability(Abilities.Id.WATERWALK)]
	var inst := F.make_instance()
	inst.add_job("tank")
	inst.add_job("scout")
	assert_bool(inst.has_live_ability(Abilities.Id.IRON_WILL)).is_true()
	assert_bool(inst.has_live_ability(Abilities.Id.WATERWALK)).is_true()

func test_live_kit_dedupes_the_same_ability_from_two_jobs() -> void:
	_tank.ability_pool = [_ability(Abilities.Id.TAUNT)]
	_scout.ability_pool = [_ability(Abilities.Id.TAUNT)]
	var inst := F.make_instance()
	inst.add_job("tank")
	inst.add_job("scout")
	var taunt_count := 0
	for ability in inst.get_live_abilities():
		if ability.id == Abilities.Id.TAUNT:
			taunt_count += 1
	assert_int(taunt_count).is_equal(1)

func test_live_kit_skips_none_id_abilities() -> void:
	# NONE = unfinished authoring (the enum's deliberate first value) — never live.
	_tank.ability_pool = [AbilityData.new()]   # id defaults to Abilities.Id.NONE
	var inst := F.make_instance()
	inst.add_job("tank")
	assert_int(inst.get_live_abilities().size()).is_equal(0)

func test_removing_a_job_drops_its_abilities_from_the_kit() -> void:
	_tank.ability_pool = [_ability(Abilities.Id.IRON_WILL)]
	var inst := F.make_instance()
	inst.add_job("tank")
	assert_bool(inst.has_live_ability(Abilities.Id.IRON_WILL)).is_true()
	inst.remove_job("tank")
	assert_bool(inst.has_live_ability(Abilities.Id.IRON_WILL)).is_false()
