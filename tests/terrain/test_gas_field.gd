# GasField + Gas (#508): the atmosphere store and the packing it leans on. Pure data -- no scene.
extends GdUnitTestSuite

const A := Vector2i(2, 3)
const B := Vector2i(-1, 4)


func test_the_packing_has_room_for_every_kind_and_every_amount() -> void:
	# Four bits a kind: the cap must fit a nibble, and the renderer's kind mask is one byte.
	assert_int(Gas.MAX_AMOUNT).override_failure_message(
		"MAX_AMOUNT no longer fits Gas.BITS -- the packing (and every save) needs migrating").is_less(1 << Gas.BITS)
	assert_int(Gas.Kind.size()).override_failure_message(
		"more than eight gases: Gas.kind_mask no longer fits the renderer's byte").is_less_equal(8)


func test_every_kind_round_trips_at_both_ends_of_its_range() -> void:
	for kind: Gas.Kind in Gas.Kind.values():
		for amount in [0, 1, Gas.MAX_AMOUNT]:
			var packed := Gas.with_amount(0, kind, amount)
			assert_int(Gas.amount_in(packed, kind)).is_equal(amount)


func test_kinds_in_one_cell_are_independent() -> void:
	var field := GasField.new()
	field.set_amount(A, Gas.Kind.STEAM, 5)
	field.set_amount(A, Gas.Kind.SULFUR, Gas.MAX_AMOUNT)
	field.set_amount(A, Gas.Kind.STEAM, 9)
	assert_int(field.amount_at(A, Gas.Kind.STEAM)).is_equal(9)
	assert_int(field.amount_at(A, Gas.Kind.SULFUR)).is_equal(Gas.MAX_AMOUNT)
	assert_array(Gas.kinds_in(field.packed_at(A))).contains_exactly([Gas.Kind.STEAM, Gas.Kind.SULFUR])


func test_set_amount_clamps_and_zero_erases() -> void:
	var field := GasField.new()
	field.set_amount(A, Gas.Kind.SMOKE, 99)
	assert_int(field.amount_at(A, Gas.Kind.SMOKE)).is_equal(Gas.MAX_AMOUNT)
	field.set_amount(A, Gas.Kind.SMOKE, 0)
	assert_bool(field.is_empty()).is_true()


func test_the_version_moves_only_on_a_real_change() -> void:
	# A drag repaints what is already there on every motion event; that must cost a renderer nothing.
	var field := GasField.new()
	field.set_amount(A, Gas.Kind.POISON, 6)
	var after_first := field.dirty.version
	field.set_amount(A, Gas.Kind.POISON, 6)
	assert_int(field.dirty.version).is_equal(after_first)
	field.set_amount(A, Gas.Kind.POISON, 7)
	assert_int(field.dirty.version).is_greater(after_first)


func test_a_dict_round_trip_restores_every_cell() -> void:
	var field := GasField.new()
	field.set_amount(A, Gas.Kind.FROST, 3)
	field.set_amount(B, Gas.Kind.THUNDER, 11)
	var copy := GasField.new()
	copy.load_dict(field.to_dict())
	assert_int(copy.amount_at(A, Gas.Kind.FROST)).is_equal(3)
	assert_int(copy.amount_at(B, Gas.Kind.THUNDER)).is_equal(11)
	assert_int(copy.cells().size()).is_equal(2)


func test_prune_groundless_takes_only_the_cells_without_ground() -> void:
	var field := GasField.new()
	field.set_amount(A, Gas.Kind.STEAM, 4)
	field.set_amount(B, Gas.Kind.STEAM, 4)
	var pruned := field.prune_groundless(func(cell: Vector2i) -> bool: return cell == A)
	assert_bool(pruned).is_true()
	assert_int(field.amount_at(A, Gas.Kind.STEAM)).is_equal(4)
	assert_int(field.amount_at(B, Gas.Kind.STEAM)).is_equal(0)


func test_a_groundless_cell_refuses_gas_but_always_gives_it_up() -> void:
	var field := GasField.new()
	var ground := {A: true}
	field.ground_source = func(cell: Vector2i) -> bool: return ground.has(cell)
	field.set_amount(B, Gas.Kind.STEAM, 4)
	field.add_amount(B, Gas.Kind.STEAM, 4)
	assert_int(field.amount_at(B, Gas.Kind.STEAM)).override_failure_message(
		"gas landed on a cell with no ground").is_equal(0)
	field.set_amount(A, Gas.Kind.STEAM, 4)
	ground.erase(A)   # the tile goes; taking its gas away must not be refused with it
	field.set_amount(A, Gas.Kind.STEAM, 0)
	assert_bool(field.is_empty()).is_true()


func test_a_deposit_adds_to_what_is_there_and_clamps() -> void:
	var field := GasField.new()
	field.add_amount(A, Gas.Kind.STEAM, 5)
	field.add_amount(A, Gas.Kind.STEAM, 4)
	assert_int(field.amount_at(A, Gas.Kind.STEAM)).is_equal(9)
	field.add_amount(A, Gas.Kind.STEAM, Gas.MAX_AMOUNT)
	assert_int(field.amount_at(A, Gas.Kind.STEAM)).is_equal(Gas.MAX_AMOUNT)


func test_apply_plays_a_cell_effects_gas_into_the_store() -> void:
	var field := GasField.new()
	field.set_amount(A, Gas.Kind.STEAM, 2)
	var effect := ResolvedCellEffect.new()
	effect.cell = A
	effect.add_gas(Gas.Kind.STEAM, 3)
	effect.add_gas(Gas.Kind.STEAM, 1)   # two reactions on one cell sum
	field.apply(effect)
	assert_int(field.amount_at(A, Gas.Kind.STEAM)).is_equal(6)


func test_the_scenario_bridge_carries_gas_both_ways() -> void:
	# BoardSnapshot.from_scenario / write_into are the ONE place "which fields are the board" is
	# written down, so a save, a load and an undo all ride this.
	var snapshot := BoardSnapshot.new()
	snapshot.gas = {A: Gas.with_amount(0, Gas.Kind.STEAM, 7)}
	var scenario := ScenarioData.new()
	snapshot.write_into(scenario)
	var back := BoardSnapshot.from_scenario(scenario)
	assert_bool(back.equals(snapshot)).is_true()
	snapshot.gas = {}
	assert_bool(back.equals(snapshot)).override_failure_message(
		"two boards differing only in gas compared equal").is_false()
