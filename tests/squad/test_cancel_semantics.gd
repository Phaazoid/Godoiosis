# Action-queue cancel semantics (#2). Two directions, mirroring what game.gd's
# _on_queue_cancel_requested does at the squad layer:
#
#   * Cancel a MOVE  -> the unit's main action (attack/rescue) goes too. A main action is
#     planned to resolve from the unit's POST-move position (the move-before-main rule), so
#     a move-less attack is stale and nothing re-validates its range. The combo dies together.
#   * Cancel the ATTACK only -> a co-queued move SURVIVES (you can drop the attack and keep
#     the move). The cascade is one-way.
#
# These call the real SquadManager cancel wrappers. They redraw overlays, but on the in-tree
# make_manager graph (real OverlayManager + bare overlay children) the redraws no-op on an
# empty planned_move_by_unit, so they run clean headless.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# Queue a real (non-hold) move for `unit` to the cell one step right, then an attack on `target`.
# Move-then-attack is the only legal order (move precedes the main action).
func _queue_move_then_attack(unit: Unit, target: Unit) -> void:
	var path: Array[Vector2i] = [unit.movement.cell, unit.movement.cell + Vector2i(1, 0)]
	var move := MoveAction.new()
	move.init(unit, path, null)
	unit.squad._queue_action(move)
	unit.squad._queue_action(AttackAction.create(unit, unit.movement.cell, target, target.movement.cell))

# Mirror _on_queue_cancel_requested's "remove the unit's stored main action" step.
func _cancel_main_action(unit: Unit) -> void:
	for action in unit.squad.action_queue.duplicate():
		if action.actor == unit and action.is_main_action():
			_sm.remove_action(unit.squad, action)
			return

# Cancelling a move also cancels the unit's main action — the combo is one order to the player.
func test_cancel_move_also_cancels_main_action() -> void:
	var a := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var d := H.spawn_solo(self, _sm, ENEMY, Vector2i(5, 5))
	_queue_move_then_attack(a, d)
	assert_bool(a.has_main_action_queued()).is_true()

	# The MOVE branch of the cancel handler: cancel the move, then drop the main action.
	_sm.cancel_move_for_unit(a)
	_cancel_main_action(a)

	assert_bool(a.has_main_action_queued()).is_false()
	assert_bool(a.has_valid_move_queued()).is_false()   # only the re-queued hold remains

# The reverse direction is independent: cancelling just the attack keeps a co-queued move.
func test_cancel_attack_keeps_co_queued_move() -> void:
	var a := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var d := H.spawn_solo(self, _sm, ENEMY, Vector2i(5, 5))
	_queue_move_then_attack(a, d)

	_cancel_main_action(a)

	assert_bool(a.has_main_action_queued()).is_false()
	assert_bool(a.has_valid_move_queued()).is_true()    # the move is untouched
