extends Window
class_name DevOverlay

# The dev-tools window — a real OS window when unembedded (CLAUDE.md "Sharp edges": dev tools =
# separate OS window; the game is wrapped in a SubViewport). Since #382 it is a SCOPE TREE over a
# page stack: the left-hand ToolTree selects a leaf, grouped by who the work belongs to — this
# MISSION (Scenario), the whole GAME (Project), or this sitting (Session) — and the old DevTabs
# TabContainer survives underneath with its tab bar hidden, purely as the page stack. That split
# is the load-bearing trick: every behaviour keyed on the current tab (the zone-overlay rule, the
# brush disarm, the on-show refreshes) still hangs off tab_changed, and the tree merely drives
# current_tab. LEAVES below is the one declaration of the tree; a law test pins it complete.
#
# Above the tree, always visible: ScenarioHeader — the scenario's file ops and the (modified)
# marker, reachable from every leaf for the same reason the Moods tab pinned its buttons above its
# sub-tabs (dev ask, 2026-08-14). Wires each tool that needs external state to the live game;
# Item Editor, Attack Editor and Character are self-sufficient (their own _ready() does all setup).

@onready var scenario_manager: ScenarioManager = get_node("../GameContainer/GameView/Game/ScenarioManager")
@onready var game = get_node("../GameContainer/GameView/Game")
@onready var tile_brush: TileBrushTool = get_node("%Tile Brush")
@onready var unit_editor: UnitEditorTool = get_node("%Unit Editor")
@onready var spawn: SpawnTool = get_node("%Spawn")
@onready var character_editor: CharacterEditorTool = get_node("%Character")
@onready var unit_authoring: MarginContainer = get_node("%Unit Authoring")
@onready var scenario_tool: ScenarioTool = get_node("%Scenario")
@onready var scenario_header: ScenarioHeader = get_node("%ScenarioHeader")
@onready var squads_ai: SquadsAiTool = get_node("%SquadsAI")
@onready var moods_tool: MoodsTool = get_node("%Moods")
@onready var object_tool: ObjectTool = get_node("%Objects")
@onready var game_tool: GameTool = get_node("%Game")
@onready var tool_tree: Tree = get_node("%ToolTree")
@onready var dev_mode_toggle: CheckButton = %DevModeToggle
@onready var dev_mode_banner: PanelContainer = %DevModeBanner

# The tree, declared whole: scope -> leaves, each leaf naming its page by unique name and carrying
# its tooltip. One table so the laws in tests/dev/test_dev_tree.gd can pin it — every leaf resolves
# to a real page, every page has exactly one leaf (an orphan page is a tool that silently vanished,
# which is how the Game tab shipped without a tooltip under the index-based scheme this replaced),
# and every leaf explains itself. Label is what current_tab_title() reports ("Scope / Leaf"), i.e.
# what a bug report's "Dev tools:" line says (#328).
const LEAVES: Array[Dictionary] = [
	{"scope": "Scenario", "label": "Properties", "page": "%Scenario",
		"tip": "What this mission DECLARES — objectives, the look preset it wears, where its camera opens. The header above saves all of it."},
	{"scope": "Scenario", "label": "Tile Brush", "page": "%Tile Brush",
		"tip": "Paint the board — Terrain (with its level and ramp rise), Zones, or Tile States (fire/ice/cover); left-drag paints, right-drag erases."},
	{"scope": "Scenario", "label": "Spawn", "page": "%Spawn",
		"tip": "Spawn units — configure here, then hover the board + Space to place."},
	{"scope": "Scenario", "label": "Unit Editor", "page": "%Unit Editor",
		"tip": "Click a unit in dev mode to edit it here — the unit standing on THIS board, not its character file."},
	{"scope": "Scenario", "label": "Squads & AI", "page": "%SquadsAI",
		"tip": "Who is standing on this board and how it behaves — per-faction AI control, and each squad's archetype and zone."},
	{"scope": "Project", "label": "Characters", "page": "%Character",
		"tip": "Author cast characters — the Resources/Units/ files authored saves reference. Update rewrites the character everywhere; Save As or Capture creates."},
	{"scope": "Project", "label": "Items", "page": "%Item Editor",
		"tip": "Author items — weapons and runes. Load a preset or start new, edit, name, save."},
	{"scope": "Project", "label": "Attacks", "page": "%Attack Editor",
		"tip": "Author attacks — Transmutation, Weapon Attack, or Family Mains (edit an established family's main in place); toggle at top."},
	{"scope": "Project", "label": "Objects", "page": "%Objects",
		"tip": "What a terrain object TYPE is — its own light, its own size — written into the tileset the tile itself carries."},
	{"scope": "Project", "label": "Moods", "page": "%Moods",
		"tip": "Scene mood, tuned live — lighting, post, fog, camera framing. Saves as a named mood a mission wears, or rewrites the default every other board gets."},
	{"scope": "Project", "label": "Game", "page": "%Game",
		"tip": "The game's own constants — board markup and its colours, the unit readout, camera handling, world construction, fire. Save to source writes each value into the declaration that authors it."},
	{"scope": "Session", "label": "Experiments", "page": "%Experiments",
		"tip": "Dev feature flags for this machine — persisted to user://, read by nothing a player ships with."},
]

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
	scenario_header.init(scenario_manager, game)
	scenario_tool.init(scenario_manager, game, scenario_header)
	squads_ai.init(game, scenario_header)
	spawn.init(game)
	unit_editor.init(game)
	tile_brush.init(game)
	# A file op changes the board under every scenario-scoped page; the header says so once and
	# the window routes it, so the header never reaches into a panel.
	scenario_header.file_changed.connect(_on_scenario_file_changed)
	close_requested.connect(_on_close_requested)
	%DevTabs.tab_changed.connect(_on_tab_changed)
	%AuthoringTabs.tab_changed.connect(_on_authoring_tab_changed)
	_build_tree()
	show_leaf(spawn)   # boot where the old tab 0 opened

# The 3D host PUSHES itself in from battle3d._ready (it already resolves this window to hide it).
# Nothing under Game reaches up to Battle3D as a result, and a flat Main.tscn launch just never
# calls this. A demo build has already queue_free()'d this window, so don't build 60-odd rows for it.
#
# The WINDOW holds it, not the Moods tab (#234). It arrived for the Moods tab (#212) and was named for
# it, and by #253 the Scenario tab was already borrowing it back off that panel -- which quietly made
# a tuning panel the project's host registry. Second consumer, so it moves to the wiring hub that
# every other tab is already wired from; moods_tool keeps its own copy for the ~76 knob rows.
func attach_3d_host(host: Node3D) -> void:
	if not DevTools.enabled():
		return
	host_3d = host
	moods_tool.attach_host(host)
	object_tool.attach_host(host)
	game_tool.attach_host(host)


# --- The tree ---------------------------------------------------------------------------------

# Built once from LEAVES. Scope rows are headers, not destinations — unselectable, always expanded.
# Each leaf's TreeItem carries its page control as metadata, so selection resolves by identity and
# never by index (the fragility the tooltip-by-index scheme died of).
func _build_tree() -> void:
	tool_tree.clear()
	var root := tool_tree.create_item()
	var scopes: Dictionary[String, TreeItem] = {}
	for leaf: Dictionary in LEAVES:
		var scope_name: String = leaf["scope"]
		if not scopes.has(scope_name):
			var scope_item := tool_tree.create_item(root)
			scope_item.set_text(0, scope_name.to_upper())
			scope_item.set_selectable(0, false)
			scopes[scope_name] = scope_item
		var item := tool_tree.create_item(scopes[scope_name])
		item.set_text(0, leaf["label"])
		item.set_tooltip_text(0, leaf["tip"])
		item.set_metadata(0, get_node(leaf["page"]))
	tool_tree.item_selected.connect(_on_tree_leaf_selected)


# The one door to "show this tool", whoever asks — a tree click, the boot selection, or the
# Unit Editor's click-a-unit jump. Sets the page stack AND the tree so the two cannot disagree;
# the guard stops the tree's own item_selected from re-entering while we sync it.
var _syncing_tree := false

func show_leaf(page: Control) -> void:
	_syncing_tree = true
	var item := _leaf_item_for(page)
	if item != null:
		item.select(0)
	_syncing_tree = false
	_show_page(page)


func _on_tree_leaf_selected() -> void:
	if _syncing_tree:
		return
	var item := tool_tree.get_selected()
	if item == null:
		return
	var page := item.get_metadata(0) as Control
	if page != null:
		_show_page(page)


# The page stack half: Spawn and Character still live under the Unit Authoring container in the
# scene (their connections stay untouched that way), so showing either sets both containers. The
# containers' tab_changed hooks below keep firing exactly as they did under the tab strip.
func _show_page(page: Control) -> void:
	var tabs: TabContainer = %DevTabs
	var authoring_tabs: TabContainer = %AuthoringTabs
	if page == spawn or page == character_editor:
		tabs.current_tab = tabs.get_tab_idx_from_control(unit_authoring)
		authoring_tabs.current_tab = authoring_tabs.get_tab_idx_from_control(page)
	else:
		tabs.current_tab = tabs.get_tab_idx_from_control(page)


func _leaf_item_for(page: Control) -> TreeItem:
	var root := tool_tree.get_root()
	if root == null:
		return null
	var scope_item := root.get_first_child()
	while scope_item != null:
		var item := scope_item.get_first_child()
		while item != null:
			if item.get_metadata(0) == page:
				return item
			item = item.get_next()
		scope_item = scope_item.get_next()
	return null


# What the dev was looking at, for a bug report (#328). The WINDOW answers it, because the tree is
# its own -- BugReporter reaching into %ToolTree would be a second reader of this window's layout.
# "Scope / Leaf", the tree's own words.
func current_tab_title() -> String:
	var item := tool_tree.get_selected()
	if item == null:
		return ""
	return "%s / %s" % [item.get_parent().get_text(0).capitalize(), item.get_text(0)]

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
	if current == squads_ai:
		squads_ai.refresh_on_show()
	if current != tile_brush:
		tile_brush.deactivate()
	_update_zone_visibility()


# A load/save/save-as changed what every scenario-scoped page draws — and where the dropdown of a
# freshly saved name lives. The pages refresh whether or not they are showing; both are cheap.
func _on_scenario_file_changed() -> void:
	scenario_tool.refresh_on_show()
	squads_ai.refresh_on_show()

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
	scenario_header.refresh_on_show()   # aim the dropdown at the loaded scenario on every window show
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
