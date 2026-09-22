# A shape's PATHS as data (#1056, #1079): the flat pair (path_cells + path_lengths) read back as
# paths, tiles() -- which tiles a shape covers, painted or pathed -- and path_fault, the one judge of
# whether the pair is sound. Resolving a path as a single-target swing is #1057's, so until then a
# path shape lands on its tiles like any other. Shapes are built here, never loaded.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

const A := Vector2i(0, -1)
const B := Vector2i(0, -2)
const C := Vector2i(1, -1)


func _two_paths() -> AttackShape:
	return P.pathed([[A, B, A] as Array[Vector2i], [C] as Array[Vector2i]] as Array[Array])


func test_each_path_reads_back_in_its_own_order() -> void:
	var shape := _two_paths()
	assert_int(shape.path_count()).is_equal(2)
	assert_array(shape.path_at(0)).contains_exactly([A, B, A])
	assert_array(shape.path_at(1)).contains_exactly([C])


func test_an_index_past_the_end_reads_as_no_tiles() -> void:
	var shape := _two_paths()
	assert_array(shape.path_at(2)).is_empty()
	assert_array(shape.path_at(-1)).is_empty()


func test_splitting_and_joining_are_inverses() -> void:
	var paths: Array[Array] = [[A, B] as Array[Vector2i], [C, A, C] as Array[Vector2i]]
	var cells := AttackShape.joined_cells(paths)
	var lengths := AttackShape.joined_lengths(paths)
	assert_array(cells).contains_exactly([A, B, C, A, C])
	assert_array(lengths).contains_exactly([2, 3])
	var back := AttackShape.split_paths(cells, lengths)
	assert_int(back.size()).is_equal(2)
	assert_array(back[0]).contains_exactly([A, B])
	assert_array(back[1]).contains_exactly([C, A, C])


func test_a_painted_shape_covers_its_stamp() -> void:
	var shape := P.shape([A, C] as Array[Vector2i])
	assert_bool(shape.is_path_shape()).is_false()
	assert_array(shape.tiles()).contains_exactly([A, C])


func test_a_path_shape_covers_what_its_paths_visit_once_each_in_first_visit_order() -> void:
	var shape := P.pathed([[B, A, B] as Array[Vector2i], [C, A] as Array[Vector2i]] as Array[Array])
	assert_bool(shape.is_path_shape()).is_true()
	assert_array(shape.tiles()).contains_exactly([B, A, C])


func test_a_path_shape_lands_on_the_tiles_its_paths_visit() -> void:
	# Until #1057 a path shape fires as an AoE over its tiles, so it places exactly as a painted shape
	# of those tiles would -- and its own stamp is empty, so a place() reading the stamp lands nowhere.
	var painted := P.shape([A, B, C] as Array[Vector2i])
	var placed := _two_paths().place(Vector2i(4, 4), AttackShape.FORWARD)
	assert_array(placed).is_not_empty()
	assert_array(placed).contains_exactly(painted.place(Vector2i(4, 4), AttackShape.FORWARD))


func test_a_shape_with_no_paths_is_sound() -> void:
	assert_str(P.shape([A] as Array[Vector2i]).path_fault()).is_equal("")


func test_a_revisit_that_is_not_back_to_back_is_sound() -> void:
	# Dev ruling, 2026-09-22: a path may come back to a tile it has already visited.
	assert_str(_two_paths().path_fault()).is_equal("")


func test_visiting_a_tile_twice_in_a_row_is_a_fault() -> void:
	# Dev ruling, 2026-09-22: "it does not make sense to visit the same tile twice in a row".
	var shape := P.pathed([[B, A, A] as Array[Vector2i]] as Array[Array])
	assert_str(shape.path_fault()).contains("0,-1 twice in a row")


func test_painted_tiles_beside_paths_are_a_fault() -> void:
	# A shape is painted tiles OR paths; the grid clears one kind to write the other.
	var shape := _two_paths()
	shape.stamp = [A] as Array[Vector2i]
	assert_str(shape.path_fault()).contains("both painted tiles and paths")


func test_lengths_that_disagree_with_the_cells_are_a_fault() -> void:
	var shape := _two_paths()
	shape.path_lengths = [3, 2] as Array[int]
	assert_str(shape.path_fault()).contains("add up to 5")


func test_an_empty_path_is_a_fault() -> void:
	var shape := _two_paths()
	shape.path_lengths = [4, 0] as Array[int]
	assert_str(shape.path_fault()).contains("no tiles")
