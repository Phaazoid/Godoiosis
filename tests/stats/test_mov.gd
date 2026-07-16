# MOV as a derived readout (#56, jobs.md — closes audit A4): job base + DEX band
# (retuned 2026-07-15) - weight step, then the leg throttle LAST (dev ruling 2026-07-14:
# one empty leg halves rounded up; two empty pin MOV to 1 flat). Pure Resource tests.
extends GdUnitTestSuite

func _make_instance(partial_stats: Dictionary[Stats.Stat, int]) -> UnitInstance:
	var data := UnitData.new()
	data.base_stats = partial_stats
	var inst := UnitInstance.new()
	inst.data = data
	inst.initialize()
	return inst

func test_default_unit_moves_at_jobless_base() -> void:
	# DEX 5 -> band 0; CON 5 -> weight 5, under the threshold.
	assert_int(_make_instance({}).get_mov()).is_equal(UnitInstance.JOBLESS_MOV_BASE)

func test_dex_band_rungs_reach_mov() -> void:
	assert_int(_make_instance({Stats.Stat.DEX: 3}).get_mov()).is_equal(3)   # low rung
	assert_int(_make_instance({Stats.Stat.DEX: 6}).get_mov()).is_equal(5)   # one point of investment
	assert_int(_make_instance({Stats.Stat.DEX: 9}).get_mov()).is_equal(6)   # the earned top rung

func test_heavy_body_pays_the_weight_step() -> void:
	# CON 8 -> weight 8 >= threshold -> one coarse step off (never per-point).
	assert_int(_make_instance({Stats.Stat.CON: 8}).get_mov()).is_equal(UnitInstance.JOBLESS_MOV_BASE - 1)

func test_one_empty_leg_halves_final_mov() -> void:
	# The full thread, default unit: leg empties -> eff DEX ceil(5/2)=3 -> band -1 -> 3,
	# then the throttle halves it rounded up -> 2. Both effects stack deliberately.
	var inst := _make_instance({})
	inst.limbs[UnitInstance.LimbSlot.LEG_L].state = UnitInstance.LimbState.EMPTY
	assert_int(inst.get_mov()).is_equal(2)

func test_one_empty_leg_on_a_sprinter() -> void:
	# DEX 12: eff DEX ceil(12/2)=6 -> band +1 -> 5 -> halved up -> 3. Fast, but limping.
	var inst := _make_instance({Stats.Stat.DEX: 12})
	inst.limbs[UnitInstance.LimbSlot.LEG_R].state = UnitInstance.LimbState.EMPTY
	assert_int(inst.get_mov()).is_equal(3)

func test_both_legs_empty_pins_mov_to_one() -> void:
	# Categorical (dev ruling): overrides base, band, weight — even a DEX-12 sprinter crawls.
	var inst := _make_instance({Stats.Stat.DEX: 12})
	inst.limbs[UnitInstance.LimbSlot.LEG_L].state = UnitInstance.LimbState.EMPTY
	inst.limbs[UnitInstance.LimbSlot.LEG_R].state = UnitInstance.LimbState.EMPTY
	assert_int(inst.get_mov()).is_equal(1)

func test_prosthetic_leg_lifts_the_throttle() -> void:
	# A fitted prosthetic is a functional leg: no halving; its stat feeds the DEX mean.
	var inst := _make_instance({Stats.Stat.DEX: 5})
	inst.limbs[UnitInstance.LimbSlot.LEG_L].state = UnitInstance.LimbState.PROSTHETIC
	inst.limbs[UnitInstance.LimbSlot.LEG_L].prosthetic_stat = 5
	assert_int(inst.get_mov()).is_equal(UnitInstance.JOBLESS_MOV_BASE)

func test_mov_never_drops_below_one() -> void:
	# Low DEX + heavy body + one empty leg: 4-1-1=2 -> eff DEX drags band... floor holds at 1.
	var inst := _make_instance({Stats.Stat.DEX: 0, Stats.Stat.CON: 8})
	inst.limbs[UnitInstance.LimbSlot.LEG_L].state = UnitInstance.LimbState.EMPTY
	assert_int(inst.get_mov()).is_greater_equal(1)
