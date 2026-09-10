# Water SOURCES the WET state (#884): wading through it on your own feet, or being thrown into it.
# Both halves land in the resolver, so the queue shows the soaking before Execute and a SHOCK hit
# later in the SAME pass sees it -- which is the ordering case at the bottom of this file and the one
# a naive build gets wrong.
#
# Water is authored per cell (the content razor); is_walkable is overridden because a headless
# BoardContext with no grid reads every cell as a wall, and a shove needs somewhere to go.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

class _WaterBoard extends BoardContext:
	var water: Dictionary
	var deep: Dictionary
	func _init(unit_list: Array[Unit], shallow_cells: Array[Vector2i], deep_cells: Array[Vector2i],
			states: TerrainStateManager) -> void:
		super(null, unit_list, null, states)
		water = {}
		deep = {}
		for cell in shallow_cells:
			water[cell] = true
		for cell in deep_cells:
			water[cell] = true
			deep[cell] = true
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return Terrain.Kind.WATER if water.has(cell) else Terrain.Kind.GRASS
	func is_walkable(cell: Vector2i) -> bool:
		if has_tile_state(cell, Terrain.TileState.FROZEN):
			return true
		return not deep.has(cell)


func _states(frozen: Array[Vector2i]) -> TerrainStateManager:
	var store: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(store)
	for cell in frozen:
		var freeze := ResolvedCellEffect.new()
		freeze.cell = cell
		freeze.states_added.assign([Terrain.TileState.FROZEN])
		store.apply(freeze)
	return store

func _board(units: Array[Unit], shallow: Array[Vector2i], deep: Array[Vector2i] = [],
		frozen: Array[Vector2i] = []) -> _WaterBoard:
	return _WaterBoard.new(units, shallow, deep, _states(frozen))

func _walker(cell: Vector2i) -> Unit:
	return H.spawn_unit(self, PLAYER, cell, {Stats.Stat.STR: 0}, true, 4)

func _walk(mover: Unit, path: Array[Vector2i]) -> MoveAction:
	var move := MoveAction.new()
	move.init(mover, path, null)
	return move

func _resolve_walk(move: MoveAction, board: BoardContext, plan: ResolvedPlan) -> void:
	var no_reactions: Array[ElementalReaction] = []
	var no_terrain: Array[TerrainReaction] = []
	PlanResolver.resolve_move(move, plan, plan.hypo, no_reactions, board, no_terrain)

func _shock_electrocute(bonus := 5) -> ElementalReaction:
	var reaction := ElementalReaction.new()
	reaction.incoming_element = Elemental.Element.SHOCK
	reaction.required_state = Elemental.State.WET
	reaction.damage_bonus = bonus
	reaction.remove_states.assign([Elemental.State.WET])
	return reaction


# --- wading ------------------------------------------------------------------------------------

func test_walking_through_the_river_soaks_the_walker() -> void:
	var mover := _walker(Vector2i(0, 0))
	var units: Array[Unit] = [mover]
	var river: Array[Vector2i] = [Vector2i(1, 0)]
	var move := _walk(mover, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	var plan := ResolvedPlan.new()
	_resolve_walk(move, _board(units, river), plan)

	# The stamp, which execution replays and the queue row draws...
	assert_object(move.resolved).is_not_null()
	assert_bool(move.resolved.states_added.has(Elemental.State.WET)).is_true()
	# ...and the thread, which a later hit in this same pass reads.
	assert_bool(PlanResolver.projected_states(mover, plan.hypo).has(Elemental.State.WET)).is_true()

# The trigger is CROSSING, not arriving: the walk ends on dry ground and the mover is still soaked.
func test_a_ford_soaks_even_though_the_walk_ends_dry() -> void:
	var mover := _walker(Vector2i(0, 0))
	var units: Array[Unit] = [mover]
	var river: Array[Vector2i] = [Vector2i(1, 0)]
	var move := _walk(mover, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	var plan := ResolvedPlan.new()
	_resolve_walk(move, _board(units, river), plan)

	assert_bool(RulesService.wets_in(move.destination, mover, _board(units, river))).is_false()
	assert_bool(move.resolved.states_added.has(Elemental.State.WET)).is_true()

func test_a_walk_that_never_touches_water_stamps_nothing() -> void:
	var mover := _walker(Vector2i(0, 0))
	var units: Array[Unit] = [mover]
	var river: Array[Vector2i] = [Vector2i(5, 5)]
	var move := _walk(mover, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	var plan := ResolvedPlan.new()
	_resolve_walk(move, _board(units, river), plan)

	assert_object(move.resolved).is_null()

# A re-planned walk must not carry last pass's verdict -- resolved_stop_index's own rule, applied to
# the thing beside it. Re-planning OUT of the river is the whole reason the reset exists.
func test_re_planning_out_of_the_river_drops_the_soaking() -> void:
	var mover := _walker(Vector2i(0, 0))
	var units: Array[Unit] = [mover]
	var river: Array[Vector2i] = [Vector2i(1, 0)]
	var board := _board(units, river)
	var move := _walk(mover, [Vector2i(0, 0), Vector2i(1, 0)])
	_resolve_walk(move, board, ResolvedPlan.new())
	assert_object(move.resolved).is_not_null()

	move.path = [Vector2i(0, 0), Vector2i(0, 1)]
	move.destination = Vector2i(0, 1)
	_resolve_walk(move, board, ResolvedPlan.new())
	assert_object(move.resolved).is_null()

# A walk hits nobody, so its row must not print an HP arrow (#884). The flag is what the queue row
# reads; every outcome that evaluates a subject's health keeps the default.
func test_a_walks_outcome_carries_no_hp_reading() -> void:
	var mover := _walker(Vector2i(0, 0))
	var units: Array[Unit] = [mover]
	var river: Array[Vector2i] = [Vector2i(1, 0)]
	var move := _walk(mover, [Vector2i(0, 0), Vector2i(1, 0)])
	_resolve_walk(move, _board(units, river), ResolvedPlan.new())

	assert_bool(move.resolved.reads_hp).is_false()
	assert_bool(ResolvedOutcome.new().reads_hp).is_true()

func test_a_waterwalker_fords_dry() -> void:
	var mover := _walker(Vector2i(0, 0))
	var granted := AbilityData.new()
	granted.id = Abilities.Id.WATERWALK
	mover.unit_instance.data.innate_abilities = [granted]
	var units: Array[Unit] = [mover]
	var river: Array[Vector2i] = [Vector2i(1, 0)]
	var move := _walk(mover, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	_resolve_walk(move, _board(units, river), ResolvedPlan.new())

	assert_object(move.resolved).is_null()

# THE WIRE: the resolver stamps and EXECUTION applies. Both ends were already asserted above; this is
# the connection between them, which is the half a green suite is blind to (#103's shape).
func test_executing_the_walk_puts_the_state_on_the_unit() -> void:
	var mover := _walker(Vector2i(0, 0))
	var units: Array[Unit] = [mover]
	var river: Array[Vector2i] = [Vector2i(1, 0)]
	var move := _walk(mover, [Vector2i(0, 0), Vector2i(1, 0)])
	_resolve_walk(move, _board(units, river), ResolvedPlan.new())
	assert_bool(mover.element_states.has(Elemental.State.WET)).is_false()   # resolving changes nothing

	await move.execute()
	assert_bool(mover.element_states.has(Elemental.State.WET)).is_true()


# --- being thrown in ---------------------------------------------------------------------------

func _shove(attacker: Unit, target: Unit, board: BoardContext) -> AttackAction:
	var action := H.stamped_attack(attacker, target)
	action.fired_attack.knockback = 2
	var plan := ResolvedPlan.new()
	plan.attacks.append(action)
	var no_reactions: Array[ElementalReaction] = []
	var no_terrain: Array[TerrainReaction] = []
	PlanResolver.resolve_attacks(plan, plan.hypo, no_reactions, board, no_terrain)
	return action

func test_a_shove_that_lands_in_the_shallows_soaks_the_body() -> void:
	var attacker := _walker(Vector2i(0, 0))
	var target: Unit = H.spawn_unit(self, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	var units: Array[Unit] = [attacker, target]
	var shallow: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]

	var shove := _shove(attacker, target, _board(units, shallow))
	assert_bool(shove.resolved.knockback_applied).is_true()
	assert_bool(shove.resolved.states_added.has(Elemental.State.WET)).is_true()

# Deep water too: depth is walkability and wetness does not read it, so a drowning body comes up wet
# and goes on conducting. The drown is asserted alongside, or this could pass on a shove that never
# reached the lake at all.
func test_a_shove_into_deep_water_soaks_the_drowning_body() -> void:
	var attacker := _walker(Vector2i(0, 0))
	var target: Unit = H.spawn_unit(self, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	var units: Array[Unit] = [attacker, target]
	var no_shallow: Array[Vector2i] = []
	var deep: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]

	var shove := _shove(attacker, target, _board(units, no_shallow, deep))
	assert_int(shove.resolved.drown_damage).is_greater(0)
	assert_bool(shove.resolved.states_added.has(Elemental.State.WET)).is_true()

func test_a_shove_onto_dry_ground_soaks_nobody() -> void:
	var attacker := _walker(Vector2i(0, 0))
	var target: Unit = H.spawn_unit(self, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	var units: Array[Unit] = [attacker, target]
	var elsewhere: Array[Vector2i] = [Vector2i(5, 5)]

	var shove := _shove(attacker, target, _board(units, elsewhere))
	assert_bool(shove.resolved.knockback_applied).is_true()
	assert_bool(shove.resolved.states_added.has(Elemental.State.WET)).is_false()


# --- the ordering case -------------------------------------------------------------------------

# E4 end to end, and the reason the soaking lives in the resolver rather than at execution: a unit
# that FORDS the river this pass is electrocuted by a shock queued later in the SAME pass, and the
# queue shows the bonus before Execute.
#
# The dry control is what gives it teeth: a suite that set WET directly and then shocked would pass
# against a build where wading does nothing at all.
func test_wading_this_pass_electrocutes_on_the_same_pass() -> void:
	var mover := _walker(Vector2i(0, 0))
	var shooter := _walker(Vector2i(0, -4))
	(shooter.get_equipped_weapon() as WeaponInstance).template.main_attack.elemental_damage_type = \
		Elemental.Element.SHOCK
	var units: Array[Unit] = [mover, shooter]
	var river: Array[Vector2i] = [Vector2i(1, 0)]
	var reactions: Array[ElementalReaction] = [_shock_electrocute(5)]
	var no_terrain: Array[TerrainReaction] = []

	# Dry control: the same walk over dry ground, shocked by the same attack.
	var dry_board := _board(units, [] as Array[Vector2i])
	var dry_plan := ResolvedPlan.new()
	PlanResolver.resolve_move(_walk(mover, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]),
			dry_plan, dry_plan.hypo, reactions, dry_board, no_terrain)
	var dry_shot := H.stamped_attack(shooter, mover)
	dry_plan.attacks.append(dry_shot)
	PlanResolver.resolve_attacks(dry_plan, dry_plan.hypo, reactions, dry_board, no_terrain)

	# ...and the ford, which soaks him on the way through.
	var wet_board := _board(units, river)
	var wet_plan := ResolvedPlan.new()
	PlanResolver.resolve_move(_walk(mover, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]),
			wet_plan, wet_plan.hypo, reactions, wet_board, no_terrain)
	var wet_shot := H.stamped_attack(shooter, mover)
	wet_plan.attacks.append(wet_shot)
	PlanResolver.resolve_attacks(wet_plan, wet_plan.hypo, reactions, wet_board, no_terrain)

	assert_int(wet_shot.resolved.damage).is_equal(dry_shot.resolved.damage + 5)
	assert_bool(wet_shot.resolved.fired_reactions.is_empty()).is_false()
