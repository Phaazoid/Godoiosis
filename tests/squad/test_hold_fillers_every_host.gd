# A squad grows its hold-position fillers when its plan opens, whoever hosts it (#46).
#
# The filler -- a "stay where you stand" MOVE for every member not ordered to move -- is a RULE: the
# cohesion validator judges it, so it decides whether a plan is legal. It used to be queued by
# game.gd's squad_became_active handler, which meant a board without game.gd (the headless Play API,
# and every suite on squad_fixtures.make_manager) never grew one, and the two hosts disagreed about
# whether the same plan was legal (#103's whole reproduction gap). SquadManager queues it now.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


# Leader at (0,0), member beside it.
func _pair() -> Array[Unit]:
	var leader := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var mate := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1))
	_sm.join_squad(mate, leader.squad)
	var pair: Array[Unit] = [leader, mate]
	return pair


func _step(unit: Unit) -> MoveAction:
	var path: Array[Vector2i] = [unit.movement.cell, unit.movement.cell + Vector2i(1, 0)]
	var move := MoveAction.new()
	move.init(unit, path, null)
	return move


func _holds_of(squad: Squad, unit: Unit) -> int:
	var count := 0
	for action: BaseAction in squad.action_queue:
		if action.actor == unit and action is MoveAction and (action as MoveAction).is_hold_position:
			count += 1
	return count


func _holds(squad: Squad) -> int:
	var count := 0
	for action: BaseAction in squad.action_queue:
		if action is MoveAction and (action as MoveAction).is_hold_position:
			count += 1
	return count


func test_a_squad_grows_a_hold_for_every_member_not_moving_when_its_plan_opens() -> void:
	var pair := _pair()
	var squad: Squad = pair[0].squad

	assert_bool(_sm.queue_action(squad, _step(pair[0]))).override_failure_message(
		"fixture: the leader's step was refused").is_true()

	assert_int(_holds_of(squad, pair[1])).override_failure_message(
		"the member standing still was given no hold filler -- the plan opened without it").is_equal(1)
	assert_int(_holds_of(squad, pair[0])).override_failure_message(
		"the leader, who has a real move, was also given a hold").is_equal(0)


# Before the re-emit, so a listener reading the plan on squad_became_active reads the whole of it --
# the Play API's re-resolve is one (PlaySession._on_plan_opened).
func test_the_fillers_are_in_the_queue_before_the_plan_is_announced() -> void:
	var pair := _pair()
	var squad: Squad = pair[0].squad
	var seen: Array[int] = [-1]
	_sm.squad_became_active.connect(func(s: Squad, _a: BaseAction) -> void:
		seen[0] = _holds(s))

	_sm.queue_action(squad, _step(pair[0]))

	assert_int(seen[0]).override_failure_message(
		"squad_became_active was never heard, so this case proves nothing").is_not_equal(-1)
	assert_int(seen[0]).override_failure_message(
		"the plan was announced before its hold filler was queued").is_equal(1)


# The AI's threat preview queues the real archetypes' orders and rolls them back (#710): it draws
# nothing and must leave nothing, so it grows no fillers.
func test_the_threat_preview_grows_no_fillers() -> void:
	var pair := _pair()
	var squad: Squad = pair[0].squad
	_sm.previewing = true
	var queued := _sm.queue_action(squad, _step(pair[0]))
	_sm.previewing = false

	assert_bool(queued).override_failure_message("fixture: the leader's step was refused").is_true()
	assert_int(_holds(squad)).override_failure_message(
		"the preview's plan grew hold fillers").is_equal(0)
