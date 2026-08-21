# Group Move queues N orders as ONE player action. SquadManager.batching suppresses the per-order
# fan-out (re-validate, redraw, and the action_queued signal that drives a full queue-panel +
# overlay rebuild) and runs it once at the end — a 5-member move was paying for 12 full plan
# resolutions per click, 11 of which no frame could ever have rendered.
#
# The whole optimisation rests on one property: skipping those intermediate passes must not change
# the RESULT. That is what this suite pins. If a future order type makes queueing order-dependent,
# these fail rather than the panel quietly going stale.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")


func _build_squad_board(member_count: int) -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(0, 0, 8, 3))

	var leader: Unit = BB.spawn(board, H.make_unit_data({Stats.Stat.LDR: 8}, Team.Faction.ENEMY), Vector2i(0, 0))
	leader.equipped_weapon = H.make_weapon()
	for i in range(member_count):
		var member: Unit = BB.spawn(board, H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(i + 1, 0))
		member.equipped_weapon = H.make_weapon()
		board.squad_manager.join_squad(member, leader.squad)

	board["leader"] = leader
	return board


func _context(board: Dictionary) -> BoardContext:
	var units: Array[Unit] = []
	for child in board.units_root.get_children():
		units.append(child as Unit)
	return BoardContext.new(board.grid, units, board.squad_manager)


# Everything observable about the queued plan, in queue order.
func _plan_signature(squad: Squad) -> Array:
	var sig: Array = []
	for a in squad.action_queue:
		var dest := str(a.get_destination()) if a.action_type == BaseAction.ActionType.MOVE else "-"
		sig.append("%s|%d|%s|%s" % [a.actor.get_unit_name(), a.action_type, dest, str(a.is_valid)])
	return sig


func test_batched_group_move_matches_the_unbatched_result() -> void:
	var dest := Vector2i(3, 0)

	# Batched: the real queue_group_move path.
	var a: Dictionary = _build_squad_board(2)
	a.squad_manager.queue_group_move(a.leader.squad, dest, _context(a))
	var batched := _plan_signature(a.leader.squad)

	# Unbatched: same solver output, queued one at a time with the full fan-out each.
	var b: Dictionary = _build_squad_board(2)
	for move in GroupMoveSolver.plan(b.leader.squad, dest, _context(b)):
		b.squad_manager.queue_action(b.leader.squad, move)
	b.squad_manager.validate_squad_plan(b.leader.squad)
	var unbatched := _plan_signature(b.leader.squad)

	assert_array(batched).is_equal(unbatched)
	assert_int(batched.size()).is_greater(0)


func test_batching_flag_is_cleared_afterwards() -> void:
	# A leaked flag would silently mute every later single-unit order's repaint.
	var board: Dictionary = _build_squad_board(2)
	assert_bool(board.squad_manager.batching).is_false()
	board.squad_manager.queue_group_move(board.leader.squad, Vector2i(3, 0), _context(board))
	assert_bool(board.squad_manager.batching).is_false()


func test_batched_orders_are_still_validated() -> void:
	# Skipping the per-order validation must not skip validation — the batch validates once at the
	# end, so every queued order still carries a real is_valid verdict.
	var board: Dictionary = _build_squad_board(2)
	board.squad_manager.queue_group_move(board.leader.squad, Vector2i(3, 0), _context(board))

	var squad: Squad = board.leader.squad
	assert_int(squad.action_queue.size()).is_greater(0)
	for action in squad.action_queue:
		assert_bool(action.is_valid).is_true()


func test_exactly_one_repaint_notification_per_group_move() -> void:
	# action_queued still fires per order — cheap per-unit listeners (the projected-ghost swap)
	# need every one. What's coalesced is the EXPENSIVE squad-level repaint, which game.gd runs
	# only when `batching` is false. This models that listener: N orders, one repaint.
	var board: Dictionary = _build_squad_board(2)
	var sm: SquadManager = board.squad_manager
	var repaints := [0]
	sm.squad_action_queued.connect(func(_s, _a):
		if not sm.batching:
			repaints[0] += 1)

	sm.queue_group_move(board.leader.squad, Vector2i(3, 0), _context(board))

	assert_int(repaints[0]).is_equal(1)


func test_a_lone_order_still_notifies_immediately() -> void:
	# The batch flag must not change the ordinary single-order path — no deferral, no coalescing.
	var board: Dictionary = _build_squad_board(1)
	var sm: SquadManager = board.squad_manager
	var repaints := [0]
	sm.squad_action_queued.connect(func(_s, _a):
		if not sm.batching:
			repaints[0] += 1)

	var reach: Dictionary = RulesService.compute_move_range(board.leader, _context(board))
	var path: Array[Vector2i] = RulesService.reconstruct_path(reach.came_from, board.leader.movement.cell, Vector2i(1, 1))
	var move := MoveAction.new()
	move.init(board.leader, path, null)
	sm.queue_action(board.leader.squad, move)

	assert_int(repaints[0]).is_greater(0)
	assert_bool(sm.batching).is_false()


# ==============================================================================
#  All or nothing (#103) — the REFUSED half (#443)
# ==============================================================================
# The rollback used to ask one question: is any queued move INVALID? An order the Law #3
# chokepoint refuses never reaches the queue at all, so that scan cannot see it — it is not an
# invalid move there, it is an ABSENT one. Move-before-main is the refusal that actually fires:
# a leader holding a main action has its own move dropped while every follower's is queued, at
# offsets solved for a destination the leader never reaches. The squad marched off without it.
#
# These drive the real queue_group_move rather than the menu, because the menu is only one of the
# doors — the Play API and the AI's group-move path reach the same function directly.

# Rally is the cheapest real main action to author: it only needs Will to restore.
func _lock_a_main_action(sm: SquadManager, unit: Unit) -> void:
	unit.unit_instance.set_current_will(1)
	var rally := RallyAction.new()
	rally.init(unit)
	assert_bool(sm.queue_action(unit.squad, rally)).is_true()
	assert_bool(unit.has_main_action_queued()).is_true()


func test_group_move_is_refused_whole_when_the_leader_holds_a_main_action() -> void:
	var board: Dictionary = _build_squad_board(1)
	var sm: SquadManager = board.squad_manager
	var leader: Unit = board.leader
	_lock_a_main_action(sm, leader)

	var queued: bool = sm.queue_group_move(leader.squad, Vector2i(3, 0), _context(board))

	assert_bool(queued) \
		.override_failure_message("queue_group_move reported success for a formation its leader was refused") \
		.is_false()


func test_group_move_is_refused_whole_when_a_MEMBER_holds_a_main_action() -> void:
	# #461 closed this at the MENU, which is one door: the AI and the Play API reach
	# queue_group_move directly and must still be refused whole. Same refusal as the leader case
	# above, one member along -- plan() authors a move for everybody and queue_action turns this
	# one down, so the count check (#443's REFUSED half) is what sees it, not the invalid scan.
	var board: Dictionary = _build_squad_board(2)
	var sm: SquadManager = board.squad_manager
	var leader: Unit = board.leader
	_lock_a_main_action(sm, leader.squad.get_members()[1])

	var queued: bool = sm.queue_group_move(leader.squad, Vector2i(3, 0), _context(board))

	assert_bool(queued) \
		.override_failure_message("queue_group_move reported success for a formation a MEMBER was refused") \
		.is_false()
	assert_bool(leader.has_action_type_queued(BaseAction.ActionType.MOVE)) \
		.override_failure_message("the leader kept a move from a batch its squadmate broke") \
		.is_false()


func test_a_refused_group_move_leaves_nobody_walking() -> void:
	# The load-bearing assertion: a partial formation is what strands the leader, and it is
	# invisible in the return value alone. Hold-position moves are not walking (Unit treats them
	# as no move at all), so this reads the PROJECTION rather than the queue's shape.
	var board: Dictionary = _build_squad_board(2)
	var sm: SquadManager = board.squad_manager
	var leader: Unit = board.leader
	_lock_a_main_action(sm, leader)

	var before := {}
	for member in leader.squad.get_members():
		before[member] = member.movement.cell

	sm.queue_group_move(leader.squad, Vector2i(3, 0), _context(board))

	for member in leader.squad.get_members():
		assert_vector(member.get_projected_destination()) \
			.override_failure_message("%s was left walking after the batch was refused" % member.get_unit_name()) \
			.is_equal(before[member])
		assert_bool(member.has_action_type_queued(BaseAction.ActionType.MOVE)) \
			.override_failure_message("%s kept a real move from a refused batch" % member.get_unit_name()) \
			.is_false()


func test_the_rollback_does_not_eat_the_main_action_that_caused_it() -> void:
	# The rollback cancels MOVES. The order the player actually queued has to survive it, or the
	# refusal costs them their turn instead of costing them nothing.
	var board: Dictionary = _build_squad_board(1)
	var sm: SquadManager = board.squad_manager
	var leader: Unit = board.leader
	_lock_a_main_action(sm, leader)

	sm.queue_group_move(leader.squad, Vector2i(3, 0), _context(board))

	assert_bool(leader.has_main_action_queued()).is_true()


func test_an_unreachable_leader_destination_reports_failure() -> void:
	# Same rule one step earlier: the solver authors nothing when the leader cannot path to the
	# goal, and a return of true would say a formation was queued that never existed.
	var board: Dictionary = _build_squad_board(1)
	var sm: SquadManager = board.squad_manager

	# Off the painted 8x3 rect entirely — no path, so plan() returns an empty batch.
	var queued: bool = sm.queue_group_move(board.leader.squad, Vector2i(30, 30), _context(board))

	assert_bool(queued).is_false()


func test_a_clean_group_move_still_reports_success() -> void:
	# Positive control: the two new refusals must not swallow the ordinary case.
	var board: Dictionary = _build_squad_board(2)
	var queued: bool = board.squad_manager.queue_group_move(board.leader.squad, Vector2i(3, 0), _context(board))

	assert_bool(queued).is_true()
	assert_vector(board.leader.get_projected_destination()).is_equal(Vector2i(3, 0))
