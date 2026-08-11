extends Node
class_name ScenarioManager

# Owns scenario save/load and the board-reset flow (dev_reset_scenario): serializes every
# live unit into a ScenarioUnitEntry/ScenarioData, and rebuilds the board from a saved one.
# Since #87 a save is a true mid-battle snapshot, battle-scoped layer included.

const SCENARIO_DIR := "res://Scenarios/"

# Missions are ordinary saved scenarios living in a subfolder -- the convention fixtures/ set.
# Saving under this path needs no new code: save_scenario already makes the directory, so a
# scenario named "missions/Camp" lands here.
const MISSION_DIR := SCENARIO_DIR + "missions/"

static func scenario_path(scenario_name: String) -> String:
	return SCENARIO_DIR + scenario_name + ".tres"

# The inverse: a saved path's dropdown-relative name ("missions/Prolog"). One spelling for the
# trim -- the Scenario tab's list, its Loaded label, and its auto-aim all read this.
static func display_name(path: String) -> String:
	return path.trim_prefix(SCENARIO_DIR).trim_suffix(".tres")

@onready var game = get_parent()
@onready var grid: TileMapLayer = $"../Grid"
@onready var units_root: Node2D = $"../Units"
@onready var squad_manager: SquadManager = $"../SquadManager"
@onready var overlay_manager: OverlayManager = $"../OverlayManager"
@onready var turn_manager: TurnManager = $"../TurnManager"

var last_loaded_path := ""

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

# The snapshot itself, split from writing it (#87) -- apply_scenario is its inverse.
# authored (#177): cast units — those spawned from a standalone character file — save as a
# REFERENCE to that file with no state captured, so every load re-reads the character as it is
# then. Default false keeps every other caller (BugReporter's #87 mid-battle snapshot above all)
# a byte-exact capture. Ad-hoc units snapshot fully in both modes; nothing else holds them.
func capture_scenario(scenario_name: String, authored := false) -> ScenarioData:
	var scenario := ScenarioData.new()
	scenario.scenario_name = scenario_name
	scenario.tile_data = grid.tile_map_data
	scenario.active_faction = turn_manager.active_faction()
	scenario.terrain_states = game.terrain_states.to_state_dict()
	scenario.zones = game.zone_manager.to_dict()
	scenario.objectives = game.mission_controller.objectives.duplicate()
	scenario.ai_factions = game.ai_controller.ai_factions()   # #150: who the computer plays here
	scenario.captured_zones = game.mission_controller.captured_zone_names()
	scenario.contested = game.mission_controller.is_contested()

	for unit: Unit in units_root.get_children():
		if unit.is_queued_for_deletion():
			continue

		var entry := ScenarioUnitEntry.new()
		if authored and unit.unit_data_source != null:
			# Reference, not copy: serializes as an ExtResource to the character file, and
			# state_saved=false tells the loader the spawn's own initialize+kit is the whole answer.
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

		scenario.unit_entries.append(entry)

	return scenario

func load_scenario(path: String):
	var scenario: ScenarioData = load(path)
	if scenario == null:
		push_error("Could not load scenario at %s" % path)
		return

	apply_scenario(scenario)
	last_loaded_path = path

# Rebuild the board from a snapshot; path bookkeeping stays in load_scenario.
func apply_scenario(scenario: ScenarioData) -> void:
	clear_board()

	grid.tile_map_data = scenario.tile_data
	game.terrain_states.load_state_dict(scenario.terrain_states)
	# Authored state must be VISIBLE at turn one -- nothing else redraws until the first round tick (#174).
	overlay_manager.redraw_terrain_live(game.terrain_states)
	game.zone_manager.load_dict(scenario.zones)
	game.mission_controller.set_objectives(scenario.objectives)
	game.mission_controller.restore_progress(scenario.captured_zones, scenario.contested)
	# Before any turn starts: MissionController._begin_turn runs after load_scenario returns, and
	# start_faction_turn is what reads these. The set is REPLACED, not merged (#150).
	game.ai_controller.set_ai_factions(scenario.ai_factions)

	var leaders_by_squad_id := {}
	var members_by_squad_id := {}
	var acted_squad_ids: Array[int] = []

	for entry in valid_entries(scenario):
		# Handed WITHOUT the old outer duplicate (#177): UnitFactory copies anyway, and the copy
		# here was destroying resource_path — the provenance a reference entry exists to keep.
		var unit: Unit = game.spawn_unit(entry.unit_data, entry.cell)
		if unit == null:
			push_warning("Could not spawn unit at %s (blocked or off-map)" % entry.cell)
			continue

		if entry.state_saved:
			entry.apply_unit_state(unit)

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

	turn_manager.set_active_faction(scenario.active_faction)

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
	game.mission_controller.reset()   # mission START resets battle-scoped state (#96/#87 seam)
	# A cleared board has NO loaded scenario. Update's load-gate reads this; a stale path would let
	# a sandbox board overwrite the last-loaded mission (the Prolog accident, 2026-08-11). Safe for
	# load paths: load_scenario re-sets it AFTER apply_scenario's internal clear_board.
	last_loaded_path = ""
	# Same seam for AI control (#150): spawn_sandbox() lands here with no ScenarioData, so without
	# this it would inherit the last mission's flags. A typed local, not a bare [] -- `game` is
	# untyped, and a literal passed through it is not coerced to the typed parameter.
	var no_ai_factions: Array[Team.Faction] = []
	game.ai_controller.set_ai_factions(no_ai_factions)
	game.zone_manager.load_dict({})   # zones are board content; load_scenario refills them after
	overlay_manager.redraw_zones(game.zone_manager)
	game.terrain_states.clear()   # tile states are board content too -- a sandbox spawn inherits no fire (#174)
	overlay_manager.redraw_terrain_live(game.terrain_states)
	if game.dev_overlay != null:
		game.dev_overlay.unit_editor.edit_unit(null)
	game.unit_info_panel.clear()
	squad_manager.clear_all_squads()
	# Not clear_selection: only this nulls selected_unit, which the frees below would strand (#149).
	game.exit_current_mode()
	game.refresh_action_queue(null)
	overlay_manager.clear_all_planned_paths()
	overlay_manager.clear_all_projected_sprites()

	for unit in units_root.get_children():
		#remove_child immediately so same-frame respawns don't see dying units in occupancy checks
		units_root.remove_child(unit)
		unit.queue_free()
