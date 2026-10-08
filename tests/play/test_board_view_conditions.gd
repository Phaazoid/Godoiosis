# What the overview shows that it did not (#1236): a defended point on the board, and on each unit's
# line what it is standing in -- the facts the game's inspect panel shows. Expectations are spelled in
# the game's own words (Elemental.state_display_name, UnitInstance.LIMB_FULL), never retyped.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")
const BoardView := preload("res://play/board_view.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


func test_a_defended_point_is_drawn_and_named() -> void:
	var src: Dictionary = BoardBuilder.build(self, "DefendSrc")
	auto_free(src.root)
	BoardBuilder.paint_rect(src.grid, Rect2i(-2, -2, 12, 8))
	var scenario := ScenarioData.new()
	scenario.tile_data = src.grid.tile_map_data
	var cargo: Array[Vector2i] = [Vector2i(4, 4)]
	scenario.zones["Cargo"] = {"kind": ZoneManager.Kind.DEFEND, "cells": cargo}
	for placed: Array in [["P1", PLAYER, Vector2i(0, 0)], ["E1", ENEMY, Vector2i(8, 0)]]:
		var entry := ScenarioUnitEntry.new()
		entry.unit_data = _data(placed[0], placed[1])
		entry.cell = placed[2]
		scenario.unit_entries.append(entry)
	var board: Dictionary = BoardBuilder.build(self, "DefendDst")
	auto_free(board.root)
	await BoardBuilder.apply_scenario(board, scenario)
	var sess = PlaySession.new(board)

	var overlay: Dictionary = BoardView._overview_overlay(sess)
	assert_str(str(overlay.get(Vector2i(4, 4), ""))).override_failure_message(
		"the defended cell carries no glyph").is_equal("F")
	assert_str(BoardView.render_overview(sess)).contains("F = defend zone")


func test_the_unit_line_names_what_a_unit_stands_in() -> void:
	var b := BoardBuilder.build(self, "ConditionsRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var sess = PlaySession.new(b)
	assert_str(BoardView._unit_line(sess, hero)).override_failure_message(
		"precondition: an unhurt unit already shows a condition").not_contains("[")

	hero.wounded = true
	hero.in_crisis = true
	hero.element_states.append(Elemental.State.WET)
	hero.unit_instance.limbs[UnitInstance.LimbSlot.ARM_L].state = UnitInstance.LimbState.EMPTY

	var line: String = BoardView._unit_line(sess, hero)
	for words: String in ["WOUNDED", "CRISIS", Elemental.state_display_name(Elemental.State.WET),
			"no %s" % UnitInstance.LIMB_FULL[UnitInstance.LimbSlot.ARM_L].to_lower()]:
		assert_str(line).override_failure_message("the unit line does not say '%s': %s" % [words, line]).contains(words)
