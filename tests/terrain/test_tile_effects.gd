# An attack's TILE EFFECT (#894): a tile state it LAYS whatever the ground would take of its element, on
# tiles of its own -- fire on stone is a fire wall. Three halves, one section each: what a pass deposits
# (PlanResolver), how long it lasts (the store), and where it lands (Conduction's Sweep.effect, stamped
# by AttackAction.stamp_sweep; Reach's own placement cases are in test_attack_geometry.gd).
#
# The deposit cases run against the AUTHORED reaction catalog, because the rulings are about how a laid
# fire meets the ground the game ships ("a regular fire", dev 2026-10-30) -- and they read no number
# off it. The clock cases use terrain_fixtures' own fuel, never the authored grass.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const T := preload("res://tests/support/terrain_fixtures.gd")
const PLAYER := Team.Faction.PLAYER
const BURNING := Terrain.TileState.BURNING
const FROZEN := Terrain.TileState.FROZEN
const SCORCHED := Terrain.TileState.SCORCHED

const CELL := Vector2i(1, 0)
# This suite's own life for a laid fire, kept apart from T.FUEL_TURNS so the two clocks can be told apart.
const LIFE := T.FUEL_TURNS + 2


class _KindBoard extends BoardContext:
	var kinds: Dictionary
	func _init(states: TerrainStateManager, k: Dictionary) -> void:
		var no_units: Array[Unit] = []
		super(null, no_units, null, states)
		kinds = k
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return kinds.get(cell, Terrain.Kind.NONE)


func _attacker(element: Elemental.Element, targets: EquippableData.TargetMode) -> Unit:
	var u: Unit = H.spawn_unit(self, PLAYER, Vector2i(0, 0))
	var attack := (u.get_equipped_weapon() as WeaponInstance).template.main_attack
	attack.elemental_damage_type = element
	attack.targets = targets
	return u


# `attacker`'s attack, laying fire for LIFE rounds.
func _laying(attacker: Unit) -> AttackData:
	var attack := attacker.get_fired_attack()
	attack.tile_effect = Elemental.Element.FIRE
	attack.tile_effect_turns = LIFE
	return attack


# An aim as a volley builder stamps it (stamp_sweep): the tiles it struck, and where its effect lands.
func _aim(attacker: Unit, struck: Array[Vector2i], effect: Array[Vector2i]) -> AttackAction:
	var aim := AttackAction.create(attacker, attacker.movement.cell, null, CELL)
	aim.fired_attack = attacker.get_fired_attack()
	aim.struck_cells = struck
	aim.effect_cells = effect
	return aim


func _resolve(aim: AttackAction, board: BoardContext) -> ResolvedPlan:
	var plan := ResolvedPlan.new()
	var attacks: Array[AttackAction] = [aim]
	plan.attacks = attacks
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions, board, TerrainReactionCatalog.get_all())
	return plan


# The plan's deposit on `cell`, or null.
func _effect_on(plan: ResolvedPlan, cell: Vector2i) -> ResolvedCellEffect:
	for effect in plan.cell_effects:
		if effect.cell == cell:
			return effect
	return null


func _lays_fire(plan: ResolvedPlan, cell: Vector2i) -> bool:
	var effect := _effect_on(plan, cell)
	return effect != null and effect.states_added.has(BURNING)


func _store_with(cell: Vector2i, state: Terrain.TileState) -> TerrainStateManager:
	var tsm: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(tsm)
	var seed_effect := ResolvedCellEffect.new()
	seed_effect.cell = cell
	seed_effect.states_added.assign([state])
	tsm.apply(seed_effect)
	return tsm


# --- what the pass deposits ----------------------------------------------------------------------

func test_fire_is_laid_on_ground_no_reaction_would_light() -> void:
	var stone := Vector2i(1, 0)
	var dirt := Vector2i(2, 0)
	var kinds := {stone: Terrain.Kind.ROCK, dirt: Terrain.Kind.DIRT}
	var cells: Array[Vector2i] = [stone, dirt]
	var attacker := _attacker(Elemental.Element.FIRE, EquippableData.TargetMode.BOTH)
	# The control first: the same fire hit with no tile effect leaves this ground alone, or the case
	# below would pass on the catalog's word rather than the attack's.
	var plain := _resolve(_aim(attacker, cells, cells), _KindBoard.new(null, kinds))
	for cell in cells:
		assert_bool(_lays_fire(plain, cell)).override_failure_message(
			"fixture: the catalog lit %s on its own -- pick ground no reaction burns" % [cell]).is_false()
	var attack := _laying(attacker)
	var plan := _resolve(_aim(attacker, cells, cells), _KindBoard.new(null, kinds))
	for cell in cells:
		assert_bool(_lays_fire(plan, cell)).override_failure_message("no fire laid on %s" % [cell]).is_true()
		var effect := _effect_on(plan, cell)
		if effect != null:
			assert_int(effect.state_turns.get(BURNING, -1)).override_failure_message(
				"the laid fire on %s did not carry the attack's life" % [cell]).is_equal(attack.tile_effect_turns)


func test_the_effect_lands_on_its_own_tiles_whatever_targets_says() -> void:
	# A unit-only, elementless attack: nothing else it does touches the map at all.
	var attacker := _attacker(Elemental.Element.NONE, EquippableData.TargetMode.UNIT)
	_laying(attacker)
	var struck: Array[Vector2i] = [CELL]
	var effect: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1)]
	var plan := _resolve(_aim(attacker, struck, effect), _KindBoard.new(null, {}))
	for cell in effect:
		assert_bool(_lays_fire(plan, cell)).override_failure_message("no fire laid on effect tile %s" % [cell]).is_true()
	assert_bool(_lays_fire(plan, CELL)).override_failure_message(
		"fire landed where the attack hit, off its effect tiles").is_false()


func test_laid_fire_fizzles_on_open_water() -> void:
	var water := Vector2i(1, 0)
	var dirt := Vector2i(2, 0)
	var cells: Array[Vector2i] = [water, dirt]
	var attacker := _attacker(Elemental.Element.NONE, EquippableData.TargetMode.BOTH)
	_laying(attacker)
	var plan := _resolve(_aim(attacker, cells, cells),
			_KindBoard.new(null, {water: Terrain.Kind.WATER, dirt: Terrain.Kind.DIRT}))
	assert_bool(_lays_fire(plan, dirt)).override_failure_message("fixture: no fire on the dry tile").is_true()
	assert_bool(_lays_fire(plan, water)).override_failure_message("fire was laid on open water").is_false()


func test_laid_fire_burns_on_ice_the_hit_leaves_frozen() -> void:
	# Ruling 4: on ice it lands, until the dev's ice rule exists. An elementless hit melts nothing.
	var tsm := _store_with(CELL, FROZEN)
	var cells: Array[Vector2i] = [CELL]
	var attacker := _attacker(Elemental.Element.NONE, EquippableData.TargetMode.BOTH)
	_laying(attacker)
	var plan := _resolve(_aim(attacker, cells, cells), _KindBoard.new(tsm, {CELL: Terrain.Kind.WATER}))
	assert_bool(_lays_fire(plan, CELL)).override_failure_message("fire laid on ice fizzled as if on water").is_true()


func test_ice_the_same_hit_melts_takes_no_fire() -> void:
	var tsm := _store_with(CELL, FROZEN)
	var cells: Array[Vector2i] = [CELL]
	var attacker := _attacker(Elemental.Element.FIRE, EquippableData.TargetMode.BOTH)
	_laying(attacker)
	var plan := _resolve(_aim(attacker, cells, cells), _KindBoard.new(tsm, {CELL: Terrain.Kind.WATER}))
	var effect := _effect_on(plan, CELL)
	assert_bool(effect != null and effect.states_removed.has(FROZEN)).override_failure_message(
		"fixture: the authored catalog no longer melts ice with fire -- point this case at what does").is_true()
	assert_bool(_lays_fire(plan, CELL)).override_failure_message(
		"fire was laid on water its own hit had just melted").is_false()


# --- how long it lasts ---------------------------------------------------------------------------

func _lay(store: TerrainStateManager, cell: Vector2i, turns: int) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([BURNING])
	effect.state_turns[BURNING] = turns
	store.apply(effect)


func test_on_stone_a_laid_fire_runs_its_own_life_and_goes_out_clean() -> void:
	var stone: TerrainStateManager = auto_free(T.store_on_stone())
	add_child(stone)
	_lay(stone, CELL, LIFE)
	assert_int(stone.turns_remaining(CELL, BURNING)).is_equal(LIFE)
	for _i in range(LIFE - 1):
		stone.tick_states()
	assert_bool(stone.has_state(CELL, BURNING)).override_failure_message("the wall went out early").is_true()
	stone.tick_states()
	assert_bool(stone.has_state(CELL, BURNING)).override_failure_message("the wall outlived its life").is_false()
	assert_bool(stone.has_state(CELL, SCORCHED)).override_failure_message(
		"stone was left scorched, though nothing on it was fuel").is_false()


func test_on_fuel_the_grounds_clock_wins_and_scorches() -> void:
	# Ruling 5: fire laid on grass burns as grass.
	var grass: TerrainStateManager = auto_free(T.store_on_fuel())
	add_child(grass)
	_lay(grass, CELL, LIFE)
	assert_int(grass.turns_remaining(CELL, BURNING)).override_failure_message(
		"the laid life beat the ground's own clock").is_equal(T.FUEL_TURNS)
	for _i in range(T.FUEL_TURNS):
		grass.tick_states()
	assert_bool(grass.has_state(CELL, BURNING)).is_false()
	assert_bool(grass.has_state(CELL, SCORCHED)).override_failure_message("burnt fuel left no scorch").is_true()


func test_a_fire_laid_over_a_brazier_leaves_it_permanent() -> void:
	var stone: TerrainStateManager = auto_free(T.store_on_stone())
	add_child(stone)
	var brazier := ResolvedCellEffect.new()
	brazier.cell = CELL
	brazier.states_added.assign([BURNING])
	stone.apply(brazier)
	_lay(stone, CELL, LIFE)
	assert_int(stone.turns_remaining(CELL, BURNING)).override_failure_message(
		"a laid fire put a clock on a permanent brazier").is_equal(-1)
	for _i in range(LIFE * 2):
		stone.tick_states()
	assert_bool(stone.has_state(CELL, BURNING)).is_true()


func test_a_fire_laid_over_a_standing_wall_leaves_its_clock() -> void:
	var stone: TerrainStateManager = auto_free(T.store_on_stone())
	add_child(stone)
	_lay(stone, CELL, LIFE)
	stone.tick_states()
	var left := stone.turns_remaining(CELL, BURNING)
	_lay(stone, CELL, LIFE)
	assert_int(stone.turns_remaining(CELL, BURNING)).override_failure_message(
		"a second wall restarted the first one's clock").is_equal(left)


func test_a_mid_battle_save_keeps_a_walls_clock() -> void:
	var src: TerrainStateManager = auto_free(T.store_on_stone())
	add_child(src)
	_lay(src, CELL, LIFE)
	src.tick_states()
	var dst: TerrainStateManager = auto_free(T.store_on_stone())
	add_child(dst)
	dst.load_state_dict(src.to_state_dict(), src.to_turns_dict())
	assert_int(dst.turns_remaining(CELL, BURNING)).override_failure_message(
		"the reloaded wall lost its clock -- on stone it would never go out").is_equal(src.turns_remaining(CELL, BURNING))


func test_a_wall_beside_grass_lights_it_at_the_round_end() -> void:
	# Ruling 6: it spreads like any fire. Stone at CELL, fuel beside it.
	var grass := CELL + Vector2i.RIGHT
	var fuel := T.fuel()
	var store: TerrainStateManager = auto_free(TerrainStateManager.new())
	store.fuel_source = func(cell: Vector2i) -> TerrainReaction: return fuel if cell == grass else null
	add_child(store)
	_lay(store, CELL, LIFE)
	store.tick_states()
	assert_bool(store.has_state(grass, BURNING)).override_failure_message("the wall did not light the grass beside it").is_true()
	assert_int(store.turns_remaining(grass, BURNING)).override_failure_message(
		"the grass the wall lit burned on the wall's life, not its own").is_equal(T.FUEL_TURNS)


# --- where it lands ------------------------------------------------------------------------------

func test_a_sweep_hands_its_effect_tiles_to_every_member_it_stamps() -> void:
	var attacker := _attacker(Elemental.Element.NONE, EquippableData.TargetMode.BOTH)
	var attack := _laying(attacker)
	P.line(attack, 2)
	var origin := attacker.movement.cell
	var aim := origin + Vector2i.RIGHT
	var board := _KindBoard.new(null, {})
	# No effect shape: the effect lands where the attack struck.
	var plain := Conduction.sweep(attacker, origin, aim, attack, board)
	assert_array(plain.effect).contains_exactly(plain.struck)
	# An effect shape of its own: placed by Reach, apart from the hit.
	attack.tile_effect_shape = P.shape([Vector2i(-1, -1), Vector2i(1, -1)] as Array[Vector2i])
	var shaped := Conduction.sweep(attacker, origin, aim, attack, board)
	var placed := Reach.get_effect_cells_from(origin, aim, attack, board)
	assert_array(shaped.effect).contains_exactly(placed)
	assert_array(shaped.effect).override_failure_message(
		"fixture: the effect shape landed on the hit's own tiles, which proves nothing").is_not_equal(shaped.struck)
	var group: Array[AttackAction] = [AttackAction.create(attacker, origin, null, aim)]
	AttackAction.stamp_sweep(group, shaped)
	assert_array(group[0].effect_cells).contains_exactly(placed)
