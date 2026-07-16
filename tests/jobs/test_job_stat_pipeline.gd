# The stat pipeline (#58, jobs.md): base -> limb substitution -> job nudge -> gear -> ceiling
# clamp, subs contribute no stats, and a ceiling clamps even a prosthetic's built-in stat.
# Coupled to the real "tank" job (see job_fixtures.gd) — its nudges/ceilings are set per test
# and restored after, since the authored placeholder content doesn't set them.
extends GdUnitTestSuite

const F := preload("res://tests/support/job_fixtures.gd")

var _tank: JobData
var _tank_snap: Dictionary

func before_test() -> void:
	_tank = JobCatalog.get_job("tank")
	_tank_snap = F.snapshot(_tank)

func after_test() -> void:
	F.restore(_tank, _tank_snap)

func test_jobless_unit_reads_plain_effective_stats() -> void:
	var inst := F.make_instance({Stats.Stat.CON: 7})
	assert_int(inst.get_effective_stat(Stats.Stat.CON)).is_equal(7)

func test_main_job_nudge_applies() -> void:
	_tank.stat_nudges = {Stats.Stat.CON: 2}
	var inst := F.make_instance({Stats.Stat.CON: 7})
	inst.certify("tank")
	inst.set_main_job("tank")
	assert_int(inst.get_effective_stat(Stats.Stat.CON)).is_equal(9)

func test_sub_job_contributes_no_stats() -> void:
	_tank.stat_nudges = {Stats.Stat.CON: 2}
	var inst := F.make_instance({Stats.Stat.CON: 7})
	inst.certify("tank")
	inst.set_unlocked_sub_slots(1)
	inst.set_sub_job(0, "tank")
	assert_int(inst.get_effective_stat(Stats.Stat.CON)).is_equal(7)   # no nudge — subs are abilities-only

func test_ceiling_clamps_the_effective_stat() -> void:
	_tank.stat_ceilings = {Stats.Stat.DEX: 3}
	var inst := F.make_instance({Stats.Stat.DEX: 8})
	inst.certify("tank")
	inst.set_main_job("tank")
	assert_int(inst.get_effective_stat(Stats.Stat.DEX)).is_equal(3)

func test_ceiling_leaves_room_below_cap_alone() -> void:
	_tank.stat_ceilings = {Stats.Stat.DEX: 10}
	var inst := F.make_instance({Stats.Stat.DEX: 5})
	inst.certify("tank")
	inst.set_main_job("tank")
	assert_int(inst.get_effective_stat(Stats.Stat.DEX)).is_equal(5)

func test_ceiling_clamps_even_a_prosthetic() -> void:
	# The prompt's named case: a cap is free to neuter a prosthetic's built-in stat.
	_tank.stat_ceilings = {Stats.Stat.DEX: 3}
	var inst := F.make_instance()
	inst.limbs[UnitInstance.LimbSlot.LEG_L].state = UnitInstance.LimbState.PROSTHETIC
	inst.limbs[UnitInstance.LimbSlot.LEG_L].prosthetic_stat = 12
	inst.limbs[UnitInstance.LimbSlot.LEG_R].state = UnitInstance.LimbState.PROSTHETIC
	inst.limbs[UnitInstance.LimbSlot.LEG_R].prosthetic_stat = 12
	inst.certify("tank")
	inst.set_main_job("tank")
	assert_int(inst.get_limb_effective_base(Stats.Stat.DEX)).is_equal(12)   # the prosthetic, uncapped
	assert_int(inst.get_effective_stat(Stats.Stat.DEX)).is_equal(3)          # the job caps it anyway

func test_pipeline_order_nudge_then_gear_then_ceiling() -> void:
	_tank.stat_nudges = {Stats.Stat.DEX: 2}
	_tank.stat_ceilings = {Stats.Stat.DEX: 8}
	var inst := F.make_instance({Stats.Stat.DEX: 5})
	inst.stat_modifiers[Stats.Stat.DEX] = 3
	inst.certify("tank")
	inst.set_main_job("tank")
	# 5 (base) + 2 (nudge) + 3 (gear) = 10, THEN clamp to 8.
	assert_int(inst.get_stat_before_ceiling(Stats.Stat.DEX)).is_equal(10)
	assert_int(inst.get_effective_stat(Stats.Stat.DEX)).is_equal(8)
