# GasSpread (#508): how gas moves once per round -- Spill, the dev's pick (2026-10-03). A medium or
# thick cell raises each open side to one level thinner every round it holds; a cell thins a level
# after holding it for its gas's hold_rounds; thin never spreads; and nothing crosses an edge a unit
# could not walk over, except onto water (ruling 6).
#
# Pure: a fake board answers every question the rule asks, so a wall, a ledge, a ramp, deep water
# and a hole are each one line. Every timing is read off the AUTHORED hold_rounds, never written
# as a literal -- the number is the dev's to tune (tests/README.md #8).
extends GdUnitTestSuite

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)
const W := Vector2i(3, 4)
const N := Vector2i(4, 3)
const S := Vector2i(4, 5)
const STEAM := Gas.Kind.STEAM
const THIN := Gas.Level.THIN
const MEDIUM := Gas.Level.MEDIUM
const THICK := Gas.Level.THICK


class _FakeBoard extends BoardContext:
	var ground := {}
	var walls := {}
	var water := {}
	var holes := {}
	var corners := {}
	func _init(grid_layer: TileMapLayer) -> void:
		var no_units: Array[Unit] = []
		super(grid_layer, no_units, null)
	func has_ground(cell: Vector2i) -> bool:
		return ground.has(cell)
	func is_void_at(cell: Vector2i) -> bool:
		return holes.has(cell)
	func is_walkable(cell: Vector2i) -> bool:
		return ground.has(cell) and not walls.has(cell) and not water.has(cell)
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return Terrain.Kind.WATER if water.has(cell) else Terrain.Kind.GRASS
	func corners_at(cell: Vector2i) -> Vector4i:
		return corners.get(cell, Vector4i.ZERO)


# A flat 9x9 field of open ground. The grid is a real, empty layer: holds_gas only skips its own
# questions for a board with NO grid, and this fake answers every one of them itself.
func _board() -> _FakeBoard:
	var grid: TileMapLayer = auto_free(TileMapLayer.new())
	var board := _FakeBoard.new(grid)
	for x in 9:
		for y in 9:
			board.ground[Vector2i(x, y)] = true
	return board


func _hold() -> int:
	var rules := GasRules.for_kind(STEAM)
	assert_object(rules).override_failure_message("steam has no rules file -- nothing here can move").is_not_null()
	return rules.hold_rounds


func _field(cells: Dictionary) -> Dictionary[Vector2i, int]:
	var out: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in cells:
		var level: int = cells[cell]
		out[cell] = Gas.with_level(0, STEAM, level)
	return out


func _level(field: Dictionary[Vector2i, int], cell: Vector2i, kind := STEAM) -> int:
	return Gas.level_in(field.get(cell, 0), kind)


# What a cell's OWN level becomes after one round, holding since it was laid.
func _held(level: int) -> int:
	return level if _hold() > 1 else level - 1


func test_a_thick_cloud_spills_medium_onto_every_open_side() -> void:
	var next := GasSpread.next(_field({C: THICK}), _board())
	for side in [E, W, N, S]:
		assert_int(_level(next, side)).override_failure_message("no medium spilled to %s" % [side]).is_equal(MEDIUM)
	assert_int(_level(next, C)).is_equal(_held(THICK))


func test_thin_steam_never_spreads() -> void:
	var next := GasSpread.next(_field({C: THIN}), _board())
	for side in [E, W, N, S]:
		assert_int(_level(next, side)).is_equal(0)
	assert_int(_level(next, C)).is_equal(_held(THIN))


func test_spill_never_thins_a_thicker_neighbour() -> void:
	# Medium spills thin; a thick neighbour keeps whatever its own hold gives it.
	var next := GasSpread.next(_field({C: MEDIUM, E: THICK}), _board())
	assert_int(_level(next, E)).is_equal(_held(THICK))


func test_a_cell_thins_one_level_when_its_hold_runs_out() -> void:
	var hold := _hold()
	var field := _field({C: THICK})
	var board := _board()
	for r in hold:
		assert_int(_level(field, C)).override_failure_message("thinned early, at round %d of %d" % [r, hold]).is_equal(THICK)
		field = GasSpread.next(field, board)
	assert_int(_level(field, C)).is_equal(MEDIUM)


func test_a_wall_tile_stops_it() -> void:
	var board := _board()
	board.walls[E] = true
	var next := GasSpread.next(_field({C: THICK}), board)
	assert_int(_level(next, E)).is_equal(0)
	assert_int(_level(next, W)).override_failure_message("fixture: the open side never filled").is_equal(MEDIUM)


func test_a_hole_stops_it() -> void:
	var board := _board()
	board.holes[E] = true
	assert_int(_level(GasSpread.next(_field({C: THICK}), board), E)).is_equal(0)


func test_deep_water_carries_it() -> void:
	# Not walkable, but water: gas floats over it.
	var board := _board()
	board.water[E] = true
	assert_int(_level(GasSpread.next(_field({C: THICK}), board), E)).is_equal(MEDIUM)


func test_a_sheer_ledge_stops_it_and_a_ramp_lets_it_through() -> void:
	var board := _board()
	board.corners[E] = Vector4i(2, 2, 2, 2)   # a whole level up on every side: sheer to C
	board.corners[W] = Vector4i(2, 0, 0, 2)   # rises westward: its EAST edge meets C at the bottom
	var next := GasSpread.next(_field({C: THICK}), board)
	assert_int(_level(next, E)).override_failure_message("steam climbed a sheer ledge").is_equal(0)
	assert_int(_level(next, W)).override_failure_message("steam could not go up a ramp").is_equal(MEDIUM)


func test_a_gas_with_no_rules_file_never_moves() -> void:
	assert_object(GasRules.for_kind(Gas.Kind.SMOKE)).override_failure_message(
		"smoke has a rules file now -- point this case at a gas that does not").is_null()
	var smoke := Gas.with_level(0, Gas.Kind.SMOKE, THICK)
	var cells: Dictionary[Vector2i, int] = {C: smoke}
	var next := GasSpread.next(cells, _board())
	assert_int(next.size()).is_equal(1)
	assert_int(next[C]).is_equal(smoke)


func test_the_answer_does_not_depend_on_the_order_cells_are_visited() -> void:
	var a := Vector2i(2, 2)
	var b := Vector2i(3, 2)
	var c := Vector2i(5, 2)
	var forward: Dictionary[Vector2i, int] = {}
	var backward: Dictionary[Vector2i, int] = {}
	for cell in [a, b, c]:
		forward[cell] = Gas.with_level(0, STEAM, THICK if cell != b else MEDIUM)
	for cell in [c, b, a]:
		backward[cell] = Gas.with_level(0, STEAM, THICK if cell != b else MEDIUM)
	var board := _board()
	var one := GasSpread.next(forward, board)
	var two := GasSpread.next(backward, board)
	assert_int(one.size()).is_equal(two.size())
	for cell: Vector2i in one:
		assert_int(two.get(cell, -1)).override_failure_message("%s differs by visiting order" % [cell]).is_equal(one[cell])


func test_the_rule_reads_the_field_and_writes_nothing_into_it() -> void:
	var cells := _field({C: THICK})
	var before := cells.duplicate()
	GasSpread.next(cells, _board())
	assert_bool(cells == before).is_true()
