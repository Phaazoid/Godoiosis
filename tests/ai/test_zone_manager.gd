# ZoneManager: the name -> {kind, cells} store painted via the Tile Brush Zone mode. Pure logic —
# no board or scene needed.
#
# Zones grew a KIND in #96 (2026-07-28) so one mechanism serves every region-shaped feature: a
# capture point is a zone of size one, not a parallel Array[Vector2i] on ScenarioData. The kind
# cases below are what stop that generalization from regressing into "cells, plus some other
# stuff" — in particular that a kind survives the round-trip, since ScenarioData.zones is the
# only place an authored objective's geometry is persisted.
#
# Zones OVERLAP since 2026-08-12 (enemies patrol an area containing a capture point), erase is
# scoped to one zone, and a zone's kind locks at creation — the overlap/kind/erase cases pin all
# three dev calls. zones_changed is the wire the Tile Brush picker rebuilds off; the signal cases
# count real emissions because a listener nobody fires is legal GDScript.
extends GdUnitTestSuite

const PATROL := ZoneManager.Kind.PATROL
const CAPTURE := ZoneManager.Kind.CAPTURE
const EXTRACTION := ZoneManager.Kind.EXTRACTION
const DEPLOYMENT := ZoneManager.Kind.DEPLOYMENT


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


func test_zones_overlap_freely() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("patrol route", PATROL, Vector2i(1, 1))
	zones.paint_cell("the point", CAPTURE, Vector2i(1, 1))

	assert_bool(zones.contains("patrol route", Vector2i(1, 1))).is_true()
	assert_bool(zones.contains("the point", Vector2i(1, 1))).is_true()
	assert_array(zones.zone_names()).contains_exactly_in_any_order(["patrol route", "the point"])


func test_repainting_an_owned_cell_does_not_duplicate_it() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("gate", PATROL, Vector2i(1, 1))
	zones.paint_cell("gate", PATROL, Vector2i(1, 1))   # a drag repaints every motion event

	assert_array(zones.cells_in("gate")).contains_exactly([Vector2i(1, 1)])


func test_erase_prunes_empty_zone() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("gate", PATROL, Vector2i(1, 1))
	zones.erase_cell_from("gate", Vector2i(1, 1))

	assert_array(zones.zone_names()).is_empty()
	assert_bool(zones.contains("gate", Vector2i(1, 1))).is_false()


func test_erase_is_scoped_to_its_zone() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("patrol route", PATROL, Vector2i(1, 1))
	zones.paint_cell("the point", CAPTURE, Vector2i(1, 1))
	zones.erase_cell_from("patrol route", Vector2i(1, 1))

	assert_bool(zones.contains("patrol route", Vector2i(1, 1))).is_false()
	assert_bool(zones.contains("the point", Vector2i(1, 1))).is_true()


func test_erase_untracked_cell_is_a_noop() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("gate", PATROL, Vector2i(1, 1))
	zones.erase_cell_from("gate", Vector2i(9, 9))
	zones.erase_cell_from("nope", Vector2i(1, 1))

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


# The silent-retype trap (reported 2026-08-12): painting more of a zone with a different kind
# picked used to convert the whole zone. Kind is authored at creation and never after.
func test_kind_locks_at_creation() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("throne", PATROL, Vector2i(4, 4))
	zones.paint_cell("throne", CAPTURE, Vector2i(5, 4))

	assert_int(zones.kind_of("throne")).is_equal(PATROL)
	assert_array(zones.cells_in("throne")).contains_exactly_in_any_order([Vector2i(4, 4), Vector2i(5, 4)])


# ---- the picker's wire ----

# The Tile Brush zone picker rebuilds off zones_changed. Count real emissions: a mutation that
# changed nothing must stay silent (a drag emits per motion event), and every real change —
# paint, erase, load — must speak.
func test_zones_changed_fires_on_change_and_only_on_change() -> void:
	var zones: ZoneManager = _zones()
	var hits: Array[int] = [0]
	zones.zones_changed.connect(func(): hits[0] += 1)

	zones.paint_cell("gate", PATROL, Vector2i(1, 1))
	assert_int(hits[0]).is_equal(1)
	zones.paint_cell("gate", CAPTURE, Vector2i(1, 1))   # owned cell: no-op, no emission
	assert_int(hits[0]).is_equal(1)
	zones.erase_cell_from("gate", Vector2i(9, 9))        # untracked cell: no-op, no emission
	assert_int(hits[0]).is_equal(1)
	zones.erase_cell_from("gate", Vector2i(1, 1))
	assert_int(hits[0]).is_equal(2)
	zones.load_dict({})
	assert_int(hits[0]).is_equal(3)


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


# Overlapping cells are just cells appearing in two zones' arrays — the dict format never encoded
# exclusivity, so overlap must survive the same round-trip untouched.
func test_dict_round_trip_preserves_overlap() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("patrol route", PATROL, Vector2i(1, 1))
	zones.paint_cell("the point", CAPTURE, Vector2i(1, 1))

	var restored: ZoneManager = auto_free(ZoneManager.new())
	restored.load_dict(zones.to_dict())

	assert_bool(restored.contains("patrol route", Vector2i(1, 1))).is_true()
	assert_bool(restored.contains("the point", Vector2i(1, 1))).is_true()


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


# --- Kind.DEPLOYMENT and the union query it needed (#736) ---

# The enum is PERSISTED (ScenarioData.zones stores plain ints), so its VALUES are format, not
# taste -- the content razor's exemption. The round-trip cases above cannot see this: they compare
# whatever ints the enum has against themselves, so a REORDER passes every one of them while every
# board on disk silently changes which kind its zones are.
func test_the_zone_kinds_keep_the_values_every_saved_board_was_written_with() -> void:
	assert_int(ZoneManager.Kind.PATROL).is_equal(0)
	assert_int(ZoneManager.Kind.CAPTURE).is_equal(1)
	assert_int(ZoneManager.Kind.EXTRACTION).is_equal(2)
	assert_int(ZoneManager.Kind.DEPLOYMENT).is_equal(3)


# The dedup is the reason cells_of_kind exists at all: zones overlap freely, so summing cells_in()
# sizes over zone_names_of() counts a shared cell twice, and BoardLint's cap check would then be
# comparing an authored number against more room than the board has.
func test_cells_of_kind_counts_a_shared_cell_once() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("landing", DEPLOYMENT, Vector2i(1, 1))
	zones.paint_cell("landing", DEPLOYMENT, Vector2i(2, 1))
	zones.paint_cell("reserve", DEPLOYMENT, Vector2i(2, 1))   # the overlap
	zones.paint_cell("reserve", DEPLOYMENT, Vector2i(3, 1))

	# Four paints, three distinct cells. A naive sum over the two zones answers four.
	var cells: Array[Vector2i] = zones.cells_of_kind(DEPLOYMENT)
	assert_array(cells).contains_exactly_in_any_order(
		[Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)])
	# The SIZE is the assertion with teeth, and only a mutant said so: contains_exactly_in_any_order
	# compares membership, not multiplicity, so it passes on [a, b, b, c] -- exactly the array a
	# cells_of_kind with no dedup returns. A caller asking "how much room is there" reads the count.
	assert_int(cells.size()).override_failure_message(
		"cells_of_kind counted the shared cell twice: %s" % str(cells)).is_equal(3)


func test_cells_of_kind_ignores_every_other_kind() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("landing", DEPLOYMENT, Vector2i(1, 1))
	zones.paint_cell("gate", PATROL, Vector2i(2, 2))
	zones.paint_cell("throne", CAPTURE, Vector2i(3, 3))

	assert_array(zones.cells_of_kind(DEPLOYMENT)).contains_exactly([Vector2i(1, 1)])
	assert_array(zones.cells_of_kind(PATROL)).contains_exactly([Vector2i(2, 2)])


func test_cells_of_kind_is_empty_when_nothing_of_that_kind_is_painted() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("gate", PATROL, Vector2i(1, 1))

	assert_array(zones.cells_of_kind(DEPLOYMENT)).is_empty()


# The Tile Brush indexed a parallel label array RAW, so a kind added without a label was an
# out-of-bounds crash in the zone dropdown rather than a missing string. Deriving from the enum is
# what makes a new kind cost the brush nothing -- this asserts the derivation reads well, since a
# key that capitalizes badly is the one way it could be a bad trade.
func test_kind_display_name_reads_every_kind() -> void:
	assert_str(ZoneManager.kind_display_name(PATROL)).is_equal("Patrol")
	assert_str(ZoneManager.kind_display_name(CAPTURE)).is_equal("Capture")
	assert_str(ZoneManager.kind_display_name(EXTRACTION)).is_equal("Extraction")
	assert_str(ZoneManager.kind_display_name(DEPLOYMENT)).is_equal("Deployment")


func test_a_deployment_zone_survives_the_dict_round_trip_with_its_kind() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("landing", DEPLOYMENT, Vector2i(6, 7))
	var data := zones.to_dict()

	var restored: ZoneManager = _zones()
	restored.load_dict(data)

	assert_int(restored.kind_of("landing")).is_equal(DEPLOYMENT)
	assert_array(restored.cells_in("landing")).contains_exactly([Vector2i(6, 7)])
