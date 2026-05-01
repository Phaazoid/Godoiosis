extends Panel

@onready var name_label: Label = $StatsMargin/StatsVBox/HeaderHBox/NameLabel
@onready var hp_label: Label = $StatsMargin/StatsVBox/HeaderHBox/HPLabel

var unit: Unit
@onready var stats_container = $StatsMargin/StatsVBox/StatsContainer

func _populate_stats():
	#Clear old rows
	for child in stats_container.get_children():
		child.queue_free()
	
	var stats := unit.get_all_stats()
	var stat_names := stats.keys()
	
	for stat_name in stat_names:
		var name_label := Label.new()
		name_label.text = stat_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var value_label := Label.new()
		value_label.text = str(stats[stat_name])
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if stat_name != "MHP":
			stats_container.add_child((name_label))
			stats_container.add_child(value_label)
		
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
	hp_label.text = str(unit.get_current_hp(), "/", unit.get_base_stat("MHP"))
	_populate_stats()
	
func _on_hp_changed(current, max):
	hp_label.text = str(current, "/", max)
	
	
	# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
