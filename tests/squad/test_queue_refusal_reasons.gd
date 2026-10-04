# The order chokepoint says WHY it refused (#662). SquadManager.try_queue_action answers "" when it
# queues and the refusing gate's own reason when it does not, and queue_action is derived from it.
#
# One case per gate, each comparing the answer against the SOURCE of the reason rather than a
# retyped sentence: the standing check (RulesService.standing_block_reason), the action's own
# requirement (BaseAction.actor_block_reason) and the plan-context gate (the candidate's own
# validation errors). A refusal that came back "" would read as ACCEPTED to every caller, so each case
# also asserts the reason is non-empty and the order never landed.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const ACTIONS_DIR := "res://Classes/actions/"

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

func _move(unit: Unit) -> MoveAction:
	var path: Array[Vector2i] = [unit.movement.cell, unit.movement.cell + Vector2i(0, 1)]
	var move := MoveAction.new()
	move.init(unit, path, null)
	return move

func _refused(reason: String, action: BaseAction, squad: Squad, what: String) -> void:
	assert_str(reason).override_failure_message("%s: refused with no reason" % what).is_not_empty()
	assert_bool(squad.action_queue.has(action)).override_failure_message(
		"%s: the refused order landed in the queue anyway" % what).is_false()

# ==============================================================================

func test_a_downed_actor_is_refused_with_the_standing_reason() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	unit.lifecycle_state = Unit.LifecycleState.DOWNED
	var move := _move(unit)
	var reason := _sm.try_queue_action(unit.squad, move)
	_refused(reason, move, unit.squad, "a downed actor")
	assert_str(reason).is_equal(RulesService.standing_block_reason(unit))

func test_a_move_after_a_main_action_is_refused_with_the_moves_own_reason() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var aim := AttackAction.declare(unit, unit.movement.cell, foe.movement.cell)
	assert_str(_sm.try_queue_action(unit.squad, aim)).override_failure_message(
		"precondition: the main action did not queue").is_empty()
	var move := _move(unit)
	var reason := _sm.try_queue_action(unit.squad, move)
	_refused(reason, move, unit.squad, "move-before-main")
	assert_str(reason).is_equal(move.actor_block_reason())

func test_a_locked_two_handed_attack_is_refused_with_the_verb_locks_reason() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var weapon := H.make_weapon(3)
	weapon.template.two_handed = true
	unit.equipped_weapon = weapon
	unit.unit_instance.limbs[UnitInstance.LimbSlot.ARM_L].state = UnitInstance.LimbState.EMPTY
	var aim := AttackAction.declare(unit, unit.movement.cell, foe.movement.cell)
	var reason := _sm.try_queue_action(unit.squad, aim)
	_refused(reason, aim, unit.squad, "the two-handed verb lock")
	assert_str(reason).is_equal(unit.wield_block_reason())

func test_an_aim_at_bare_ground_is_refused_with_the_candidates_own_validation_error() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var aim := AttackAction.declare(unit, unit.movement.cell, Vector2i(1, 0))   # nobody stands there
	var reason := _sm.try_queue_action(unit.squad, aim)
	_refused(reason, aim, unit.squad, "a whiffed aim")
	assert_str(reason).is_equal("; ".join(aim.validation_errors))

func test_an_accepted_order_answers_empty_and_lands_in_the_queue() -> void:
	var unit := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var aim := AttackAction.declare(unit, unit.movement.cell, foe.movement.cell)
	assert_str(_sm.try_queue_action(unit.squad, aim)).is_empty()
	assert_bool(unit.squad.action_queue.has(aim)).is_true()

# The derived bool is only safe while nothing overrides it: an action that answered actor_can_perform
# on its own could refuse with no reason, and the chokepoint, which asks the reason, would queue it.
func test_no_action_overrides_actor_can_perform() -> void:
	var overriders: Array[String] = []
	var reasoners := 0
	var scanned := 0
	for file: String in DirAccess.get_files_at(ACTIONS_DIR):
		if not file.ends_with(".gd"):
			continue
		scanned += 1
		var text := FileAccess.get_file_as_string(ACTIONS_DIR + file)
		if file != "BaseAction.gd" and text.contains("func actor_can_perform"):
			overriders.append(file)
		if file != "BaseAction.gd" and text.contains("func actor_block_reason"):
			reasoners += 1
	assert_int(reasoners).override_failure_message(
		"non-vacuity: no action under %s declares a reason -- is the scan pointed at the right folder? (%d files)" % [
			ACTIONS_DIR, scanned]).is_greater(0)
	assert_array(overriders).override_failure_message(
		"these override actor_can_perform -- override actor_block_reason instead: %s" % str(overriders)).is_empty()
