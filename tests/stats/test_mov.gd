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
	assert_int(_mov(_make_instance({Stats.Stat.DEX: 3}))).is_equal(3)   # low rung
	assert_int(_mov(_make_instance({Stats.Stat.DEX: 6}))).is_equal(5)   # one point of investment
	assert_int(_mov(_make_instance({Stats.Stat.DEX: 9}))).is_equal(6)   # the earned top rung

func test_con_does_not_touch_mov() -> void:
	# Doctrine correction 2026-07-27: weight is gear-only and feeds nothing, so a high-CON
	# unit is no slower than anyone else. This used to assert the opposite.
	assert_int(_mov(_make_instance({Stats.Stat.CON: 8}))).is_equal(UnitInstance.JOBLESS_MOV_BASE)
	assert_int(_mov(_make_instance({Stats.Stat.CON: 20}))).is_equal(UnitInstance.JOBLESS_MOV_BASE)

func test_one_empty_leg_halves_final_mov() -> void:
	# The full thread, default unit: leg empties -> eff DEX ceil(5/2)=3 -> band -1 -> 3,
	# then the throttle halves it rounded up -> 2. Both effects stack deliberately.
	var inst := _make_instance({})
	inst.limbs[UnitInstance.LimbSlot.LEG_L].state = UnitInstance.LimbState.EMPTY
	assert_int(_mov(inst)).is_equal(2)

func test_one_empty_leg_on_a_sprinter() -> void:
	# DEX 12: eff DEX ceil(12/2)=6 -> band +1 -> 5 -> halved up -> 3. Fast, but limping.
	var inst := _make_instance({Stats.Stat.DEX: 12})
	inst.limbs[UnitInstance.LimbSlot.LEG_R].state = UnitInstance.LimbState.EMPTY
	assert_int(_mov(inst)).is_equal(3)

func test_both_legs_empty_pins_mov_to_one() -> void:
	# Categorical (dev ruling): overrides base, band, weight — even a DEX-12 sprinter crawls.
	var inst := _make_instance({Stats.Stat.DEX: 12})
	inst.limbs[UnitInstance.LimbSlot.LEG_L].state = UnitInstance.LimbState.EMPTY
	inst.limbs[UnitInstance.LimbSlot.LEG_R].state = UnitInstance.LimbState.EMPTY
	assert_int(_mov(inst)).is_equal(1)

func test_prosthetic_leg_lifts_the_throttle() -> void:
	# A fitted prosthetic is a functional leg: no halving; its stat feeds the DEX mean.
	var inst := _make_instance({Stats.Stat.DEX: 5})
	inst.limbs[UnitInstance.LimbSlot.LEG_L].state = UnitInstance.LimbState.PROSTHETIC
	inst.limbs[UnitInstance.LimbSlot.LEG_L].prosthetic_stat = 5
	assert_int(_mov(inst)).is_equal(UnitInstance.JOBLESS_MOV_BASE)

func test_mov_never_drops_below_one() -> void:
	# Low DEX + heavy body + one empty leg: 4-1-1=2 -> eff DEX drags band... floor holds at 1.
	var inst := _make_instance({Stats.Stat.DEX: 0, Stats.Stat.CON: 8})
	inst.limbs[UnitInstance.LimbSlot.LEG_L].state = UnitInstance.LimbState.EMPTY
	assert_int(_mov(inst)).is_greater_equal(1)
