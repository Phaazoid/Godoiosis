extends Node
class_name MissionController

# Owns the mission's ENDING: when the predicate has fired, what the game does about it, and the
# latches that keep it from firing twice (#96 slice 1). Built in game._build_collaborators with a
# back-ref -- the DevController/OrderExecutor pattern.
#
# The rule itself is NOT here; it is MissionRules, pure and static. This node holds what a pure
# predicate structurally cannot: whether the mission has already ended, whether both sides were
# ever up at once, this battle's progress (captured zones, the round clock), and -- since #101 --
# WHY it was lost, which the banner has to name.
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
# The pre-mission screen (#740), open for exactly as long as _deploying is. Held rather than looked
# up, the way _select_screen is, because game.menu_is_up() has to ask about it every frame.
var _premission_screen: PreMissionScreen
# The roster as ENTRY ORDER, which is the order #740's card grid draws in. Node order cannot answer
# it: deploy_unit and undeploy_unit REPARENT, so units_root and reserve_root both reshuffle every
# time the player changes their mind and the grid would reorder under them mid-decision.
var _roster_units: Array[Unit] = []
# Which CAPTURE zones have been claimed, by name. Battle-scoped, which is why it lives here and
# not on ScenarioData: the zones are authored content, taking them is this battle's progress.
var _captured_zones: Array[String] = []
# What THIS mission requires. Authored content that arrives with the scenario, so it is cleared by
# reset() and refilled on load -- one list for every objective kind, rather than a field per kind.
var objectives: Array[MissionRules.Objective] = []
# What LOSES it, and the clock's limit (#101). Authored, so both clear with the objectives above.
var lose_conditions: Array[MissionRules.LoseCondition] = []
var round_limit := 0
# Rounds the clock has counted. Battle-scoped like _captured_zones, for the same reason: the limit
# is authored content, how far through it this battle is is progress. Advanced from ONE place.
var _rounds_elapsed := 0
# Why the mission was lost, for the banner. Set beside `outcome`, so it can never name a reason for
# an ending that did not happen.
var _failed_by: MissionRules.LoseCondition = MissionRules.LoseCondition.NONE
# Has a turn actually STARTED on this board (#736)? Battle-scoped like the two above, and set from
# _begin_turn -- the one door every arrival takes (mission select, restart, resume, sandbox), and
# NOT from begin_mission, which #737's pre-mission phase will run inside. False therefore means
# "nobody is playing yet": an authoring session loaded through the dev tools, or that phase.
#
# Its one reader is hidden_zone_names below. It is deliberately not a "is the battle running" flag
# for general use -- it answers exactly one question, and a second caller wanting a different
# shade of it should ask its own.
var _battle_begun := false
# Is the pre-mission phase OPEN (#739) -- the board loaded and standing, the roster drawn, and
# nobody's turn started? This is the INTENT behind GameState.PRE_MISSION, and it has to be a flag of
# its own for the reason dev_mode_enabled is one: game._base_state() decides what the board RESTS
# at, and clear_selection WRITES game_state from it, so a state that read game_state would answer
# PICKING_TARGET in the middle of a squad pick and rest the board on IDLE.
#
# `_battle_begun` above is NOT this flag, and its own comment says so: a dev-tools load has that
# false too. This one means "a player is choosing right now".
#
# ITS FOUR EDGES, and they are the whole design:
#   * SET by _open_deployment, from begin_mission and restart_mission -- the two fresh-start doors.
#     That one entry also RESTS the board on the new _base_state; setting the flag alone leaves
#     game_state wherever the arrival left it, and every click would reach the battle ring.
#   * CLEARED in commit_deployment BEFORE _begin_turn, because start_faction_turn rests the board on
#     _base_state() and turn 1 would otherwise rest inside the phase.
#   * CLEARED in reset(), which clear_board calls BEFORE its own exit_current_mode -- and that
#     ordering is what makes F2, a board swap, Load Game and the next mission all leave the phase
#     correctly, for free. Do not reorder those two.
#   * The SCREEN (#740) opens and closes with it, and abandon_mission needs its own close: that
#     path never reaches clear_board, so nothing else would ever take the screen down.
#   * The HUD stand-down rides the SETTER, never commit. abandon_mission and resume_from_slot both
#     leave the phase without passing through commit, so a hide written at commit would strand the
#     next mission with no End Turn button (CameraController._set_playback_cinematic's shape).
var _deploying := false:
	set(value):
		if _deploying == value:
			return
		_deploying = value
		game.set_battle_hud_hidden(value)


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
	var failure: MissionRules.LoseCondition = failure_for(board)
	var result: MissionRules.Outcome = MissionRules.evaluate(board, _contested,
			objective_progress(board), failure)
	if result == MissionRules.Outcome.ONGOING:
		return
	outcome = result
	if result == MissionRules.Outcome.DEFEAT:
		_failed_by = failure   # set beside the outcome, so the banner cannot name a stale reason
	_end_mission()   # deliberately un-awaited: outcome is already set, so is_over() is true for
					 # every caller the moment we return, while the banner blocks only itself

# Mission START: the blank slate restore_progress() writes a mid-battle snapshot back over (#87).
func reset() -> void:
	outcome = MissionRules.Outcome.ONGOING
	_contested = false
	_ending = false
	_captured_zones.clear()
	objectives.clear()
	lose_conditions.clear()
	round_limit = 0
	_rounds_elapsed = 0
	_failed_by = MissionRules.LoseCondition.NONE
	_battle_begun = false
	# Through the setter, so the HUD comes back up on every board teardown (#739). This is the edge
	# that covers F2, a board swap, Load Game and Abandon -- none of which pass through commit.
	_deploying = false
	_close_deployment_menu()
	# Dropped BEFORE clear_board frees these nodes, so nothing holds a reference into a dead board.
	_roster_units.clear()
	game.refresh_mission_status()

# --- Mid-battle snapshot (#87) ---

func captured_zone_names() -> Array[String]:
	return _captured_zones.duplicate()


# THE answer to "which painted zones should not be drawn right now" -- redraw_zones' `hidden`
# argument, for every caller of it (#736). It used to be answered twice: this node passed
# _captured_zones while ScenarioManager and DevController passed nothing, so painting a zone
# mid-battle quietly re-lit a capture point that had already been claimed.
#
# A claimed CAPTURE zone is done with; a DEPLOYMENT zone is done with the moment a turn starts,
# because it says where you MAY PLACE units and placement is over. Both are "this zone has stopped
# being information", which is why they are one list and not two mechanisms.
func hidden_zone_names() -> Array[String]:
	var hidden: Array[String] = _captured_zones.duplicate()
	if _battle_begun:
		hidden.append_array(game.zone_manager.zone_names_of(ZoneManager.Kind.DEPLOYMENT))
	return hidden

func is_contested() -> bool:
	return _contested

func rounds_elapsed() -> int:
	return _rounds_elapsed

# Runs after zones are refilled, since the redraw needs them painted.
func restore_progress(zones: Array[String], contested: bool, rounds := 0) -> void:
	_captured_zones.assign(zones)
	_contested = contested
	_rounds_elapsed = rounds
	game.overlay_manager.redraw_zones(game.zone_manager, hidden_zone_names())
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
	_select_screen.mission_chosen.connect(begin_mission)
	_select_screen.load_game_chosen.connect(_on_load_game_chosen)
	_select_screen.sandbox_chosen.connect(_on_sandbox_chosen)
	_select_screen.glossary_chosen.connect(func(): GlossaryScreen.show_screen(game))
	_select_screen.settings_chosen.connect(func(): SettingsScreen.show_screen(game))
	# Defaults to FEEDBACK, not BUG: nobody reaches this screen mid-defect (#131 item 6).
	_select_screen.feedback_chosen.connect(func(): game.open_report_card(BugReporter.Kind.FEEDBACK))
	_select_screen.quit_chosen.connect(func(): game.get_tree().quit())

func _close_mission_select() -> void:
	if is_instance_valid(_select_screen):
		_select_screen.queue_free()
	_select_screen = null

# The one path-taking mission entry, public since #220 — the Mission Select signal
# and the Battle3D driver both start missions through this door.
func begin_mission(path: String, armed := true) -> void:
	_close_mission_select()
	game.scenario_manager.load_scenario(path)   # routes through clear_board() -> reset()
	var drawn := deploy_roster()   # BEFORE the arm, and it matters -- see the function
	# A PLAYER is what the phase is for (#739). armed=false is the watch-only boot (#375) and the
	# Play API's shape -- nobody there to answer it -- so the draw stands as the answer and the
	# mission starts, which is #731 ruling 8's "both auto-deploy". A board that drew NOBODY (no
	# roster, or a zone with no room, which Check board BLOCKS) also falls straight through: a phase
	# with nothing in it is one you could never commit.
	if armed and drawn > 0:
		_open_deployment()
		return
	# armed=false is the watch-only boot (#375: a lesson needs a student -- demo mode has no player
	# to advance dialog or follow instructions). Must be decided HERE, not disarmed after: the intro
	# starts DEFERRED (the layout-ready trap), so a late disarm cannot un-start it.
	if armed:
		game.scenario_director.mission_started()   # fresh start (the #220 door); ARMS before turn 1 fires
	else:
		game.scenario_director.disarm()
	_begin_turn()


# The phase's one ENTRY, from the two fresh-start doors above. Setting the flag is not enough by
# itself: game_state is written by whoever last rested the board, and the arrival that got us here
# rested it on IDLE -- clear_board's exit_current_mode, which runs after reset() and before the
# draw. clear_selection is that write point, and it is the same one _begin_turn reaches through
# start_faction_turn on the other branch, so the phase and a turn come to rest the same way.
func _open_deployment() -> void:
	_deploying = true
	game.clear_selection()   # -> _base_state(), which now answers PRE_MISSION
	_premission_screen = PreMissionScreen.open(game, self)


# THE screen's whole lifecycle, in one place because every path that ends the phase has to take it
# (#740). Freeing rather than hiding: the screen holds references to Unit nodes the next
# load_scenario frees, which is the #107 stale-reference shape.
func _close_deployment_menu() -> void:
	if is_instance_valid(_premission_screen):
		_premission_screen.queue_free()
	_premission_screen = null


# Is the pre-mission menu on screen RIGHT NOW? game.menu_is_up() reads this, which is what puts the
# board behind it out of reach -- see that function for why a full-rect Control is not enough.
# Hidden (the board preview) reads FALSE on purpose: that is the whole point of the toggle.
func deployment_menu_is_up() -> bool:
	return is_instance_valid(_premission_screen) and _premission_screen.visible


# The board preview, and back (#731 ruling 6). The screen is HIDDEN rather than freed so the
# player's scroll position and any open row survive a look at the board.
func toggle_deployment_menu() -> void:
	if not is_instance_valid(_premission_screen):
		return
	_premission_screen.set_shown(not _premission_screen.visible)


# The phase's one exit (#739). Refused with nothing on the board -- a mission cannot start with no
# force -- and that refusal has a VOICE, because a silent one reads as a dead key.
#
# It clears the flag BEFORE arming and beginning the turn: start_faction_turn rests the board on
# _base_state(), so turn 1 would otherwise rest inside the phase it just left.
func commit_deployment() -> bool:
	if not _deploying:
		return false
	if deployed_roster_count() == 0:
		game.turn_banner.show_label("Deploy someone first")
		return false
	_deploying = false
	_close_deployment_menu()
	game.exit_current_mode()   # the phase's own ring/pick is over; rests on the new _base_state
	game.scenario_director.mission_started()   # a commit is a fresh start (#182), same as the door above
	_begin_turn()
	return true


func is_deploying() -> bool:
	return _deploying


# The DEPLOYMENT cells a unit could actually be put on, right now. TWO callers and that is the point
# (#739): the draw asks it once at mission start, and every click on an empty cell asks it again --
# so "where may a unit stand" is one answer, not one the walk holds and one the click re-derives.
#
# Legality is asked HERE and passed onward, never inside PreMission's pure walk: game.can_spawn_at
# IS spawn_unit's own gate, so a cell this accepts is one that spawn cannot refuse, while the
# headless host's spawn answers differently. One question, asked by whoever can answer it.
func open_deployment_cells() -> Array[Vector2i]:
	var open_cells: Array[Vector2i] = []
	for cell: Vector2i in game.zone_manager.cells_of_kind(ZoneManager.Kind.DEPLOYMENT):
		if game.can_spawn_at(cell):
			open_cells.append(cell)
	return open_cells

# Where this unit could stand instead (#772). The deployment zone's cells, minus its own, keeping
# both a FREE cell and one another ROSTER-DRAWN unit holds -- swapping is allowed (dev, 2026-09-05),
# so an occupied cell is a legal target rather than a refusal.
#
# Authored units are not swappable, for the reason Undeploy is gated the same way: they are the
# BOARD's, additive to the roster's draw (#731 ruling 2c), and trading places with one would move a
# unit the player was never given.
#
# can_spawn_at is asked for the FREE case rather than restated, so a cell this offers is one the
# draw would also have accepted -- terrain, the map's edge and occupancy, one answer.
func reposition_cells(unit: Unit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if unit == null or not unit.drawn_from_roster:
		return cells
	for cell: Vector2i in game.zone_manager.cells_of_kind(ZoneManager.Kind.DEPLOYMENT):
		if cell == unit.movement.cell:
			continue
		if game.can_spawn_at(cell):
			cells.append(cell)
			continue
		var occupant: Unit = game.get_unit_at_cell(cell)
		if occupant != null and occupant.drawn_from_roster:
			cells.append(cell)   # a swap
	return cells


# Move a placed unit inside the zone, trading places with whoever is there.
#
# set_cell rather than deploy_unit: the unit is already ON the board with a squad, so this is a
# position change, not a board entry -- the same door DevController's armed move uses.
#
# THEN THE SQUAD SETTLES, IMMEDIATELY (dev, 2026-09-05: it "ejects them there and then in the battle
# preview"). Placing a member out of its leader's cohesion range is legal, and enforce_contact is
# what answers for it -- the same sweep that runs at the end of a resolution pass and at turn start,
# so THE PRE-MISSION PHASE IS A THIRD SETTLE POINT. Calling it here rather than leaving turn 1 to
# find it is what makes the consequence land while the player is still looking at the board that
# caused it, instead of a turn later with nothing on screen to connect it to.
func reposition(unit: Unit, cell: Vector2i) -> bool:
	if not _deploying or unit == null or not unit.drawn_from_roster:
		return false
	if not reposition_cells(unit).has(cell):
		return false
	var from := unit.movement.cell
	var occupant: Unit = game.get_unit_at_cell(cell)
	unit.movement.set_cell(cell)
	if occupant != null:
		occupant.movement.set_cell(from)   # the swap: both ends move, then the squads settle ONCE
	game.squad_manager.enforce_contact()
	game.overlay_manager.redraw_projected_units()
	return true


# The roster in ENTRY ORDER -- what #740's card grid iterates. Node order cannot serve: deploying
# and undeploying REPARENT between units_root and reserve_root, so both lists reshuffle every time
# the player changes their mind, and a grid drawn off them would reorder mid-decision.
func roster_units() -> Array[Unit]:
	return _roster_units

# How many of the ROSTER are standing on the board -- what the cap counts, and what #743's strip
# will read as the left half of "4 / 6". Authored units on the same board are not the roster's and
# never count against its cap (ruling 2c: authored units are additive).
func deployed_roster_count() -> int:
	var count := 0
	for unit: Unit in game.units_root.get_children():
		if unit.drawn_from_roster:
			count += 1
	return count


# Room under the cap for one more? `0` is the cap's own "as many as fit" sentinel (#736), and the
# ZONE is the other limit -- but that one enforces itself, since a cell with nothing free is a cell
# open_deployment_cells never offers.
func can_deploy_another() -> bool:
	var cap: int = game.scenario_manager.current_deployment_cap
	return cap == PreMission.NO_CAP or deployed_roster_count() < cap

# The pre-mission phase's DRAW (#737). A board that names a Roster (#735) spawns ALL of it (#738)
# and stands as many as its cap allows on its DEPLOYMENT zone (#736). Returns how many stood up;
# the rest wait in game.reserve_root until clear_board frees them.
#
# THE PLAYER NOW LINGERS HERE (#739, replacing #737's "not yet"): the draw is the OPENING position
# rather than the answer, and begin_mission holds the board in the phase instead of playing on. So
# the three things #737 left unbuilt -- a commit that can be refused, a ring that can undeploy, a
# save refusal -- are built, now that there is something for each of them to serve rather than a
# mechanism whose only job was to survive until this ticket.
#
# The RESTART BUFFER is the one piece still out, filed as its own ticket rather than parked here
# (#763): the walk below is deterministic over the same roster, cap and zone, so a retry re-draws
# the same characters onto the same cells and only HAND placements are re-made.
#
# WHERE IT IS CALLED IS THE WHOLE DESIGN. It sits at the two FRESH-START doors, beside the arm
# decision the director already forks on (#182) -- never inside apply_scenario, which every board
# load crosses. A save slot records `roster` like any other field, so a deploy down there would fire
# on resume_from_slot ON TOP of the units the save just restored, and again on the dev-tools Load
# and on F2, neither of which is a mission starting.
#
# And BEFORE the arm, not after. spawn_unit creates a solo squad per unit, which emits
# squad_created, which an ARMED ScenarioDirector answers by firing SQUAD_FORMED beats and advancing
# the lesson -- so a three-unit draw would play its "now you move as one" payoff three times before
# the player had touched anything. The director's own header says it: a loading board must never
# trip a lesson or a beat.
#
# A restart re-runs it. That is why there is no buffer to preserve: the walk is deterministic over
# the same roster, cap and zone, so the same characters land on the same cells.
func deploy_roster() -> int:
	var scenario_manager: ScenarioManager = game.scenario_manager
	# "" resolves to null, which is every board saved before #735 and every board that simply has no
	# pre-mission phase. A NAMED roster that will not resolve push_errors and is a BLOCKS finding on
	# Check board -- substituting a different pool would hand the player a different mission.
	var roster: Roster = RosterCatalog.resolve(scenario_manager.current_roster)
	if roster == null:
		return 0

	var open_cells: Array[Vector2i] = open_deployment_cells()

	# The WHOLE roster spawns, deployed or not (#738), into game.reserve_root -- so a card on #740's
	# screen is a real Unit and every wielder-taking predicate serves it unchanged. It is also what
	# makes this the ONE way a roster unit reaches the board: the draw below deploys out of the same
	# set the screen will later let the player choose from, rather than a second spawn path #740
	# would have had to replace.
	var unit_of_entry: Dictionary = {}   # ScenarioUnitEntry -> its reserve Unit
	_roster_units.clear()
	for entry: ScenarioUnitEntry in roster.entries:
		# The same skip PreMission.deployment_plan makes, so the two loops agree about who exists.
		if entry == null or entry.unit_data == null:
			continue
		# Un-duplicated, exactly as apply_scenario passes it (#177): UnitFactory copies anyway, and
		# an outer duplicate destroys the resource_path a reference entry exists to keep.
		var unit: Unit = game.spawn_reserve_unit(entry.unit_data)
		# Marked here rather than at deploy, so deploy_unit stays a pure board-entry that knows
		# nothing about rosters -- and so an undeployed unit carries the mark too, for whenever
		# something starts asking.
		unit.drawn_from_roster = true
		if entry.state_saved:
			entry.apply_unit_state(unit)   # the snapshot half of #177's fork, same as the loader's
		unit_of_entry[entry] = unit
		_roster_units.append(unit)   # entry order, and it must survive every later reparent

	var deployed := 0
	for row: Dictionary in PreMission.deployment_plan(roster.entries, open_cells,
			scenario_manager.current_deployment_cap):
		var entry: ScenarioUnitEntry = row[PreMission.ENTRY]
		var unit: Unit = unit_of_entry.get(entry)
		if unit == null:
			continue
		if not game.deploy_unit(unit, row[PreMission.CELL]):
			continue   # the cells were filtered, so this is a bug rather than a blocked cell
		# One unit per entry: a file hand-edited to list the same sub-resource twice would otherwise
		# try to deploy it a second time. It spends a slot and says nothing, which is the right
		# volume for authoring nonsense RosterLint has not been taught to name.
		unit_of_entry.erase(entry)
		deployed += 1

	if deployed > 0:
		# apply_scenario's own last two calls, repeated because the board has mutated AGAIN since it
		# made them. This is #134's write-point trap exactly, and that function's comment names it:
		# the mission HUD refreshed before these units existed, so an EXTRACT objective would read
		# its progress off the authored cast alone and sit stale until the first turn event.
		game.refresh_end_turn_button()
		game.refresh_mission_status()
	return deployed


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
	# The deployment window closes here (#736), and the zones that showed it stop being drawn. Set
	# BEFORE the redraw for the obvious reason, and the redraw is needed at all because every
	# arrival painted the zones on the way in (apply_scenario -> restore_progress) while this was
	# still false.
	_battle_begun = true
	game.overlay_manager.redraw_zones(game.zone_manager, hidden_zone_names())
	var faction: Team.Faction = game.turn_manager.active_faction()
	game.turn_banner.show_label("%s Turn" % Team.faction_name(faction))
	game.start_faction_turn(faction)

# The one answer to "start this mission over" -- the end-of-mission Retry and the pause menu's
# Restart both land here. False on a Sandbox board: there is no file to reload.
func can_restart() -> bool:
	return game.scenario_manager.last_loaded_path != ""

func restart_mission() -> void:
	game.scenario_manager.reload_current()
	var drawn := deploy_roster()   # a restart re-runs the same deterministic draw; see deploy_roster
	# ...and returns to the PHASE, so a retry is a chance to place differently (#739). What it does
	# not do yet is preserve what the player placed LAST attempt -- the draw is deterministic, so
	# the force is the same, but hand placements are re-made. Filed as its own ticket rather than
	# parked here (dev, 2026-09-05).
	if drawn > 0:
		_open_deployment()
		return
	game.scenario_director.mission_started()   # a restart is a fresh start (#182); arms before turn 1
	_begin_turn()

# Player-facing resume (#144): the same two-step arrival begin_mission makes, except the
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
	game.scenario_director.disarm()   # a resume is not a fresh start; dialog beats are fresh-start content (#182)

# Leaving a mission the player has not finished. Deliberately the SAME handoff _end_mission makes
# for its Mission Select choice, minus the outcome -- tidy the HUD, then hand to the menu. The
# abandoned board is left standing on purpose: MissionSelectScreen's background is opaque, and the
# next mission routes through load_scenario -> clear_board() like every other entry does.
func abandon_mission() -> void:
	# Abandon never reaches clear_board -- the board is deliberately left standing behind Mission
	# Select's opaque backdrop -- so the phase's own screen has to be closed here or it outlives the
	# mission it belongs to, holding units the NEXT load frees (#740, Fable).
	_close_deployment_menu()
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
	game.overlay_manager.redraw_zones(game.zone_manager, hidden_zone_names())
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
	# Zero surviving players is _capture_progress's counts.y == 0 twin (missing until 2026-08-12):
	# 0 == 0 read as MET, which ticked Extract on the HUD during load, before units had spawned.
	# For evaluate() the guard never decides anything -- DEFEAT is checked first.
	if counts.y == 0:
		return MissionRules.Progress.PENDING
	return MissionRules.Progress.MET if counts.x == counts.y else MissionRules.Progress.PENDING

# Several extraction zones on one map are alternatives, not a set to split across.
func _in_any_zone(zone_names: Array[String], cell: Vector2i) -> bool:
	for name in zone_names:
		if game.zone_manager.contains(name, cell):
			return true
	return false

# ==============================================================================
#  Lose conditions (#101)
# ==============================================================================

func set_lose_conditions(list: Array[MissionRules.LoseCondition], limit: int) -> void:
	lose_conditions.assign(list)
	round_limit = limit
	for condition in lose_conditions_missing_setup():
		push_error("Lose condition %s is declared but has nothing to fire on — this mission would be lost immediately." % MissionRules.LoseCondition.keys()[condition])
	game.refresh_mission_status()

# Declared lose conditions with no usable parameter -- objectives_missing_geometry's twin, and the
# same doctrine: the mission really is broken, so say so loudly rather than dropping the clause.
func lose_conditions_missing_setup() -> Array[MissionRules.LoseCondition]:
	var missing: Array[MissionRules.LoseCondition] = []
	if lose_conditions.has(MissionRules.LoseCondition.ROUND_LIMIT) and round_limit <= 0:
		missing.append(MissionRules.LoseCondition.ROUND_LIMIT)
	return missing

# The ONE increment point, called from game._on_round_completed. TurnManager emits round_completed
# before turn_started, so the very next check() -- turn start, after the downed clocks tick -- is
# the one that sees it. No new evaluation seam.
func advance_round() -> void:
	_rounds_elapsed += 1
	game.refresh_mission_status()

# Rounds left on the clock, for the HUD. 0 when no clock is authored.
func rounds_remaining() -> int:
	return MissionRules.rounds_remaining(_rounds_elapsed, round_limit)

# WHY this mission is lost, NONE while it is not. The reason only; whether the mission ends is
# MissionRules.evaluate's answer, which is handed this and keeps its own wipe branch for the
# callers that pass nothing (the headless Play API). Both read the one faction predicate below.
#
# The wipe outranks an authored condition, matching evaluate's own order: a squad lost on the round
# the clock expires reports the squad, which is the more concrete thing that happened.
func failure_for(board: BoardContext) -> MissionRules.LoseCondition:
	if not board.faction_has_active_units(Team.Faction.PLAYER):
		return MissionRules.LoseCondition.SQUAD_LOST
	for condition in lose_conditions:
		if _condition_fired(condition):
			return condition   # ANY, not all -- the first one that fires ends it
	return MissionRules.LoseCondition.NONE

func _condition_fired(condition: MissionRules.LoseCondition) -> bool:
	match condition:
		MissionRules.LoseCondition.ROUND_LIMIT:
			return MissionRules.round_limit_reached(_rounds_elapsed, round_limit)
		MissionRules.LoseCondition.NONE, MissionRules.LoseCondition.SQUAD_LOST:
			return false   # never authored; the wipe is answered above, not from the list
	push_error("MissionController: no rule for lose condition %s" % MissionRules.LoseCondition.keys()[condition])
	return false

func _end_mission() -> void:
	_ending = true
	game.clear_selection()                            # rests game_state ...
	game.refresh_action_queue(null)
	game.unit_info_panel.clear()
	game.game_state = game.GameState.MISSION_OVER     # ... so lock the board AFTER it

	var victory: bool = outcome == MissionRules.Outcome.VICTORY
	var reason: String = MissionRules.defeat_reason(_failed_by)   # "" on a victory; the banner falls back
	var choice: MissionEndBanner.Choice = await MissionEndBanner.show_banner(game, victory, can_restart(), reason)

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
