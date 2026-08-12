extends Node
class_name MissionController

# Owns the mission's ENDING: when the predicate has fired, what the game does about it, and the
# latches that keep it from firing twice (#96 slice 1). Built in game._build_collaborators with a
# back-ref -- the DevController/OrderExecutor pattern.
#
# The rule itself is NOT here; it is MissionRules, pure and static. This node holds only the two
# facts a pure predicate structurally cannot: whether the mission has already ended, and whether
# both sides were ever up at once.
#
# check() is called from every point board state can change AND settle -- the end of a resolution
# pass, the end-of-turn burn, and turn start after the downed clocks tick. Pass-end rather than
# turn-end is deliberate: a friendly AoE can down your own last unit mid-pass, and the game should
# say so then instead of taking more orders for a squad that no longer exists.

var game   # the Game coordinator; set by game._ready()

var outcome: MissionRules.Outcome = MissionRules.Outcome.ONGOING
var _contested := false
var _ending := false   # _end_mission awaits the banner, so check() can re-enter behind it
var _select_screen: MissionSelectScreen
# Which CAPTURE zones have been claimed, by name. Battle-scoped, which is why it lives here and
# not on ScenarioData: the zones are authored content, taking them is this battle's progress.
var _captured_zones: Array[String] = []
# What THIS mission requires. Authored content that arrives with the scenario, so it is cleared by
# reset() and refilled on load -- one list for every objective kind, rather than a field per kind.
var objectives: Array[MissionRules.Objective] = []


func is_over() -> bool:
	return outcome != MissionRules.Outcome.ONGOING

func check() -> void:
	# The board has settled whether or not the mission ends -- the HUD reads the settled state (#134).
	game.refresh_mission_status()
	if is_over() or _ending:
		return
	var board: BoardContext = game._board()
	if not _contested:
		_contested = MissionRules.is_contested(board)
	var result: MissionRules.Outcome = MissionRules.evaluate(board, _contested, objective_progress(board))
	if result == MissionRules.Outcome.ONGOING:
		return
	outcome = result
	_end_mission()   # deliberately un-awaited: outcome is already set, so is_over() is true for
					 # every caller the moment we return, while the banner blocks only itself

# Mission START: the blank slate restore_progress() writes a mid-battle snapshot back over (#87).
func reset() -> void:
	outcome = MissionRules.Outcome.ONGOING
	_contested = false
	_ending = false
	_captured_zones.clear()
	objectives.clear()
	game.refresh_mission_status()

# --- Mid-battle snapshot (#87) ---

func captured_zone_names() -> Array[String]:
	return _captured_zones.duplicate()

func is_contested() -> bool:
	return _contested

# Runs after zones are refilled, since the redraw needs them painted.
func restore_progress(zones: Array[String], contested: bool) -> void:
	_captured_zones.assign(zones)
	_contested = contested
	game.overlay_manager.redraw_zones(game.zone_manager, _captured_zones)
	game.refresh_mission_status()

# ==============================================================================
#  Starting a mission (slice 2)
# ==============================================================================

# The front door: game._ready() opens it at boot, and every mission ending can return here.
func open_mission_select() -> void:
	if is_instance_valid(_select_screen):
		return
	game.game_state = game.GameState.MENU
	var missions: Array[String] = game.scenario_manager.get_missions()
	var others: Array[String] = []
	for path in game.scenario_manager.get_saved_scenarios():
		if not missions.has(path):
			others.append(path)   # root playtest saves + fixtures/ -- selectable during development
	_select_screen = MissionSelectScreen.open(game, missions, others)
	_select_screen.mission_chosen.connect(_on_mission_chosen)
	_select_screen.load_game_chosen.connect(_on_load_game_chosen)
	_select_screen.sandbox_chosen.connect(_on_sandbox_chosen)
	_select_screen.glossary_chosen.connect(func(): GlossaryScreen.show_screen(game))
	# Defaults to FEEDBACK, not BUG: nobody reaches this screen mid-defect (#131 item 6).
	_select_screen.feedback_chosen.connect(func(): game.open_report_card(BugReporter.Kind.FEEDBACK))
	_select_screen.quit_chosen.connect(func(): game.get_tree().quit())

func _close_mission_select() -> void:
	if is_instance_valid(_select_screen):
		_select_screen.queue_free()
	_select_screen = null

func _on_mission_chosen(path: String) -> void:
	_close_mission_select()
	game.scenario_manager.load_scenario(path)   # routes through clear_board() -> reset()
	_begin_turn()

func _on_sandbox_chosen() -> void:
	_close_mission_select()
	game.spawn_sandbox()                        # also routes through clear_board() -> reset()
	_begin_turn()

# The title door into a save slot (#144). The card locks over the select screen (the Glossary-
# over-title shape); no lost-progress confirm here -- nothing is in progress on the title.
func _on_load_game_chosen() -> void:
	var slot: int = await SaveLoadScreen.show_screen(game, SaveLoadScreen.Mode.LOAD)
	if slot < 0:
		return   # backed out; the select screen is still up
	_close_mission_select()
	resume_from_slot(slot)

# A board arriving from the menu has nobody's turn actually STARTED -- load_scenario only
# restores whose turn it was. Without this a mission saved on an AI faction's turn would sit
# there doing nothing, because turn_started only ever fires from TurnManager.end_turn.
func _begin_turn() -> void:
	var faction: Team.Faction = game.turn_manager.active_faction()
	game.turn_banner.show_label("%s Turn" % Team.faction_name(faction))
	game.start_faction_turn(faction)

# The one answer to "start this mission over" -- the end-of-mission Retry and the pause menu's
# Restart both land here. False on a Sandbox board: there is no file to reload.
func can_restart() -> bool:
	return game.scenario_manager.last_loaded_path != ""

func restart_mission() -> void:
	game.scenario_manager.reload_current()
	_begin_turn()

# Player-facing resume (#144): the same two-step arrival _on_mission_chosen makes, except the
# board comes from a save slot and last_loaded_path is aimed at the ORIGIN mission -- so Restart
# and F2 reload the mission start, and no dev tool can ever aim Update at a slot. _begin_turn no
# longer resets actions (a menu arrival trusts the file -- see game._on_turn_started), which is
# what keeps the restored has_acted alive.
func resume_from_slot(slot: int) -> void:
	var save: SaveGame = game.scenario_manager.load_slot(slot)
	if save == null:
		return
	game.scenario_manager.apply_scenario(save.scenario)
	game.scenario_manager.last_loaded_path = save.mission_path
	_begin_turn()

# Leaving a mission the player has not finished. Deliberately the SAME handoff _end_mission makes
# for its Mission Select choice, minus the outcome -- tidy the HUD, then hand to the menu. The
# abandoned board is left standing on purpose: MissionSelectScreen's background is opaque, and the
# next mission routes through load_scenario -> clear_board() like every other entry does.
func abandon_mission() -> void:
	# exit_current_mode, not clear_selection: only the former nulls the STORED game.selected_unit
	# (#107), and walking away from a board must not leave a reference into it -- the next
	# load_scenario frees those Unit nodes. clear_selection sets game_state = IDLE on the way ...
	game.exit_current_mode()
	game.refresh_action_queue(null)
	game.unit_info_panel.clear()
	open_mission_select()                  # ... and this sets MENU, so the order matters

# ==============================================================================
#  The capture objective (slice 3)
# ==============================================================================

# The uncaptured CAPTURE zone at this cell, "" when none. Kind-filtered because zones overlap
# (2026-08-12): "the" zone at a cell stopped being a well-formed question, and every reader of the
# old zone_at was asking exactly this one. A captured zone stops matching, so where two capture
# zones overlap the second becomes capturable once the first is claimed.
func capturable_zone_at(cell: Vector2i) -> String:
	for name in game.zone_manager.zone_names_of(ZoneManager.Kind.CAPTURE):
		if game.zone_manager.contains(name, cell) and not _captured_zones.has(name):
			return name
	return ""

# Standing anywhere in a capture zone claims the WHOLE zone -- a multi-tile objective is one
# objective, not N of them.
func capture(zone_name: String) -> void:
	if zone_name == "" or _captured_zones.has(zone_name):
		return
	if game.zone_manager.kind_of(zone_name) != ZoneManager.Kind.CAPTURE:
		return
	_captured_zones.append(zone_name)
	game.overlay_manager.redraw_zones(game.zone_manager, _captured_zones)
	game.refresh_mission_status()

func is_zone_captured(zone_name: String) -> bool:
	return _captured_zones.has(zone_name)


func set_objectives(list: Array[MissionRules.Objective]) -> void:
	objectives.assign(list)
	for objective in objectives_missing_geometry():
		push_error("Mission objective %s is declared but no matching zone is painted — this mission cannot be won." % MissionRules.Objective.keys()[objective])
	game.refresh_mission_status()

# Declared objectives whose geometry was never painted. ROUT needs none, so it can never appear
# here. The Scenario tab shows this live while authoring; set_objectives shouts it once on load.
func objectives_missing_geometry() -> Array[MissionRules.Objective]:
	var missing: Array[MissionRules.Objective] = []
	if objectives.has(MissionRules.Objective.CAPTURE) and game.zone_manager.zone_names_of(ZoneManager.Kind.CAPTURE).is_empty():
		missing.append(MissionRules.Objective.CAPTURE)
	if objectives.has(MissionRules.Objective.EXTRACT) and game.zone_manager.zone_names_of(ZoneManager.Kind.EXTRACTION).is_empty():
		missing.append(MissionRules.Objective.EXTRACT)
	return missing

# Every declared objective must be met -- they compose by AND. An empty list is NONE, which sends
# MissionRules.evaluate to its rout fallback.
func objective_progress(board: BoardContext) -> MissionRules.Progress:
	if objectives.is_empty():
		return MissionRules.Progress.NONE
	for objective in objectives:
		if progress_for(objective, board) != MissionRules.Progress.MET:
			return MissionRules.Progress.PENDING
	return MissionRules.Progress.MET

# Public since #134: the mission-status HUD reads each declared objective's own progress. The
# rules stay here -- the HUD never re-derives them.
func progress_for(objective: MissionRules.Objective, board: BoardContext) -> MissionRules.Progress:
	match objective:
		MissionRules.Objective.ROUT:
			return MissionRules.Progress.MET if not MissionRules.has_active_hostiles(board) else MissionRules.Progress.PENDING
		MissionRules.Objective.CAPTURE:
			return _capture_progress()
		MissionRules.Objective.EXTRACT:
			return _extract_progress(board)
	push_error("MissionController: no progress rule for objective %s" % MissionRules.Objective.keys()[objective])
	return MissionRules.Progress.PENDING

# (captured, total painted CAPTURE zones) -- the HUD's "1/2 zones". _capture_progress derives MET
# from these same numbers so the count and the boolean cannot drift (#134).
func capture_counts() -> Vector2i:
	var targets: Array[String] = game.zone_manager.zone_names_of(ZoneManager.Kind.CAPTURE)
	var done := 0
	for name in targets:
		if _captured_zones.has(name):
			done += 1
	return Vector2i(done, targets.size())

# Unpainted geometry reads as PENDING, not MET: the mission really is unwinnable, and silently
# dropping the objective would quietly turn a broken map into a different, playable one.
func _capture_progress() -> MissionRules.Progress:
	var counts := capture_counts()
	if counts.y == 0:
		return MissionRules.Progress.PENDING
	return MissionRules.Progress.MET if counts.x == counts.y else MissionRules.Progress.PENDING

# (surviving player units inside an extraction zone, surviving player units) -- "surviving" is
# not-DEAD, so the DOWNED count on both sides of the fraction, per the doctrine on
# _extract_progress below.
func extract_counts(board: BoardContext) -> Vector2i:
	var zones: Array[String] = game.zone_manager.zone_names_of(ZoneManager.Kind.EXTRACTION)
	var done := 0
	var total := 0
	for unit in board.units:
		if not is_instance_valid(unit) or unit.get_faction() != Team.Faction.PLAYER or unit.is_dead():
			continue
		total += 1
		if _in_any_zone(zones, unit.movement.cell):
			done += 1
	return Vector2i(done, total)

# "Surviving" is not-DEAD, so a DOWNED unit inside the zone counts as extracted exactly like an
# active one -- alive and in the zone means they get out. What blocks the objective is a living
# unit OUTSIDE the zone, and a downed one out there cannot walk in on its own: someone has to
# reach them with RescueAction, which revives to 1 HP and ACTIVE.
func _extract_progress(board: BoardContext) -> MissionRules.Progress:
	# The zones-empty guard runs BEFORE the counts: an unpainted extraction with no player units
	# would read 0 == 0 as MET, converting the broken map _capture_progress refuses to.
	if game.zone_manager.zone_names_of(ZoneManager.Kind.EXTRACTION).is_empty():
		return MissionRules.Progress.PENDING
	var counts := extract_counts(board)
	return MissionRules.Progress.MET if counts.x == counts.y else MissionRules.Progress.PENDING

# Several extraction zones on one map are alternatives, not a set to split across.
func _in_any_zone(zone_names: Array[String], cell: Vector2i) -> bool:
	for name in zone_names:
		if game.zone_manager.contains(name, cell):
			return true
	return false

func _end_mission() -> void:
	_ending = true
	game.clear_selection()                            # rests game_state ...
	game.refresh_action_queue(null)
	game.unit_info_panel.clear()
	game.game_state = game.GameState.MISSION_OVER     # ... so lock the board AFTER it

	var victory: bool = outcome == MissionRules.Outcome.VICTORY
	var choice: MissionEndBanner.Choice = await MissionEndBanner.show_banner(game, victory, can_restart())

	_ending = false
	game.game_state = game._base_state()   # unlock; dev mode survives a mission end (2026-08-11)
	match choice:
		MissionEndBanner.Choice.RETRY:
			restart_mission()
		MissionEndBanner.Choice.MISSION_SELECT:
			open_mission_select()
		_:
			pass   # STAY: board unlocks for inspection. The mission stays over -- check() is
				   # latched, and the turn cycle does not resume.
