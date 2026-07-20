# MOV as a flat readout (#61 descope: job-driven MOV base is parked — audit A4 reopens). This
# only pins that holding a job does NOT change MOV; the DEX-band/leg-throttle mechanics
# themselves are covered independently in tests/stats/test_mov.gd.
extends GdUnitTestSuite

const F := preload("res://tests/support/job_fixtures.gd")

func test_jobless_mov_uses_the_jobless_base() -> void:
	var inst := F.make_instance()
	assert_int(inst.get_mov()).is_equal(UnitInstance.JOBLESS_MOV_BASE)

func test_holding_a_job_does_not_change_mov() -> void:
	var inst := F.make_instance()
	inst.add_job("tank")
	assert_int(inst.get_mov()).is_equal(UnitInstance.JOBLESS_MOV_BASE)
