# The "move before main action" rule (#33 / will-and-death.md). A unit may move, THEN take
# one main action (attack, rescue, ...) — never the reverse. Once a main action is locked in,
# movement is refused, so an attack always resolves from the unit's FINAL position: no
# attack-then-flee, no dodging the counter by stepping away.
#
# The action menu hides the Move option once a main action is queued; SquadManager.queue_action
# is the Law #3 backstop tested here (it also covers the future AI, which only orders through it).
#
# These tests exercise only the REJECTION path of queue_action, which returns before it
# redraws overlays — so, like the rest of this suite, they never touch the overlay/grid
# wrappers the fixture notes are out of scope.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

func _make_move(unit: Unit) -> MoveAction:
	var path: Array[Vector2i] = [unit.movement.cell, unit.movement.cell + Vector2i(1, 0)]
	var move := MoveAction.new()
	move.init(unit, path, null)
	return move

# A locked-in attack refuses a follow-up move; the move is rejected and never lands.
func test_move_is_refused_after_an_attack_is_queued() -> void:
	var a := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var d := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))

	# Nothing locked yet -> the rule has no reason to refuse.
	assert_bool(a.has_main_action_queued()).is_false()

	a.squad._queue_action(AttackAction.create(a, a.movement.cell, d, d.movement.cell))
	assert_bool(a.has_main_action_queued()).is_true()

	var move := _make_move(a)
	assert_bool(_sm.queue_action(a.squad, move)).is_false()
	assert_int(a.squad.action_queue.size()).is_equal(1)   # only the attack; the move was rejected

# The rule keys on "main action", not specifically attack: a queued rescue locks out move too.
func test_move_is_refused_after_a_rescue_is_queued() -> void:
	var a := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))

	var rescue := RescueAction.new()
	rescue.init(a, ally)
	a.squad._queue_action(rescue)
	assert_bool(a.has_main_action_queued()).is_true()

	var move := _make_move(a)
	assert_bool(_sm.queue_action(a.squad, move)).is_false()
	assert_int(a.squad.action_queue.size()).is_equal(1)   # only the rescue; the move was rejected
