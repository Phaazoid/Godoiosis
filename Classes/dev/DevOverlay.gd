extends Window
class_name DevOverlay

# The dev-tools window — a real OS window when unembedded (CLAUDE.md "Sharp edges": dev tools =
# separate OS window; the game is wrapped in a SubViewport). Owns the DevTabs TabContainer and
# wires each per-tool tab that needs external state (Spawn/Unit Editor/Scenario/Tile Brush) to the
# live game + scenario manager; Item Editor, Attack Editor and Character are self-sufficient
# (their own _ready() does all setup) and need no wiring here. The Unit Authoring tab is a plain
# container holding the Spawn and Character sub-tabs (#179 -- top-level tabs stay few, dev call).

@onready var scenario_manager: ScenarioManager = get_node("../GameContainer/GameView/Game/ScenarioManager")
@onready var game = get_node("../GameContainer/GameView/Game")
@onready var tile_brush: TileBrushTool = get_node("%Tile Brush")
@onready var unit_editor: UnitEditorTool = get_node("%Unit Editor")
@onready var spawn: SpawnTool = get_node("%Spawn")
@onready var unit_authoring: MarginContainer = get_node("%Unit Authoring")
@onready var scenario_tool: ScenarioTool = get_node("%Scenario")
@onready var dev_mode_toggle: CheckButton = %DevModeToggle

func _ready() -> void:
	if not DevTools.enabled():
		queue_free()   # a demo build constructs no dev tools (#132)
		return
	scenario_tool.init(scenario_manager, game)
	spawn.init(game)
	unit_editor.init(game)
	tile_brush.init(game)
	close_requested.connect(_on_close_requested)
	%DevTabs.tab_changed.connect(_on_tab_changed)
	var tabs := %DevTabs
	tabs.set_tab_tooltip(0, "Author units — Spawn places configured or cast units; Character edits the cast files.")
	tabs.set_tab_tooltip(1, "Click a unit in dev mode to edit it here.")
	tabs.set_tab_tooltip(2, "Author items — weapons and runes. Load a preset or start new, edit, name, save.")
	tabs.set_tab_tooltip(3, "Author attacks — Transmutation, Weapon Attack, or Family Mains (edit an established family's main in place); toggle at top.")
	tabs.set_tab_tooltip(4, "Save / load board scenarios. F2 resets the current one.")
	tabs.set_tab_tooltip(5, "Paint the board — Terrain, Zones, or Tile States (fire/ice/cover); left-drag paints, right-click erases.")
	var authoring_tabs: TabContainer = %AuthoringTabs
	authoring_tabs.tab_changed.connect(_on_authoring_tab_changed)
	authoring_tabs.set_tab_tooltip(0, "Spawn units — configure here, then hover the board + Space to place.")
	authoring_tabs.set_tab_tooltip(1, "Author cast characters — the Resources/Units/ files authored saves reference. Update rewrites the character everywhere; Save As or Capture creates.")

func _on_close_requested():
	hide()
	game.set_dev_mode(false)
	_update_zone_visibility()

func _on_tab_changed(_tab: int):
	var current = %DevTabs.get_current_tab_control()
	if current == unit_authoring:
		_refresh_spawn_pickers()
	if current == unit_editor:
		unit_editor.refresh_catalogs()
	if current == scenario_tool:
		scenario_tool.refresh_on_show()
	if current != tile_brush:
		tile_brush.deactivate()
	_update_zone_visibility()

# The Spawn form's dropdowns go stale whenever authoring happens elsewhere, so they refresh at
# BOTH doors into it: outer tab entry above, and the sub-tab switch here -- "save a character,
# flip to Spawn, place it" never fires an outer tab change (#179).
func _on_authoring_tab_changed(_tab: int) -> void:
	if %AuthoringTabs.get_current_tab_control() == spawn:
		_refresh_spawn_pickers()

func _refresh_spawn_pickers() -> void:
	spawn.refresh_weapons()
	spawn.refresh_characters()

# Zones are authoring scaffolding -- visible only while actively painting (this window up
# AND the Tile Brush tab current), never during play.
func _update_zone_visibility() -> void:
	game.overlay_manager.set_zone_visibility(visible and %DevTabs.get_current_tab_control() == tile_brush)

func show_beside():
	var main_pos := DisplayServer.window_get_position(DisplayServer.MAIN_WINDOW_ID)
	var main_size := DisplayServer.window_get_size(DisplayServer.MAIN_WINDOW_ID)
	position = main_pos + Vector2i(main_size.x + 16, 0)
	# Keep the whole window on the monitor: overlapping the game beats hanging off-screen.
	var usable := DisplayServer.screen_get_usable_rect(
		DisplayServer.window_get_current_screen(DisplayServer.MAIN_WINDOW_ID))
	position = Vector2i(
		clampi(position.x, usable.position.x, usable.position.x + usable.size.x - size.x),
		clampi(position.y, usable.position.y, usable.position.y + usable.size.y - size.y))
	show()
	_update_zone_visibility()

func sync_dev_mode_button(active: bool):
	dev_mode_toggle.set_pressed_no_signal(active)

func _on_dev_mode_toggled(pressed: bool):
	game.set_dev_mode(pressed)
