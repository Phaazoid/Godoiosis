extends Window
class_name DevOverlay

@onready var scenario_manager: ScenarioManager = get_node("../GameContainer/GameView/Game/ScenarioManager")
@onready var game = get_node("../GameContainer/GameView/Game")
@onready var tile_brush: TileBrushTool = get_node("%Tile Brush")
@onready var unit_editor: UnitEditorTool = get_node("%Unit Editor")
@onready var spawn: SpawnTool = get_node("%Spawn")
@onready var dev_mode_toggle: CheckButton = %DevModeToggle

func _ready() -> void:
	(%Scenario as ScenarioTool).init(scenario_manager)
	spawn.init(game)
	close_requested.connect(_on_close_requested)
	%DevTabs.tab_changed.connect(_on_tab_changed)
	var tabs := %DevTabs
	tabs.set_tab_tooltip(0, "Spawn units — configure here, then hover the board + Space to place.")
	tabs.set_tab_tooltip(1, "Author weapons — load a preset or start new, edit, name, and save.")
	tabs.set_tab_tooltip(2, "Click a unit in dev mode to edit it here.")
	tabs.set_tab_tooltip(3, "Save / load board scenarios. F2 resets the current one.")
	tabs.set_tab_tooltip(4, "Paint tiles — left-drag paints, right-click erases.")

func _on_close_requested():
	hide()
	game.set_dev_mode(false)

func _on_tab_changed(_tab: int):
	var current = %DevTabs.get_current_tab_control()
	if current == spawn:
		spawn.refresh_weapons()
	if current != tile_brush:
		tile_brush.deactivate()
		
func show_beside():
	var main_pos := DisplayServer.window_get_position(DisplayServer.MAIN_WINDOW_ID)
	var main_size := DisplayServer.window_get_size(DisplayServer.MAIN_WINDOW_ID)
	position = main_pos + Vector2i(main_size.x + 16, 0)
	show()

func sync_dev_mode_button(active: bool):
	dev_mode_toggle.set_pressed_no_signal(active)

func _on_dev_mode_toggled(pressed: bool):
	game.set_dev_mode(pressed)
