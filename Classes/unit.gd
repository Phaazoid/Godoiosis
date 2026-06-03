extends Node2D
class_name Unit

#This is a container for everything that is a unit on the map.  These only exist during combat. 
#These have different components (movement, combat) that allow them to work, and reference specific UnitInstances to get their data. 

#Core stats
@onready var combat: Combat_Component = $Combat_Component
@onready var movement: Movement_Component = $Movement_Component
@onready var map_sprite: Sprite2D = $MapSprite
@onready var move_sprite: Sprite2D = $MoveSprite
@onready var visuals: UnitVisuals = $UnitVisuals
@export var unit_data: UnitData

const MAX_INVENTORY_SIZE := 6 #Balance actual size later
const BASE_SPRITE_INDEX = 4

var unit_instance: UnitInstance
var selected := false #Not actually being used atm
var inventory : Array[Item] = []
var squad: Squad
var pending_grid : TileMapLayer
var pending_cell : Vector2i

func set_selected(value: bool):
	selected = value

func setup(grid : TileMapLayer, cell: Vector2i):
	pending_grid = grid
	pending_cell = cell

# Called when the node enters the scene tree for the first time.
func _ready():
	if unit_data == null:
		push_error("Unit missing UnitData.")
		return
	
	#This exists because node parent/child relations don't exist until node is added to a tree
	if pending_grid:
		movement.set_grid(pending_grid)
		movement.set_cell(pending_cell)

	unit_instance = UnitInstance.new()
	unit_instance.data = unit_data
	unit_instance.initialize()
	inventory.resize(MAX_INVENTORY_SIZE)
	unit_instance.died.connect(_on_instance_died)
	map_sprite.z_index = BASE_SPRITE_INDEX
	move_sprite.z_index = BASE_SPRITE_INDEX
	
	match unit_data.faction:
		Team.Faction.PLAYER:
			modulate = Color.WHITE
		Team.Faction.ENEMY:
			modulate = Color(1, 0.6, 0.6)
		Team.Faction.OTHER:
			modulate = Color(0.6, 0.8, 1)

func add_item(item: Item) -> bool:
	for i in range (inventory.size()):
		if inventory[i] == null:
			inventory[i] = item
			return true
	return false

func get_map_sprite_texture() -> Texture2D:
	if map_sprite == null:
		return null
	
	return map_sprite.texture 
	
func get_move_texture() -> Texture2D:
	if move_sprite == null:
		return null
	
	return move_sprite.texture
	
func get_unit_name() -> String:
	return unit_data.display_name

func reset_squad():
	var newSquad = Squad.new()
	newSquad.set_leader(self)
	squad = newSquad

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
	return unit_data.faction

func has_squad() -> bool:
	if squad.get_members().size() == 1:
		return false
	else:
		return true

func is_leader() -> bool:
	if squad.get_leader() == self:
		return true
	else:
		return false
	
func die() -> void:
	queue_free()

func change_faction(new_faction: Team.Faction):
	unit_data.faction = new_faction

func has_action_type_queued(actiontype: BaseAction.ActionType) -> bool:
	for action in squad.action_queue:
		if action.actor == self:
			if action.action_type == actiontype:
				if action.action_type == BaseAction.ActionType.MOVE and action.is_hold_position:  #treat hold moves like not having a move queued
					return false
				else:
					return true
	return false

func has_valid_move_queued() -> bool:
	if self.has_action_type_queued(BaseAction.ActionType.MOVE):
		var move = self.get_move_action()
		if move.is_valid:
			return true
	return false
	
func get_unit_actions() -> Array[BaseAction]:
	var actions = []
	for action in squad.get_actions():
		if action.actor == self:
			actions.append(action)
	return actions
	
func get_move_action() -> MoveAction:
	for action in squad.get_actions():
		if action.actor == self and action.action_type == BaseAction.ActionType.MOVE:
			return action
	return null
	
func has_any_actions() -> bool:
	for action in squad.get_actions():
		if action.actor == self:
			return true
	return false

func get_projected_destination() -> Vector2i:
	for action in squad.get_actions():
		if action.actor == self and action.action_type == BaseAction.ActionType.MOVE and action.is_valid:
			return action.get_destination()
	return self.movement.cell
