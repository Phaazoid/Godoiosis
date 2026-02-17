extends Panel

@onready var name_label: Label = $NameLabel
@onready var hp_label: Label = $HPLabel

var unit: Unit



func set_unit(target: Unit):
	#To prevent duplicate stacking.  
	if unit: 
		unit.unit_instance.hp_changed.disconnect(_on_hp_changed)
		unit.unit_instance.died.disconnect(_on_unit_died)
		
	unit = target
	
	
	if unit == null:
		name_label.text = ""
		hp_label.text = ""
		return
	
	unit.unit_instance.died.connect(_on_unit_died)
	unit.unit_instance.hp_changed.connect(_on_hp_changed)
	
	_refresh()
	
func _on_unit_died():
	hp_label.text = "DED X_X"


func _refresh():
	if unit == null:
		name_label.text = "ERROR"
		hp_label.text = "ERROR"
		return
	name_label.text = unit.unit_data.display_name
	hp_label.text = str(unit.get_current_hp(), "/", unit.get_stat("MHP"))
	
func _on_hp_changed(current, max):
	hp_label.text = str(current, "/", max)
	
	
	# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
