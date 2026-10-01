# GasRegions (#508): where the gas volume marches. Pure -- cells and two answers in, boxes out, no
# scene. The property everything rests on is that the boxes come out DISJOINT, because the compute
# pass marches every box a ray crosses one after another and an overlap would count gas twice.
extends GdUnitTestSuite

const FLAT := Vector2(0.0, 0.0)


func _flat(_cell: Vector2i) -> Vector2:
	return FLAT


func _top(_cell: Vector2i) -> float:
	return 2.0


func _boxes(cells: Array[Vector2i], offset := Vector3.ZERO) -> Array[AABB]:
	return GasRegions.boxes(cells, _flat, _top, offset)


func _assert_disjoint(boxes: Array[AABB]) -> void:
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			assert_bool(boxes[i].intersects(boxes[j])).override_failure_message(
				"boxes %s and %s overlap -- a ray through both would count that gas twice" % [boxes[i], boxes[j]]
			).is_false()


func test_an_l_shape_is_one_patch_and_one_box() -> void:
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]
	assert_int(GasRegions.patches(cells).size()).is_equal(1)
	var boxes := _boxes(cells)
	assert_int(boxes.size()).is_equal(1)
	# The box covers every cell with the pad all round, and stands as tall as the column.
	assert_bool(boxes[0].has_point(Vector3(0.5, 1.0, 0.5))).is_true()
	assert_bool(boxes[0].has_point(Vector3(2.5, 1.0, 2.5))).is_true()
	assert_float(boxes[0].position.x).is_equal_approx(-GasRegions.PAD, 0.0001)
	assert_float(boxes[0].end.y).is_equal_approx(2.0 + GasRegions.ABOVE, 0.0001)


func test_a_diagonal_touch_joins_the_patch() -> void:
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 1)]
	assert_int(GasRegions.patches(cells).size()).is_equal(1)


func test_far_apart_patches_keep_their_own_boxes() -> void:
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(10, 10), Vector2i(10, 11)]
	var boxes := _boxes(cells)
	assert_int(boxes.size()).is_equal(2)
	_assert_disjoint(boxes)


func test_patches_whose_padding_meets_are_merged() -> void:
	# One empty cell between: separate patches, but a cell of pad each way makes their boxes overlap.
	# (Two apart, the pads only TOUCH, which is disjoint and stays two boxes.)
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0)]
	assert_int(GasRegions.patches(cells).size()).is_equal(2)
	var boxes := _boxes(cells)
	assert_int(boxes.size()).is_equal(1)


func test_merging_never_leaves_an_overlap_behind() -> void:
	# A chain where merging two boxes makes the result reach a third.
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(3, 0), Vector2i(6, 3), Vector2i(12, 0), Vector2i(0, 8)]
	_assert_disjoint(_boxes(cells))


func test_a_lifted_copy_rides_the_stage_offset() -> void:
	var cells: Array[Vector2i] = [Vector2i(2, 2)]
	var offset := Vector3(0.0, 40.0, 0.0)
	var board := _boxes(cells)
	var lifted := _boxes(cells, offset)
	assert_vector(lifted[0].position).is_equal_approx(board[0].position + offset, Vector3.ONE * 0.0001)
	assert_vector(lifted[0].size).is_equal_approx(board[0].size, Vector3.ONE * 0.0001)


func test_the_box_spans_the_ground_it_stands_on() -> void:
	var ground := func(cell: Vector2i) -> Vector2: return Vector2(float(cell.x), float(cell.x) + 0.5)
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var box := GasRegions.boxes(cells, ground, _top)[0]
	assert_float(box.position.y).is_equal_approx(0.0 - GasRegions.BELOW, 0.0001)
	assert_float(box.end.y).is_equal_approx(2.5 + 2.0 + GasRegions.ABOVE, 0.0001)


func test_no_cells_no_boxes() -> void:
	var cells: Array[Vector2i] = []
	assert_int(_boxes(cells).size()).is_equal(0)
