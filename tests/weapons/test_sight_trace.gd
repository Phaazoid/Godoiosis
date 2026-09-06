# The sight trace (#258): one trajectory function is both the LoS rule and the bead readout
# ("if the bead can find the target, the shot is valid" -- dev, 2026-08-20). Fixtures are
# hand-painted in the shape of the two bug-report boards (a ramp-less wall column between two
# ground units), never loaded content.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

const NO_UNITS: Array[Unit] = []


func _board_with(heights: BoardHeights) -> BoardContext:
	return BoardContext.new(null, NO_UNITS, null, null, null, heights)


# One wall cell at (1,0), everything else flat -- the report shape in miniature.
func _wall_board(height: int) -> BoardContext:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), height)
	return _board_with(heights)


func _shot(clearance: int, max_range: int = 3) -> AttackData:
	var attack := AttackData.new()
	attack.arc_clearance = clearance
	P.point(attack, max_range, 1)
	return attack


# The Noemie report: a flat shot (clearance 0) at a same-level target dies on the wall between.
func test_a_flat_shot_dies_on_a_wall() -> void:
	var trace := Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(2, 0), _wall_board(6))
	assert_bool(trace.blocked).is_true()
	assert_bool(trace.blocked_cell == Vector2i(1, 0)).is_true()
	assert_bool(Reach.vertical_aim_ok(_shot(0), Vector2i(0, 0), Vector2i(2, 0), _wall_board(6))).is_false()


# The Isaac report: a one-level lob arcs to eye + a level mid-flight -- a two-level wall stops it,
# a one-level wall does not. Heights and clearance are both in units (#427), so all four numbers
# doubled together and the geometry is unchanged.
func test_a_lob_clears_low_walls_and_dies_on_high_ones() -> void:
	assert_bool(Reach.sight_trace(_shot(4), Vector2i(0, 0), Vector2i(2, 0), _wall_board(8)).blocked).is_true()
	assert_bool(Reach.sight_trace(_shot(4), Vector2i(0, 0), Vector2i(2, 0), _wall_board(4)).blocked).is_false()


# Touch = blocked: a bead grazing a wall-top stops, so even a 1-high wall stops a flat shot
# (the dev's standing "1-block-tall blocks line of sight").
func test_a_one_high_wall_blocks_a_flat_shot() -> void:
	assert_bool(Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(2, 0), _wall_board(2)).blocked).is_true()


# The original slice-2 point survives: a gun up a ramp staircase hugs the rising line from below.
func test_a_flat_shot_up_a_ramp_staircase_is_clear() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), 0, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(2, 0), 2, Terrain.RampRise.EAST)
	heights.set_cell(Vector2i(3, 0), 4)
	var board := _board_with(heights)
	assert_bool(Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(3, 0), board).blocked).is_false()


# The eye offset (#218, now the sprite's CENTER -- dev, 2026-08-20): standing ON your cliff edge,
# the shot down clears, because the sightline starts half a level above your feet. One cell back,
# your own lip occludes the steep shot -- real lip occlusion; step forward to take it.
func test_shooting_down_from_the_lip_clears_and_one_back_is_occluded() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(0, 0), 4)   # the shooter stands ON the edge
	var board := _board_with(heights)
	assert_bool(Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(3, 0), board).blocked).is_false()

	heights.set_cell(Vector2i(1, 0), 4)   # now the edge is one cell ahead -- the lip occludes
	assert_bool(Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(3, 0), board).blocked).is_true()


# The sightline originates at the sprite's CENTER (dev): the trace's first point sits exactly half
# a level above the shooter's surface, at the cell's center. Pins EYE_HEIGHT through the READOUT --
# the drawn path is the rule, so this is the one number a player could measure off the screen.
func test_the_line_starts_at_the_sprites_center() -> void:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(0, 0), 4)
	var trace := Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(2, 0), _board_with(heights))
	var first: Vector3 = trace.points[0]
	# Height 4 plus EYE_HEIGHT (1 unit = half a level), in the trace's own unit.
	assert_float(first.y).is_equal_approx(5.0, 0.0001)
	assert_float(first.x).is_equal_approx(0.5, 0.0001)


# The rule IS the readout: wherever horizontal membership holds, can_hit_cell_from and the trace
# verdict must agree (the attack's tolerances are unlimited, so the trace is the only vertical
# clause in play).
func test_the_gate_and_the_trace_never_disagree() -> void:
	for wall_height in [0, 2, 4, 6, 8]:
		var board := _wall_board(wall_height)
		var shot := _shot(4)
		var hit: bool = Reach.can_hit_cell_from(null, Vector2i(0, 0), Vector2i(2, 0), shot, board)
		var clear: bool = not Reach.sight_trace(shot, Vector2i(0, 0), Vector2i(2, 0), board).blocked
		assert_bool(hit == clear) \
			.override_failure_message("gate and trace disagree at wall height %d" % wall_height) \
			.is_true()


# A blocked trace truncates its beads at the wall instead of drawing through it.
func test_a_blocked_trace_stops_at_the_wall() -> void:
	var trace := Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(3, 0), _wall_board(3))
	assert_bool(trace.blocked).is_true()
	assert_int(trace.points.size()).is_greater(1)
	var last: Vector3 = trace.points[trace.points.size() - 1]
	assert_bool(last.x <= 2.0).is_true()   # never past the wall cell's far edge (wall spans x 1..2)


# --- cells_crossed: the deterministic supercover walk the trace rides ---------------------------

func test_cells_crossed_walks_a_straight_line_endpoints_excluded() -> void:
	var expected: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
	assert_that(GridUtils.cells_crossed(Vector2i(0, 0), Vector2i(3, 0))).is_equal(expected)


func test_cells_crossed_includes_both_cells_of_a_corner() -> void:
	# A one-step diagonal passes exactly through the shared corner: conservative supercover takes
	# BOTH side cells, so a shot can never thread a seam between two walls.
	var crossed := GridUtils.cells_crossed(Vector2i(0, 0), Vector2i(1, 1))
	assert_that(crossed).contains_exactly_in_any_order([Vector2i(1, 0), Vector2i(0, 1)])


func test_cells_crossed_of_an_oblique_line() -> void:
	var expected: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1)]
	assert_that(GridUtils.cells_crossed(Vector2i(0, 0), Vector2i(2, 1))).is_equal(expected)


# --- props block the line too (#660) ------------------------------------------------------------
#
# The bug this closes: a wall is a painted TILE, not geometry, so its cell's elevation is whatever
# ground it stands on -- 0 on a flat board. The trace read BoardHeights alone, and every shot in the
# game passed through every wall, at every angle.
#
# These stub the tile-authored column the way the terrain suites stub terrain_kind_at, so the
# ARITHMETIC is pinned without pinning authored content. The real-tileset pair at the bottom is what
# pins the WIRE -- a stub board cannot see GridUtils or BoardContext at all.
class _PropBoard extends BoardContext:
	const NO_UNITS: Array[Unit] = []
	var _props: Dictionary

	func _init(heights_store: BoardHeights, props: Dictionary) -> void:
		super(null, NO_UNITS, null, null, null, heights_store)
		_props = props

	func prop_rule_height_at(cell: Vector2i) -> int:
		var height: int = _props.get(cell, 0)
		return height


# One cell at (1,0) carrying a prop of the given height, standing on ground of the given height.
func _prop_board(prop_height: int, ground: int = 0) -> BoardContext:
	var heights := BoardHeights.new()
	heights.set_cell(Vector2i(1, 0), ground)
	return _PropBoard.new(heights, {Vector2i(1, 0): prop_height})


func test_a_painted_wall_stops_a_flat_shot() -> void:
	# THE BUG. Flat ground under a wall: elevation_at reads 0, so the old trace sailed over it at
	# EYE_HEIGHT with room to spare. One block of prop is enough -- touch = blocked.
	var board := _prop_board(Terrain.UNITS_PER_LEVEL)
	var trace := Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(2, 0), board)
	assert_bool(trace.blocked).is_true()
	assert_bool(trace.blocked_cell == Vector2i(1, 0)).is_true()
	assert_bool(Reach.vertical_aim_ok(_shot(0), Vector2i(0, 0), Vector2i(2, 0), board)).is_false()


func test_a_prop_stacks_on_the_ground_under_it() -> void:
	# A prop is a column ON the surface, not a reading of it: two units of ground plus two of wall
	# stops a lob that clears either half alone. Both controls are named because a trace that took
	# the LARGER of the two rather than the SUM would pass the third assert and fail the game.
	var over_ground := Reach.sight_trace(_shot(3), Vector2i(0, 0), Vector2i(2, 0), _prop_board(0, 2))
	var over_prop := Reach.sight_trace(_shot(3), Vector2i(0, 0), Vector2i(2, 0), _prop_board(2, 0))
	var over_both := Reach.sight_trace(_shot(3), Vector2i(0, 0), Vector2i(2, 0), _prop_board(2, 2))
	assert_bool(over_ground.blocked).override_failure_message(
		"ground alone should not stop this lob").is_false()
	assert_bool(over_prop.blocked).override_failure_message(
		"prop alone should not stop this lob").is_false()
	assert_bool(over_both.blocked).override_failure_message(
		"ground + prop did not add up").is_true()


func test_a_lob_clears_a_fence_and_dies_on_a_curtain_wall() -> void:
	# What the rules-height answer buys that an opaque-wall answer could not (the #660 A/B fork):
	# arc_clearance keeps its job over a PROP, not just over terrain. The gun is the control -- a
	# fence a lob clears is still not transparent.
	var fence := _prop_board(1)
	var wall := _prop_board(6)
	assert_bool(Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(2, 0), fence).blocked) \
		.override_failure_message("a gun should die on a fence").is_true()
	assert_bool(Reach.sight_trace(_shot(2), Vector2i(0, 0), Vector2i(2, 0), fence).blocked) \
		.override_failure_message("a lob should clear a fence").is_false()
	assert_bool(Reach.sight_trace(_shot(2), Vector2i(0, 0), Vector2i(2, 0), wall).blocked) \
		.override_failure_message("the same lob should die on a curtain wall").is_true()


func test_the_red_overlay_paints_the_cell_behind_a_wall() -> void:
	# The preview derives from the same gate, so it can no longer tell the player a through-the-wall
	# shot is legal. The open direction is the control: this must be a WALL verdict, not a blanket
	# one.
	var blocked := Reach.blocked_cells_from(null, Vector2i(0, 0), _shot(0),
		_prop_board(Terrain.UNITS_PER_LEVEL))
	assert_bool(blocked.has(Vector2i(2, 0))).override_failure_message(
		"the cell behind the wall still previews as legal").is_true()
	assert_bool(blocked.has(Vector2i(0, 2))).override_failure_message(
		"an open direction was painted blocked").is_false()


# --- the wire: GridUtils -> BoardContext -> the trace, against the REAL tileset ------------------
#
# Everything above stubs prop_rule_height_at, so all of it stays green with the reader and the
# read-point deleted -- which is precisely the bug that shipped. These paint a real tile and let the
# real readers answer. Tiles are found BY SHAPE, never by name: authored content is not pinnable.

const TILES: TileSet = preload("res://Resources/TestTiles.tres")


func _tile_of_shape(shape: GridUtils.PropShape) -> Vector2i:
	var source := TILES.get_source(0) as TileSetAtlasSource
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		if source.get_tile_size_in_atlas(coords) != Vector2i.ONE:
			continue
		if GridUtils.prop_shape_of(source.get_tile_data(coords, 0)) == shape:
			return coords
	return Vector2i(-1, -1)


func _board_painted_with(shape: GridUtils.PropShape) -> BoardContext:
	var coords := _tile_of_shape(shape)
	assert_bool(coords != Vector2i(-1, -1)).override_failure_message(
		"fixture: the tileset declares no %s tile, so this case checks nothing"
		% GridUtils.PropShape.keys()[shape]).is_true()
	var layer := auto_free(TileMapLayer.new()) as TileMapLayer
	layer.tile_set = TILES
	layer.set_cell(Vector2i(1, 0), 0, coords)
	return BoardContext.new(layer, NO_UNITS, null)


func test_a_real_painted_wall_blocks_a_real_shot() -> void:
	# THE WIRE. Nothing is stubbed: the tile's shape resolves its default through GridUtils,
	# BoardContext reads it off the grid, and the trace stacks it on the surface. Drop any one of
	# those three and every stubbed case above still passes while walls go back to transparent.
	var board := _board_painted_with(GridUtils.PropShape.PLANE)
	assert_bool(Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(2, 0), board).blocked).is_true()


func test_a_real_painted_tuft_blocks_nothing() -> void:
	# The control, and the narrowing: a TUFT stands up (its plants are billboards) but IS ground, so
	# it reads 0 and a flowerbed does not stop a carbine. Without this, the case above would pass
	# just as well against "any painted cell blocks".
	var board := _board_painted_with(GridUtils.PropShape.TUFT)
	assert_bool(Reach.sight_trace(_shot(0), Vector2i(0, 0), Vector2i(2, 0), board).blocked).is_false()


func test_a_solid_prop_stands_one_block_unauthored() -> void:
	# The dev's standing "1 block tall blocks line of sight", shipped as the shape DEFAULT rather
	# than as nineteen authored copies of one number. Asserted in the UNIT, never as a literal, so
	# the two cannot drift apart -- and the first assert guards the premise the second rests on.
	var data := (TILES.get_source(0) as TileSetAtlasSource).get_tile_data(
		_tile_of_shape(GridUtils.PropShape.PLANE), 0)
	assert_int(GridUtils.prop_int_override_of(data, "prop_rule_height")).override_failure_message(
		"fixture: this tile now AUTHORS a rules height, so this no longer tests the default"
		).is_equal(0)
	assert_int(GridUtils.prop_rule_height_of(data)).is_equal(Terrain.UNITS_PER_LEVEL)


func test_a_board_with_no_grid_stands_nothing_up() -> void:
	# The fixture contract every case above the props section leans on: a grid-less BoardContext
	# reads flat AND propless, so adding this column changed no existing board in the suite.
	assert_int(BoardContext.new(null, NO_UNITS, null).prop_rule_height_at(Vector2i(1, 0))).is_equal(0)
