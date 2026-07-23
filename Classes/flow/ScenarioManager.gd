extends Node
class_name ScenarioManager

# Owns scenario save/load and the board-reset flow (dev_reset_scenario): serializes every
# live unit into a ScenarioUnitEntry/ScenarioData, and rebuilds the board from a saved one.

const SCENARIO_DIR := "res://Scenarios/"

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

func save_scenario(scenario_name: String):
	if scenario_name.strip_edges() == "":
		push_warning("Scenario needs a name")
		return

	var scenario := ScenarioData.new()
	scenario.scenario_name = scenario_name
	scenario.tile_data = grid.tile_map_data
	scenario.active_faction = turn_manager.active_faction()
	scenario.terrain_states = game.terrain_states.to_state_dict()
	scenario.zones = game.zone_manager.to_dict()

	for unit: Unit in units_root.get_children():
		if unit.is_queued_for_deletion():
			continue

		var entry := ScenarioUnitEntry.new()
		entry.unit_data = unit.unit_data.duplicate(true)
		entry.cell = unit.movement.cell
		entry.squad_id = squad_manager.squads.find(unit.squad)
		entry.is_leader = unit.is_leader()
		if entry.is_leader:
			entry.squad_name = unit.squad.squad_name
			entry.squad_archetype = unit.squad.archetype
			entry.squad_zone = unit.squad.zone_name

		entry.capture_unit_state(unit)

		scenario.unit_entries.append(entry)

	var path := SCENARIO_DIR + scenario_name + ".tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := ResourceSaver.save(scenario, path)
	if err != OK:
		push_error("Failed to save scenario: error %s" % err)
		return

	last_loaded_path = path

func load_scenario(path: String):
	var scenario: ScenarioData = load(path)
	if scenario == null:
		push_error("Could not load scenario at %s" % path)
		return

	_clear_board()

	grid.tile_map_data = scenario.tile_data
	game.terrain_states.load_state_dict(scenario.terrain_states)
	game.zone_manager.load_dict(scenario.zones)
	overlay_manager.redraw_zones(game.zone_manager)

	var leaders_by_squad_id := {}
	var members_by_squad_id := {}

	for entry in valid_entries(scenario):
		var unit: Unit = game.spawn_unit(entry.unit_data.duplicate(true), entry.cell)
		if unit == null:
			push_warning("Could not spawn unit at %s (blocked or off-map)" % entry.cell)
			continue

		entry.apply_unit_state(unit)

		if entry.squad_id == -1:
			continue

		if entry.is_leader:
			leaders_by_squad_id[entry.squad_id] = unit
			unit.squad.squad_name = entry.squad_name
			unit.squad.archetype = entry.squad_archetype
			unit.squad.zone_name = entry.squad_zone
			unit.squad.home_cell = entry.cell
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
			
	turn_manager.set_active_faction(scenario.active_faction)
	last_loaded_path = path

func reload_current():
	if last_loaded_path == "":
		return
	load_scenario(last_loaded_path)

func get_saved_scenarios() -> Array[String]:
	var paths: Array[String] = []
	_collect_scenarios(SCENARIO_DIR.trim_suffix("/"), paths)
	return paths

# Subfolders first, so fixtures/ groups above the root playtest saves.
func _collect_scenarios(dir: String, paths: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_collect_scenarios(dir.path_join(sub), paths)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			paths.append(dir.path_join(file))

func _unhandled_input(event):
	if event.is_action_pressed("dev_reset_scenario"):
		reload_current()

func _clear_board():
	game.dev_overlay.unit_editor.edit_unit(null)
	game.unit_info_panel.clear()
	squad_manager.clear_all_squads()
	game.clear_selection()
	game.refresh_action_queue(null)
	overlay_manager.clear_all_planned_paths()
	overlay_manager.clear_all_projected_sprites()

	for unit in units_root.get_children():
		#remove_child immediately so same-frame respawns don't see dying units in occupancy checks
		units_root.remove_child(unit)
		unit.queue_free()
