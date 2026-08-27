# Queue order becomes real (#412, docs/design/standing-reactions.md). Moves resolve in the order
# they sit in the queue, that order is the player's to set, and it is the pass's clock for anything
# that happens DURING movement — an overwatch trigger being the first customer.
#
# Every case drives the real SquadManager.resolve_plan over a real queue and the real reorder seam,
# because the claim is about SEQUENCE: a suite handed a pre-built plan cannot see any of it, and one
# that pokes the resolver directly would not be exercising the lever the player actually pulls.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _main_of(unit: Unit) -> WeaponAttackData:
	return (unit.get_equipped_weapon() as WeaponInstance).template.main_attack


func _watcher(footprint: Array[Vector2i], cell := Vector2i(2, 5), power := 6) -> Unit:
	var unit := H.spawn_solo(self, _sm, ENEMY, cell, {Stats.Stat.STR: 4}, true, power)
	unit.arm_watch(cell, footprint[0], footprint, _main_of(unit))
	return unit


func _walk(unit: Unit) -> MoveAction:
	var path: Array[Vector2i] = []
	for x in range(unit.movement.cell.x, 5):
		path.append(Vector2i(x, unit.movement.cell.y))
	var move := MoveAction.new()
	move.init(unit, path, null)
	return move


func _board_with(units_in: Array) -> BoardContext:
	var units: Array[Unit] = []
	units.assign(units_in)
	return BoardContext.new(_sm.grid, units, _sm)


func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for shot in plan.watch_shots:
		shot.volley = empty


# Two squadmates, one per row, each walking east through its own watched cell.
class Pair:
	var top: Unit
	var bottom: Unit
	var watcher: Unit
	var board: BoardContext


func _crossing_pair() -> Pair:
	var pair := Pair.new()
	var watched: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 1)]
	pair.watcher = _watcher(watched)
	pair.top = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 60}, false)
	pair.bottom = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1), {Stats.Stat.MHP: 60}, false)
	_sm.join_squad(pair.bottom, pair.top.squad)
	pair.board = _board_with([pair.watcher, pair.top, pair.bottom])
	return pair


# The headline: which of your units eats the one shot is the row order you set, not the board's
# iteration order and not who happens to be nearer.
func test_the_first_mover_in_queue_order_eats_the_shot() -> void:
	var pair := _crossing_pair()
	pair.top.squad._queue_action(_walk(pair.top))
	pair.top.squad._queue_action(_walk(pair.bottom))

	var plan := _sm.resolve_plan(pair.top.squad, pair.board)

	assert_int(plan.watch_shots.size()).is_equal(1)
	assert_object(plan.watch_shots[0].target).is_same(pair.top)
	_break_volleys(plan)


# ...and dragging the rows changes the answer. The whole payoff of the ticket, through the seam the
# queue panel's drag actually calls.
func test_reordering_the_move_rows_changes_who_eats_the_shot() -> void:
	var pair := _crossing_pair()
	pair.top.squad._queue_action(_walk(pair.top))
	pair.top.squad._queue_action(_walk(pair.bottom))

	pair.top.squad.reorder_by_actor(BaseAction.ActionType.MOVE, [pair.bottom, pair.top])
	var plan := _sm.resolve_plan(pair.top.squad, pair.board)

	assert_int(plan.watch_shots.size()).is_equal(1)
	assert_object(plan.watch_shots[0].target).is_same(pair.bottom)
	_break_volleys(plan)


# The ordering is REAL, not just a list order: a mover later in the queue has not moved yet, so a
# shot fired while an EARLIER one crosses finds it standing where it started. Here the second
# mover's own starting cell is inside the blast, and it is hit there — an order-blind walk (everyone
# already at their destination) would find that cell empty and miss it entirely.
func test_a_later_mover_is_still_at_its_origin_when_an_earlier_shot_lands() -> void:
	var watched: Array[Vector2i] = [Vector2i(2, 0), Vector2i(0, 1)]
	var watcher := _watcher(watched)
	var crosser := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 60}, false)
	var straggler := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1), {Stats.Stat.MHP: 60}, false)
	_sm.join_squad(straggler, crosser.squad)
	crosser.squad._queue_action(_walk(crosser))
	crosser.squad._queue_action(_walk(straggler))

	var plan := _sm.resolve_plan(crosser.squad, _board_with([watcher, crosser, straggler]))

	# One trigger, two victims: the crosser at the cell it walked into and the straggler on the
	# cell it has not left yet.
	assert_int(plan.watch_shots.size()).is_equal(2)
	var hit: Array = []
	for shot in plan.watch_shots:
		hit.append(shot.target)
	assert_bool(hit.has(crosser)).is_true()
	assert_bool(hit.has(straggler)).is_true()
	_break_volleys(plan)


# The no-regression pin for the move phase: when nothing interrupts it, the block leaves every mover
# exactly where an order-blind projection always put them. That equality is what makes the rest of
# the pass — attacks, counters, cell effects, the board preview — bit-for-bit unchanged by #412.
func test_an_uninterrupted_walk_leaves_every_mover_at_its_destination() -> void:
	var top := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 60}, false)
	var bottom := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1), {Stats.Stat.MHP: 60}, false)
	_sm.join_squad(bottom, top.squad)
	var top_move := _walk(top)
	var bottom_move := _walk(bottom)
	top.squad._queue_action(top_move)
	top.squad._queue_action(bottom_move)

	var plan := _sm.resolve_plan(top.squad, _board_with([top, bottom]))

	assert_that(PlanResolver.projected_position(top, plan.hypo)).is_equal(top_move.destination)
	assert_that(PlanResolver.projected_position(bottom, plan.hypo)).is_equal(bottom_move.destination)
	assert_bool(top_move.was_halted()).is_false()
	assert_bool(bottom_move.was_halted()).is_false()
