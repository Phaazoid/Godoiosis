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
# Its board-side twin (#774): the corner affordance that is up exactly while the screen is not, so
# the phase never leaves the frame with nothing on it. Same lifecycle, same one owner.
var _premission_bar: PreMissionBar
# The phase's roster, live gear and rules (#46) -- built by deploy_roster with this game as its host,
# and dropped in reset() because it holds references into a board about to be freed. Never null: an
# empty phase is what a board with no roster has.
var _phase: PreMissionPhase = PreMissionPhase.new()
# WHAT THE PLAYER CHOSE last time they left this phase (#763), so a retry does not make them build
# a five-minute loadout again to move one unit two tiles. Taken at the commit; replayed by a
# restart of the SAME mission.
#
# IT IS THE ONE PHASE FIELD reset() MUST NOT CLEAR, and that is the whole trick -- the two above
# are dropped there because they hold references into a board about to be freed, while this holds
# only data. Its life has exactly two edges and neither is a teardown:
#
#   * OVERWRITTEN by the next commit, wherever that happens. A different mission's commit replaces
#     it, which is why no door has to remember to clear it: mission_path below stops a buffer being
#     read by a board it does not describe (dev, 2026-09-07: "for now, b is fine. Once we have
#     persistent profiles, it will live in the profile").
#   * DROPPED by a restart taken while the phase is still OPEN, which is the player's one way back
#     to the draw the author wrote (dev's ruling; the pause row renames itself there to say so).
#
# A demo boot (armed=false, #375) replays one like any other arrival. Harmless and deliberate: it
# never opens the phase, so what it inherits is a force somebody chose rather than the plain walk.
var _staged: PreMissionSnapshot = null
# The phase is open and its BRIEFING is still talking (#882), so the screen is built but withheld:
# a line telling you what the map wants has to arrive over the map, and before the loadout, or it
# is advice about a choice already made. Cleared in _close_deployment_menu rather than in reset(),
# which is the only door every exit takes -- abandon_mission never reaches reset() at all.
var _briefing := false
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
# Has a unit the mission was protecting died (#572)? A LATCH, not a board question, and it has to be:
# Unit.die() queue_frees the node, so by the time any check() runs the unit is simply gone -- which
# is indistinguishable from one that was never placed at all. Battle-scoped, cleared by reset().
#
# It never needs saving. The mission ends on the very next check() after the death, and check() runs
# at the end of the pass the death resolved in, so no save can be taken while this is true.
var _protected_lost := false
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
	# FIRST, and before anything below is cleared (#53): this is the universal teardown, so it is
	# the one place that catches every door out of a mission that does NOT go through a named exit
	# -- F2, a board swap, Load Game, Mission Select. reload_current has exactly two callers and
	# only restart_mission seals, so without this an F2 leaves the run OPEN and it goes on appending
	# events describing a board that no longer exists.
	#
	# It composes with the named seals rather than fighting them: seal() early-returns when closed,
	# so restart_mission's RESTARTED still wins and this call is then a no-op. And it must run BEFORE
	# _rounds_elapsed is zeroed -- clear_board frees the units AFTER this, so the sealed record still
	# reads the final board.
	game.mission_log.seal(MissionLog.Ending.INTERRUPTED)
	outcome = MissionRules.Outcome.ONGOING
	_contested = false
	_ending = false
	_captured_zones.clear()
	objectives.clear()
	lose_conditions.clear()
	round_limit = 0
	_rounds_elapsed = 0
	_failed_by = MissionRules.LoseCondition.NONE
	_protected_lost = false
	_battle_begun = false
	# Through the setter, so the HUD comes back up on every board teardown (#739). This is the edge
	# that covers F2, a board swap, Load Game and Abandon -- none of which pass through commit.
	_deploying = false
	_close_deployment_menu()
	# Dropped BEFORE clear_board frees these nodes, so nothing holds a reference into a dead board.
	_phase = PreMissionPhase.new()   # the phase's gear dies with the phase (#731 ruling 3)
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
	_open_mission_select(DevTools.enabled())


# The gate as a PARAMETER, so both builds are drivable in a suite (#860). DevTools.enabled() reads
# OS.has_feature, which a headless run cannot make false -- left inline, the shipped build's whole
# branch would be unreachable code no test could ever enter, on the one feature whose entire job is
# to behave differently there.
func _open_mission_select(dev: bool) -> void:
	if is_instance_valid(_select_screen):
		return
	game.game_state = game.GameState.MENU
	var missions: Array[String] = game.scenario_manager.get_missions()
	if not dev:
		missions = _missions_in_demo(missions)   # #860: a shipped build lists only what was ticked
	var others: Array[String] = []
	if dev:
		# Root playtest saves + fixtures/ -- selectable during development, and DEV SCAFFOLDING by
		# their own admission, so a shipped build must not list them (#860). Ungated until now.
		for path in game.scenario_manager.get_saved_scenarios():
			if not missions.has(path):
				others.append(path)
	_select_screen = MissionSelectScreen.open(game, missions, others, dev)
	_select_screen.mission_chosen.connect(begin_mission)
	_select_screen.load_game_chosen.connect(_on_load_game_chosen)
	_select_screen.sandbox_chosen.connect(_on_sandbox_chosen)
	_select_screen.glossary_chosen.connect(func(): GlossaryScreen.show_screen(game))
	_select_screen.settings_chosen.connect(func(): SettingsScreen.show_screen(game))
	_select_screen.credits_chosen.connect(func(): CreditsScreen.show_screen(game))
	# Defaults to FEEDBACK, not BUG: nobody reaches this screen mid-defect (#131 item 6).
	_select_screen.feedback_chosen.connect(func(): game.open_report_card(BugReporter.Kind.FEEDBACK))
	_select_screen.quit_chosen.connect(func(): game.get_tree().quit())
	# The update nag (#1060), on the same door and for the same reason. NOT awaited: its answer
	# comes off the network, and the title screen may not wait for it. Called BEFORE the notice so
	# that when both are due on one launch, the notice is the later sibling and sits on top.
	_nag_if_outdated()
	# What changed since this install last looked (#1075). A child of the title screen rather than
	# of card_layer, so it cannot follow a mission out. Before the notice, which needs an answer and
	# so belongs on top when both are due.
	WhatsNewCard.show_if_needed(_select_screen)
	# The first-launch notice (#53 slice 3), stacked over the screen we just built. Here rather
	# than in game._ready because this is the ONE door to the title screen, so the card is
	# guaranteed something to sit on; it costs nothing on the later returns through here, since
	# should_show() is false forever after the first dismissal.
	TelemetryNotice.show_if_needed(game)


# Asks once per launch and shows the banner only if the player is STILL on the title screen -- the
# answer arrives off the network, so a slow reply must not drop a modal over a battle that started
# while it was in flight.
func _nag_if_outdated() -> void:
	if not UpdateBanner.should_show():
		return
	var latest: Dictionary = await VersionCheck.latest(game)
	if latest.is_empty() or not is_instance_valid(_select_screen):
		return
	UpdateBanner.show_if_needed(game, str(latest["url"]))

# Which of those boards a build WITHOUT dev tools may list (#860).
#
# The filter lives HERE and never inside ScenarioManager.get_missions(), which must keep meaning
# EVERY mission on disk: tests/dev/test_board_lint.gd sweeps that list to lint every shipped
# mission, and filtering at the source would silently stop linting exactly the boards nobody
# ticked. A board kept out of the demo is still a board that must not be broken.
#
# A board that fails to load is EXCLUDED rather than raised: a dangling ext_resource is a hard
# parse error, and today that costs you one unplayable row -- through this reader it would take
# the whole title screen down with it. Loud in the log, absent from the list.
func _missions_in_demo(paths: Array[String]) -> Array[String]:
	var shipped: Array[String] = []
	for path in paths:
		var scenario := load(path) as ScenarioData
		if scenario == null:
			push_error("Mission select: '%s' failed to load; omitted from the mission list." % path)
			continue
		if scenario.in_demo:
			shipped.append(path)
	return shipped


func _close_mission_select() -> void:
	if is_instance_valid(_select_screen):
		_select_screen.queue_free()
	_select_screen = null

# Is the title screen the surface on screen? Esc's ONE exception (#723). Everywhere else it opens
# the pause menu; here it does nothing, because this screen already IS that menu -- Load, Glossary,
# Settings, Feedback and Quit are rows on it, so a pause card over it would be a second copy of a
# list the player is looking at.
#
# EXISTENCE, not visibility, unlike deployment_menu_is_up() next door: that screen is hidden and
# kept so the player can look at the board behind it, and this one is freed when it closes.
#
# A separate question from menu_is_up(), not a second answer to it: that one asks whether the board
# is the player's to click, which is true of this screen and three other situations besides.
func mission_select_is_up() -> bool:
	return is_instance_valid(_select_screen)

# The one path-taking mission entry, public since #220 — the Mission Select signal
# and the Battle3D driver both start missions through this door.
func begin_mission(path: String, armed := true) -> void:
	_close_mission_select()
	game.scenario_manager.load_scenario(path)   # routes through clear_board() -> reset()
	# Staged against the path we were HANDED, not last_loaded_path: same value here, but this one
	# cannot be read before the load has set it (#763 ruling 1 -- the buffer belongs to a mission,
	# not to the button that got us here, so coming back through Mission Select restores it too).
	var drawn := deploy_roster(PreMissionPhase.replay_for(_staged, path))   # BEFORE the arm, and it matters -- see the function
	# A PLAYER is what the phase is for (#739). armed=false is the watch-only boot (#375) -- nobody
	# there to answer it -- so the draw stands as the answer and the mission starts, which is #731
	# ruling 8's "both auto-deploy". (The headless Play API answers the phase itself since #46.) A board that drew NOBODY (no
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
	game.squad_tether_presenter.arm()   # #367: the placement ring's Squad Up plays; the draw did not
	game.clear_selection()   # -> _base_state(), which now answers PRE_MISSION
	_premission_screen = PreMissionScreen.open(game, self)
	_premission_bar = PreMissionBar.open(game, self)
	_premission_bar.set_shown(false)   # the screen is what the phase opens ON; the bar is its swap
	# ...unless the board has a BRIEFING (#882), in which case the phase opens on the BOARD and the
	# screen waits for the last line. It is HIDDEN rather than shown-on-quiet, because a Control is
	# visible the moment it is built -- the line above is the bar's own default being corrected, not
	# a pattern to copy. Both fresh-start doors come through here, so a restart replays the briefing
	# for free -- the same parity MISSION_START has always had.
	_briefing = game.scenario_director.pre_mission_started()
	if _briefing:
		_premission_screen.set_shown(false)


# The briefing has finished (#882). Wired to the director's went_quiet in game._build_collaborators,
# which fires on every timeline that empties the queue -- so the flag, not the signal, is what says
# this one was ours.
func _on_director_quiet() -> void:
	if not _briefing:
		return
	_briefing = false
	if is_instance_valid(_premission_screen):
		_premission_screen.set_shown(true)


# THE menu's whole lifecycle, in one place because every path that ends the phase has to take it
# (#740). Freeing rather than hiding: the screen holds references to Unit nodes the next
# load_scenario frees, which is the #107 stale-reference shape. #774's bar rides here rather than
# growing a second teardown -- reset, commit and abandon already all come through this one door.
func _close_deployment_menu() -> void:
	_briefing = false   # #882: every exit passes here, and reset() does not cover abandon_mission
	# So does an open ring (#1034): Enter's confirm card became clickable over the deploy wheel, and
	# "Begin" left it offering reserve units to a battle already running. reset() is every board
	# teardown too, and runs before clear_board frees a unit, so no ring outlives its board.
	game.main_action_menu.close_ring()
	if is_instance_valid(_premission_screen):
		_premission_screen.queue_free()
	_premission_screen = null
	if is_instance_valid(_premission_bar):
		_premission_bar.queue_free()
	_premission_bar = null


# Is the pre-mission menu on screen RIGHT NOW? game.menu_is_up() reads this, which is what puts the
# board behind it out of reach -- see that function for why a full-rect Control is not enough.
# Hidden (the board preview) reads FALSE on purpose: that is the whole point of the toggle.
func deployment_menu_is_up() -> bool:
	return is_instance_valid(_premission_screen) and _premission_screen.visible


# The board preview, and back (#731 ruling 6). The screen is HIDDEN rather than freed so the player's
# scroll position and any open row survive a look at the board. ONE act with two halves since #774:
# the screen and the bar are each other's complement, so a swap that moved only one of them would
# leave the phase showing two surfaces or none.
func toggle_deployment_menu() -> void:
	if _briefing:
		return   # #882: the screen is deliberately withheld while the briefing plays
	if not is_instance_valid(_premission_screen):
		return
	var shown := not _premission_screen.visible
	_premission_screen.set_shown(shown)
	if is_instance_valid(_premission_bar):
		_premission_bar.set_shown(not shown)


# The phase's one exit (#739). Refused with nothing on the board -- a mission cannot start with no
# force -- and that refusal has a VOICE, because a silent one reads as a dead key.
#
# It clears the flag BEFORE arming and beginning the turn: start_faction_turn rests the board on
# _base_state(), so turn 1 would otherwise rest inside the phase it just left.
func commit_deployment() -> bool:
	if not _deploying:
		return false
	var refusal := _phase.commit_block_reason()
	if refusal != "":
		game.turn_banner.show_label(refusal)
		return false
	# BEFORE anything tears the phase down (#763). This is the instant the player's choices are
	# final and the board has not begun to move, which is also what keeps the battle-scoped half of
	# a captured entry inert -- nothing is downed, in crisis or on watch until _begin_turn below.
	_staged = _phase.capture(game.scenario_manager.last_loaded_path)
	_deploying = false
	_close_deployment_menu()
	game.exit_current_mode()   # the phase's own ring/pick is over; rests on the new _base_state
	game.scenario_director.mission_started()   # a commit is a fresh start (#182), same as the door above
	_begin_turn()
	return true


# The same act with a question in front of it (dev, 2026-09-05: an accidental press must not start a
# battle prematurely). It lives on the CONTROLLER rather than on either button because the commit has
# THREE doors -- the bar, the screen, and the Enter key -- and a confirm bolted to one of them is a
# confirm the other two walk around.
#
# The refusal comes first and UNASKED, through commit_deployment itself: a card that asks about an act
# already destined to be refused is two dead ends where one would do, and routing it through the real
# exit is what stops the wording becoming a second copy.
func confirm_and_commit() -> void:
	if not _deploying:
		return
	# #882: Enter is BOTH this commit and Dialogic's advance (dialogic_default_action carries Enter,
	# Space and left click), so without this the keypress that closes Torv's last line would open
	# the Begin Mission card behind it. The player has not seen the loadout yet either way.
	if _briefing:
		return
	if deployed_roster_count() == 0:
		commit_deployment()   # refuses, and speaks
		return
	var sure: bool = await ConfirmCard.ask(game,
		"Begin the mission with the force you have placed? There is no coming back to the loadout "
		+ "once the battle starts.", "Begin Mission", "Not Yet")
	# No re-read of _deploying after the await, deliberately: the phase CAN end while the card is up
	# (a dev key is exempt from the modal freeze, so F2 reaches the board), and commit_deployment's
	# own first line already refuses outside the phase. A guard here would be a second copy of that
	# one, and an unfalsifiable one -- nothing could ever reach it that the act does not already stop.
	if sure:
		commit_deployment()


func is_deploying() -> bool:
	return _deploying


# --- The phase's rules and state live on PreMissionPhase (#46) ---
# Shared with the headless Play API, so they are answered there once. What stays here is the GAME's
# half: every door into and out of the phase, the screen and bar, the briefing, the HUD, and the
# restart buffer. These are the phase's answers, read through this node so no UI caller had to move.

func open_deployment_cells() -> Array[Vector2i]:
	return _phase.open_deployment_cells()

func reposition_cells(unit: Unit) -> Array[Vector2i]:
	return _phase.reposition_cells(unit)

# The board's own redraw rides the phase's reposition, which settles the squads (#772).
func reposition(unit: Unit, cell: Vector2i) -> bool:
	if not _deploying:
		return false
	if not _phase.reposition(unit, cell):
		return false
	game.overlay_manager.redraw_projected_units()
	return true

# Never null: an empty Loadout is what a board with no roster has.
func loadout() -> Loadout:
	return _phase.loadout

# The roster in ENTRY ORDER (#763). The card grid orders ITSELF (#1089) and reads this for
# membership and a tie-break only.
func roster_units() -> Array[Unit]:
	return _phase.units

func deployed_roster_count() -> int:
	return _phase.deployed_count()

func can_deploy_another() -> bool:
	return _phase.can_deploy_another()

# Why one more cannot be placed, or "" -- the card's refusal, answered by the phase.
func deploy_block_reason() -> String:
	return _phase.deploy_block_reason()

# The pre-mission phase's DRAW (#737), stood up by PreMissionPhase with this game as its host.
# Returns how many stood up; the rest wait in game.reserve_root until clear_board frees them.
#
# WHERE IT IS CALLED IS THE WHOLE DESIGN. It sits at the two FRESH-START doors, beside the arm
# decision the director already forks on (#182) -- never inside apply_scenario, which every board
# load crosses. A save slot records `roster` like any other field, so a deploy down there would fire
# on resume_from_slot ON TOP of the units the save just restored, and again on the dev-tools Load
# and on F2, neither of which is a mission starting.
#
# And BEFORE the arm, not after. spawn_unit creates a solo squad per unit, which emits
# squad_created, which an ARMED ScenarioDirector answers by firing SQUAD_FORMED beats -- so a
# three-unit draw would play its "now you move as one" payoff three times before the player had
# touched anything.
func deploy_roster(staged: PreMissionSnapshot = null) -> int:
	var scenario_manager: ScenarioManager = game.scenario_manager
	_phase = PreMissionPhase.new(game, game.zone_manager, game.squad_manager,
			func() -> int: return scenario_manager.current_deployment_cap)
	var deployed := _phase.draw(scenario_manager.current_roster, staged)
	if deployed > 0:
		# apply_scenario's own last two calls, repeated because the board has mutated AGAIN since it
		# made them -- #134's write-point trap: the HUD refreshed before these units existed.
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
func _begin_turn(record_to_disk := true) -> void:
	# The deployment window closes here (#736), and the zones that showed it stop being drawn. Set
	# BEFORE the redraw for the obvious reason, and the redraw is needed at all because every
	# arrival painted the zones on the way in (apply_scenario -> restore_progress) while this was
	# still false.
	_battle_begun = true
	# Defaulted, so all five arrival doors are unchanged. The replay driver is the one caller that
	# passes false: it takes this same door so the board is armed identically, and records in memory.
	game.mission_log.begin(record_to_disk)   # the run starts here, whichever door brought us (#53)
	# Membership changes play from here on (#367). This and _open_deployment are where every load
	# lands, so the load's own joins are the baseline rather than a moment.
	game.squad_tether_presenter.arm()
	game.overlay_manager.redraw_zones(game.zone_manager, hidden_zone_names())
	var faction: Team.Faction = game.turn_manager.active_faction()
	game.turn_banner.show_label("%s Turn" % Team.faction_name(faction))
	game.start_faction_turn(faction)

# The one answer to "start this mission over" -- the end-of-mission Retry and the pause menu's
# Restart both land here. False on a Sandbox board: there is no file to reload.
func can_restart() -> bool:
	return game.scenario_manager.last_loaded_path != ""

func restart_mission() -> void:
	# READ _deploying BEFORE THE RELOAD, and this is the whole of #763's second ruling. reload_current
	# routes through clear_board -> reset(), and reset() clears the flag -- so the same question asked
	# one line lower answers "no" every time, and a restart taken from inside the phase would replay
	# the buffer it exists to drop. A restart from a phase that has not started means the mission as
	# the author wrote it; the pause menu renames its own row there to say so. The rule itself is
	# PreMissionPhase's, shared with the headless Play API's restart (#46).
	_staged = PreMissionPhase.kept_by_restart(_staged, _deploying)
	var staged: PreMissionSnapshot = PreMissionPhase.replay_for(_staged, game.scenario_manager.last_loaded_path)
	game.mission_log.seal(MissionLog.Ending.RESTARTED)   # a retry is its own metric (#53)
	game.scenario_manager.reload_current()
	# ...and returns to the PHASE, so a retry is a chance to place differently (#739) -- with what
	# was placed LAST attempt already standing there (#763), rather than five minutes of loadout to
	# rebuild before one unit can move two tiles.
	var drawn := deploy_roster(staged)
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
	game.scenario_manager.apply_scenario(save.scenario, save.mission_path)
	_begin_turn()
	game.scenario_director.disarm()   # a resume is not a fresh start; dialog beats are fresh-start content (#182)

# Leaving a mission the player has not finished. Deliberately the SAME handoff _end_mission makes
# for its Mission Select choice, minus the outcome -- tidy the HUD, then hand to the menu. The
# abandoned board is left standing on purpose: MissionSelectScreen's background is opaque, and the
# next mission routes through load_scenario -> clear_board() like every other entry does.
func abandon_mission() -> void:
	game.mission_log.seal(MissionLog.Ending.ABANDONED)
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
	game.mission_log.record_capture(zone_name)
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
	for objective: MissionRules.Objective in MissionRules.OBJECTIVE_ZONE_KIND:
		if objectives.has(objective) and game.zone_manager.zone_names_of(MissionRules.OBJECTIVE_ZONE_KIND[objective]).is_empty():
			missing.append(objective)
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
# reach them with RescueAction, which revives to ACTIVE at whatever HP the body has.
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

# The cargo this mission is holding -- every painted Kind.DEFEND zone. ONE answer, and both readers
# are downstream of it: the lose condition asks whether a hostile is standing in any of them, and
# the HUD names them. There is no owner and no progress to hold, which is why this whole section is
# a pass-through to the zone store rather than a battle-scoped field like _captured_zones: a
# defended point is authored geometry that either still holds or has ended the mission.
# THE #572 WIRE. game._on_unit_died is the one place every death arrives -- take_damage's two
# branches, the downed countdown and the dev kill button all reach Unit.die(), which emits once and
# is idempotent -- so this is asked once per unit and never re-asked about a corpse.
func note_unit_died(unit: Unit) -> void:
	if unit != null and unit.must_survive:
		_protected_lost = true

# Who this mission is protecting, still standing -- the HUD's readout.
func protected_units(board: BoardContext) -> Array[Unit]:
	return MissionRules.protected_units(board)


func defend_zone_names() -> Array[String]:
	return game.zone_manager.zone_names_of(MissionRules.LOSE_ZONE_KIND[MissionRules.LoseCondition.POINT_LOST])

# Who is standing on the cargo right now, null while it holds. The HUD's readout and the predicate
# both come off MissionRules, so the row and the rule cannot disagree.
func breaching_unit(board: BoardContext) -> Unit:
	return MissionRules.breaching_unit(board, defend_zone_names(), game.zone_manager)


func set_lose_conditions(list: Array[MissionRules.LoseCondition], limit: int) -> void:
	lose_conditions.assign(list)
	round_limit = limit
	game.refresh_mission_status()

# The shout, MOVED OUT of set_lose_conditions above (#572) rather than duplicated. It used to fire
# there, which is mid-load -- before a single unit has spawned -- and a board-dependent condition
# judged then is judged against an empty board: a perfectly good PROTECTED_UNIT_LOST would have
# reported itself broken on every load, for ever. ScenarioManager.apply_scenario calls this at the
# point it already re-pushes the HUD, which is the one moment the board has finished mutating (the
# #134 write-point trap, and the same fix EXTRACT needed).
func report_missing_setup() -> void:
	for condition in lose_conditions_missing_setup():
		push_error("Lose condition %s is declared but has nothing to fire on — this mission would be lost immediately." % MissionRules.LoseCondition.keys()[condition])

# Declared lose conditions with no usable parameter -- objectives_missing_geometry's twin, and the
# same doctrine: the mission really is broken, so say so loudly rather than dropping the clause.
func lose_conditions_missing_setup() -> Array[MissionRules.LoseCondition]:
	var missing: Array[MissionRules.LoseCondition] = []
	if lose_conditions.has(MissionRules.LoseCondition.ROUND_LIMIT) and round_limit <= 0:
		missing.append(MissionRules.LoseCondition.ROUND_LIMIT)
	# #571's geometry half, and it is objectives_missing_geometry's rule rather than the clock's:
	# the cargo IS the painted zone, so a declared POINT_LOST with nothing painted has nothing to
	# lose and the mission is simply not the mission that was authored.
	if lose_conditions.has(MissionRules.LoseCondition.POINT_LOST) and defend_zone_names().is_empty():
		missing.append(MissionRules.LoseCondition.POINT_LOST)
	# #572's twin, with one extra clause that is not decoration: once the VIP has died there is
	# genuinely nobody flagged on the board, and without `not _protected_lost` the row would flip to
	# "not set" at the exact moment the condition FIRED -- reporting a broken board for the one
	# thing that worked.
	if lose_conditions.has(MissionRules.LoseCondition.PROTECTED_UNIT_LOST) and not _protected_lost \
			and protected_units(game._board()).is_empty():
		missing.append(MissionRules.LoseCondition.PROTECTED_UNIT_LOST)
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
		if _condition_fired(condition, board):
			return condition   # ANY, not all -- the first one that fires ends it
	return MissionRules.LoseCondition.NONE

func _condition_fired(condition: MissionRules.LoseCondition, board: BoardContext) -> bool:
	match condition:
		MissionRules.LoseCondition.ROUND_LIMIT:
			return MissionRules.round_limit_reached(_rounds_elapsed, round_limit)
		MissionRules.LoseCondition.POINT_LOST:
			return MissionRules.defend_zone_breached(board, defend_zone_names(), game.zone_manager)
		MissionRules.LoseCondition.PROTECTED_UNIT_LOST:
			return _protected_lost
		MissionRules.LoseCondition.NONE, MissionRules.LoseCondition.SQUAD_LOST:
			return false   # never authored; the wipe is answered above, not from the list
	push_error("MissionController: no rule for lose condition %s" % MissionRules.LoseCondition.keys()[condition])
	return false

func _end_mission() -> void:
	_ending = true
	# Sealed BEFORE the banner: a player who quits at it still has the record (#53).
	var ending: MissionLog.Ending = MissionLog.Ending.VICTORY if outcome == MissionRules.Outcome.VICTORY else MissionLog.Ending.DEFEAT
	game.mission_log.seal(ending, _failed_by)
	game.clear_selection()                            # rests game_state ...
	game.refresh_action_queue(null)
	game.unit_info_panel.clear()
	game.game_state = game.GameState.MISSION_OVER     # ... so lock the board AFTER it

	var victory: bool = outcome == MissionRules.Outcome.VICTORY
	var reason: String = MissionRules.defeat_reason(_failed_by)   # "" on a victory; the banner falls back
	# Grabbed BEFORE the banner draws, which carries a report form (#1052): a report filed from it
	# wants the board as the mission ended, not a picture of the form. _open_pause_menu's rule, and
	# its reason for locking first -- the extra frame is not interactive.
	var frame: Image = await game.bug_reporter.capture_frame()
	var choice: MissionEndBanner.Choice = await MissionEndBanner.show_banner(game, victory, can_restart(), reason, frame)

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
