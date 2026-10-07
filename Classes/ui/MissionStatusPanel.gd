extends Control
class_name MissionStatusPanel

# The mission-status HUD (#134) -- the first always-on element in the game viewport. One row per
# DECLARED objective, with its progress ("Capture -- 1/2 zones"). Shows the declared list ONLY --
# never an implied "kill everyone" line, because an authored objective is the only way to win
# (docs/design/missions.md).
#
# IT ALSO OWNS THE TOP-RIGHT STRIP: the build version stamp, and since #1051 the report sign beside
# it. Neither of those is mission status; both are always-on corner furniture, and one owner of
# that band is what stops a second node restating where the first one ends.
#
# A declared second REPRESENTATION of what the board's zone marks already show (Law #4):
# MissionState stays authoritative, this panel only draws what it is handed on refresh, and
# game.refresh_mission_status() is the one caller. Rules and counts are read off the mission,
# never re-derived here.
#
# THE ROWS THEMSELVES HAVE A SECOND READER since #740: the pre-mission contract shows the same
# briefing before the battle that this shows during it. `briefing` is that one builder -- a static,
# so the screen needs no panel instance -- and this file is the only place the wording, the ordering
# and the two headers live.
# A THIRD reader since #46: the headless Play API's board view prints the rows' text, so a driver
# reads a mission's progress in the words the player does.
#
# A ROW ABOUT A PLACE ANSWERS THE POINTER since #955 part 3, here and not in the briefing: Capture,
# Extract and Defend wear their zone's emblem, hovering one lights its zones on the board and a click
# glides the camera to the next of them. The panel and its containers still let clicks through; only
# those rows stop the mouse. Which control is under the pointer is RECONCILED every frame rather than
# followed by mouse_entered/exited, because every refresh rebuilds the rows and a freed row never says
# the pointer left it.

const CORNER_MARGIN := 8
const BUTTON_CLEARANCE := 44   # the End Turn button's reserved corner slot below us: 36 high + its 8 margin (#189)
# The top-right metadata strip: the build stamp, and since #1051 the report sign beside it. A
# tighter inset than CORNER_MARGIN because these are furniture rather than a panel, and the gap is
# the only spacing either one declares -- where the sign SITS is measured off the stamp, never
# restated as a number here.
const STRIP_INSET := 6
const HINT_GAP := 10

# The sign's own two facts: WHICH binding it names, and how it words it. The key itself is not
# here -- Controls.key_for_action fills that in from the registry.
const REPORT_ACTION := "report_bug"
const REPORT_HINT := "%s: Report a bug"   # PLACEHOLDER, like every line a player reads

const MET_COLOR := Color(0.55, 0.95, 0.55)
const PENDING_COLOR := Color(0.92, 0.92, 0.92)
const UNWINNABLE_COLOR := Color(1, 0.45, 0.35)   # the Scenario tab's warning colour
const INSTRUCTION_COLOR := Color(1, 0.87, 0.5)   # guidance, not a win condition -- its own colour lane

# The clock's urgency cue (#101, dev fork C: colour it, don't interrupt with a modal). `static var`
# rather than `const` because these are GameKnobs.CLASS_KNOBS rows -- a feel value gets a knob, and
# this panel is 2D UI so the node-property table cannot reach it.
static var URGENT_ROUNDS := 2               # rounds left at or below which the clock goes urgent
static var URGENT_COLOR := Color(1, 0.55, 0.3)

# A zone row's emblem and the box it shows while under the pointer (#955 part 3).
const EMBLEM_SIZE := 16
const EMBLEM_GAP := 4
const ROW_PAD := 3
const HOVER_BG := Color(1, 1, 1, 0.13)
const HOVER_BORDER := Color(1, 1, 1, 0.45)

# The pointer is on a zone row (MissionRules.NO_ZONE when it leaves), and a zone row was clicked.
signal zone_row_hovered(kind: int)
signal zone_row_clicked(kind: int)

# Which zone kinds the board is drawing, pushed in by the game (OverlayManager.drawn_zone_kinds): a
# row answers only while there is something of its kind to light or visit.
var drawn_zone_kinds: Callable

var _hovered_kind := MissionRules.NO_ZONE


# One briefing row: its label, and the zone kind it is about (MissionRules.NO_ZONE for none).
class Row:
	var label: Label
	var zone_kind: int

	func _init(row_label: Label, kind: int) -> void:
		label = row_label
		zone_kind = kind


# A zone row as the HUD draws it: the emblem, then the label, in a box that shows the hover.
class ZoneRow extends PanelContainer:
	var zone_kind := MissionRules.NO_ZONE

@onready var _panel: PanelContainer = $ObjectivePanel
@onready var _rows: VBoxContainer = $ObjectivePanel/Rows
@onready var _version_label: Label = $VersionLabel
@onready var _report_hint: Label = $ReportHint

func _ready() -> void:
	z_index = UiLayers.MISSION_STATUS
	_panel.visible = false
	_version_label.text = "v" + Build.version()
	_version_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, STRIP_INSET)
	_build_report_hint()

# The objectives panel's own box, for the playback hint in the slot below it (#545), so the two
# corner panels share one look rather than two copies of it.
func panel_style() -> StyleBox:
	return _panel.get_theme_stylebox("panel")

# THE REPORT SIGN (#1051) -- a player is TOLD the key, not handed another button. The ticket was
# built once as a clickable mark and that was the wrong answer (dev, 2026-09-21): a fourth door to
# the same card left three of them undiscoverable and named none, where one line of text makes the
# cheapest door the one on screen. So it takes no input, and the case asserting that is the rule.
#
# It lives HERE rather than in a scene of its own because this panel already owns the top-right
# strip and already lays the stamp out in code. A second node reaching into that band needed a
# constant restating where the stamp ends, which is the duplicate-seam shape (Law #4) and is what
# the first build had.
#
# The key is READ FROM THE REGISTRY, never spelled: `tests/law/test_controls_coverage.gd` pins that
# registry against the live Input Map in both directions, so the sign cannot name a key the game
# does not have, and #691's rebinding lands on it for free.
#
# THE WORDING IS A PLACEHOLDER awaiting the dev, as all player-facing prose is his -- though this
# one he picked from three on 2026-09-21.
func _build_report_hint() -> void:
	var key := Controls.key_for_action(REPORT_ACTION)
	# Nothing documents the binding: say nothing rather than print ": Report a bug" at a player.
	# The coverage law reds long before a build gets here, so this is a floor, not a fix.
	_report_hint.visible = key != ""
	if not _report_hint.visible:
		return
	_report_hint.text = REPORT_HINT % key
	_report_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, STRIP_INSET)
	# Stepped left by the stamp's OWN measured width, so a longer version string pushes the sign
	# along instead of sliding under it. Pure post-preset translation, as the objective panel's is.
	var step := _version_label.get_combined_minimum_size().x + HINT_GAP
	_report_hint.offset_left -= step
	_report_hint.offset_right -= step

# No mission on this board (sandbox, cleared) -- nothing to say. The corner strip stays: the build
# stamp and the report sign are not mission status and never go down with the objective list.
func clear() -> void:
	_panel.visible = false
	_set_hovered(MissionRules.NO_ZONE)

# THE briefing, as a list of rows -- what the corner HUD draws during the battle and what the
# pre-mission contract draws before it (#740). ONE builder, because the two surfaces answer the
# same question and a second implementation would drift the moment a lose condition gains a
# readout: the SquadManager.contact_breaks split, one domain over. Each row names the zone kind it is
# about, off MissionRules' one pairing, so the HUD can make it answer the pointer (#955 part 3).
#
# Static, and every fact still comes off the mission -- this re-derives nothing.
static func briefing(mission: MissionState, board: BoardContext) -> Array[Row]:
	var rows: Array[Row] = []
	if not mission.objectives.is_empty():   # a lesson-only board has no OBJECTIVES header to earn
		rows.append(Row.new(_build_header("OBJECTIVES"), MissionRules.NO_ZONE))
	for objective in mission.objectives:
		rows.append(Row.new(_build_row(objective, mission, board),
				MissionRules.zone_kind_of_objective(objective)))
	# What LOSES it (#101), under its own header: a countdown listed among the objectives reads as
	# something to achieve. Driven off the declared list, so the next condition needs no edit here.
	if not mission.lose_conditions.is_empty():
		rows.append(Row.new(_build_header("FAIL IF"), MissionRules.NO_ZONE))
	for condition in mission.lose_conditions:
		rows.append(Row.new(_build_lose_row(condition, mission, board),
				MissionRules.zone_kind_of_lose(condition)))
	return rows

# The briefing as plain labels -- what the pre-mission contract draws, where nothing answers the
# pointer (the board is behind an opaque screen there; its Tab preview has this panel).
static func briefing_rows(mission: MissionState, board: BoardContext) -> Array[Label]:
	var labels: Array[Label] = []
	for row in briefing(mission, board):
		labels.append(row.label)
	return labels

func show_status(mission: MissionState, board: BoardContext, instruction := "") -> void:
	# Immediate free, not queue_free: the panel re-lays out from minimum size below, and a dying
	# child still counts toward it until end of frame.
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.free()
	for row in briefing(mission, board):
		if row.zone_kind == MissionRules.NO_ZONE:
			_rows.add_child(row.label)
		else:
			_rows.add_child(_zone_row(row))
	_paint_hover()
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

# A row about a place (#955 part 3): its zone's emblem in the kind's colour, then the label. The row
# itself stops the mouse; its children ignore it, so the viewport reports the row as the control under
# the pointer.
func _zone_row(row: Row) -> ZoneRow:
	var box := ZoneRow.new()
	box.zone_kind = row.zone_kind
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", EMBLEM_GAP)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var emblem := TextureRect.new()
	emblem.texture = ZoneMarks.emblem_of(row.zone_kind as ZoneManager.Kind)
	emblem.modulate = ZoneMarks.colour_of(row.zone_kind as ZoneManager.Kind)
	emblem.custom_minimum_size = Vector2(EMBLEM_SIZE, EMBLEM_SIZE)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(emblem)
	line.add_child(row.label)
	box.add_child(line)
	box.gui_input.connect(_on_zone_row_input.bind(box))
	return box


func _on_zone_row_input(event: InputEvent, box: ZoneRow) -> void:
	var press := event as InputEventMouseButton
	if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT:
		return
	box.accept_event()
	if _is_live(box.zone_kind):
		zone_row_clicked.emit(box.zone_kind)


# Whether the board is drawing any zone of this kind -- a claimed or unpainted objective keeps its
# emblem as a key but has nothing to light or visit.
func _is_live(kind: int) -> bool:
	if not drawn_zone_kinds.is_valid():
		return false
	var kinds: Array[int] = drawn_zone_kinds.call()
	return kinds.has(kind)


# The reconcile (see the header): which live zone row the pointer is on, asked of the viewport, so
# anything covering the panel covers the rows too. Right after a refresh the viewport holds no control
# until the pointer moves; the row under the pointer by position stands in until then, or every
# refresh during a pass would flicker the lit zones off.
func _process(_delta: float) -> void:
	var kind := MissionRules.NO_ZONE
	var over := get_viewport().gui_get_hovered_control()
	if over is ZoneRow and over.get_parent() == _rows:
		kind = (over as ZoneRow).zone_kind
	elif over == null:
		kind = _row_under_pointer()
	if not _is_live(kind):
		kind = MissionRules.NO_ZONE
	_set_hovered(kind)


func _row_under_pointer() -> int:
	if not _panel.visible:
		return MissionRules.NO_ZONE
	var at := get_global_mouse_position()
	for child in _rows.get_children():
		var box := child as ZoneRow
		if box != null and box.zone_kind == _hovered_kind and box.get_global_rect().has_point(at):
			return box.zone_kind
	return MissionRules.NO_ZONE


func _set_hovered(kind: int) -> void:
	if kind == _hovered_kind:
		return
	_hovered_kind = kind
	_paint_hover()
	zone_row_hovered.emit(kind)


func _paint_hover() -> void:
	for child in _rows.get_children():
		var box := child as ZoneRow
		if box != null:
			box.add_theme_stylebox_override("panel", _row_box(box.zone_kind == _hovered_kind))


static func _row_box(hovered: bool) -> StyleBox:
	var box := StyleBoxFlat.new()
	box.bg_color = HOVER_BG if hovered else Color(0, 0, 0, 0)
	box.border_color = HOVER_BORDER
	box.set_border_width_all(1 if hovered else 0)
	box.set_content_margin_all(ROW_PAD)
	return box


static func _build_header(text: String) -> Label:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 11)
	header.modulate = Color(1, 1, 1, 0.65)
	return header

# One declared lose condition. Rules and counts come off the mission, never re-derived here.
# Takes the board since #572: a protect row NAMES the units it is grading you on, and who is still
# standing is a board question -- the same argument _build_row has always needed.
static func _build_lose_row(condition: MissionRules.LoseCondition, mission: MissionState,
		board: BoardContext) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	# Declared with nothing to fire on -- the objectives' unpainted-geometry row, same doctrine: the
	# mission is broken and the row must say so rather than vanish.
	if mission.lose_conditions_missing_setup(board).has(condition):
		label.text = "%s — not set" % _lose_title(condition)
		label.modulate = UNWINNABLE_COLOR
		return label
	match condition:
		MissionRules.LoseCondition.ROUND_LIMIT:
			var left: int = mission.rounds_remaining()
			label.text = "Time — %d %s" % [left, "round left" if left == 1 else "rounds left"]
			label.modulate = URGENT_COLOR if left <= URGENT_ROUNDS else PENDING_COLOR
			return label
		MissionRules.LoseCondition.PROTECTED_UNIT_LOST:
			# NAMED, not counted (#572 fork D): "Protect" on a board with twelve units tells the
			# player nothing about which one they are being graded on.
			var names: Array[String] = []
			for unit in mission.protected_units(board):
				names.append(unit.get_unit_name())
			label.text = "Protect — %s" % ", ".join(names)
			label.modulate = PENDING_COLOR
			return label
		MissionRules.LoseCondition.POINT_LOST:
			# NAMED, not counted (#571): a defended point is a place on the board, and "Defend — 1
			# point" tells a player nothing about which one. Zone names are already authored to be
			# read ("South Bank", "Landing"), so they are the readout.
			label.text = "Defend — %s" % ", ".join(mission.defend_zone_names())
			label.modulate = PENDING_COLOR
			return label
	label.text = _lose_title(condition)
	label.modulate = PENDING_COLOR
	return label

static func _lose_title(condition: MissionRules.LoseCondition) -> String:
	return String(MissionRules.LoseCondition.keys()[condition]).capitalize()

static func _build_row(objective: MissionRules.Objective, mission: MissionState, board: BoardContext) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	# Declared but unpainted: the mission is unwinnable and the row must say so, never vanish
	# (canon -- silently dropping it would turn a broken map into a different, playable one).
	if mission.objectives_missing_geometry().has(objective):
		label.text = "%s — no zone painted" % _title(objective)
		label.modulate = UNWINNABLE_COLOR
		return label
	if mission.progress_for(objective, board) == MissionRules.Progress.MET:
		label.text = "✓ " + _title(objective)
		label.modulate = MET_COLOR
		return label
	match objective:
		MissionRules.Objective.ROUT:
			var left := MissionRules.active_hostile_count(board)
			label.text = "Rout — %d %s" % [left, "foe remains" if left == 1 else "foes remain"]
		MissionRules.Objective.CAPTURE:
			var captured: Vector2i = mission.capture_counts()
			label.text = "Capture — %d/%d zones" % [captured.x, captured.y]
		MissionRules.Objective.EXTRACT:
			var extracted: Vector2i = mission.extract_counts(board)
			label.text = "Extract — %d/%d in the zone" % [extracted.x, extracted.y]
		_:
			label.text = _title(objective)
	label.modulate = PENDING_COLOR
	return label

static func _title(objective: MissionRules.Objective) -> String:
	return String(MissionRules.Objective.keys()[objective]).capitalize()
