# The water half of the fire/water terrain loop, tested against the AUTHORED catalog
# (TerrainReactionCatalog.get_all(), unlike test_ice.gd's injected twins): WATER puts out both
# fire states — BURNING and the permanent BLAZE, mirroring #199's ice symmetry (permanent states
# are removed by the opposing element, never a clock) — FIRE ignites GRASS, and DIRT is the
# non-flammable ground: no reaction keys on it, so fire deposits nothing there.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const PLAYER := Team.Faction.PLAYER
const TARGET_CELL := Vector2i(1, 0)

# test_ice.gd's board: kinds authored directly (no TileSet headlessly), carrying the live state
# store so required_tile_state has something to read.
class _KindBoard extends BoardContext:
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

func _store_with(state: Terrain.TileState) -> TerrainStateManager:
	var tsm: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(tsm)
	var seed_effect := ResolvedCellEffect.new()
	seed_effect.cell = TARGET_CELL
	seed_effect.states_added.assign([state])
	tsm.apply(seed_effect)
	return tsm

# Resolve one cell-targeted attack against the AUTHORED terrain catalog.
func _resolve(attacker: Unit, board: _KindBoard) -> ResolvedPlan:
	var plan := ResolvedPlan.new()
	var aim := AttackAction.create(attacker, attacker.movement.cell, null, TARGET_CELL)
	aim.fired_attack = attacker.get_fired_attack()
	plan.attacks.append(aim)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions, board, TerrainReactionCatalog.get_all())
	return plan

func test_water_douses_a_burning_tile() -> void:
	var attacker := _map_attacker(Elemental.Element.WATER)
	var board := _KindBoard.new(_store_with(Terrain.TileState.BURNING), { TARGET_CELL: Terrain.Kind.GRASS })
	var plan := _resolve(attacker, board)
	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_bool(plan.cell_effects[0].states_removed.has(Terrain.TileState.BURNING)).is_true()

func test_water_douses_a_blaze() -> void:
	# BLAZE has no timer — water is its ONLY exit, the way fire is FROZEN's (test_ice.gd).
	var attacker := _map_attacker(Elemental.Element.WATER)
	var board := _KindBoard.new(_store_with(Terrain.TileState.BLAZE), { TARGET_CELL: Terrain.Kind.GRASS })
	var plan := _resolve(attacker, board)
	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_bool(plan.cell_effects[0].states_removed.has(Terrain.TileState.BLAZE)).is_true()

func test_water_on_a_calm_tile_deposits_nothing() -> void:
	var attacker := _map_attacker(Elemental.Element.WATER)
	var board := _KindBoard.new(null, { TARGET_CELL: Terrain.Kind.GRASS })
	var plan := _resolve(attacker, board)
	assert_int(plan.cell_effects.size()).is_equal(0)

func test_fire_ignites_grass() -> void:
	var attacker := _map_attacker(Elemental.Element.FIRE)
	var board := _KindBoard.new(null, { TARGET_CELL: Terrain.Kind.GRASS })
	var plan := _resolve(attacker, board)
	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_bool(plan.cell_effects[0].states_added.has(Terrain.TileState.BURNING)).is_true()

func test_fire_on_dirt_deposits_nothing() -> void:
	# DIRT exists precisely so level authors have ground that cannot catch — by omission: no
	# authored reaction may key on it. This case pins the omission.
	var attacker := _map_attacker(Elemental.Element.FIRE)
	var board := _KindBoard.new(null, { TARGET_CELL: Terrain.Kind.DIRT })
	var plan := _resolve(attacker, board)
	assert_int(plan.cell_effects.size()).is_equal(0)
