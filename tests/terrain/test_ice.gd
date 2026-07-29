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
	var weapon := u.get_equipped_weapon() as WeaponInstance
	weapon.template.main_attack.elemental_damage_type = element
	weapon.template.main_attack.targets = EquippableData.TargetMode.MAP
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
	# Cell-targeted (no unit), but still STAMPED — since #102 an unstamped order means "no attack",
	# so it would deposit nothing. Production's declare() does exactly this.
	var aim := AttackAction.create(attacker, attacker.movement.cell, null, cell)
	aim.fired_attack = attacker.get_fired_attack()
	plan.attacks.append(aim)
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

func test_a_tileset_that_omits_the_walkable_flag_reads_unwalkable() -> void:
	# #109 picked is_walkable's missing-flag default and made it explicit: an undeclared `walkable`
	# layer means NOT walkable. Two of the four old hand-rolls said the opposite, so the fork was a
	# live contradiction rather than a decision. It also wasn't free: without the has_custom_data
	# guard this path raised TWO runtime errors per call (the engine's "TileSet has no layer with
	# name: walkable", then "Trying to return value of type Nil from a function whose return type
	# is bool") and only answered false as a Nil->bool coercion byproduct — once per neighbour per
	# frame inside the move-range BFS. Every tile in TestTiles.tres declares the flag, so a
	# synthetic tileset is the only way to reach the branch at all.
	var ts := TileSet.new()
	ts.add_custom_data_layer(0)
	ts.set_custom_data_layer_name(0, "move_cost")
	ts.set_custom_data_layer_type(0, TYPE_INT)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(Image.create(16, 16, false, Image.FORMAT_RGBA8))
	src.texture_region_size = Vector2i(16, 16)
	src.create_tile(Vector2i.ZERO)
	ts.add_source(src, 0)

	var grid: TileMapLayer = auto_free(TileMapLayer.new())
	grid.tile_set = ts
	add_child(grid)
	grid.set_cell(Vector2i.ZERO, 0, Vector2i.ZERO)

	var no_units: Array[Unit] = []
	var board := BoardContext.new(grid, no_units, null)
	assert_bool(board.is_walkable(Vector2i.ZERO)).is_false()

func test_frozen_melts_after_three_ticks() -> void:
	var tsm := _frozen_store()
	tsm.tick_states()
	tsm.tick_states()
	assert_bool(tsm.has_state(WATER_CELL, Terrain.TileState.FROZEN)).is_true()
	tsm.tick_states()
	assert_bool(tsm.has_state(WATER_CELL, Terrain.TileState.FROZEN)).is_false()
