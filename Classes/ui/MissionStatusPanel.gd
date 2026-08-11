extends Control
class_name MissionStatusPanel

# The mission-status HUD (#134) -- the first always-on element in the game viewport. One row per
# DECLARED objective, with its progress ("Capture -- 1/2 zones"), plus the build version stamp in
# the top-right corner. Shows the declared list ONLY -- never an implied "kill everyone" line,
# because an authored objective is the only way to win (docs/design/missions.md).
#
# A declared second REPRESENTATION of what the board's zone tint already shows (Law #4):
# MissionController stays authoritative, this panel only draws what it is handed on refresh, and
# game.refresh_mission_status() is the one caller. Rules and counts are read off the controller,
# never re-derived here.

const CORNER_MARGIN := 8
const MET_COLOR := Color(0.55, 0.95, 0.55)
const PENDING_COLOR := Color(0.92, 0.92, 0.92)
const UNWINNABLE_COLOR := Color(1, 0.45, 0.35)   # the Scenario tab's warning colour

@onready var _panel: PanelContainer = $ObjectivePanel
@onready var _rows: VBoxContainer = $ObjectivePanel/Rows
@onready var _version_label: Label = $VersionLabel

func _ready() -> void:
	z_index = UiLayers.MISSION_STATUS
	_panel.visible = false
	_version_label.text = "v" + Build.version()
	_version_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 6)

# No mission on this board (sandbox, cleared) -- nothing to say. The version stamp stays.
func clear() -> void:
	_panel.visible = false

func show_status(controller: MissionController, board: BoardContext) -> void:
	# Immediate free, not queue_free: the panel re-lays out from minimum size below, and a dying
	# child still counts toward it until end of frame.
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.free()
	var header := Label.new()
	header.text = "OBJECTIVES"
	header.add_theme_font_size_override("font_size", 11)
	header.modulate = Color(1, 1, 1, 0.65)
	_rows.add_child(header)
	for objective in controller.objectives:
		_rows.add_child(_build_row(objective, controller, board))
	_panel.visible = true
	# Re-anchor from the new minimum size each refresh -- offsets track content both ways, so a
	# shrinking list never leaves the panel ratcheted at its widest (the off-screen-card lesson).
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, CORNER_MARGIN)

func _build_row(objective: MissionRules.Objective, controller: MissionController, board: BoardContext) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	# Declared but unpainted: the mission is unwinnable and the row must say so, never vanish
	# (canon -- silently dropping it would turn a broken map into a different, playable one).
	if controller.objectives_missing_geometry().has(objective):
		label.text = "%s — no zone painted" % _title(objective)
		label.modulate = UNWINNABLE_COLOR
		return label
	if controller.progress_for(objective, board) == MissionRules.Progress.MET:
		label.text = "✓ " + _title(objective)
		label.modulate = MET_COLOR
		return label
	match objective:
		MissionRules.Objective.ROUT:
			var left := MissionRules.active_hostile_count(board)
			label.text = "Rout — %d %s" % [left, "foe remains" if left == 1 else "foes remain"]
		MissionRules.Objective.CAPTURE:
			var captured: Vector2i = controller.capture_counts()
			label.text = "Capture — %d/%d zones" % [captured.x, captured.y]
		MissionRules.Objective.EXTRACT:
			var extracted: Vector2i = controller.extract_counts(board)
			label.text = "Extract — %d/%d in the zone" % [extracted.x, extracted.y]
		_:
			label.text = _title(objective)
	label.modulate = PENDING_COLOR
	return label

func _title(objective: MissionRules.Objective) -> String:
	return String(MissionRules.Objective.keys()[objective]).capitalize()
