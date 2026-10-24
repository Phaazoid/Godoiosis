# The enemy field stays the board's (#1360). game.threat_field() is a CACHE, and every door that
# moves, adds or removes a unit, or rewrites the ground under one, has to leave it describing the
# board as it now stands -- before this, deploying, repositioning, a dev Move, a Unit Editor save and
# every brush stroke left the tones and reach lines on the old board.
#
# Each case drives the REAL door, then compares the cache with a field built fresh by the same
# builder (ThreatField.for_viewer), so no expectation is hand-derived from movement rules. A second
# assertion -- that the door changed the FRESH field at all -- is what keeps each case from going
# vacuous if the corridor below ever stops being a corridor.
#
# Needs the real game scene (fixture: tests/ui/test_game_scene_smoke.gd, tests/README.md -> Testing
# the game scene): the doors are game.gd's, MissionController's, DevController's and the editor's.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const SCRATCH := "user://__threat_freshness_1360.tres"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
# A one-cell-wide corridor with the enemy at its east end, so a body or a hole on the cell in front
# of it cuts every route west whatever its MOV.
const ROW := 16
const ENEMY_CELL := Vector2i(ROW - 1, 0)
const BLOCK_CELL := Vector2i(ROW - 2, 0)
const WEST_CELL := Vector2i(0, 0)

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"   # game.gd's dev-overlay lookup resolves against the production name
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.mission_controller._close_mission_select()
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(ROW):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	game.scenario_manager.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _spawn_enemy(archetype := AIArchetype.Type.RUSHDOWN) -> Unit:
	var enemy: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), ENEMY_CELL)
	assert_object(enemy).override_failure_message("precondition: the enemy would not spawn").is_not_null()
	enemy.equipped_weapon = H.make_weapon()
	enemy.squad.archetype = archetype
	return enemy


# The reach the V toggle draws: reach_cells_of with no subjects means every enemy (game.gd).
func _cells(field: ThreatField) -> Array[Vector2i]:
	var everyone: Array[Unit] = []
	var cells := field.reach_cells_of(everyone)
	cells.sort()
	return cells


# Read through the cache, so the case starts from a field that was really built and held.
func _cached() -> Array[Vector2i]:
	return _cells(game.threat_field())


func _assert_cache_follows(before: Array[Vector2i], door: String) -> void:
	var fresh := _cells(ThreatField.for_viewer(game.squad_manager, Team.Faction.PLAYER, true))
	assert_bool(fresh == before).override_failure_message(
			"fixture is vacuous: %s did not change what a fresh field reaches" % door).is_false()
	var cached := _cached()
	assert_bool(cached == fresh).override_failure_message(
			"after %s the cached field still describes the old board\n  cached %s\n  fresh  %s"
			% [door, cached, fresh]).is_true()


# ==============================================================================
#  Units -- the doors drop synchronously, like spawn_unit and a death
# ==============================================================================

func test_deploying_a_blocker_rebuilds_the_field() -> void:
	_spawn_enemy()
	var reserve: Unit = game.spawn_reserve_unit(H.make_unit_data({}, Team.Faction.PLAYER))
	var before := _cached()

	assert_bool(game.deploy_unit(reserve, BLOCK_CELL)).is_true()

	_assert_cache_follows(before, "deploy_unit")


func test_undeploying_a_blocker_rebuilds_the_field() -> void:
	_spawn_enemy()
	var reserve: Unit = game.spawn_reserve_unit(H.make_unit_data({}, Team.Faction.PLAYER))
	assert_bool(game.deploy_unit(reserve, BLOCK_CELL)).is_true()
	var before := _cached()

	game.undeploy_unit(reserve)

	_assert_cache_follows(before, "undeploy_unit")


func test_dev_move_rebuilds_the_field() -> void:
	_spawn_enemy()
	var blocker: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), WEST_CELL)
	var before := _cached()

	var dev: DevController = game.dev_controller
	dev.arm_move(blocker)
	dev.resolve_pending(BLOCK_CELL)

	assert_object(blocker.movement.cell).is_equal(BLOCK_CELL)
	_assert_cache_follows(before, "the dev Move")


func test_unit_editor_faction_save_rebuilds_the_field() -> void:
	var turncoat: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), BLOCK_CELL)
	# CARRIED, not just held: the editor's Save re-equips from the inventory and unarms the rest.
	var weapon := H.make_weapon()
	turncoat.add_item(weapon)
	turncoat.equipped_weapon = weapon
	var before := _cached()
	var editor: UnitEditorTool = game.dev_overlay.unit_editor
	editor.edit_unit(turncoat)
	editor._stage_faction("ENEMY")

	var save: Button = null
	for child in editor.unit_editor_container.find_children("*", "Button", true, false):
		if (child as Button).text.begins_with("Save"):
			save = child as Button
	assert_object(save).override_failure_message("no Save button in the editor").is_not_null()
	save.pressed.emit()

	assert_int(turncoat.get_faction()).is_equal(Team.Faction.ENEMY)
	_assert_cache_follows(before, "a Unit Editor faction save")


# Through the real phase: a roster draw stands a unit on the deployment zone, and the reposition
# verb moves it in front of the enemy. The roster is shipped content, so only its EXISTENCE is
# asked of it.
func test_reposition_rebuilds_the_field() -> void:
	var rosters: Array[String] = RosterCatalog.saved_rosters()
	if rosters.is_empty():
		push_warning("no rosters are shipped, so repositioning cannot be exercised")
		return
	for x in range(ROW - 1):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	var sm: ScenarioManager = game.scenario_manager
	sm.current_roster = rosters[0]
	sm.current_deployment_cap = 1
	assert_int(ResourceSaver.save(sm.capture_scenario("threat_freshness_1360", true), SCRATCH)).is_equal(OK)
	var mc: MissionController = game.mission_controller
	mc.begin_mission(SCRATCH)
	await await_idle_frame()
	assert_bool(mc.is_deploying()).override_failure_message(
			"precondition: the roster drew nobody, so the phase never opened").is_true()
	var drawn: Unit = null
	for unit: Unit in game.units_root.get_children():
		if unit.drawn_from_roster:
			drawn = unit
	_spawn_enemy()
	var to := BLOCK_CELL if drawn.movement.cell != BLOCK_CELL else WEST_CELL
	var before := _cached()

	assert_bool(mc.reposition(drawn, to)).is_true()

	_assert_cache_follows(before, "MissionController.reposition")


# ==============================================================================
#  The ground -- no drop at any writer; the field knows which store versions it was built on
# ==============================================================================

func test_a_terrain_write_rebuilds_the_field_by_the_next_frame() -> void:
	_spawn_enemy()
	var before := _cached()

	game.grid.erase(BLOCK_CELL)   # a hole in the corridor, through BoardGrid's one write door
	await await_idle_frame()

	_assert_cache_follows(before, "a terrain erase")


func test_undo_rebuilds_the_field_by_the_next_frame() -> void:
	_spawn_enemy()
	var dev: DevController = game.dev_controller
	dev._begin_stroke()
	game.grid.erase(BLOCK_CELL)
	dev._end_stroke()
	await await_idle_frame()
	var before := _cached()

	game.game_state = game.GameState.DEV_MODE   # the history only moves in dev mode (#1432)
	assert_bool(dev.undo_board()).override_failure_message("the stroke left nothing to undo").is_true()
	await await_idle_frame()

	_assert_cache_follows(before, "an undo")


# A Sentry strikes only from its zone, and ZoneManager has no version -- zones_changed is counted.
func test_a_zone_edit_rebuilds_the_field_by_the_next_frame() -> void:
	var sentry := _spawn_enemy(AIArchetype.Type.SENTRY)
	sentry.squad.zone_name = "post"
	game.zone_manager.paint_cell("post", ZoneManager.Kind.PATROL, ENEMY_CELL)
	await await_idle_frame()
	var before := _cached()

	game.zone_manager.paint_cell("post", ZoneManager.Kind.PATROL, BLOCK_CELL)
	await await_idle_frame()

	_assert_cache_follows(before, "a zone paint")
