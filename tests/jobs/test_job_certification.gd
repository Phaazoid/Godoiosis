# Certification rules (#58, jobs.md): certify-once, no stat prerequisites ever, is_locked
# as the one sanctioned gate (dev-tool force bypasses it), and the day-one starter grant.
# Pure Resource tests, coupled to the real authored "tank" job — see job_fixtures.gd.
extends GdUnitTestSuite

const F := preload("res://tests/support/job_fixtures.gd")

var _tank: JobData
var _tank_snap: Dictionary

func before_test() -> void:
	_tank = JobCatalog.get_job("tank")
	_tank_snap = F.snapshot(_tank)

func after_test() -> void:
	F.restore(_tank, _tank_snap)

func test_certify_unknown_job_fails() -> void:
	var inst := F.make_instance()
	assert_bool(inst.certify("no_such_job")).is_false()
	assert_bool(inst.certified_jobs.has("no_such_job")).is_false()

func test_certify_known_job_succeeds() -> void:
	var inst := F.make_instance()
	assert_bool(inst.certify("tank")).is_true()
	assert_bool(inst.certified_jobs.has("tank")).is_true()

func test_certify_is_idempotent() -> void:
	var inst := F.make_instance()
	inst.certify("tank")
	assert_bool(inst.certify("tank")).is_true()   # already-owned reads as success, not a re-grant

func test_no_stat_prerequisites_ever() -> void:
	# jobs.md doctrine: stats are fixed, so a stat gate would be a permanent lockout. A unit
	# with a terrible statline certifies exactly like anyone else.
	var inst := F.make_instance({Stats.Stat.STR: 0, Stats.Stat.DEX: 0, Stats.Stat.CON: 0})
	assert_bool(inst.certify("tank")).is_true()

func test_certify_refuses_a_locked_job() -> void:
	_tank.is_locked = true
	var inst := F.make_instance()
	assert_bool(inst.certify("tank")).is_false()
	assert_bool(inst.certified_jobs.has("tank")).is_false()

func test_certify_force_bypasses_the_lock() -> void:
	# The dev editor's certify button forces past is_locked; nothing else does.
	_tank.is_locked = true
	var inst := F.make_instance()
	assert_bool(inst.certify("tank", true)).is_true()
	assert_bool(inst.certified_jobs.has("tank")).is_true()

func test_certify_grants_the_starter_ability() -> void:
	var starter := AbilityData.new()
	starter.id = "test_starter_ability"
	_tank.starter_ability = starter
	var inst := F.make_instance()
	inst.certify("tank")
	assert_bool(inst.known_abilities.has("test_starter_ability")).is_true()

func test_certify_without_a_starter_grants_nothing() -> void:
	_tank.starter_ability = null
	var inst := F.make_instance()
	inst.certify("tank")
	assert_bool(inst.known_abilities.is_empty()).is_true()
