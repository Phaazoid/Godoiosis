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
const BUTTON_CLEARANCE := 44   # the End Turn button's reserved corner slot below us: 36 high + its 8 margin (#189)
const MET_COLOR := Color(0.55, 0.95, 0.55)
const PENDING_COLOR := Color(0.92, 0.92, 0.92)
const UNWINNABLE_COLOR := Color(1, 0.45, 0.35)   # the Scenario tab's warning colour
const INSTRUCTION_COLOR := Color(1, 0.87, 0.5)   # guidance, not a win condition -- its own colour lane

# The clock's urgency cue (#101, dev fork C: colour it, don't interrupt with a modal). `static var`
# rather than `const` because these are GameKnobs.CLASS_KNOBS rows -- a feel value gets a knob, and
# this panel is 2D UI so the node-property table cannot reach it.
static var URGENT_ROUNDS := 2               # rounds left at or below which the clock goes urgent
static var URGENT_COLOR := Color(1, 0.55, 0.3)

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

func show_status(controller: MissionController, board: BoardContext, instruction := "") -> void:
	# Immediate free, not queue_free: the panel re-lays out from minimum size below, and a dying
	# child still counts toward it until end of frame.
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.free()
	if not controller.objectives.is_empty():   # a lesson-only board has no OBJECTIVES header to earn
		_rows.add_child(_build_header("OBJECTIVES"))
	for objective in controller.objectives:
		_rows.add_child(_build_row(objective, controller, board))
	# What LOSES it (#101), under its own header: a countdown listed among the objectives reads as
	# something to achieve. Driven off the declared list, so the next condition needs no edit here.
	if not controller.lose_conditions.is_empty():
		_rows.add_child(_build_header("FAIL IF"))
	for condition in controller.lose_conditions:
		_rows.add_child(_build_lose_row(condition, controller))
	# The tutorial's instruction row (#182): what to do NOW. Drawn last, below the win conditions,
	# and only handed to us -- ScenarioDirector owns the text, game.refresh_mission_status() the read.
	if instruction != "":
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 13)
		row.text = "> " + instruction
		row.modulate = INSTRUCTION_COLOR
		_rows.add_child(row)
	_panel.visible = true
	# Re-anchor from the new minimum size each refresh -- offsets track content both ways, so a
	# shrinking list never leaves the panel ratcheted at its widest (the off-screen-card lesson).
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, CORNER_MARGIN)
	# Pure post-preset translation, so it never fights the anchor math above: lifts the panel clear
	# of the End Turn button's slot at the corner itself (#189) -- reserved even while the button is
	# hidden, so the HUD never reflows when it appears.
	_panel.offset_top -= BUTTON_CLEARANCE
	_panel.offset_bottom -= BUTTON_CLEARANCE

func _build_header(text: String) -> Label:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 11)
	header.modulate = Color(1, 1, 1, 0.65)
	return header

# One declared lose condition. Rules and counts come off the controller, never re-derived here.
func _build_lose_row(condition: MissionRules.LoseCondition, controller: MissionController) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	# Declared with nothing to fire on -- the objectives' unpainted-geometry row, same doctrine: the
	# mission is broken and the row must say so rather than vanish.
	if controller.lose_conditions_missing_setup().has(condition):
		label.text = "%s — not set" % _lose_title(condition)
		label.modulate = UNWINNABLE_COLOR
		return label
	match condition:
		MissionRules.LoseCondition.ROUND_LIMIT:
			var left: int = controller.rounds_remaining()
			label.text = "Time — %d %s" % [left, "round left" if left == 1 else "rounds left"]
			label.modulate = URGENT_COLOR if left <= URGENT_ROUNDS else PENDING_COLOR
			return label
	label.text = _lose_title(condition)
	label.modulate = PENDING_COLOR
	return label

func _lose_title(condition: MissionRules.LoseCondition) -> String:
	return String(MissionRules.LoseCondition.keys()[condition]).capitalize()

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
