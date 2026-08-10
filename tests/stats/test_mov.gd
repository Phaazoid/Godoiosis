# MOV as a derived readout (#56, jobs.md — closes audit A4): job base + DEX band
# (retuned 2026-07-15), then the leg throttle LAST (dev ruling 2026-07-14: one empty leg
# halves rounded up; two empty pin MOV to 1 flat). Weight does NOT feed MOV (2026-07-27).
# Pure Resource tests.
extends GdUnitTestSuite

func _make_instance(partial_stats: Dictionary[Stats.Stat, int]) -> UnitInstance:
	var data := UnitData.new()
	data.base_stats = partial_stats
	var inst := UnitInstance.new()
	inst.data = data
	inst.initialize()
	return inst

# UnitInstance.get_mov takes the FINISHED effective DEX as of 2026-07-27, so that gear (which
# only Unit can see) enters the stat chain in exactly one place. These are bare instances with
# no Unit and therefore no gear, so the instance's own effective DEX is the whole answer.
func _mov(inst: UnitInstance) -> int:
	return inst.get_mov(inst.get_effective_stat(Stats.Stat.DEX))

func test_default_unit_moves_at_jobless_base() -> void:
	# DEX 5 -> band 0.
	assert_int(_mov(_make_instance({}))).is_equal(UnitInstance.JOBLESS_MOV_BASE)

func test_dex_band_rungs_reach_mov() -> void:
	# Inputs through the named thresholds, expected off the base (2026-08-10 sweep): both are
	# playtest-tunable and retuning either must not turn this red. The rung deltas stay literal --
	# they are the band's shape, pinned by test_stat_bands.
	assert_int(_mov(_make_instance({Stats.Stat.DEX: Stats.BAND_LOW_MAX}))) \
		.is_equal(UnitInstance.JOBLESS_MOV_BASE - 1)   # low rung
	assert_int(_mov(_make_instance({Stats.Stat.DEX: Stats.DEX_MOV_MID_MAX + 1}))) \
		.is_equal(UnitInstance.JOBLESS_MOV_BASE + 1)   # one point of investment
	assert_int(_mov(_make_instance({Stats.Stat.DEX: Stats.DEX_MOV_HIGH_MAX + 1}))) \
		.is_equal(UnitInstance.JOBLESS_MOV_BASE + 2)   # the earned top rung

func test_con_does_not_touch_mov() -> void:
	# Doctrine correction 2026-07-27: weight is gear-only and feeds nothing, so a high-CON
	# unit is no slower than anyone else. This used to assert the opposite.
	assert_int(_mov(_make_instance({Stats.Stat.CON: 8}))).is_equal(UnitInstance.JOBLESS_MOV_BASE)
	assert_int(_mov(_make_instance({Stats.Stat.CON: 20}))).is_equal(UnitInstance.JOBLESS_MOV_BASE)

# The throttle threads assert the RELATIONSHIP, not a finished number (2026-08-10 sweep): the
# dragged DEX is read back off the real chain and the pre-throttle MOV rebuilt from it, so the only
# thing each case can fail on is its own stage -- the halve-up -- and no knob retune reaches it.
func _unthrottled_mov(inst: UnitInstance) -> int:
	return UnitInstance.JOBLESS_MOV_BASE + Stats.dex_mov_band(inst.get_effective_stat(Stats.Stat.DEX))

func test_one_empty_leg_halves_final_mov() -> void:
	# The full thread, default unit: leg empties -> the DEX mean drags -> the band drops,
	# then the throttle halves the result rounded up. Both effects stack deliberately.
	var inst := _make_instance({})
	inst.limbs[UnitInstance.LimbSlot.LEG_L].state = UnitInstance.LimbState.EMPTY
	assert_int(_mov(inst)).is_equal(ceili(_unthrottled_mov(inst) / 2.0))
	# The premise -- the drag really reached the band, or the halve-up above proved nothing new.
	assert_int(_unthrottled_mov(inst)).is_less(UnitInstance.JOBLESS_MOV_BASE)

func test_one_empty_leg_on_a_sprinter() -> void:
	# A high-DEX unit limps too, from its own higher baseline. Fast, but limping.
	var inst := _make_instance({Stats.Stat.DEX: 12})
	inst.limbs[UnitInstance.LimbSlot.LEG_R].state = UnitInstance.LimbState.EMPTY
	assert_int(_mov(inst)).is_equal(ceili(_unthrottled_mov(inst) / 2.0))
	# Premise: the sprinter keeps a band edge over the default even dragged.
	assert_int(_unthrottled_mov(inst)).is_greater(UnitInstance.JOBLESS_MOV_BASE - 1)

func test_both_legs_empty_pins_mov_to_one() -> void:
	# Categorical (dev ruling): overrides base, band, weight — even a DEX-12 sprinter crawls.
	var inst := _make_instance({Stats.Stat.DEX: 12})
	inst.limbs[UnitInstance.LimbSlot.LEG_L].state = UnitInstance.LimbState.EMPTY
	inst.limbs[UnitInstance.LimbSlot.LEG_R].state = UnitInstance.LimbState.EMPTY
	assert_int(_mov(inst)).is_equal(1)

func test_prosthetic_leg_lifts_the_throttle() -> void:
	# A fitted prosthetic is a functional leg: no halving; its stat feeds the DEX mean. A
	# default-stat prosthetic on a default unit rides the defaults-land-on-0 guarantee
	# (test_stat_bands), so the expectation is the bare base whatever the numbers are.
	var inst := _make_instance({Stats.Stat.DEX: Stats.STAT_DEFAULTS[Stats.Stat.DEX]})
	inst.limbs[UnitInstance.LimbSlot.LEG_L].state = UnitInstance.LimbState.PROSTHETIC
	inst.limbs[UnitInstance.LimbSlot.LEG_L].prosthetic_stat = Stats.STAT_DEFAULTS[Stats.Stat.DEX]
	assert_int(_mov(inst)).is_equal(UnitInstance.JOBLESS_MOV_BASE)

func test_mov_never_drops_below_one() -> void:
	# Low DEX + heavy body + one empty leg: 4-1-1=2 -> eff DEX drags band... floor holds at 1.
	var inst := _make_instance({Stats.Stat.DEX: 0, Stats.Stat.CON: 8})
	inst.limbs[UnitInstance.LimbSlot.LEG_L].state = UnitInstance.LimbState.EMPTY
	assert_int(_mov(inst)).is_greater_equal(1)
