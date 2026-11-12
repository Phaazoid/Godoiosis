# THE WIND DRIFTS GAS (#1660): after spill and fade, every gas the round's step runs moves the board's
# wind's drift downwind (GasSpread._drift), along can_cross, and leaves past the board's edge. Every cloud
# walks from one snapshot, and a tile keeps the thickest that ends there, the younger on a tie.
#
# The content razor: the wind's and steam's rules are injected in memory (WindRules/GasRules caches,
# restored after), so retuning a file moves nothing here. THIN steam is used wherever a spill would only
# blur the case, because THIN never spills.
extends GdUnitTestSuite

const C := Vector2i(4, 4)
const STEAM := Gas.Kind.STEAM
const THIN := Gas.Level.THIN
const MEDIUM := Gas.Level.MEDIUM
const THICK := Gas.Level.THICK
const EAST := Wind.Direction.EAST
const NORTH_EAST := Wind.Direction.NORTH_EAST
const STRONG := Wind.Kind.STRONG_WIND

var _wind_cache: Dictionary
var _gas_cache: Dictionary


class _FakeBoard extends BoardContext:
	var ground := {}
	var walls := {}
	var holes := {}
	var corners := {}
	var marks := {}   # Vector2i -> the cell's time marks
	func _init(grid_layer: TileMapLayer) -> void:
		var no_units: Array[Unit] = []
		super(grid_layer, no_units, null)
	func has_ground(cell: Vector2i) -> bool:
		return ground.has(cell)
	func is_void_at(cell: Vector2i) -> bool:
		return holes.has(cell)
	func is_walkable(cell: Vector2i) -> bool:
		return ground.has(cell) and not walls.has(cell)
	func terrain_kind_at(_cell: Vector2i) -> Terrain.Kind:
		return Terrain.Kind.GRASS
	func corners_at(cell: Vector2i) -> Vector4i:
		return corners.get(cell, Vector4i.ZERO)
	func paces_at(cell: Vector2i) -> Dictionary:
		return marks.get(cell, {})


func before_test() -> void:
	_wind_cache = WindRules._rules_by_kind.duplicate()
	_gas_cache = GasRules._rules_by_kind.duplicate()
	var steam := GasRules.new()
	steam.hold_rounds = 4   # nothing fades inside a case, so a level is only ever moved
	GasRules._rules_by_kind[STEAM] = steam
	_wind(STRONG, 1)


func after_test() -> void:
	WindRules._rules_by_kind = _wind_cache
	GasRules._rules_by_kind = _gas_cache


func _wind(kind: Wind.Kind, drift: int) -> void:
	var rules := WindRules.new()
	rules.drift = drift
	WindRules._rules_by_kind[kind] = rules


# A flat 9x9 field of open ground, the wind STRONG toward `direction`.
func _board(direction := EAST, kind := STRONG) -> _FakeBoard:
	var board := _FakeBoard.new(auto_free(TileMapLayer.new()))
	for x in 9:
		for y in 9:
			board.ground[Vector2i(x, y)] = true
	board.wind = kind
	board.wind_direction = direction
	return board


func _field(cells: Dictionary, ages := {}) -> Dictionary[Vector2i, int]:
	var out: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in cells:
		out[cell] = Gas.with_level(0, STEAM, cells[cell], int(ages.get(cell, 0)))
	return out


func _level(field: Dictionary[Vector2i, int], cell: Vector2i, kind := STEAM) -> int:
	return Gas.level_in(field.get(cell, 0), kind)


# Where the field's steam lies, as {cell: level}.
func _steam(field: Dictionary[Vector2i, int]) -> Dictionary:
	var out := {}
	for cell: Vector2i in field:
		var level := _level(field, cell)
		if level > 0:
			out[cell] = level
	return out


func _steam_part() -> String:
	var parts := CellSubstances.present_from(SubstanceMap.authored().of_gas(STEAM))
	if parts.is_empty():
		fail("precondition: steam is made of nothing in the authored map, so no mark can name it")
		return ""
	return parts[0]


func _pace(board: _FakeBoard, cells: Array[Vector2i], kind: Pace.Kind) -> void:
	for cell in cells:
		board.marks[cell] = {_steam_part(): Pace.mark(kind, 2)}


# A one-row corridor along y 4, so a spill only ever runs along the wind's own line.
func _corridor() -> _FakeBoard:
	var board := _board()
	board.ground.clear()
	for x in 9:
		board.ground[Vector2i(x, 4)] = true
	return board


# --- it moves, and how far ----------------------------------------------------------------------

func test_a_cloud_drifts_its_winds_tiles_downwind() -> void:
	var next := GasSpread.next(_field({C: THIN}), _board())
	assert_dict(_steam(next)).is_equal({C + Vector2i(1, 0): THIN})


func test_a_stronger_drift_carries_it_further() -> void:
	_wind(STRONG, 2)
	var next := GasSpread.next(_field({C: THIN}), _board())
	assert_dict(_steam(next)).is_equal({C + Vector2i(2, 0): THIN})


# A thick cloud spills first and the whole cloud then moves: the drift is the last thing the step does.
func test_a_cloud_spills_where_it_lay_and_then_drifts() -> void:
	var still := GasSpread.next(_field({C: THICK}), _board(EAST, Wind.Kind.CALM))
	var moved := GasSpread.next(_field({C: THICK}), _board())
	var expected := {}
	for cell: Vector2i in _steam(still):
		expected[cell + Vector2i(1, 0)] = _steam(still)[cell]
	assert_int(expected.size()).override_failure_message("precondition: the calm cloud spilled nothing").is_greater(1)
	assert_dict(_steam(moved)).is_equal(expected)


func test_no_drift_moves_nothing() -> void:
	_wind(Wind.Kind.BREEZE, 0)
	var next := GasSpread.next(_field({C: THIN}), _board(EAST, Wind.Kind.BREEZE))
	assert_dict(_steam(next)).is_equal({C: THIN})


func test_a_wind_with_no_rules_moves_nothing() -> void:
	WindRules._rules_by_kind[Wind.Kind.GALE] = null
	var next := GasSpread.next(_field({C: THIN}), _board(EAST, Wind.Kind.GALE))
	assert_dict(_steam(next)).is_equal({C: THIN})


func test_a_gas_with_no_rules_never_drifts() -> void:
	GasRules._rules_by_kind[Gas.Kind.POISON] = null
	var poison := Gas.with_level(0, Gas.Kind.POISON, THIN)
	var cells: Dictionary[Vector2i, int] = {C: poison}
	var next := GasSpread.next(cells, _board())
	assert_dict(next).is_equal(cells)


# --- what stops it ------------------------------------------------------------------------------

func test_a_wall_stops_it_on_the_tile_before() -> void:
	_wind(STRONG, 2)
	var board := _board()
	board.walls[C + Vector2i(2, 0)] = true
	assert_dict(_steam(GasSpread.next(_field({C: THIN}), board))).is_equal({C + Vector2i(1, 0): THIN})


func test_a_sheer_ledge_stops_it_and_a_ramp_lets_it_through() -> void:
	var sheer := _board()
	sheer.corners[C + Vector2i(1, 0)] = Vector4i(2, 2, 2, 2)
	assert_dict(_steam(GasSpread.next(_field({C: THIN}), sheer))).override_failure_message(
		"steam drifted up a sheer ledge").is_equal({C: THIN})
	var ramp := _board()
	ramp.corners[C + Vector2i(1, 0)] = Vector4i(0, 2, 2, 0)   # its WEST edge meets C at the bottom
	assert_dict(_steam(GasSpread.next(_field({C: THIN}), ramp))).override_failure_message(
		"steam could not drift up a ramp").is_equal({C + Vector2i(1, 0): THIN})


func test_a_hole_stops_it() -> void:
	var board := _board()
	board.holes[C + Vector2i(1, 0)] = true
	assert_dict(_steam(GasSpread.next(_field({C: THIN}), board))).is_equal({C: THIN})


# Past the board's edge is open sky (#1638's rule): the wind carries the cloud away.
func test_a_cloud_at_the_edge_blows_off_the_board() -> void:
	var edge := Vector2i(8, 4)
	var next := GasSpread.next(_field({edge: THIN}), _board())
	assert_dict(_steam(next)).is_empty()


# --- a diagonal wind ----------------------------------------------------------------------------

func test_a_diagonal_wind_moves_a_cloud_a_tile_diagonally() -> void:
	var next := GasSpread.next(_field({C: THIN}), _board(NORTH_EAST))
	assert_dict(_steam(next)).is_equal({C + Vector2i(1, -1): THIN})


func test_a_diagonal_goes_round_through_either_open_side() -> void:
	var east_walled := _board(NORTH_EAST)
	east_walled.walls[C + Vector2i(1, 0)] = true
	assert_dict(_steam(GasSpread.next(_field({C: THIN}), east_walled))).override_failure_message(
		"the north leg was open and the cloud stayed").is_equal({C + Vector2i(1, -1): THIN})
	var north_walled := _board(NORTH_EAST)
	north_walled.walls[C + Vector2i(0, -1)] = true
	assert_dict(_steam(GasSpread.next(_field({C: THIN}), north_walled))).override_failure_message(
		"the east leg was open and the cloud stayed").is_equal({C + Vector2i(1, -1): THIN})


func test_a_diagonal_with_both_sides_walled_holds() -> void:
	var board := _board(NORTH_EAST)
	board.walls[C + Vector2i(1, 0)] = true
	board.walls[C + Vector2i(0, -1)] = true
	assert_dict(_steam(GasSpread.next(_field({C: THIN}), board))).is_equal({C: THIN})


# Both side tiles open, and a sheer ledge between each and the corner: no leg pair crosses.
func test_a_diagonal_blocked_by_a_ledge_on_both_legs_holds() -> void:
	var board := _board(NORTH_EAST)
	board.corners[C + Vector2i(1, -1)] = Vector4i(2, 2, 2, 2)
	assert_dict(_steam(GasSpread.next(_field({C: THIN}), board))).is_equal({C: THIN})


# --- where clouds meet --------------------------------------------------------------------------

# A wall at x 5 and a drift of 2: the clouds at x 2, 3 and 4 all end on x 4, two arriving and one that
# could not move. The thickest stays.
func test_clouds_that_end_on_one_tile_keep_the_thickest() -> void:
	_wind(STRONG, 2)
	var board := _corridor()
	board.walls[Vector2i(5, 4)] = true
	var next := GasSpread.next(_field({Vector2i(2, 4): THIN, Vector2i(3, 4): MEDIUM, Vector2i(4, 4): THIN}), board)
	assert_int(_level(next, Vector2i(4, 4))).is_equal(MEDIUM)


# The order case: two equal clouds of different ages end on one tile, and the younger stays whichever
# is visited first.
func test_the_younger_of_two_equal_clouds_stays_whatever_the_order() -> void:
	var board := _corridor()
	board.walls[Vector2i(4, 4)] = true
	var a := Vector2i(2, 4)
	var b := Vector2i(3, 4)
	var ages := {a: 0, b: 2}
	var forward := _field({a: THIN, b: THIN}, ages)
	var backward: Dictionary[Vector2i, int] = {}
	for cell in [b, a]:
		backward[cell] = forward[cell]
	var one := GasSpread.next(forward, board)
	var two := GasSpread.next(backward, board)
	assert_dict(two).override_failure_message("the answer depends on the visiting order").is_equal(one)
	assert_int(Gas.age_in(one.get(b, 0), STEAM)).override_failure_message(
		"the older cloud stayed where the younger met it").is_equal(1)


# --- Still and Quicken (#1311) ------------------------------------------------------------------

func test_a_held_gas_stays_and_a_cloud_stops_short_of_it() -> void:
	_wind(STRONG, 2)
	var board := _corridor()
	var held := Vector2i(5, 4)
	_pace(board, [held] as Array[Vector2i], Pace.Kind.HELD)
	var next := GasSpread.next(_field({Vector2i(3, 4): THIN, held: THIN}), board)
	assert_dict(_steam(next)).is_equal({Vector2i(4, 4): THIN, held: THIN})


func test_a_cloud_quickened_on_both_tiles_drifts_twice() -> void:
	var board := _board()
	_pace(board, [C, C + Vector2i(1, 0)] as Array[Vector2i], Pace.Kind.QUICK)
	assert_dict(_steam(GasSpread.next(_field({C: THIN}), board))).is_equal({C + Vector2i(2, 0): THIN})


func test_a_cloud_that_drifts_off_its_quickened_tile_drifts_once() -> void:
	var board := _board()
	_pace(board, [C] as Array[Vector2i], Pace.Kind.QUICK)
	assert_dict(_steam(GasSpread.next(_field({C: THIN}), board))).is_equal({C + Vector2i(1, 0): THIN})
