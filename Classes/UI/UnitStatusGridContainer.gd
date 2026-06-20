extends GridContainer
class_name UnitStatusGridContainer

@onready var portrait_panel = $HBoxContainer/PortraitPanel
@onready var stats_panel = $HBoxContainer/StatsPanel
@onready var inventory_panel = $InventoryPanel
@onready var squad_panel = $SquadInfoPanel

var unit: Unit


func set_unit(target: Unit, can_act := false):
	unit = target
	portrait_panel.set_unit(unit)
	stats_panel.set_unit(unit)
	inventory_panel.set_unit(unit, can_act)
	squad_panel.set_unit(unit)
