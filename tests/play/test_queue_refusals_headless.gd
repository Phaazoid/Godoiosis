# The headless Play API reports the order chokepoint's own reason (#662), never a guessed one.
#
# Until #662 every refusal at SquadManager.queue_action came back as one of two fixed sentences:
# "another squad is already active" and "already has a main action". The chokepoint never checked the
# first (only the menu did, so headlessly a second squad silently took the activation) and the second
# is never a refusal at all (a second main action displaces the first). Each case here compares the
# reply against the reason's SOURCE, so it does not pin any wording.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


func _board() -> Dictionary:
	var b := BoardBuilder.build(self, "QueueRefusalsRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 14, 14))
	return b


func test_a_move_after_a_main_action_is_refused_with_the_moves_own_reason() -> void:
	var b := _board()
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(1, 0))
	hero.add_item(H.make_weapon(3))
	var sess = PlaySession.new(b)
	var handle: String = sess.handle_for(hero)
	var attacked: Dictionary = sess.queue_attack(handle, foe.movement.cell)
	assert_bool(attacked.ok).override_failure_message(
		"precondition: the main action did not queue: %s" % str(attacked.get("error", ""))).is_true()

	var moved: Dictionary = sess.queue_move(handle, Vector2i(0, 1))
	assert_bool(moved.ok).override_failure_message("a move after a main action was accepted").is_false()
	var probe := MoveAction.new()
	var path: Array[Vector2i] = [hero.movement.cell, Vector2i(0, 1)]
	probe.init(hero, path, null)
	var expected := probe.actor_block_reason()
	assert_str(expected).override_failure_message("precondition: the move carries no reason").is_not_empty()
	assert_str(str(moved.error)).contains(expected)


func test_a_second_squad_cannot_order_while_the_first_holds_orders() -> void:
	var b := _board()
	var first: Unit = BoardBuilder.spawn(b, _data("First", PLAYER), Vector2i(0, 0))
	var second: Unit = BoardBuilder.spawn(b, _data("Second", PLAYER), Vector2i(6, 6))
	BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(11, 11))
	var sess = PlaySession.new(b)
	assert_bool((sess.queue_move(sess.handle_for(first), Vector2i(0, 1)) as Dictionary).ok).is_true()

	var refused: Dictionary = sess.queue_move(sess.handle_for(second), Vector2i(6, 7))
	assert_bool(refused.ok).override_failure_message(
		"a second squad was ordered while the first held orders").is_false()
	assert_object(sess.squad_manager.active_squad).override_failure_message(
		"the second squad took the activation").is_same(first.squad)
	assert_bool(second.squad.action_queue.is_empty()).override_failure_message(
		"the refused order landed in the second squad's queue").is_true()

	# Not vacuous: the same move is legal once the first squad's orders are gone.
	sess.cancel(sess.handle_for(first))
	var after: Dictionary = sess.queue_move(sess.handle_for(second), Vector2i(6, 7))
	assert_bool(after.ok).override_failure_message(
		"the second squad's move was illegal on its own: %s" % str(after.get("error", ""))).is_true()


func test_a_rev_with_nothing_that_revs_is_refused_through_the_chokepoint() -> void:
	var b := _board()
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(8, 8))
	var sess = PlaySession.new(b)
	assert_bool(hero.can_rev_weapon()).override_failure_message(
		"precondition: the unarmed hero can rev").is_false()
	var revved: Dictionary = sess.rev(sess.handle_for(hero))
	assert_bool(revved.ok).is_false()
	var probe := RevAction.new()
	probe.init(hero)
	assert_str(str(revved.error)).contains(probe.actor_block_reason())
	assert_bool(hero.squad.action_queue.is_empty()).is_true()
