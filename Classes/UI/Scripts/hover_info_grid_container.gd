extends GridContainer

var unit: Unit
@onready var portrait_texture = $PortraitTexture
@onready var name_label = $NameLabel
@onready var hp_label = $HPLabel

	
func set_unit(target: Unit):
	#To prevent duplicate stacking.  
	if unit: 
		unit.unit_instance.hp_changed.disconnect(_on_hp_changed)
		unit.unit_instance.died.disconnect(_on_unit_died)
	unit = target
	
	if unit == null:
		name_label.text = ""
		hp_label.text = ""
		portrait_texture.texture = null

		return
	if unit.unit_data.portrait == null:
		portrait_texture.texture = load("res://Art/Units/Portraits/faceless_one.png")
	else:
		portrait_texture.texture = unit.unit_data.portrait
	
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
	hp_label.text = str(unit.get_current_hp(), "/", unit.get_base_stat("MHP"))
	
func _on_hp_changed(current, max):
	hp_label.text = str(current, "/", max)
