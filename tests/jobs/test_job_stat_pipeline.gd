# The stat pipeline (#61 descope): base -> limb substitution -> SUMMED job nudges (every held
# job, not just one) -> gear. No ceiling stage (#58's clamp was descoped — docs/design/jobs.md
# "Parked"). Coupled to the real "scout"/"tank" jobs (see job_fixtures.gd) — their nudges are
# set per test and restored after, since the authored placeholder content doesn't set them.
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

func test_jobless_unit_reads_plain_effective_stats() -> void:
	var inst := F.make_instance({Stats.Stat.CON: 7})
	assert_int(inst.get_effective_stat(Stats.Stat.CON)).is_equal(7)

func test_held_job_nudge_applies() -> void:
	_tank.stat_nudges = {Stats.Stat.CON: 2}
	var inst := F.make_instance({Stats.Stat.CON: 7})
	inst.add_job("tank")
	assert_int(inst.get_effective_stat(Stats.Stat.CON)).is_equal(9)

func test_multiple_held_jobs_nudges_sum() -> void:
	# The key behavior change from #58's main-job-only nudge: every held job contributes.
	_tank.stat_nudges = {Stats.Stat.CON: 2}
	_scout.stat_nudges = {Stats.Stat.CON: 1}
	var inst := F.make_instance({Stats.Stat.CON: 7})
	inst.add_job("tank")
	inst.add_job("scout")
	assert_int(inst.get_effective_stat(Stats.Stat.CON)).is_equal(10)   # 7 + 2 + 1

func test_pipeline_order_nudge_then_gear_no_ceiling() -> void:
	_tank.stat_nudges = {Stats.Stat.DEX: 2}
	var inst := F.make_instance({Stats.Stat.DEX: 5})
	inst.stat_modifiers[Stats.Stat.DEX] = 3
	inst.add_job("tank")
	# 5 (base) + 2 (nudge) + 3 (gear) = 10, nothing clamps it (#61 descoped ceilings).
	assert_int(inst.get_effective_stat(Stats.Stat.DEX)).is_equal(10)
