# The deployment zone and the authored cap (#736) -- the roster's other half. Three things:
# ScenarioData.deployment_cap and the four writers of its store, a DEPLOYMENT zone surviving the
# board round trip, and the rule that makes such a zone stop being drawn once the battle starts.
#
# Real game scene (test_roster_binding.gd's shape, same reason): capture_scenario and
# apply_scenario only exist together on a real ScenarioManager, and hidden_zone_names is read by
# an overlay this suite asserts on.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const SCRATCH := "user://__deployment_roundtrip_736.tres"
const DEPLOYMENT := ZoneManager.Kind.DEPLOYMENT

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
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	sm = game.scenario_manager
	mc = game.mission_controller
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _paint(zone_name: String, cells: Array) -> void:
	for cell: Vector2i in cells:
		game.zone_manager.paint_cell(zone_name, DEPLOYMENT, cell)


# --- The cap's four writers (ScenarioManager's stated contract) ---

func test_capture_writes_the_authored_cap_onto_the_scenario() -> void:
	sm.current_deployment_cap = 6
	var snap := sm.capture_scenario("cap_capture")
	assert_int(snap.deployment_cap).is_equal(6)


func test_apply_reads_the_authored_cap_back_into_the_store() -> void:
	sm.current_deployment_cap = 6
	var snap := sm.capture_scenario("cap_apply")
	sm.current_deployment_cap = 99
	sm.apply_scenario(snap)
	await await_idle_frame()
	assert_int(sm.current_deployment_cap).is_equal(6)


# The writer nothing else would catch, and #735's mutant proved it: tests/law/test_board_scoped_state.gd
# scans `static var`s in Classes/board and Classes/presentation, and this is an instance var on
# ScenarioManager. Without it, Sandbox after a capped mission inherits that mission's cap.
func test_clear_board_zeroes_the_cap() -> void:
	sm.current_deployment_cap = 6
	sm.clear_board()
	assert_int(sm.current_deployment_cap).is_equal(0)


func test_a_sandbox_capture_after_a_capped_mission_caps_nobody() -> void:
	sm.current_deployment_cap = 6
	sm.clear_board()   # what spawn_sandbox lands in, with no ScenarioData to read from
	var snap := sm.capture_scenario("sandbox_after_cap")
	assert_int(snap.deployment_cap).is_equal(0)


# 0 is "as many as fit" AND the field's own default, so a board that never authored a cap cannot
# read as one that authored a cap of zero -- which would let nobody deploy at all.
func test_a_board_authoring_no_cap_round_trips_as_zero() -> void:
	var snap := sm.capture_scenario("no_cap")
	assert_int(snap.deployment_cap).is_equal(0)
	sm.current_deployment_cap = 4
	sm.apply_scenario(snap)
	await await_idle_frame()
	assert_int(sm.current_deployment_cap).is_equal(0)


func test_the_cap_survives_a_real_save_and_load() -> void:
	sm.current_deployment_cap = 5
	var snap := sm.capture_scenario("cap_disk")
	assert_int(ResourceSaver.save(snap, SCRATCH)).is_equal(OK)

	# CACHE_MODE_IGNORE so this reads the FILE rather than the object just saved.
	var reloaded := ResourceLoader.load(SCRATCH, "", ResourceLoader.CACHE_MODE_IGNORE) as ScenarioData
	assert_object(reloaded).is_not_null()
	assert_int(reloaded.deployment_cap).is_equal(5)


# --- The zone itself, through the real board round trip ---

func test_a_deployment_zone_survives_capture_and_apply() -> void:
	_paint("landing", [Vector2i(2, 2), Vector2i(3, 2)])
	var snap := sm.capture_scenario("zone_roundtrip")
	game.zone_manager.load_dict({})

	sm.apply_scenario(snap)
	await await_idle_frame()

	assert_int(game.zone_manager.kind_of("landing")).is_equal(DEPLOYMENT)
	assert_array(game.zone_manager.cells_in("landing")).contains_exactly_in_any_order(
		[Vector2i(2, 2), Vector2i(3, 2)])


# --- Visible while authoring, gone once the battle starts (dev, 2026-09-04) ---

func test_a_deployment_zone_is_drawn_while_no_turn_has_begun() -> void:
	_paint("landing", [Vector2i(2, 2), Vector2i(3, 2)])
	game.overlay_manager.redraw_zones(game.zone_manager, mc.hidden_zone_names())

	assert_array(mc.hidden_zone_names()).is_empty()
	# The visible consequence, not just the list: this is the authoring session the dev paints in.
	assert_array(game.overlay_manager.deployment_overlay.get_used_cells()).contains_exactly_in_any_order(
		[Vector2i(2, 2), Vector2i(3, 2)])


# Driven through _begin_turn rather than by setting the flag: that is the one door every arrival
# takes (mission select, restart, resume, sandbox), and the dev-tools Load path deliberately takes
# none of them -- which is the whole reason a painted zone stays visible while authoring.
func test_beginning_a_turn_stops_the_deployment_zone_being_drawn() -> void:
	_paint("landing", [Vector2i(2, 2), Vector2i(3, 2)])
	game.overlay_manager.redraw_zones(game.zone_manager, mc.hidden_zone_names())
	assert_array(game.overlay_manager.deployment_overlay.get_used_cells()).is_not_empty()

	mc._begin_turn()
	await await_idle_frame()

	assert_array(mc.hidden_zone_names()).contains("landing")
	assert_array(game.overlay_manager.deployment_overlay.get_used_cells()).is_empty()


# The store the deployment zones JOIN, rather than replace. Before #736 this list was answered
# twice -- MissionController passed _captured_zones while ScenarioManager and DevController passed
# nothing -- so painting a zone mid-battle re-lit a capture point that had already been claimed.
func test_hidden_zones_still_carry_the_claimed_capture_points() -> void:
	game.zone_manager.paint_cell("throne", ZoneManager.Kind.CAPTURE, Vector2i(5, 5))
	_paint("landing", [Vector2i(2, 2)])
	mc.capture("throne")
	mc._begin_turn()
	await await_idle_frame()

	assert_array(mc.hidden_zone_names()).contains_exactly_in_any_order(["throne", "landing"])


# A board teardown is a mission START, so the next board is authorable again.
func test_clearing_the_board_puts_the_deployment_window_back() -> void:
	_paint("landing", [Vector2i(2, 2)])
	mc._begin_turn()
	await await_idle_frame()
	assert_array(mc.hidden_zone_names()).contains("landing")

	sm.clear_board()
	_paint("landing", [Vector2i(2, 2)])

	assert_array(mc.hidden_zone_names()).is_empty()


# A board that paints no deployment zone is every board that exists today, and beginning its turn
# must not start hiding anything -- the guard against the flag being read as a blanket "hide zones".
func test_beginning_a_turn_hides_nothing_on_a_board_with_no_deployment_zone() -> void:
	game.zone_manager.paint_cell("gate", ZoneManager.Kind.PATROL, Vector2i(1, 1))
	mc._begin_turn()
	await await_idle_frame()

	assert_array(mc.hidden_zone_names()).is_empty()
