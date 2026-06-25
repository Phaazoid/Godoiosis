extends GridContainer

var unit: Unit
@onready var portrait_texture = $PortraitTexture
@onready var name_label = $NameRow/NameLabel
@onready var states_row = $NameRow/StatesRow
@onready var hp_label = $HPLabel

func set_unit(target: Unit):
	if unit:
		unit.unit_instance.hp_changed.disconnect(_on_hp_changed)
		unit.unit_instance.died.disconnect(_on_unit_died)
		unit.downed_countdown_changed.disconnect(_on_countdown_changed)
	unit = target

	if unit == null:
		name_label.text = ""
		hp_label.text = ""
		portrait_texture.texture = null
		StateIcons.populate(states_row, [])
		return

	if unit.unit_data.portrait == null:
		portrait_texture.texture = load("res://Art/Units/Portraits/faceless_one.png")
	else:
		portrait_texture.texture = unit.unit_data.portrait

	unit.unit_instance.died.connect(_on_unit_died)
	unit.unit_instance.hp_changed.connect(_on_hp_changed)
	unit.downed_countdown_changed.connect(_on_countdown_changed)
	
	_refresh()

func _on_unit_died():
	hp_label.text = "DED X_X"

func _refresh():
	if unit == null:
		name_label.text = "ERROR"
		hp_label.text = "ERROR"
		return
	name_label.text = unit.unit_data.display_name
	StateIcons.populate(states_row, unit.element_states)
	_refresh_hp()

func _refresh_hp():
	if unit == null:
		return
	var text := str(unit.get_current_hp(), "/", unit.get_base_stat(Stats.Stat.MHP))
	if unit.is_downed() and unit.downed_turns_remaining > 0:
		text += "  (down: %d)" % unit.downed_turns_remaining
	hp_label.text = text

func _on_hp_changed(current, max):
	hp_label.text = str(current, "/", max)

func _on_countdown_changed(_turns: int):
	_refresh_hp()
