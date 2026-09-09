# The demo gate (#860) — which boards a SHIPPED build lists, and what it hides.
#
# Three questions, and the middle one is why this file exists at all:
#
#   * does `in_demo` survive the four-writer contract (capture -> apply -> clear)?
#   * does a build WITHOUT dev tools list only the ticked boards, and hide the fixtures
#     section and the Sandbox row?
#   * is a board that fails to load excluded rather than fatal?
#
# `DevTools.enabled()` reads OS.has_feature, which a headless run cannot make false, so the
# shipped-build branch is reached through `MissionController._open_mission_select(dev)` — the
# parameterised seam that exists for exactly this reason. The one hop no case here covers is
# `open_mission_select()` passing `DevTools.enabled()` into it, which is a single visible line.
#
# Fixture is test_mission_controller.gd's: the instanced root MUST be named "Main" under /root
# or game.gd's absolute /root/Main/DevOverlay lookup returns null and clear_board() dies on it.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

# user://, never res://: these boards exist to be READ BACK by the filter, and writing probe
# scenarios into Scenarios/missions/ would leave the repo dirty and feed the real menu.
const PROBE_DIR := "user://test_demo_gate/"

var _main: Node
var game: Node2D
var mc: MissionController


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	mc = game.mission_controller
	await await_idle_frame()


func after_test() -> void:
	if is_instance_valid(mc) and is_instance_valid(mc._select_screen):
		mc._select_screen.queue_free()
	get_tree().root.remove_child(_main)
	_main.free()
	_clear_probes()
	await await_idle_frame()   # #93/#114: drain before the suite tears the scene down


func _clear_probes() -> void:
	var dir := DirAccess.open(PROBE_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)


# A board on disk that declares nothing except whether it ships.
func _write_probe(file_name: String, in_demo: bool) -> String:
	DirAccess.make_dir_recursive_absolute(PROBE_DIR)
	var scenario := ScenarioData.new()
	scenario.scenario_name = file_name
	scenario.in_demo = in_demo
	var path := PROBE_DIR + file_name + ".tres"
	assert_int(ResourceSaver.save(scenario, path)).is_equal(OK)
	return path


# Close whatever screen is standing, then open one at the gate under test.
func _reopen(dev: bool) -> void:
	mc._close_mission_select()
	await await_idle_frame()
	mc._open_mission_select(dev)
	await await_idle_frame()
	assert_object(mc._select_screen).is_not_null()


func _row_labels(screen: Node) -> Array[String]:
	var labels: Array[String] = []
	for node: Node in _descendants(screen):
		if node is Button:
			labels.append((node as Button).text)
	return labels


func _section_texts(screen: Node) -> Array[String]:
	var texts: Array[String] = []
	for node: Node in _descendants(screen):
		if node is Label:
			texts.append((node as Label).text)
	return texts


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found


# ==============================================================================
#  The store: the four-writer contract (#860, the roster/deployment_cap shape)
# ==============================================================================

func test_in_demo_round_trips_through_capture_and_apply() -> void:
	var sm: ScenarioManager = game.scenario_manager
	sm.current_in_demo = true
	var captured := sm.capture_scenario("probe", true)
	assert_bool(captured.in_demo).is_true()   # capture READS the store

	sm.current_in_demo = false
	sm.apply_scenario(captured)
	await await_idle_frame()
	assert_bool(sm.current_in_demo).is_true()   # apply WRITES it back


func test_clear_board_unticks_the_store_so_a_sandbox_cannot_inherit_it() -> void:
	# The Save As trap this guards: a sandbox spawned after a ticked mission would otherwise
	# capture in_demo = true and bake a scratch fixture into the demo's mission list.
	var sm: ScenarioManager = game.scenario_manager
	sm.current_in_demo = true
	sm.clear_board()
	await await_idle_frame()
	assert_bool(sm.current_in_demo).is_false()
	assert_bool(sm.capture_scenario("sandbox", true).in_demo).is_false()


# ==============================================================================
#  The filter itself
# ==============================================================================

func test_the_filter_keeps_only_the_ticked_boards() -> void:
	var ticked := _write_probe("ships", true)
	var unticked := _write_probe("scratch", false)
	var kept := mc._missions_in_demo([ticked, unticked] as Array[String])
	assert_array(kept).contains_exactly([ticked])


func test_a_board_that_cannot_load_is_omitted_rather_than_fatal() -> void:
	# A dangling ext_resource is a HARD parse error, so through this reader an unloadable board
	# would take the whole title screen down. It costs one row instead.
	var ticked := _write_probe("ships", true)
	var kept := mc._missions_in_demo(
		[ticked, PROBE_DIR + "does_not_exist.tres"] as Array[String])
	assert_array(kept).contains_exactly([ticked])


# ==============================================================================
#  The wire: what each build actually renders
# ==============================================================================

# The SCREEN's own half. It gates only what it CAN gate -- the Sandbox row and the empty-state
# wording -- and deliberately renders whatever `other_paths` it is handed, so the fixtures
# section is asserted one level up where the decision actually lives.
func test_a_shipped_screen_drops_the_sandbox_row() -> void:
	var screen := MissionSelectScreen.open(
		game, [] as Array[String], [] as Array[String], false)
	await await_idle_frame()
	assert_array(_row_labels(screen)).not_contains(["Sandbox (Test Board)"])
	screen.queue_free()


func test_a_dev_screen_keeps_the_sandbox_row() -> void:
	var screen := MissionSelectScreen.open(
		game, [] as Array[String], [] as Array[String], true)
	await await_idle_frame()
	assert_array(_row_labels(screen)).contains(["Sandbox (Test Board)"])
	screen.queue_free()


# The pre-#860 hint would LIE in a shipped build: the missions exist on disk, they are simply
# withheld, so "save a scenario named missions/<name>" sends the reader to fix nothing.
func test_the_two_empty_states_say_different_things() -> void:
	var shipped := MissionSelectScreen.open(
		game, [] as Array[String], [] as Array[String], false)
	await await_idle_frame()
	assert_array(_section_texts(shipped)).contains(["No missions available in this build."])
	shipped.queue_free()
	await await_idle_frame()

	var dev := MissionSelectScreen.open(
		game, [] as Array[String], [] as Array[String], true)
	await await_idle_frame()
	assert_array(_section_texts(dev)).contains(
		["No missions yet — save a scenario named  missions/<name>"])
	dev.queue_free()


# And the CONTROLLER's half -- the decision itself. A shipped build supplies NO fixtures, so the
# section cannot render; a dev build supplies them and it does.
func test_the_controller_withholds_the_fixtures_section_from_a_shipped_build() -> void:
	# Precondition, stated rather than assumed: the absence below has to mean "withheld", not
	# "there were none to show". Guards the case against an empty fixture library.
	var others := 0
	var missions: Array[String] = game.scenario_manager.get_missions()
	for path: String in game.scenario_manager.get_saved_scenarios():
		if not missions.has(path):
			others += 1
	assert_int(others).override_failure_message(
		"No non-mission scenarios on disk, so this case proves nothing.").is_greater(0)

	# game._ready() ALREADY opened the boot screen, and _open_mission_select returns early while
	# one stands -- without this the case asserts against the dev screen the fixture booted with,
	# which is exactly how it failed first time round.
	await _reopen(false)
	assert_array(_section_texts(mc._select_screen)).not_contains(["SCENARIOS & FIXTURES"])
	assert_array(_row_labels(mc._select_screen)).not_contains(["Sandbox (Test Board)"])

	await _reopen(true)
	assert_array(_section_texts(mc._select_screen)).contains(["SCENARIOS & FIXTURES"])
	assert_array(_row_labels(mc._select_screen)).contains(["Sandbox (Test Board)"])


# THE WIRE ITSELF: _open_mission_select(false) must actually APPLY the filter. Every other case
# here proves the filter works or that the screen hides a row -- delete the `if not dev` line and
# all of them still pass, because the mission LIST is the one thing they never look at.
#
# Stated as a property, not as a copy of the implementation: no board the shipped screen lists may
# be unticked. That survives the dev ticking boards later, which an expected-list assertion would
# not.
func test_a_shipped_build_lists_no_unticked_board() -> void:
	var on_disk: Array[String] = game.scenario_manager.get_missions()
	var unticked := 0
	for path: String in on_disk:
		var board := load(path) as ScenarioData
		if board != null and not board.in_demo:
			unticked += 1
	assert_int(unticked).override_failure_message(
		"Every mission on disk is ticked, so this case cannot tell a filter from no filter."
	).is_greater(0)

	await _reopen(false)
	var listed := _row_labels(mc._select_screen)
	for path: String in on_disk:
		var board := load(path) as ScenarioData
		if board == null or board.in_demo:
			continue
		var label := ScenarioManager.display_name(path).trim_prefix("missions/")
		assert_array(listed).override_failure_message(
			"'%s' is not in the demo but a shipped build listed it." % label
		).not_contains([label])
