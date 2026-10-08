# TWO HOSTS, ONE PHASE (#46). The pre-mission phase's rules live once, on PreMissionPhase, and two
# hosts drive it: the game (MissionController, game.gd's spawn/deploy/undeploy) and the headless Play
# API (PlaySession's twins of those calls). Placement is per host BY DESIGN (PreMission.gd), which
# makes this the law that keeps the declared copy honest: the same mission, opened by both, must
# agree on who stands where, who waits in reserve, and who leads whom -- after the draw, and again
# after the same placement decisions are made on each.
#
# What it cannot see, by construction: a fault in a SHARED rule (RulesService.can_spawn_at, the draw)
# moves both hosts together and they still agree. The flow suites that pin the phase itself cover
# that half.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const SCRATCH := "user://__pre_mission_two_hosts.tres"
const TEST_SAVE_DIR := "user://__test_saves_two_hosts/"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const ROW_WIDTH := 10
const ZONE_CELLS := 5
const CAP := 2

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController
var _sess


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
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


# The shipped roster offering the most characters, so the cap leaves someone in reserve. Loaded, never
# asserted about (the content razor).
static func _largest_roster() -> String:
	var best := ""
	var most := -1
	for name: String in RosterCatalog.saved_rosters():
		var roster: Roster = RosterCatalog.resolve(name)
		var count := 0 if roster == null else roster.offered_entries().size()
		if count > most:
			best = name
			most = count
	return best


# One mission, authored through the game's own capture, saved where BOTH hosts can load it.
func _author(offered := true) -> String:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
		game.grid.paint(Vector2i(x, 1), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	assert_object(game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(ROW_WIDTH - 1, 1))) \
		.override_failure_message("precondition: the authored enemy would not spawn").is_not_null()
	sm.current_roster = _largest_roster()
	sm.current_deployment_cap = CAP
	sm.current_offers_pre_mission = offered
	# Claimed before it is written (CLAUDE.md, the load() cache): a session left over from an earlier
	# case still holds the last board's ScenarioData, so an unclaimed save loads back stale.
	var scenario := sm.capture_scenario("two_hosts", true)
	scenario.take_over_path(SCRATCH)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


func _open_both(offered := true) -> void:
	var path := _author(offered)
	mc.begin_mission(path)
	await await_idle_frame()
	var board := BoardBuilder.build(self, "TwoHostsHeadless")
	auto_free(board.root)
	await BoardBuilder.load_scenario(board, path)
	_sess = PlaySession.new(board)
	_sess.start_pre_mission()
	await await_idle_frame()


# Per roster entry, in entry order: standing or not, where, which entry leads its squad, and what it
# carries (#46 slice 3 -- a restart replays gear as well as placement).
static func _picture(units: Array[Unit], deployed: Callable) -> Array:
	var rows: Array = []
	for unit: Unit in units:
		var carried: Array[String] = []
		for item: Item in unit.inventory:
			if item != null:
				carried.append(item.shown_name())
		if not deployed.call(unit):
			rows.append(["reserve", carried])
			continue
		var leader: Unit = unit.squad.get_leader() if unit.squad != null else null
		rows.append(["standing", unit.movement.cell, units.find(leader), carried])
	return rows


func _game_picture() -> Array:
	return _picture(mc.roster_units(), func(u: Unit) -> bool: return game.is_deployed(u))


func _play_picture() -> Array:
	return _picture(_sess.roster_units(), func(u: Unit) -> bool: return _sess.is_deployed(u))


func _agree(when: String) -> void:
	var g := _game_picture()
	var p := _play_picture()
	assert_int(p.size()).override_failure_message(
		"%s: the hosts drew rosters of different sizes" % when).is_equal(g.size())
	assert_str(str(p)).override_failure_message(
		"%s: the hosts disagree\n  game:     %s\n  headless: %s" % [when, str(g), str(p)]).is_equal(str(g))


# ==============================================================================

func test_the_draw_lands_the_same_on_both_hosts() -> void:
	await _open_both()
	assert_bool(mc.is_deploying()).override_failure_message("the game did not open the phase").is_true()
	assert_bool(_sess.is_deploying()).override_failure_message("the headless host did not open the phase").is_true()
	_agree("after the draw")


# A board whose Pre-mission screen box is unticked (#46): neither host opens the phase, and both stand
# the same authored draw. PreMissionPhase.opens is the one rule both ask.
func test_an_unticked_board_opens_no_phase_on_either_host() -> void:
	await _open_both(false)
	assert_bool(mc.is_deploying()).override_failure_message("the game opened the phase").is_false()
	assert_bool(_sess.is_deploying()).override_failure_message("the headless host opened the phase").is_false()
	_agree("an unticked board")


func test_the_same_decisions_leave_the_same_board() -> void:
	await _open_both()
	var g_units: Array[Unit] = mc.roster_units()
	var p_units: Array[Unit] = _sess.roster_units()
	if g_units.size() <= CAP:
		fail("fixture: the largest shipped roster is not larger than the cap (%d)" % CAP)
		return

	# 1. Take the first standing unit off.
	game.undeploy_unit(g_units[0])
	assert_bool((_sess.undeploy(_sess.handle_for(p_units[0])) as Dictionary).ok).is_true()
	_agree("after an undeploy")

	# 2. Stand the first waiting unit on the first open cell -- the same cell on both, or the hosts
	#    already disagree about where one may stand.
	var open_cells: Array[Vector2i] = mc.open_deployment_cells()
	assert_str(str(_sess.deployment_cells())).is_equal(str(open_cells))
	var waiting := CAP   # the draw stood entries 0..CAP-1, so this one waited
	assert_bool(game.deploy_unit(g_units[waiting], open_cells[0])).is_true()
	assert_bool((_sess.deploy(_sess.handle_for(p_units[waiting]), open_cells[0]) as Dictionary).ok).is_true()
	_agree("after a deploy")

	# 3. Swap two standing units.
	var target: Vector2i = g_units[waiting].movement.cell
	assert_bool(mc.reposition(g_units[1], target)).is_true()
	assert_bool((_sess.reposition(_sess.handle_for(p_units[1]), target) as Dictionary).ok).is_true()
	_agree("after a reposition")


# ==============================================================================
# A RESTART (#46 slice 3). The game restarts through MissionController.restart_mission; the headless
# host has no restart of its own below the bridge, so _restart_headless is the bridge's sequence --
# a fresh board, and the draw handed the buffer PreMissionPhase's two rules choose.

const PROBE := "Two Hosts Probe"


# The same decisions on both hosts -- one unit off, the first waiting one on, a test-authored piece out
# of the stash to it -- then the commit on each. Returns false (having failed) when the fixture cannot
# make them.
func _decide_and_commit() -> bool:
	var g_units: Array[Unit] = mc.roster_units()
	var p_units: Array[Unit] = _sess.roster_units()
	if g_units.size() <= CAP:
		fail("fixture: the largest shipped roster is not larger than the cap (%d)" % CAP)
		return false
	game.undeploy_unit(g_units[0])
	assert_bool((_sess.undeploy(_sess.handle_for(p_units[0])) as Dictionary).ok).is_true()
	var open_cells: Array[Vector2i] = mc.open_deployment_cells()
	assert_bool(game.deploy_unit(g_units[CAP], open_cells[0])).is_true()
	assert_bool((_sess.deploy(_sess.handle_for(p_units[CAP]), open_cells[0]) as Dictionary).ok).is_true()

	var g_piece := Item.new()
	g_piece.display_name = PROBE
	mc.loadout().stash.append(g_piece)
	assert_str(mc.loadout().move(g_piece, null, g_units[CAP])).is_empty()
	var p_piece := Item.new()
	p_piece.display_name = PROBE
	(_sess.stash() as Array).append(p_piece)
	var given: Dictionary = _sess.give("stash", (_sess.stash() as Array).find(p_piece), _sess.handle_for(p_units[CAP]))
	assert_bool(given.ok).override_failure_message(str(given.get("error", ""))).is_true()
	_agree("after the decisions")

	assert_bool(mc.commit_deployment()).is_true()
	assert_bool((_sess.begin() as Dictionary).ok).is_true()
	return true


func _restart_headless(buffer: PreMissionSnapshot, from_inside_phase: bool) -> PreMissionSnapshot:
	var kept := PreMissionPhase.kept_by_restart(buffer, from_inside_phase)
	var board := BoardBuilder.build(self, "TwoHostsRestart_%d" % Time.get_ticks_usec())
	auto_free(board.root)
	await BoardBuilder.load_scenario(board, SCRATCH)
	_sess = PlaySession.new(board)
	_sess.start_pre_mission(PreMissionPhase.replay_for(kept, SCRATCH, true))
	await await_idle_frame()
	return kept


static func _carries(unit: Unit, piece_name: String) -> bool:
	for item: Item in unit.inventory:
		if item != null and item.shown_name() == piece_name:
			return true
	return false


func test_a_restart_replays_the_same_loadout_on_both_hosts() -> void:
	await _open_both()
	if not _decide_and_commit():
		return
	var buffer: PreMissionSnapshot = _sess.staged

	mc.restart_mission()
	await await_idle_frame()
	await _restart_headless(buffer, false)
	assert_bool(mc.is_deploying()).override_failure_message("the game's restart did not reopen the phase").is_true()
	assert_bool(_sess.is_deploying()).override_failure_message("the headless restart did not reopen the phase").is_true()
	_agree("after a restart")
	# Not vacuous: the probe the decisions handed out came back, on the unit it went to.
	var g_units: Array[Unit] = mc.roster_units()
	assert_bool(_carries(g_units[CAP], PROBE)).override_failure_message(
		"the restart dropped the piece the loadout gave out").is_true()
	var taken_off_stands: bool = game.is_deployed(g_units[0])
	assert_bool(taken_off_stands).override_failure_message(
		"the restart stood the unit the player took off").is_false()


func test_a_restart_from_inside_the_phase_stands_the_authored_draw_on_both_hosts() -> void:
	await _open_both()
	var authored := _game_picture()
	if not _decide_and_commit():
		return
	var buffer: PreMissionSnapshot = _sess.staged
	mc.restart_mission()
	await await_idle_frame()
	buffer = await _restart_headless(buffer, false)

	# Now inside the replayed phase: Reset Loadout on both.
	mc.restart_mission()
	await await_idle_frame()
	await _restart_headless(buffer, true)
	_agree("after Reset Loadout")
	assert_str(str(_game_picture())).override_failure_message(
		"Reset Loadout did not stand the mission's own draw").is_equal(str(authored))
