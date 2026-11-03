# Guard (#414) through the headless Play API, on a REAL painted board.
#
# Two things only this surface pins. The `guard` verb itself — every other side-channel main action
# has one, and without it the AI-facing API cannot express the mechanic at all. And the SPEND on
# the headless path: play_session._apply_attack calls AttackAction.land for it since #46, the step
# the game's execute() calls, but only a headless case can see that the headless path reaches it
# (the went_downed trap, CLAUDE.md's execution-order bullet).
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


# #1570: a counter from a unit the pass has ALREADY downed never lands, so it must not spend the ward.
# The Guard used to be applied to each counter volley before its counter-er's liveness was asked: the
# downed counter-er's blow was redirected onto the blocker, the plan's ward copy marked spent, and a
# squadmate's live counter then hit the ward for full. Asked in resolve_attack_group's order now.
func test_a_downed_counter_er_does_not_spend_the_ward_its_squadmate_needs() -> void:
	var b := BoardBuilder.build(self, "GuardRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-1, -1, 12, 9))
	var ward: Unit = BoardBuilder.spawn(b, _data("Ward", PLAYER), Vector2i(3, 3))
	var blocker: Unit = BoardBuilder.spawn(b, _data("Blocker", PLAYER), Vector2i(3, 4))
	var downed: Unit = BoardBuilder.spawn(b, _data("Downed", ENEMY), Vector2i(4, 3))
	var live: Unit = BoardBuilder.spawn(b, _data("Live", ENEMY), Vector2i(3, 2))
	for unit: Unit in [ward, blocker, downed, live]:
		_arm(unit)
	var sm: SquadManager = b.squad_manager
	sm.join_squad(blocker, ward.squad)
	sm.join_squad(live, downed.squad)   # one reacting squad: both answer the ward's hit
	downed.set_current_hp(1)            # the ward's hit downs it
	blocker.arm_guard(ward, blocker.get_guard_range())
	var sess = PlaySession.new(b)
	var ward_hp := ward.get_current_hp()

	var queued: Dictionary = sess.queue_attack(sess.handle_for(ward), downed.movement.cell)
	assert_bool(queued.ok).override_failure_message("fixture failed to queue the ward's attack").is_true()
	var plan := sm.resolve_plan(ward.squad, sm.board_source.call())
	var from_downed: CounterAttackAction = null
	var from_live: CounterAttackAction = null
	for ctr in plan.counters:
		if ctr.actor == downed:
			from_downed = ctr
		elif ctr.actor == live:
			from_live = ctr
	assert_object(from_live).override_failure_message("fixture: the live squadmate drew no counter").is_not_null()
	assert_object(from_downed).override_failure_message("fixture: the downed counter-er's counter was not derived").is_not_null()
	assert_bool(from_downed.resolved.skipped).override_failure_message("fixture: the downed counter-er was not skipped").is_true()

	assert_object(from_downed.blocked_for).override_failure_message(
			"the Guard took a counter that never lands (#1570)").is_null()
	assert_object(from_live.target).override_failure_message(
			"the live counter was not blocked: the ward was spent on the downed counter-er's blow").is_same(blocker)

	sess.execute()
	assert_int(ward.get_current_hp()).override_failure_message(
			"the ward took the live counter unguarded").is_equal(ward_hp)
	assert_bool(blocker.guard.spent).override_failure_message("the blocker's live Guard was never spent").is_true()
