# ZoneManager (#29 Sentry regions): the name->cells store painted via the Tile Brush Zone
# mode. Pure logic — no board or scene needed.
extends GdUnitTestSuite


func _zones() -> ZoneManager:
	var zones: ZoneManager = auto_free(ZoneManager.new())
	return zones


func test_paint_and_query() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("gate", Vector2i(1, 1))
	zones.paint_cell("gate", Vector2i(2, 1))

	assert_array(zones.zone_names()).contains_exactly(["gate"])
	assert_array(zones.cells_in("gate")).contains_exactly_in_any_order([Vector2i(1, 1), Vector2i(2, 1)])
	assert_bool(zones.contains("gate", Vector2i(1, 1))).is_true()
	assert_bool(zones.contains("gate", Vector2i(5, 5))).is_false()
	assert_array(zones.cells_in("nope")).is_empty()


func test_cell_belongs_to_at_most_one_zone() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("a", Vector2i(1, 1))
	zones.paint_cell("b", Vector2i(1, 1))   # repaint moves the cell, silently

	assert_bool(zones.contains("b", Vector2i(1, 1))).is_true()
	assert_bool(zones.contains("a", Vector2i(1, 1))).is_false()
	# "a" lost its only cell -> pruned entirely
	assert_array(zones.zone_names()).contains_exactly(["b"])


func test_erase_prunes_empty_zone() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("gate", Vector2i(1, 1))
	zones.erase_cell(Vector2i(1, 1))

	assert_array(zones.zone_names()).is_empty()
	assert_bool(zones.contains("gate", Vector2i(1, 1))).is_false()


func test_erase_untracked_cell_is_a_noop() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("gate", Vector2i(1, 1))
	zones.erase_cell(Vector2i(9, 9))

	assert_array(zones.cells_in("gate")).contains_exactly([Vector2i(1, 1)])


func test_dict_round_trip() -> void:
	var zones: ZoneManager = _zones()
	zones.paint_cell("gate", Vector2i(1, 1))
	zones.paint_cell("gate", Vector2i(2, 1))
	zones.paint_cell("yard", Vector2i(7, 3))

	var restored: ZoneManager = auto_free(ZoneManager.new())
	restored.paint_cell("stale", Vector2i(0, 0))   # load must clear pre-existing content
	restored.load_dict(zones.to_dict())

	assert_array(restored.zone_names()).contains_exactly_in_any_order(["gate", "yard"])
	assert_array(restored.cells_in("gate")).contains_exactly_in_any_order([Vector2i(1, 1), Vector2i(2, 1)])
	assert_array(restored.cells_in("yard")).contains_exactly([Vector2i(7, 3)])
	assert_bool(restored.contains("stale", Vector2i(0, 0))).is_false()
