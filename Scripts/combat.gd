extends Node
class_name Combat_Component

@export var max_hp: int = 10
@export var attack: int = 5
@export var range: int = 1
@export var can_counter: bool = true


var current_hp: int

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	current_hp = max_hp

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func can_attack(attacker: Unit, target: Unit) -> bool:
	if attacker == target:
		return false
	if not Team.is_enemy(attacker.faction, target.faction):
		return false
	return true
	
func get_range() -> int:
	return range

func apply_damage(damage: int) -> void:
	current_hp -= damage
	if current_hp <= 0:
		current_hp = 0
		get_parent().die()
