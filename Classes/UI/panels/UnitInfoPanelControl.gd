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

func _ready() -> void:
	$UnitInfoPanel/Margin/VBox/HeaderRow/CloseButton.pressed.connect(clear)

func set_unit(unit: Unit, can_act := false):
	if current_unit == unit:
		return
	if unit == null:
		clear()
		return
	current_unit = unit
	visible = true
	name_label.text = unit.get_unit_name()
	jobs_label.text = _jobs_text(unit)
	portrait_panel.set_unit(unit)
	stats_section.set_unit(unit)
	inventory_panel.set_unit(unit, can_act)
	squad_panel.set_unit(unit)
	states_bar.set_unit(unit)

func clear():
	current_unit = null
	visible = false
	portrait_panel.set_unit(null)
	stats_section.set_unit(null)
	inventory_panel.set_unit(null)
	squad_panel.set_unit(null)
	states_bar.set_unit(null)

func is_showing() -> bool:
	return visible and current_unit != null

func is_showing_unit(unit: Unit) -> bool:
	return visible and current_unit == unit

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
