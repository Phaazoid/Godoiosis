# The Play API's execute and end_turn logs say what happened (#46). A playtester saw a Splash land
# and no Wet in the log, a Guard logged as "Warden guards Warden" with no way to tell which Warden,
# and a downed ally vanish between turns with no line at all.
#
# Expectations are read off the resolved outcome and the session's handles, never restated.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


func _board(root_name: String) -> Dictionary:
	var b := BoardBuilder.build(self, root_name)
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 12, 12))
	return b


func _weapon(element := Elemental.Element.NONE) -> WeaponInstance:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = WeaponAttackData.new()
	t.main_attack.power = 2
	t.main_attack.elemental_damage_type = element
	return WeaponInstance.make(t)


# Every state the hit gave its target is logged, in the game's word for it.
func test_a_hit_logs_the_states_it_left_on_its_target() -> void:
	var b := _board("StateLogRoot")
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(1, 0))
	hero.add_item(_weapon(Elemental.Element.WATER))
	foe.unit_instance.stats[Stats.Stat.MHP] = 200
	foe.set_current_hp(200)
	var sess = PlaySession.new(b)
	assert_bool(sess.queue_attack(sess.handle_for(hero), foe.movement.cell).ok).is_true()
	var plan: ResolvedPlan = sess.squad_manager.resolved_plan_for(hero.squad)
	var added: Array[Elemental.State] = plan.attacks[0].resolved.states_added
	if added.is_empty():
		fail("fixture: no shipped reaction gives a water hit a state, so there is nothing to log")
		return

	var events: Array = sess.execute().get("events", [])

	for state in added:
		var line := "%s gains %s" % [sess.handle_for(foe), Elemental.state_display_name(state)]
		assert_bool(events.has(line)).override_failure_message("the log did not say '%s': %s"
				% [line, str(events)]).is_true()


# A side-channel line names both ends by handle, ahead of the game's own words.
func test_a_guard_is_logged_by_handle() -> void:
	var b := _board("GuardLogRoot")
	var guard: Unit = BoardBuilder.spawn(b, _data("Warden", PLAYER), Vector2i(0, 0))
	var ward: Unit = BoardBuilder.spawn(b, _data("Warden", PLAYER), Vector2i(1, 0))
	BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(8, 8))
	var sess = PlaySession.new(b)
	var g: String = sess.handle_for(guard)
	var w: String = sess.handle_for(ward)
	var queued: Dictionary = sess.guard(g, w)
	assert_bool(queued.ok).override_failure_message("fixture: the guard was refused: %s" % str(queued)).is_true()

	var events: Array = sess.execute().get("events", [])

	var prefix := "%s GUARD -> %s:" % [g, w]
	var found := false
	for e in events:
		if str(e).begins_with(prefix):
			found = true
	assert_bool(found).override_failure_message("no line begins '%s': %s" % [prefix, str(events)]).is_true()


# A downed unit whose clock runs out at its side's turn start is logged by the hand-off that ran it.
func test_a_bleed_out_is_logged_at_the_turn_it_happens() -> void:
	var b := _board("BleedLogRoot")
	BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var body: Unit = BoardBuilder.spawn(b, _data("Body", PLAYER), Vector2i(3, 3))
	BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(8, 8))
	var sess = PlaySession.new(b)
	var handle: String = sess.handle_for(body)
	body.force_down()
	body.downed_turns_remaining = 1   # this side's next turn start is its last

	var to_enemy: Dictionary = sess.end_turn()
	var back: Dictionary = sess.end_turn()

	assert_str(str(back.get("faction", ""))).override_failure_message(
			"fixture: the second hand-off did not come back to the player").is_equal("PLAYER")
	var line := "%s bleeds out" % handle
	assert_bool((to_enemy.get("ai_events", []) as Array).has(line)).override_failure_message(
			"the body bled out on the ENEMY's turn start: %s" % str(to_enemy)).is_false()
	assert_bool((back.get("ai_events", []) as Array).has(line)).override_failure_message(
			"the bleed-out was not logged: %s" % str(back)).is_true()
