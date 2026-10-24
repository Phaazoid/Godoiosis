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


# THE LINE NAMES WHAT THE WEAPON FIRES (#1365). It printed the template's main, so a mod that replaces
# the main left the attack verb firing something the view never showed, and the friendly-fire and
# element marks were the authored ones, not what the fitted mods make of them.
func test_the_unit_line_prints_the_main_a_mod_put_there_and_its_composed_marks() -> void:
	var b := BoardBuilder.build(self, "ReplacedMainRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var unit: Unit = BoardBuilder.spawn(b, UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(),
			"Gunner", Team.Faction.PLAYER), Vector2i(0, 0))
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.display_name = "Stock Swing"
	var replacement := WeaponAttackData.new()
	replacement.display_name = "Lobbed Swing"
	var mod := WeaponModData.new()
	mod.display_name = "Lob Fitting"
	mod.replaces_main = replacement
	mod.applies_to = WeaponModData.AppliesTo.MAIN_ATTACK
	mod.added_element = Elemental.Element.FIRE
	mod.hits_allies_override = WeaponModData.Override.ON
	var inst := WeaponInstance.make(template)
	assert_bool(inst.fit(0, mod)).override_failure_message("fixture: the mod did not fit").is_true()
	unit.add_item(inst)
	var sess = PlaySession.new(b)
	var main := inst.effective_main(unit.state)
	if main == template.main_attack:
		fail("fixture: the fitted mod did not replace the main, so the line cannot show it")
		return
	assert_bool(inst.effective_hits_allies(unit.state, main)).override_failure_message(
			"fixture: the mod does not make the main hit allies").is_true()

	var line: String = BoardView._unit_line(sess, unit)

	assert_str(line).override_failure_message("the line does not name the main it fires: %s" % line) \
			.contains(main.display_name)
	for element in inst.get_elements(unit.state, main):
		assert_str(line).override_failure_message("the line drops the %s the mod adds: %s"
				% [Elemental.Element.keys()[element], line]).contains("/" + Elemental.Element.keys()[element])
	assert_str(line).override_failure_message("the line drops the friendly fire the mod turns on: %s" % line) \
			.contains("/ff")


# A LEADER'S STRANDING CELLS ARE NOT "+ move" (#1365): queue_move refuses them (#1069), so focus marks
# them refused, cell for cell where legal_moves splits them off.
func test_focus_marks_a_leaders_stranding_cells_as_refused() -> void:
	var b := BoardBuilder.build(self, "StrandFocusRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-4, -4, 18, 18))
	# test_group_move_headless's stranding squad: a quick leader on a short leash, a slow follower.
	var quick := Stats.STAT_DEFAULTS.duplicate()
	quick[Stats.Stat.DEX] = 10
	quick[Stats.Stat.COH] = 1
	var slow := Stats.STAT_DEFAULTS.duplicate()
	slow[Stats.Stat.DEX] = 0
	var leader: Unit = BoardBuilder.spawn(b, UnitFactory.create_unit_data(quick, "Lead", Team.Faction.PLAYER),
			Vector2i(0, 0))
	var member: Unit = BoardBuilder.spawn(b, UnitFactory.create_unit_data(slow, "Slow", Team.Faction.PLAYER),
			Vector2i(0, 1))
	BoardBuilder.spawn(b, UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Foe",
			Team.Faction.ENEMY), Vector2i(12, 12))
	var sess = PlaySession.new(b)
	var joined: Dictionary = sess.join(sess.handle_for(member), sess.handle_for(leader))
	assert_bool(joined.ok).override_failure_message("fixture: the member did not join").is_true()
	var legal: Dictionary = sess.legal_moves(sess.handle_for(leader))
	var stranding: Array[Vector2i] = []
	stranding.assign(legal.get("stranding", []))
	if stranding.is_empty():
		fail("fixture: the leader can reach nowhere its squad cannot follow, so focus shows nothing")
		return

	var text := str(BoardView.render_focus(sess, sess.handle_for(leader)))

	assert_str(text).override_failure_message("the legend does not name the stranding mark:\n%s" % text) \
			.contains("- strands a squadmate")
	var overlay := _focus_overlay(sess, text)
	for cell: Vector2i in stranding:
		assert_str(str(overlay.get(cell, ""))).override_failure_message(
				"focus offers %s as a move, which queue_move refuses:\n%s" % [str(cell), text]).is_equal("-")
	for cell: Vector2i in legal.cells:
		assert_bool(["+", "*"].has(str(overlay.get(cell, "")))).override_failure_message(
				"focus withholds %s, which queue_move takes:\n%s" % [str(cell), text]).is_true()


# Each cell's overlay character, read back off the rendered grid through the view's own rulers.
static func _focus_overlay(sess, text: String) -> Dictionary:
	var bounds: Rect2i = BoardView._content_bounds(sess)
	var out := {}
	for line: String in text.split("\n"):
		var m := RegEx.create_from_string("^ *y= *(-?\\d+) ").search(line)
		if m == null:
			continue
		var y := int(m.get_string(1))
		var body := line.substr(m.get_end())
		for i in bounds.size.x:
			var cell_text := body.substr(i * 3, 3)
			if cell_text.length() == 3:
				out[Vector2i(bounds.position.x + i, y)] = cell_text[2]
	return out
