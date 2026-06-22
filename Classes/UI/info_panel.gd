extends Panel

@onready var name_label: Label = $StatsMargin/StatsVBox/HeaderHBox/NameLabel
@onready var hp_label: Label = $StatsMargin/StatsVBox/HeaderHBox/HPLabel

var unit: Unit
@onready var stats_container = $StatsMargin/StatsVBox/StatsContainer

func _populate_stats():
	# Clear old rows
	for child in stats_container.get_children():
		child.queue_free()

	var stats := unit.get_all_stats()
	var stat_names := stats.keys()

	for stat_name in stat_names:
		if stat_name == Stats.Stat.MHP:
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
	hp_label.text = str(unit.get_current_hp(), "/", unit.get_base_stat(Stats.Stat.MHP))
	_populate_stats()
	
func _on_hp_changed(current, max):
	hp_label.text = str(current, "/", max)
