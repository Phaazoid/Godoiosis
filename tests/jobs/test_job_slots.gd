# Slot rules (#58, jobs.md): only certified jobs slot, main and subs stay distinct, subs are
# gated one-by-one by unlocked_sub_slots, and jobless is always a fully valid state. No
# numeric job content needed here (id-based rules only), so no fixture snapshot/restore.
extends GdUnitTestSuite

const F := preload("res://tests/support/job_fixtures.gd")

func test_uncertified_job_cannot_slot_as_main() -> void:
	var inst := F.make_instance()
	assert_bool(inst.set_main_job("tank")).is_false()
	assert_str(inst.main_job).is_equal("")

func test_certified_job_slots_as_main() -> void:
	var inst := F.make_instance()
	inst.certify("tank")
	assert_bool(inst.set_main_job("tank")).is_true()
	assert_str(inst.main_job).is_equal("tank")

func test_clearing_main_job_is_always_legal() -> void:
	var inst := F.make_instance()
	inst.certify("tank")
	inst.set_main_job("tank")
	assert_bool(inst.set_main_job("")).is_true()
	assert_str(inst.main_job).is_equal("")

func test_uncertified_job_cannot_slot_as_sub() -> void:
	var inst := F.make_instance()
	inst.set_unlocked_sub_slots(2)
	assert_bool(inst.set_sub_job(0, "scout")).is_false()

func test_sub_slot_needs_unlocking_first() -> void:
	var inst := F.make_instance()
	inst.certify("scout")
	assert_bool(inst.set_sub_job(0, "scout")).is_false()   # unlocked_sub_slots defaults to 0
	inst.set_unlocked_sub_slots(1)
	assert_bool(inst.set_sub_job(0, "scout")).is_true()

func test_second_sub_slot_needs_its_own_unlock() -> void:
	var inst := F.make_instance()
	inst.certify("scout")
	inst.set_unlocked_sub_slots(1)
	assert_bool(inst.set_sub_job(1, "scout")).is_false()
	inst.set_unlocked_sub_slots(2)
	assert_bool(inst.set_sub_job(1, "scout")).is_true()

func test_unlocked_sub_slots_clamped_to_0_2() -> void:
	var inst := F.make_instance()
	inst.set_unlocked_sub_slots(-3)
	assert_int(inst.unlocked_sub_slots).is_equal(0)
	inst.set_unlocked_sub_slots(99)
	assert_int(inst.unlocked_sub_slots).is_equal(2)

func test_main_job_cannot_also_be_a_sub() -> void:
	var inst := F.make_instance()
	inst.certify("tank")
	inst.set_unlocked_sub_slots(1)
	inst.set_main_job("tank")
	assert_bool(inst.set_sub_job(0, "tank")).is_false()

func test_sub_job_cannot_also_become_main() -> void:
	var inst := F.make_instance()
	inst.certify("tank")
	inst.certify("scout")
	inst.set_unlocked_sub_slots(1)
	inst.set_sub_job(0, "scout")
	assert_bool(inst.set_main_job("scout")).is_false()

func test_jobless_unit_is_fully_valid() -> void:
	var inst := F.make_instance()
	assert_str(inst.main_job).is_equal("")
	assert_bool(inst.sub_jobs.is_empty()).is_true()
