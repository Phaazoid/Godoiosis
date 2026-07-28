# ZoneManager: the name -> {kind, cells} store painted via the Tile Brush Zone mode. Pure logic —
# no board or scene needed.
#
# Zones grew a KIND in #96 (2026-07-28) so one mechanism serves every region-shaped feature: a
# capture point is a zone of size one, not a parallel Array[Vector2i] on ScenarioData. The kind
# cases below are what stop that generalization from regressing into "cells, plus some other
# stuff" — in particular that a kind survives the round-trip, since ScenarioData.zones is the
# only place an authored objective's geometry is persisted.
extends GdUnitTestSuite

const PATROL := ZoneManager.Kind.PATROL
const CAPTURE := ZoneManager.Kind.CAPTURE
const EXTRACTION := ZoneManager.Kind.EXTRACTION


func _zones() -> ZoneManager:
	var zones: ZoneManager = auto_free(ZoneManager.new())
	return zones


func test_paint_and_query() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("gate", PATROL, Vector2i(1, 1))
	zones.paint_cell("gate", PATROL, Vector2i(2, 1))

	assert_array(zones.zone_names()).contains_exactly(["gate"])
	assert_array(zones.cells_in("gate")).contains_exactly_in_any_order([Vector2i(1, 1), Vector2i(2, 1)])
	assert_bool(zones.contains("gate", Vector2i(1, 1))).is_true()
	assert_bool(zones.contains("gate", Vector2i(5, 5))).is_false()
	assert_array(zones.cells_in("nope")).is_empty()


func test_cell_belongs_to_at_most_one_zone() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("a", PATROL, Vector2i(1, 1))
	zones.paint_cell("b", PATROL, Vector2i(1, 1))   # repaint moves the cell, silently

	assert_bool(zones.contains("b", Vector2i(1, 1))).is_true()
	assert_bool(zones.contains("a", Vector2i(1, 1))).is_false()
	# "a" lost its only cell -> pruned entirely
	assert_array(zones.zone_names()).contains_exactly(["b"])


func test_erase_prunes_empty_zone() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("gate", PATROL, Vector2i(1, 1))
	zones.erase_cell(Vector2i(1, 1))

	assert_array(zones.zone_names()).is_empty()
	assert_bool(zones.contains("gate", Vector2i(1, 1))).is_false()


func test_erase_untracked_cell_is_a_noop() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("gate", PATROL, Vector2i(1, 1))
	zones.erase_cell(Vector2i(9, 9))

	assert_array(zones.cells_in("gate")).contains_exactly([Vector2i(1, 1)])


# ---- kinds ----

func test_zone_names_of_filters_by_kind() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("gate", PATROL, Vector2i(1, 1))
	zones.paint_cell("throne", CAPTURE, Vector2i(4, 4))
	zones.paint_cell("docks", EXTRACTION, Vector2i(8, 8))

	assert_array(zones.zone_names_of(PATROL)).contains_exactly(["gate"])
	assert_array(zones.zone_names_of(CAPTURE)).contains_exactly(["throne"])
	assert_array(zones.zone_names_of(EXTRACTION)).contains_exactly(["docks"])


func test_kind_of_reads_back_what_was_painted() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("throne", CAPTURE, Vector2i(4, 4))

	assert_int(zones.kind_of("throne")).is_equal(CAPTURE)


# A zone that doesn't exist has to answer SOMETHING, and PATROL is the inert answer — it drives no
# objective, so an unknown name can never accidentally declare one.
func test_kind_of_an_unknown_zone_is_patrol() -> void:
	assert_int(_zones().kind_of("nope")).is_equal(PATROL)


func test_repainting_an_existing_zone_retypes_it() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("throne", PATROL, Vector2i(4, 4))
	zones.paint_cell("throne", CAPTURE, Vector2i(5, 4))

	assert_int(zones.kind_of("throne")).is_equal(CAPTURE)
	assert_array(zones.cells_in("throne")).contains_exactly_in_any_order([Vector2i(4, 4), Vector2i(5, 4)])


func test_zone_at_finds_the_owning_zone() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("throne", CAPTURE, Vector2i(4, 4))

	assert_str(zones.zone_at(Vector2i(4, 4))).is_equal("throne")


func test_zone_at_is_empty_for_an_unpainted_cell() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("throne", CAPTURE, Vector2i(4, 4))

	assert_str(zones.zone_at(Vector2i(0, 0))).is_equal("")


# ---- persistence ----

func test_dict_round_trip() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("gate", PATROL, Vector2i(1, 1))
	zones.paint_cell("gate", PATROL, Vector2i(2, 1))
	zones.paint_cell("yard", PATROL, Vector2i(7, 3))

	var restored: ZoneManager = auto_free(ZoneManager.new())
	restored.paint_cell("stale", PATROL, Vector2i(0, 0))   # load must clear pre-existing content
	restored.load_dict(zones.to_dict())

	assert_array(restored.zone_names()).contains_exactly_in_any_order(["gate", "yard"])
	assert_array(restored.cells_in("gate")).contains_exactly_in_any_order([Vector2i(1, 1), Vector2i(2, 1)])
	assert_array(restored.cells_in("yard")).contains_exactly([Vector2i(7, 3)])
	assert_bool(restored.contains("stale", Vector2i(0, 0))).is_false()


# The one that matters for missions: an objective's geometry is persisted ONLY as a zone kind, so
# a kind lost in the round-trip silently turns a capture map into a rout map.
func test_dict_round_trip_preserves_kinds() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("gate", PATROL, Vector2i(1, 1))
	zones.paint_cell("throne", CAPTURE, Vector2i(4, 4))
	zones.paint_cell("docks", EXTRACTION, Vector2i(8, 8))

	var restored: ZoneManager = auto_free(ZoneManager.new())
	restored.load_dict(zones.to_dict())

	assert_int(restored.kind_of("gate")).is_equal(PATROL)
	assert_int(restored.kind_of("throne")).is_equal(CAPTURE)
	assert_int(restored.kind_of("docks")).is_equal(EXTRACTION)
