extends Control
class_name UnitInfoPanelControl

# Controller for the click-to-inspect panel (UnitInfoPanel.tscn) — a docked, full-height
# left column as of #68 (replaces the old flip-top/bottom popup). Owns show/hide + which
# unit is open, sets the header (name/jobs), and fans set_unit/clear out to the child
# sections so their signal hookups tear down together.

@onready var portrait_panel = $UnitInfoPanel/Margin/VBox/HeaderRow/PortraitPanel
@onready var name_label: Label = $UnitInfoPanel/Margin/VBox/HeaderRow/HeaderText/NameLabel
@onready var jobs_label: Label = $UnitInfoPanel/Margin/VBox/HeaderRow/HeaderText/JobsLabel
@onready var stats_section = $UnitInfoPanel/Margin/VBox/StatsSection
@onready var inventory_panel = $UnitInfoPanel/Margin/VBox/InventoryPanel
@onready var squad_panel = $UnitInfoPanel/Margin/VBox/SquadInfoPanel
@onready var states_bar = $UnitInfoPanel/Margin/VBox/UnitStatesBar

var current_unit: Unit
var current_board: BoardContext   # kept so a live refresh can recompute terrain-dependent DEF

# Hidden while a cinematic pass owns the frame (#722), and what the CONTENT rule last decided.
# `_content_shown` is exactly what `visible` meant before #722, which is why is_showing/
# is_showing_unit read it: a panel hidden for a cinematic has NOT let go of its unit, and
# HoverPresenter asks those two to decide where the hover card parks and whether it would be a
# second card for the same unit. Answering "no unit is open" there would move the card mid-pass.
var _hidden_for_playback := false
var _content_shown := false

func _ready() -> void:
	$UnitInfoPanel/Margin/VBox/HeaderRow/CloseButton.pressed.connect(clear)
	inventory_panel.loadout_changed.connect(_refresh_derived_rows)

func set_unit(unit: Unit, can_act := false, board: BoardContext = null):
	if current_unit == unit:
		return
	if unit == null:
		clear()
		return
	_release_current_unit()
	current_unit = unit
	current_board = board
	_content_shown = true
	_apply_visibility()
	name_label.text = unit.get_unit_name()
	jobs_label.text = _jobs_text(unit)
	portrait_panel.set_unit(unit)
	stats_section.set_unit(unit, board)
	inventory_panel.set_unit(unit, can_act)
	squad_panel.set_unit(unit)
	states_bar.set_unit(unit)
	unit.movement.movement_finished.connect(_refresh_derived_rows)

# Re-read only the derived numbers. set_unit early-returns on the same unit (it's called on every
# inspect), so a change made while the panel is OPEN would otherwise leave DEF and MOV showing
# their values from inspect time -- and re-inspecting cannot clear it. Two triggers, because two
# things move these numbers: a loadout edit, and ARRIVAL -- DEF's cover term is read at the unit's
# current cell, so walking on or off Cover changes it.
func _refresh_derived_rows():
	if current_unit == null:
		return
	stats_section.set_unit(current_unit, current_board)

# The panel outlives the units it shows. Guarded the way info_panel.set_unit guards its own
# teardown: a freed ref compares == null as TRUE (#149), so this skips instead of faulting.
func _release_current_unit() -> void:
	if current_unit != null and is_instance_valid(current_unit):
		current_unit.movement.movement_finished.disconnect(_refresh_derived_rows)

func clear():
	_release_current_unit()
	current_unit = null
	_content_shown = false
	_apply_visibility()
	portrait_panel.set_unit(null)
	stats_section.set_unit(null)
	inventory_panel.set_unit(null)
	squad_panel.set_unit(null)
	states_bar.set_unit(null)

# #722's one input.
func set_hidden_for_playback(hidden: bool) -> void:
	_hidden_for_playback = hidden
	_apply_visibility()

func _apply_visibility() -> void:
	visible = _content_shown and not _hidden_for_playback

func is_showing() -> bool:
	return _content_shown and current_unit != null

func is_showing_unit(unit: Unit) -> bool:
	return _content_shown and current_unit == unit

func panel_width() -> float:
	return $UnitInfoPanel.size.x

func _jobs_text(unit: Unit) -> String:
	# Always-reveal placeholder (#69: the real PER-gated enemy-job reveal needs a
	# "who's inspecting" concept that doesn't exist yet).
	var names: Array[String] = []
	for job_id in unit.unit_instance.jobs:
		var job := JobCatalog.get_job(job_id)
		if job != null:
			names.append(job.display_name)
	return ", ".join(names) if not names.is_empty() else "Jobless"
