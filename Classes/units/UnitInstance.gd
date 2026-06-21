extends Resource
class_name UnitInstance

#This resource represents a runtime instance of a character.  This is where we will store persistent changes to units such as
#stat changes, limb loss, weapon proficiency, job stats, etc. 

@export var data: UnitData

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
	current_hp = get_base_stat(Stats.Stat.MHP)

func get_base_stat(stat_name: Stats.Stat) -> int:
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
	current_hp = clamp(value, 0, get_base_stat(Stats.Stat.MHP))
	emit_signal("hp_changed", current_hp, get_base_stat(Stats.Stat.MHP))

	if current_hp <= 0:
		emit_signal("died")

func apply_damage(amount: int):
	set_current_hp(current_hp - amount)

func is_dead() -> bool:
	return current_hp <= 0
