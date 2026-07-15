extends Panel

@onready var name_label: Label = $StatsMargin/StatsVBox/HeaderHBox/NameLabel
@onready var hp_label: Label = $StatsMargin/StatsVBox/HPLabel
var unit: Unit
@onready var stats_container = $StatsMargin/StatsVBox/StatsContainer

func _populate_stats():
	# Clear old rows
	for child in stats_container.get_children():
		child.queue_free()

	var stats := unit.get_all_stats()
	var stat_names := stats.keys()

	for stat_name in stat_names:
		if stat_name == Stats.Stat.MHP or stat_name == Stats.Stat.WIL:
			continue
		var name_lbl := Label.new()
		name_lbl.text = Stats.Stat.keys()[stat_name]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var value_lbl := Label.new()
		value_lbl.text = str(stats[stat_name])
		value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stats_container.add_child(name_lbl)
		stats_container.add_child(value_lbl)

func set_unit(target: Unit):
	#To prevent duplicate stacking.  
	if unit != null and is_instance_valid(unit):
		unit.unit_instance.hp_changed.disconnect(_on_hp_changed)
		unit.unit_instance.died.disconnect(_on_unit_died)
		unit.unit_instance.will_changed.disconnect(_on_will_changed)
	unit = target
	
	if unit == null:
		name_label.text = ""
		hp_label.text = ""
		return
	
	unit.unit_instance.died.connect(_on_unit_died)
	unit.unit_instance.hp_changed.connect(_on_hp_changed)
	unit.unit_instance.will_changed.connect(_on_will_changed)
	
	_refresh()
	
func _on_unit_died():
	hp_label.text = "DED X_X"

func _refresh():
	if unit == null:
		name_label.text = "ERROR"
		hp_label.text = "ERROR"
		return
	name_label.text = unit.unit_data.display_name
	_refresh_hp()
	_populate_stats()

func _refresh_hp():
	if unit == null:
		return
	var text := str(unit.get_current_hp(), "/", unit.get_max_hp())
	text += "  WIL %d/%d" % [unit.unit_instance.get_current_will(), unit.unit_instance.get_max_will()]
	if unit.unit_instance.is_maimed():
		text += " [MAIMED]"
	if unit.in_crisis:
		text += " [CRISIS]"
	hp_label.text = text

func _on_hp_changed(_current, _max):
	_refresh_hp()

func _on_will_changed(_current, _max):
	_refresh_hp()
