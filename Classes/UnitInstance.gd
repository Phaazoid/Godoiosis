extends Resource
class_name UnitInstance

#This resource represents a runtime instance of a character.  This is where we will store persistent changes to units such as
#levels, stat changes, limb loss, weapon proficiency, job stats, etc. 

@export var data: UnitData
@export var level: int = 1

signal died
signal hp_changed(current, max)

#Permanent stat storage (base + growth gains, other permanent additions)
var stats: Dictionary = {}

#all buffs and debuffs from everything. Terrain, items, enemy attacks, etc. 
var stat_modifiers: Dictionary = {}

#Battle stats
var current_hp: int = 0
#effective str, other things here



func initialize():
	if data == null:
		push_error("UnitInstance has no UnitData assigned.")
		return
	#base current stats off of the data without editing the values in UnitData that we're pulling from
	stats = data.base_stats.duplicate(true) 
	
	#reset battle stats
	_refresh_derived_stats()
	current_hp = get_base_stat("MHP")

func level_up():
	#Basic level up function, that increments stats randomly from a range pulled from UnitData. 
	#This is a little too basic/similar to FE for my taste, but we haven't really decided on how we
	#want to handle stats and stat ups yet, so this is a placeholder that will be easy to edit later.  
	if data == null:
		return
	
	level += 1
	
	for stat_name in data.frowth_ranges:    
		var range: Vector2i = data.growth_ranges[stat_name]
		var gain = randi_range(range.x, range.y)
		
		if stats.has(stat_name):
			stats[stat_name] += gain
		else:
			stats[stat_name] = gain
		
		_refresh_derived_stats()
			
func initialize_at_level(target_level: int): 
	#for leveling up generic mook enemies on spawn
	initialize()
	
	for i in range(target_level - 1):
		level_up()
	current_hp = get_base_stat("MHP")

func get_base_stat(stat_name: String) -> int:
	if stats.has(stat_name):
		return stats[stat_name]
	return 0

func _refresh_derived_stats():
	#Placeholder for - 
	#item bonuses
	#job modifiers
	#debuffs
	#passives
	#literally anything that can change stats
	pass
	
func get_current_hp() -> int:
	return current_hp
	
func set_current_hp(value: int):
	current_hp = clamp(value, 0, get_base_stat("MHP"))
	emit_signal("hp_changed", current_hp, get_base_stat("MHP"))
	
	if current_hp <= 0:
		emit_signal("died")
	
func apply_damage(amount: int):
	set_current_hp(current_hp - amount)
		
	
func is_dead() -> bool:
	return current_hp <= 0
