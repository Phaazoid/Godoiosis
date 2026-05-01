extends Node2D


@onready var grid : TileMapLayer = $Grid
@onready var overlay: TileMapLayer = $Overlay
@onready var units_root: Node2D = $Units
@onready var pause_menu :PopupMenu = $PauseMenu
@onready var turn_manager = $TurnManager
@onready var turn_banner = $TurnBanner
@onready var unit_info_panel: Control = $UnitInfo/UnitInfoPanelControl
@onready var dev_overlay : CanvasLayer = $DevOverlay
@export var unit_scene: PackedScene

const OVERLAY_SOURCE := 0
const OVERLAY_MOVE_ATLAS := Vector2i(4,0)
const OVERLAY_ATTACK_ATLAS := Vector2i(1,0)
const OVERLAY_TARGET_ATLAS := Vector2i(3,0)
const OVERLAY_SQUAD_SELECT_ATLAS := Vector2i(5,0)
const OVERLAY_UNIT_IN_SQUAD_ATLAS := Vector2i(6, 0)
const CANNOT_WALK_TILE := 99
const OUT_OF_MAP_TILE := 999

const GAME_MENU_MOVE := 0
const GAME_MENU_ATTACK := 1
const GAME_MENU_OTHER := 2
const GAME_MENU_CANCEL := 3
const GAME_MENU_WAIT := 4
const GAME_MENU_ENDTURN := 5
const GAME_MENU_SQUADUP := 6
const GAME_MENU_JOINSQUAD := 7
const GAME_MENU_LEAVESQUAD := 8
const GAME_MENU_DISBAND_SQUAD := 9
#Can update this as we want things like icons, hover descriptions, etc for each menu item
const ACTION_DATA = {
	GAME_MENU_MOVE: {"name": "Move"},
	GAME_MENU_ATTACK: {"name" : "Attack"},
	GAME_MENU_CANCEL: {"name": "Cancel"},
	GAME_MENU_WAIT: {"name": "Wait"},
	GAME_MENU_ENDTURN: {"name": "End Turn"},
	GAME_MENU_SQUADUP: {"name": "Squad Up"},
	GAME_MENU_JOINSQUAD: {"name": "Join Squad"},
	GAME_MENU_LEAVESQUAD: {"name": "Leave Squad"},
	GAME_MENU_DISBAND_SQUAD: {"name": "Disband Squad"}
}

enum GameState {
	IDLE,
	TILE_SELECTED,
	ATTACK_TARGETING,
	CHOOSING_MOVE,
	CHOOSING_SQUAD,
	CREATING_SQUAD,
	BETWEEN_TURNS,
	DEV_MODE
}

var game_state: GameState = GameState.IDLE
var last_clicked_cell: Vector2i = Vector2i(-999, -999)
var last_hovered_cell: Vector2i = Vector2i(-999, -999)

func _ready() -> void:
	spawn_test_units()
	pause_menu.id_pressed.connect(_on_pause_menu_pressed)
	turn_manager.connect("turn_started", _on_turn_started)


func _on_turn_started(phase):
	if phase == TurnManager.TurnPhase.PLAYER:
		turn_banner.show_label("Player Turn")
		start_player_turn()
	else:
		turn_banner.show_label("Enemy Turn")
		start_enemy_turn()
		
		
func _on_friendly_action_menu_pressed(action_id: int, unit: Unit) -> void:
	#TODO Add an inspect option
	match action_id:
		GAME_MENU_MOVE:
			enter_move_mode(unit)
		GAME_MENU_ATTACK: #Attack
			enter_attack_mode(unit)
		GAME_MENU_CANCEL: #Cancel
			clear_selection()
		GAME_MENU_WAIT: #Wait
			unit.has_acted = true
			clear_selection()
		GAME_MENU_ENDTURN: #End Turn
			clear_selection()
			update_selection_overlay()
			turn_manager.end_turn()
		GAME_MENU_SQUADUP: 
			create_squad(unit)
		GAME_MENU_JOINSQUAD:
			join_squad_mode(unit)
		GAME_MENU_DISBAND_SQUAD:
			disband_squad(unit)
		GAME_MENU_LEAVESQUAD:
			unit.squad.remove_member(unit)
			

func _on_pause_menu_pressed(id: int) -> void:
	match id:
		1: #End Turn
			#print("Current Turn is " + TurnManager.TurnPhase.keys()[turn_manager.current_turn])
			turn_manager.end_turn()

func create_squad(unit: Unit):
	game_state = GameState.CREATING_SQUAD
	draw_create_squad(unit)
	#Draw simple range from LDR, highlight valid units
	
func enter_move_mode(unit: Unit):
	game_state = GameState.CHOOSING_MOVE
	draw_move_range(compute_move_range(unit), unit)
	
func enter_attack_mode(unit: Unit):
	game_state = GameState.ATTACK_TARGETING
	draw_attack_range(compute_basic_range(unit, unit.combat.get_range()))
		
func disband_squad(unit: Unit):
	unit.squad.reassign_leader()

func join_squad_mode(unit: Unit):
	game_state = GameState.CHOOSING_SQUAD
	draw_joinable_squads(unit)

func try_attack(attacker: Unit, target: Unit, range: Array) -> void:
	if target.movement.cell in range:  #if the target is in range
		target.combat.apply_damage(attacker.get_base_stat("STR"))
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

func _input(event):
	if event.is_action_pressed("toggle_dev_overlay"):
		dev_overlay.visible = !dev_overlay.visible
		if dev_overlay.visible == true:
			game_state = GameState.DEV_MODE
		else:
			exit_move_mode()
			

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		var mouse_world := get_global_mouse_position()
		var clickedCell: Vector2i = grid.local_to_map(grid.to_local(mouse_world))
		var otherCell := grid.local_to_map(grid.to_local(get_global_mouse_position())) #not sure if this is the same as above, GPT wanted it for moverangeselection checking
		var clickedUnit : Unit = get_unit_at_cell(clickedCell)
		var lastUnit = get_unit_at_cell(last_clicked_cell)

		#When you click a unit, select it
		#For now, controlling enemies is fine, for testing purposes.  But when enemy AI is brought in, will need to not allow player to control enemy. 
		
		if event.button_index == MOUSE_BUTTON_LEFT: #and turn_manager.is_player_turn():
			match game_state:
				GameState.IDLE:
					last_clicked_cell = clickedCell
					game_state = GameState.TILE_SELECTED
					if clickedUnit != null:
						var menu_options = get_available_menu_options(clickedUnit)
						show_action_menu(event.global_position, menu_options, clickedUnit)
					else:
						show_action_menu(event.global_position,[GAME_MENU_CANCEL,GAME_MENU_ENDTURN], clickedUnit)
				GameState.CHOOSING_SQUAD:
					if clickedUnit != null:
						if can_join_squad(lastUnit, clickedUnit.squad):
							join_squad(lastUnit, clickedUnit.squad)
					exit_move_mode()
				GameState.CREATING_SQUAD:
					if clickedUnit != null and not clickedUnit.has_squad():
						if can_squad_up(clickedUnit, lastUnit.squad):
							#If that unit was already in a squad, visually show somehow?
							join_squad(clickedUnit, lastUnit.squad)
					exit_move_mode()
				#GameState.TILE_SELECTED:
					#print("hoo hoo")
				GameState.CHOOSING_MOVE: 
					if overlay.get_cell_source_id(otherCell) != -1:
						var result = compute_move_range(lastUnit)
						var path = reconstruct_path(result.came_from, last_clicked_cell, otherCell)
						lastUnit.movement.move_along_path(path)
					exit_move_mode()
				GameState.ATTACK_TARGETING:
					if clickedUnit != null and clickedUnit.get_faction() != get_unit_at_cell(last_clicked_cell).get_faction():
						try_attack(lastUnit, clickedUnit, compute_basic_range(lastUnit, lastUnit.combat.get_range()))
						#print("Unit at ", clickedUnit.movement.cell, " Tried to attack unit at ", targetedUnit.movement.cell)
					exit_move_mode() #will need different logic later.  Show enemy stats before trying attack, not exit back to idle after attack, etc
						
			
			update_selection_overlay()
			#print("Current Gamestate is " + GameState.keys()[game_state])
		#Right click deselects all
		if event.button_index == MOUSE_BUTTON_RIGHT and turn_manager.is_player_turn() and game_state != GameState.DEV_MODE:
			clear_selection()
			game_state = GameState.IDLE
			update_selection_overlay()
			
func get_available_menu_options(unit: Unit) -> Array:
	var options = [GAME_MENU_ENDTURN, GAME_MENU_CANCEL]
	if not unit.has_acted:
		options.append(GAME_MENU_WAIT)
		options.append(GAME_MENU_ATTACK)
		options.append(GAME_MENU_MOVE)
		
	if can_create_any_squad(unit):
		options.append(GAME_MENU_SQUADUP)
	if can_join_any_squad(unit):
		options.append(GAME_MENU_JOINSQUAD)
	if unit.squad != null and unit.has_squad():
		if unit.squad.get_leader() == unit:
			options.append(GAME_MENU_DISBAND_SQUAD)
		else:
			options.append(GAME_MENU_LEAVESQUAD)	
	return options
	
func get_grid() -> TileMapLayer:
	return grid
	
func can_create_any_squad(creating_unit: Unit) -> bool:
	if creating_unit.has_squad():
		return false

	for unit in units_root.get_children():
		if can_squad_up(unit, creating_unit.squad):
			return true
	return false
	
func can_join_any_squad(joining_unit: Unit) -> bool:
	for unit in units_root.get_children():
		if can_join_squad(joining_unit, unit.squad)	and unit.squad.leader.has_squad():
			return true
	return false

func can_squad_up(joining_unit: Unit, squad: Squad) -> bool:
	var dist = joining_unit.movement.cell.distance_to(squad.leader.movement.cell)
	if dist <= squad.get_max_range() and squad.leader.faction == joining_unit.faction and not joining_unit.has_squad() and not squad.get_members().has(joining_unit):
		return true
	return false
	
func can_join_squad(unit: Unit, squad: Squad) -> bool:
	var dist = unit.movement.cell.distance_to(squad.leader.movement.cell)
	if dist <= squad.get_max_range() and squad.leader.faction == unit.faction and not squad.get_members().has(unit) and squad.leader.has_squad():
		return true
	return false
	
func join_squad(unit: Unit, squad: Squad):
	if unit.squad.get_leader() == unit and unit.squad.members.size() > 1:
		print("Are you sure you want to dissolve squad?")
		unit.squad.reassign_leader()
			
		#TODO if yes, have to resolve other squad dissolving.  currently just resets it entirely, but command can fall to second highest leadership unit in squad?
	squad.add_member(unit)
	#print("Squad now consists of ", squad.get_members())
	
	

func start_enemy_turn():
	game_state = GameState.BETWEEN_TURNS
	await get_tree().create_timer(2.0).timeout #later make small waits between each enemy movement. 
	game_state = GameState.IDLE
	#for unit in units_root.get_children():
		#if unit.faction == Team.Faction.ENEMY:
			#print("I am enemy") #do enemy actions here
		
	#turn_manager.end_turn()
	
func start_player_turn():
	game_state = GameState.BETWEEN_TURNS
	await get_tree().create_timer(2.0).timeout #later make small waits between each enemy movement. 
	game_state = GameState.IDLE
	reset_unit_actions()
	
func reset_unit_actions():
	for unit in units_root.get_children():
		#if unit.faction == Team.Faction.PLAYER:
			unit.has_acted = false

func show_action_menu(pos: Vector2i, items: Array, unit: Unit) -> void:
	var controller = ActionMenuController.new()
	controller.setup(unit)
	add_child(controller)
	
	controller.action_selected.connect(_on_friendly_action_menu_pressed)
	controller.cancelled.connect(clear_selection_controller)
	controller.local_menu.clear()
	for item in items:
		controller.local_menu.add_item(ACTION_DATA[item].name, item)
		
	controller.setpos(pos)
	controller.local_menu.popup()
	
func show_pause_menu(pos: Vector2i) -> void:
	pause_menu.position = pos
	pause_menu.popup()

func exit_move_mode() -> void:
	last_clicked_cell = Vector2i(-999, -999)
	clear_selection()


func clear_selection():
	game_state = GameState.IDLE
	overlay.clear
	
func clear_selection_controller(controller):
	game_state = GameState.IDLE
	overlay.clear
		
func can_select(unit: Unit) -> bool:
	if unit != null:
		return unit.faction == Team.Faction.PLAYER
	return false
		

func update_selection_overlay():
	#Used for managing unit selection logic
	overlay.clear()
	#if selected_unit == null:
		#return
	#overlay.set_cell(selected_unit.movement.cell, 0, Vector2i(2,0))
	
func spawn_unit_properly(unit: Unit):
	var cell = unit.pending_cell
	var tile_data: TileData = unit.pending_grid.get_cell_tile_data(unit.pending_cell)
	if tile_data == null:
		return  # outside the map
		
	var walkable: bool = true
	if tile_data.has_custom_data("walkable"):
		walkable = tile_data.get_custom_data("walkable")
		
	if get_unit_at_cell(unit.pending_cell) != null:
		walkable = false
		
	if walkable: #TODO later change this for various unit types, i.e. flyers can spawn on rocks, etc
		units_root.add_child(unit)

func spawn_unit(cell:Vector2i, faction: Team.Faction, data: UnitData) -> Unit:
	#TODO check for walkable, etc
	
	var unit: Unit = unit_scene.instantiate()
	unit.faction = faction
	unit.unit_data = data
	units_root.add_child(unit)
	unit.movement.set_grid(grid)
	unit.movement.set_cell(cell)	
		
	return unit
	
func create_unit_data(stats: Dictionary[String, int], name: String) -> UnitData:
	var data = UnitData.new()
	data.base_stats = stats
	data.display_name = name
	
	return data

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
			
	#Filter the tiles in movement for other blockers (so far just allies)
	var reachable := {}
	for cell in cost_so_far.keys():
		var other := get_unit_at_cell(cell)

		# Allow standing on your starting tile
		if cell == start:
			reachable[cell] = cost_so_far[cell]
			continue

		# Block ending on any occupied tile
		if other != null:
			continue

		reachable[cell] = cost_so_far[cell]
		
	return {"costs": reachable,
				"came_from": came_from
	}
	
func compute_basic_range(unit: Unit, range: int) -> Array:
	var origin := unit.movement.cell
	var max_range := range

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
				
	return results

func draw_joinable_squads(joining_unit: Unit):
	overlay.clear()
	for unit in units_root.get_children():
		if can_join_squad(joining_unit, unit.squad) and unit.is_leader():
			for cell in compute_basic_range(unit, unit.get_base_stat("LDR")):
				if get_unit_at_cell(cell) == null:
					overlay.set_cell(cell, OVERLAY_SOURCE, OVERLAY_SQUAD_SELECT_ATLAS)
			overlay.set_cell(unit.movement.cell, OVERLAY_SOURCE, OVERLAY_UNIT_IN_SQUAD_ATLAS)

func draw_squadmates(unit: Unit):
	for member in unit.squad.get_members():
		if member != unit and member != unit.squad.leader:
			overlay.set_cell(member.movement.cell, OVERLAY_SOURCE, OVERLAY_UNIT_IN_SQUAD_ATLAS)
		if member != unit and member == unit.squad.leader:
			overlay.set_cell(member.movement.cell, OVERLAY_SOURCE, OVERLAY_SQUAD_SELECT_ATLAS)



func draw_create_squad(unit: Unit):
	overlay.clear()
	for cell in compute_basic_range(unit, unit.get_base_stat("LDR")):
		if cell != unit.movement.cell:
			overlay.set_cell(cell, OVERLAY_SOURCE, OVERLAY_SQUAD_SELECT_ATLAS)
		if get_unit_at_cell(cell) != null and can_squad_up(get_unit_at_cell(cell), unit.squad):
			#print("My name is ", get_unit_at_cell(cell).get_unit_name(), " and it is ", get_unit_at_cell(cell).has_squad(), " that I'm in a squad")
			overlay.set_cell(cell, OVERLAY_SOURCE, OVERLAY_UNIT_IN_SQUAD_ATLAS)
	

func draw_move_range(result: Dictionary, unit: Unit):
	overlay.clear()
	
	for cell in result.costs.keys():
		if cell == unit.movement.cell:
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
	var test_data_baddy := preload("res://Resources/BadGuy1.tres")
	var test_data_goody := preload("res://Resources/GoodGuy1.tres")
	
	var test_cells := [
		Vector2i(-1, -5)
	]
	for cell in test_cells:
		spawn_unit(cell, Team.Faction.PLAYER, test_data_goody)
		
	var test_enemy : Unit = spawn_unit(Vector2i(4,4), Team.Faction.ENEMY, test_data_baddy)
	var test_item : Item = preload("res://Resources/ChainSword.tres")
	test_enemy.add_item(test_item)

	var generic_stats: Dictionary[String, int] = { 
			"MHP" : 20,
			"STR" : 5,
			"LDR" : 5	
		}
	
	var data1 = create_unit_data(generic_stats, "GoodGuy 2")
	var data2 = create_unit_data(generic_stats, "GoodGuyThree")
	var data3 = create_unit_data(generic_stats, "BaddyNumeroDos")
	
	spawn_unit(Vector2i(-5, -5), Team.Faction.PLAYER, data1)
	spawn_unit(Vector2i(-9, -5), Team.Faction.PLAYER, data2)
	spawn_unit(Vector2i(4, 6), Team.Faction.ENEMY, data3)

	#var test_ally : Unit = spawn_unit(Vector2i(4,5), Team.Faction.ALLY)
	#var test_other : Unit = spawn_unit(Vector2i(4,6), Team.Faction.OTHER)
	
func highlight_tile(gridpos: Vector2i) -> bool:
	overlay.clear()
	#TODO make sure this is in the actual grid.  will fail otherwise.  
	#return true or false based on tile data walkable, like in _process below
	overlay.set_cell(gridpos, OVERLAY_SOURCE, OVERLAY_TARGET_ATLAS)
	return true


func _process(_delta):
	var mouse_world: Vector2 = get_global_mouse_position()
	var hoveredCell: Vector2i = grid.local_to_map(grid.to_local(mouse_world))
	var hoveredUnit : Unit = get_unit_at_cell(hoveredCell)
	var tile_data: TileData = grid.get_cell_tile_data(hoveredCell)
	if tile_data == null:
		return  # outside the map
		
	var walkable: bool = true
	if tile_data.has_custom_data("walkable"): 
		walkable = tile_data.get_custom_data("walkable")

	if game_state == GameState.DEV_MODE:
		if not walkable:
			overlay.set_cell(hoveredCell, 0, OVERLAY_ATTACK_ATLAS)
		else:
			overlay.set_cell(hoveredCell, 0, OVERLAY_TARGET_ATLAS)
		dev_overlay.set_mousepos(hoveredCell)
		
	if game_state == GameState.IDLE: # and turn_manager.is_player_turn():
		#Always show selected tile and info for what you're hovering over
		if hoveredUnit != null:
			unit_info_panel.set_unit(hoveredUnit)
			overlay.set_cell(hoveredCell, 0, OVERLAY_TARGET_ATLAS)
			if hoveredUnit.has_squad():
				draw_squadmates(hoveredUnit)
		else:
			unit_info_panel.clear()
			overlay.set_cell(hoveredCell, 0, OVERLAY_MOVE_ATLAS)
	
	if game_state == GameState.TILE_SELECTED:
		overlay.set_cell(last_clicked_cell, 0, OVERLAY_TARGET_ATLAS)


	#if game_state == GameState.TILE_SELECTED:
	#No following overlay, flashing cursor on selected unit/tile
	
		

	if hoveredCell == last_hovered_cell:
		return

	last_hovered_cell = hoveredCell
	
	if game_state == GameState.DEV_MODE:
		overlay.clear()
	if game_state == GameState.IDLE:
		overlay.clear()
	
		


	#var atlas_coords := Vector2i(0,0)
	#if not walkable:
	#	atlas_coords = Vector2i(1,0)
		#This was for testing cell hovering and walkability.  
	#overlay.set_cell(cell, 0, atlas_coords)
