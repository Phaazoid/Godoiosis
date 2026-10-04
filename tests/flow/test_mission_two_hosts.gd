# TWO HOSTS, ONE MISSION (#46 slice 2). A saved mission is loaded by two loaders -- the game's
# ScenarioManager and the headless BoardBuilder -- and scored by one MissionState each host owns. Both
# loaders read a scenario's mission through MissionState.apply_scenario and each unit's placement
# through ScenarioUnitEntry.apply_placement; this is the law that keeps them honest: one mission,
# authored through the game's own capture, must come back the same in both, down to the clock, the
# captured zones, who the mission protects and what every squad was told to be.
#
# The same law over what each loader does with an ENTRY (#46): both iterate valid_entries, ask the one
# spawn gate (a refused entry is dropped by both, a saved body still lies in deep water in both), hand
# the spawn the entry's own UnitData so a cast reference keeps its provenance, and re-link every armed
# Guard through ScenarioManager.relink_guards.
#
# What it cannot see, by construction: a fault inside one of the two shared doors moves both hosts
# together and they still agree. test_mission_state and the headless scoring suite pin those.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const SCRATCH := "user://__mission_two_hosts.tres"
const TEST_SAVE_DIR := "user://__test_saves_mission_two_hosts/"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const WIDTH := 10
const HEIGHT := 4

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController
var _sess
var _written: Array[String] = []


func before_test() -> void:
	ScenarioManager.save_dir = TEST_SAVE_DIR
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
	ScenarioManager.save_dir = ScenarioManager.DEFAULT_SAVE_DIR
	_sess = null
	_written.append(SCRATCH)
	for path in _written:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_written.clear()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).override_failure_message("precondition: nothing would spawn at %s" % cell).is_not_null()
	return unit


func _paint() -> void:
	for x in range(WIDTH):
		for y in range(HEIGHT):
			game.grid.paint(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)


# A file of its own per case: load() serves the resource cache, so a second board saved over one
# path would come back as the first.
func _save(scenario: ScenarioData, tag: String) -> String:
	var path := "user://__mission_two_hosts_%s.tres" % tag
	assert_int(ResourceSaver.save(scenario, path)).is_equal(OK)
	_written.append(path)
	return path


# A mission with every field the two doors carry set off its default, taken mid-battle, through the
# game's own capture, and saved where both hosts can load it.
func _author() -> String:
	_paint()
	game.zone_manager.paint_cell("North", ZoneManager.Kind.CAPTURE, Vector2i(2, 0))
	game.zone_manager.paint_cell("South", ZoneManager.Kind.CAPTURE, Vector2i(2, 3))
	for y in range(HEIGHT):
		game.zone_manager.paint_cell("Post", ZoneManager.Kind.PATROL, Vector2i(WIDTH - 2, y))

	var vip := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	vip.must_survive = true
	_spawn(Team.Faction.PLAYER, Vector2i(0, 2))
	var sentry := _spawn(Team.Faction.ENEMY, Vector2i(WIDTH - 1, 1))
	var lookout := _spawn(Team.Faction.ENEMY, Vector2i(WIDTH - 1, 2))
	game.squad_manager.join_squad(lookout, sentry.squad)
	assert_bool(sentry.is_leader()).override_failure_message("precondition: the sentry does not lead its squad").is_true()
	sentry.squad.squad_name = "Watch"
	sentry.squad.archetype = AIArchetype.Type.SENTRY
	sentry.squad.zone_name = "Post"

	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.CAPTURE]
	var lose: Array[MissionRules.LoseCondition] = [
			MissionRules.LoseCondition.ROUND_LIMIT, MissionRules.LoseCondition.PROTECTED_UNIT_LOST]
	mc.set_objectives(objectives)
	mc.set_lose_conditions(lose, 5)
	var ai: Array[Team.Faction] = [Team.Faction.ENEMY]
	game.ai_controller.set_ai_factions(ai)
	var taken: Array[String] = ["North"]
	mc.mission.restore(taken, true, 2)   # two rounds in, one zone claimed

	assert_int(ResourceSaver.save(sm.capture_scenario("mission_two_hosts"), SCRATCH)).is_equal(OK)
	return SCRATCH


func _open_both() -> void:
	await _load_both(_author())


# One saved file, loaded by the game's ScenarioManager and then onto a fresh headless board.
func _load_both(path: String) -> void:
	sm.load_scenario(path)
	await await_idle_frame()
	var board := BoardBuilder.build(self, "MissionTwoHostsHeadless")
	auto_free(board.root)
	await BoardBuilder.load_scenario(board, path)
	_sess = PlaySession.new(board)


static func _mission_picture(mission: MissionState) -> Array:
	return [mission.objectives, mission.lose_conditions, mission.round_limit, mission.rounds_elapsed,
			mission.contested, mission.captured_zones]


# Per unit, in cell order: what apply_placement writes, read back off the unit and its squad.
static func _placement_picture(units: Array[Unit]) -> Array:
	var by_cell := {}
	for unit: Unit in units:
		var squad: Squad = unit.squad
		by_cell[unit.movement.cell] = [unit.movement.cell, unit.must_survive, unit.is_leader(),
				squad.squad_name, AIArchetype.Type.keys()[squad.archetype], squad.zone_name, squad.home_cell]
	var cells: Array = by_cell.keys()
	cells.sort()
	var rows: Array = []
	for cell in cells:
		rows.append(by_cell[cell])
	return rows


# Per unit, in cell order: its lifecycle, the character file it came from, and the Guard it holds --
# the ward's cell and whether the block is spent.
static func _entry_picture(units: Array[Unit]) -> Array:
	var by_cell := {}
	for unit: Unit in units:
		var source: UnitData = unit.unit_data_source
		var guard: GuardWard = unit.guard
		var held: Array = [] if guard == null else [guard.ward.movement.cell, guard.spent]
		by_cell[unit.movement.cell] = [unit.movement.cell, Unit.LifecycleState.keys()[unit.lifecycle_state],
				"<no file>" if source == null else source.resource_path, held]
	var cells: Array = by_cell.keys()
	cells.sort()
	var rows: Array = []
	for cell in cells:
		rows.append(by_cell[cell])
	return rows


static func _unit_at(units: Array[Unit], cell: Vector2i) -> Unit:
	for unit: Unit in units:
		if unit.movement.cell == cell:
			return unit
	return null


func _game_units() -> Array[Unit]:
	var units: Array[Unit] = []
	for child in game.units_root.get_children():
		if child is Unit:
			units.append(child)
	return units


func _agree(what: String, g: Variant, p: Variant) -> void:
	assert_str(str(p)).override_failure_message(
		"the hosts disagree about %s\n  game:     %s\n  headless: %s" % [what, str(g), str(p)]).is_equal(str(g))


# ==============================================================================

func test_both_hosts_load_the_same_mission() -> void:
	await _open_both()
	var g := _mission_picture(mc.mission)
	assert_int(mc.mission.rounds_elapsed).override_failure_message(
		"precondition: the game did not load the clock back, so agreement would be on defaults").is_equal(2)
	_agree("the mission", g, _mission_picture(_sess.mission))


func test_both_hosts_place_every_unit_the_same() -> void:
	await _open_both()
	var g := _placement_picture(_game_units())
	assert_str(str(g)).override_failure_message(
		"precondition: the game loaded no Sentry, so agreement would be on defaults").contains("SENTRY")
	assert_str(str(g)).override_failure_message(
		"precondition: the game loaded nobody it protects").contains("true")
	_agree("unit placement", g, _placement_picture(_sess.live_units()))


# ==============================================================================
#  What each loader does with an entry
# ==============================================================================

func test_both_hosts_relink_every_armed_guard() -> void:
	_paint()
	var blocker := _spawn(Team.Faction.PLAYER, Vector2i(1, 0))
	var ward := _spawn(Team.Faction.PLAYER, Vector2i(2, 0))
	var spent_blocker := _spawn(Team.Faction.ENEMY, Vector2i(WIDTH - 2, 0))
	var spent_ward := _spawn(Team.Faction.ENEMY, Vector2i(WIDTH - 1, 0))
	blocker.arm_guard(ward, blocker.get_guard_range())
	spent_blocker.arm_guard(spent_ward, spent_blocker.get_guard_range())
	spent_blocker.spend_guard()
	await _load_both(_save(sm.capture_scenario("two_hosts_guards"), "guards"))

	var g_units := _game_units()
	var g_blocker := _unit_at(g_units, Vector2i(1, 0))
	var g_spent := _unit_at(g_units, Vector2i(WIDTH - 2, 0))
	assert_bool(g_blocker != null and g_blocker.guard != null and g_spent != null and g_spent.guard != null) \
		.override_failure_message("precondition: the game reloaded without both Guards, so agreement would be on none") \
		.is_true()
	assert_bool(g_spent != null and g_spent.guard != null and g_spent.guard.spent) \
		.override_failure_message("precondition: the game reloaded the spent Guard fresh").is_true()
	_agree("every armed Guard", _entry_picture(g_units), _entry_picture(_sess.live_units()))


func test_both_hosts_keep_a_cast_references_provenance() -> void:
	_paint()
	var cast: Dictionary = UnitCatalog.get_characters_by_file()
	var files: Array = cast.keys()
	assert_bool(files.is_empty()).override_failure_message(
		"precondition: no character file under %s to reference" % UnitCatalog.CHARACTER_DIR).is_false()
	if files.is_empty():
		return
	files.sort()
	var source: UnitData = cast[files[0]]
	var spawned: Unit = game.spawn_unit(source, Vector2i(1, 1))
	assert_object(spawned).override_failure_message("precondition: the character would not spawn").is_not_null()
	var authored: ScenarioData = sm.capture_scenario("two_hosts_cast", true)
	assert_bool(authored.unit_entries.size() == 1 and not authored.unit_entries[0].state_saved) \
		.override_failure_message("precondition: the authored capture did not save a REFERENCE entry").is_true()
	await _load_both(_save(authored, "cast"))

	var g_units := _game_units()
	var g_unit := _unit_at(g_units, Vector2i(1, 1))
	assert_bool(g_unit != null and g_unit.unit_data_source != null) \
		.override_failure_message("precondition: the game lost the reference's provenance itself").is_true()
	_agree("where each unit came from", _entry_picture(g_units), _entry_picture(_sess.live_units()))


func test_both_hosts_drop_an_entry_the_spawn_gate_refuses() -> void:
	_paint()
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	_spawn(Team.Faction.ENEMY, Vector2i(WIDTH - 1, 0))
	var scenario: ScenarioData = sm.capture_scenario("two_hosts_gate")
	# One column past the right edge of everything painted: no ground, so the gate refuses it.
	var used: Rect2i = game.grid.get_used_rect()
	var off_map := Vector2i(used.end.x, used.position.y)
	var ground: TileData = game.grid.get_cell_tile_data(off_map)
	assert_object(ground).override_failure_message("precondition: %s is painted" % off_map).is_null()
	scenario.unit_entries[1].cell = off_map
	await _load_both(_save(scenario, "gate"))

	var g_units := _game_units()
	assert_int(g_units.size()).override_failure_message(
		"precondition: the game kept the refused entry or lost the witness (%d units)" % g_units.size()).is_equal(1)
	_agree("which entries spawned", _entry_picture(g_units), _entry_picture(_sess.live_units()))


func test_both_hosts_lay_a_saved_body_in_deep_water() -> void:
	_paint()
	var water := Vector2i(2, 2)
	game.grid.paint(water, GRASS_SOURCE, BoardBuilder.WATER_ATLAS)
	var standing_ok: bool = game.can_spawn_at(water)
	assert_bool(standing_ok).override_failure_message(
		"precondition: a unit may STAND on the water tile, so the body exception is never asked").is_false()
	var drowning := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.PLAYER, Vector2i(4, 1))   # the witness: a dropped body vs a board that never loaded
	drowning.movement.set_cell(water)   # under the way a shove puts it: onto the water, then down
	drowning.force_down()
	await _load_both(_save(sm.capture_scenario("two_hosts_body"), "body"))

	var g_units := _game_units()
	var g_body := _unit_at(g_units, water)
	assert_bool(g_body != null and g_body.is_downed() and g_units.size() == 2) \
		.override_failure_message("precondition: the game did not lay the body in the water beside its witness").is_true()
	_agree("the body in the water", _entry_picture(g_units), _entry_picture(_sess.live_units()))
