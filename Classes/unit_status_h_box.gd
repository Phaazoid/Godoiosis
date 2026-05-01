extends GridContainer
class_name UnitStatusUI

@onready var portrait_panel = $HBoxContainer/PortraitPanel
@onready var stats_panel = $HBoxContainer/StatsPanel
@onready var inventory_panel = $InventoryPanel
@onready var squad_panel = $SquadInfoPanel

var unit: Unit


func set_unit(target: Unit):
	unit = target
	portrait_panel.set_unit(unit)
	stats_panel.set_unit(unit)
	inventory_panel.set_unit(unit)
	squad_panel.set_unit(unit)
	

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
