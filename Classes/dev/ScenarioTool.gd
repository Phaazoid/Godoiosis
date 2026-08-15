extends VBoxContainer
class_name ScenarioTool

# Dev-overlay tab for scenario authoring: Save As / Update / Load / Delete over Scenarios/,
# per-faction AI toggles (#150), squad archetype/zone rows, mission objectives (#96), and the
# authored-save checkbox (#177 — cast units save as references to their character files).

@onready var scenario_name_input: LineEdit = %ScenarioNameInput
@onready var scenario_dropdown: OptionButton = %ScenarioDropdown
@onready var update_button: Button = %UpdateScenarioButton
@onready var delete_button: Button = %DeleteScenarioButton
@onready var ai_toggle_list: VBoxContainer = %AIToggleList
@onready var objective_list: VBoxContainer = %ObjectiveList
@onready var squad_list: VBoxContainer = %SquadList
@onready var loaded_label: Label = %LoadedScenarioLabel
@onready var status_label: Label = %ScenarioStatusLabel

var scenario_manager: ScenarioManager
var game
var _objective_boxes := {}   # MissionRules.Objective -> CheckBox
var _ai_boxes: Dictionary[Team.Faction, CheckBox] = {}
var _objective_warning: Label
# Authored vs snapshot (#177). ON: cast units (spawned from character files) save as references
# and re-read their files on every load. OFF: the exact #87 mid-battle snapshot, cast included.
# Ad-hoc units snapshot fully either way.
var authored_save := true
var _look_row: HBoxContainer

const NO_ZONE_LABEL := "(no zone)"
const NO_LOOK_LABEL := "(none - default)"

func init(p_scenario_manager: ScenarioManager, p_game):
	scenario_manager = p_scenario_manager
	game = p_game
	refresh_dropdown()
	_build_ai_toggles()
	refresh_squads()
	_build_objectives()
	refresh_loaded_label()
	DevWidgets.add_checkbox(self, "Authored save — cast units re-read their character files",
		authored_save, func(pressed: bool): authored_save = pressed,
		"ON (authoring mode): units spawned from a character file (Resources/Units/) save as\n"
		+ "REFERENCES to that file — every load re-reads the character as authored, so editing\n"
		+ "the file later updates this mission too. Their mid-battle state (HP, Will, elemental\n"
		+ "states, weapon charge) is deliberately NOT saved. Ad-hoc units always save as full\n"
		+ "snapshots either way.\n\n"
		+ "OFF (snapshot mode): everything saves as an exact mid-battle snapshot, cast included —\n"
		+ "the save replays this precise moment forever and stops following character-file edits.\n"
		+ "Use for save-and-resume of a fight in progress.\n\n"
		+ "Bug reports (F3) ignore this and always snapshot.")
	move_child(get_child(get_child_count() - 1), 0)
	refresh_look_row()


# The board's look (#253 part 2). Code-built and moved to the top, exactly like the checkbox above
# -- the tab's fixed controls live in the .tscn, anything data-shaped is generated.
func refresh_look_row() -> void:
	if _look_row != null:
		remove_child(_look_row)
		_look_row.queue_free()
	var options: Array[String] = [NO_LOOK_LABEL]
	options.append_array(LookKnobs.saved_presets())
	var current: String = scenario_manager.current_look_preset
	# A board naming a since-deleted preset keeps the stale name selectable, so the binding stays
	# VISIBLE rather than silently reading as "(none)" -- the same call the squad zone row makes.
	if current != "" and not options.has(current):
		options.append(current)
	_look_row = DevWidgets.add_option(self, "Look preset", options,
		current if current != "" else NO_LOOK_LABEL, _on_look_picked)
	move_child(_look_row, 0)


func _on_look_picked(picked: String) -> void:
	scenario_manager.current_look_preset = "" if picked == NO_LOOK_LABEL else picked
	# Apply live so the pick is visible at once, and route it through the Look tab so ITS baseline
	# stays in step -- that tab is also the only thing here holding the pushed-in 3D host.
	var overlay: DevOverlay = game.dev_overlay
	if overlay == null or not overlay.look_tool.has_host():
		return
	overlay.look_tool.apply_preset(LookKnobs.resolve(scenario_manager.current_look_preset))

# select_name is a dropdown-relative name ("fixtures/Foo"), not a path. Load and Save As hand it
# whatever they just touched; the empty default re-selects what was already showing, so a rebuild
# never silently moves Update's target.
func refresh_dropdown(select_name := "") -> void:
	if select_name == "":
		select_name = DevWidgets.selected_name(scenario_dropdown)

	scenario_dropdown.clear()
	for path in scenario_manager.get_saved_scenarios():
		scenario_dropdown.add_item(ScenarioManager.display_name(path))

	# add_item auto-selects index 0 -- force "nothing picked" unless the name really matched,
	# or a deleted scenario leaves Update aimed at whatever sorts first.
	scenario_dropdown.select(-1)
	for i in scenario_dropdown.item_count:
		if scenario_dropdown.get_item_text(i) == select_name:
			scenario_dropdown.select(i)
			break

	_refresh_update_button()

func refresh_loaded_label() -> void:
	var path: String = scenario_manager.last_loaded_path
	if path == "":
		loaded_label.text = "Loaded: (unsaved board)"
		return
	loaded_label.text = "Loaded: %s" % ScenarioManager.display_name(path)

# Called on tab-switch: a mission loaded from the boot screen, or an F2 reset, changes the board
# without going through this tab.
func refresh_on_show() -> void:
	refresh_squads()
	refresh_objectives()
	refresh_ai_toggles()
	refresh_loaded_label()
	refresh_look_row()   # a board load changes which preset this board wears
	# Aim the dropdown at the loaded scenario (dev ask 2026-08-11): with the load-gate it is the
	# only target Update can act on, so finding it by hand every visit was pure friction. Nothing
	# loaded leaves the selection alone; refresh_dropdown re-evaluates the Update button either way.
	if scenario_manager.last_loaded_path != "":
		refresh_dropdown(ScenarioManager.display_name(scenario_manager.last_loaded_path))
	else:
		_refresh_update_button()

func _refresh_update_button() -> void:
	DevWidgets.refresh_update_button(update_button, DevWidgets.selected_name(scenario_dropdown), "scenario", _update_block_reason())
	DevWidgets.refresh_delete_button(delete_button, DevWidgets.selected_name(scenario_dropdown), "scenario")

# "" = allowed. Update only writes the LOADED board back over its own file (dev call 2026-08-11);
# aiming it anywhere else is how missions/Prolog got destroyed.
func _update_block_reason() -> String:
	var target := DevWidgets.selected_name(scenario_dropdown)
	if target == "":
		return ""
	if ScenarioManager.scenario_path(target) != scenario_manager.last_loaded_path:
		return "Load '%s' before updating it -- Update saves the loaded board back over its own file" % target
	return ""

func _build_ai_toggles():
	for child in ai_toggle_list.get_children():
		child.queue_free()
	_ai_boxes.clear()
	for faction in Team.all_factions():
		var box := CheckBox.new()
		box.text = Team.faction_name(faction)
		box.button_pressed = game.ai_controller.is_faction_ai_enabled(faction)
		box.tooltip_text = "AI-controlled at this faction's turn"
		box.toggled.connect(func(pressed): game.ai_controller.set_faction_ai_enabled(faction, pressed))
		ai_toggle_list.add_child(box)
		_ai_boxes[faction] = box

# The flags are board content since #150, so a load changes them without this tab's involvement.
# set_pressed_no_signal, never button_pressed: the latter fires `toggled`, and a refresh that
# writes back into AIController would author state instead of displaying it.
func refresh_ai_toggles() -> void:
	for faction in _ai_boxes:
		var enabled: bool = game.ai_controller.is_faction_ai_enabled(faction)
		_ai_boxes[faction].set_pressed_no_signal(enabled)

# Public so DevOverlay can call it on tab-switch -- squads form/rename outside this tab
# (Unit Editor, actual play), so the list needs to be rebuilt each time it's shown.
func refresh_squads():
	for child in squad_list.get_children():
		child.queue_free()

	var squads_by_faction := {}
	for squad in game.squad_manager.squads:
		if not is_instance_valid(squad) or squad.leader == null:
			continue
		var faction = squad.leader.get_faction()
		if not squads_by_faction.has(faction):
			squads_by_faction[faction] = []
		squads_by_faction[faction].append(squad)

	for faction in Team.all_factions():
		if not squads_by_faction.has(faction):
			continue
		DevWidgets.add_label(squad_list, Team.faction_name(faction))
		for squad in squads_by_faction[faction]:
			squad_list.add_child(_build_squad_row(squad))

func _build_squad_row(squad: Squad) -> HBoxContainer:
	var row := HBoxContainer.new()

	var label := Label.new()
	label.text = squad.squad_name if squad.squad_name != "" else "(unnamed, leader: %s)" % squad.leader.get_unit_name()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var archetype := OptionButton.new()
	var type_names := AIArchetype.Type.keys()
	for i in type_names.size():
		archetype.add_item(type_names[i])
	archetype.select(squad.archetype)
	archetype.item_selected.connect(func(idx): squad.archetype = AIArchetype.Type.values()[idx])
	row.add_child(archetype)

	var zone := OptionButton.new()
	var zone_options: Array[String] = [NO_ZONE_LABEL]
	zone_options.append_array(game.zone_manager.zone_names())
	# A squad can point at a zone that's since been fully erased -- keep the stale name
	# selectable so the binding stays visible instead of silently reading as "(no zone)".
	if squad.zone_name != "" and not zone_options.has(squad.zone_name):
		zone_options.append(squad.zone_name)
	var current := squad.zone_name if squad.zone_name != "" else NO_ZONE_LABEL
	for i in zone_options.size():
		zone.add_item(zone_options[i])
		if zone_options[i] == current:
			zone.select(i)
	zone.item_selected.connect(func(idx): squad.zone_name = "" if idx == 0 else zone_options[idx])
	row.add_child(zone)

	return row

func _on_load_pressed() -> void:
	var target := DevWidgets.selected_name(scenario_dropdown)
	if target == "":
		return
	scenario_manager.load_scenario(ScenarioManager.scenario_path(target))
	refresh_squads()
	refresh_objectives()
	refresh_ai_toggles()
	refresh_dropdown(target)
	refresh_loaded_label()
	refresh_look_row()   # a board load changes which preset this board wears

func _on_update_pressed() -> void:
	var target := DevWidgets.selected_name(scenario_dropdown)
	if target == "":
		return
	# The handler is the real gate -- the disabled button is only its surface (#166 shape).
	var reason := _update_block_reason()
	if reason != "":
		status_label.text = reason
		return
	# Confirmed like Delete (dev call 2026-08-12): the load-gate cannot catch a mis-click at the
	# loaded file itself -- a wrecked board (accidental resize) one button away from Load is
	# exactly how Level_1 died.
	DevWidgets.confirm(self, "Overwrite scenario '%s' with the current board? The saved version is lost." % target,
		func(): _update_confirmed(target))

func _update_confirmed(target: String) -> void:
	# Subfolder names round-trip untouched: save_over make_dir_recursive's the base dir.
	scenario_manager.save_scenario(target, status_label, authored_save)
	refresh_dropdown(target)
	refresh_loaded_label()
	refresh_look_row()   # a board load changes which preset this board wears

func _on_delete_pressed() -> void:
	var target := DevWidgets.selected_name(scenario_dropdown)
	if target == "":
		return
	DevWidgets.confirm_delete(self, "scenario '%s'" % target, func(): _delete_confirmed(target))

func _delete_confirmed(target: String) -> void:
	if DevWidgets.delete_saved_file(ScenarioManager.scenario_path(target), "scenario", status_label):
		refresh_dropdown()

func _on_save_as_pressed() -> void:
	var entered := scenario_name_input.text.strip_edges()
	if entered == "":
		var msg := "Scenario needs a name"
		push_warning(msg)
		status_label.text = msg
		return
	# allow_slash: Scenarios/fixtures/-style subfolder names are a real feature here, unlike
	# Item/Attack's flat catalogs (#168).
	if DevWidgets.refuse_illegal_name(entered, "scenario", status_label, true):
		return
	if DevWidgets.refuse_existing_file(ScenarioManager.scenario_path(entered), "scenario", status_label):
		return
	scenario_manager.save_scenario(entered, status_label, authored_save)
	scenario_name_input.text = ""
	refresh_dropdown(entered)
	refresh_loaded_label()
	refresh_look_row()   # a board load changes which preset this board wears

func _on_load_dropdown_item_selected(_index: int) -> void:
	_refresh_update_button()
	
# One checkbox per objective, driven off the enum so a new objective kind needs no edit here.
func _build_objectives() -> void:
	DevWidgets.add_label(objective_list, "Mission objectives")
	for objective in MissionRules.Objective.values():
		var box := CheckBox.new()
		box.text = String(MissionRules.Objective.keys()[objective]).capitalize()
		box.button_pressed = game.mission_controller.objectives.has(objective)
		box.toggled.connect(func(pressed: bool): _on_objective_toggled(objective, pressed))
		objective_list.add_child(box)
		_objective_boxes[objective] = box

	_objective_warning = Label.new()
	_objective_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_warning.modulate = Color(1, 0.45, 0.35)
	objective_list.add_child(_objective_warning)
	_refresh_objective_warning()

func refresh_objectives() -> void:
	for objective in _objective_boxes:
		_objective_boxes[objective].set_pressed_no_signal(game.mission_controller.objectives.has(objective))
	_refresh_objective_warning()

func _on_objective_toggled(objective: MissionRules.Objective, pressed: bool) -> void:
	if pressed:
		if not game.mission_controller.objectives.has(objective):
			game.mission_controller.objectives.append(objective)
	else:
		game.mission_controller.objectives.erase(objective)
	_refresh_objective_warning()
	game.refresh_mission_status()   # this write bypasses set_objectives, so refresh here (#134)

# The guard you asked for: an objective ticked with no matching zone painted makes the mission
# unwinnable. Far cheaper to say so at authoring time than to find out mid-playtest.
func _refresh_objective_warning() -> void:
	var missing: Array = game.mission_controller.objectives_missing_geometry()
	if missing.is_empty():
		_objective_warning.text = ""
		return
	var names := []
	for objective in missing:
		names.append(MissionRules.Objective.keys()[objective])
	_objective_warning.text = "⚠ No zone painted for: %s — this mission cannot be won." % ", ".join(names)
