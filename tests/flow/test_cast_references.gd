# Cast reference semantics (#177): an AUTHORED save writes a unit spawned from a standalone
# character file as a REFERENCE to that file (state_saved = false, nothing captured), so every
# load re-reads the character as it is THEN — while the default capture stays the exact #87
# snapshot, and a snapshot applied over a seeded kit replaces it rather than doubling it.
#
# Real game scene (the #114 fixture shape, same reasons as test_scenario_round_trip.gd):
# capture/apply only exist together on a real ScenarioManager.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const FIXTURE_PATH := "res://tests/support/CastFixture.tres"
const H := preload("res://tests/support/squad_fixtures.gd")

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


func _spawn_cast(cell: Vector2i) -> Unit:
	var source: UnitData = load(FIXTURE_PATH)
	var unit: Unit = game.spawn_unit(source, cell)
	assert_object(unit).is_not_null()
	return unit


func _sole_unit() -> Unit:
	var units: Array[Node] = game.units_root.get_children()
	assert_int(units.size()).is_equal(1)
	return units[0] as Unit


func _carried_count(unit: Unit) -> int:
	var count := 0
	for item in unit.inventory:
		if item != null:
			count += 1
	return count


func test_authored_capture_references_the_character_file() -> void:
	var source: UnitData = load(FIXTURE_PATH)
	_spawn_cast(Vector2i(1, 1))

	var snap: ScenarioData = sm.capture_scenario("__cast", true)
	assert_int(snap.unit_entries.size()).is_equal(1)
	var entry: ScenarioUnitEntry = snap.unit_entries[0]
	assert_object(entry.unit_data).is_same(source)   # the FILE resource itself -> serializes as ExtResource
	assert_bool(entry.state_saved).is_false()


func test_reference_load_rereads_the_character_file() -> void:
	var source: UnitData = load(FIXTURE_PATH)
	_spawn_cast(Vector2i(1, 1))
	var snap: ScenarioData = sm.capture_scenario("__cast", true)

	# First reload: the kit re-seeds from the file, no state block applies.
	sm.apply_scenario(snap)
	await await_idle_frame()
	assert_bool(_sole_unit().unit_instance.has_job("scout")).is_true()

	# The semantics proof: edit the character, reload the same scenario, see the edit.
	# Mutate -> apply -> read -> RESTORE before asserting, so a failure can't leak the
	# mutation into the shared resource cache for later suites.
	source.base_stats[Stats.Stat.STR] = 42
	sm.apply_scenario(snap)
	await await_idle_frame()
	var seen_str: int = _sole_unit().unit_instance.get_base_stat(Stats.Stat.STR)
	source.base_stats.erase(Stats.Stat.STR)
	assert_int(seen_str).is_equal(42)


func test_reference_survives_a_load_and_resave() -> void:
	# The real authoring loop: load a mission, tweak the board, Update. The loader must hand
	# spawn_unit the entry's resource ITSELF (not a copy) or the re-capture silently embeds —
	# exactly what the old outer duplicate(true) did.
	var source: UnitData = load(FIXTURE_PATH)
	_spawn_cast(Vector2i(1, 1))
	var snap: ScenarioData = sm.capture_scenario("__cast", true)

	sm.apply_scenario(snap)
	await await_idle_frame()
	var resaved: ScenarioData = sm.capture_scenario("__cast_again", true)
	var entry: ScenarioUnitEntry = resaved.unit_entries[0]
	assert_object(entry.unit_data).is_same(source)
	assert_bool(entry.state_saved).is_false()


func test_default_capture_still_embeds_a_snapshot() -> void:
	var source: UnitData = load(FIXTURE_PATH)
	_spawn_cast(Vector2i(1, 1))

	var snap: ScenarioData = sm.capture_scenario("__snap")
	var entry: ScenarioUnitEntry = snap.unit_entries[0]
	assert_bool(entry.state_saved).is_true()
	assert_bool(entry.unit_data == source).is_false()   # an embedded copy, not the file
	assert_str(entry.unit_data.resource_path).is_empty()


func test_snapshot_apply_replaces_a_seeded_kit_instead_of_doubling_it() -> void:
	var data := H.make_unit_data({}, Team.Faction.PLAYER)
	data.starting_inventory = [H.make_weapon(3)]
	var unit: Unit = game.spawn_unit(data, Vector2i(1, 1))
	assert_object(unit).is_not_null()
	assert_int(_carried_count(unit)).is_equal(1)

	var snap: ScenarioData = sm.capture_scenario("__double")   # ad-hoc unit -> full snapshot
	sm.apply_scenario(snap)
	await await_idle_frame()
	assert_int(_carried_count(_sole_unit())).is_equal(1)   # the seeded item was cleared, then restored once


func test_saved_subresource_is_never_provenance() -> void:
	_spawn_cast(Vector2i(1, 1))
	var snap: ScenarioData = sm.capture_scenario("__roundtrip")   # default -> embedded unit_data

	# Through real serialization: a sub-resource's runtime path (empty or "file::id") must
	# never register as a character file when the scenario is loaded back and applied.
	var temp_path := "user://__cast_provenance_test.tres"
	assert_int(ResourceSaver.save(snap, temp_path)).is_equal(OK)
	var reloaded: ScenarioData = ResourceLoader.load(temp_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(temp_path)
	assert_object(reloaded).is_not_null()

	sm.apply_scenario(reloaded)
	await await_idle_frame()
	assert_object(_sole_unit().unit_data_source).is_null()


func test_existing_saves_read_as_snapshots() -> void:
	# Back-compat: state_saved is absent from every pre-#177 .tres and must default TRUE.
	var legacy: ScenarioData = load("res://Scenarios/fixtures/WeaponsTest.tres")
	assert_object(legacy).is_not_null()
	assert_bool(legacy.unit_entries.is_empty()).is_false()
	for entry: ScenarioUnitEntry in legacy.unit_entries:
		assert_bool(entry.state_saved).is_true()
