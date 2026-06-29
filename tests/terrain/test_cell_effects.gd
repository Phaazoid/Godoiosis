# #50 slice 1: the cell-effect channel + terrain reactions + the tile-state store, headless.
# Proves the MODEL end to end with no execution or visuals: a FIRE attack flagged to hit the
# map deposits a ResolvedCellEffect onto its target cell, a reaction turns "FIRE on a TREE"
# into BURNING, and TerrainStateManager records/clears it. The terrain-kind read goes through
# a BoardContext stub -- the fixture grid is a bare TileMapLayer with no TileSet to paint.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const TREE_CELL := Vector2i(1, 0)
const GRASS_CELL := Vector2i(2, 0)

# A BoardContext whose terrain kinds are authored directly (no TileSet to paint headlessly).
class _StubBoard extends BoardContext:
	var kinds: Dictionary
	func _init(g: TileMapLayer, u: Array[Unit], m: SquadManager, k: Dictionary) -> void:
		super(g, u, m)
		kinds = k
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return kinds.get(cell, Terrain.Kind.NONE)

func _fire_attacker(mode: EquippableData.TargetMode) -> Unit:
	var u: Unit = H.spawn_unit(self, PLAYER, Vector2i(0, 0))
	(u.get_equipped_weapon() as WeaponData).elemental_damage_type = Elemental.Element.FIRE
	(u.get_equipped_weapon() as WeaponData).targets = mode
	return u

func _fire_burns_tree() -> TerrainReaction:
	var tr: TerrainReaction = TerrainReaction.new()
	tr.incoming_element = Elemental.Element.FIRE
	tr.required_kind = Terrain.Kind.TREE
	tr.add_tile_states.assign([Terrain.TileState.BURNING])
	return tr

func _resolve_cell_attack(attacker: Unit, cell: Vector2i, reactions: Array[TerrainReaction]) -> ResolvedPlan:
	var plan: ResolvedPlan = ResolvedPlan.new()
	plan.attacks.append(AttackAction.create(attacker, attacker.movement.cell, null, cell))
	var no_reactions: Array[ElementalReaction] = []
	var no_units: Array[Unit] = []
	var board: _StubBoard = _StubBoard.new(null, no_units, null, { TREE_CELL: Terrain.Kind.TREE })
	PlanResolver.resolve(plan, no_reactions, board, reactions)
	return plan

# --- the channel + the kind gate ---

func test_fire_on_a_tree_deposits_burning() -> void:
	var attacker: Unit = _fire_attacker(EquippableData.TargetMode.MAP)
	var reactions: Array[TerrainReaction] = [_fire_burns_tree()]
	var plan: ResolvedPlan = _resolve_cell_attack(attacker, TREE_CELL, reactions)
	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_bool(plan.cell_effects[0].cell == TREE_CELL).is_true()
	assert_bool(plan.cell_effects[0].states_added.has(Terrain.TileState.BURNING)).is_true()

func test_fire_on_bare_grass_deposits_nothing() -> void:
	# GRASS_CELL isn't in the stub's kind map -> Kind.NONE -> required_kind TREE unmet.
	var attacker: Unit = _fire_attacker(EquippableData.TargetMode.MAP)
	var reactions: Array[TerrainReaction] = [_fire_burns_tree()]
	var plan: ResolvedPlan = _resolve_cell_attack(attacker, GRASS_CELL, reactions)
	assert_int(plan.cell_effects.size()).is_equal(0)

# --- the per-attack toggle (default UNIT never touches the map) ---

func test_unit_only_attack_never_touches_the_map() -> void:
	var attacker: Unit = _fire_attacker(EquippableData.TargetMode.UNIT)
	var reactions: Array[TerrainReaction] = [_fire_burns_tree()]
	var plan: ResolvedPlan = _resolve_cell_attack(attacker, TREE_CELL, reactions)
	assert_int(plan.cell_effects.size()).is_equal(0)

# --- the tile-state store ---

func test_state_manager_records_then_clears_a_state() -> void:
	var tsm: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(tsm)

	var ignite: ResolvedCellEffect = ResolvedCellEffect.new()
	ignite.cell = TREE_CELL
	ignite.states_added.assign([Terrain.TileState.BURNING])
	tsm.apply(ignite)
	assert_bool(tsm.has_state(TREE_CELL, Terrain.TileState.BURNING)).is_true()

	var douse: ResolvedCellEffect = ResolvedCellEffect.new()
	douse.cell = TREE_CELL
	douse.states_removed.assign([Terrain.TileState.BURNING])
	tsm.apply(douse)
	assert_bool(tsm.has_state(TREE_CELL, Terrain.TileState.BURNING)).is_false()
