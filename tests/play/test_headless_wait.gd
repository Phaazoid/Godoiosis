# The ring's Wait, headlessly (#1236). The parity ledger found docs/play-api.md promising a `wait`
# that never existed. It spends the squad's turn through the door MainActionMenu's WAIT arm uses,
# and is offered when the ring offers it: a squad that has not acted, with no plan open.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


func _setup(root_name: String) -> Dictionary:
	var b := BoardBuilder.build(self, root_name)
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 12, 12))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(6, 0))
	return {"sess": PlaySession.new(b), "hero": hero, "foe": foe}


func test_wait_spends_the_squads_turn() -> void:
	var s := _setup("WaitRoot")
	var sess = s.sess
	var hero: Unit = s.hero
	var h: String = sess.handle_for(hero)

	var r: Dictionary = sess.wait(h)

	assert_bool(r.ok).override_failure_message("wait was refused: %s" % str(r)).is_true()
	assert_bool(hero.squad.has_acted).is_true()
	# What a spent squad means everywhere else: it takes no more orders this turn.
	var moved: Dictionary = sess.queue_move(h, Vector2i(1, 0))
	assert_bool(moved.ok).override_failure_message("a squad that waited still took an order").is_false()


func test_wait_is_refused_while_the_squad_has_orders_queued() -> void:
	var s := _setup("WaitQueuedRoot")
	var sess = s.sess
	var hero: Unit = s.hero
	var h: String = sess.handle_for(hero)
	var moved: Dictionary = sess.queue_move(h, Vector2i(1, 0))
	assert_bool(moved.ok).override_failure_message("precondition: the move was refused: %s" % str(moved)).is_true()

	var r: Dictionary = sess.wait(h)

	assert_bool(r.ok).override_failure_message("wait spent a squad with a plan open").is_false()
	assert_bool(hero.squad.has_acted).is_false()


func test_wait_is_refused_off_the_active_faction() -> void:
	var s := _setup("WaitFactionRoot")
	var sess = s.sess
	var foe: Unit = s.foe

	var r: Dictionary = sess.wait(sess.handle_for(foe))

	assert_bool(r.ok).override_failure_message("the enemy waited on the player's turn").is_false()
	assert_bool(foe.squad.has_acted).is_false()
