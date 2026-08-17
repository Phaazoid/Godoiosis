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
@onready var look_tool: LookTool = get_node("%Look")
@onready var object_tool: ObjectTool = get_node("%Objects")
@onready var dev_mode_toggle: CheckButton = %DevModeToggle
@onready var dev_mode_banner: PanelContainer = %DevModeBanner

# The banner's two faces. Dev chrome, not the HD-2D look stack -- no mission wears these and
# LookKnobs has no business holding them, so they are consts here rather than Look-tab knobs.
const DEV_MODE_ON_BG := Color(0.55, 0.16, 0.62)
const DEV_MODE_OFF_BG := Color(0.14, 0.14, 0.16)

var _banner_on: StyleBoxFlat
var _banner_off: StyleBoxFlat

# The running Battle3D, pushed in by attach_3d_host below; null under a flat Main.tscn launch.
# Any tab needing the 3D world reads it from here.
var host_3d: Node3D = null

# The dev keys work from THIS window too (#340 follow-up, found in play). This is a real second OS
# window, and a key event reaches only the focused one — so every dev binding was dead exactly when
# the dev was standing in the tool that arms it. Forwarded to DevController's one public entry, never
# reimplemented: two windows are two input SOURCES for one set of bindings.
#
# A text field must win first, or typing a scenario name would toggle the overlay and reset the
# board. gui_input is consumed by a focused LineEdit before _input ever runs here, so the guard is
# only needed for the case Godot cannot answer for us.
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit:
			return   # a SpinBox edits through a LineEdit too, so this covers the level/size fields
	game.dev_controller.handle_dev_key(event)


func _ready() -> void:
	if not DevTools.enabled():
		queue_free()   # a demo build constructs no dev tools (#132)
		return
	_build_banner_styles()
	# The toggle FOLLOWS the intent rather than being pushed at. set_dev_mode called this directly
	# until the 3D badge needed the same fact; one emit, every listener.
	game.dev_mode_changed.connect(sync_dev_mode_button)
	sync_dev_mode_button(game.dev_mode_enabled)
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
	tabs.set_tab_tooltip(5, "Paint the board — Terrain (with its level and ramp rise), Zones, or Tile States (fire/ice/cover); left-drag paints, right-drag erases.")
	tabs.set_tab_tooltip(6, "Tune the 3D look live — lighting, post, fog, camera, markup. Copy Values hands back what you moved.")
	tabs.set_tab_tooltip(7, "Terrain objects and effects — how props, tufts and cover bumps stand, and how fire is drawn. Game-wide, not per mission: Save to source writes the value into the script that declares it.")
	var authoring_tabs: TabContainer = %AuthoringTabs
	authoring_tabs.tab_changed.connect(_on_authoring_tab_changed)
	authoring_tabs.set_tab_tooltip(0, "Spawn units — configure here, then hover the board + Space to place.")
	authoring_tabs.set_tab_tooltip(1, "Author cast characters — the Resources/Units/ files authored saves reference. Update rewrites the character everywhere; Save As or Capture creates.")

# The 3D host PUSHES itself in from battle3d._ready (it already resolves this window to hide it).
# Nothing under Game reaches up to Battle3D as a result, and a flat Main.tscn launch just never
# calls this. A demo build has already queue_free()'d this window, so don't build 60-odd rows for it.
#
# The WINDOW holds it, not the Look tab (#234). It arrived for the Look tab (#212) and was named for
# it, and by #253 the Scenario tab was already borrowing it back off that panel -- which quietly made
# a tuning panel the project's host registry. Second consumer, so it moves to the wiring hub that
# every other tab is already wired from; look_tool keeps its own copy for the ~76 knob rows.
func attach_3d_host(host: Node3D) -> void:
	if not DevTools.enabled():
		return
	host_3d = host
	look_tool.attach_host(host)
	object_tool.attach_host(host)


# What the dev was looking at, for a bug report (#328). The WINDOW answers it, because the tabs are
# its own -- BugReporter reaching into %DevTabs would be a second reader of this window's layout.
# Unit Authoring is a container of two, so it names the sub-tab as well or the answer is half of one.
func current_tab_title() -> String:
	var tabs: TabContainer = %DevTabs
	var title := tabs.get_tab_title(tabs.current_tab)
	if tabs.get_current_tab_control() == unit_authoring:
		var authoring_tabs: TabContainer = %AuthoringTabs
		title += " / %s" % authoring_tabs.get_tab_title(authoring_tabs.current_tab)
	return title

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

# The banner SAYS its state three ways -- switch position, word, and background colour -- because
# the switch alone was what the dev could not read at a glance. The word is the load-bearing one.
func sync_dev_mode_button(active: bool):
	dev_mode_toggle.set_pressed_no_signal(active)
	dev_mode_toggle.text = "DEV MODE: ON" if active else "DEV MODE: OFF        (F1)"
	dev_mode_banner.add_theme_stylebox_override("panel", _banner_on if active else _banner_off)

# Built rather than authored: a StyleBoxFlat in the scene would be one resource, and the banner
# needs two to swap between. NOT a ColorPicker in sight -- that family is banned from this window
# (CLAUDE.md "Sharp edges", #212).
func _build_banner_styles() -> void:
	_banner_on = _banner_style(DEV_MODE_ON_BG)
	_banner_off = _banner_style(DEV_MODE_OFF_BG)

func _banner_style(bg: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_content_margin_all(6.0)
	box.set_corner_radius_all(4)
	return box

func _on_dev_mode_toggled(pressed: bool):
	game.set_dev_mode(pressed)
