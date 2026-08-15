# Regression coverage for #79: Waterwalk must cost the same as any other terrain step, not
# bypass move_cost along with impassability. Needs the REAL TestTiles.tres-backed board (via
# BoardBuilder) since RulesService.movement_cost reads tile custom data straight off the grid —
# the grid-free node fixtures (squad_fixtures.gd) can't exercise it (no TileSet -> every cell
# reads null tile data, see test_rules_service.gd's header). Scout's ability_pool is forced to
# just WATERWALK for the duration, mirroring test_ability_chassis_live_kit.gd, so this stays
# correct regardless of Scout's real authored kit.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const F := preload("res://tests/support/job_fixtures.gd")
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

var _scout: JobData
var _scout_snap: Dictionary

func before_test() -> void:
	_scout = JobCatalog.get_job("scout")
	_scout_snap = F.snapshot(_scout)
	var ability := AbilityData.new()
	ability.id = Abilities.Id.WATERWALK
	_scout.ability_pool = [ability]

func after_test() -> void:
	F.restore(_scout, _scout_snap)

func _board() -> Dictionary:
	var board := BoardBuilder.build(self)
	auto_free(board.root)
	BoardBuilder.paint_rect(board.grid, Rect2i(0, 0, 12, 1))
	return board

func _spawn(board: Dictionary, cell: Vector2i, waterwalking: bool) -> Unit:
	var data := H.make_unit_data({}, PLAYER)
	var unit := BoardBuilder.spawn(board, data, cell)
	if waterwalking:
		unit.unit_instance.add_job("scout")
	return unit

func _rules_board(board: Dictionary, unit: Unit) -> BoardContext:
	var units: Array[Unit] = [unit]
	return BoardContext.new(board.grid, units, board.squad_manager)

func test_water_is_impassable_without_waterwalk() -> void:
	var board := _board()
	BoardBuilder.paint_cell(board.grid, Vector2i(1, 0), BoardBuilder.WATER_ATLAS)
	var unit := _spawn(board, Vector2i(0, 0), false)

	var cost := RulesService.movement_cost(Vector2i(0, 0), Vector2i(1, 0),unit, _rules_board(board, unit))

	assert_int(cost).is_equal(RulesService.CANNOT_WALK_TILE)

func test_waterwalk_water_step_costs_the_same_as_any_other_tile() -> void:
	var board := _board()
	BoardBuilder.paint_cell(board.grid, Vector2i(1, 0), BoardBuilder.WATER_ATLAS)
	var unit := _spawn(board, Vector2i(0, 0), true)

	var cost := RulesService.movement_cost(Vector2i(0, 0), Vector2i(1, 0),unit, _rules_board(board, unit))

	assert_int(cost).is_equal(1)

func test_can_traverse_is_the_per_unit_terrain_answer() -> void:
	# #115 gave the unit-level question ONE home. BoardContext.is_walkable answers the cell-only
	# form ("may a unit stand here", #109); can_traverse is the per-unit layer on top, and both
	# movement_cost and path_hops now read it instead of each deciding separately.
	var board := _board()
	BoardBuilder.paint_cell(board.grid, Vector2i(1, 0), BoardBuilder.WATER_ATLAS)
	var plain := _spawn(board, Vector2i(0, 0), false)
	var walker := _spawn(board, Vector2i(3, 0), true)
	var context := _rules_board(board, plain)

	assert_bool(context.is_walkable(Vector2i(1, 0))).is_false()          # the cell says no
	assert_bool(RulesService.can_traverse(Vector2i(1, 0), plain, context)).is_false()
	assert_bool(RulesService.can_traverse(Vector2i(1, 0), walker, context)).is_true()
	# Ordinary ground is unaffected either way.
	assert_bool(RulesService.can_traverse(Vector2i(2, 0), plain, context)).is_true()


func test_can_traverse_ignores_occupancy() -> void:
	# Deliberate split: an enemy body blocks a MOVE (movement_cost adds that) but is not a terrain
	# fact, so the connectivity field must still see through it. Pinned so the two don't get merged.
	var board := _board()
	var mover := _spawn(board, Vector2i(0, 0), false)
	var blocker := BoardBuilder.spawn(board, H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(1, 0))
	var units: Array[Unit] = [mover, blocker]
	var context := BoardContext.new(board.grid, units, board.squad_manager)

	assert_bool(RulesService.can_traverse(Vector2i(1, 0), mover, context)).is_true()
	assert_int(RulesService.movement_cost(Vector2i(0, 0), Vector2i(1, 0),mover, context)).is_equal(RulesService.CANNOT_WALK_TILE)


func test_active_enemy_still_blocks_movement() -> void:
	# #122: only the DOWNED half of the asymmetry changes. An active enemy occupant must keep
	# refusing traversal exactly as before.
	var board := _board()
	var mover := _spawn(board, Vector2i(0, 0), false)
	var blocker := BoardBuilder.spawn(board, H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(1, 0))
	var units: Array[Unit] = [mover, blocker]
	var context := BoardContext.new(board.grid, units, board.squad_manager)

	assert_int(RulesService.movement_cost(Vector2i(0, 0), Vector2i(1, 0),mover, context)).is_equal(RulesService.CANNOT_WALK_TILE)

func test_downed_enemy_is_traversable_but_not_reachable() -> void:
	# #122: a downed enemy body stops blocking a PATH through its cell (matching a downed ally
	# today), but compute_move_range's destination filter -- unchanged -- still refuses standing
	# on it. The second assertion is the one that matters: falsify by reverting the fix and the
	# first assertion should go red while this one stays green.
	var board := _board()
	var mover := _spawn(board, Vector2i(0, 0), false)
	var blocker := BoardBuilder.spawn(board, H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(1, 0))
	blocker.lifecycle_state = Unit.LifecycleState.DOWNED
	var units: Array[Unit] = [mover, blocker]
	var context := BoardContext.new(board.grid, units, board.squad_manager)

	assert_int(RulesService.movement_cost(Vector2i(0, 0), Vector2i(1, 0),mover, context)).is_less(RulesService.CANNOT_WALK_TILE)

	var result := RulesService.compute_move_range(mover, context)
	assert_bool(result.reachable.has(Vector2i(1, 0))).is_false()

func test_waterwalk_move_range_stays_within_mov_budget_across_water() -> void:
	var board := _board()
	for x in range(1, 10):
		BoardBuilder.paint_cell(board.grid, Vector2i(x, 0), BoardBuilder.WATER_ATLAS)
	var unit := _spawn(board, Vector2i(0, 0), true)
	var mov := unit.get_mov()

	var result := RulesService.compute_move_range(unit, _rules_board(board, unit))

	assert_bool(result.reachable.has(Vector2i(mov, 0))).is_true()
	assert_bool(result.reachable.has(Vector2i(mov + 1, 0))).is_false()
