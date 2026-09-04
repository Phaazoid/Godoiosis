# A mission names a roster (#735): the ScenarioData field, its store on ScenarioManager, and the
# four writers of that store. Nothing reads a roster to spawn from yet -- #737 is the first reader,
# and until then this binding IS the feature.
#
# Real game scene (test_cast_references.gd's shape, same reason): capture_scenario and
# apply_scenario only exist together on a real ScenarioManager.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const CAST := "res://tests/support/CastFixture.tres"
const SCRATCH := "user://__roster_roundtrip_735.tres"

var _main: Node
var game: Node2D
var sm: ScenarioManager


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	sm = game.scenario_manager
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


# --- The store's four writers (ScenarioManager.gd's stated contract) ---

func test_capture_writes_the_named_roster_onto_the_scenario() -> void:
	sm.current_roster = "Company"
	var snap := sm.capture_scenario("roster_capture")
	assert_str(snap.roster).is_equal("Company")


func test_apply_reads_the_named_roster_back_into_the_store() -> void:
	sm.current_roster = "Company"
	var snap := sm.capture_scenario("roster_apply")
	sm.current_roster = "something else entirely"
	sm.apply_scenario(snap)
	await await_idle_frame()
	assert_str(sm.current_roster).is_equal("Company")


func test_clear_board_zeroes_the_store() -> void:
	# The third writer, and the one nothing else would catch. tests/law/test_board_scoped_state.gd
	# governs `static var`s in Classes/board and Classes/presentation; current_roster is an instance
	# var on ScenarioManager, which that law never scans.
	#
	# What it prevents: load a roster mission, hit Sandbox (which lands in clear_board with no
	# ScenarioData at all), Save As -- and the fixture you just saved names the last mission's pool.
	sm.current_roster = "Company"
	sm.clear_board()
	assert_str(sm.current_roster).is_equal("")


func test_a_sandbox_capture_after_a_roster_mission_names_nobody() -> void:
	# The same rule asserted at the surface it actually breaks at, rather than at the store: this is
	# the fault a reader would recognise, and it stays true even if the reset later moves.
	sm.current_roster = "Company"
	sm.clear_board()
	var snap := sm.capture_scenario("sandbox_after_roster")
	assert_str(snap.roster).is_equal("")


# --- Roster-less boards are the ones that already exist ---

func test_a_board_naming_no_roster_round_trips_as_empty() -> void:
	var snap := sm.capture_scenario("no_roster")
	assert_str(snap.roster).is_equal("")
	sm.apply_scenario(snap)
	await await_idle_frame()
	assert_str(sm.current_roster).is_equal("")


func test_every_shipped_scenario_names_a_roster_that_resolves() -> void:
	# The binding's own integrity, asked of what ships -- the sibling of BoardLint's live-board
	# rule, in the file-shaped form a lint structurally cannot ask (test_board_lint.gd's split).
	var paths := sm.get_saved_scenarios()
	assert_bool(paths.is_empty()).override_failure_message(
		"no scenarios found -- the sweep would pass over nothing").is_false()
	var problems: Array[String] = []
	for path: String in paths:
		var scenario: ScenarioData = ContentRepair.load_tolerant(path)
		if scenario == null or scenario.roster == "":
			continue
		if not RosterCatalog.saved_rosters().has(scenario.roster):
			problems.append("%s names roster '%s', which does not exist" % [path, scenario.roster])
	assert_array(problems).is_empty()


# --- The catalog ---

func test_the_shipped_roster_resolves_and_carries_entries() -> void:
	var names := RosterCatalog.saved_rosters()
	assert_array(names).contains(["Company"])
	var roster := RosterCatalog.resolve("Company")
	assert_object(roster).is_not_null()
	assert_bool(roster.entries.is_empty()).override_failure_message(
		"the shipped roster offers nobody").is_false()
	for entry: ScenarioUnitEntry in roster.entries:
		assert_object(entry.unit_data).override_failure_message(
			"a roster entry resolves to no character file").is_not_null()


func test_an_absent_name_resolves_to_null_rather_than_a_substitute() -> void:
	# Deliberately unlike LookKnobs.resolve, which falls back to the default preset: a board with no
	# look plays as authored, a board with no POOL does not. Substituting some other roster would
	# hand the player a different mission, so null is the honest answer and BoardLint flags it.
	assert_object(RosterCatalog.resolve("no such roster")).is_null()


func test_the_empty_name_is_absence_and_not_an_error() -> void:
	assert_object(RosterCatalog.resolve("")).is_null()


# --- The serialization boundary ---

func test_a_roster_survives_a_real_save_and_load() -> void:
	# Through an actual .tres write/read rather than in memory, the
	# test_saved_subresource_is_never_provenance idiom: a roster holds ScenarioUnitEntry
	# sub-resources, and entries are exactly where a typed-array round trip can go wrong.
	var reference := ScenarioUnitEntry.new()
	reference.unit_data = load(CAST)
	reference.state_saved = false

	var snapshot := ScenarioUnitEntry.new()
	snapshot.unit_data = load(CAST)
	snapshot.state_saved = true
	snapshot.stats = {Stats.Stat.STR: 7}
	snapshot.jobs = ["a"]

	var roster := Roster.new()
	roster.entries = [reference, snapshot]

	assert_int(ResourceSaver.save(roster, SCRATCH)).is_equal(OK)
	var loaded := ResourceLoader.load(SCRATCH, "", ResourceLoader.CACHE_MODE_IGNORE) as Roster
	assert_object(loaded).is_not_null()
	assert_int(loaded.entries.size()).is_equal(2)
	assert_bool(loaded.entries[0].state_saved).is_false()
	assert_bool(loaded.entries[1].state_saved).is_true()
	assert_int(loaded.entries[1].stats[Stats.Stat.STR]).is_equal(7)
	assert_array(loaded.entries[1].jobs).contains(["a"])
