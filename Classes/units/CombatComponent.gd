extends Node
class_name CombatComponent

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
	if not Team.is_enemy(attacker.get_faction(), target.get_faction()):
		return false
	return true
	
func apply_damage(damage: int):
	var unit := owner as Unit
	if unit == null:
		return
	unit.take_damage(damage)
	
func get_attack_cells_from(origin_cell: Vector2i, target_hint_cell: Vector2i) -> Array[Vector2i]:
	var unit := owner as Unit
	var weapon := unit.get_equipped_weapon() if unit != null else null

	if weapon == null or weapon.attack_pattern == null:
		return GridUtils.cells_within_manhattan_range(origin_cell, 1)

	return weapon.attack_pattern.get_selectable_cells(unit, origin_cell, target_hint_cell)
	
func can_hit_cell_from(origin_cell: Vector2i, target_cell: Vector2i) -> bool:
	return get_attack_cells_from(origin_cell, target_cell).has(target_cell)
 #For now just using simple manhatten distance range. Will need to update with lists of cells most likely.  

func get_all_attack_cells_from(origin_cell: Vector2i) -> Array[Vector2i]:
	var unit := owner as Unit
	var weapon := unit.get_equipped_weapon() if unit != null else null

	if weapon == null or weapon.attack_pattern == null:
		return GridUtils.cells_within_manhattan_range(origin_cell, 1)

	return weapon.attack_pattern.get_all_selectable_cells(unit, origin_cell)
	
func get_affected_cells_from(origin_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	var unit := owner as Unit
	var weapon := unit.get_equipped_weapon() if unit != null else null

	if weapon == null or weapon.attack_pattern == null:
		return [target_cell]

	return weapon.attack_pattern.get_affected_cells(unit, origin_cell, target_cell)
	
# Does the equipped weapon aim by facing (forward line/wide) rather than at a specific cell?
# game.gd uses this so directional attacks can target a DIRECTION (the whole spread fires)
# instead of requiring the clicked cell to be a spread member. No pattern / no weapon = point.
func is_directional_attack() -> bool:
	var unit := owner as Unit
	var weapon := unit.get_equipped_weapon() if unit != null else null
	if weapon == null or weapon.attack_pattern == null:
		return false
	return weapon.attack_pattern.is_directional()
