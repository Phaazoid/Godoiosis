# UnitInstance stat plumbing (#55): missing-key robustness (seed + fallback), the one
# max-HP truth (MHP base + CON band), effective LDR (base + PER band), and the Weight
# readout. Pure Resource tests — no scene, no manager.
extends GdUnitTestSuite

# A UnitInstance from a deliberately PARTIAL statline, as legacy .tres are.
func _make_instance(partial_stats: Dictionary[Stats.Stat, int]) -> UnitInstance:
	var data := UnitData.new()
	data.base_stats = partial_stats
	var inst := UnitInstance.new()
	inst.data = data
	inst.initialize()
	return inst

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
	assert_int(_make_instance({Stats.Stat.MHP: 20, Stats.Stat.CON: 9}).get_max_hp()).is_equal(22)
	assert_int(_make_instance({Stats.Stat.MHP: 20, Stats.Stat.CON: 5}).get_max_hp()).is_equal(20)
	assert_int(_make_instance({Stats.Stat.MHP: 20, Stats.Stat.CON: 2}).get_max_hp()).is_equal(18)

func test_initialize_spawns_at_banded_max_hp() -> void:
	# Regression guard for the #55 drift: spawn HP must read the BANDED max, not raw MHP.
	var inst := _make_instance({Stats.Stat.MHP: 20, Stats.Stat.CON: 9})
	assert_int(inst.get_current_hp()).is_equal(22)

func test_set_current_hp_clamps_to_banded_max() -> void:
	var inst := _make_instance({Stats.Stat.MHP: 20, Stats.Stat.CON: 9})
	inst.set_current_hp(999)
	assert_int(inst.get_current_hp()).is_equal(22)

func test_effective_ldr_consumes_per_band() -> void:
	assert_int(_make_instance({Stats.Stat.LDR: 5, Stats.Stat.PER: 9}).get_effective_ldr()).is_equal(6)
	assert_int(_make_instance({Stats.Stat.LDR: 5, Stats.Stat.PER: 5}).get_effective_ldr()).is_equal(5)
	assert_int(_make_instance({Stats.Stat.LDR: 5, Stats.Stat.PER: 2}).get_effective_ldr()).is_equal(4)

func test_weight_is_the_con_body_term() -> void:
	# Derived, never authored; gear/module/inventory terms are still placeholder 0 (7/10).
	assert_int(_make_instance({Stats.Stat.CON: 7}).get_weight()).is_equal(7)
	assert_int(_make_instance({Stats.Stat.CON: 5}).get_weight()).is_equal(5)
