# What a headless pass does once it has played out: the same two sweeps OrderExecutor.execute_orders
# runs (#46). Before this the headless sweep ejected a downed unit but never spent one a squadmate
# rescued in the same pass (#124), so it could act again that turn; and nothing split a member out
# of contact (#151) until the next turn start, where the game splits it as the pass settles.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER


func _data(unit_name: String) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, PLAYER)


func _flat_board(root_name: String) -> Dictionary:
	var b := BoardBuilder.build(self, root_name)
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 16, 16))
	return b


# The game's own case (test_downed_ejection's same-pass rescue), through the session's doors: the
# striker's plan drops a squadmate, the medic picks it up in the side channel, and the sweep still
# ejects it and spends its turn.
func test_a_same_pass_rescue_leaves_the_rescued_unit_spent() -> void:
	var b := _flat_board("SamePassRescueRoot")
	var striker: Unit = BoardBuilder.spawn(b, _data("Striker"), Vector2i(1, 0))
	var victim: Unit = BoardBuilder.spawn(b, _data("Victim"), Vector2i(2, 0))
	var medic: Unit = BoardBuilder.spawn(b, _data("Medic"), Vector2i(3, 0))
	BoardBuilder.arm(striker, 1)
	(striker.get_equipped_weapon() as WeaponInstance).template.main_attack.hits_allies = true
	var sm: SquadManager = b.squad_manager
	sm.join_squad(victim, striker.squad)
	sm.join_squad(medic, striker.squad)
	victim.take_damage(victim.get_current_hp() - 1)
	var sess = PlaySession.new(b)
	var acting: Squad = striker.squad

	var aimed: Dictionary = sess.queue_attack(sess.handle_for(striker), victim.movement.cell)
	assert_bool(aimed.ok).override_failure_message("fixture: the aim did not queue: %s" % str(aimed.get("error", ""))).is_true()
	var res: Dictionary = sess.rescue(sess.handle_for(medic), sess.handle_for(victim))
	assert_bool(res.ok).override_failure_message("fixture: the rescue did not queue: %s" % str(res.get("error", ""))).is_true()
	assert_bool((sess.execute() as Dictionary).ok).override_failure_message("the pass did not execute").is_true()

	assert_bool(victim.is_active()).override_failure_message("fixture: the same-pass rescue did not stand the victim up").is_true()
	assert_bool(victim.squad == acting).override_failure_message(
			"revived mid-pass but never ejected -- revive must not re-enlist").is_false()
	assert_bool(victim.squad.has_acted).override_failure_message(
			"a unit rescued in the same pass is fresh headlessly; the game spends it the turn it is rescued").is_true()


# The game's wire case (test_squad_cohesion's pass-end ejection): ANY squad's pass sweeps every
# squad, so a member a shove the plan never chose left out of reach is split when the next pass
# settles, not at the next turn start.
func test_a_pass_splits_a_member_out_of_contact() -> void:
	var b := _flat_board("PassEndContactRoot")
	var leader: Unit = BoardBuilder.spawn(b, _data("Leader"), Vector2i(0, 0))
	var member: Unit = BoardBuilder.spawn(b, _data("Member"), Vector2i(1, 0))
	var bystander: Unit = BoardBuilder.spawn(b, _data("Bystander"), Vector2i(0, 6))
	var sm: SquadManager = b.squad_manager
	sm.join_squad(member, leader.squad)
	var sess = PlaySession.new(b)
	member.movement.set_cell(Vector2i(13, 13))   # a shove the plan never chose
	assert_bool(sm.contact_breaks().has(member)).override_failure_message(
			"fixture: the member is still in contact, so there is nothing to split").is_true()

	var moved: Dictionary = sess.queue_move(sess.handle_for(bystander), Vector2i(1, 6))
	assert_bool(moved.ok).override_failure_message("fixture: the bystander's move did not queue: %s" % str(moved.get("error", ""))).is_true()
	assert_bool((sess.execute() as Dictionary).ok).override_failure_message("the bystander's pass did not execute").is_true()

	assert_bool(member.squad == leader.squad).override_failure_message(
			"a member out of its leader's reach stayed in the squad after a pass settled").is_false()
