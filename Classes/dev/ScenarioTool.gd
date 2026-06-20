extends VBoxContainer
class_name ScenarioTool

@onready var scenario_name_input: LineEdit = %ScenarioNameInput
@onready var scenario_dropdown: OptionButton = %ScenarioDropdown
var scenario_manager: ScenarioManager

func init(p_scenario_manager: ScenarioManager):
	scenario_manager = p_scenario_manager
	refresh_dropdown()

func refresh_dropdown():
	scenario_dropdown.clear()
	for path in scenario_manager.get_saved_scenarios():
		scenario_dropdown.add_item(path.get_file().get_basename())

func _on_save_pressed():
	scenario_manager.save_scenario(scenario_name_input.text)
	refresh_dropdown()

func _on_load_pressed():
	if scenario_dropdown.selected < 0:
		return
	var paths := scenario_manager.get_saved_scenarios()
	scenario_manager.load_scenario(paths[scenario_dropdown.selected])
