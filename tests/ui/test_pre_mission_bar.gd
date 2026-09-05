# The pre-mission phase's board-side bar (#774): the corner affordance that is up exactly while the
# screen (#740) is swapped away, so the phase never leaves the frame with nothing on it.
#
# THREE CASES ON PURPOSE. The bar's teardown at the phase's three exits is not re-tested here --
# reset, commit and abandon all route through _close_deployment_menu, which
# tests/ui/test_pre_mission_screen.gd already pins one case each for, and its Abandon case carries
# the one added assertion that the bar goes with them. Begin's refusal with nobody placed is not
# re-tested either: it is commit_deployment's own voice (#739) and already has a case. What is left
# is what only this ticket can break -- the swap, the two buttons' wires, and the key that started
# the whole thing.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const SCRATCH := "user://__pre_mission_774.tres"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROW_WIDTH := 10
const ZONE_CELLS := 6

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	mc = game.mission_controller
	sm = game.scenario_manager
	mc._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _author(roster: String, cap: int) -> String:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = roster
	sm.current_deployment_cap = cap
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	mc.set_objectives(objectives)
	var scenario := sm.capture_scenario("pre_mission_774", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


func _enter_phase(cap := 2) -> bool:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		push_warning("no rosters are shipped, so the phase cannot be exercised")
		return false
	mc.begin_mission(_author(names[0], cap))
	await await_idle_frame()
	return mc.is_deploying()


func _bar() -> PreMissionBar:
	for child in game.ui_layer.get_children():
		if child is PreMissionBar:
			return child
	return null


func _screen() -> PreMissionScreen:
	for child in game.ui_layer.get_children():
		if child is PreMissionScreen:
			return child
	return null


# --- the swap, and the button that is the whole point of the ticket ---

# The complement is the rule: inside the phase exactly one of the two is on screen. Before this the
# board came up with no chrome at all, and the only way back was a key nobody had been told about.
func test_the_bar_stands_in_for_the_screen_and_hands_the_frame_back() -> void:
	if not await _enter_phase():
		return
	assert_bool(_screen().visible).override_failure_message(
		"the phase did not open on the screen").is_true()
	assert_bool(_bar().visible).override_failure_message(
		"the bar is up UNDER the screen -- two surfaces for one phase").is_false()

	mc.toggle_deployment_menu()
	await await_idle_frame()
	assert_bool(_screen().visible).is_false()
	assert_bool(_bar().visible).override_failure_message(
		"the board came up with nothing on it -- the #774 bug itself").is_true()

	# ...and back through the button, which is the affordance the key never was.
	_bar()._loadout_button.pressed.emit()
	await await_idle_frame()
	assert_bool(_screen().visible).override_failure_message(
		"Loadout did not bring the menu back").is_true()
	assert_bool(_bar().visible).is_false()


# A pressed signal wired to nothing is legal GDScript, so the button gets driven rather than the
# controller. commit_deployment's own rules are pinned elsewhere; this is the wire.
func test_begin_from_the_bar_starts_the_mission() -> void:
	if not await _enter_phase():
		return
	mc.toggle_deployment_menu()
	await await_idle_frame()
	assert_int(mc.deployed_roster_count()).override_failure_message(
		"precondition: the phase drew nobody onto the board").is_greater(0)

	_bar()._begin_button.pressed.emit()
	await await_idle_frame()

	assert_bool(mc.is_deploying()).override_failure_message(
		"Begin on the bar did not start the mission").is_false()
	assert_object(_bar()).override_failure_message(
		"the bar outlived the mission it started").is_null()


# THE case this ticket exists for. Tab was bound, registered in Controls.gd and named in a tooltip,
# and nothing anywhere drove it -- test_pre_mission_screen.gd calls toggle_deployment_menu()
# directly, so the function was pinned and the wire from the keypress was not. The event is built
# the way project.godot binds it, on physical_keycode, so a re-bind that misses this action fails
# here rather than in someone's hands.
func test_the_tab_key_reaches_the_swap() -> void:
	if not await _enter_phase():
		return
	var key := InputEventKey.new()
	key.physical_keycode = KEY_TAB
	key.pressed = true

	game._input(key)
	await await_idle_frame()
	assert_bool(_screen().visible).override_failure_message(
		"Tab did not reach the swap -- the key is bound and dead").is_false()
	assert_bool(_bar().visible).is_true()

	game._input(key)
	await await_idle_frame()
	assert_bool(_screen().visible).override_failure_message(
		"Tab swaps one way only").is_true()
