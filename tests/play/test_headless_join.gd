# The Play API's `join` asks the game's own formation rule (#46). It used to hand-roll range, faction
# and orders, and so missed two of the clauses every game door asks: room in the squad and both sides
# standing. A playtester grew a squad past its capacity headlessly (the bridge log grandfathered it,
# "over capacity (4/2)"), a squad the game could never have formed.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER


func _data(unit_name: String) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, PLAYER)


# A leader and a recruit standing side by side, with the session held so it hears the board.
func _pair(root_name: String) -> Dictionary:
	var b := BoardBuilder.build(self, root_name)
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var leader: Unit = BoardBuilder.spawn(b, _data("Leader"), Vector2i(0, 0))
	var recruit: Unit = BoardBuilder.spawn(b, _data("Recruit"), Vector2i(1, 0))
	return {"board": b, "leader": leader, "recruit": recruit}


func test_a_full_squad_refuses_a_join_in_the_games_words() -> void:
	var f := _pair("FullSquadJoinRoot")
	var leader: Unit = f.leader
	var recruit: Unit = f.recruit
	leader.unit_instance.stats[Stats.Stat.LDR] = 0   # leads nobody but itself
	var sess = PlaySession.new(f.board)
	assert_int(leader.squad.members.size()).override_failure_message(
			"fixture: the leader's squad has room, so this case cannot see a capacity refusal") \
		.is_greater_equal(leader.squad.max_size())

	var res: Dictionary = sess.join(sess.handle_for(recruit), sess.handle_for(leader))

	assert_bool(res.ok).override_failure_message("a join into a full squad was accepted headlessly").is_false()
	assert_str(str(res.get("error", ""))).override_failure_message(
			"the refusal did not give the game's reason: %s" % str(res.get("error", ""))).contains("full")
	assert_bool(recruit.squad == leader.squad).override_failure_message("the recruit joined anyway").is_false()


func test_a_downed_recruit_is_refused_in_the_games_words() -> void:
	var f := _pair("DownedJoinRoot")
	var leader: Unit = f.leader
	var recruit: Unit = f.recruit
	var sess = PlaySession.new(f.board)
	recruit.take_damage(recruit.get_current_hp())
	assert_bool(recruit.is_downed()).override_failure_message("fixture: the recruit did not go down").is_true()

	var res: Dictionary = sess.join(sess.handle_for(recruit), sess.handle_for(leader))

	assert_bool(res.ok).override_failure_message("a downed body was recruited headlessly").is_false()
	assert_str(str(res.get("error", ""))).override_failure_message(
			"the refusal did not give the game's reason: %s" % str(res.get("error", ""))).contains("is down")


# And the door stays open where the game's is: a standing recruit in range of a leader with room.
func test_a_legal_join_still_joins() -> void:
	var f := _pair("LegalJoinRoot")
	var leader: Unit = f.leader
	var recruit: Unit = f.recruit
	var sess = PlaySession.new(f.board)
	assert_int(leader.squad.max_size()).override_failure_message(
			"fixture: the leader leads nobody, so a legal join cannot be shown").is_greater(1)

	var res: Dictionary = sess.join(sess.handle_for(recruit), sess.handle_for(leader))

	assert_bool(res.ok).override_failure_message("a legal join was refused: %s" % str(res.get("error", ""))).is_true()
	assert_bool(recruit.squad == leader.squad).override_failure_message("the recruit did not join").is_true()
