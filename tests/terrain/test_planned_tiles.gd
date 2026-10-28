# PlannedTiles (#1498): where a pass leaves the tiles it touches, the cell half of the pass's
# hypothetical. Pure data over two bare stores -- no scene -- except the last case, which resolves a
# real plan to check every deposit landed on plan.tiles as it was appended.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const T := preload("res://tests/support/terrain_fixtures.gd")
const A := Vector2i(2, 3)
const B := Vector2i(-1, 4)
const BARE := Vector2i(9, 9)   # the groundless cell
const STEAM := Gas.Kind.STEAM
const SMOKE := Gas.Kind.SMOKE

var _terrain: TerrainStateManager
var _gas: GasField


func before_test() -> void:
	_terrain = _store()
	_gas = _field()


func _store() -> TerrainStateManager:
	var store: TerrainStateManager = auto_free(T.store_on_stone())
	store.ground_source = func(cell: Vector2i) -> bool: return cell != BARE
	return store


func _field() -> GasField:
	var field := GasField.new()
	field.ground_source = func(cell: Vector2i) -> bool: return cell != BARE
	return field


func _effect(cell: Vector2i, added: Array[Terrain.TileState] = [], removed: Array[Terrain.TileState] = [],
		gas: Dictionary = {}, clears := false) -> ResolvedCellEffect:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign(added)
	effect.states_removed.assign(removed)
	for kind: Gas.Kind in gas:
		effect.add_gas(kind, gas[kind])
	effect.gas_cleared = clears
	return effect


func _board(terrain: TerrainStateManager, gas: GasField) -> BoardContext:
	var no_units: Array[Unit] = []
	return BoardContext.new(null, no_units, null, terrain, null, null, gas)


func test_an_untouched_cell_reads_the_stores() -> void:
	_terrain.apply(_effect(A, [Terrain.TileState.COVER]))
	_gas.set_level(A, STEAM, Gas.Level.MEDIUM)
	var tiles := PlannedTiles.new(_terrain, _gas)
	tiles.land(_effect(B, [Terrain.TileState.FROZEN]))
	assert_array(tiles.states_at(A)).is_equal(_terrain.states_at(A))
	assert_bool(tiles.has_state(A, Terrain.TileState.COVER)).is_true()
	assert_int(tiles.gas_at(A)).is_equal(_gas.packed_at(A))
	assert_array(tiles.cells()).override_failure_message("a cell nothing landed on was recorded").contains_exactly([B])


func test_a_landing_copies_its_cell_and_writes_no_store() -> void:
	_terrain.apply(_effect(A, [Terrain.TileState.COVER]))
	_gas.set_level(A, SMOKE, Gas.Level.THIN)
	var terrain_version := _terrain.dirty.version
	var gas_version := _gas.dirty.version
	var tiles := PlannedTiles.new(_terrain, _gas)

	tiles.land(_effect(A, [Terrain.TileState.FROZEN], [Terrain.TileState.COVER], {STEAM: Gas.Level.THIN}))

	assert_bool(tiles.has_state(A, Terrain.TileState.FROZEN)).is_true()
	assert_bool(tiles.has_state(A, Terrain.TileState.COVER)).is_false()
	assert_int(Gas.level_in(tiles.gas_at(A), SMOKE)).override_failure_message(
			"the landing did not start from the store's gas").is_equal(Gas.Level.THIN)
	assert_array(_terrain.states_at(A)).override_failure_message("a landing wrote the terrain store") \
		.contains_exactly([Terrain.TileState.COVER])
	assert_int(Gas.level_in(_gas.packed_at(A), STEAM)).override_failure_message("a landing wrote the gas store").is_equal(0)
	assert_int(_terrain.dirty.version).is_equal(terrain_version)
	assert_int(_gas.dirty.version).is_equal(gas_version)


# The one rule: a sequence of landings reads, cell by cell, exactly as the same effects apply()'d to a
# twin of the stores -- add, remove, clear-then-add, the cap, and a groundless cell.
func test_a_sequence_of_landings_reads_as_apply_leaves_the_stores() -> void:
	var twin_terrain := _store()
	var twin_gas := _field()
	for pair in [[_terrain, _gas], [twin_terrain, twin_gas]]:
		(pair[0] as TerrainStateManager).apply(_effect(A, [Terrain.TileState.BURNING]))
		(pair[1] as GasField).set_level(A, SMOKE, Gas.Level.THICK)
		(pair[1] as GasField).set_level(B, STEAM, Gas.Level.MEDIUM)
	var effects: Array[ResolvedCellEffect] = [
		_effect(A, [Terrain.TileState.COVER], [Terrain.TileState.BURNING]),
		_effect(A, [], [], {STEAM: Gas.Level.THIN}, true),
		_effect(B, [Terrain.TileState.FROZEN], [], {STEAM: Gas.Level.THICK}),
		_effect(A, [Terrain.TileState.FROZEN], [Terrain.TileState.COVER], {STEAM: Gas.Level.MEDIUM}),
		_effect(BARE, [Terrain.TileState.FROZEN], [], {SMOKE: Gas.Level.THIN}),
	]
	var tiles := PlannedTiles.new(_terrain, _gas)
	for effect in effects:
		tiles.land(effect)
		twin_terrain.apply(effect)
		twin_gas.apply(effect)

	for cell: Vector2i in [A, B, BARE]:
		assert_array(tiles.states_at(cell)).override_failure_message(
				"the planned %s and the applied one disagree on tile states" % [cell]).is_equal(twin_terrain.states_at(cell))
		assert_int(tiles.gas_at(cell)).override_failure_message(
				"the planned %s and the applied one disagree on gas" % [cell]).is_equal(twin_gas.packed_at(cell))
	assert_int(Gas.level_in(tiles.gas_at(B), STEAM)).override_failure_message(
			"fixture: the cap was never reached").is_equal(Gas.MAX_LEVEL)


func test_after_leaves_the_board_it_was_handed_as_it_was() -> void:
	var board := _board(_terrain, _gas)
	var none: Array[ResolvedCellEffect] = []
	assert_object(PlannedTiles.after(board, none)).is_same(board)

	var freeze: Array[ResolvedCellEffect] = [_effect(A, [Terrain.TileState.FROZEN])]
	var after := PlannedTiles.after(board, freeze)
	assert_bool(after.has_tile_state(A, Terrain.TileState.FROZEN)).is_true()
	assert_bool(board.has_tile_state(A, Terrain.TileState.FROZEN)).override_failure_message(
			"the board after() was handed reads the change too").is_false()
	assert_object(board.tiles).is_null()


# A board already over planned tiles is built ON, never silently dropped -- and the tiles it carries
# are not written by the moment built over them.
func test_after_over_a_planned_board_builds_on_its_tiles() -> void:
	var tiles := PlannedTiles.new(_terrain, _gas)
	tiles.land(_effect(A, [Terrain.TileState.FROZEN]))
	var planned := _board(_terrain, _gas).planned(tiles)
	var smoke: Array[ResolvedCellEffect] = [_effect(B, [], [], {SMOKE: Gas.Level.THIN})]

	var after := PlannedTiles.after(planned, smoke)

	assert_bool(after.has_tile_state(A, Terrain.TileState.FROZEN)).override_failure_message(
			"after() dropped the tiles the board already carried").is_true()
	assert_int(Gas.level_in(after.gas_at(B), SMOKE)).is_equal(Gas.Level.THIN)
	assert_int(planned.gas_at(B)).override_failure_message("after() wrote the tiles it built on").is_equal(0)


# WHEN playback lands them (#1498 stage 2): a volley's deposits, whichever member laid each, once its LAST
# member has played (one blast is one moment) and in the order they were laid; a lone hit's and a
# Burrow's COVER once they have. Hand-built members, so no shape decides who leads.
func test_a_volley_lands_after_its_last_member_and_an_order_after_itself() -> void:
	var lead := AttackAction.new()
	var last := AttackAction.new()
	var volley: Array[AttackAction] = [lead, last]
	lead.volley = volley
	last.volley = volley
	var lone := AttackAction.new()
	var burrow := BurrowAction.new()
	var plan := ResolvedPlan.new()
	var board := _board(_terrain, _gas)
	var laid: Array[ResolvedCellEffect] = [
		_effect(A, [], [], {SMOKE: Gas.Level.THIN}),
		_effect(B, [], [], {STEAM: Gas.Level.THIN}),
		_effect(B, [], [], {}, true),
		_effect(A, [Terrain.TileState.COVER]),
	]
	var causes: Array[BaseAction] = [lead, last, lone, burrow]
	for i in laid.size():
		laid[i].cause = causes[i]
		plan.deposit(laid[i], board)

	assert_array(plan.landing_after(lead)).override_failure_message("a volley landed before its last member").is_empty()
	assert_array(plan.landing_after(last)).override_failure_message("the volley did not land whole, in the order laid") \
		.contains_exactly([laid[0], laid[1]])
	assert_array(plan.deposits_of(lead)).override_failure_message("a member answered for less than its volley") \
		.contains_exactly([laid[0], laid[1]])
	assert_array(plan.landing_after(lone)).contains_exactly([laid[2]])
	assert_array(plan.landing_after(burrow)).override_failure_message("a Burrow's COVER did not land with it") \
		.contains_exactly([laid[3]])

	assert_array(plan.play_landing(last, _terrain, _gas)).contains_exactly([laid[0], laid[1]])
	assert_int(Gas.level_in(_gas.packed_at(A), SMOKE)).override_failure_message("play_landing wrote no store") \
		.is_equal(Gas.Level.THIN)
	assert_int(Gas.level_in(_gas.packed_at(B), STEAM)).is_equal(Gas.Level.THIN)
	assert_bool(_terrain.has_state(A, Terrain.TileState.COVER)).override_failure_message(
			"play_landing landed a deposit that is not this volley's").is_false()
	volley.clear()   # the cycle a plan breaks as it frees (#1359); these members are in none of its lists


# An attacker at `at` whose every hit leaves `level` of `kind` on the cells it strikes
# (test_gas_deposits' aim: the struck cells stamped as the volley builder stamps them).
func _gasser(at: Vector2i, kind: Gas.Kind, level: Gas.Level, struck: Array[Vector2i]) -> AttackAction:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, at)
	var attack := (unit.get_equipped_weapon() as WeaponInstance).template.main_attack
	attack.targets = EquippableData.TargetMode.UNIT
	attack.gases = {kind: level}
	var aim := AttackAction.create(unit, at, null, struck[0])
	aim.fired_attack = unit.get_fired_attack()
	aim.struck_cells = struck
	return aim


# Every deposit a real pass makes lands on plan.tiles as it is appended (ResolvedPlan.deposit): two
# attacks laying gas on one shared cell, and the plan's tiles read as its own records landed afresh.
func test_a_resolved_plans_tiles_are_its_deposits_landed() -> void:
	_gas.set_level(B, STEAM, Gas.Level.THIN)
	var first: Array[Vector2i] = [A, B]
	var second: Array[Vector2i] = [B]
	var plan := ResolvedPlan.new()
	plan.attacks = [_gasser(Vector2i(0, 0), STEAM, Gas.Level.THIN, first),
			_gasser(Vector2i(0, 1), SMOKE, Gas.Level.MEDIUM, second)] as Array[AttackAction]
	var board := _board(_terrain, _gas)
	var no_reactions: Array[ElementalReaction] = []

	PlanResolver.resolve(plan, no_reactions, board, TerrainReactionCatalog.get_all())

	assert_int(plan.cell_effects.size()).override_failure_message(
			"fixture: the pass laid %d deposits, not one per struck cell" % plan.cell_effects.size()).is_equal(3)
	assert_object(plan.tiles).override_failure_message("a pass that deposited carries no planned tiles").is_not_null()
	if plan.tiles == null:
		return
	var relanded := PlannedTiles.after(board, plan.cell_effects)
	assert_array(plan.tiles.cells()).is_equal(relanded.tiles.cells())
	for cell: Vector2i in plan.tiles.cells():
		assert_array(plan.tiles.states_at(cell)).is_equal(relanded.tile_states_at(cell))
		assert_int(plan.tiles.gas_at(cell)).is_equal(relanded.gas_at(cell))
	assert_int(Gas.level_in(plan.tiles.gas_at(B), STEAM)).override_failure_message(
			"the planned cell did not start from the store's steam").is_equal(Gas.Level.MEDIUM)
	assert_int(Gas.level_in(_gas.packed_at(B), SMOKE)).override_failure_message("the resolve wrote the store").is_equal(0)
