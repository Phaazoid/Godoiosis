extends VBoxContainer
class_name ScenarioTool

# The Properties page (#382): what this mission DECLARES -- objectives (#96), the look preset it
# wears (#253), and where its camera opens (#234). The file operations that used to head this tab
# live on ScenarioHeader now (the persistent header over the whole window), and the board's
# occupants (AI toggles, squad rows) live on SquadsAiTool -- what a mission requires versus who is
# standing on it, split at the seam.
#
# Every edit here is scenario content, so each one marks the header modified.

@onready var objective_list: VBoxContainer = %ObjectiveList

var scenario_manager: ScenarioManager
var game
var _header: ScenarioHeader
var _objective_boxes := {}   # MissionRules.Objective -> CheckBox
var _objective_warning: Label
var _look_row: HBoxContainer
var _camera_row: HBoxContainer

const NO_LOOK_LABEL := "(none - default)"


func init(p_scenario_manager: ScenarioManager, p_game, header: ScenarioHeader) -> void:
	scenario_manager = p_scenario_manager
	game = p_game
	_header = header
	_build_objectives()
	refresh_look_row()
	refresh_camera_row()   # last, so it lands above the look row and stays there on every rebuild


func _mark() -> void:
	if _header != null:
		_header.mark_modified()


# The board's look (#253 part 2). Code-built and moved to the top -- the page's fixed controls
# live in the .tscn, anything data-shaped is generated.
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
	_mark()
	# Apply live so the pick is visible at once, and route it through the Moods tab so ITS baseline
	# stays in step.
	var overlay: DevOverlay = game.dev_overlay
	if overlay == null or not overlay.moods_tool.has_host():
		return
	overlay.moods_tool.apply_preset(LookKnobs.resolve(scenario_manager.current_look_preset))


# Where this board opens the camera (#234). Same code-built-and-moved-to-the-top shape as the look
# row: fly the camera where you want the mission to start and press Capture, rather than typing
# numbers at it. Persisted by the header's Save As / Update, through capture_scenario.
func refresh_camera_row() -> void:
	if _camera_row != null:
		remove_child(_camera_row)
		_camera_row.queue_free()

	_camera_row = HBoxContainer.new()
	var label := Label.new()
	label.text = "Camera start: %s" % _camera_start_text()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_camera_row.add_child(label)

	var capture := Button.new()
	capture.text = "Capture view"
	capture.disabled = _host_3d() == null
	capture.pressed.connect(_on_capture_camera_pressed)
	_camera_row.add_child(capture)

	var clear := Button.new()
	clear.text = "Clear"
	clear.disabled = scenario_manager.current_camera_start == null
	clear.pressed.connect(_on_clear_camera_pressed)
	_camera_row.add_child(clear)

	DevWidgets.apply_tooltip(_camera_row, DevWidgets.wrap_tooltip(
		"Where the camera sits when this mission OPENS. Capture stores the view you are looking at "
		+ "right now -- aim, angle and zoom -- and every load of this board returns to it, including "
		+ "a resumed save.\n\n"
		+ "Clear goes back to DERIVED: the camera opens on your own units, as wide as the Moods tab's "
		+ "'Opening shot (cells)'. That knob does nothing on a board that authors a start.\n\n"
		+ "Nothing is validated. Edit the board afterwards and an aim that now sits off it is simply "
		+ "clamped back on, silently -- re-capture if the shot looks wrong.\n\n"
		+ "3D only: the flat 2D view has no opening shot of its own (#292)."))

	add_child(_camera_row)
	move_child(_camera_row, 0)


func _camera_start_text() -> String:
	var start: CameraPose = scenario_manager.current_camera_start
	if start == null:
		return "derived (opens on your own units)"
	return "authored -- yaw %.0f deg, zoom %.1f, at %s" % [
		start.yaw_degrees, start.distance, BoardSpace.flat(BoardSpace.cell_of(start.aim))]


# Null under a flat Main.tscn launch -- nothing pushed a 3D world in, so there is no view to capture.
func _host_3d() -> Node3D:
	var overlay: DevOverlay = game.dev_overlay
	return null if overlay == null else overlay.host_3d


func _on_capture_camera_pressed() -> void:
	var host := _host_3d()
	if host == null:
		return
	scenario_manager.current_camera_start = host.capture_camera_start()
	_mark()
	_status().text = "Camera start captured -- save the scenario to keep it."
	refresh_camera_row()


func _on_clear_camera_pressed() -> void:
	scenario_manager.current_camera_start = null
	_mark()
	_status().text = "Camera start cleared -- this board opens on your own units again."
	refresh_camera_row()


# The one status line is the header's -- a second per-page one would be a second place to look.
func _status() -> Label:
	return _header.status_label


# Called on show and on the header's file_changed: a mission loaded from the boot screen, or an
# F2 reset, changes the board without going through this page.
func refresh_on_show() -> void:
	refresh_objectives()
	refresh_look_row()   # a board load changes which preset this board wears
	refresh_camera_row()   # ...and where it opens (#234)


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
	_mark()
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
