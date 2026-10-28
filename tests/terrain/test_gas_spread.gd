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
const T := preload("res://tests/support/terrain_fixtures.gd")


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
	assert_object(GasRules.for_kind(Gas.Kind.POISON)).override_failure_message(
		"poison has a rules file now -- point this case at a gas that does not").is_null()
	var poison := Gas.with_level(0, Gas.Kind.POISON, THICK)
	var cells: Dictionary[Vector2i, int] = {C: poison}
	var next := GasSpread.next(cells, _board())
	assert_int(next.size()).is_equal(1)
	assert_int(next[C]).is_equal(poison)


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


# A gas that moves the air diffuses back (#1324): as the rounds thin it, its cell returns to the BOARD'S
# reading -- the authored one, which is Normal only on a Normal board. Read off whichever gases move the
# air, played through the real round (GasField.tick).
func test_a_gas_that_moves_the_air_fades_its_cell_back_to_the_boards_reading() -> void:
	var moving := 0
	for kind: Gas.Kind in Gas.Kind.values():
		var rules := GasRules.for_kind(kind)
		if rules == null or rules.air.is_empty():
			continue
		moving += 1
		var field := GasField.new()
		field.set_level(C, kind, THICK)
		var board := _board()
		board.gas = field
		var authored: Dictionary[String, int] = {"vapor": int(Atmosphere.NORMAL["vapor"]) + int(Atmosphere.STEP["vapor"])}
		board.atmosphere = authored
		assert_dict(board.air_at(C)).override_failure_message(
				"fixture: a thick %s moves nothing" % Gas.name_of(kind)).is_not_equal(authored)
		var rounds := 0
		while not field.is_empty() and rounds < 50:
			field.tick(board)
			rounds += 1
		assert_bool(field.is_empty()).override_failure_message(
				"%s never faded in %d rounds" % [Gas.name_of(kind), rounds]).is_true()
		assert_dict(board.air_at(C)).override_failure_message(
				"%s faded and left its cell off the board's reading" % Gas.name_of(kind)).is_equal(authored)
	assert_int(moving).override_failure_message("no gas's rules move the air, so nothing here is checked").is_greater(0)


func test_the_rule_reads_the_field_and_writes_nothing_into_it() -> void:
	var cells := _field({C: THICK})
	var before := cells.duplicate()
	GasSpread.next(cells, _board())
	assert_bool(cells == before).is_true()


# IGNITION (#1335): a cell fire takes this round gives off its ground's gases, the `gases` a hit lighting
# it releases. The fixture's fuel carries its own (never the authored grass's), and the cell already
# alight gives off nothing more -- "once", at the moment it catches.
func test_a_cell_fire_takes_gives_off_its_grounds_gases_and_the_fire_itself_nothing() -> void:
	var store: TerrainStateManager = auto_free(T.store_on_fuel())
	var fuel := store.fuel_at(C)
	fuel.gases = {Gas.Kind.SMOKE: THICK, STEAM: THIN}
	var lit := ResolvedCellEffect.new()
	lit.cell = C
	lit.states_added.assign([Terrain.TileState.BURNING])
	store.apply(lit)
	var board := _board()
	board.terrain_states = store
	var taken := store.cells_fire_takes()
	assert_bool(taken.is_empty()).override_failure_message("fixture: fire takes nothing").is_false()

	var nothing: Dictionary[Vector2i, int] = {}
	var next := GasSpread.next(nothing, board)
	for cell: Vector2i in taken:
		assert_int(_level(next, cell, Gas.Kind.SMOKE)).is_equal(THICK)
		assert_int(_level(next, cell, STEAM)).is_equal(THIN)
	assert_int(_level(next, C, Gas.Kind.SMOKE)).override_failure_message(
			"the cell already alight gave off smoke again").is_equal(0)
	assert_int(next.size()).is_equal(taken.size())


# #1430: the board's PLANNED TILES are where the fire spreads from -- what Alt's outline hands it, the
# previewed plan's (#1498). A tile a queued hit lights spreads (and gives off) as if alight already; the
# live store, which the round reads, still takes nothing.
func test_a_tile_a_deposit_lights_spreads_its_fire_and_gas_from_the_planned_tiles() -> void:
	var store: TerrainStateManager = auto_free(T.store_on_fuel())
	store.fuel_at(C).gases = {Gas.Kind.SMOKE: THICK}
	var lit := ResolvedCellEffect.new()
	lit.cell = C
	lit.states_added.assign([Terrain.TileState.BURNING])
	var tiles := PlannedTiles.new(store, null)
	tiles.land(lit)
	assert_bool(store.cells_fire_takes().is_empty()).override_failure_message(
			"fixture: the live store is already burning").is_true()
	var taken := store.cells_fire_takes(tiles)
	assert_array(taken).override_failure_message("a tile a deposit lights took nothing next round") \
		.contains_exactly_in_any_order(GridUtils.cells_within_blended_range(C, 1, false).filter(
			func(cell: Vector2i) -> bool: return cell != C))

	var board := _board()
	board.terrain_states = store
	var nothing: Dictionary[Vector2i, int] = {}
	assert_bool(GasSpread.next(nothing, board).is_empty()).override_failure_message(
			"a board with no planned tiles spread a fire nothing has lit").is_true()
	board.tiles = tiles
	var next := GasSpread.next(nothing, board)
	for cell: Vector2i in taken:
		assert_int(_level(next, cell, Gas.Kind.SMOKE)).override_failure_message(
				"%s takes the fire without its smoke" % [cell]).is_equal(THICK)


# ...and a deposit that puts a fire OUT takes its frontier away: a queued douse does not outline the
# smoke of a spread the round will never make.
func test_a_fire_a_deposit_puts_out_spreads_nothing() -> void:
	var store: TerrainStateManager = auto_free(T.store_on_fuel())
	var lit := ResolvedCellEffect.new()
	lit.cell = C
	lit.states_added.assign([Terrain.TileState.BURNING])
	store.apply(lit)
	assert_bool(store.cells_fire_takes().is_empty()).override_failure_message("fixture: fire takes nothing").is_false()
	var douse := ResolvedCellEffect.new()
	douse.cell = C
	douse.states_removed.assign([Terrain.TileState.BURNING])
	var tiles := PlannedTiles.new(store, null)
	tiles.land(douse)
	assert_bool(store.cells_fire_takes(tiles).is_empty()).override_failure_message(
			"a fire a deposit puts out still spreads").is_true()


# Laid AFTER spill and fade, so fresh smoke sits at its own level for a round with a fresh hold, and
# is added to what already lies there.
func test_a_spreading_fire_adds_its_gas_to_what_lies_there() -> void:
	var store: TerrainStateManager = auto_free(T.store_on_fuel())
	store.fuel_at(E).gases = {STEAM: THIN}
	var lit := ResolvedCellEffect.new()
	lit.cell = C
	lit.states_added.assign([Terrain.TileState.BURNING])
	store.apply(lit)
	var board := _board()
	board.terrain_states = store
	assert_bool(store.cells_fire_takes().has(E)).override_failure_message("fixture: fire does not take E").is_true()
	var next := GasSpread.next(_field({E: THIN}), board)
	assert_int(_level(next, E)).is_equal(mini(_held(THIN) + THIN, Gas.MAX_LEVEL))
	assert_int(Gas.age_in(next[E], STEAM)).override_failure_message("a fresh release kept an old hold").is_equal(0)
