# MOV as a flat readout (#61 descope: job-driven MOV base is parked — audit A4 reopens). This
# only pins that holding a job does NOT change MOV; the DEX-band/leg-throttle mechanics
# themselves are covered independently in tests/stats/test_mov.gd.
extends GdUnitTestSuite

const F := preload("res://tests/support/job_fixtures.gd")

# get_mov takes the finished effective DEX since 2026-07-27 (see tests/stats/test_mov.gd);
# a bare instance has no gear, so its own effective DEX is the whole answer.
func _mov(inst: UnitInstance) -> int:
	return inst.get_mov(inst.get_effective_stat(Stats.Stat.DEX))

func test_jobless_mov_uses_the_jobless_base() -> void:
	var inst := F.make_instance()
	assert_int(_mov(inst)).is_equal(UnitInstance.JOBLESS_MOV_BASE)

func test_holding_a_job_does_not_change_mov() -> void:
	var inst := F.make_instance()
	inst.add_job("tank")
	assert_int(_mov(inst)).is_equal(UnitInstance.JOBLESS_MOV_BASE)
