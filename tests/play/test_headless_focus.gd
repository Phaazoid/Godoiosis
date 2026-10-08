# The Play API's `focus` view (#46). A playtester's `focus` on a unit still in reserve crashed inside
# the move-range search (a reserve unit has no squad to lead), and `focus` on a deployed one printed
# only authored numbers, so a driver could not see what its gear and jobs made of them.
#
# Every expectation is read off the game's own seams (the unit's derived stats, Unit.attack_detail),
# never a number this file chose -- the tuning razor, tests/README #8.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const BoardView := preload("res://play/board_view.gd")
const PlaySession := preload("res://play/play_session.gd")

const ZONE: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]


# The shipped roster offering the most characters, so a cap of one leaves someone in reserve.
static func _largest_roster() -> String:
	var best := ""
	var most := -1
	for name: String in RosterCatalog.saved_rosters():
		var roster: Roster = RosterCatalog.resolve(name)
		if roster != null and roster.offered_entries().size() > most:
			best = name
			most = roster.offered_entries().size()
	return best


func test_focus_on_a_reserve_unit_answers_in_words() -> void:
	var b := BoardBuilder.build(self, "ReserveFocusRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(0, 0, 6, 3))
	BoardBuilder.spawn(b, UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Foe",
			Team.Faction.ENEMY), Vector2i(5, 2))
	var scenario := ScenarioData.new()
	scenario.roster = _largest_roster()
	scenario.deployment_cap = 1
	scenario.zones = {"landing": {"kind": ZoneManager.Kind.DEPLOYMENT, "cells": ZONE.duplicate()}}
	b.zone_manager.load_dict(scenario.zones)
	b["scenario"] = scenario
	var sess = PlaySession.new(b)
	sess.start_pre_mission()
	var reserve: Array[Unit] = sess.reserve_units()
	if reserve.is_empty():
		fail("fixture: the roster left nobody in reserve, so this case cannot see a reserve focus")
		return
	var handle: String = sess.handle_for(reserve[0])

	var text := str(BoardView.render_focus(sess, handle))

	assert_str(text).override_failure_message("focus on a reserve unit did not say so: '%s'" % text) \
		.contains("in reserve")
	assert_str(text).override_failure_message("the refusal did not point at kit: '%s'" % text) \
		.contains("kit %s" % handle)


func test_focus_reads_the_units_derived_numbers_and_its_attacks() -> void:
	var b := BoardBuilder.build(self, "StatsFocusRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var unit: Unit = BoardBuilder.spawn(b, UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(),
			"Swordsman", Team.Faction.PLAYER), Vector2i(0, 0))
	BoardBuilder.spawn(b, UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Foe",
			Team.Faction.ENEMY), Vector2i(5, 5))
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.display_name = "Focus Swing"
	template.main_attack.power = 4
	unit.add_item(WeaponInstance.make(template))
	var sess = PlaySession.new(b)
	var attacks: Array[AttackData] = unit.get_selectable_attacks()
	if attacks.is_empty():
		fail("fixture: the unit has no attack to list")
		return

	var text := str(BoardView.render_focus(sess, sess.handle_for(unit)))

	for expected: String in [
			"HP %d/%d" % [unit.get_current_hp(), unit.get_max_hp()],
			"MOV %d" % unit.get_mov(),
			"STR %d" % unit.get_effective_stat(Stats.Stat.STR),
			"DEF %d" % unit.get_effective_def(),
			"squad %d/%d" % [unit.squad.members.size(), unit.squad.max_size()]]:
		assert_str(text).override_failure_message("focus did not print '%s':\n%s" % [expected, text]) \
			.contains(expected)
	for attack in attacks:
		var detail := unit.attack_detail(attack).get_slice("\n", 0)
		assert_str(text).override_failure_message(
				"focus did not list %s in the game's words ('%s'):\n%s" % [attack.display_name, detail, text]) \
			.contains("%s: %s" % [attack.display_name, detail])
