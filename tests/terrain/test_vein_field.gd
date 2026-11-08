# VeinField (#696): the materia vein store, and the board snapshot that carries it through a save, a
# load, an undo and an authored save. Pure data -- no scene. GasField's suite is the shape.
extends GdUnitTestSuite

const A := Vector2i(2, 3)
const B := Vector2i(-1, 4)


func test_a_cell_holds_one_vein_and_painting_overwrites() -> void:
	var field := VeinField.new()
	field.set_kind(A, Vein.Kind.FIRE)
	assert_int(field.kind_at(A)).is_equal(Vein.Kind.FIRE)
	field.set_kind(A, Vein.Kind.ALKAHEST)
	assert_int(field.kind_at(A)).is_equal(Vein.Kind.ALKAHEST)
	assert_int(field.kind_at(B)).is_equal(Vein.Kind.NONE)


func test_none_erases() -> void:
	var field := VeinField.new()
	field.set_kind(A, Vein.Kind.WATER)
	field.set_kind(A, Vein.Kind.NONE)
	assert_bool(field.is_empty()).is_true()


func test_the_version_moves_only_on_a_real_change() -> void:
	# A drag repaints what is already there on every motion event; that must cost a renderer nothing.
	var field := VeinField.new()
	field.set_kind(A, Vein.Kind.EARTH)
	var after_first := field.dirty.version
	field.set_kind(A, Vein.Kind.EARTH)
	field.set_kind(B, Vein.Kind.NONE)
	assert_int(field.dirty.version).is_equal(after_first)
	field.set_kind(A, Vein.Kind.AIR)
	assert_int(field.dirty.version).is_greater(after_first)


# The tile states' rule (#245): a vein needs ground under it, and taking one away is never refused.
func test_a_groundless_cell_refuses_a_vein_but_always_gives_one_up() -> void:
	var field := VeinField.new()
	field.set_kind(A, Vein.Kind.AETHER)
	field.ground_source = func(cell: Vector2i) -> bool: return cell != A and cell != B
	field.set_kind(B, Vein.Kind.FIRE)
	assert_int(field.kind_at(B)).is_equal(Vein.Kind.NONE)
	field.set_kind(A, Vein.Kind.NONE)
	assert_bool(field.is_empty()).is_true()


func test_prune_groundless_takes_only_the_cells_without_ground() -> void:
	var field := VeinField.new()
	field.set_kind(A, Vein.Kind.LIGHTNING)
	field.set_kind(B, Vein.Kind.LIGHTNING)
	var before := field.dirty.version
	assert_bool(field.prune_groundless(func(cell: Vector2i) -> bool: return cell == A)).is_true()
	assert_int(field.kind_at(A)).is_equal(Vein.Kind.LIGHTNING)
	assert_int(field.kind_at(B)).is_equal(Vein.Kind.NONE)
	assert_int(field.dirty.version).is_greater(before)
	assert_bool(field.prune_groundless(func(_cell: Vector2i) -> bool: return true)).is_false()


func test_a_dict_round_trip_restores_every_cell() -> void:
	var field := VeinField.new()
	field.set_kind(A, Vein.Kind.FIRE)
	field.set_kind(B, Vein.Kind.ALKAHEST)
	var copy := VeinField.new()
	copy.load_dict(field.to_dict())
	assert_int(copy.kind_at(A)).is_equal(Vein.Kind.FIRE)
	assert_int(copy.kind_at(B)).is_equal(Vein.Kind.ALKAHEST)
	assert_int(copy.cells().size()).is_equal(2)


# to_dict hands out a copy: a snapshot taken before an edit must not move with the store.
func test_to_dict_is_a_copy() -> void:
	var field := VeinField.new()
	field.set_kind(A, Vein.Kind.FIRE)
	var taken := field.to_dict()
	field.set_kind(A, Vein.Kind.WATER)
	assert_int(taken[A]).is_equal(Vein.Kind.FIRE)


# A load replaces; it never merges into what the last board left.
func test_a_load_replaces_the_store() -> void:
	var field := VeinField.new()
	field.set_kind(B, Vein.Kind.EARTH)
	field.load_dict({A: Vein.Kind.AIR, Vector2i(9, 9): Vein.Kind.NONE})
	assert_array(field.cells()).contains_exactly([A])


func test_every_kind_names_itself() -> void:
	for kind: int in Vein.Kind.values():
		assert_str(Vein.display_name(kind)).is_not_empty()


# --- the board snapshot ------------------------------------------------------------------------

func test_the_scenario_bridge_carries_veins_both_ways() -> void:
	# BoardSnapshot.from_scenario / write_into are the ONE place "which fields are the board" is
	# written down, so a save, a load and an undo all ride this.
	var snapshot := BoardSnapshot.new()
	snapshot.veins = {A: Vein.Kind.FIRE}
	var scenario := ScenarioData.new()
	snapshot.write_into(scenario)
	var back := BoardSnapshot.from_scenario(scenario)
	assert_bool(back.equals(snapshot)).is_true()
	snapshot.veins = {}
	assert_bool(back.equals(snapshot)).override_failure_message(
		"two boards differing only in veins compared equal").is_false()


# Play never writes a vein, so an authoring edit's result is its veins whole: what was painted, never
# what the authored copy held before (#1507's reflection copy).
func test_an_authored_board_keeps_the_veins_as_painted() -> void:
	var authored := BoardSnapshot.new()
	var before := BoardSnapshot.new()
	var after := BoardSnapshot.new()
	after.veins = {A: Vein.Kind.AETHER}
	var result := authored.edited(before, after, Callable())
	assert_dict(result.veins).is_equal({A: Vein.Kind.AETHER})
	assert_bool(BoardSnapshot.PLAY_WRITTEN.has(&"veins")).override_failure_message(
		"play does not write veins, so they must not take the per-cell play merge").is_false()
