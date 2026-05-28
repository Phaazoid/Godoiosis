extends Node
class_name Combat_Component

@export var range: int = 1 #doesn't make sense for this to be stored in the unit, will come from weapon, later.  
@export var can_counter: bool = true

#if this breaks because this instance is initialized before _ready() finishes setting up unit_instance, move initialization to _enter_tree()
#or call comabt_component.setup(self) after instance is created

# Called when the node enters the scene tree for the first time.
func _ready():
	var unit := owner as Unit
	if unit == null:
		push_error("Combat Component must be a child of a Unit")
		return

func can_attack(attacker: Unit, target: Unit) -> bool:
	if attacker == target:
		return false
	if not Team.is_enemy(attacker.faction, target.faction):
		return false
	return true
	
func get_range() -> int:
	return range

func apply_damage(damage: int):
	var unit := owner as Unit
	if unit == null:
		return
	unit.unit_instance.apply_damage(damage)
	
