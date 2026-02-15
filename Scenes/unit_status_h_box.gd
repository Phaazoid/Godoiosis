extends HBoxContainer
class_name UnitStatusUI

@onready var portrait_panel = $PortraitPanel
@onready var info_panel = $InfoPanel

var unit: Unit


func set_unit(target: Unit):
	unit = target
	portrait_panel.set_unit(unit)
	info_panel.set_unit(unit)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
