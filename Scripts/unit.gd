extends Node2D
class_name Unit

#This is a container for everything that is a unit on the map.  These only exist during combat. 
#These have different components (movement, combat) that allow them to work, and reference specific UnitInstances to get their data. 



#Core statas
@onready var combat: Combat_Component = $Combat_Component
@onready var movement: Movement_Component = $Movement_Component
@export var unit_data: UnitData

const MAX_INVENTORY_SIZE := 6 #Balance actual size later

var unit_instance: UnitInstance
var current_position: Vector2i
var selected := false #Not actually being used atm
var has_acted := false
var inventory : Array[Item] = []

#Ownership
@onready var faction: Team.Faction

func set_selected(value: bool) -> void:
	selected = value

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	if unit_data == null:
		push_error("Unit missing UnitData.")
		return

	unit_instance = UnitInstance.new()
	unit_instance.data = unit_data
	unit_instance.initialize()
	inventory.resize(MAX_INVENTORY_SIZE)
	
	unit_instance.died.connect(_on_instance_died)
	
	match faction:
		Team.Faction.PLAYER:
			modulate = Color.WHITE
		Team.Faction.ENEMY:
			modulate = Color(1, 0.6, 0.6)
		Team.Faction.ALLY:
			modulate = Color(0.6, 0.8, 1)
	
	
func add_item(item: Item) -> bool:
	for i in range (inventory.size()):
		if inventory[i] == null:
			inventory[i] = item
			return true
	return false
	
func remove_item(index: int):
	if index >= 0 and index < inventory.size():
		inventory[index] = null
		
func _on_instance_died():
	die()
			
func get_base_stat(stat: String) -> int:
	if unit_instance == null:
		return -1
	return unit_instance.get_base_stat(stat)
	
func get_effective_stat(stat: String) -> int:
	return get_base_stat(stat) + get_modifier(stat)
	
func get_modifier(stat: String) -> int:
	return unit_instance.modifiers.get(stat)

func get_current_hp() -> int:
	return unit_instance.get_current_hp()
	
func get_all_stats() -> Dictionary:
	var result := {}
	for stat in unit_data.base_stats.keys():
		result[stat] = get_base_stat(stat)
	return result

func get_faction() -> Team.Faction:
	return faction
			
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func die() -> void:
	queue_free()

func change_faction(new_faction: Team.Faction) -> void:
	faction = new_faction
