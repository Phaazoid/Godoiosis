extends Control
class_name UnitInfoPanelControl

@onready var status_hbox = $UnitInfoPanel/UnitStatusHBox

var current_unit: Unit

func set_unit(unit: Unit):
	current_unit = unit

	if unit == null:
		visible = false
	else:
		visible = true
	
	status_hbox.set_unit(unit)
	
func clear():
	current_unit = null
	visible = false
	

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
