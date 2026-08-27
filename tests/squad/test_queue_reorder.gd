# The queue-panel drag's other end (#412). Queue order is the pass's clock — resolve_plan walks
# squad.action_queue and nothing else — so resequencing rows has to resequence the QUEUE, for every
# type the panel can drag and without disturbing anything it cannot.
#
# Attacks have been draggable since the elemental-combo work and had no suite at all; moves and the
# side-channel verbs join them on one seam here. Guard is the case with teeth TODAY:
# PlanResolver._guard_for takes the FIRST match in plan.guards, so two stacked Guards' row order
# decides who absorbs — and until now the player had no way to touch it.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


# Three units in ONE squad, side by side. Every reorder question is about orders sharing a queue,
# and a squad is the only thing that has one. The leader's LDR is read OFF the capacity rule rather
# than typed, so retuning MEMBER_LDR_COST cannot silently make this an over-capacity squad.
func _trio() -> Array[Unit]:
	var ldr_for_three: int = Squad.MEMBER_LDR_COST * 2
	var a := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: ldr_for_three})
	var b := H.spawn_unit(self, PLAYER, Vector2i(1, 0))
	var c := H.spawn_unit(self, PLAYER, Vector2i(2, 0))
	_sm.join_squad(b, a.squad)
	_sm.join_squad(c, a.squad)
	var trio: Array[Unit] = [a, b, c]
	return trio


func _move(unit: Unit) -> MoveAction:
	var path: Array[Vector2i] = [unit.movement.cell, unit.movement.cell + Vector2i(0, 1)]
	var move := MoveAction.new()
	move.init(unit, path, null)
	return move


func _hold(unit: Unit) -> MoveAction:
	var hold := MoveAction.new()
	hold.init_hold_position(unit, null)
	return hold


func _guard(blocker: Unit, ward: Unit) -> GuardAction:
	var order := GuardAction.new()
	order.init(blocker, ward)
	return order


# The queue's own answer to "who is ordered to do this, in what order" — the fact the drag rewrites.
func _actors_of(squad: Squad, type: BaseAction.ActionType) -> Array[Unit]:
	var actors: Array[Unit] = []
	for action in squad.action_queue:
		if action.action_type == type and action.is_reorderable():
			actors.append(action.actor)
	return actors


func test_moves_follow_the_dragged_row_order() -> void:
	var units := _trio()
	var squad: Squad = units[0].squad
	for unit in units:
		squad._queue_action(_move(unit))

	squad.reorder_by_actor(BaseAction.ActionType.MOVE, [units[2], units[0], units[1]])

	assert_array(_actors_of(squad, BaseAction.ActionType.MOVE)) \
		.is_equal([units[2], units[0], units[1]])


func test_attacks_follow_the_dragged_row_order() -> void:
	var units := _trio()
	var squad: Squad = units[0].squad
	var mark := H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(0, 4))
	for unit in units:
		squad._queue_action(H.stamped_attack(unit, mark))

	squad.reorder_by_actor(BaseAction.ActionType.ATTACK, [units[1], units[2], units[0]])

	assert_array(_actors_of(squad, BaseAction.ActionType.ATTACK)) \
		.is_equal([units[1], units[2], units[0]])


# The side-channel half, and the one that already changes an outcome: stacked Guards absorb in
# plan.guards order, which resolve_plan builds by walking this queue.
func test_guards_follow_the_dragged_row_order() -> void:
	var units := _trio()
	var squad: Squad = units[0].squad
	squad._queue_action(_guard(units[0], units[2]))
	squad._queue_action(_guard(units[1], units[2]))

	squad.reorder_by_actor(BaseAction.ActionType.GUARD, [units[1], units[0]])

	assert_array(_actors_of(squad, BaseAction.ActionType.GUARD)).is_equal([units[1], units[0]])


# A section drag can only speak for its own section. Every other order keeps the slot it had —
# including the ones a re-timed block moves past.
func test_reordering_one_type_leaves_every_other_order_where_it_was() -> void:
	var units := _trio()
	var squad: Squad = units[0].squad
	var guard := _guard(units[0], units[2])
	squad._queue_action(_move(units[0]))
	squad._queue_action(guard)
	squad._queue_action(_move(units[1]))

	squad.reorder_by_actor(BaseAction.ActionType.MOVE, [units[1], units[0]])

	assert_array(_actors_of(squad, BaseAction.ActionType.MOVE)).is_equal([units[1], units[0]])
	# The Guard neither moved nor was swallowed by the re-inserted move block.
	assert_int(squad.action_queue.size()).is_equal(3)
	assert_object(squad.action_queue[2]).is_same(guard)


# The hold-position fillers are not orders anybody gave (BaseAction.batch_id 0), cross nothing, and
# must not be dragged OR displaced — the block re-inserts at the first REAL move's slot.
func test_a_hold_position_filler_never_moves() -> void:
	var units := _trio()
	var squad: Squad = units[0].squad
	var hold := _hold(units[1])
	squad._queue_action(hold)
	squad._queue_action(_move(units[0]))
	squad._queue_action(_move(units[2]))

	squad.reorder_by_actor(BaseAction.ActionType.MOVE, [units[2], units[0]])

	assert_object(squad.action_queue[0]).is_same(hold)
	assert_array(_actors_of(squad, BaseAction.ActionType.MOVE)).is_equal([units[2], units[0]])
	assert_bool(hold.is_reorderable()).is_false()


# The LIFO undo (#228) pops the newest GESTURE, and it finds it by batch_id, not by queue position.
# Reordering is a re-timing, never a re-authoring, so the same gesture must still come back.
func test_the_undo_gesture_survives_a_reorder() -> void:
	var units := _trio()
	var squad: Squad = units[0].squad
	assert_bool(_sm.queue_action(squad, _move(units[0]))).is_true()
	var newest := _move(units[1])
	assert_bool(_sm.queue_action(squad, newest)).is_true()

	squad.reorder_by_actor(BaseAction.ActionType.MOVE, [units[1], units[0]])

	var gesture := _sm.last_gesture_actions(squad)
	assert_int(gesture.size()).is_equal(1)
	assert_object(gesture[0]).is_same(newest)


# A counter is derived every pass and never enters the queue, so its row is inert by construction
# rather than by the panel remembering to skip it.
func test_a_counter_is_never_reorderable() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var mark := H.spawn_solo(self, _sm, Team.Faction.ENEMY, Vector2i(0, 1))
	var counter := CounterAttackAction.new()
	counter.init_counter(mark, attacker, mark.movement.cell, H.stamped_attack(attacker, mark))

	assert_bool(counter.is_reorderable()).is_false()
