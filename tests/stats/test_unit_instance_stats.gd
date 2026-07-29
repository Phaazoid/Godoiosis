# UnitInstance stat plumbing (#55): missing-key robustness (seed + fallback) and the one
# max-HP truth (MHP base + CON band). Pure Resource tests — no scene, no manager.
extends GdUnitTestSuite

# A UnitInstance from a deliberately PARTIAL statline, as legacy .tres are.
func _make_instance(partial_stats: Dictionary[Stats.Stat, int]) -> UnitInstance:
	var data := UnitData.new()
	data.base_stats = partial_stats
	var inst := UnitInstance.new()
	inst.data = data
	inst.initialize()
	return inst

# get_max_hp takes the FINISHED effective CON since #106 — the chain's gear stage lives on Unit,
# a layer these bare instances don't have. At this layer the instance's own effective stat IS the
# whole chain, so passing it here is faithful; a real unit passes Unit.get_effective_stat.
func _max_hp(inst: UnitInstance) -> int:
	return inst.get_max_hp(inst.get_effective_stat(Stats.Stat.CON))

func test_initialize_seeds_missing_stats_from_defaults() -> void:
	var inst := _make_instance({Stats.Stat.MHP: 20})
	# Every canonical stat present after initialize (the dev editor iterates this dict).
	assert_int(inst.stats.size()).is_equal(Stats.STAT_DEFAULTS.size())
	assert_int(inst.get_base_stat(Stats.Stat.STR)).is_equal(Stats.STAT_DEFAULTS[Stats.Stat.STR])
	assert_int(inst.get_base_stat(Stats.Stat.CON)).is_equal(Stats.STAT_DEFAULTS[Stats.Stat.CON])

func test_get_base_stat_falls_back_to_default_for_missing_key() -> void:
	# The read-path guard behind the seeding — a key absent from the dict (any future
	# enum append) reads its default, never 0.
	var inst := _make_instance({Stats.Stat.MHP: 20})
	inst.stats.erase(Stats.Stat.CON)
	assert_int(inst.get_base_stat(Stats.Stat.CON)).is_equal(Stats.STAT_DEFAULTS[Stats.Stat.CON])

func test_max_hp_consumes_con_band() -> void:
	assert_int(_max_hp(_make_instance({Stats.Stat.MHP: 20, Stats.Stat.CON: 9}))).is_equal(22)
	assert_int(_max_hp(_make_instance({Stats.Stat.MHP: 20, Stats.Stat.CON: 5}))).is_equal(20)
	assert_int(_max_hp(_make_instance({Stats.Stat.MHP: 20, Stats.Stat.CON: 2}))).is_equal(18)

func test_initialize_spawns_at_banded_max_hp() -> void:
	# Regression guard for the #55 drift: spawn HP must read the BANDED max, not raw MHP.
	var inst := _make_instance({Stats.Stat.MHP: 20, Stats.Stat.CON: 9})
	assert_int(inst.get_current_hp()).is_equal(22)

func test_set_current_hp_clamps_to_banded_max() -> void:
	# The ceiling is PASSED in since #106 — UnitInstance can't derive it, because max HP depends
	# on gear it can't see. Unit.set_current_hp is the arg-free front door for real units.
	var inst := _make_instance({Stats.Stat.MHP: 20, Stats.Stat.CON: 9})
	inst.set_current_hp(999, _max_hp(inst))
	assert_int(inst.get_current_hp()).is_equal(22)

# Effective LDR left UnitInstance on 2026-07-28 (#106): both its terms are FINISHED effective
# stats, so it only computes correctly at the layer that can see the gear stage. It is
# Unit.get_effective_ldr now, covered in tests/stats/test_derived_stat_chain.gd.
#
# Weight left UnitInstance entirely on 2026-07-27: it is gear-only, and gear lives on the
# transient Unit, so there was nothing for the persistent instance to compute. Coverage moved
# to tests/stats/test_carried_weight.gd.
