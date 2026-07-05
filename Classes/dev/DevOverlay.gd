extends Window
class_name DevOverlay

@onready var scenario_manager: ScenarioManager = get_node("../GameContainer/GameView/Game/ScenarioManager")
@onready var game = get_node("../GameContainer/GameView/Game")
@onready var tile_brush: TileBrushTool = get_node("%Tile Brush")
@onready var unit_editor: UnitEditorTool = get_node("%Unit Editor")
@onready var spawn: SpawnTool = get_node("%Spawn")
@onready var scenario_tool: ScenarioTool = get_node("%Scenario")
@onready var dev_mode_toggle: CheckButton = %DevModeToggle

func _ready() -> void:
	scenario_tool.init(scenario_manager, game)
	spawn.init(game)
	unit_editor.init(game)
	tile_brush.init(game)
	close_requested.connect(_on_close_requested)
	%DevTabs.tab_changed.connect(_on_tab_changed)
	var tabs := %DevTabs
	tabs.set_tab_tooltip(0, "Spawn units — configure here, then hover the board + Space to place.")
	tabs.set_tab_tooltip(1, "Click a unit in dev mode to edit it here.")
	tabs.set_tab_tooltip(2, "Author items — weapons and runes. Load a preset or start new, edit, name, save.")
	tabs.set_tab_tooltip(3, "Author attack carvings — sigil weights + flourishes; runes inscribe these.")
	tabs.set_tab_tooltip(4, "Save / load board scenarios. F2 resets the current one.")
	tabs.set_tab_tooltip(5, "Paint tiles — left-drag paints, right-click erases.")

func _on_close_requested():
	hide()
	game.set_dev_mode(false)
	_update_zone_visibility()

func _on_tab_changed(_tab: int):
	var current = %DevTabs.get_current_tab_control()
	if current == spawn:
		spawn.refresh_weapons()
	if current == scenario_tool:
		scenario_tool.refresh_squads()
	if current != tile_brush:
		tile_brush.deactivate()
	_update_zone_visibility()

# Zones are authoring scaffolding -- visible only while actively painting (this window up
# AND the Tile Brush tab current), never during play.
func _update_zone_visibility() -> void:
	game.overlay_manager.set_zone_visibility(visible and %DevTabs.get_current_tab_control() == tile_brush)

func show_beside():
	var main_pos := DisplayServer.window_get_position(DisplayServer.MAIN_WINDOW_ID)
	var main_size := DisplayServer.window_get_size(DisplayServer.MAIN_WINDOW_ID)
	position = main_pos + Vector2i(main_size.x + 16, 0)
	show()
	_update_zone_visibility()

func sync_dev_mode_button(active: bool):
	dev_mode_toggle.set_pressed_no_signal(active)

func _on_dev_mode_toggled(pressed: bool):
	game.set_dev_mode(pressed)
