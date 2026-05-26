extends Node2D


@onready var grid : TileMapLayer = $Grid
@onready var overlay: TileMapLayer = $Overlay
@onready var units_root: Node2D = $Units
@onready var turn_manager = $TurnManager
@onready var turn_banner = $TurnBanner
@onready var unit_info_panel: Control = $UILayer/UnitInfoPanelControl
@onready var hover_info_panel: Control = $UILayer/HoverInfoPanelControl
@onready var dev_overlay: CanvasLayer = $DevOverlay
@onready var overlay_manager: OverlayManager = $OverlayManager
@onready var squad_manager: SquadManager = $SquadManager
@onready var squad_action_queue_control: SquadActionQueueControl = $UILayer/SquadActionQueueControl
@onready var cursor_controller: CursorController = $CursorController
@onready var camera_controller: CameraController = $CameraController

signal hovered_cell_changed(cell: Vector2i, mouse_pos: Vector2i)
signal hovered_unit_changed(previous_unit: Unit, new_unit: Unit)

const TERRAIN_ICONS := {
	"grass" : preload("res://Art/Icons/TerrainIcons/grass.png"),
	"rock" : preload("res://Art/Icons/TerrainIcons/rock.png"),
	"mud" : preload("res://Art/Icons/TerrainIcons/mud.png"),
	"error" : preload("res://Art/Icons/ArrowIcons/ERROR.png")	
}

const OVERLAY_SOURCE := 0
const OVERLAY_DEFAULT_ATLAS := Vector2i(0, 0)
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
const GAME_MENU_INSPECT := 10
const GAME_MENU_EXECUTE_ORDERS := 11
#Can update this as we want things like icons, hover descriptions, etc for each menu item
const ACTION_DATA = {
	GAME_MENU_MOVE: {"name": "Move"},
	GAME_MENU_ATTACK: {"name" : "Attack"},
	GAME_MENU_CANCEL: {"name": "Cancel Plan"},
	GAME_MENU_WAIT: {"name": "Wait"},
	GAME_MENU_ENDTURN: {"name": "End Turn"},
	GAME_MENU_SQUADUP: {"name": "Squad Up"},
	GAME_MENU_JOINSQUAD: {"name": "Join Squad"},
	GAME_MENU_LEAVESQUAD: {"name": "Leave Squad"},
	GAME_MENU_DISBAND_SQUAD: {"name": "Disband Squad"},
	GAME_MENU_INSPECT: {"name": "Inspect"},
	GAME_MENU_EXECUTE_ORDERS: {"name": "Execute Orders"}
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
	hovered_cell_changed.connect(update_hover_visuals)
	turn_manager.connect("turn_started", _on_turn_started)
	squad_manager.squad_action_cancelled.connect(_on_unit_action_cancelled)
	squad_manager.squad_action_queued.connect(_on_unit_action_queued)
	squad_manager.squad_became_active.connect(_on_squad_became_active)
	squad_manager.squad_became_empty.connect(_on_squad_has_no_actions)
	hovered_unit_changed.connect(_on_hovered_unit_changed)
	hovered_unit_changed.connect(overlay_manager.on_hovered_unit_changed)
	#This is for mouse controlling camera, putting a pin in that for now
	#hovered_cell_changed.connect(camera_controller.on_hovered_cell_changed)

func _on_turn_started(phase):
	if phase == TurnManager.TurnPhase.PLAYER:
		turn_banner.show_label("Player Turn")
		start_player_turn()
	else:
		turn_banner.show_label("Enemy Turn")
		start_enemy_turn()
		
func _on_friendly_action_menu_pressed(action_id: int, unit: Unit) -> void:
	match action_id:
		GAME_MENU_MOVE:
			enter_move_mode(unit)
		GAME_MENU_ATTACK: #Attack
			enter_attack_mode(unit)
		GAME_MENU_CANCEL: #Cancel
			cancel_orders(unit)
			clear_selection()
		GAME_MENU_WAIT: #Wait
			squad_manager.set_has_acted(unit.squad, true)
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
			squad_manager.leave_squad(unit)
		GAME_MENU_INSPECT:
			unit_info_panel.set_unit(unit)
		GAME_MENU_EXECUTE_ORDERS:
			execute_orders(unit)

func execute_orders(unit):
	var squad = unit.squad
	
	if squad_manager.squad_has_invalid_actions(squad):
		#showfeedback
		for action in squad.action_queue:
			if not action.is_valid:
				action.actor.visuals.play_invalid_flash()
		return
		
	for action in unit.squad.action_queue.duplicate():
		if action.action_type == BaseAction.ActionType.MOVE:
			action.actor.movement.move_along_path(action.path)
			squad_manager.remove_action(squad, action)
	squad_manager.set_has_acted(squad, true)
	for member in squad.members:
		overlay_manager.clear_planned_path(member)
	clear_icons([OverlayIcon.IconType.CROWN, OverlayIcon.IconType.SQUADMEMBER, OverlayIcon.IconType.TARGET])
	
func sho_invalid_plan_feedback(squad: Squad):
	for action in squad.action_queue:
		if action.is_valid:
			continue
		
		if action.action_type == BaseAction.ActionType.MOVE:
			overlay_manager.play_invalid_path_feedback(action)
		if action.actor != null:
			action.actor.play_invalid_flash()

func cancel_orders(unit): #clears all actions for unit
	squad_manager.remove_actions_for_unit(unit)
	#if unit.is_leader():
	#	clip_invalid_squad_movement(unit)
		
func create_squad(unit: Unit):
	game_state = GameState.CREATING_SQUAD
	draw_create_squad(unit)
	#Draw simple range (value from LDR stat), highlight valid units
	
func enter_move_mode(unit: Unit):
	game_state = GameState.CHOOSING_MOVE
	#TODO - This is slightly intrusive?  Instead of always snapping to center, only snap when unit's move is off screen
	#or maybe to the squad leader?
	if unit.has_squad():
		draw_squad_leader_range(unit.squad, unit.squad.leader.get_queued_move_cell())
	overlay_manager.show_overlay(OverlayManager.OverlayType.MOVE, get_move_range(compute_move_range(unit), unit), OVERLAY_DEFAULT_ATLAS)
	if not unit.is_leader():
		var unreachable = compute_move_range(unit).squad_unreachable.keys()
		overlay_manager.show_overlay(OverlayManager.OverlayType.INVALIDMOVE, unreachable, OVERLAY_DEFAULT_ATLAS)

func enter_attack_mode(unit: Unit):
	game_state = GameState.ATTACK_TARGETING
	overlay_manager.show_overlay(OverlayManager.OverlayType.ATTACK, compute_basic_range(unit, unit.combat.get_range()), OVERLAY_DEFAULT_ATLAS)
		
func disband_squad(unit: Unit):
	squad_manager.delete_squad(unit.squad)
	
func join_squad_mode(unit: Unit):
	game_state = GameState.CHOOSING_SQUAD
	draw_joinable_squads(unit)

func try_attack(attacker: Unit, target: Unit, attack_range: Array) -> void:
	if target.movement.cell in attack_range:  #if the target is in range
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

func cell_has_planned_movement(cell: Vector2i):
	return overlay_manager.get_planned_destinations().has(cell)
			
func _input(event):
	if event.is_action_pressed("toggle_dev_overlay"):
		dev_overlay.visible = !dev_overlay.visible
		if dev_overlay.visible == true:
			game_state = GameState.DEV_MODE
		else:
			exit_current_mode()
			
func _unhandled_input(event):
	var mouse_world := get_global_mouse_position()
	if event is InputEventMouseButton and event.pressed:
		var clickedCell: Vector2i = grid.local_to_map(grid.to_local(mouse_world))
		var clickedUnit : Unit = get_unit_at_cell(clickedCell)
		var lastUnit = get_unit_at_cell(last_clicked_cell)

		#When you click a unit, select it
		#For now, controlling enemies is fine, for testing purposes.  But when enemy AI is brought in, will need to not allow player to control enemy. 
		
		if event.button_index == MOUSE_BUTTON_LEFT: #and turn_manager.is_player_turn():
			update_hover_visuals(clickedCell, get_viewport().get_mouse_position())
			match game_state:
				GameState.IDLE:
					last_clicked_cell = clickedCell
					game_state = GameState.TILE_SELECTED
					if clickedUnit != null:
						var menu_options = populate_action_menu(clickedCell)
						show_action_menu(event.global_position, menu_options, clickedUnit)
					else:
						show_action_menu(event.global_position,[GAME_MENU_ENDTURN], clickedUnit)
				GameState.CHOOSING_SQUAD:
					if clickedUnit != null:
						if can_join_squad(lastUnit, clickedUnit.squad):
							squad_manager.join_squad(lastUnit, clickedUnit.squad)
					exit_current_mode()
				GameState.CREATING_SQUAD:
					if clickedUnit != null and not clickedUnit.has_squad():
						if can_squad_up(clickedUnit, lastUnit.squad):
							#If that unit was already in a squad, visually show somehow?
							squad_manager.join_squad(clickedUnit, lastUnit.squad)
					exit_current_mode()
				#GameState.TILE_SELECTED:
					#"hoo hoo"
				GameState.CHOOSING_MOVE: 
					#This is checking if you're clicking on a valid tile
					if compute_move_range(lastUnit).reachable.keys().has(clickedCell):
						var path = reconstruct_path(compute_move_range(lastUnit).came_from, last_clicked_cell, clickedCell)
						var move = MoveAction.new()
						move.init(lastUnit, path, get_Terrain_icon_at_cell(path.back()))
						squad_manager.queue_action(lastUnit.squad, move)
						overlay_manager.show_planned_path(lastUnit, move)
						#if lastUnit.is_leader():
							#clip_invalid_projected_squad_movement(lastUnit)
					exit_current_mode()
					
				GameState.ATTACK_TARGETING:
					if lastUnit != null:
						var attack_range = compute_basic_range(lastUnit, lastUnit.combat.get_range())
						if clickedCell in attack_range and clickedUnit != null and clickedUnit.get_faction() != get_unit_at_cell(last_clicked_cell).get_faction():
							var attack = AttackAction.new()
							attack.init(lastUnit, clickedUnit, clickedCell, lastUnit.get_base_stat("STR"))
							squad_manager.queue_action(lastUnit.squad, attack)
							#try_attack(lastUnit, clickedUnit, compute_basic_range(lastUnit, lastUnit.combat.get_range()))
							#print("Unit at ", clickedUnit.movement.cell, " Tried to attack unit at ", targetedUnit.movement.cell)
					exit_current_mode() #will need different logic later.  Show enemy stats before trying attack, not exit back to idle after attack, etc
						
			
			update_selection_overlay()
			#print("Current Gamestate is " + GameState.keys()[game_state])
		#Right click deselects all
		if event.button_index == MOUSE_BUTTON_RIGHT and turn_manager.is_player_turn() and game_state != GameState.DEV_MODE:
			if game_state == GameState.CHOOSING_MOVE:
				overlay_manager.clear_planned_path(get_unit_at_cell(last_clicked_cell))
			exit_current_mode()
			#TODO Add close button to this panel
			unit_info_panel.clear()
			update_selection_overlay()
		
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_SPACE:
		camera_controller.center_on_position(mouse_world)
 
func populate_action_menu(cell: Vector2i) -> Array:
	#TODO Order these explicitly instead of just order added to array
	var options = []
	var unit = get_unit_at_cell(cell)
	
	if unit.squad.has_any_queued_actions() and unit.is_leader():
		options.append(GAME_MENU_EXECUTE_ORDERS)

	if not unit.has_move_queued() and not unit.squad.has_acted and not squad_manager.is_another_squad_active(unit.squad):
		options.append(GAME_MENU_MOVE)
		#Once Squad is active, squad state cannot change through actions
		if not squad_manager.active_squad == unit.squad:
			if can_create_any_squad(unit):
				options.append(GAME_MENU_SQUADUP)
			if can_join_any_squad(unit):
				options.append(GAME_MENU_JOINSQUAD)
			if unit.has_squad():
				options.append(GAME_MENU_LEAVESQUAD)
				if unit.squad.get_leader() == unit:
					options.append(GAME_MENU_DISBAND_SQUAD)

	if not unit.squad.unit_has_queued_actions(unit):
		options.append(GAME_MENU_ATTACK)
		options.append(GAME_MENU_WAIT)

	if unit != null:
		options.append(GAME_MENU_INSPECT)

	options.append(GAME_MENU_ENDTURN)
	
	if unit != null and unit.squad.unit_has_queued_actions(unit):
		options.append(GAME_MENU_CANCEL)
		
	return options
	
func clip_invalid_projected_squad_movement(unit: Unit):
	var squad = unit.squad	
	for member in squad.get_members():
		if not member.is_leader() and not squad.get_ldr_range_from_cell(squad.leader.get_queued_move_cell()).has(member.get_queued_move_cell()):
			squad_manager.remove_actions_for_unit(member)
			
func clip_invalid_squad_movement(unit: Unit):
	for member in unit.squad.get_members():
		if not member.is_leader() and not unit.squad.get_ldr_range_from_cell(unit.get_queued_move_cell()).has(member.get_queued_move_cell()):
			squad_manager.remove_actions_for_unit(member)

func can_create_any_squad(creating_unit: Unit) -> bool:
	if creating_unit.has_squad() or creating_unit.squad.has_acted:
		return false

	for unit in units_root.get_children():
		if can_squad_up(unit, creating_unit.squad):
			return true
	return false
	
func can_join_any_squad(joining_unit: Unit) -> bool:
	for unit in units_root.get_children():
		if can_join_squad(joining_unit, unit.squad)	and unit.squad.leader.has_squad() and not unit.squad.has_acted and not joining_unit.squad.has_acted:
			return true
	return false

func can_squad_up(joining_unit: Unit, squad: Squad) -> bool:
	var dist = GridUtils.manhattan_distance(joining_unit.movement.cell, squad.leader.movement.cell)
	if dist <= squad.get_max_range() and squad.leader.get_faction() == joining_unit.get_faction() and not joining_unit.has_squad() and not squad.get_members().has(joining_unit) and not joining_unit.squad.has_acted and not squad.has_acted:
		return true
	return false
	
func can_join_squad(unit: Unit, squad: Squad) -> bool:
	var dist = GridUtils.manhattan_distance(unit.movement.cell, squad.leader.movement.cell)
	if dist <= squad.get_max_range() and squad.leader.get_faction() == unit.get_faction() and not squad.get_members().has(unit) and squad.leader.has_squad() and not squad.has_acted and not unit.squad.has_acted:
		return true
	return false
	
func start_enemy_turn():
	game_state = GameState.BETWEEN_TURNS
	await get_tree().create_timer(1.0).timeout #later make small waits between each enemy movement. 
	game_state = GameState.IDLE
	squad_manager.reset_faction_actions(Team.Faction.ENEMY)

func start_player_turn():
	game_state = GameState.BETWEEN_TURNS
	await get_tree().create_timer(1.0).timeout #later make small waits between each enemy movement. 
	game_state = GameState.IDLE
	squad_manager.reset_faction_actions(Team.Faction.PLAYER)
	
func show_action_menu(pos: Vector2i, items: Array, unit: Unit):
	#TODO This should probably be it's own game state - IN_MENU or something.  
	#Can call an end menu function from the popup hide that calls update visuals instead.  
	#Right now, mouse icon changes while menu is up and you hover around, so a new state could be used to stop erratic behavoir like that
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
	controller.cancelled.connect(_on_action_menu_cancelled)

func _on_action_menu_cancelled(controller):
	update_hover_visuals(last_hovered_cell, get_viewport().get_mouse_position())

func exit_current_mode():
	overlay_manager.clear_hover_move_path()
	
	if squad_manager.active_squad != null:
		squad_manager.validate_squad_plan(squad_manager.active_squad)
		overlay_manager.redraw_planned_paths()
		squad_action_queue_control.show_squad_actions(squad_manager.active_squad)
	
	last_clicked_cell = Vector2i(-999, -999)
	clear_selection()
	
func clear_selection():	
	game_state = GameState.IDLE

	overlay.clear()
	overlay_manager.clear_all()
	if squad_manager.active_squad == null:
		overlay_manager.clear_squad_range()
	if squad_manager.active_squad == null:
		clear_icons([OverlayIcon.IconType.CROWN, OverlayIcon.IconType.SQUADMEMBER])

func clear_selection_controller(controller):
	clear_selection()

func update_selection_overlay():
	overlay.clear()
	
func spawn_unit(data: UnitData, pos: Vector2i) -> Unit:
	var unit = UnitFactory.create_unit(data, grid, pos)

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
		squad_manager.create_squad(unit)
		return unit
	return null
	
func _on_squad_became_active(squad: Squad, action: BaseAction):
	if squad.leader.has_squad():
		var icons_to_draw = {}
		draw_squad_leader_range(squad, squad.leader.get_queued_move_cell())
		icons_to_draw = get_squad_icons(squad.leader)
		for cell in icons_to_draw.keys():
			for icontype in icons_to_draw[cell]:
				overlay_manager.create_icon(cell, icontype)
	squad_action_queue_control.show_squad_actions(squad)

func draw_squad_leader_range(squad: Squad, cell: Vector2i):		
	overlay_manager.show_overlay(OverlayManager.OverlayType.SQUADRANGE, squad.get_ldr_range_from_cell(cell), OVERLAY_DEFAULT_ATLAS)

func _on_squad_has_no_actions(squad: Squad):
	overlay_manager.clear_squad_range()
	squad_action_queue_control.show_squad_actions(squad)
	
func _on_unit_action_cancelled(squad: Squad, unit: Unit, actiontype: BaseAction.ActionType):
	overlay_manager.clear_planned_path(unit)
	if squad_manager.active_squad == squad:
		overlay_manager.create_icon(unit.movement.cell, OverlayIcon.IconType.SQUADMEMBER)
		if unit.is_leader():
			overlay_manager.create_icon(unit.movement.cell, OverlayIcon.IconType.CROWN)

	if unit.is_leader():
		draw_squad_leader_range(squad, squad.leader.get_queued_move_cell())
	
	squad_manager.validate_squad_plan(squad)
	overlay_manager.redraw_planned_paths()
	squad_action_queue_control.show_squad_actions(squad)

func _on_unit_action_queued(squad: Squad, action: BaseAction):
	var unit = action.actor
	if squad_manager.active_squad == squad and unit.has_squad():
		draw_squad_leader_range(squad, squad.leader.get_queued_move_cell())
		overlay_manager.clear_target_icon_by_cell(unit.movement.cell, OverlayIcon.IconType.SQUADMEMBER)
	squad_manager.validate_squad_plan(squad)
	squad_action_queue_control.show_squad_actions(squad)

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
		if Team.is_enemy(unit.get_faction(), other.get_faction()): 
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
			frontier.append({ "cell": next, "cost": new_cost})
			
	#Filter the tiles in movement for other blockers (so far just allies)
	var reachable := {}
	var squad_unreachable := {}
	for cell in cost_so_far.keys():
		var other_unit := get_unit_at_cell(cell)

		#Gotta stay in the Leader's current movement range if they don't have a queued move  
		if not unit.is_leader() and not unit.squad.get_leader().has_move_queued() and GridUtils.manhattan_distance(cell, unit.squad.get_leader().movement.cell) > unit.movement.move_range:
			squad_unreachable[cell] = cost_so_far[cell]
			continue
			
		#If they do have a queued move, gotta stay in the *new* movement range
		if not unit.is_leader() and unit.squad.get_leader().has_move_queued() and GridUtils.manhattan_distance(cell, unit.squad.get_leader().get_queued_move_cell()) > unit.movement.move_range:
			squad_unreachable[cell] = cost_so_far[cell]
			continue
			
		# Cannot walk onto spaces with non-squad members (and even those are potentially invalid - check SquadManager)
		if other_unit != null and not unit.squad.get_members().has(other_unit):
			continue
		
		#Cannot move onto own tile
		if other_unit == unit:
			continue

		reachable[cell] = cost_so_far[cell]
		
	return {"reachable": reachable,
				"came_from": came_from,
				"squad_unreachable": squad_unreachable
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
	overlay_manager.clear_all()
	var units: Array[Vector2i] = []
	var cells: Array[Vector2i] = []
	for unit in units_root.get_children():
		if can_join_squad(joining_unit, unit.squad) and unit.is_leader():
			for cell in compute_basic_range(unit, unit.get_base_stat("LDR")):
				if get_unit_at_cell(cell) == null:
					cells.append(cell)
			units.append(unit.movement.cell)
	overlay_manager.show_overlay(OverlayManager.OverlayType.SQUAD, cells, OVERLAY_DEFAULT_ATLAS)
	for cell in units:
		overlay_manager.create_icon(cell, OverlayIcon.IconType.CROWN)
		overlay_manager.create_icon(cell, OverlayIcon.IconType.SQUADMEMBER)

func get_squadmates_icons(unit: Unit) -> Dictionary: #Ignores hovered unit
	overlay_manager.clear_all()
	var icons = {}
	for member in unit.squad.get_members():
		if member != unit and member != unit.squad.leader:
			icons[member.movement.cell] = [OverlayIcon.IconType.SQUADMEMBER]
		if member != unit and member == unit.squad.leader:
			icons[member.movement.cell] = [OverlayIcon.IconType.SQUADMEMBER, OverlayIcon.IconType.CROWN]
	return icons

func get_squad_icons(unit: Unit) -> Dictionary: #Ignores hovered unit
	overlay_manager.clear_all()
	var icons = {}
	for member in unit.squad.get_members():
		if member != unit.squad.leader:
			icons[member.movement.cell] = [OverlayIcon.IconType.SQUADMEMBER]
		if member == unit.squad.leader:
			icons[member.movement.cell] = [OverlayIcon.IconType.SQUADMEMBER, OverlayIcon.IconType.CROWN]
	return icons


func draw_create_squad(unit: Unit):
	overlay.clear()
	var cells: Array[Vector2i] = []
	for cell in compute_basic_range(unit, unit.get_base_stat("LDR")):
		if cell != unit.movement.cell:
			cells.append(cell)
		if get_unit_at_cell(cell) != null and can_squad_up(get_unit_at_cell(cell), unit.squad):
			overlay_manager.create_icon(cell, OverlayIcon.IconType.TARGET)
	overlay_manager.show_overlay(OverlayManager.OverlayType.SQUAD, cells, OVERLAY_DEFAULT_ATLAS)

func get_move_range(result: Dictionary, unit: Unit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in result.reachable.keys():
		if cell == unit.movement.cell:
			continue
		cells.append(cell)
	return cells
	
func reconstruct_path(came_from: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path : Array[Vector2i] = []
	var current := goal
	
	while current != start:
		path.push_front(current)
		current = came_from[current]
		
	path.push_front(start)
	return path

func spawn_test_units():
	var test_data_baddy := preload("res://Resources/BadGuy1.tres")
	var test_data_goody := preload("res://Resources/GoodGuy1.tres")
	
	var test_cells := [
		Vector2i(-1, -5)
	]
	for cell in test_cells:
		spawn_unit(test_data_goody, cell)
		
	var test_enemy : Unit = spawn_unit(test_data_baddy, Vector2i(4,4))
	var test_item : Item = preload("res://Resources/ChainSword.tres")
	test_enemy.add_item(test_item)

	var generic_stats: Dictionary[String, int] = { 
			"MHP" : 20,
			"STR" : 5,
			"LDR" : 5	
		}
	
	var data1 = UnitFactory.create_unit_data(generic_stats, "GoodGuy 2", Team.Faction.PLAYER)
	var data2 = UnitFactory.create_unit_data(generic_stats, "GoodGuyThree", Team.Faction.PLAYER)
	var data3 = UnitFactory.create_unit_data(generic_stats, "BaddyNumeroDos", Team.Faction.ENEMY)
	
	spawn_unit(data1, Vector2i(-6, -5))
	spawn_unit(data2, Vector2i(-8, -5))
	spawn_unit(data3, Vector2i(4, 6))

	#var test_ally : Unit = spawn_unit(Vector2i(4,5), Team.Faction.ALLY)
	#var test_other : Unit = spawn_unit(Vector2i(4,6), Team.Faction.OTHER)
	
func get_terrain_type_at_cell(cell:Vector2i) -> String:
	var data := grid.get_cell_tile_data(cell)
	
	if data == null:
		return "error"
		
	if data.has_custom_data("terrain_type"):
		return str(data.get_custom_data("terrain_type"))
		
	return "error"
	
func get_Terrain_icon_at_cell(cell: Vector2i) -> Texture2D:
	var terrain_type := get_terrain_type_at_cell(cell)
	
	if TERRAIN_ICONS.has(terrain_type):
		return TERRAIN_ICONS[terrain_type]
		
	return TERRAIN_ICONS["error"]
		
	
func update_hover_visuals(hoveredCell: Vector2i, mousepos: Vector2i):
	var hoveredUnit : Unit = get_unit_at_cell(hoveredCell)
	var tile_data: TileData = grid.get_cell_tile_data(hoveredCell)
	if tile_data == null:
		return  # outside the map
		
	var walkable: bool = true
	if tile_data.has_custom_data("walkable"): 
		walkable = tile_data.get_custom_data("walkable")
	
	#Create Dictionary of icons to draw
	#Clear all and redraw only this dictionary at the end 
	var icons_to_draw = {}
	
	if game_state == GameState.DEV_MODE:
		if not walkable or hoveredUnit != null:
			cursor_controller.set_state(CursorController.CursorState.INVALID)
		else:
			cursor_controller.set_state(CursorController.CursorState.DEFAULT)
		cursor_controller.set_cursor_pos(hoveredCell)
		dev_overlay.set_mousepos(hoveredCell)
		
	if game_state == GameState.IDLE: # and turn_manager.is_player_turn():
		#Always show selected tile and info for what you're hovering over
		if squad_manager.active_squad == null:
			clear_icons([OverlayIcon.IconType.CROWN, OverlayIcon.IconType.SQUADMEMBER, OverlayIcon.IconType.TARGET])
		cursor_controller.set_cursor_pos(hoveredCell)
		if hoveredUnit != null:
			overlay_manager.show_overlay(OverlayManager.OverlayType.MOVE, get_move_range(compute_move_range(hoveredUnit), hoveredUnit), OVERLAY_DEFAULT_ATLAS)
			hover_info_panel.set_unit(hoveredUnit)
			cursor_controller.set_state(CursorController.CursorState.TARGET)
			var unreachable = compute_move_range(hoveredUnit).squad_unreachable.keys()
			overlay_manager.show_overlay(OverlayManager.OverlayType.INVALIDMOVE, unreachable, OVERLAY_DEFAULT_ATLAS)

			if hoveredUnit.has_squad() and squad_manager.active_squad == null: #TODO later change this to muted colors if other squads are active
				icons_to_draw = get_squadmates_icons(hoveredUnit) #Have this add to the dictionary of icons. 
			#if hoveredUnit.has_squad():
			#	draw_squad_leader_range(hoveredUnit.squad) #TODO - implement selective tile map deletion
		else:
			hover_info_panel.clear()
			overlay_manager.clear_all()
			#overlay_manager.clear_squad_range()
			cursor_controller.set_state(CursorController.CursorState.DEFAULT)
	
	if game_state == GameState.TILE_SELECTED:
		cursor_controller.set_state(CursorController.CursorState.TARGET)
		cursor_controller.set_cursor_pos(last_clicked_cell)
		
	if game_state == GameState.CREATING_SQUAD: #TODO - perhaps better targeting on these - green over valid targets, red over invalid, etc
		cursor_controller.set_cursor_pos(hoveredCell)
	
	if game_state == GameState.CHOOSING_SQUAD:
		cursor_controller.set_cursor_pos(hoveredCell)
	
	if game_state == GameState.CHOOSING_MOVE:
		var unit = get_unit_at_cell(last_clicked_cell)
		overlay_manager.clear_hover_move_path()
		if unit.is_leader(): 
			overlay_manager.clear_squad_range()
		if unit.is_leader() and unit.has_squad() and compute_move_range(unit).reachable.keys().has(hoveredCell):
			draw_squad_leader_range(unit.squad, hoveredCell)
			
			overlay_manager.redraw_planned_paths()
		
		if compute_move_range(unit).reachable.keys().has(hoveredCell):
			cursor_controller.set_state(CursorController.CursorState.VALID)
			var path = reconstruct_path(compute_move_range(unit).came_from, last_clicked_cell, hoveredCell)
			var move = MoveAction.new()
			move.init(unit, path, get_Terrain_icon_at_cell(path.back()))
			
			squad_manager.validate_squad_plan_preview(unit.squad, move)
			
			overlay_manager.show_hover_move_path(move)
			overlay_manager.redraw_planned_paths()
			squad_action_queue_control.show_squad_actions(unit.squad)
		else:
			cursor_controller.set_state(CursorController.CursorState.INVALID)
		cursor_controller.set_cursor_pos(hoveredCell)

	for cell in icons_to_draw.keys():
		for icontype in icons_to_draw[cell]:
			overlay_manager.create_icon(cell, icontype)

func clear_icons(icons: Array[OverlayIcon.IconType]):
	overlay_manager.clear_icon_types(icons)
	
func _on_hovered_unit_changed(previous_unit: Unit, new_unit: Unit):
	if previous_unit != null and is_instance_valid(previous_unit):
		previous_unit.visuals.set_hovered(false)
	
	if new_unit != null and is_instance_valid(new_unit):
		new_unit.visuals.set_hovered(true)
		
func _process(_delta):
	var mouse_world: Vector2 = get_global_mouse_position()
	var hoveredCell: Vector2i = grid.local_to_map(grid.to_local(mouse_world))

	if hoveredCell == last_hovered_cell: #everything after this only gets called if you change what cell you're hovering
		return
		
	hovered_unit_changed.emit(get_unit_at_cell(last_hovered_cell), get_unit_at_cell(hoveredCell))
	hovered_cell_changed.emit(hoveredCell, get_viewport().get_mouse_position())
	last_hovered_cell = hoveredCell
