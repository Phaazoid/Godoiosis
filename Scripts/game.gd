extends Node2D


@onready var grid : TileMapLayer = $Grid
@onready var overlay: TileMapLayer = $Overlay
@onready var units_root: Node2D = $Units
@onready var friendly_action_menu: PopupMenu = $FriendlyUnitActionMenu
@onready var pause_menu :PopupMenu = $PauseMenu
@onready var turn_manager = $TurnManager
@onready var turn_banner = $TurnBanner
@export var unit_scene: PackedScene

const OVERLAY_SOURCE := 0
const OVERLAY_MOVE_ATLAS := Vector2i(4,0)
const OVERLAY_ATTACK_ATLAS := Vector2i(1,0)
const CANNOT_WALK_TILE := 99
const OUT_OF_MAP_TILE := 999

enum GameState {
	IDLE,
	UNIT_SELECTED,
	ATTACK_TARGETING,
	CHOOSING_MOVE	
}

var game_state: GameState = GameState.IDLE
var last_cell: Vector2i = Vector2i(-999, -999)
var selected_unit: Unit = null
var current_attack_range : Array[Vector2i] = []

func _ready() -> void:
	spawn_test_units()
	pause_menu.id_pressed.connect(_on_pause_menu_pressed)
	friendly_action_menu.id_pressed.connect(_on_friendly_action_menu_pressed)
	turn_manager.connect("turn_started", _on_turn_started)

func _on_turn_started(phase):
	if phase == TurnManager.TurnPhase.PLAYER:
		turn_banner.show_label("Player Turn")
		start_player_turn()
	else:
		turn_banner.show_label("Enemy Turn")
		start_enemy_turn()

func _on_friendly_action_menu_pressed(id: int) -> void:
	match id:
		0: #Move
			enter_move_mode()
		1: #Attack
			game_state = GameState.ATTACK_TARGETING
			compute_attack_range(selected_unit)
			draw_attack_range(current_attack_range)
		3: #Cancel
			clear_selection()
		4: #Wait
			selected_unit.has_acted = true
			
func _on_pause_menu_pressed(id: int) -> void:
	match id:
		1: #End Turn
			#print("Current Turn is " + TurnManager.TurnPhase.keys()[turn_manager.current_turn])
			turn_manager.end_turn()


func try_attack(attacker: Unit, target: Unit) -> void:
	if target.movement.cell in current_attack_range:  #if the target is in range
		target.combat.apply_damage(attacker.combat.attack)
		return

	if not attacker.combat.can_attack(attacker, target): #if the target is valid
		return

func is_walkable(cell: Vector2i) -> bool:
	var tile_data: TileData =grid.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	return tile_data.get_custom_data("walkable")	
	
func get_unit_at_cell(cell: Vector2i) -> Unit:
	for unit in units_root.get_children():
		if unit.movement.cell == cell:
			return unit
	return null

func _unhandled_input(event):
	if selected_unit != null and selected_unit.movement.moving: #Should probably change this to a gamestate enum thing
		return
	if event is InputEventMouseButton and event.pressed:
		var mouse_world := get_global_mouse_position()
		var clickedCell: Vector2i = grid.local_to_map(grid.to_local(mouse_world))
		var otherCell := grid.local_to_map(grid.to_local(get_global_mouse_position())) #not sure if this is the same as above, GPT wanted it for moverangeselection checking
		var clickedUnit : Unit = get_unit_at_cell(clickedCell)
		
		#When you click a unit, select it
		if event.button_index == MOUSE_BUTTON_LEFT and turn_manager.is_player_turn():
			match game_state:
				GameState.IDLE:
					if selected_unit != clickedUnit and clickedUnit != null:
						selected_unit = clickedUnit
						game_state = GameState.UNIT_SELECTED
				GameState.UNIT_SELECTED:
					if selected_unit == clickedUnit and clickedUnit != null and can_select(clickedUnit) and not selected_unit.has_acted:
						show_action_menu(event.global_position)
					if selected_unit != clickedUnit and clickedUnit != null:
						selected_unit = clickedUnit
				GameState.CHOOSING_MOVE: 
					#Currently bugged, stays in this game state if same unit chosen, but selector field disappears
					if overlay.get_cell_source_id(otherCell) != -1:
						var result = compute_move_range(selected_unit)
						var path = reconstruct_path(result.came_from, selected_unit.movement.cell, otherCell)
						selected_unit.movement.move_along_path(path)
						exit_move_mode()
				GameState.ATTACK_TARGETING:
					#if overlay.get_cell_source_id(otherCell) != -1:
					var targetedUnit : Unit = get_unit_at_cell(otherCell)
					if targetedUnit != null:
						try_attack(selected_unit, targetedUnit)
						print("Unit at ", selected_unit.movement.cell, " Tried to attack unit at ", targetedUnit.movement.cell)
					exit_move_mode() #will need different logic later.  Show enemy stats before trying attack, not exit back to idle after attack, etc
						
			
			update_selection_overlay()
			#print("Current Gamestate is " + GameState.keys()[game_state])
		#Right click deselects all
		if event.button_index == MOUSE_BUTTON_RIGHT and turn_manager.is_player_turn():
			selected_unit = null
			game_state = GameState.IDLE
			update_selection_overlay()
			show_pause_menu(event.global_position)
		#if selected_unit != null:
			#print("Currently selected unit is unit at ", selected_unit.movement.cell)
		#else:
			#print("There is no currently selected unit")

func start_enemy_turn():
	await get_tree().create_timer(2.0).timeout #later make small waits between each enemy movement. 
	for unit in units_root.get_children():
		if unit.faction == Team.Faction.ENEMY:
			print("I am enemy") #do enemy actions here
		
	turn_manager.end_turn()
	
func start_player_turn():
	reset_player_units()
	
func reset_player_units():
	for unit in units_root.get_children():
		if unit.faction == Team.Faction.PLAYER:
			unit.has_acted = false

func show_action_menu(pos: Vector2i) -> void:
	friendly_action_menu.position = pos
	friendly_action_menu.popup()

func show_pause_menu(pos: Vector2i) -> void:
	pause_menu.position = pos
	pause_menu.popup()

func exit_move_mode() -> void:
	game_state = GameState.IDLE
	selected_unit = null
	overlay.clear()

func clear_selection() -> void:
		selected_unit = null
		game_state = GameState.IDLE
		overlay.clear
		
func can_select(unit: Unit) -> bool:
	if unit != null:
		return unit.faction == Team.Faction.PLAYER
	return false
		
		
func enter_move_mode() -> void:
	game_state = GameState.CHOOSING_MOVE
	friendly_action_menu.hide()
	draw_move_range(compute_move_range(selected_unit))


func update_selection_overlay():
	#Used for managing unit selection logic
	overlay.clear()
	if selected_unit == null:
		return
	overlay.set_cell(selected_unit.movement.cell, 0, Vector2i(2,0))
	
func spawn_unit(cell:Vector2i, faction: Team.Faction) -> Unit:
	var unit = unit_scene.instantiate()
	unit.faction = faction
	units_root.add_child(unit)
	unit.movement.set_grid(grid)
	unit.movement.set_cell(cell)
	
	return unit

func movement_cost(cell: Vector2i, unit: Unit) -> int:
	var data := grid.get_cell_tile_data(cell)
	if data == null:
		return OUT_OF_MAP_TILE
	if is_walkable(cell) == false:
		return CANNOT_WALK_TILE
	if not grid.get_used_rect().has_point(cell):
		return OUT_OF_MAP_TILE
		
	var cost : int = 0 #Base tile costs are stored in the Grid custom data
	
	#Terrain weight
	if data.has_custom_data("move_cost"):
		cost += data.get_custom_data("move_cost")
	
	#Cost for other things on tiles
	var other := get_unit_at_cell(cell)
	if other != null:
		if Team.is_enemy(unit.faction, other.faction): 
			return CANNOT_WALK_TILE #Can't move past enemies
			
	return cost
	
func compute_move_range(unit: Unit) -> Dictionary:
	var start := unit.movement.cell
	var max_cost := unit.movement.move_range
	
	var frontier := []
	var cost_so_far := {}
	var came_from := {}
	
	frontier.append({"cell": start, "cost": 0})
	cost_so_far[start] = 0
	came_from[start] = start
	
	while frontier.size() > 0:
		#pop the cheapest item
		frontier.sort_custom(func(a, b): return a.cost < b.cost)
		var current = frontier.pop_front()
		var current_cell : Vector2i = current.cell
		
		for dir in [
			Vector2i.UP,
			Vector2i.DOWN,
			Vector2i.LEFT,
			Vector2i.RIGHT 
		]:
			var next : Vector2i = current_cell + dir
			var move_cost : int = movement_cost(next, unit)
			
			if move_cost > 98: #CANNOT_WALK_TILE = 99.  This is bad, placeholder logic.  Fix later.  
				continue
			
			# Bounds check
			if not grid.get_used_rect().has_point(next):
				continue
				
			var new_cost : int = cost_so_far[current_cell] + move_cost
			if new_cost > max_cost:
				continue
				
			if cost_so_far.has(next) and new_cost >= cost_so_far[next]:
				continue
				
			
			cost_so_far[next] = new_cost
			came_from[next] = current_cell
			frontier.append({ "cell": next, "cost": new_cost })
		
	return {"costs": cost_so_far,
				"came_from": came_from
	}
	
func compute_attack_range(unit: Unit) -> void:
	var origin := unit.movement.cell
	var max_range := unit.combat.get_range()

	var results: Array[Vector2i] = []
	var frontier: Array[Vector2i] = [origin]
	var distance := { origin: 0 }

	while frontier.size() > 0:
		var current : Vector2i = frontier.pop_front()

		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next : Vector2i = current + dir

			#if not grid.is_cell_valid(next):
			#	continue

			var new_dist : int = distance[current] + 1
			if new_dist > max_range:
				continue

			if not distance.has(next):
				distance[next] = new_dist
				frontier.append(next)
				results.append(next)
				
	current_attack_range = results
			
func draw_move_range(result: Dictionary):
	overlay.clear()
	
	for cell in result.costs.keys():
		if cell == selected_unit.movement.cell:
			continue
		overlay.set_cell(cell, OVERLAY_SOURCE, OVERLAY_MOVE_ATLAS)
		
func draw_attack_range(cells: Array[Vector2i]):
	overlay.clear()
	for cell in cells:
		overlay.set_cell(cell, OVERLAY_SOURCE, OVERLAY_ATTACK_ATLAS)

func reconstruct_path(came_from: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path : Array[Vector2i] = []
	var current := goal
	
	while current != start:
		path.push_front(current)
		current = came_from[current]
		
	path.push_front(start)
	return path
	
	
func spawn_test_units() -> void:
	var test_cells := [
		Vector2i(3, 3),
		Vector2i(5, 3),
		Vector2i(7, 3),
		Vector2i(3, 6),
		Vector2i(5, 6),
	]
	for cell in test_cells:
		spawn_unit(cell, Team.Faction.PLAYER)
		
	var test_enemy : Unit = spawn_unit(Vector2i(4,4), Team.Faction.ENEMY)
	var test_ally : Unit = spawn_unit(Vector2i(4,5), Team.Faction.ALLY)
	var test_other : Unit = spawn_unit(Vector2i(4,6), Team.Faction.OTHER)


func _process(_delta):
	var mouse_world: Vector2 = get_global_mouse_position()
	var cell: Vector2i = grid.local_to_map(grid.to_local(mouse_world))

	if cell == last_cell:
		return

	last_cell = cell
	#overlay.clear()

	var tile_data: TileData = grid.get_cell_tile_data(cell)
	if tile_data == null:
		return  # outside the map
		
	var walkable: bool = true
	if tile_data.has_custom_data("walkable"):
		walkable = tile_data.get_custom_data("walkable")

	var atlas_coords := Vector2i(0,0)
	if not walkable:
		atlas_coords = Vector2i(1,0)
		#This was for testing cell hovering and walkability.  
	#overlay.set_cell(cell, 0, atlas_coords)
