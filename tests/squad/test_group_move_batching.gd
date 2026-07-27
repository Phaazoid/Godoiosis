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
