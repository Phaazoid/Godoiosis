extends Node
class_name ScenarioManager

# Owns scenario save/load and the board-reset flow (dev_reset_scenario): serializes every
# live unit into a ScenarioUnitEntry/ScenarioData, and rebuilds the board from a saved one.
# Since #87 a save is a true mid-battle snapshot, battle-scoped layer included. Player save
# slots (#144) live here too: same capture/apply pair, wrapped in a SaveGame under user://.
# board_loaded (#222) fires once per board build, after the last settle step.

# Every board swap crosses apply_scenario (begin_mission, Load Game, F2/Restart, the dev
# Scenario tab) EXCEPT game.spawn_sandbox, which emits this itself after TestBoard.spawn.
# turn_started deliberately never fires on menu arrivals (#144), so the load funnel speaks
# for itself — the 3D mirror rebuilds on it.
signal board_loaded

const SCENARIO_DIR := "res://Scenarios/"

# Missions are ordinary saved scenarios living in a subfolder -- the convention fixtures/ set.
# Saving under this path needs no new code: save_scenario already makes the directory, so a
# scenario named "missions/Camp" lands here.
const MISSION_DIR := SCENARIO_DIR + "missions/"

static func scenario_path(scenario_name: String) -> String:
	return SCENARIO_DIR + scenario_name + ".tres"

# Player save slots (#144). user://, never Scenarios/ -- res:// is read-only once exported, and
# anything under Scenarios/ is picked up by Mission Select's scan and #9's integrity suite.
const SLOT_COUNT := 3
const DEFAULT_SAVE_DIR := "user://saves/"
# Injectable for TESTS ONLY -- suites redirect it so falsification runs never touch real slots.
static var save_dir := DEFAULT_SAVE_DIR

static func slot_path(slot: int) -> String:
	return save_dir + "slot_%d.tres" % slot

static func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))

# Statics so UI can gate rows (the pause menu's Load, the title's Load Game) without a manager ref.
static func any_save_exists() -> bool:
	for slot in range(1, SLOT_COUNT + 1):
		if slot_exists(slot):
			return true
	return false

# The inverse: a saved path's dropdown-relative name ("missions/Prolog"). One spelling for the
# trim -- the Scenario tab's list, its Loaded label, and its auto-aim all read this.
static func display_name(path: String) -> String:
	return path.trim_prefix(SCENARIO_DIR).trim_suffix(".tres")

@onready var game = get_parent()
@onready var grid: TileMapLayer = $"../Grid"
@onready var units_root: Node2D = $"../Units"
@onready var reserve_root: Node2D = $"../Reserve"   # #738; freed by clear_board beside the board's own
@onready var squad_manager: SquadManager = $"../SquadManager"
@onready var overlay_manager: OverlayManager = $"../OverlayManager"
@onready var turn_manager: TurnManager = $"../TurnManager"

var last_loaded_path := ""

# The look the CURRENT board wears (#253 part 2), by preset name; "" = the default. One store,
# one writer per path: apply_scenario sets it from the loaded board, clear_board zeroes it, and
# the dev Scenario tab writes it when you pick one. capture_scenario reads it back out.
var current_look_preset := ""

# Where the CURRENT board opens the camera (#234); null = derive from the player's units. Same
# store/writer shape as the look right above -- apply_scenario sets it, clear_board zeroes it, the
# dev Scenario tab captures into it, capture_scenario reads it back out.
var current_camera_start: CameraPose = null

# Which roster the CURRENT board offers (#735), by name; "" = no pre-mission phase. Same store and
# same four writers as the look right above -- apply_scenario sets it from the loaded board,
# clear_board zeroes it, the dev Scenario tab writes it when you pick one, capture_scenario reads
# it back out. MissionController.deploy_roster resolves it at the mission-start doors (#737).
var current_roster := ""

# How many of that roster the CURRENT board lets the player deploy (#736); 0 = as many as the
# deployment zone holds. Same store and same four writers as the roster right above, and it lives
# HERE rather than beside MissionController.round_limit because it is the roster's other half --
# one question ("what force may be fielded on this board"), one home. MissionController owns the
# mission's ENDING, which a deployment cap has nothing to do with.
var current_deployment_cap := 0

# The #182 lesson content, same seam: authored scenario content that is not board state. THE store
# — ScenarioDirector reads these LIVE (never copies), capture_scenario writes them back out, and
# clear_board empties them so a sandbox spawn cannot inherit the last mission's lesson.
var current_dialog_beats: Array[DialogBeat] = []
var current_tutorial_steps: Array[TutorialStep] = []

# Entries whose unit_data failed to resolve (resource deleted/moved since saving) come back
# null. Drop them with a push_error instead of letting load_scenario null-deref (#13). Pure +
# static so it's unit-testable without the game scene.
static func valid_entries(scenario: ScenarioData) -> Array[ScenarioUnitEntry]:
	var result: Array[ScenarioUnitEntry] = []
	for entry in scenario.unit_entries:
		if entry.unit_data == null:
			push_error("Scenario: skipping a unit whose unit_data could not be resolved.")
			continue
		result.append(entry)
	return result

# The write itself is DevWidgets.save_over -- dir creation, the take_over_path cache claim, and
# the error path (mirrored into status_label when given, #168) all live there, not here.
func save_scenario(scenario_name: String, status_label: Label = null, authored := false):
	if scenario_name.strip_edges() == "":
		push_warning("Scenario needs a name")
		return

	var scenario := capture_scenario(scenario_name, authored)
	var path := scenario_path(scenario_name)
	if DevWidgets.save_over(scenario, path, status_label):
		last_loaded_path = path

# A player save (#144): a FULL snapshot -- authored stays false, the #177 reference mode captures
# no state -- wrapped with its origin mission so Restart-after-resume returns to the mission start.
# Refuses on a board with no loaded mission (Save is only offered there, but the handler is the
# real gate -- the disabled row is only its surface).
func save_to_slot(slot: int) -> bool:
	if last_loaded_path == "":
		push_warning("No mission loaded -- nothing to save")
		return false
	var save := SaveGame.new()
	save.scenario = capture_scenario(display_name(last_loaded_path), false)
	save.mission_path = last_loaded_path
	save.saved_at = int(Time.get_unix_time_from_system())
	save.version = Build.version()
	return DevWidgets.save_over(save, slot_path(slot))

# null on empty or unreadable -- callers grey the row rather than crash (#166 shape).
func load_slot(slot: int) -> SaveGame:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return null
	var save := load(path) as SaveGame
	if save == null or save.scenario == null:
		push_error("Save slot %d is unreadable at %s" % [slot, path])
		return null
	return save

# --- the BOARD half, on its own (#391) ---
#
# Terrain, height, tile states and zones: what the Tile Brush writes, and what an authoring undo
# puts back. The whole-battle pair below is built on top of these, so there is ONE answer to "put a
# board back" rather than one for loading and a second for undoing.
func capture_board() -> BoardSnapshot:
	var snapshot := BoardSnapshot.new()
	snapshot.tile_data = grid.tile_map_data
	snapshot.terrain_states = game.terrain_states.to_state_dict()
	snapshot.corner_heights = game.board_heights.to_corner_dict()
	snapshot.zones = game.zone_manager.to_dict()
	return snapshot

# Two things a load does are deliberately NOT here, so that routing apply_scenario through this
# could not move the load path:
#   - CameraController.refresh_bounds, which a scenario load has never done. The dev brush does, at
#     its own three sites, and undo joins them there.
#   - the CAPTURED-zone redraw. MissionController.restore_progress runs one immediately after a
#     load and is the last writer either way; the plain redraw here is what an undo needs, since
#     nothing else follows it.
func restore_board(snapshot: BoardSnapshot) -> void:
	grid.restore(snapshot.tile_data)
	game.terrain_states.load_state_dict(snapshot.terrain_states)
	game.board_heights.load_corner_dict(snapshot.corner_heights)
	# Authored state must be VISIBLE at turn one -- nothing else redraws until the first round tick (#174).
	overlay_manager.redraw_terrain_live(game.terrain_states)
	game.zone_manager.load_dict(snapshot.zones)
	overlay_manager.redraw_zones(game.zone_manager, game.mission_controller.hidden_zone_names())

# The snapshot itself, split from writing it (#87) -- apply_scenario is its inverse.
# authored (#177): cast units — those spawned from a standalone character file — save as a
# REFERENCE to that file with no state captured, so every load re-reads the character as it is
# then. Default false keeps every other caller (BugReporter's #87 mid-battle snapshot above all)
# a byte-exact capture. Ad-hoc units snapshot fully in both modes; nothing else holds them.
func capture_scenario(scenario_name: String, authored := false) -> ScenarioData:
	var scenario := ScenarioData.new()
	scenario.scenario_name = scenario_name
	capture_board().write_into(scenario)
	scenario.active_faction = turn_manager.active_faction()
	scenario.objectives = game.mission_controller.objectives.duplicate()
	scenario.lose_conditions = game.mission_controller.lose_conditions.duplicate()   # #101: what loses it
	scenario.round_limit = game.mission_controller.round_limit
	scenario.ai_factions = game.ai_controller.ai_factions()   # #150: who the computer plays here
	scenario.look_preset = current_look_preset               # #253 part 2: the look it wears
	scenario.roster = current_roster                         # #735: who it offers, if anyone
	scenario.deployment_cap = current_deployment_cap         # #736: and how many of them
	scenario.camera_start = current_camera_start             # #234: where it opens, if authored
	scenario.dialog_beats = current_dialog_beats.duplicate()       # #182/#397: Update must not wipe
	scenario.tutorial_steps = current_tutorial_steps.duplicate()   # the lesson it cannot see on the board
	scenario.captured_zones = game.mission_controller.captured_zone_names()
	scenario.contested = game.mission_controller.is_contested()
	scenario.rounds_elapsed = game.mission_controller.rounds_elapsed()

	var entry_of: Dictionary = {}   # Unit -> its ScenarioUnitEntry, for the guard re-link below
	for unit: Unit in units_root.get_children():
		if unit.is_queued_for_deletion():
			continue
		# #737: an AUTHORED save records what this BOARD authors, and a roster draw is authored by
		# the roster. Recording them would make the next boot draw a second force on top of the one
		# it just wrote in -- and Update is reachable straight after a mission-select boot, so the
		# trip is play, F1, tweak something, Update. A full capture (a save slot, a bug report) keeps
		# them: it is restoring a battle, not re-authoring a board. Residual, worth knowing: a squad
		# the player later builds ACROSS the two kinds loses its drawn members from an authored save.
		if authored and unit.drawn_from_roster:
			continue

		var entry := ScenarioUnitEntry.new()
		if authored and unit.unit_data_source != null and not unit.dev_edited:
			# Reference, not copy: serializes as an ExtResource to the character file, and
			# state_saved=false tells the loader the spawn's own initialize+kit is the whole answer.
			# A DEV-EDITED unit falls through to the snapshot branch (dev-ratified, #259 rework):
			# the edit made it board-local, and a re-reference would silently discard it.
			entry.unit_data = unit.unit_data_source
			entry.state_saved = false
		else:
			entry.unit_data = unit.unit_data.duplicate(true)
		entry.cell = unit.movement.cell
		entry.squad_id = squad_manager.squads.find(unit.squad)
		entry.is_leader = unit.is_leader()
		if entry.is_leader:
			entry.squad_name = unit.squad.squad_name
			entry.squad_archetype = unit.squad.archetype
			entry.squad_zone = unit.squad.zone_name
			entry.squad_has_acted = unit.squad.has_acted   # #87: a spent squad reloads spent

		if entry.state_saved:
			entry.capture_unit_state(unit)

		entry_of[unit] = entry
		scenario.unit_entries.append(entry)

	# An armed Guard (#414) is a pair, so it can only be written once every entry exists -- the same
	# after-the-loop shape the squad rebuild uses on load. Stored as an INDEX into unit_entries, the
	# limb-prosthetic re-link pattern: a Unit reference cannot serialize, and a name is not unique.
	# A reference entry (#177) captured no battle state and gets none here either.
	for unit: Unit in entry_of:
		var entry: ScenarioUnitEntry = entry_of[unit]
		if not entry.state_saved or unit.guard == null or not unit.guard.is_intact():
			continue
		if not entry_of.has(unit.guard.ward):
			continue   # ward is leaving the board this frame -- the Guard goes with it
		entry.guard_ward_index = scenario.unit_entries.find(entry_of[unit.guard.ward])
		entry.guard_spent = unit.guard.spent

	return scenario

func load_scenario(path: String):
	var scenario: ScenarioData = ContentRepair.load_tolerant(path)
	if scenario == null:
		push_error("Could not load scenario at %s" % path)
		return

	apply_scenario(scenario)
	last_loaded_path = path

# Rebuild the board from a snapshot; path bookkeeping stays in load_scenario.
func apply_scenario(scenario: ScenarioData) -> void:
	clear_board()

	restore_board(BoardSnapshot.from_scenario(scenario))
	game.mission_controller.set_objectives(scenario.objectives)
	game.mission_controller.set_lose_conditions(scenario.lose_conditions, scenario.round_limit)   # #101
	game.mission_controller.restore_progress(scenario.captured_zones, scenario.contested,
			scenario.rounds_elapsed)
	# Before any turn starts: MissionController._begin_turn runs after load_scenario returns, and
	# start_faction_turn is what reads these. The set is REPLACED, not merged (#150).
	game.ai_controller.set_ai_factions(scenario.ai_factions)
	# #182 lesson content: REPLACED, not merged (#150's shape). The director reads these stores
	# live; clear_board (first line of this function) already reset its execution state.
	current_dialog_beats = scenario.dialog_beats
	current_tutorial_steps = scenario.tutorial_steps
	# Set BEFORE board_loaded fires (it is this function's last line), because battle3d reads this
	# from that signal. The 3D view is the only reader; a flat Main.tscn launch has no host and
	# correctly applies nothing.
	current_look_preset = scenario.look_preset
	current_camera_start = scenario.camera_start   # #234, same signal, same reason: read from board_loaded
	current_roster = scenario.roster              # #735; the mission-start doors draw from it (#737)
	current_deployment_cap = scenario.deployment_cap   # #736: its other half, and BoardLint reads it today

	var leaders_by_squad_id := {}
	var members_by_squad_id := {}
	var acted_squad_ids: Array[int] = []
	var unit_of_entry: Dictionary = {}   # ScenarioUnitEntry -> the Unit it spawned, for the #414 re-link

	for entry in valid_entries(scenario):
		# Handed WITHOUT the old outer duplicate (#177): UnitFactory copies anyway, and the copy
		# here was destroying resource_path — the provenance a reference entry exists to keep.
		# The saved lifecycle is passed, not looked up (#116): a DOWNED entry may lie on ground
		# nothing may STAND on -- deep water -- and without this the load would silently drop it.
		# A reference entry (state_saved false) is authored cast, never mid-drown, so ACTIVE is right.
		var unit: Unit = game.spawn_unit(entry.unit_data, entry.cell,
			entry.state_saved and entry.lifecycle_state == Unit.LifecycleState.DOWNED)
		if unit == null:
			push_warning("Could not spawn unit at %s (blocked or off-map)" % entry.cell)
			continue

		if entry.state_saved:
			entry.apply_unit_state(unit)

		unit_of_entry[entry] = unit

		if entry.squad_id == -1:
			continue

		if entry.is_leader:
			leaders_by_squad_id[entry.squad_id] = unit
			unit.squad.squad_name = entry.squad_name
			unit.squad.archetype = entry.squad_archetype
			unit.squad.zone_name = entry.squad_zone
			unit.squad.home_cell = entry.cell
			if entry.squad_has_acted:
				acted_squad_ids.append(entry.squad_id)   # applied AFTER the rebuild below
		else:
			if not members_by_squad_id.has(entry.squad_id):
				members_by_squad_id[entry.squad_id] = []
			members_by_squad_id[entry.squad_id].append(unit)

	for squad_id in members_by_squad_id.keys():
		var leader: Unit = leaders_by_squad_id.get(squad_id)
		if leader == null:
			continue #group saved without a leader; leave them as solos

		for member in members_by_squad_id[squad_id]:
			squad_manager.join_squad(member, leader.squad)

	# has_acted after the rebuild: join_squad is ungated, but assemble-then-mark-spent stays correct
	# if the loader is ever routed through the player-facing gate (_formation_basics_ok).
	for squad_id: int in acted_squad_ids:
		var acted_leader: Unit = leaders_by_squad_id.get(squad_id)
		if acted_leader != null:
			squad_manager.set_has_acted(acted_leader.squad, true)

	# Armed Guards (#414), after every spawn: a pair cannot be re-linked until both ends exist. A ward
	# whose entry never spawned (blocked cell, off-map) simply loses the Guard rather than failing the
	# load, matching how a squad saved without a leader degrades to solos above.
	for entry in unit_of_entry:
		if entry.guard_ward_index < 0 or entry.guard_ward_index >= scenario.unit_entries.size():
			continue
		var ward_entry: ScenarioUnitEntry = scenario.unit_entries[entry.guard_ward_index]
		if not unit_of_entry.has(ward_entry):
			continue
		var guarding_unit: Unit = unit_of_entry[entry]
		guarding_unit.arm_guard(unit_of_entry[ward_entry], guarding_unit.get_guard_range(), entry.guard_spent)
	game.refresh_guard_markers()
	game.refresh_watch_markers()   # a loaded watch is telegraphed the moment the board is up (#413)

	turn_manager.set_active_faction(scenario.active_faction)
	game.refresh_end_turn_button()   # a resumed save can load straight into an already-spent faction (#189)
	# The board has finished mutating -- re-push the mission HUD (#134's write-point set was missing
	# this one). set_objectives refreshed it mid-load, BEFORE units spawned, so extraction read its
	# progress off an empty board and the stale answer sat until the first turn event.
	game.refresh_mission_status()
	board_loaded.emit()

func reload_current():
	if last_loaded_path == "":
		return
	load_scenario(last_loaded_path)

func get_saved_scenarios() -> Array[String]:
	var paths: Array[String] = []
	_collect_scenarios(SCENARIO_DIR.trim_suffix("/"), paths)
	return paths

# The player-facing subset: everything the Mission Select screen offers. Dev scratch saves in the
# root (and fixtures/) are deliberately excluded -- that separation IS the mission/sandbox split.
func get_missions() -> Array[String]:
	var result: Array[String] = []
	for path in get_saved_scenarios():
		if path.begins_with(MISSION_DIR):
			result.append(path)
	return result

# Subfolders first, so fixtures/ groups above the root playtest saves.
func _collect_scenarios(dir: String, paths: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_collect_scenarios(dir.path_join(sub), paths)
	for file in ResourceDir.files_with_extension(dir, ".tres"):
		paths.append(dir.path_join(file))

func clear_board():
	# Director BEFORE controller: mc.reset() is a refresh_mission_status write point, and that
	# refresh reads active_instruction() -- reset the director first or the instruction row
	# re-renders stale on the dying board (#182).
	game.scenario_director.reset()
	game.mission_controller.reset()   # mission START resets battle-scoped state (#96/#87 seam)
	# A cleared board has NO loaded scenario. Update's load-gate reads this; a stale path would let
	# a sandbox board overwrite the last-loaded mission (the Prolog accident, 2026-08-11). Safe for
	# load paths: load_scenario re-sets it AFTER apply_scenario's internal clear_board.
	last_loaded_path = ""
	# Same reasoning for the look (#253 part 2): spawn_sandbox() lands here with no ScenarioData,
	# so without this it would keep wearing the last mission's preset. Empty = the default.
	current_look_preset = ""
	# And the camera start (#234): a sandbox spawn must not open on the last mission's authored shot.
	current_camera_start = null
	# And the roster (#735), for exactly the look preset's reason and with a sharper consequence:
	# Sandbox lands here with no ScenarioData, so without this a sandbox board would keep offering
	# the last mission's pool -- and the next Save As would write that name into a fixture.
	current_roster = ""
	# And the cap with it (#736) -- a sandbox board offers nobody, so it can hardly cap them at six,
	# and the same Save As would write the stale number into a fixture beside the stale name.
	current_deployment_cap = 0
	# And the lesson (#182/#397): content follows its board out.
	current_dialog_beats = []
	current_tutorial_steps = []
	# Same seam for AI control (#150): spawn_sandbox() lands here with no ScenarioData, so without
	# this it would inherit the last mission's flags. A typed local, not a bare [] -- `game` is
	# untyped, and a literal passed through it is not coerced to the typed parameter.
	var no_ai_factions: Array[Team.Faction] = []
	game.ai_controller.set_ai_factions(no_ai_factions)
	# And the AI's claim on the camera (#484). A new board owns no AI turn, same reasoning as the line
	# above -- but load-bearing rather than tidy since that flag became the board lock's authority: a
	# reload mid-enemy-phase rests game_state on _base_state() through exit_current_mode below, so an
	# playback_locked left standing by an interrupted turn would lock the fresh board for good.
	game.camera_controller.set_playback_locked(false)
	# ...and the TEAR-OUT the same pass may have left in the sky (#521, wired to the camera in #520
	# diff 2b). Same shape as the line above and the same trigger: only execute_orders clears the
	# staging, so a board swapped mid-pass (F2, Mission Select) hands the fresh board a lifted set of
	# cells nothing will ever put down -- and since the rig now RIDES that lift, the camera goes with
	# it. `BoardSpace` is a static, so it outlives the board exactly the way that flag does.
	BoardSpace.clear_staging()
	game.zone_manager.load_dict({})   # zones are board content; load_scenario refills them after
	overlay_manager.redraw_zones(game.zone_manager, game.mission_controller.hidden_zone_names())
	game.terrain_states.clear()   # tile states are board content too -- a sandbox spawn inherits no fire (#174)
	overlay_manager.redraw_terrain_live(game.terrain_states)
	game.board_heights.clear()   # so is elevation (#257) -- a sandbox spawn starts flat, not on the
								 # last mission's cliff. apply_scenario refills it straight after.
	if game.dev_overlay != null:
		game.dev_overlay.unit_editor.edit_unit(null)
	game.unit_info_panel.clear()
	squad_manager.clear_all_squads()
	# Not clear_selection: only this nulls selected_unit, which the frees below would strand (#149).
	game.exit_current_mode()
	game.refresh_action_queue(null)
	game.refresh_end_turn_button()   # a cleared board must not leave a stale flashing button up (#189)
	overlay_manager.clear_all_planned_paths()
	overlay_manager.clear_all_projected_sprites()

	for unit in units_root.get_children():
		#remove_child immediately so same-frame respawns don't see dying units in occupancy checks
		units_root.remove_child(unit)
		unit.queue_free()

	# The roster's UNDEPLOYED half goes out with the board (#738), and this line is half of why the
	# reserve is allowed to exist at all: a holding parent outside the teardown would leave those
	# units standing after a board swap, pointing into a board that has been freed -- #107's shape,
	# one node over. They need no occupancy dance; nothing looks them up by cell.
	for unit in reserve_root.get_children():
		reserve_root.remove_child(unit)
		unit.queue_free()
