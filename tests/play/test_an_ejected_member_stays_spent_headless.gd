# The HEADLESS half of #1556. play_session.execute is the Play API's own executor, with its own copy
# of the pass's tail: the settle sweeps, then the squad marked spent. A member the sweep ejected got a
# fresh, un-acted solo squad there too, and the Play API -- which the AI drives (Law #3) -- let it
# queue a second action. The game-scene half is tests/squad/test_a_squad_acts_once_per_turn.gd.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _spawn(b: Dictionary, faction: Team.Faction, cell: Vector2i, stats: Dictionary = {}, power := 1,
		knockback := 0) -> Unit:
	var unit: Unit = BoardBuilder.spawn(b, H.make_unit_data(stats, faction), cell)
	var weapon := H.make_weapon(power)
	(weapon.template.main_attack as WeaponAttackData).knockback = knockback
	unit.equipped_weapon = weapon
	unit.set_current_hp(unit.get_max_hp())
	return unit


# test_split_forecast's counter-shove layout: the member's attack draws a counter that knocks it out
# of its leader's reach, and the pass-end sweep ejects it.
func test_a_member_its_own_headless_pass_shoves_out_stays_spent() -> void:
	var b := BoardBuilder.build(self, "SpentEjecteeRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(0, 0, 10, 5))
	var lead := _spawn(b, PLAYER, Vector2i(1, 3), {Stats.Stat.LDR: 10})
	var member := _spawn(b, PLAYER, Vector2i(4, 2))
	var foe := _spawn(b, ENEMY, Vector2i(3, 2), {Stats.Stat.MHP: 200}, 1, 2)
	var sess = PlaySession.new(b)
	var joined: Dictionary = sess.join(sess.handle_for(member), sess.handle_for(lead))
	assert_bool(joined.ok).override_failure_message("fixture: the member did not join: %s" % str(joined)).is_true()
	var queued: Dictionary = sess.queue_attack(sess.handle_for(member), foe.movement.cell)
	assert_bool(queued.ok).override_failure_message("fixture: the attack was refused: %s" % str(queued)).is_true()

	var result: Dictionary = sess.execute()

	assert_bool(result.ok).override_failure_message("fixture: the pass was refused: %s" % str(result)).is_true()
	assert_bool(member.squad == lead.squad).override_failure_message(
			"fixture: the counter never shoved the member out of contact").is_false()
	assert_bool(member.squad.has_acted).override_failure_message(
			"the headless pass handed the ejected member a squad that has not acted").is_true()
	# Wait, not a second attack: the shove leaves the member out of reach, which refuses any aim anyway.
	var again: Dictionary = sess.wait(sess.handle_for(member))
	assert_bool(again.ok).override_failure_message(
			"the Play API let a member of a squad that had acted spend a second turn").is_false()
