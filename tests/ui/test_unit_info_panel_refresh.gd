extends GdUnitTestSuite

# The inspect panel's DERIVED rows must survive the unit MOVING (#44 checklist item).
#
# DEF is the one cell-dependent row -- RulesService.def_breakdown reads Cover at the unit's CURRENT
# cell -- and UnitInfoPanelControl re-read its derived rows on inventory_panel.loadout_changed
# alone. So walking onto a Burrow-dug Cover tile with the panel open left DEF showing the number
# from inspect time, and set_unit's same-unit early return meant re-inspecting could not clear it
# either: only closing the panel, right-clicking, inspecting someone else or ending the turn did.
#
# MovementComponent.movement_finished already announced arrival and had ZERO connect() callers, so
# the fix is one wire rather than a new signal -- which is exactly the kind of thing a green suite
# stays green without. These cases drive a REAL walk and assert the label the player reads.
#
# The DEF assertion is a DELTA against Terrain.COVER_DEF, never a literal DEF value: stats, armour
# and board geometry are all authored, and pinning any of them here would red on a content commit
# (tests/README.md #9, the content razor).
#
# DELIBERATELY NOT COVERED -- a Burrow depositing Cover in the SAME pass. OrderExecutor applies cell
# effects AFTER the move phase, so the refresh runs before the deposit lands; covering that needs an
# end-of-pass announcement OrderExecutor does not have (dev ruling, 2026-08-21).

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var game: Node2D


func before_test() -> void:
	# Named + parented exactly as in production so game.gd's dev-overlay lookup resolves; fixture
	# copied from tests/ui/test_game_scene_smoke.gd.
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.spawn_sandbox()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func test_walking_onto_cover_moves_the_def_on_the_open_panel() -> void:
	var pair := _movable_unit_and_destination()
	assert_bool(pair.size() == 2).override_failure_message(
			"no spawned unit could be ordered anywhere, so a walk proves nothing"
			).is_true()
	var unit: Unit = pair[0]
	var destination: Vector2i = pair[1]

	_deposit_cover(destination)
	var panel: UnitInfoPanelControl = game.unit_info_panel
	panel.set_unit(unit, true, game._board())
	var before := _def_value()
	assert_str(before).override_failure_message(
			"the panel rendered no DEF row, so there is nothing to go stale").is_not_empty()

	await _walk(unit, destination)

	var after := _def_value()
	assert_int(after.to_int() - before.to_int()).override_failure_message(
			"DEF stayed at %s after walking onto Cover -- the open panel is showing the number "
			% before + "from inspect time").is_equal(Terrain.COVER_DEF)


func test_walking_off_cover_moves_it_back() -> void:
	# The twin direction, because a refresh that only ever ADDED would also pass the case above if
	# it re-read the wrong cell. Start ON cover, walk off it.
	var pair := _movable_unit_and_destination()
	assert_bool(pair.size() == 2).override_failure_message(
			"no spawned unit could be ordered anywhere, so a walk proves nothing"
			).is_true()
	var unit: Unit = pair[0]
	var destination: Vector2i = pair[1]

	_deposit_cover(unit.movement.cell)
	var panel: UnitInfoPanelControl = game.unit_info_panel
	panel.set_unit(unit, true, game._board())
	var before := _def_value()

	await _walk(unit, destination)

	assert_int(before.to_int() - _def_value().to_int()).override_failure_message(
			"DEF stayed at %s after walking OFF Cover" % before).is_equal(Terrain.COVER_DEF)


func test_the_panel_lets_go_of_a_unit_it_stops_showing() -> void:
	# The disconnect is the risky half of this wire: the panel outlives the units it shows, and a
	# leaked connection means a freed unit's signal still points at it.
	var units := _live_units()
	assert_bool(units.size() >= 2).override_failure_message(
			"need two units to swap between").is_true()
	var first := units[0]
	var second := units[1]
	var panel: UnitInfoPanelControl = game.unit_info_panel

	panel.set_unit(first, true, game._board())
	assert_bool(first.movement.movement_finished.is_connected(panel._refresh_derived_rows)).is_true()

	panel.set_unit(second, true, game._board())
	assert_bool(first.movement.movement_finished.is_connected(panel._refresh_derived_rows)
			).override_failure_message(
			"inspecting a second unit left the first one still wired to the panel").is_false()
	assert_bool(second.movement.movement_finished.is_connected(panel._refresh_derived_rows)).is_true()

	panel.clear()
	assert_bool(second.movement.movement_finished.is_connected(panel._refresh_derived_rows)
			).override_failure_message(
			"closing the panel left its unit still wired to it").is_false()


func test_the_loadout_trigger_still_reaches_the_same_refresh() -> void:
	# Both triggers must land on one handler -- they were one method before arrival was added, and a
	# rename that missed this connect would fail at runtime rather than at parse time.
	var panel: UnitInfoPanelControl = game.unit_info_panel
	var inventory: Node = panel.inventory_panel
	assert_bool(inventory.loadout_changed.is_connected(panel._refresh_derived_rows)).is_true()


# --- helpers -------------------------------------------------------------------------------

func _live_units() -> Array[Unit]:
	var live: Array[Unit] = []
	for child in game.units_root.get_children():
		var unit := child as Unit
		if unit != null:
			live.append(unit)
	return live


# A unit the board actually lets move, and one cell it may be ordered to. Both DERIVED from the real
# move-range seam rather than assumed -- on an authored board the first unit can genuinely be boxed
# in, and a hardcoded cell is a content pin.
func _movable_unit_and_destination() -> Array:
	for unit in _live_units():
		var reach: Dictionary = game.compute_move_range(unit)
		var cells: Array[Vector2i] = game.get_move_range(reach, unit)
		if not cells.is_empty():
			return [unit, cells[0]]
	return []


func _deposit_cover(cell: Vector2i) -> void:
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([Terrain.TileState.COVER] as Array[Terrain.TileState])
	game.terrain_states.apply(effect)


# The real walk, not set_cell: movement_finished is what the panel listens to, and a teleport does
# not emit it. Cranked speed keeps the tween real but short.
func _walk(unit: Unit, destination: Vector2i) -> void:
	unit.movement.move_speed = 4000
	unit.movement.move_along_path([unit.movement.cell, destination] as Array[Vector2i])
	await unit.movement.movement_finished


# The DEF value Label out of the live panel. queue_free()d rows linger until the next frame, so the
# is_queued_for_deletion filter is what makes this readable straight after a refresh.
func _def_value() -> String:
	var grid: GridContainer = game.unit_info_panel.stats_section.stats_grid
	var kids := grid.get_children()
	for i in kids.size():
		var label := kids[i] as Label
		if label == null or label.is_queued_for_deletion():
			continue
		if label.text == "DEF" and i + 1 < kids.size():
			var value := kids[i + 1] as Label
			if value != null:
				return value.text
	return ""
