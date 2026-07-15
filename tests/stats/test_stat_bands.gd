# The band doctrine as executable spec (docs/design/stats.md, #55): every input stat
# casts a small, coarse, bounded shadow. Pure functions — rung values, both boundaries,
# and the invariant that makes the whole session behavior-neutral: DEFAULTS LAND ON 0.
extends GdUnitTestSuite

func test_dex_mov_band_rungs() -> void:
	assert_int(Stats.dex_mov_band(0)).is_equal(-1)
	assert_int(Stats.dex_mov_band(3)).is_equal(-1)   # top of low rung
	assert_int(Stats.dex_mov_band(4)).is_equal(0)    # bottom of mid rung
	assert_int(Stats.dex_mov_band(7)).is_equal(0)    # top of mid rung
	assert_int(Stats.dex_mov_band(8)).is_equal(1)    # bottom of high rung
	assert_int(Stats.dex_mov_band(12)).is_equal(1)

func test_con_mhp_band_rungs() -> void:
	assert_int(Stats.con_mhp_band(0)).is_equal(-2)
	assert_int(Stats.con_mhp_band(3)).is_equal(-2)
	assert_int(Stats.con_mhp_band(4)).is_equal(0)
	assert_int(Stats.con_mhp_band(7)).is_equal(0)
	assert_int(Stats.con_mhp_band(8)).is_equal(2)
	assert_int(Stats.con_mhp_band(12)).is_equal(2)

func test_con_mhp_band_extremes_within_doctrine() -> void:
	# stats.md: extremes no more than 4-5 MHP apart end to end.
	var spread := Stats.con_mhp_band(99) - Stats.con_mhp_band(0)
	assert_int(spread).is_less_equal(5)

func test_per_ldr_band_rungs() -> void:
	assert_int(Stats.per_ldr_band(0)).is_equal(-1)
	assert_int(Stats.per_ldr_band(3)).is_equal(-1)
	assert_int(Stats.per_ldr_band(4)).is_equal(0)
	assert_int(Stats.per_ldr_band(7)).is_equal(0)
	assert_int(Stats.per_ldr_band(8)).is_equal(1)
	assert_int(Stats.per_ldr_band(12)).is_equal(1)

func test_all_defaults_land_on_the_zero_rung() -> void:
	# The no-behavior-shift guarantee: a default statline (5s) takes 0 from every band,
	# so pre-CON units, scenarios, and fixtures keep their exact numbers.
	assert_int(Stats.dex_mov_band(Stats.STAT_DEFAULTS[Stats.Stat.DEX])).is_equal(0)
	assert_int(Stats.con_mhp_band(Stats.STAT_DEFAULTS[Stats.Stat.CON])).is_equal(0)
	assert_int(Stats.per_ldr_band(Stats.STAT_DEFAULTS[Stats.Stat.PER])).is_equal(0)

func test_armor_def_multiplier_with_no_base() -> void:
	# DEF x CON (stats.md): naked or zero-CON -> zero DEF; CON 5 wears armor as printed.
	assert_int(Stats.armor_def(10, 5)).is_equal(10)   # default body = printed value
	assert_int(Stats.armor_def(10, 8)).is_equal(16)
	assert_int(Stats.armor_def(10, 2)).is_equal(4)
	assert_int(Stats.armor_def(10, 0)).is_equal(0)    # CON 0 can't brace armor
	assert_int(Stats.armor_def(0, 9)).is_equal(0)     # no gear, no DEF — regardless of CON
	assert_int(Stats.armor_def(3, 4)).is_equal(2)     # 2.4 rounds down
	assert_int(Stats.armor_def(7, 5)).is_equal(7)
