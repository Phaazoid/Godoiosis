# #50 cell-effect channel + terrain reactions + the tile-state store, headless.
# Proves the MODEL end to end with no execution or visuals: a map-hitting attack deposits a
# ResolvedCellEffect across its blast FOOTPRINT, a reaction turns "FIRE on a TREE" into BURNING,
# and TerrainStateManager records/clears it. AoE parity (the deposit covers every footprint cell,
# once per aim) is exercised alongside the single-cell case. The terrain-kind read goes through a
# BoardContext stub -- the fixture grid is a bare TileMapLayer with no TileSet to paint.
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
	var weapon := u.get_equipped_weapon() as WeaponInstance
	weapon.template.main_attack.elemental_damage_type = Elemental.Element.FIRE
	weapon.template.main_attack.targets = mode
	return u

# A FIRE attacker with a ForwardLine[length] pattern -> a multi-cell blast footprint, so the
# AoE-parity tests can put trees at several cells the one aim covers.
func _fire_line_attacker(mode: EquippableData.TargetMode, length: int) -> Unit:
	var u: Unit = _fire_attacker(mode)
	var line := ForwardLinePattern.new()
	line.length = length
	(u.get_equipped_weapon() as WeaponInstance).template.main_attack.attack_pattern = line
	return u

func _fire_burns_tree() -> TerrainReaction:
	var tr: TerrainReaction = TerrainReaction.new()
	tr.incoming_element = Elemental.Element.FIRE
	tr.required_kind = Terrain.Kind.TREE
	tr.add_tile_states.assign([Terrain.TileState.BURNING])
	return tr

func _resolve(plan: ResolvedPlan, reactions: Array[TerrainReaction], kinds: Dictionary) -> ResolvedPlan:
	var no_reactions: Array[ElementalReaction] = []
	var no_units: Array[Unit] = []
	var board: _StubBoard = _StubBoard.new(null, no_units, null, kinds)
	PlanResolver.resolve(plan, no_reactions, board, reactions)
	return plan

func _resolve_cell_attack(attacker: Unit, aim_cell: Vector2i, reactions: Array[TerrainReaction], kinds: Dictionary = { TREE_CELL: Terrain.Kind.TREE }) -> ResolvedPlan:
	var plan: ResolvedPlan = ResolvedPlan.new()
	plan.attacks.append(AttackAction.create(attacker, attacker.movement.cell, null, aim_cell))
	return _resolve(plan, reactions, kinds)

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

# --- AoE parity: the deposit covers the WHOLE blast footprint, once per aim ---

func test_aoe_ignites_every_tree_in_its_footprint() -> void:
	# ForwardLine[3] from (0,0) aimed RIGHT -> footprint (1,0),(2,0),(3,0). Trees at (1,0)+(2,0)
	# both ignite; bare (3,0) does not. (The old per-attack stage lit only the single aimed cell.)
	var attacker: Unit = _fire_line_attacker(EquippableData.TargetMode.MAP, 3)
	var reactions: Array[TerrainReaction] = [_fire_burns_tree()]
	var kinds := { Vector2i(1, 0): Terrain.Kind.TREE, Vector2i(2, 0): Terrain.Kind.TREE }
	var plan: ResolvedPlan = _resolve_cell_attack(attacker, Vector2i(1, 0), reactions, kinds)
	assert_int(plan.cell_effects.size()).is_equal(2)
	var cells: Array[Vector2i] = []
	for effect in plan.cell_effects:
		cells.append(effect.cell)
	assert_bool(cells.has(Vector2i(1, 0))).is_true()
	assert_bool(cells.has(Vector2i(2, 0))).is_true()
	assert_bool(cells.has(Vector2i(3, 0))).is_false()

func test_secondary_volley_member_skips_the_deposit() -> void:
	# Two attacks sharing one aim + footprint (a volley). The deposit runs once per aim: only the
	# lead member (is_secondary_hit false) deposits, the secondary is skipped -> each footprint cell
	# ignites once, never once-per-victim (the duplication this fixes). Target-less so it stays
	# grid/squad-free, like the rest of this suite; the gate is what's under test.
	var attacker: Unit = _fire_line_attacker(EquippableData.TargetMode.MAP, 3)
	var primary := AttackAction.create(attacker, attacker.movement.cell, null, Vector2i(1, 0))
	var secondary := AttackAction.create(attacker, attacker.movement.cell, null, Vector2i(1, 0))
	secondary.is_secondary_hit = true
	var plan: ResolvedPlan = ResolvedPlan.new()
	plan.attacks.append(primary)
	plan.attacks.append(secondary)
	var reactions: Array[TerrainReaction] = [_fire_burns_tree()]
	var kinds := { Vector2i(1, 0): Terrain.Kind.TREE, Vector2i(2, 0): Terrain.Kind.TREE }
	_resolve(plan, reactions, kinds)
	assert_int(plan.cell_effects.size()).is_equal(2)
	var burning_at_1 := 0
	for effect in plan.cell_effects:
		if effect.cell == Vector2i(1, 0):
			burning_at_1 += 1
	assert_int(burning_at_1).is_equal(1)

func test_counter_deposits_terrain_across_its_footprint() -> void:
	# A live, map-hitting counter ignites its own blast footprint too -- the same channel as an
	# attack (a fire counter should light trees). ForwardLine[2] from (0,0) -> (1,0),(2,0).
	var counter_unit: Unit = _fire_line_attacker(EquippableData.TargetMode.MAP, 2)
	var counter := CounterAttackAction.new()
	counter.init(counter_unit, counter_unit.movement.cell, null, Vector2i(1, 0))
	var plan: ResolvedPlan = ResolvedPlan.new()
	plan.counters.append(counter)
	var reactions: Array[TerrainReaction] = [_fire_burns_tree()]
	var kinds := { Vector2i(1, 0): Terrain.Kind.TREE, Vector2i(2, 0): Terrain.Kind.TREE }
	_resolve(plan, reactions, kinds)
	assert_int(plan.cell_effects.size()).is_equal(2)
	var cells: Array[Vector2i] = []
	for effect in plan.cell_effects:
		cells.append(effect.cell)
	assert_bool(cells.has(Vector2i(1, 0))).is_true()
	assert_bool(cells.has(Vector2i(2, 0))).is_true()

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
