# The objectives panel's zone rows (#955 part 3), driven with a REAL pointer: motion and clicks parsed
# into the window the way test_input_bridge drives the board, so the viewport's own hover and the
# panel's reconcile are what is exercised -- not a signal emitted by hand. What each case asserts is
# the visible consequence: the marks both views draw, and the cell the camera is sent to.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"

var _board := SharedBoard.new(SCENE_PATH)
var game: Node2D
var _overlays: BoardOverlays
var _looked_at: Array[Vector2i] = []


# Two capture zones and one extraction zone, with a Rout objective and a clock beside them -- rows
# that name no place.
func _zones() -> Dictionary:
	return {
		"north": {"kind": ZoneManager.Kind.CAPTURE, "cells": [Vector2i(1, 1), Vector2i(2, 1)]},
		"south": {"kind": ZoneManager.Kind.CAPTURE, "cells": [Vector2i(1, 6)]},
		"exit": {"kind": ZoneManager.Kind.EXTRACTION, "cells": [Vector2i(6, 6)]},
	}


func before() -> void:
	await _board.open(self, _clear_the_board)


func _clear_the_board() -> void:
	_board.game.scenario_manager.clear_board()
	_board.game.game_state = _board.game.GameState.IDLE


func before_test() -> void:
	await _board.reset(self)
	game = _board.game
	# The boot title screen sits over the board and, rightly, over this panel too.
	game.mission_controller._close_mission_select()
	_overlays = _board.scene.get_node("BoardOverlays") as BoardOverlays
	game.zone_manager.load_dict(_zones())
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT,
			MissionRules.Objective.CAPTURE, MissionRules.Objective.EXTRACT]
	game.mission_controller.set_objectives(objectives)
	var lose: Array[MissionRules.LoseCondition] = [MissionRules.LoseCondition.ROUND_LIMIT]
	game.mission_controller.set_lose_conditions(lose, 6)
	_om().redraw_zones(game.zone_manager, game.mission_controller.hidden_zone_names())
	game.refresh_mission_status()
	_looked_at.clear()
	game.view_focus_requested.connect(_record_look)
	# A headless window is never told the mouse ENTERED it (the OS sends that), and a viewport that
	# thinks the pointer is outside it tracks no control under the pointer -- so say it, as the OS would.
	get_tree().root.notification(Node.NOTIFICATION_VP_MOUSE_ENTER)
	await _pump()


func after_test() -> void:
	game.view_focus_requested.disconnect(_record_look)
	game.game_state = game.GameState.IDLE
	_parse_motion(_off_panel())
	await _pump()
	await _board.check(self)


func after() -> void:
	_board.close()


func _record_look(cell: Vector2i) -> void:
	_looked_at.append(cell)


func _om() -> OverlayManager:
	return game.overlay_manager


func _panel() -> MissionStatusPanel:
	return game.mission_status_panel


func _zone_row(kind: ZoneManager.Kind) -> MissionStatusPanel.ZoneRow:
	for child in _panel()._rows.get_children():
		var row := child as MissionStatusPanel.ZoneRow
		if row != null and row.zone_kind == kind:
			return row
	return null


func _plain_row(prefix: String) -> Label:
	for child in _panel()._rows.get_children():
		var label := child as Label
		if label != null and label.text.contains(prefix):
			return label
	return null


# A board point well clear of every HUD surface.
func _off_panel() -> Vector2:
	return Vector2(320, 300)


func _centre(control: Control) -> Vector2:
	return control.get_global_rect().get_center()


func _parse_motion(screen_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	motion.global_position = screen_pos
	Input.parse_input_event(motion)


func _click(control: Control) -> void:
	var at := _centre(control)
	_parse_motion(at)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(event)
	await _pump()


# test_input_bridge's pump: deliver everything, then let the _process reconcile see it.
func _pump() -> void:
	Input.flush_buffered_events()
	await await_idle_frame()
	Input.flush_buffered_events()
	await await_idle_frame()
	await await_idle_frame()


func _hover(control: Control) -> void:
	_parse_motion(_centre(control))
	await _pump()


# The colours of the marks wearing LIT art, in each view. The art is white and shared across kinds (a
# lone capture cell and a lone exit cell wear the same texture), so which kind is lit is read off the
# tint each lit mark wears.
func _lit_tints_3d() -> Array[Color]:
	var tints: Array[Color] = []
	for mark in _overlays.markers_of(BoardOverlays.Layer.ZONE_MARKS):
		if _is_lit_art(mark["texture"]):
			tints.append(mark["modulate"])
	return tints


func _lit_tints_2d() -> Array[Color]:
	var tints: Array[Color] = []
	for sprite in _om()._zone_sprites:
		if is_instance_valid(sprite) and _is_lit_art(sprite.texture):
			tints.append(sprite.modulate)
	return tints


func _is_lit_art(texture: Texture2D) -> bool:
	for zone in _om().drawn_zones:
		var zone_cells: Array[Vector2i] = []
		zone_cells.assign(zone["cells"])
		var masks := ZoneMarks.cell_masks(zone_cells)
		for cell: Vector2i in masks:
			if texture == ZoneMarks.texture(masks[cell], true):
				return true
	return false


# Every drawn capture cell's tint, as each view paints it.
func _capture_tints(flat: bool) -> Array[Color]:
	var tint := ZoneMarks.colour_of(ZoneManager.Kind.CAPTURE)
	if not flat:
		tint = _overlays.layer_modulate(BoardOverlays.Layer.ZONE_CAPTURE)
		tint.a = 1.0
	var tints: Array[Color] = []
	for zone in _om().drawn_zones:
		if int(zone["kind"]) == ZoneManager.Kind.CAPTURE:
			for cell: Vector2i in zone["cells"]:
				tints.append(tint)
	return tints


func _emblem_cells(kind: ZoneManager.Kind) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for zone in _om().drawn_zones:
		if int(zone["kind"]) == kind:
			var zone_cells: Array[Vector2i] = []
			zone_cells.assign(zone["cells"])
			cells.append(ZoneMarks.emblem_cell(zone_cells))
	return cells


func test_each_zone_row_wears_its_zones_emblem() -> void:
	for kind: ZoneManager.Kind in [ZoneManager.Kind.CAPTURE, ZoneManager.Kind.EXTRACTION]:
		var row := _zone_row(kind)
		assert_object(row).override_failure_message("no zone row for kind %d" % kind).is_not_null()
		var emblem := row.find_children("*", "TextureRect", true, false)
		assert_int(emblem.size()).is_equal(1)
		assert_object((emblem[0] as TextureRect).texture).is_same(ZoneMarks.emblem_of(kind))


func test_hovering_a_zone_row_lights_its_zones_in_both_views() -> void:
	assert_array(_lit_tints_3d()).override_failure_message("a zone is lit before any hover").is_empty()
	await _hover(_zone_row(ZoneManager.Kind.CAPTURE))
	assert_int(_om().lit_zone_kind).is_equal(ZoneManager.Kind.CAPTURE)
	assert_array(_lit_tints_3d()).override_failure_message(
			"the diorama did not light exactly the capture zones").is_equal(_capture_tints(false))
	assert_array(_lit_tints_2d()).override_failure_message(
			"the flat view did not light exactly the capture zones").is_equal(_capture_tints(true))

	_parse_motion(_off_panel())
	await _pump()
	assert_int(_om().lit_zone_kind).is_equal(MissionRules.NO_ZONE)
	assert_array(_lit_tints_3d()).override_failure_message("the light outlived the pointer").is_empty()
	assert_array(_lit_tints_2d()).is_empty()


# Every refresh rebuilds the rows (several a pass). A resting pointer keeps its light through one, and
# leaving the rebuilt row still puts it out -- a freed row never sends mouse_exited.
func test_a_refresh_under_a_resting_pointer_neither_drops_nor_strands_the_light() -> void:
	await _hover(_zone_row(ZoneManager.Kind.CAPTURE))
	game.refresh_mission_status()
	await _pump()
	assert_int(_om().lit_zone_kind).override_failure_message(
			"a refresh under a resting pointer put the light out").is_equal(ZoneManager.Kind.CAPTURE)
	_parse_motion(_off_panel())
	await _pump()
	assert_int(_om().lit_zone_kind).override_failure_message(
			"leaving a row rebuilt under the pointer left its zones lit").is_equal(MissionRules.NO_ZONE)


func test_clicking_a_zone_row_visits_each_zone_in_turn() -> void:
	var emblems := _emblem_cells(ZoneManager.Kind.CAPTURE)
	assert_int(emblems.size()).override_failure_message("the fixture needs two capture zones").is_equal(2)
	for i in 3:
		await _click(_zone_row(ZoneManager.Kind.CAPTURE))
	assert_array(_looked_at).is_equal([emblems[0], emblems[1], emblems[0]])


func test_a_click_while_the_board_is_locked_moves_nothing() -> void:
	game.game_state = game.GameState.AI_TURN
	await _click(_zone_row(ZoneManager.Kind.CAPTURE))
	assert_array(_looked_at).override_failure_message(
			"a zone row moved the camera during an enemy turn").is_empty()
	# Lighting is hover paint and stays live through the turn.
	assert_int(_om().lit_zone_kind).is_equal(ZoneManager.Kind.CAPTURE)


func test_a_claimed_zone_is_neither_lit_nor_visited() -> void:
	game.mission_controller.capture("north")
	await _pump()
	await _hover(_zone_row(ZoneManager.Kind.CAPTURE))
	assert_array(_lit_tints_3d()).override_failure_message(
			"a claimed capture zone lit up, or the unclaimed one did not").is_equal(_capture_tints(false))
	assert_int(_lit_tints_3d().size()).is_equal(1)
	await _click(_zone_row(ZoneManager.Kind.CAPTURE))
	await _click(_zone_row(ZoneManager.Kind.CAPTURE))
	assert_array(_looked_at).is_equal([Vector2i(1, 6), Vector2i(1, 6)])


func test_rows_that_name_no_place_do_not_answer() -> void:
	for prefix: String in ["Rout", "Time"]:
		var label := _plain_row(prefix)
		assert_object(label).override_failure_message("no %s row" % prefix).is_not_null()
		assert_int(label.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
		await _click(label)
	assert_array(_looked_at).is_empty()
	assert_int(_om().lit_zone_kind).is_equal(MissionRules.NO_ZONE)


# The pre-mission contract draws the same briefing as plain text: the board is behind an opaque
# screen there. The HUD's rows are what answer; the briefing names each row's place all the same.
func test_the_briefing_stays_plain_text_and_names_each_rows_place() -> void:
	for label in MissionStatusPanel.briefing_rows(game.mission_controller, game._board()):
		assert_int(label.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
		label.free()
	var kinds: Array[int] = []
	for row in MissionStatusPanel.briefing(game.mission_controller, game._board()):
		kinds.append(row.zone_kind)
		row.label.free()
	# OBJECTIVES header, Rout, Capture, Extract, FAIL IF header, Time.
	assert_array(kinds).is_equal([MissionRules.NO_ZONE, MissionRules.NO_ZONE, ZoneManager.Kind.CAPTURE,
			ZoneManager.Kind.EXTRACTION, MissionRules.NO_ZONE, MissionRules.NO_ZONE])
	assert_int(MissionRules.zone_kind_of_lose(MissionRules.LoseCondition.POINT_LOST)).is_equal(
			ZoneManager.Kind.DEFEND)
