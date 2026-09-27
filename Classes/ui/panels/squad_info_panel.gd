extends PanelContainer

# Squad section of the inspect panel: size n/max, leader, members. (Rewritten in #68 — the
# old version's validity guard was inverted, so it showed "No Unit" for every real unit.)
# Text on paper in the player's palette (#1105): body ink, with the count and leader in the dock's
# one highlight colour.

@onready var squad_label: RichTextLabel = $MarginContainer/SquadLabel

var unit: Unit

func set_unit(new_unit: Unit):
	unit = new_unit
	_refresh()

func restyle() -> void:
	squad_label.add_theme_color_override("default_color", QueueStyle.ink(QueueStyle.Role.BODY_TEXT))
	_refresh()

func _refresh():
	if unit == null or not is_instance_valid(unit):
		squad_label.text = "No unit"
		return
	var squad := unit.squad
	var mark := "[color=#%s]" % QueueStyle.ink(QueueStyle.Role.EMPHASIS_TEXT).to_html(false)
	var text := "Squad %s%d/%d[/color]\n" % [mark, squad.get_members().size(), squad.max_size()]
	text += "Leader: %s%s[/color]" % [mark, squad.get_leader().get_unit_name()]
	var others: Array[String] = []
	for member in squad.get_members():
		if member != squad.get_leader():
			others.append(member.get_unit_name())
	if not others.is_empty():
		text += "\nWith: %s" % ", ".join(others)
	squad_label.text = text
