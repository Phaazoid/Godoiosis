# #50 ice slice: ICE on a WATER tile freezes it (a walkable FROZEN state over non-walkable water);
# FIRE on a FROZEN tile reverts it; FROZEN melts after STATE_DURATIONS ticks. Headless model.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const PLAYER := Team.Faction.PLAYER
const WATER_CELL := Vector2i(1, 0)

# Kinds authored directly (no TileSet headlessly); carries the live state store so the resolver's
# required_tile_state gate and is_walkable override have something to read.
class _IceBoard extends BoardContext:
	var kinds: Dictionary
	func _init(states: TerrainStateManager, k: Dictionary) -> void:
		var no_units: Array[Unit] = []
		super(null, no_units, null, states)
		kinds = k
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return kinds.get(cell, Terrain.Kind.NONE)

func _map_attacker(element: Elemental.Element) -> Unit:
	var u: Unit = H.spawn_unit(self, PLAYER, Vector2i(0, 0))
	var weapon := u.get_equipped_weapon() as WeaponData
	weapon.elemental_damage_type = element
	weapon.targets = EquippableData.TargetMode.MAP
	return u

func _ice_freezes_water() -> TerrainReaction:
	var tr := TerrainReaction.new()
	tr.incoming_element = Elemental.Element.ICE
	tr.required_kind = Terrain.Kind.WATER
	tr.add_tile_states.assign([Terrain.TileState.FROZEN])
	return tr

func _fire_melts_ice() -> TerrainReaction:
	var tr := TerrainReaction.new()
	tr.incoming_element = Elemental.Element.FIRE
	tr.required_tile_state = Terrain.TileState.FROZEN
	tr.remove_tile_states.assign([Terrain.TileState.FROZEN])
	return tr

func _frozen_store() -> TerrainStateManager:
	var tsm: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(tsm)
	var freeze := ResolvedCellEffect.new()
	freeze.cell = WATER_CELL
	freeze.states_added.assign([Terrain.TileState.FROZEN])
	tsm.apply(freeze)
	return tsm

func _resolve(attacker: Unit, cell: Vector2i, reactions: Array[TerrainReaction], board: _IceBoard) -> ResolvedPlan:
	var plan := ResolvedPlan.new()
	plan.attacks.append(AttackAction.create(attacker, attacker.movement.cell, null, cell))
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions, board, reactions)
	return plan

func test_ice_on_water_deposits_frozen() -> void:
	var attacker := _map_attacker(Elemental.Element.ICE)
	var reactions: Array[TerrainReaction] = [_ice_freezes_water()]
	var board := _IceBoard.new(null, { WATER_CELL: Terrain.Kind.WATER })
	var plan := _resolve(attacker, WATER_CELL, reactions, board)
	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_bool(plan.cell_effects[0].states_added.has(Terrain.TileState.FROZEN)).is_true()

func test_fire_on_a_frozen_tile_reverts_it() -> void:
	var attacker := _map_attacker(Elemental.Element.FIRE)
	var reactions: Array[TerrainReaction] = [_fire_melts_ice()]
	var board := _IceBoard.new(_frozen_store(), { WATER_CELL: Terrain.Kind.WATER })
	var plan := _resolve(attacker, WATER_CELL, reactions, board)
	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_bool(plan.cell_effects[0].states_removed.has(Terrain.TileState.FROZEN)).is_true()

func test_fire_on_unfrozen_water_does_nothing() -> void:
	# required_tile_state FROZEN unmet (no live state) -> reaction skipped.
	var attacker := _map_attacker(Elemental.Element.FIRE)
	var reactions: Array[TerrainReaction] = [_fire_melts_ice()]
	var board := _IceBoard.new(null, { WATER_CELL: Terrain.Kind.WATER })
	var plan := _resolve(attacker, WATER_CELL, reactions, board)
	assert_int(plan.cell_effects.size()).is_equal(0)

func test_frozen_tile_is_walkable() -> void:
	# A bare grid (no TileSet): every cell reads null tile data -> not walkable, except where the
	# FROZEN override short-circuits true. Proves ice makes non-walkable water walkable.
	var grid: TileMapLayer = auto_free(TileMapLayer.new())
	add_child(grid)
	var no_units: Array[Unit] = []
	var board := BoardContext.new(grid, no_units, null, _frozen_store())
	assert_bool(board.is_walkable(WATER_CELL)).is_true()
	assert_bool(board.is_walkable(Vector2i(9, 9))).is_false()

func test_frozen_melts_after_three_ticks() -> void:
	var tsm := _frozen_store()
	tsm.tick_states()
	tsm.tick_states()
	assert_bool(tsm.has_state(WATER_CELL, Terrain.TileState.FROZEN)).is_true()
	tsm.tick_states()
	assert_bool(tsm.has_state(WATER_CELL, Terrain.TileState.FROZEN)).is_false()
