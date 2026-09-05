# PreMission.deployment_plan (#737) -- WHO the roster sends and WHERE each of them stands. Pure
# logic, no board and no scene: the walk deliberately spawns nothing, so that the game and the
# headless Play API can reach the same answer through their own spawners.
#
# The cases that matter are the CONTRACTS, not the arithmetic. Cells arrive already legal (the host
# owns "may a unit stand here"), nothing is written back onto an entry (they are shared
# sub-resources of a cached Roster), and the order is the author's for who and reading order for
# where -- the zone store's own order is insertion x paint order, which nobody can reason about.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


func _entry(name: String) -> ScenarioUnitEntry:
	var data := H.make_unit_data({}, Team.Faction.PLAYER)   # its overrides are STAT keys, not fields
	data.display_name = name
	var entry := ScenarioUnitEntry.new()
	entry.unit_data = data
	entry.state_saved = false
	return entry


func _entries(count: int) -> Array[ScenarioUnitEntry]:
	var list: Array[ScenarioUnitEntry] = []
	for i in range(count):
		list.append(_entry("Unit%d" % i))
	return list


func _cells_of(plan: Array[Dictionary]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row: Dictionary in plan:
		cells.append(row[PreMission.CELL])
	return cells


func _names_of(plan: Array[Dictionary]) -> Array[String]:
	var names: Array[String] = []
	for row: Dictionary in plan:
		var entry: ScenarioUnitEntry = row[PreMission.ENTRY]
		names.append(entry.unit_data.display_name)
	return names


# --- who, and where ---

func test_entries_deploy_in_roster_order_onto_cells_in_reading_order() -> void:
	var cells: Array[Vector2i] = [Vector2i(5, 9), Vector2i(1, 2), Vector2i(4, 2)]
	var plan: Array[Dictionary] = PreMission.deployment_plan(_entries(3), cells, PreMission.NO_CAP)

	assert_array(_names_of(plan)).is_equal(["Unit0", "Unit1", "Unit2"])
	# Top-left first, rows before columns -- NOT the order the cells arrived in.
	assert_array(_cells_of(plan)).is_equal([Vector2i(1, 2), Vector2i(4, 2), Vector2i(5, 9)])


func test_the_cell_order_does_not_depend_on_the_order_the_zone_stored_them() -> void:
	# Determinism as a PROPERTY, not as a literal: two callers handing the same set in different
	# orders must get the same answer. Asserting specific cells here would pin authored geometry.
	var forwards: Array[Vector2i] = [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 1)]
	var backwards: Array[Vector2i] = [Vector2i(0, 1), Vector2i(3, 0), Vector2i(0, 0)]

	assert_array(_cells_of(PreMission.deployment_plan(_entries(3), forwards, PreMission.NO_CAP))) \
		.is_equal(_cells_of(PreMission.deployment_plan(_entries(3), backwards, PreMission.NO_CAP)))


# --- the three limits, which compose ---

func test_no_cap_sends_as_many_as_the_zone_holds() -> void:
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	assert_int(PreMission.deployment_plan(_entries(5), cells, PreMission.NO_CAP).size()).is_equal(3)


func test_the_cap_limits_the_draw_below_what_the_zone_would_hold() -> void:
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var plan: Array[Dictionary] = PreMission.deployment_plan(_entries(4), cells, 2)

	assert_int(plan.size()).is_equal(2)
	assert_array(_names_of(plan)).is_equal(["Unit0", "Unit1"])


func test_a_roster_smaller_than_the_cap_sends_everyone_it_has() -> void:
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	assert_int(PreMission.deployment_plan(_entries(2), cells, 9).size()).is_equal(2)


func test_a_zone_with_no_room_sends_nobody() -> void:
	var none: Array[Vector2i] = []
	assert_array(PreMission.deployment_plan(_entries(3), none, PreMission.NO_CAP)).is_empty()


# --- the two contracts ---

func test_an_entry_with_no_unit_data_is_skipped_rather_than_deploying_nothing() -> void:
	# RosterLint reports an empty entry at DEGRADES, so a half-authored roster file legitimately
	# reaches here. Skipping keeps the SLOT usable: the next real entry takes that cell.
	var list: Array[ScenarioUnitEntry] = [_entry("A"), ScenarioUnitEntry.new(), _entry("B")]
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]

	assert_array(_names_of(PreMission.deployment_plan(list, cells, PreMission.NO_CAP))) \
		.is_equal(["A", "B"])


func test_the_walk_writes_nothing_back_onto_the_entries_it_pairs() -> void:
	# RosterCatalog.resolve serves the CACHED Roster, so its entries are shared sub-resources of a
	# file on disk. Filling `cell` in would edit content in memory, and the next roster save would
	# write it out -- which is why the plan is a separate pairing rather than a mutation.
	var list := _entries(2)
	var before_cells: Array[Vector2i] = [list[0].cell, list[1].cell]
	var cells: Array[Vector2i] = [Vector2i(7, 7), Vector2i(8, 7)]

	PreMission.deployment_plan(list, cells, PreMission.NO_CAP)

	assert_vector(list[0].cell).is_equal(before_cells[0])
	assert_vector(list[1].cell).is_equal(before_cells[1])
	assert_int(list[0].squad_id).is_equal(-1)


func test_the_walk_does_not_reorder_the_caller_s_own_cell_array() -> void:
	var cells: Array[Vector2i] = [Vector2i(5, 5), Vector2i(0, 0)]
	PreMission.deployment_plan(_entries(2), cells, PreMission.NO_CAP)
	assert_array(cells).is_equal([Vector2i(5, 5), Vector2i(0, 0)])
