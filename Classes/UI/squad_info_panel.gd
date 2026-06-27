extends Panel

@onready var squad_label : RichTextLabel = $MarginContainer/SquadLabel

var unit: Unit


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	squad_label.bbcode_enabled = true
	_refresh()

func set_unit(new_unit: Unit):
	unit = new_unit
	_refresh()

func _refresh():
	if unit == null or is_instance_valid(unit):
		squad_label.text = "No Unit"
		return

	if unit.squad.get_members().size() == 1:
		squad_label.text = "No Squad"
		return
		
	var display_text = ""
		
	display_text += "Squad Leader: "
	display_text += "[color=gold]" + unit.squad.get_leader().get_unit_name() + "[/color]\n"
	display_text += "Squad Members: "
	for member in unit.squad.get_members():
		if member != unit.squad.get_leader():
			display_text += member.get_unit_name() + ", "

	squad_label.text = display_text
	
