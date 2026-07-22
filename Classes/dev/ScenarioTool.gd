extends VBoxContainer
class_name ScenarioTool

@onready var scenario_name_input: LineEdit = %ScenarioNameInput
@onready var scenario_dropdown: OptionButton = %ScenarioDropdown
@onready var ai_toggle_list: VBoxContainer = %AIToggleList
@onready var squad_list: VBoxContainer = %SquadList
var scenario_manager: ScenarioManager
var game

const NO_ZONE_LABEL := "(no zone)"

func init(p_scenario_manager: ScenarioManager, p_game):
	scenario_manager = p_scenario_manager
	game = p_game
	refresh_dropdown()
	_build_ai_toggles()
	refresh_squads()

func refresh_dropdown():
	scenario_dropdown.clear()
	for path in scenario_manager.get_saved_scenarios():
		scenario_dropdown.add_item(path.trim_prefix(ScenarioManager.SCENARIO_DIR).trim_suffix(".tres"))

func _build_ai_toggles():
	for child in ai_toggle_list.get_children():
		child.queue_free()
	for faction in Team.all_factions():
		var box := CheckBox.new()
		box.text = Team.faction_name(faction)
		box.button_pressed = game.ai_controller.is_faction_ai_enabled(faction)
		box.tooltip_text = "AI-controlled at this faction's turn"
		box.toggled.connect(func(pressed): game.ai_controller.set_faction_ai_enabled(faction, pressed))
		ai_toggle_list.add_child(box)

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

func _on_save_pressed():
	scenario_manager.save_scenario(scenario_name_input.text)
	refresh_dropdown()

func _on_load_pressed():
	if scenario_dropdown.selected < 0:
		return
	var paths := scenario_manager.get_saved_scenarios()
	scenario_manager.load_scenario(paths[scenario_dropdown.selected])
	refresh_squads()
