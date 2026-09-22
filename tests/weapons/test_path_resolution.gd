# A SINGLE-TARGET SWING resolves along its paths (#1057, slice C of #1054): Reach walks each path and
# cuts it at the first tile the attack cannot reach, and the gather takes the first valid target on
# each walked path and stops there. The rulings under test are #1054's 7, 8, 9, 16, 17 and 26.
#
# Every attack and board is BUILT here (the content razor). A bare BoardHeights is the board for the
# geometry cases -- a grid-less BoardContext answers 0 for every prop column, so a tall cell IS a wall.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const ORIGIN := Vector2i(0, 0)
const UP_AIM := Vector2i(0, -1)   # facing north: grid-up is board-up, so offsets read as cells
const WALL := 6                    # three levels: stops any flat shot that has to pass it
const NO_UNITS: Array[Unit] = []


class _WaterBoard extends BoardContext:
	var water: Dictionary
	func _init(unit_list: Array[Unit], water_cells: Array[Vector2i]) -> void:
		super(null, unit_list, null)
		water = {}
		for cell in water_cells:
			water[cell] = true
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return Terrain.Kind.WATER if water.has(cell) else Terrain.Kind.GRASS


func _board(heights: Dictionary = {}, units: Array[Unit] = NO_UNITS) -> BoardContext:
	var h := BoardHeights.new()
	for cell: Vector2i in heights:
		h.set_cell(cell, heights[cell])
	return BoardContext.new(null, units, null, null, null, h)


func _path(cells: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(cells)
	return out


# A swing drawn as `paths`, self-anchored unless a range is given.
func _swing(paths: Array[Array], max_range := 0) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.max_range = max_range
	attack.attack_shape = P.pathed(paths)
	attack.swing = true
	return attack


func _walk(attack: AttackData, target: Vector2i, board: BoardContext, origin := ORIGIN) -> Array[Array]:
	return Reach.get_paths_from(null, origin, target, attack, board)


# A unit holding `attack` as its main, so the sweep reads that attack's element off it.
func _wielder(attack: WeaponAttackData, cell := ORIGIN) -> Unit:
	var unit: Unit = H.spawn_unit(self, PLAYER, cell)
	(unit.get_equipped_weapon() as WeaponInstance).template.main_attack = attack
	return unit


func _straight(length: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for step in range(1, length + 1):
		cells.append(Vector2i(0, -step))
	return cells


# ==============================================================================
#  The walk (Reach.get_paths_from)
# ==============================================================================

# THE identity (#1054): one straight path forward from the attacker is bit-for-bit today's
# _truncate on a width-1 line, every facing, every length, over boards that stop a lane two
# different ways -- a wall the trace cannot cross and a ledge the vertical rule refuses. Every
# shipped watch is exactly this case, so nothing they did before this ticket changes.
func test_a_straight_path_walks_exactly_what_the_painted_line_truncates_to() -> void:
	var boards: Array[Dictionary] = [
		{},
		{Vector2i(0, -3): WALL, Vector2i(3, 0): WALL, Vector2i(0, 3): WALL, Vector2i(-3, 0): WALL},
		{Vector2i(0, -2): 4, Vector2i(2, 0): 4, Vector2i(0, 2): 4, Vector2i(-2, 0): 4},
	]
	for heights in boards:
		var board := _board(heights)
		for dir: Vector2i in GridUtils.CARDINAL_DIRECTIONS:
			for length in range(1, 6):
				var painted := P.line(WeaponAttackData.new(), length)
				painted.swing = true
				painted.up_tolerance = 2
				var drawn := _swing([_straight(length)] as Array[Array])
				drawn.up_tolerance = 2
				var lane := Reach.get_affected_cells_from(null, ORIGIN, ORIGIN + dir, painted, board)
				var walked := _walk(drawn, ORIGIN + dir, board)
				var got: Array[Vector2i] = []
				if not walked.is_empty():
					got.assign(walked[0])
				assert_array(got).override_failure_message(
						"length %d facing %s over %s: the path walked %s, the line truncates to %s"
						% [length, dir, heights, got, lane]).is_equal(lane)


# Ruling 26 (dev, 2026-09-22): a side tile asks the SAME gate an AoE swing's tile asks -- the lane
# from beside the attacker -- not a straight line from the attacker. The one input where the two
# disagree: a wall right beside the attacker. The straight line to the diagonal tile clips that
# corner; the lane starts on it, and a trace ignores its own start.
func test_a_wall_beside_the_attacker_does_not_block_its_own_side_path() -> void:
	var diagonal := Vector2i(-1, -1)
	var board := _board({Vector2i(-1, 0): WALL})
	assert_bool(Reach.vertical_aim_ok(null, ORIGIN, diagonal, board)).override_failure_message(
			"fixture: the straight line is not blocked, so the two gates are not being told apart").is_false()
	var swing := _swing([_path([diagonal])] as Array[Array])
	swing.vertical_rule = AttackData.VerticalRule.RANGED
	assert_array(_walk(swing, UP_AIM, board)).is_equal([_path([diagonal])])


# Ruling 16: a path cannot go round a wall. The first tile it cannot reach ENDS it, and a later
# visit to a tile it could reach does not pick it back up.
func test_a_path_ends_at_its_first_unreachable_tile_and_a_revisit_does_not_resume_it() -> void:
	var near := Vector2i(0, -1)
	var ledge := Vector2i(1, -1)
	var swing := _swing([_path([near, ledge, near])] as Array[Array])
	swing.up_tolerance = 2
	var board := _board({ledge: 4})
	assert_array(_walk(swing, UP_AIM, board)).is_equal([_path([near])])


# A PLACED path is judged from where it lands, _spread's anchor: a wall between the attacker and the
# impact is nothing to it, and a wall past its first tile stops the tile behind.
func test_a_placed_path_is_judged_from_the_impact() -> void:
	var impact := Vector2i(0, -3)
	var swing := _swing([_path([Vector2i(0, 0), Vector2i(0, -1), Vector2i(0, -2)])] as Array[Array], 3)
	var board := _board({Vector2i(0, -1): WALL, Vector2i(0, -4): WALL})
	assert_array(_walk(swing, impact, board)).is_equal([_path([impact, Vector2i(0, -4)])])


func test_swing_off_walks_no_paths_and_covers_every_tile() -> void:
	var swing := _swing([_straight(3)] as Array[Array])
	swing.swing = false
	var board := _board({Vector2i(0, -2): WALL})
	assert_array(_walk(swing, UP_AIM, board)).is_empty()
	assert_array(Reach.get_affected_cells_from(null, ORIGIN, UP_AIM, swing, board)) \
		.contains_exactly_in_any_order(_straight(3))


func test_a_null_board_walks_every_tile() -> void:
	var swing := _swing([_straight(3)] as Array[Array])
	assert_array(_walk(swing, UP_AIM, null)).is_equal([_straight(3)])


# The footprint projection stays one tile per entry whatever the paths revisit -- _resolve_cell_effects
# used to take it literally, and a revisit must not become a second deposit.
func test_the_footprint_lists_a_revisited_tile_once() -> void:
	var swing := _swing([_path([Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -1)])] as Array[Array])
	var cells := Reach.get_affected_cells_from(null, ORIGIN, UP_AIM, swing, _board())
	assert_array(cells).contains_exactly_in_any_order([Vector2i(0, -1), Vector2i(0, -2)])


# ==============================================================================
#  The gather (Conduction.sweep -> RulesService.gather_path_victims)
# ==============================================================================

func _sweep(attacker: Unit, board: BoardContext) -> Conduction.Sweep:
	return Conduction.sweep(attacker, attacker.movement.cell, attacker.movement.cell + Vector2i.UP,
			attacker.get_fired_attack(), board)


func test_a_path_takes_its_first_valid_target_and_stops() -> void:
	var attacker := _wielder(_swing([_straight(3)] as Array[Array]))
	var near: Unit = H.spawn_unit(self, ENEMY, Vector2i(0, -2))
	var far: Unit = H.spawn_unit(self, ENEMY, Vector2i(0, -3))
	var reach := _sweep(attacker, _board({}, [attacker, near, far] as Array[Unit]))
	assert_array(reach.victims).is_equal([near])
	assert_array(reach.struck).is_equal(_straight(2))


# Ruling 8: an ally the attack may not hit is TRANSPARENT -- passed through, never a wall.
func test_an_ally_the_attack_cannot_hit_is_passed_through() -> void:
	var attacker := _wielder(_swing([_straight(3)] as Array[Array]))
	var friend: Unit = H.spawn_unit(self, PLAYER, Vector2i(0, -1))
	var foe: Unit = H.spawn_unit(self, ENEMY, Vector2i(0, -3))
	assert_bool(attacker.get_fired_attack().hits_allies).is_false()
	var reach := _sweep(attacker, _board({}, [attacker, friend, foe] as Array[Unit]))
	assert_array(reach.victims).is_equal([foe])


# Ruling 9: a downed enemy is an ordinary target, so its body ABSORBS the swing and shields the live
# enemy behind it.
func test_a_downed_body_absorbs_the_swing() -> void:
	var attacker := _wielder(_swing([_straight(3)] as Array[Array]))
	var body: Unit = H.spawn_unit(self, ENEMY, Vector2i(0, -1))
	body.lifecycle_state = Unit.LifecycleState.DOWNED
	var behind: Unit = H.spawn_unit(self, ENEMY, Vector2i(0, -2))
	var reach := _sweep(attacker, _board({}, [attacker, body, behind] as Array[Unit]))
	assert_array(reach.victims).is_equal([body])


# Rulings 7 and 17: two paths reaching one unit are TWO hits, and paths travel together -- step 1 of
# every path, then step 2 -- so a first-step victim on the LAST path leads the volley.
func test_two_paths_on_one_unit_hit_it_twice_in_step_order() -> void:
	var long_way := _path([Vector2i(1, -1), Vector2i(1, -2), Vector2i(0, -2)])
	var short_way := _path([Vector2i(0, -1), Vector2i(0, -2)])
	var aside := _path([Vector2i(-1, -1)])
	var attacker := _wielder(_swing([short_way, long_way, aside] as Array[Array]))
	var twice: Unit = H.spawn_unit(self, ENEMY, Vector2i(0, -2))
	var first: Unit = H.spawn_unit(self, ENEMY, Vector2i(-1, -1))
	var reach := _sweep(attacker, _board({}, [attacker, twice, first] as Array[Unit]))
	assert_array(reach.victims).is_equal([first, twice, twice])


# A path through the attacker's own tile: hits_self decides whether they are a target (ruling 4).
func test_the_attackers_own_tile_is_passed_through_unless_it_hits_self() -> void:
	var swing := _swing([_path([Vector2i(0, 0), Vector2i(0, -1)])] as Array[Array])
	var attacker := _wielder(swing)
	var foe: Unit = H.spawn_unit(self, ENEMY, Vector2i(0, -1))
	var board := _board({}, [attacker, foe] as Array[Unit])
	assert_array(_sweep(attacker, board).victims).is_equal([foe])
	swing.hits_self = true
	var reach := _sweep(attacker, board)
	assert_array(reach.victims).is_equal([attacker])
	assert_array(reach.struck).is_equal([ORIGIN])


# ==============================================================================
#  The current is seeded from what the swing STRUCK
# ==============================================================================

func _shock_swing(length: int) -> WeaponAttackData:
	var swing := _swing([_straight(length)] as Array[Array])
	swing.elemental_damage_type = Elemental.Element.SHOCK
	return swing


# Water only PAST the victim stays dark: the shot never reached it. Flooding the uncut path first --
# the area sweep's order -- would catch the swimmer.
func test_water_past_the_victim_carries_no_current() -> void:
	var attacker := _wielder(_shock_swing(3))
	var victim: Unit = H.spawn_unit(self, ENEMY, Vector2i(0, -2))
	var swimmer: Unit = H.spawn_unit(self, ENEMY, Vector2i(1, -3))
	var units: Array[Unit] = [attacker, victim, swimmer]
	var board := _WaterBoard.new(units, _path([Vector2i(0, -3), Vector2i(1, -3)]))
	var reach := _sweep(attacker, board)
	assert_array(reach.victims).is_equal([victim])


# ...while water the swing crossed on the way to its victim conducts as normal.
func test_water_the_swing_crossed_carries_the_current() -> void:
	var attacker := _wielder(_shock_swing(3))
	var victim: Unit = H.spawn_unit(self, ENEMY, Vector2i(0, -2))
	var swimmer: Unit = H.spawn_unit(self, ENEMY, Vector2i(1, -1))
	var units: Array[Unit] = [attacker, victim, swimmer]
	var board := _WaterBoard.new(units, _path([Vector2i(0, -1), Vector2i(1, -1)]))
	var reach := _sweep(attacker, board)
	assert_array(reach.victims).is_equal([victim, swimmer])


# ==============================================================================
#  Two hits on one unit, through the resolver
# ==============================================================================

func _volley(attacker: Unit, board: BoardContext) -> Array[AttackAction]:
	var reach := _sweep(attacker, board)
	var group := AttackAction.create_volley(attacker, attacker.movement.cell,
			attacker.movement.cell + Vector2i.UP, reach.victims, attacker.get_fired_attack(), reach.cells, reach.links)
	for atk in group:
		atk.struck_cells = reach.struck
	return group


func _two_paths_onto(cell: Vector2i) -> WeaponAttackData:
	var left := _path([Vector2i(-1, -1), Vector2i(-1, -2), cell])
	var right := _path([Vector2i(1, -1), Vector2i(1, -2), cell])
	return _swing([left, right] as Array[Array])


# Ruling 7's own example: a Guard absorbs the first of the two hits and the ward takes the second.
func test_a_guard_absorbs_the_first_of_two_path_hits_and_the_ward_takes_the_second() -> void:
	var attacker := _wielder(_two_paths_onto(Vector2i(0, -2)))
	var ward: Unit = H.spawn_unit(self, ENEMY, Vector2i(0, -2), {Stats.Stat.MHP: 60})
	var blocker: Unit = H.spawn_unit(self, ENEMY, Vector2i(0, -3), {Stats.Stat.MHP: 60})
	var board := _board({}, [attacker, ward, blocker] as Array[Unit])
	var group := _volley(attacker, board)
	assert_int(group.size()).override_failure_message("fixture: the two paths did not both take the ward") \
		.is_equal(2)
	var plan := ResolvedPlan.new()
	plan.guards.append(GuardWard.make(blocker, ward, 1))
	var no_reactions: Array[ElementalReaction] = []
	var no_terrain: Array[TerrainReaction] = []
	PlanResolver.resolve_attack_group(group, plan, plan.hypo, no_reactions, board, no_terrain)
	assert_object(group[0].target).is_same(blocker)
	assert_object(group[1].target).is_same(ward)
	_break(group)


# ...and a watch the first hit breaks flips ONCE, so no two rows report one ending.
func test_a_watch_broken_by_the_first_of_two_path_hits_flips_once() -> void:
	var attacker := _wielder(_two_paths_onto(Vector2i(0, -2)))
	var watcher: Unit = H.spawn_unit(self, ENEMY, Vector2i(0, -2), {Stats.Stat.MHP: 60})
	var board := _board({}, [attacker, watcher] as Array[Unit])
	var group := _volley(attacker, board)
	var plan := ResolvedPlan.new()
	var line: Array[Vector2i] = [Vector2i(0, -3)]
	plan.watches.append(Watch.make(watcher, watcher.movement.cell, Vector2i(0, -3), line, watcher.get_fired_attack()))
	var no_reactions: Array[ElementalReaction] = []
	var no_terrain: Array[TerrainReaction] = []
	PlanResolver.resolve_attack_group(group, plan, plan.hypo, no_reactions, board, no_terrain)
	assert_bool(group[0].resolved.cancels_watch).is_true()
	assert_bool(group[1].resolved.cancels_watch).is_false()
	_break(group)


func _break(group: Array[AttackAction]) -> void:
	var empty: Array[AttackAction] = []
	for atk in group:
		atk.volley = empty


# ==============================================================================
#  The ground: cell effects stop at the victim (through the real resolve)
# ==============================================================================

class _TreeBoard extends BoardContext:
	func terrain_kind_at(_cell: Vector2i) -> Terrain.Kind:
		return Terrain.Kind.TREE


# A fire swing stopped by a body on its second tile leaves the tree on its third standing. The
# deposit reads the tiles the VOLLEY BUILDER stamped, not a fresh Reach of the whole path, so this
# goes through resolve_plan rather than hand-building an action -- the stamp is the wire.
func test_a_fire_swing_burns_only_as_far_as_its_victim() -> void:
	var sm := H.make_manager(self)
	var swing := _swing([_straight(3)] as Array[Array])
	swing.elemental_damage_type = Elemental.Element.FIRE
	swing.targets = EquippableData.TargetMode.BOTH
	var attacker := H.spawn_solo(self, sm, PLAYER, ORIGIN)
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack = swing
	var victim := H.spawn_solo(self, sm, ENEMY, Vector2i(0, -2), {Stats.Stat.MHP: 60})
	attacker.squad._queue_action(AttackAction.declare(attacker, ORIGIN, UP_AIM))
	var burn := TerrainReaction.new()
	burn.incoming_element = Elemental.Element.FIRE
	burn.required_kind = Terrain.Kind.TREE
	burn.add_tile_states.assign([Terrain.TileState.BURNING])
	var units: Array[Unit] = [attacker, victim]
	var no_reactions: Array[ElementalReaction] = []
	var terrain: Array[TerrainReaction] = [burn]

	var plan := sm.resolve_plan(attacker.squad, _TreeBoard.new(sm.grid, units, sm), no_reactions, terrain)

	var burnt: Array[Vector2i] = []
	for effect in plan.cell_effects:
		burnt.append(effect.cell)
	assert_array(burnt).override_failure_message(
			"the fire landed on %s -- a swing that stopped at its victim burned past it" % [burnt]) \
		.contains_exactly_in_any_order(_straight(2))
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
