# Guard (#414) through the headless Play API, on a REAL painted board.
#
# Two things only this surface pins. The `guard` verb itself — every other side-channel main action
# has one, and without it the AI-facing API cannot express the mechanic at all. And the SPEND in
# play_session._apply_attack, which is a hand-copied twin of AttackAction.execute's: two
# implementations of one rule, so the twin needs its own case or it drifts the first time either
# side is edited (the went_downed trap, CLAUDE.md's execution-order bullet).
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


func _arm(unit: Unit) -> void:
	# Null pattern -> Reach's adjacency fallback: reach 1, the aimed cell alone affected.
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = WeaponAttackData.new()
	t.main_attack.power = 4
	unit.add_item(WeaponInstance.make(t))


# A foe beside a ward, with the ward's bodyguard standing on the ward's far side. Everyone has room:
# the foe can only reach the ward, so the only way the blocker gets hurt is by blocking.
func _guard_board() -> Dictionary:
	var b := BoardBuilder.build(self, "GuardRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 10, 10))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(0, 0))
	var ward: Unit = BoardBuilder.spawn(b, _data("Ward", PLAYER), Vector2i(1, 0))
	var blocker: Unit = BoardBuilder.spawn(b, _data("Blocker", PLAYER), Vector2i(2, 0))
	_arm(foe)
	var sess = PlaySession.new(b)
	return {"sess": sess, "foe": foe, "ward": ward, "blocker": blocker}


func test_the_guard_verb_queues_an_order() -> void:
	var s := _guard_board()
	var sess = s.sess
	var res: Dictionary = sess.guard(sess.handle_for(s.blocker), sess.handle_for(s.ward))
	assert_bool(res.ok).is_true()
	assert_bool((s.blocker as Unit).has_action_type_queued(BaseAction.ActionType.GUARD)).is_true()


func test_the_verb_refuses_a_unit_out_of_range() -> void:
	var s := _guard_board()
	var sess = s.sess
	# The foe is two cells from the blocker AND an enemy -- both halves of the candidate rule.
	var res: Dictionary = sess.guard(sess.handle_for(s.blocker), sess.handle_for(s.foe))
	assert_bool(res.ok).is_false()


func test_a_headless_pass_moves_the_hit_onto_the_blocker_and_spends_the_ward() -> void:
	var s := _guard_board()
	var sess = s.sess
	var ward: Unit = s.ward
	var blocker: Unit = s.blocker
	blocker.arm_guard(ward, blocker.get_guard_range())
	var ward_hp := ward.get_current_hp()
	var blocker_hp := blocker.get_current_hp()

	sess.end_turn()   # hand the board to the enemy so its attack is the one that resolves
	var queued: Dictionary = sess.queue_attack(sess.handle_for(s.foe), Vector2i(1, 0))
	assert_bool(queued.ok).override_failure_message("fixture failed to queue the attack").is_true()
	sess.execute()

	assert_int(ward.get_current_hp()).override_failure_message("the ward took the hit").is_equal(ward_hp)
	assert_int(blocker.get_current_hp()).is_less(blocker_hp)
	assert_bool(blocker.guard.spent) \
		.override_failure_message("the headless twin never spent the live Guard") \
		.is_true()
