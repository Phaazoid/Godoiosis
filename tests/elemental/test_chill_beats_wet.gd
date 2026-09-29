# #1092: CHILLED and WET are mutually exclusive, and CHILLED always wins, in both orders (dev ruling).
# One declared rule (Elemental.OVERRIDES) is asked at every place a unit gains a state -- the reaction
# fold, the wade, a shove's landing, a melt's sinking and Unit.add_element_state -- so each case drives
# one of those doors and asserts the preview AND the executed unit wherever both exist.
#
# Reactions are built per case rather than read off the catalog (the content razor): the rule is what
# is under test, and each case carries a control proving its hit or its water DOES wet a dry unit.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const WET := Elemental.State.WET
const CHILLED := Elemental.State.CHILLED
const WATER := Elemental.Element.WATER
const ICE := Elemental.Element.ICE
const FIRE := Elemental.Element.FIRE

const MAIN_SCENE := "res://Scenes/Main.tscn"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const DEEP_WATER := Vector2i(5, 6)

var _sm: SquadManager
var _main: Node = null


# A hit carrying several elements at once; no shipped attack authors two today.
class _Blend extends AttackData:
	var carried: Array[Elemental.Element] = []
	func authored_elements() -> Array[Elemental.Element]:
		return carried


# Water authored per cell (test_soaking.gd's board). Every cell is walkable, so a shove has somewhere
# to go on a board with no grid.
class _WaterBoard extends BoardContext:
	var water: Dictionary
	func _init(unit_list: Array[Unit], water_cells: Array[Vector2i], states: TerrainStateManager) -> void:
		super(null, unit_list, null, states)
		water = {}
		for cell in water_cells:
			water[cell] = true
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return Terrain.Kind.WATER if water.has(cell) else Terrain.Kind.GRASS
	func is_walkable(_cell: Vector2i) -> bool:
		return true


func before_test() -> void:
	_sm = H.make_manager(self)


func after_test() -> void:
	await await_idle_frame()
	if _main != null:
		get_tree().root.remove_child(_main)
		_main.free()
		_main = null
		await await_idle_frame()


# --- fixture -------------------------------------------------------------------------------------

func _sets(element: Elemental.Element, state: Elemental.State) -> ElementalReaction:
	var reaction := ElementalReaction.new()
	reaction.incoming_element = element
	reaction.add_states.assign([state])
	return reaction

# Temperature Shock's shape: an element that ends the state it meets.
func _ends(element: Elemental.Element, state: Elemental.State) -> ElementalReaction:
	var reaction := ElementalReaction.new()
	reaction.incoming_element = element
	reaction.required_state = state
	reaction.remove_states.assign([state])
	return reaction

func _attacker(element: Elemental.Element, cell := Vector2i(0, 0)) -> Unit:
	var unit := H.spawn_solo(self, _sm, PLAYER, cell, {Stats.Stat.STR: 0}, true, 4)
	(unit.get_equipped_weapon() as WeaponInstance).template.main_attack.elemental_damage_type = element
	return unit

func _target(cell: Vector2i, held: Array[Elemental.State] = []) -> Unit:
	var unit := H.spawn_solo(self, _sm, ENEMY, cell, {Stats.Stat.MHP: 50}, false)
	for s in held:
		unit.add_element_state(s)
	return unit

func _blended(attacker: Unit, target: Unit, elements: Array[Elemental.Element]) -> AttackAction:
	var blend := _Blend.new()
	blend.carried = elements
	var action := AttackAction.create(attacker, attacker.movement.cell, target, target.movement.cell)
	action.fired_attack = blend
	return action

func _resolve(action: AttackAction, reactions: Array[ElementalReaction]) -> ResolvedPlan:
	var plan := ResolvedPlan.new()
	plan.attacks.append(action)
	PlanResolver.resolve(plan, reactions)
	return plan

func _states(frozen: Array[Vector2i] = []) -> TerrainStateManager:
	var store: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(store)
	for cell in frozen:
		var freeze := ResolvedCellEffect.new()
		freeze.cell = cell
		freeze.states_added.assign([Terrain.TileState.FROZEN])
		store.apply(freeze)
	return store

func _board(units: Array[Unit], water: Array[Vector2i]) -> _WaterBoard:
	return _WaterBoard.new(units, water, _states())

func _holds_only(unit: Unit, state: Elemental.State) -> bool:
	return unit.element_states.size() == 1 and unit.element_states.has(state)


# --- the reaction fold -----------------------------------------------------------------------------

func test_water_on_a_chilled_unit_leaves_it_chilled_and_dry() -> void:
	var reactions: Array[ElementalReaction] = [_sets(WATER, WET)]
	var attacker := _attacker(WATER)
	var dry := _target(Vector2i(1, 0))
	var chilled := _target(Vector2i(0, 1), [CHILLED])
	var control := H.stamped_attack(attacker, dry)
	_resolve(control, reactions)
	assert_bool(control.resolved.states_added.has(WET)).override_failure_message(
			"fixture: the water hit must wet a dry unit").is_true()

	var hit := H.stamped_attack(attacker, chilled)
	var plan := _resolve(hit, reactions)
	assert_bool(hit.resolved.states_added.has(WET)).override_failure_message(
			"the preview soaks a Chilled unit").is_false()
	assert_bool(hit.resolved.states_removed.has(CHILLED)).is_false()
	var projected := PlanResolver.projected_states(chilled, plan.hypo)
	assert_bool(projected.has(CHILLED) and not projected.has(WET)).override_failure_message(
			"the pass threads %s onto a Chilled unit a water hit reached" % [str(projected)]).is_true()

	await hit.execute()
	assert_bool(_holds_only(chilled, CHILLED)).override_failure_message(
			"executed, the unit holds %s" % [str(chilled.element_states)]).is_true()


# The fold judges the state the hit LEAVES, so the order the reactions match in cannot decide it (E8).
func test_ice_and_water_in_one_hit_chill_a_dry_unit_and_never_wet_it() -> void:
	var orders: Array[Array] = [
		[_sets(ICE, CHILLED), _sets(WATER, WET)],
		[_sets(WATER, WET), _sets(ICE, CHILLED)],
	]
	for i in orders.size():
		var reactions: Array[ElementalReaction] = []
		reactions.assign(orders[i])
		var attacker := _attacker(Elemental.Element.NONE, Vector2i(0, 4 * i))
		var target := _target(Vector2i(1, 4 * i))
		var hit := _blended(attacker, target, [ICE, WATER])
		_resolve(hit, reactions)
		assert_int(hit.resolved.fired_reactions.size()).override_failure_message(
				"fixture (order %d): both reactions must match the dry unit" % i).is_equal(2)
		assert_bool(hit.resolved.states_added.has(CHILLED)).is_true()
		assert_bool(hit.resolved.states_added.has(WET)).override_failure_message(
				"order %d: one hit left a unit both Chilled and Wet" % i).is_false()

		await hit.execute()
		assert_bool(_holds_only(target, CHILLED)).override_failure_message(
				"order %d, executed: the unit holds %s" % [i, str(target.element_states)]).is_true()


# Water and fire together on a Chilled unit: the fire ends the chill in the same hit, so what the hit
# leaves is not Chilled and the water is free to wet it. Judged on the pre-hit state, WET would drop.
func test_water_and_fire_on_a_chilled_unit_end_it_wet_and_not_chilled() -> void:
	var orders: Array[Array] = [
		[_sets(WATER, WET), _ends(FIRE, CHILLED)],
		[_ends(FIRE, CHILLED), _sets(WATER, WET)],
	]
	for i in orders.size():
		var reactions: Array[ElementalReaction] = []
		reactions.assign(orders[i])
		var attacker := _attacker(Elemental.Element.NONE, Vector2i(0, 4 * i))
		var target := _target(Vector2i(1, 4 * i), [CHILLED])
		var hit := _blended(attacker, target, [WATER, FIRE])
		_resolve(hit, reactions)
		assert_bool(hit.resolved.states_removed.has(CHILLED)).override_failure_message(
				"fixture (order %d): the fire must end the chill" % i).is_true()
		assert_bool(hit.resolved.states_added.has(WET)).override_failure_message(
				"order %d: the water was judged against a chill the same hit ends" % i).is_true()

		await hit.execute()
		assert_bool(_holds_only(target, WET)).override_failure_message(
				"order %d, executed: the unit holds %s" % [i, str(target.element_states)]).is_true()


# CHILLED arriving dries the unit whether or not a reaction says so: the ice here carries no Deep
# Chill, so the only thing that can take the WET away is the rule.
func test_ice_on_a_wet_unit_dries_it_even_where_no_reaction_consumes_the_wet() -> void:
	var reactions: Array[ElementalReaction] = [_sets(ICE, CHILLED)]
	var attacker := _attacker(ICE)
	var target := _target(Vector2i(1, 0), [WET])
	var hit := H.stamped_attack(attacker, target)
	var plan := _resolve(hit, reactions)
	assert_bool(hit.resolved.states_added.has(CHILLED)).override_failure_message(
			"fixture: the ice must chill").is_true()
	assert_bool(hit.resolved.states_removed.has(WET)).override_failure_message(
			"the preview chills a Wet unit and leaves it Wet").is_true()
	var projected := PlanResolver.projected_states(target, plan.hypo)
	assert_bool(projected.has(CHILLED) and not projected.has(WET)).override_failure_message(
			"the pass threads %s" % [str(projected)]).is_true()

	await hit.execute()
	assert_bool(_holds_only(target, CHILLED)).override_failure_message(
			"executed, the unit holds %s" % [str(target.element_states)]).is_true()


# --- water itself ----------------------------------------------------------------------------------

func test_a_chilled_unit_wades_the_river_and_comes_out_dry() -> void:
	var mover := H.spawn_unit(self, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 0}, true, 4)
	var units: Array[Unit] = [mover]
	var river: Array[Vector2i] = [Vector2i(1, 0)]
	var board := _board(units, river)
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var move := MoveAction.new()
	move.init(mover, path, null)
	var no_reactions: Array[ElementalReaction] = []
	var no_terrain: Array[TerrainReaction] = []

	var control := ResolvedPlan.new()
	PlanResolver.resolve_move(move, control, control.hypo, no_reactions, board, no_terrain)
	assert_bool(move.resolved != null and move.resolved.states_added.has(WET)).override_failure_message(
			"fixture: the ford must soak a dry walker").is_true()

	mover.add_element_state(CHILLED)
	var plan := ResolvedPlan.new()
	PlanResolver.resolve_move(move, plan, plan.hypo, no_reactions, board, no_terrain)
	assert_bool(move.resolved != null and move.resolved.states_added.has(WET)).override_failure_message(
			"the preview soaks a Chilled walker").is_false()
	assert_bool(PlanResolver.projected_states(mover, plan.hypo).has(WET)).is_false()

	await move.execute()
	assert_bool(_holds_only(mover, CHILLED)).override_failure_message(
			"executed, the walker holds %s" % [str(mover.element_states)]).is_true()


func test_a_chilled_unit_shoved_into_the_shallows_comes_out_dry() -> void:
	var attacker := _attacker(Elemental.Element.NONE)
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack.knockback = 2
	var target := _target(Vector2i(1, 0))
	var units: Array[Unit] = [attacker, target]
	var shallows: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]
	var board := _board(units, shallows)
	var no_reactions: Array[ElementalReaction] = []
	var no_terrain: Array[TerrainReaction] = []

	var control := H.stamped_attack(attacker, target)
	var control_plan := ResolvedPlan.new()
	control_plan.attacks.append(control)
	PlanResolver.resolve_attacks(control_plan, control_plan.hypo, no_reactions, board, no_terrain)
	assert_bool(control.resolved.knockback_applied and control.resolved.states_added.has(WET)) \
		.override_failure_message("fixture: the shove must throw a dry unit into the shallows and soak it") \
		.is_true()

	target.add_element_state(CHILLED)
	var shove := H.stamped_attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(shove)
	PlanResolver.resolve_attacks(plan, plan.hypo, no_reactions, board, no_terrain)
	assert_bool(shove.resolved.knockback_applied).override_failure_message(
			"fixture: the Chilled unit must be thrown too").is_true()
	assert_bool(shove.resolved.states_added.has(WET)).override_failure_message(
			"the preview soaks a Chilled unit thrown into the water").is_false()

	await shove.execute()
	assert_bool(_holds_only(target, CHILLED)).override_failure_message(
			"executed, the unit holds %s" % [str(target.element_states)]).is_true()


# --- the door --------------------------------------------------------------------------------------

# Both orders, because the rule's whole content is "whichever came first" (the refusal and the strip
# are two halves, and each order exercises only one of them).
func test_through_the_door_chilled_beats_wet_in_both_orders() -> void:
	var orders: Array[Array] = [[WET, CHILLED], [CHILLED, WET]]
	for order in orders:
		var unit := H.spawn_unit(self, PLAYER, Vector2i.ZERO, {}, false)
		for s: Elemental.State in order:
			unit.add_element_state(s)
		assert_bool(_holds_only(unit, CHILLED)).override_failure_message(
				"adding %s left %s" % [str(order), str(unit.element_states)]).is_true()
		assert_bool(unit.has_stat_effect_from(Elemental.state_effect_source(CHILLED))).override_failure_message(
				"adding %s: the chill's paired effect is missing" % [str(order)]).is_true()


# --- shock ---------------------------------------------------------------------------------------

# No special case (dev, explicit): the current runs through the water, and the water under a Chilled
# unit carries it the same as under anybody.
func test_the_current_still_catches_a_chilled_unit_standing_in_live_water() -> void:
	var shooter := H.spawn_unit(self, PLAYER, Vector2i(0, -4))
	(shooter.get_equipped_weapon() as WeaponInstance).template.main_attack.elemental_damage_type = \
		Elemental.Element.SHOCK
	var swimmer := _target(Vector2i(1, 0), [CHILLED])
	var units: Array[Unit] = [shooter, swimmer]
	var lake: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var board := _board(units, lake)
	var struck: Array[Vector2i] = [Vector2i(0, 0)]

	var arc := Conduction.arc_cells(shooter, shooter.get_fired_attack(), struck, board)
	var no_one: Array[Unit] = []
	assert_bool(Conduction.caught(arc, board, {}, no_one).has(swimmer)).override_failure_message(
			"a Chilled unit standing in live water was spared the current").is_true()


# ...and on dry ground it carries none: a water hit that could not wet it left no conductor behind.
func test_a_chilled_unit_a_water_hit_reached_relays_nothing_on_dry_ground() -> void:
	var reactions: Array[ElementalReaction] = [_sets(WATER, WET)]
	var attacker := _attacker(WATER)
	var dry := _target(Vector2i(1, 0))
	var chilled := _target(Vector2i(0, 1), [CHILLED])
	var plan := ResolvedPlan.new()
	plan.attacks.append(H.stamped_attack(attacker, dry))
	plan.attacks.append(H.stamped_attack(attacker, chilled))
	PlanResolver.resolve(plan, reactions)

	var units: Array[Unit] = [attacker, dry, chilled]
	var wet := Conduction.wet_cells(_board(units, [] as Array[Vector2i]), plan.hypo)
	assert_bool(wet.has(dry.movement.cell)).override_failure_message(
			"fixture: the water hit must make a dry unit a conductor").is_true()
	assert_bool(wet.has(chilled.movement.cell)).override_failure_message(
			"a Chilled unit conducts on dry ground after a water hit").is_false()


# --- the floor leaving -------------------------------------------------------------------------

# The one door that needs the real game: a melt is a deposit, and the sinking reads the ground the
# deposits leave (test_melt_sinks.gd's fixture). The fire spares the ally, so the chill it stands in
# is still on it when the water takes it.
func _boot_game() -> Node2D:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	var game: Node2D = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		for y in range(4):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()
	return game


func _sink_of(plan: ResolvedPlan, unit: Unit) -> SinkAction:
	for sink in plan.sinks:
		if sink.actor == unit:
			return sink
	return null


func test_a_chilled_unit_the_melt_sinks_goes_under_and_comes_up_dry() -> void:
	var game: Node2D = await _boot_game()
	var ice := Vector2i(3, 1)
	(game.grid as BoardGrid).paint(ice, GRASS_SOURCE, DEEP_WATER)
	var freeze := ResolvedCellEffect.new()
	freeze.cell = ice
	freeze.states_added.assign([Terrain.TileState.FROZEN])
	game.terrain_states.apply(freeze)
	var ally: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: 30}, PLAYER), ice)
	var hero: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), Vector2i(2, 1))
	assert_bool(ally != null and hero != null).override_failure_message("fixture: a unit did not spawn") \
		.is_true()
	hero.equipped_weapon = H.make_weapon(3)
	var fire: WeaponAttackData = (hero.get_equipped_weapon() as WeaponInstance).template.main_attack
	fire.elemental_damage_type = FIRE
	fire.targets = EquippableData.TargetMode.BOTH
	fire.hits_allies = false
	var squads: SquadManager = game.squad_manager
	squads.active_squad = hero.squad
	var aim := AttackAction.declare(hero, hero.movement.cell, ice)
	assert_bool(squads.queue_action(hero.squad, aim)).override_failure_message(
			"fixture: the fire never queued").is_true()
	game.refresh_action_queue(hero.squad)

	var dry_board: BoardContext = game._board()
	var dry_sink := _sink_of(squads.resolve_plan(hero.squad, dry_board), ally)
	assert_bool(dry_sink != null and dry_sink.resolved.states_added.has(WET)).override_failure_message(
			"fixture: the melt must sink the ally and soak it").is_true()

	ally.add_element_state(CHILLED)
	var board: BoardContext = game._board()
	var plan := squads.resolve_plan(hero.squad, board)
	var sink := _sink_of(plan, ally)
	assert_object(sink).override_failure_message("fixture: a Chilled ally must still go under").is_not_null()
	assert_bool(sink.resolved.states_added.has(WET)).override_failure_message(
			"the preview soaks a Chilled unit the water swallowed").is_false()
	assert_bool(PlanResolver.projected_states(ally, plan.hypo).has(WET)).is_false()

	await game.order_executor.execute_orders(hero)
	assert_bool(ally.is_downed()).override_failure_message("fixture: the ally never went under").is_true()
	assert_bool(ally.element_states.has(WET)).override_failure_message(
			"executed, the sunk Chilled ally came up Wet").is_false()
