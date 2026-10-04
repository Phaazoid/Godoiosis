# GasField + Gas (#508): the atmosphere store and the packing it leans on. Pure data -- no scene.
extends GdUnitTestSuite

const A := Vector2i(2, 3)
const B := Vector2i(-1, 4)
const THIN := Gas.Level.THIN
const MEDIUM := Gas.Level.MEDIUM
const THICK := Gas.Level.THICK


func test_the_packing_has_room_for_every_kind_its_level_and_its_hold() -> void:
	# Four bits a kind: two for the level, two for the hold counter, and the renderer's kind mask is one byte.
	assert_int(Gas.MAX_LEVEL).override_failure_message(
		"MAX_LEVEL no longer fits the level bits -- the packing (and every save) needs migrating").is_less(1 << Gas.AGE_SHIFT)
	assert_int(Gas.MAX_AGE).override_failure_message(
		"MAX_AGE no longer fits the bits above the level").is_less(1 << (Gas.BITS - Gas.AGE_SHIFT))
	assert_int(Gas.Kind.size()).override_failure_message(
		"more than eight gases: Gas.kind_mask no longer fits the renderer's byte").is_less_equal(8)


func test_every_kind_round_trips_its_level_and_hold_at_both_ends() -> void:
	for kind: Gas.Kind in Gas.Kind.values():
		for level in [0, THIN, Gas.MAX_LEVEL]:
			for age in [0, Gas.MAX_AGE]:
				var packed := Gas.with_level(0, kind, level, age)
				assert_int(Gas.level_in(packed, kind)).is_equal(level)
				assert_int(Gas.age_in(packed, kind)).is_equal(age if level > 0 else 0)


func test_no_level_means_no_hold_and_no_bits() -> void:
	assert_int(Gas.with_level(0, Gas.Kind.STEAM, 0, Gas.MAX_AGE)).is_equal(0)


func test_kinds_in_one_cell_are_independent() -> void:
	var field := GasField.new()
	field.set_level(A, Gas.Kind.STEAM, THIN)
	field.set_level(A, Gas.Kind.SULFUR, THICK)
	field.set_level(A, Gas.Kind.STEAM, MEDIUM)
	assert_int(field.level_at(A, Gas.Kind.STEAM)).is_equal(MEDIUM)
	assert_int(field.level_at(A, Gas.Kind.SULFUR)).is_equal(THICK)
	assert_array(Gas.kinds_in(field.packed_at(A))).contains_exactly([Gas.Kind.STEAM, Gas.Kind.SULFUR])


func test_set_level_clamps_and_none_erases() -> void:
	var field := GasField.new()
	field.set_level(A, Gas.Kind.SMOKE, 99)
	assert_int(field.level_at(A, Gas.Kind.SMOKE)).is_equal(Gas.MAX_LEVEL)
	field.set_level(A, Gas.Kind.SMOKE, Gas.Level.NONE)
	assert_bool(field.is_empty()).is_true()


func test_the_version_moves_only_on_a_real_change() -> void:
	# A drag repaints what is already there on every motion event; that must cost a renderer nothing.
	var field := GasField.new()
	field.set_level(A, Gas.Kind.POISON, MEDIUM)
	var after_first := field.dirty.version
	field.set_level(A, Gas.Kind.POISON, MEDIUM)
	assert_int(field.dirty.version).is_equal(after_first)
	field.set_level(A, Gas.Kind.POISON, THICK)
	assert_int(field.dirty.version).is_greater(after_first)


func test_a_dict_round_trip_restores_every_cell() -> void:
	var field := GasField.new()
	field.set_level(A, Gas.Kind.FROST, THIN)
	field.set_level(B, Gas.Kind.THUNDER, THICK)
	var copy := GasField.new()
	copy.load_dict(field.to_dict())
	assert_int(copy.level_at(A, Gas.Kind.FROST)).is_equal(THIN)
	assert_int(copy.level_at(B, Gas.Kind.THUNDER)).is_equal(THICK)
	assert_int(copy.cells().size()).is_equal(2)


func test_prune_groundless_takes_only_the_cells_without_ground() -> void:
	var field := GasField.new()
	field.set_level(A, Gas.Kind.STEAM, MEDIUM)
	field.set_level(B, Gas.Kind.STEAM, MEDIUM)
	var pruned := field.prune_groundless(func(cell: Vector2i) -> bool: return cell == A)
	assert_bool(pruned).is_true()
	assert_int(field.level_at(A, Gas.Kind.STEAM)).is_equal(MEDIUM)
	assert_int(field.level_at(B, Gas.Kind.STEAM)).is_equal(0)


func test_a_groundless_cell_refuses_gas_but_always_gives_it_up() -> void:
	var field := GasField.new()
	var ground := {A: true}
	field.ground_source = func(cell: Vector2i) -> bool: return ground.has(cell)
	field.set_level(B, Gas.Kind.STEAM, MEDIUM)
	field.add_level(B, Gas.Kind.STEAM, MEDIUM)
	assert_int(field.level_at(B, Gas.Kind.STEAM)).override_failure_message(
		"gas landed on a cell with no ground").is_equal(0)
	field.set_level(A, Gas.Kind.STEAM, MEDIUM)
	ground.erase(A)   # the tile goes; taking its gas away must not be refused with it
	field.set_level(A, Gas.Kind.STEAM, Gas.Level.NONE)
	assert_bool(field.is_empty()).is_true()


func test_a_deposit_adds_levels_and_caps_at_thick() -> void:
	var field := GasField.new()
	field.add_level(A, Gas.Kind.STEAM, THIN)
	field.add_level(A, Gas.Kind.STEAM, THIN)
	assert_int(field.level_at(A, Gas.Kind.STEAM)).is_equal(MEDIUM)
	field.add_level(A, Gas.Kind.STEAM, THICK)
	assert_int(field.level_at(A, Gas.Kind.STEAM)).is_equal(THICK)


func test_a_deposit_starts_the_hold_over() -> void:
	var field := GasField.new()
	field.load_dict({A: Gas.with_level(0, Gas.Kind.STEAM, THIN, Gas.MAX_AGE)})
	field.add_level(A, Gas.Kind.STEAM, THIN)
	assert_int(Gas.age_in(field.packed_at(A), Gas.Kind.STEAM)).is_equal(0)


func test_apply_plays_a_cell_effects_gas_into_the_store() -> void:
	var field := GasField.new()
	field.set_level(A, Gas.Kind.STEAM, THIN)
	var effect := ResolvedCellEffect.new()
	effect.cell = A
	effect.add_gas(Gas.Kind.STEAM, THIN)
	effect.add_gas(Gas.Kind.STEAM, THIN)   # two reactions on one cell sum
	field.apply(effect)
	assert_int(field.level_at(A, Gas.Kind.STEAM)).is_equal(THICK)


# The forecast's read (#508 PR 3): what apply WOULD leave, written nowhere -- the same add-and-cap,
# this cell's deposits only, and the live store untouched.
func test_the_projected_cell_folds_this_passes_deposits_and_writes_nothing() -> void:
	var field := GasField.new()
	field.set_level(A, Gas.Kind.STEAM, MEDIUM)
	var here := ResolvedCellEffect.new()
	here.cell = A
	here.add_gas(Gas.Kind.STEAM, MEDIUM)
	var elsewhere := ResolvedCellEffect.new()
	elsewhere.cell = B
	elsewhere.add_gas(Gas.Kind.STEAM, THICK)
	var effects: Array[ResolvedCellEffect] = [here, elsewhere]
	var version := field.dirty.version

	var projected := field.projected_packed_at(A, effects)

	assert_int(Gas.level_in(projected, Gas.Kind.STEAM)).is_equal(Gas.MAX_LEVEL)   # capped, as apply caps
	assert_int(Gas.level_in(field.projected_packed_at(B, effects), Gas.Kind.STEAM)).is_equal(THICK)
	assert_int(field.level_at(A, Gas.Kind.STEAM)).override_failure_message(
			"the projection wrote into the live store").is_equal(MEDIUM)
	assert_int(field.dirty.version).is_equal(version)
	var applied := GasField.new()
	applied.set_level(A, Gas.Kind.STEAM, MEDIUM)
	applied.apply(here)
	assert_int(Gas.level_in(projected, Gas.Kind.STEAM)).override_failure_message(
			"the projection and apply disagree about the same deposit").is_equal(applied.level_at(A, Gas.Kind.STEAM))


func test_a_tick_that_moves_nothing_marks_nothing() -> void:
	# SMOKE has no rules file, so the round leaves it exactly where it lies (#508 ruling 10).
	var field := GasField.new()
	field.set_level(A, Gas.Kind.SMOKE, THICK)
	var before := field.dirty.version
	var no_units: Array[Unit] = []
	field.tick(BoardContext.new(null, no_units, null))
	assert_int(field.level_at(A, Gas.Kind.SMOKE)).is_equal(THICK)
	assert_int(field.dirty.version).is_equal(before)


func test_the_scenario_bridge_carries_gas_both_ways() -> void:
	# BoardSnapshot.from_scenario / write_into are the ONE place "which fields are the board" is
	# written down, so a save, a load and an undo all ride this.
	var snapshot := BoardSnapshot.new()
	snapshot.gas = {A: Gas.with_level(0, Gas.Kind.STEAM, MEDIUM, 1)}
	var scenario := ScenarioData.new()
	snapshot.write_into(scenario)
	var back := BoardSnapshot.from_scenario(scenario)
	assert_bool(back.equals(snapshot)).is_true()
	snapshot.gas = {}
	assert_bool(back.equals(snapshot)).override_failure_message(
		"two boards differing only in gas compared equal").is_false()
