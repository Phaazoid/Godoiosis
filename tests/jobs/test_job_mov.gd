# MOV as a job-aware readout (#58, jobs.md, closes audit A4's last seam): job base replaces
# JOBLESS_MOV_BASE, subs don't touch it, and the maimed-leg-scout case threads through both
# the job base AND the DEX band. Coupled to the real "scout"/"tank" jobs (see
# job_fixtures.gd) — mov_base is set here per test since the placeholder content doesn't
# author one yet.
extends GdUnitTestSuite

const F := preload("res://tests/support/job_fixtures.gd")

var _scout: JobData
var _scout_snap: Dictionary
var _tank: JobData
var _tank_snap: Dictionary

func before_test() -> void:
	_scout = JobCatalog.get_job("scout")
	_scout_snap = F.snapshot(_scout)
	_tank = JobCatalog.get_job("tank")
	_tank_snap = F.snapshot(_tank)

func after_test() -> void:
	F.restore(_scout, _scout_snap)
	F.restore(_tank, _tank_snap)

func test_jobless_mov_uses_the_jobless_base() -> void:
	var inst := F.make_instance()
	assert_int(inst.get_mov()).is_equal(UnitInstance.JOBLESS_MOV_BASE)

func test_main_job_mov_base_replaces_the_jobless_base() -> void:
	_tank.mov_base = 3
	var inst := F.make_instance()
	inst.certify("tank")
	inst.set_main_job("tank")
	assert_int(inst.get_mov()).is_equal(3)   # DEX 5 -> band 0, nothing else in play

func test_sub_job_does_not_change_mov_base() -> void:
	_tank.mov_base = 3
	var inst := F.make_instance()
	inst.certify("tank")
	inst.set_unlocked_sub_slots(1)
	inst.set_sub_job(0, "tank")
	assert_int(inst.get_mov()).is_equal(UnitInstance.JOBLESS_MOV_BASE)

func test_maimed_leg_scout_reads_mov_through_job_base_and_dex_band() -> void:
	# The prompt's named done-when case. Scout base 5; one empty leg -> eff DEX ceil(5/2)=3
	# -> band -1 -> 4, THEN the one-empty-leg throttle halves (round up) -> 2. Both the job
	# base AND the DEX band are live in this one number.
	_scout.mov_base = 5
	var inst := F.make_instance()
	inst.certify("scout")
	inst.set_main_job("scout")
	inst.limbs[UnitInstance.LimbSlot.LEG_L].state = UnitInstance.LimbState.EMPTY
	assert_int(inst.get_mov()).is_equal(2)
