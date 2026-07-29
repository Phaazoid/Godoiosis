# The PERSISTENT half of the live kit (#61, extended by #90 — jobs.md "The ability chassis"):
# innate abilities (the story/authored source, on UnitData) union every held job's ability_pool,
# de-duplicated by id, with no training/unlock layer — holding the job is the whole gate. Gear is
# the third source and joins one layer up, on Unit (see test_gear_granted_abilities.gd).
#
# UnitInstance deliberately has NO has_live_ability since #90: the only boolean form of that
# question belongs to Unit, which can see gear too. A jobs-only bool sitting next to it was the
# split-brain trap the refactor existed to remove, so these tests scan the list instead.
#
# Coupled to the real "scout"/"tank" jobs (see job_fixtures.gd); their ability_pool is set per
# test and restored after.
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

func _holds(inst: UnitInstance, id: Abilities.Id) -> bool:
	for ability in inst.get_live_abilities():
		if ability.id == id:
			return true
	return false

func _count(inst: UnitInstance, id: Abilities.Id) -> int:
	var n := 0
	for ability in inst.get_live_abilities():
		if ability.id == id:
			n += 1
	return n

# --- Jobs as a source ---------------------------------------------------------------------

func test_live_kit_is_empty_with_no_jobs() -> void:
	var inst := F.make_instance()
	assert_int(inst.get_live_abilities().size()).is_equal(0)
	assert_bool(_holds(inst, Abilities.Id.IRON_WILL)).is_false()

func test_live_kit_unions_a_single_jobs_pool() -> void:
	_tank.ability_pool = [_ability(Abilities.Id.IRON_WILL), _ability(Abilities.Id.TAUNT)]
	var inst := F.make_instance()
	inst.add_job("tank")
	assert_bool(_holds(inst, Abilities.Id.IRON_WILL)).is_true()
	assert_bool(_holds(inst, Abilities.Id.TAUNT)).is_true()
	assert_bool(_holds(inst, Abilities.Id.INTIMIDATION)).is_false()

func test_live_kit_unions_across_multiple_jobs() -> void:
	_tank.ability_pool = [_ability(Abilities.Id.IRON_WILL)]
	_scout.ability_pool = [_ability(Abilities.Id.WATERWALK)]
	var inst := F.make_instance()
	inst.add_job("tank")
	inst.add_job("scout")
	assert_bool(_holds(inst, Abilities.Id.IRON_WILL)).is_true()
	assert_bool(_holds(inst, Abilities.Id.WATERWALK)).is_true()

func test_live_kit_dedupes_the_same_ability_from_two_jobs() -> void:
	_tank.ability_pool = [_ability(Abilities.Id.TAUNT)]
	_scout.ability_pool = [_ability(Abilities.Id.TAUNT)]
	var inst := F.make_instance()
	inst.add_job("tank")
	inst.add_job("scout")
	assert_int(_count(inst, Abilities.Id.TAUNT)).is_equal(1)

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
	assert_bool(_holds(inst, Abilities.Id.IRON_WILL)).is_true()
	inst.remove_job("tank")
	assert_bool(_holds(inst, Abilities.Id.IRON_WILL)).is_false()

# --- Innate abilities as a source (#90) ---------------------------------------------------

func test_innate_abilities_are_live_with_no_jobs_at_all() -> void:
	# The story/authored source: what a character is BORN with, needing no job to unlock it.
	var inst := F.make_instance()
	inst.data.innate_abilities = [_ability(Abilities.Id.IRON_WILL)]
	assert_bool(_holds(inst, Abilities.Id.IRON_WILL)).is_true()

func test_innate_abilities_union_with_job_pools() -> void:
	_tank.ability_pool = [_ability(Abilities.Id.TAUNT)]
	var inst := F.make_instance()
	inst.data.innate_abilities = [_ability(Abilities.Id.IRON_WILL)]
	inst.add_job("tank")
	assert_bool(_holds(inst, Abilities.Id.IRON_WILL)).is_true()
	assert_bool(_holds(inst, Abilities.Id.TAUNT)).is_true()

func test_an_innate_ability_a_job_also_grants_appears_once() -> void:
	_tank.ability_pool = [_ability(Abilities.Id.TAUNT)]
	var inst := F.make_instance()
	inst.data.innate_abilities = [_ability(Abilities.Id.TAUNT)]
	inst.add_job("tank")
	assert_int(_count(inst, Abilities.Id.TAUNT)).is_equal(1)

func test_innate_abilities_survive_losing_every_job() -> void:
	# The point of the source split: jobs come and go, identity does not.
	_tank.ability_pool = [_ability(Abilities.Id.TAUNT)]
	var inst := F.make_instance()
	inst.data.innate_abilities = [_ability(Abilities.Id.IRON_WILL)]
	inst.add_job("tank")
	inst.remove_job("tank")
	assert_bool(_holds(inst, Abilities.Id.TAUNT)).is_false()
	assert_bool(_holds(inst, Abilities.Id.IRON_WILL)).is_true()

func test_innate_abilities_skip_none_ids_too() -> void:
	# One merge for every source means the NONE guard cannot be authored per-source.
	var inst := F.make_instance()
	inst.data.innate_abilities = [AbilityData.new()]
	assert_int(inst.get_live_abilities().size()).is_equal(0)
