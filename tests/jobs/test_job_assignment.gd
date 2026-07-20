# Job assignment rules (#61 descope): no certification step, no slot cap, no main/sub split —
# a unit holds any number of jobs, freely. Pure Resource tests, coupled to the real authored
# "scout"/"tank" jobs (id-only checks, no fixture snapshot needed).
extends GdUnitTestSuite

const F := preload("res://tests/support/job_fixtures.gd")

func test_unknown_job_cannot_be_added() -> void:
	var inst := F.make_instance()
	assert_bool(inst.add_job("no_such_job")).is_false()
	assert_bool(inst.has_job("no_such_job")).is_false()

func test_known_job_can_be_added() -> void:
	var inst := F.make_instance()
	assert_bool(inst.add_job("tank")).is_true()
	assert_bool(inst.has_job("tank")).is_true()

func test_adding_the_same_job_twice_does_not_duplicate() -> void:
	var inst := F.make_instance()
	inst.add_job("tank")
	assert_bool(inst.add_job("tank")).is_false()   # already held -> no-op, not a re-add
	assert_int(inst.jobs.count("tank")).is_equal(1)

func test_remove_job_removes_it() -> void:
	var inst := F.make_instance()
	inst.add_job("tank")
	assert_bool(inst.remove_job("tank")).is_true()
	assert_bool(inst.has_job("tank")).is_false()

func test_removing_a_job_not_held_is_a_no_op() -> void:
	var inst := F.make_instance()
	assert_bool(inst.remove_job("tank")).is_false()

func test_jobless_unit_is_fully_valid() -> void:
	var inst := F.make_instance()
	assert_bool(inst.jobs.is_empty()).is_true()

func test_a_unit_can_hold_multiple_jobs_with_no_cap() -> void:
	# The explicit "no limits" ask this session descoped toward: no trio, no slot count.
	var inst := F.make_instance()
	assert_bool(inst.add_job("scout")).is_true()
	assert_bool(inst.add_job("tank")).is_true()
	assert_bool(inst.has_job("scout")).is_true()
	assert_bool(inst.has_job("tank")).is_true()
	assert_int(inst.jobs.size()).is_equal(2)
