# AttackPattern geometry (#25). Pure Resource logic — no scene; the `user` arg is unused
# by these patterns, so `null` is safe.
extends GdUnitTestSuite

func test_manhattan_pattern_all_eight_neighbours() -> void:
	# max_and_a_half on a range-1 pattern selects the full Chebyshev ring (all 8); min_range 1
	# drops the origin. Confirms ManhattanRangePattern threads the blended helper through.
	var p := ManhattanRangePattern.new()
	p.max_range = 1
	p.max_and_a_half = true
	p.min_range = 1
	var cells := p.get_selectable_cells(null, Vector2i.ZERO, Vector2i.ZERO)
	assert_int(cells.size()).is_equal(8)
	assert_array(cells).not_contains([Vector2i.ZERO])
	assert_array(cells).contains([Vector2i(1, 1), Vector2i(-1, 1)])

func test_manhattan_pattern_plain_is_unchanged() -> void:
	# and_a_half defaults false → identical to the old Manhattan diamond (every existing .tres).
	var p := ManhattanRangePattern.new()
	p.max_range = 2
	p.min_range = 0
	var cells := p.get_selectable_cells(null, Vector2i.ZERO, Vector2i.ZERO)
	assert_array(cells).contains_exactly_in_any_order(GridUtils.cells_within_manhattan_range(Vector2i.ZERO, 2))

func test_directional_flag_by_pattern() -> void:
	# Forward patterns aim by facing (game.gd targets a direction); Manhattan aims at a cell.
	assert_bool(ForwardWidePattern.new().is_directional()).is_true()
	assert_bool(ForwardLinePattern.new().is_directional()).is_true()
	assert_bool(ManhattanRangePattern.new().is_directional()).is_false()
