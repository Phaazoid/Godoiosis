extends PanelContainer
class_name ScenarioHeader

# The scenario's file operations, as a persistent header over the whole dev-tools window (#382):
# SCENARIO -- <name> (modified), Load / Update / Save As / Delete, and the authored-save checkbox.
# Carved out of the Scenario tab when the window went from tabs to a scope tree, for the same
# reason the Moods tab pinned its buttons above its sub-tabs (dev ask, 2026-08-14): saving must be
# reachable from wherever you are, never a navigation away.
#
# The file ops are ScenarioTool's old ones, verbatim in behaviour: Update is load-gated AND
# confirmed, Delete confirms, Save As refuses a taken name. What is new is the DIRTY MARKER --
# "(modified)" means AUTHORING edits since load/save, declared narrowly: terrain (the grid's own
# DirtyCells.version, the #308 any-number-of-readers counter), zones (zones_changed), and
# scenario-field edits (the Properties and Squads & AI panels call mark_modified()). Unit movement
# and combat deliberately do NOT mark -- a mid-battle board is always "changed" in the snapshot
# sense, and a marker that is always on says nothing.
#
# A file op that changes the board emits file_changed; DevOverlay routes it to the panels that
# draw board state. The header never reaches into a panel itself.

signal file_changed

@onready var loaded_label: Label = %LoadedScenarioLabel
@onready var scenario_dropdown: OptionButton = %ScenarioDropdown
@onready var update_button: Button = %UpdateScenarioButton
@onready var delete_button: Button = %DeleteScenarioButton
@onready var scenario_name_input: LineEdit = %ScenarioNameInput
@onready var status_label: Label = %ScenarioStatusLabel

var scenario_manager: ScenarioManager
var game
# Authored vs snapshot (#177). ON: cast units (spawned from character files) save as references
# and re-read their files on every load. OFF: the exact #87 mid-battle snapshot, cast included.
# Ad-hoc units snapshot fully either way.
var authored_save := true

# The dirty marker's memory: what the terrain counter read at the last load/save, and whether
# anything else (zones, scenario fields) has marked since. _process polls the terrain counter
# because DirtyCells is deliberately signal-free; gated on the window being visible.
var _seen_terrain_version := -1
var _marked := false
var _shown_dirty := false   # what the label currently says, so the poll only redraws on a flip


func init(p_scenario_manager: ScenarioManager, p_game) -> void:
	scenario_manager = p_scenario_manager
	game = p_game
	refresh_dropdown()
	var row := get_node("HeaderVbox/NewRow") as HBoxContainer
	DevWidgets.add_checkbox(row, "Authored",
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
	game.zone_manager.zones_changed.connect(mark_modified)
	# A board can arrive from OUTSIDE the header's own Load -- Mission Select, F2, the boot screen.
	# clear_board's grid.reset() bumps the terrain counter, so without re-stamping here every
	# external load would read (modified) on arrival.
	scenario_manager.board_loaded.connect(_on_board_loaded)
	_stamp_clean()
	refresh_loaded_label()


func _on_board_loaded() -> void:
	_stamp_clean()
	refresh_on_show()


# --- The dirty marker ----------------------------------------------------------------------

# Anything that authors the board and is not the terrain counter's business calls this: a zone
# paint (wired above), an objective toggle, a look pick, a camera capture, a squad field.
func mark_modified() -> void:
	if _marked:
		return
	_marked = true
	refresh_loaded_label()


# Modified is relative to a FILE: an unsaved board has nothing to have drifted from, so it never
# wears the marker however much has been painted onto it.
func is_modified() -> bool:
	if game == null or scenario_manager == null or scenario_manager.last_loaded_path == "":
		return false
	return _marked or game.grid.dirty.version != _seen_terrain_version


# A load or a save is the board and the file agreeing again, by definition.
func _stamp_clean() -> void:
	_marked = false
	if game != null:
		_seen_terrain_version = game.grid.dirty.version


# The terrain counter has no signal, so the label follows it by poll -- window-local, an int
# compare, and only while the window is up. Everything else updates the label at the moment it
# marks, so this only ever catches the brush.
func _process(_delta: float) -> void:
	var window := get_window()
	if window == null or not window.visible:
		return
	if is_modified() != _shown_dirty:
		refresh_loaded_label()


func refresh_loaded_label() -> void:
	var path: String = scenario_manager.last_loaded_path if scenario_manager != null else ""
	var shown := "(unsaved board)" if path == "" else ScenarioManager.display_name(path)
	_shown_dirty = is_modified()
	loaded_label.text = "SCENARIO — %s%s" % [shown, "  (modified)" if _shown_dirty else ""]


# --- File ops (ScenarioTool's, moved whole) --------------------------------------------------

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


# Called when the window shows and when a board arrives from outside (Mission Select, F2): aim
# the dropdown at the loaded scenario -- with the load-gate it is the only target Update can act
# on, so finding it by hand every visit was pure friction. Nothing loaded leaves the selection
# alone; refresh_dropdown re-evaluates the Update button either way.
func refresh_on_show() -> void:
	refresh_loaded_label()
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


func _on_load_pressed() -> void:
	var target := DevWidgets.selected_name(scenario_dropdown)
	if target == "":
		return
	scenario_manager.load_scenario(ScenarioManager.scenario_path(target))
	_stamp_clean()
	refresh_dropdown(target)
	refresh_loaded_label()
	file_changed.emit()


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
	DevWidgets.confirm_overwrite(self, "scenario '%s'" % target, "the current board",
		func(): _update_confirmed(target))


func _update_confirmed(target: String) -> void:
	# Subfolder names round-trip untouched: save_over make_dir_recursive's the base dir.
	scenario_manager.save_scenario(target, status_label, authored_save)
	_stamp_clean()
	refresh_dropdown(target)
	refresh_loaded_label()
	file_changed.emit()


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
	_stamp_clean()
	scenario_name_input.text = ""
	refresh_dropdown(entered)
	refresh_loaded_label()
	file_changed.emit()


func _on_load_dropdown_item_selected(_index: int) -> void:
	_refresh_update_button()
