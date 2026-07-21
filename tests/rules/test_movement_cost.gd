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

	var cost := RulesService.movement_cost(Vector2i(1, 0), unit, _rules_board(board, unit))

	assert_int(cost).is_equal(RulesService.CANNOT_WALK_TILE)

func test_waterwalk_water_step_costs_the_same_as_any_other_tile() -> void:
	var board := _board()
	BoardBuilder.paint_cell(board.grid, Vector2i(1, 0), BoardBuilder.WATER_ATLAS)
	var unit := _spawn(board, Vector2i(0, 0), true)

	var cost := RulesService.movement_cost(Vector2i(1, 0), unit, _rules_board(board, unit))

	assert_int(cost).is_equal(1)

func test_waterwalk_move_range_stays_within_mov_budget_across_water() -> void:
	var board := _board()
	for x in range(1, 10):
		BoardBuilder.paint_cell(board.grid, Vector2i(x, 0), BoardBuilder.WATER_ATLAS)
	var unit := _spawn(board, Vector2i(0, 0), true)
	var mov := unit.get_mov()

	var result := RulesService.compute_move_range(unit, _rules_board(board, unit))

	assert_bool(result.reachable.has(Vector2i(mov, 0))).is_true()
	assert_bool(result.reachable.has(Vector2i(mov + 1, 0))).is_false()
