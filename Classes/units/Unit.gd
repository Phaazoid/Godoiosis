extends Node2D
class_name Unit

#This is a container for everything that is a unit on the map.  These only exist during combat. 
#These have different components (movement, combat) that allow them to work, and reference specific UnitInstances to get their data. 

#Core stats
@onready var combat: CombatComponent = $CombatComponent
@onready var movement: MovementComponent = $MovementComponent
@onready var map_sprite: Sprite2D = $MapSprite
@onready var move_sprite: Sprite2D = $MoveSprite
@onready var visuals: UnitVisuals = $UnitVisuals
@export var unit_data: UnitData

signal unit_died(unit: Unit)

const MAX_INVENTORY_SIZE := 6 #Balance actual size later
const BASE_SPRITE_INDEX = 4

var unit_instance: UnitInstance
var inventory : Array[Item] = []
var squad: Squad
var pending_grid : TileMapLayer
var pending_cell : Vector2i
var equipped_weapon: WeaponData = null
# Battle-scoped elemental states (boolean — you have it or you don't). These live on
# the transient Unit, NOT UnitInstance: they reset each mission, so the per-battle node
# owns them (resolution-pipeline.md persistence seam / elemental fork 3). The resolver
# threads a COPY of this set forward as a hypothetical; live mutation is execution-only.
var element_states: Array[Elemental.State] = []

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
	
	if unit_data.map_sprite != null:
		map_sprite.texture = unit_data.map_sprite
	if unit_data.move_sprite != null:
		move_sprite.texture = unit_data.move_sprite
	
	_apply_faction_visuals()

func add_item(item: Item) -> bool:
	for i in range(inventory.size()):
		if inventory[i] == null:
			inventory[i] = item

			if equipped_weapon == null and item is WeaponData:
				equipped_weapon = item

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

func remove_item(index: int):
	if index >= 0 and index < inventory.size():
		if inventory[index] == equipped_weapon:
			equipped_weapon = null

		inventory[index] = null
		
func _on_instance_died():
	die()

func get_base_stat(stat: Stats.Stat) -> int:
	if unit_instance == null:
		return -1
	return unit_instance.get_base_stat(stat)

func get_effective_stat(stat: Stats.Stat) -> int:
	return get_base_stat(stat) + get_modifier(stat)

func get_modifier(stat: Stats.Stat) -> int:
	return unit_instance.stat_modifiers.get(stat, 0)

func get_current_hp() -> int:
	return unit_instance.get_current_hp()

func has_element_state(state: Elemental.State) -> bool:
	return element_states.has(state)

func add_element_state(state: Elemental.State) -> void:
	if state == Elemental.State.NONE:
		return
	if not element_states.has(state):
		element_states.append(state)

func remove_element_state(state: Elemental.State) -> void:
	element_states.erase(state)

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
	
func die():
	unit_died.emit(self)
	queue_free()

func _apply_faction_visuals():
	match unit_data.faction:
		Team.Faction.PLAYER:
			modulate = Color.WHITE
		Team.Faction.ENEMY:
			modulate = Color(1, 0.6, 0.6)
		Team.Faction.OTHER:
			modulate = Color(0.6, 0.8, 1)
		_:
			modulate = Color.WHITE

func change_faction(new_faction: Team.Faction):
	unit_data.faction = new_faction
	_apply_faction_visuals()

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
	
func get_equipped_weapon() -> WeaponData:
	return equipped_weapon

func has_equipped_weapon() -> bool:
	return equipped_weapon != null

func set_equipped_weapon(weapon: WeaponData) -> bool:
	if weapon == null:
		equipped_weapon = null
		return true

	if not inventory.has(weapon):
		return false

	equipped_weapon = weapon
	return true

func equip_weapon_from_inventory(index: int) -> bool:
	if index < 0 or index >= inventory.size():
		return false

	var item := inventory[index]
	if item == null:
		return false

	if not item is WeaponData:
		return false

	equipped_weapon = item
	return true

func unequip_weapon():
	equipped_weapon = null
