# Intimidation (Action, #61, jobs.md "The ability chassis"): a plannable main-action Will-drain,
# a BaseAction subclass mirroring RescueAction's shape (targeted, outside PlanResolver's pass).
# Mirrors test_rescue_validation.gd / test_main_action_ordering.gd's fixture conventions.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

func _queue_intimidate(intimidator: Unit, victim: Unit) -> IntimidateAction:
	var intimidate := IntimidateAction.new()
	intimidate.init(intimidator, victim)
	intimidator.squad._queue_action(intimidate)
	return intimidate

func test_execute_drains_the_targets_will() -> void:
	var intimidator := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var before := target.unit_instance.get_current_will()

	var intimidate := _queue_intimidate(intimidator, target)
	intimidate.execute()

	assert_int(target.unit_instance.get_current_will()).is_equal(before - Abilities.INTIMIDATION_WILL_DRAIN)

func test_will_cannot_be_drained_below_zero() -> void:
	var intimidator := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	target.unit_instance.set_current_will(1)   # less than the drain amount

	var intimidate := _queue_intimidate(intimidator, target)
	intimidate.execute()

	assert_int(target.unit_instance.get_current_will()).is_equal(0)

func test_is_a_main_action() -> void:
	var intimidator := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	_queue_intimidate(intimidator, target)
	assert_bool(intimidator.has_main_action_queued()).is_true()

func test_move_is_refused_after_an_intimidate_is_queued() -> void:
	# Mirrors test_main_action_ordering.gd's rescue/attack cases — the rule keys on
	# "main action", not a specific type.
	var a := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var d := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	_queue_intimidate(a, d)

	var path: Array[Vector2i] = [a.movement.cell, a.movement.cell + Vector2i(1, 0)]
	var move := MoveAction.new()
	move.init(a, path, null)
	assert_bool(_sm.queue_action(a.squad, move)).is_false()
	assert_int(a.squad.action_queue.size()).is_equal(1)   # only the intimidate; the move was rejected

func test_get_description_names_actor_and_target() -> void:
	var intimidator := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var intimidate := _queue_intimidate(intimidator, target)
	var expected := "%s intimidates %s" % [intimidator.get_unit_name(), target.get_unit_name()]
	assert_str(intimidate.get_description()).is_equal(expected)
