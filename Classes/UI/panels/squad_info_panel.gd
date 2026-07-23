extends PanelContainer

# Squad section of the inspect panel: size n/max, leader, members. (Rewritten in #68 — the
# old version's validity guard was inverted, so it showed "No Unit" for every real unit.)

@onready var squad_label: RichTextLabel = $MarginContainer/SquadLabel

var unit: Unit

func set_unit(new_unit: Unit):
	unit = new_unit
	_refresh()

func _refresh():
	if unit == null or not is_instance_valid(unit):
		squad_label.text = "No unit"
		return
	var squad := unit.squad
	var text := "Squad [color=gold]%d/%d[/color]\n" % [squad.get_members().size(), squad.max_size()]
	text += "Leader: [color=gold]%s[/color]" % squad.get_leader().get_unit_name()
	var others: Array[String] = []
	for member in squad.get_members():
		if member != squad.get_leader():
			others.append(member.get_unit_name())
	if not others.is_empty():
		text += "\nWith: %s" % ", ".join(others)
	squad_label.text = text
