# Rescue re-validation (SquadManager._validate_action_list_once, #33). A queued rescue must
# stay adjacent to a STILL-downed ally; if a re-planned move carries the rescuer out of range,
# or the target is picked up / killed first, the rescue invalidates — and the existing
# invalid-action gate then blocks execution. Mirrors the AoE victim re-derivation debt.
#
# Validation is pure logic (no overlay redraw), so it's safe in this node harness.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# Spawn an ally and put it in the DOWNED state (exactly-lethal hit, zero overkill -> down).
func _downed_ally(cell: Vector2i) -> Unit:
	var ally := H.spawn_solo(self, _sm, PLAYER, cell)
	ally.take_damage(ally.get_current_hp())
	assert_bool(ally.is_downed()).is_true()
	return ally

func _queue_rescue(rescuer: Unit, ally: Unit) -> RescueAction:
	var rescue := RescueAction.new()
	rescue.init(rescuer, ally)
	rescuer.squad._queue_action(rescue)
	return rescue

# Adjacent to a downed ally -> the rescue validates.
func test_rescue_is_valid_when_adjacent_to_a_downed_ally() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := _downed_ally(Vector2i(1, 0))
	var rescue := _queue_rescue(rescuer, ally)

	_sm.validate_squad_plan(rescuer.squad)

	assert_bool(rescue.is_valid).is_true()

# A move that carries the rescuer out of range invalidates the rescue: validation reads the
# PROJECTED (post-move) position, so the body is no longer adjacent.
func test_rescue_invalidated_when_a_move_leaves_the_ally() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := _downed_ally(Vector2i(1, 0))
	var rescue := _queue_rescue(rescuer, ally)

	var move := MoveAction.new()
	var path: Array[Vector2i] = [rescuer.movement.cell, Vector2i(6, 6)]
	move.init(rescuer, path, null)
	rescuer.squad._queue_action(move)

	_sm.validate_squad_plan(rescuer.squad)

	assert_bool(rescue.is_valid).is_false()

# If the target is picked up first (no longer downed), the queued rescue invalidates.
func test_rescue_invalidated_when_target_is_no_longer_down() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := _downed_ally(Vector2i(1, 0))
	var rescue := _queue_rescue(rescuer, ally)

	ally.revive()
	assert_bool(ally.is_downed()).is_false()

	_sm.validate_squad_plan(rescuer.squad)

	assert_bool(rescue.is_valid).is_false()
