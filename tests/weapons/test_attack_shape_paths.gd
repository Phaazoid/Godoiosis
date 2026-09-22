# A shape's PATHS as data (#1056): the flat pair (path_cells + path_lengths) read back as paths, and
# path_fault, the one judge of whether the pair is sound. Nothing reads paths in play yet (#1057), so
# this is the whole of what they mean for now. Shapes are built here, never loaded.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

const A := Vector2i(0, -1)
const B := Vector2i(0, -2)
const C := Vector2i(1, -1)


func _two_paths() -> AttackShape:
	return P.pathed([A, B, C] as Array[Vector2i],
		[[A, B, A] as Array[Vector2i], [C] as Array[Vector2i]] as Array[Array])


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
	var paths: Array[Array] = [[A, B] as Array[Vector2i], [C, C, A] as Array[Vector2i]]
	var cells := AttackShape.joined_cells(paths)
	var lengths := AttackShape.joined_lengths(paths)
	assert_array(cells).contains_exactly([A, B, C, C, A])
	assert_array(lengths).contains_exactly([2, 3])
	var back := AttackShape.split_paths(cells, lengths)
	assert_int(back.size()).is_equal(2)
	assert_array(back[0]).contains_exactly([A, B])
	assert_array(back[1]).contains_exactly([C, C, A])


func test_a_shape_with_no_paths_is_sound() -> void:
	assert_str(P.shape([A] as Array[Vector2i]).path_fault()).is_equal("")


func test_a_revisit_is_sound() -> void:
	# Dev ruling, 2026-09-22: a path may visit the same tile twice.
	assert_str(_two_paths().path_fault()).is_equal("")


func test_lengths_that_disagree_with_the_cells_are_a_fault() -> void:
	var shape := _two_paths()
	shape.path_lengths = [3, 2] as Array[int]
	assert_str(shape.path_fault()).contains("add up to 5")


func test_an_empty_path_is_a_fault() -> void:
	var shape := _two_paths()
	shape.path_lengths = [4, 0] as Array[int]
	assert_str(shape.path_fault()).contains("no tiles")


func test_a_path_off_the_stamp_is_a_fault() -> void:
	# A path tile is always one of the shape's tiles; the grid keeps that, a hand edit may not.
	var shape := _two_paths()
	shape.stamp = [A, B] as Array[Vector2i]
	assert_str(shape.path_fault()).contains("1,-1")


func test_paths_leave_the_stamp_and_its_placement_alone() -> void:
	# Inert until #1057: the footprint of a shape is its stamp whatever paths it carries.
	var plain := P.shape([A, B, C] as Array[Vector2i])
	var pathed := _two_paths()
	assert_array(pathed.place(Vector2i(4, 4), AttackShape.FORWARD)).contains_exactly(
		plain.place(Vector2i(4, 4), AttackShape.FORWARD))
