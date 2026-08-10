# The band doctrine as executable spec (docs/design/stats.md, #55): every input stat
# casts a small, coarse, bounded shadow. Pure functions — rung values, both boundaries,
# and the invariant that makes the whole session behavior-neutral: DEFAULTS LAND ON 0.
#
# Boundaries are probed THROUGH the named threshold constants, never as literals (2026-08-10
# sweep): the thresholds are playtest-tunable, and retuning one must not turn this suite red.
# The rung HEIGHTS stay literal on purpose — they live in the band function bodies, not in named
# knobs, so they are the mechanism's shape and pinning them is this file's job.
extends GdUnitTestSuite

func test_dex_mov_band_rungs() -> void:
	# Retuned 2026-07-15 (jobs.md): the default TOPS its rung — one DEX point buys +1.
	assert_int(Stats.dex_mov_band(0)).is_equal(-1)
	assert_int(Stats.dex_mov_band(Stats.BAND_LOW_MAX)).is_equal(-1)        # top of low rung
	assert_int(Stats.dex_mov_band(Stats.BAND_LOW_MAX + 1)).is_equal(0)     # bottom of mid rung
	assert_int(Stats.dex_mov_band(Stats.DEX_MOV_MID_MAX)).is_equal(0)      # last point of the free rung
	assert_int(Stats.dex_mov_band(Stats.DEX_MOV_MID_MAX + 1)).is_equal(1)  # one point of investment jumps a rung
	assert_int(Stats.dex_mov_band(Stats.DEX_MOV_HIGH_MAX)).is_equal(1)
	assert_int(Stats.dex_mov_band(Stats.DEX_MOV_HIGH_MAX + 1)).is_equal(2) # the earned top rung
	assert_int(Stats.dex_mov_band(Stats.DEX_MOV_HIGH_MAX + 4)).is_equal(2) # ...and it caps there

func test_con_mhp_band_rungs() -> void:
	assert_int(Stats.con_mhp_band(0)).is_equal(-2)
	assert_int(Stats.con_mhp_band(Stats.BAND_LOW_MAX)).is_equal(-2)
	assert_int(Stats.con_mhp_band(Stats.BAND_LOW_MAX + 1)).is_equal(0)
	assert_int(Stats.con_mhp_band(Stats.BAND_MID_MAX)).is_equal(0)
	assert_int(Stats.con_mhp_band(Stats.BAND_MID_MAX + 1)).is_equal(2)
	assert_int(Stats.con_mhp_band(Stats.BAND_MID_MAX + 5)).is_equal(2)

func test_con_mhp_band_extremes_within_doctrine() -> void:
	# stats.md: extremes no more than 4-5 MHP apart end to end.
	var spread := Stats.con_mhp_band(99) - Stats.con_mhp_band(0)
	assert_int(spread).is_less_equal(5)

func test_per_ldr_band_rungs() -> void:
	assert_int(Stats.per_ldr_band(0)).is_equal(-1)
	assert_int(Stats.per_ldr_band(Stats.BAND_LOW_MAX)).is_equal(-1)
	assert_int(Stats.per_ldr_band(Stats.BAND_LOW_MAX + 1)).is_equal(0)
	assert_int(Stats.per_ldr_band(Stats.BAND_MID_MAX)).is_equal(0)
	assert_int(Stats.per_ldr_band(Stats.BAND_MID_MAX + 1)).is_equal(1)
	assert_int(Stats.per_ldr_band(Stats.BAND_MID_MAX + 5)).is_equal(1)

func test_all_defaults_land_on_the_zero_rung() -> void:
	# The no-behavior-shift guarantee: a default statline takes 0 from every band,
	# so pre-CON units, scenarios, and fixtures keep their exact numbers.
	assert_int(Stats.dex_mov_band(Stats.STAT_DEFAULTS[Stats.Stat.DEX])).is_equal(0)
	assert_int(Stats.con_mhp_band(Stats.STAT_DEFAULTS[Stats.Stat.CON])).is_equal(0)
	assert_int(Stats.per_ldr_band(Stats.STAT_DEFAULTS[Stats.Stat.PER])).is_equal(0)

func test_armor_def_mechanism() -> void:
	# DEF = flat + (power x CON x factor), stats.md. Value-free on CON_DEF_FACTOR (playtest-tunable):
	# these pin the formula's SHAPE, so retuning the factor cannot turn them red.
	assert_int(Stats.armor_def(10, 0)).is_equal(0)   # CON 0 can't brace armor
	assert_int(Stats.armor_def(0, 9)).is_equal(0)    # no gear, no scaled DEF — regardless of CON
	# The scaled term is monotone in CON: a tougher body never wears the same piece worse.
	assert_int(Stats.armor_def(10, 8)).is_greater(Stats.armor_def(10, 2))
	# More armor never pays out less on the same body.
	assert_int(Stats.armor_def(10, 5)).is_greater_equal(Stats.armor_def(7, 5))

func test_armor_def_flat_term_is_unscaled() -> void:
	# The 2026-07-24 rule that created flat_def: a CON-gated piece pays its flat term out
	# WITHOUT double-dipping CON. flat + scaled, never (flat + power) x scaled.
	assert_int(Stats.armor_def(10, 8, 3)).is_equal(Stats.armor_def(10, 8) + 3)
	# ...and it pays out even where the scaled term is zero.
	assert_int(Stats.armor_def(0, 8, 3)).is_equal(3)
	assert_int(Stats.armor_def(10, 0, 3)).is_equal(3)
