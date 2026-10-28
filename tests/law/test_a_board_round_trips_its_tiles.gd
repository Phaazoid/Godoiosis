# A board's tile layer comes back out of BoardGrid.restore() exactly as it went in, so the dev
# tools' Update writes a loaded board's tile_data line back byte for byte.
#
# TileMapLayer.clear() only MARKS a cell deleted until the frame's internal update. A bulk write in
# the same call re-sets every cell the previous board also had IN PLACE, at that board's position,
# and a read in that frame still emits the marked cells as source -1 records. So before restore()
# purged, the order an Update wrote depended on which board was loaded first (Prolog, #1513), and a
# save taken in the frame of a clear wrote thousands of deleted cells (the four AI fixtures, #1225).
#
# The committed-board case derives its expectation from each file's own bytes, so it pins no
# authored content: it fails only when the writer would not reproduce what is committed.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")


func _grid() -> BoardGrid:
	var grid: BoardGrid = auto_free(BoardGrid.new())
	grid.tile_set = load(BoardBuilder.TILESET_PATH)
	add_child(grid)
	return grid


# The bytes a layer holding `cells`, set in that order, serializes to.
func _bytes_for(cells: Array[Vector2i]) -> PackedByteArray:
	var layer := TileMapLayer.new()
	layer.tile_set = load(BoardBuilder.TILESET_PATH)
	for cell: Vector2i in cells:
		layer.set_cell(cell, 0, Vector2i(5, 0))
	var bytes := layer.tile_map_data
	layer.free()
	return bytes


func test_a_restore_lands_the_datas_own_order_over_an_overlapping_board() -> void:
	var grid := _grid()
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(5, 5), Vector2i(2, 0)]:
		grid.paint(cell, 0, Vector2i(5, 0))
	await await_idle_frame()

	# Overlapping cells in another order, one new cell, and (5, 5) dropped.
	var data := _bytes_for([Vector2i(2, 0), Vector2i(9, 9), Vector2i(1, 0), Vector2i(0, 0)])
	grid.restore(data)

	assert_bool(grid.tile_map_data == data).override_failure_message(
		"restore() did not land its data as given: the previous board's order or its deleted cells "
		+ "survived the write, so an Update would save a different tile_data line"
	).is_true()


func test_every_committed_board_round_trips_its_tile_data() -> void:
	var grid := _grid()
	var manager: ScenarioManager = auto_free(ScenarioManager.new())
	var checked := 0
	var offenders: Array[String] = []
	for path: String in manager.get_saved_scenarios():
		var scenario := load(path) as ScenarioData
		if scenario == null or scenario.tile_data.is_empty():
			continue
		checked += 1
		# The previous board: the same cells, set in reverse, so any order a restore keeps from what
		# was there before shows.
		var reader := TileMapLayer.new()
		reader.tile_set = grid.tile_set
		reader.tile_map_data = scenario.tile_data
		var cells: Array[Vector2i] = reader.get_used_cells()
		cells.reverse()
		grid.reset()
		await await_idle_frame()   # the reset's marked cells must be gone, or the paint keeps their order
		for cell: Vector2i in cells:
			grid.paint(cell, reader.get_cell_source_id(cell), reader.get_cell_atlas_coords(cell),
					reader.get_cell_alternative_tile(cell))
		reader.free()
		await await_idle_frame()

		grid.restore(scenario.tile_data)
		# Read a frame later, as an Update does: a deleted record in the file goes in as a marked
		# cell and only leaves at the frame's end.
		await await_idle_frame()
		if grid.tile_map_data != scenario.tile_data:
			offenders.append(path)

	assert_array(offenders).override_failure_message(
		"An Update would rewrite these boards' tile_data line. Either restore() kept the previous "
		+ "board's order, or the file holds cells the writer does not emit (a save taken in the "
		+ "frame of a clear writes deleted ones); re-save it through the dev tools:\n  "
		+ "\n  ".join(offenders)
	).is_empty()
	assert_int(checked).override_failure_message(
		"no committed board was checked -- the scan is wrong, not the repo"
	).is_greater(5)
