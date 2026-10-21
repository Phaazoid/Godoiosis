# The inspect dock's gear verbs are read-only while playback owns the board and while the pre-mission
# phase is open (#1351). Mid-pass, an Equip swapped the weapon a stamped shot was already firing; in
# the phase, Toss deleted a roster unit's item past Loadout, the phase's one judge.
#
# Every case drives the real doors: the ring's Inspect (MainActionMenu.on_pressed), the queue panel's
# Execute signal, and the phase's own commit. A pass cannot be sampled between frames headlessly
# (test_hud_hides_for_the_cinematic.gd's finding: Pacing collapses every beat), so the mid-pass case
# samples at volley_struck, which the pass emits from inside its own playback.
#
# The scratch mission is authored in memory and saved to user://, never into Scenarios/
# (test_pre_mission_placement.gd's setup, for its reasons).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const SCRATCH := "user://__inspect_dock_1351.tres"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROW_WIDTH := 10
const ZONE_CELLS := 5
# What a read-only popup may still hold: reading an item is not a loadout act (#1152).
const READ_ROWS: Array[String] = ["Inspect", "Cancel"]

var _main: Node
var game: Node2D
var _was_zoom: int


func before_test() -> void:
	_was_zoom = PlayerSettings.choice_of(PlayerSettings.Setting.BATTLE_ZOOM_MODE)
	# The issue's case: with the zoom on, the cinematic hides the dock, which hid this bug.
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.OFF)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.mission_controller._close_mission_select()
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	game.turn_manager.set_active_faction(Team.Faction.PLAYER)
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, _was_zoom)
	await DialogFixtures.end_all_dialog(self)
	game.scenario_manager.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


# The loadout rows the dock offers for `slot`, read off the popup a click on it opens, then closed.
# Read off THIS popup, never a walk of the panel: a popup the gate closed is queue_free'd, so it stays
# in the tree until the frame ends and a walk would still find its buttons.
func _loadout_rows(slot: int) -> Array[String]:
	var panel = game.unit_info_panel.inventory_panel
	panel._show_action_popup(slot)
	var rows: Array[String] = []
	var popup: Control = panel.action_popup
	if popup != null:
		for node: Node in popup.find_children("*", "Button", true, false):
			var text := (node as Button).text
			if not READ_ROWS.has(text):
				rows.append(text)
	panel._do_cancel()
	return rows


static func _has_row(rows: Array[String], verb: String) -> bool:
	for row in rows:
		if row.begins_with(verb):
			return true
	return false


func _inspect(unit: Unit) -> void:
	game.main_action_menu.on_pressed(MainActionMenu.INSPECT, unit)
	await await_idle_frame()


# ==============================================================================
#  Mid-pass
# ==============================================================================

func test_the_docks_gear_verbs_stand_down_for_the_pass_and_come_back_after_it() -> void:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 0))
	var sword := H.make_weapon(3)
	var mace := H.make_weapon(5)
	unit.add_item(sword)   # the first weapon-shaped item auto-equips
	unit.add_item(mace)
	var foe: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: 200}, Team.Faction.ENEMY), Vector2i(2, 0))
	game.squad_manager.active_squad = unit.squad
	assert_bool(game.squad_manager.queue_action(unit.squad,
			AttackAction.declare(unit, unit.movement.cell, foe.movement.cell))) \
		.override_failure_message("fixture: the aim was refused at the queue").is_true()
	game.refresh_action_queue(unit.squad)
	await _inspect(unit)
	var mace_slot := unit.inventory.find(mace)
	assert_bool(_has_row(_loadout_rows(mace_slot), "Equip")).override_failure_message(
			"fixture: the dock offered no Equip at rest, so its absence mid-pass would prove nothing").is_true()

	# The issue's sequence: the popup is open when Execute is pressed.
	var panel = game.unit_info_panel.inventory_panel
	panel._show_action_popup(mace_slot)
	var samples: Array[Dictionary] = []
	game.order_executor.volley_struck.connect(func(_attack: AttackAction) -> void:
		var sample := {"popup_left_open": panel.action_popup != null, "rows": _loadout_rows(mace_slot)}
		# ...and a re-Inspect mid-pass, which lands on set_unit's same-unit path: the door must ask the
		# gate, or that path would hand the verbs straight back.
		game.inspect_unit(unit)
		sample["rows_after_reinspect"] = _loadout_rows(mace_slot)
		samples.append(sample))

	game.squad_action_queue_control.execute_requested.emit()
	for _i in range(30):
		if unit.squad.has_acted:
			break
		await await_idle_frame()

	assert_bool(unit.squad.has_acted).override_failure_message(
			"fixture: the pass never ran").is_true()
	assert_array(samples).override_failure_message(
			"fixture: no volley struck, so the dock was never sampled mid-pass").is_not_empty()
	for sample: Dictionary in samples:
		assert_bool(sample["popup_left_open"]).override_failure_message(
				"the Equip popup opened before Execute was still up mid-pass").is_false()
		assert_array(sample["rows"]).override_failure_message(
				"the dock offered %s while the pass played the plan out" % [sample["rows"]]).is_empty()
		assert_array(sample["rows_after_reinspect"]).override_failure_message(
				"a mid-pass re-Inspect handed the gear verbs back: %s" % [sample["rows_after_reinspect"]]) \
			.is_empty()
	assert_object(unit.get_equipped_weapon()).is_same(sword)

	assert_bool(_has_row(_loadout_rows(mace_slot), "Equip")).override_failure_message(
			"the dock stayed read-only after the pass ended").is_true()


# set_unit early-returned on the same unit, so a re-Inspect kept the answer from the first one.
func test_a_re_inspect_of_the_same_unit_re_asks_the_gate() -> void:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 0))
	var sword := H.make_weapon(3)
	unit.add_item(sword)
	await _inspect(unit)
	var slot := unit.inventory.find(sword)
	assert_bool(_has_row(_loadout_rows(slot), "Unequip")).override_failure_message(
			"fixture: the dock offered no Unequip on the player's turn").is_true()

	# No edge fires for a turn moving under an open dock; the re-Inspect is what must notice.
	game.turn_manager.set_active_faction(Team.Faction.ENEMY)
	await _inspect(unit)

	assert_array(_loadout_rows(slot)).override_failure_message(
			"a re-Inspect kept offering gear on a unit the player no longer commands").is_empty()


# ==============================================================================
#  The pre-mission phase
# ==============================================================================

# A roster board with a deployment zone, stopped in the phase. False when the shipped content cannot
# carry the case, so the caller returns rather than asserting about what a roster holds.
func _enter_phase() -> bool:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		push_warning("no rosters are shipped, so the phase cannot be exercised")
		return false
	var mc: MissionController = game.mission_controller
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	game.scenario_manager.current_roster = names[0]
	game.scenario_manager.current_deployment_cap = 2
	var scenario: ScenarioData = game.scenario_manager.capture_scenario("inspect_dock_1351", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	mc.begin_mission(SCRATCH)
	await await_idle_frame()
	return mc.is_deploying()


func _drawn() -> Array[Unit]:
	var found: Array[Unit] = []
	for unit: Unit in game.units_root.get_children():
		if unit.drawn_from_roster:
			found.append(unit)
	return found


# A slot with something in it. The roster's kit is content, so it is never relied on: a unit that
# carries nothing is handed a test weapon (the factory deep-copied its data, so no roster is touched).
static func _a_filled_slot(unit: Unit) -> int:
	for i in range(unit.inventory.size()):
		if unit.inventory[i] != null:
			return i
	var weapon := H.make_weapon(3)
	unit.add_item(weapon)
	return unit.inventory.find(weapon)


func test_the_dock_is_read_only_in_the_pre_mission_phase_and_opens_at_commit() -> void:
	if not await _enter_phase():
		return
	var mc: MissionController = game.mission_controller
	mc.toggle_deployment_menu()   # Tab: the board, where the phase ring offers Inspect
	await await_idle_frame()
	var drawn := _drawn()
	assert_array(drawn).override_failure_message("fixture: the phase drew nobody onto the board").is_not_empty()
	var unit: Unit = drawn[0]
	var slot := _a_filled_slot(unit)
	assert_int(slot).override_failure_message("fixture: no slot could be filled").is_not_equal(-1)

	await _inspect(unit)
	assert_bool(game.unit_info_panel.is_showing_unit(unit)).override_failure_message(
			"fixture: the phase ring's Inspect opened no dock").is_true()
	assert_array(_loadout_rows(slot)).override_failure_message(
			"the dock offered gear in the pre-mission phase, past Loadout").is_empty()

	assert_bool(mc.commit_deployment()).override_failure_message("fixture: the commit was refused").is_true()
	await await_idle_frame()
	assert_bool(game.unit_info_panel.is_showing_unit(unit)).override_failure_message(
			"fixture: the commit closed the dock, so nothing can say whether it opened up").is_true()
	assert_bool(_has_row(_loadout_rows(slot), "Toss")).override_failure_message(
			"the dock stayed read-only after the phase committed").is_true()
