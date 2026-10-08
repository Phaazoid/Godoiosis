# WEIGHT SLOWS MOVEMENT (#1176, dev 2026-10-01): MOV loses a tile per weight band -- the same bands
# shoves and falls read -- and the band is the TOTAL weight, body included. tests/stats/test_mov.gd
# pins the arithmetic on bare instances; this suite pins what only a real Unit has: the body and the
# load reaching it through get_weight, the move range that is the rule, and the loadout preview.
#
# Weights sit on the band THRESHOLDS and MOV is read against an unweighted twin, so retuning a
# threshold, the base or a DEX rung moves nothing asserted here.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER


func _ballast(weight: int) -> Item:
	var item := Item.new()
	item.display_name = "Ballast"
	item.weight = weight
	return item


# Loads a unit to exactly `weight` with one carried item.
func _weigh_to(unit: Unit, weight: int) -> void:
	var need := weight - unit.get_weight()
	assert_int(need).override_failure_message(
		"the unit already weighs more than the case needs").is_greater_equal(0)
	assert_bool(unit.add_item(_ballast(need))).is_true()
	assert_int(unit.get_weight()).is_equal(weight)


func _farthest(unit: Unit, sm: SquadManager) -> int:
	var board: BoardContext = sm.board_source.call()
	var reach: Dictionary = RulesService.compute_move_range(unit, board)
	var far := 0
	for cell: Vector2i in reach.reachable:
		far = maxi(far, absi(cell.x - unit.movement.cell.x) + absi(cell.y - unit.movement.cell.y))
	return far


# THE WIRE: the move range is the rule, so a weighted unit must reach one ring less on open ground
# -- not merely report a smaller number.
func test_a_heavy_load_shortens_the_move_range() -> void:
	var sm := H.make_manager(self)
	var unit := H.spawn_solo(self, sm, PLAYER, Vector2i.ZERO)
	var light := _farthest(unit, sm)
	assert_int(light).override_failure_message(
		"the open board did not let the unit walk at all, so the case measures nothing").is_greater(1)
	_weigh_to(unit, Stats.WEIGHT_BAND_1)
	assert_int(_farthest(unit, sm)).is_equal(light - 1)


# The ruling's own words: a heavy BODY is slow, not only a heavy load. BLD alone, nothing carried.
func test_the_body_alone_can_slow_a_unit() -> void:
	var sm := H.make_manager(self)
	var ordinary := H.spawn_solo(self, sm, PLAYER, Vector2i.ZERO, {}, false)
	var big := H.spawn_solo(self, sm, PLAYER, Vector2i(3, 0), {Stats.Stat.BLD: Stats.WEIGHT_BAND_1}, false)
	assert_int(big.get_carried_weight()).is_equal(0)
	assert_int(Stats.weight_band(ordinary.get_weight())).override_failure_message(
		"the default body is already heavy, so this control measures nothing").is_equal(0)
	assert_int(big.get_mov()).is_equal(ordinary.get_mov() - 1)


# The loadout preview: a piece coming IN adds its mass and previews the tile it costs, while equipping
# something already carried moves nothing (previewed_weight's fork, carried through).
func test_the_preview_counts_an_incoming_piece_and_ignores_one_already_carried() -> void:
	var sm := H.make_manager(self)
	var unit := H.spawn_solo(self, sm, PLAYER, Vector2i.ZERO, {}, false)
	var mov := unit.get_mov()
	var plate := _ballast(Stats.WEIGHT_BAND_1 - unit.get_weight())
	assert_int(unit.previewed_mov(plate, true)).is_equal(mov - 1)
	assert_int(unit.previewed_mov(plate, false)).is_equal(mov)
	assert_bool(unit.add_item(plate)).is_true()
	assert_int(unit.previewed_mov(plate, false)).override_failure_message(
		"equipping a piece already carried previewed a change in what the unit carries") \
		.is_equal(unit.get_mov())
