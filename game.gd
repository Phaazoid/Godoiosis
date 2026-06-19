extends Node2D

@onready var grid : TileMapLayer = $Grid
@onready var overlay: TileMapLayer = $Overlay
@onready var units_root: Node2D = $Units
@onready var turn_manager = $TurnManager
@onready var turn_banner = $TurnBanner
@onready var unit_info_panel: Control = $UILayer/UnitInfoPanelControl
@onready var hover_info_panel: Control = $UILayer/HoverInfoPanelControl
@onready var dev_overlay: DevOverlay = get_node("/root/Main/DevOverlay")
@onready var overlay_manager: OverlayManager = $OverlayManager
@onready var squad_manager: SquadManager = $SquadManager
@onready var squad_action_queue_control: SquadActionQueueControl = $UILayer/SquadActionQueueControl
@onready var cursor_controller: CursorController = $CursorController
@onready var camera_controller: CameraController = $CameraController

signal hovered_cell_changed(cell: Vector2i, mouse_pos: Vector2i)
signal hovered_unit_changed(previous_unit: Unit, new_unit: Unit)

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
	GAME_MENU_CANCEL: {"name": "Cancel Actions"},
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
var brush_painting := false

func _ready() -> void:
	
	RenderingServer.viewport_set_default_canvas_item_texture_filter(get_viewport().get_viewport_rid(), RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
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

func can_control(unit: Unit) -> bool:
	if unit == null:
		return false
	if game_state == GameState.DEV_MODE:
		return true
	return unit.get_faction() == turn_manager.active_faction()
		
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
			end_turn()
		GAME_MENU_SQUADUP: 
			create_squad(unit)
		GAME_MENU_JOINSQUAD:
			join_squad_mode(unit)
		GAME_MENU_DISBAND_SQUAD:
			disband_squad(unit)
		GAME_MENU_LEAVESQUAD:
			squad_manager.leave_squad(unit)
		GAME_MENU_INSPECT:
			unit_info_panel.set_unit(unit, can_control(unit))
		GAME_MENU_EXECUTE_ORDERS:
			execute_orders(unit)

func end_turn():
	clear_selection()
	update_selection_overlay()
	unit_info_panel.clear()
	turn_manager.end_turn()

func execute_orders(unit):
	var squad = unit.squad
	
	squad_manager.validate_squad_plan(squad)
	overlay_manager.redraw_planned_paths()
	refresh_action_queue(squad)
	
	if squad_manager.squad_has_invalid_actions(squad):
		for action in squad.action_queue:
			if not action.is_valid:
				action.actor.visuals.play_invalid_flash()
		return
		
	clear_icons([OverlayIcon.IconType.CROWN, OverlayIcon.IconType.SQUADMEMBER, OverlayIcon.IconType.TARGET])

	var plan := squad_manager.resolve_plan(squad)
	var move_actions := []

	for action in squad.action_queue.duplicate():
		action.actor.visuals.set_projected(false)
		if action.action_type == BaseAction.ActionType.MOVE:
			move_actions.append(action)

	await execute_action_phase_parallel(move_actions)
	await execute_action_sequence(plan.attacks)
	await execute_action_sequence(plan.counters)
	
	if not is_instance_valid(squad):
		return

	for action in squad.action_queue.duplicate():
		squad_manager.remove_action(squad, action)

	squad_manager.set_has_acted(squad, true)
	for member in squad.members:
		overlay_manager.clear_planned_path(member)

func execute_action_phase_parallel(actions: Array):
	if actions.is_empty():
		return
	
	for action in actions:
		action.begin_execution()
		
	for action in actions:
		action.execute()
		
	while true:
		var all_complete := true
		
		for action in actions:
			if not action.execution_complete:
				all_complete = false
				break
		if all_complete:
			return
			
		await get_tree().process_frame
	
func execute_action_sequence(actions: Array):
	if actions.is_empty():
		return

	for action in actions:
		action.begin_execution()
		action.execute()

		while not action.execution_complete:
			await get_tree().process_frame
	
func cancel_orders(unit): #clears all actions for unit
	squad_manager.remove_actions_for_unit(unit)
		
func create_squad(unit: Unit):
	game_state = GameState.CREATING_SQUAD
	draw_create_squad(unit)
	#Draw simple range (value from LDR stat), highlight valid units
	
func enter_move_mode(unit: Unit):
	game_state = GameState.CHOOSING_MOVE
	if unit.has_squad():
		draw_squad_leader_range(unit.squad, unit.squad.leader.get_projected_destination())
	overlay_manager.show_overlay(OverlayManager.OverlayType.MOVE, get_move_range(compute_move_range(unit), unit), OVERLAY_DEFAULT_ATLAS)
	if not unit.is_leader():
		var unreachable = compute_move_range(unit).squad_unreachable.keys()
		overlay_manager.show_overlay(OverlayManager.OverlayType.INVALIDMOVE, unreachable, OVERLAY_DEFAULT_ATLAS)

func enter_attack_mode(unit: Unit):
	game_state = GameState.ATTACK_TARGETING
	overlay_manager.show_overlay(OverlayManager.OverlayType.ATTACK, unit.combat.get_all_attack_cells_from(unit.get_projected_destination()), OVERLAY_DEFAULT_ATLAS)
	
func disband_squad(unit: Unit):
	squad_manager.disband_squad(unit.squad)
	
func join_squad_mode(unit: Unit):
	game_state = GameState.CHOOSING_SQUAD
	draw_joinable_squads(unit)

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
		if not dev_overlay.visible:
			dev_overlay.show_beside()
			set_dev_mode(true)
		else:
			set_dev_mode(game_state != GameState.DEV_MODE)

func set_dev_mode(active: bool):
	exit_current_mode()
	if active:
		game_state = GameState.DEV_MODE
	dev_overlay.sync_dev_mode_button(active)

func get_clicked_unit(cell: Vector2i) -> Unit:
	#Always hit the unit whose SPRITE is at this cell.
	#A projected "ghost" (an active-squad unit with a valid queued move landing here)
	#wins over a unit that physically sits here but has queued a valid move away from it.
	var projected := squad_manager.get_projected_unit_from_cell(cell)
	if projected != null:
		return projected
	var unit := get_unit_at_cell(cell)
	if unit != null and not unit.has_valid_move_queued():
		return unit
	return null

func _unhandled_input(event):
	if game_state == GameState.DEV_MODE and dev_overlay.tile_brush.brush_active:
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			_handle_tile_brush(event)
			return
			
	var mouse_world := get_global_mouse_position()
	if event is InputEventMouseButton and event.pressed:
		var clickedCell: Vector2i = grid.local_to_map(grid.to_local(mouse_world))
		var clickedUnit : Unit = get_unit_at_cell(clickedCell)
		var lastUnit = get_unit_at_cell(last_clicked_cell)
		var lastProjectedUnit = squad_manager.get_projected_unit_from_cell(last_clicked_cell)
		#When you click a unit, select it
		#For now, controlling enemies is fine, for testing purposes.  But when enemy AI is brought in, will need to not allow player to control enemy. 
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			update_hover_visuals(clickedCell, get_viewport().get_mouse_position())
			match game_state:
				GameState.IDLE:
					var target := get_clicked_unit(clickedCell)
					if target != null:
						last_clicked_cell = clickedCell
						game_state = GameState.TILE_SELECTED
						show_action_menu(event.global_position, populate_action_menu(target), target)
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
					if compute_move_range(lastUnit).reachable.keys().has(clickedCell) or compute_move_range(lastUnit).squad_unreachable.keys().has(clickedCell):
						var path = reconstruct_path(compute_move_range(lastUnit).came_from, last_clicked_cell, clickedCell)
						var move = MoveAction.new()
						move.init(lastUnit, path, GridUtils.get_terrain_icon_at_cell(grid, path.back()))
						squad_manager.queue_action(lastUnit.squad, move)
						overlay_manager.show_planned_path(lastUnit, move)
						if move.is_valid:
							overlay_manager.show_projected_unit(lastUnit, move.destination)
						#if lastUnit.is_leader():
							#clip_invalid_projected_squad_movement(lastUnit)
					exit_current_mode()
				GameState.DEV_MODE:
					if clickedUnit != null:
						dev_overlay.unit_editor.edit_unit(clickedUnit)
				GameState.ATTACK_TARGETING:
					if lastUnit != null or lastProjectedUnit != null:
						if lastUnit == null:
							lastUnit = lastProjectedUnit
						var origin = lastUnit.get_projected_destination()
						if lastUnit.combat.can_hit_cell_from(origin, clickedCell):
							var affected = lastUnit.combat.get_affected_cells_from(origin, clickedCell)
							var victims = gather_attack_victims(lastUnit, affected)
							if not victims.is_empty():
								for attack in AttackAction.create_volley(lastUnit, origin, clickedCell, victims):
									squad_manager.queue_action(lastUnit.squad, attack)
					exit_current_mode() #TODO will need different logic later.  Show enemy stats before trying attack, not exit back to idle after attack, etc
						
			
			update_selection_overlay()
		#Right click deselects all
		if event.button_index == MOUSE_BUTTON_RIGHT and game_state != GameState.DEV_MODE:
			if game_state == GameState.CHOOSING_MOVE:
				overlay_manager.clear_planned_path(get_unit_at_cell(last_clicked_cell))
			exit_current_mode()
			#TODO Add close button to this panel
			unit_info_panel.clear()
			update_selection_overlay()
		
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_SPACE:
		if game_state == GameState.DEV_MODE:
			dev_overlay.spawn.try_spawn_at(last_hovered_cell)
		else:
			camera_controller.center_on_position(mouse_world)
 
func populate_action_menu(unit: Unit) -> Array:
	#TODO Order these explicitly instead of just order added to array
	var options = []
	
	if not can_control(unit):
		options.append(GAME_MENU_INSPECT)
		if not squad_manager.any_squad_active():
			options.append(GAME_MENU_ENDTURN)
		return options
	
	if unit.squad.has_any_queued_actions() and unit.is_leader():
		options.append(GAME_MENU_EXECUTE_ORDERS)

	if not unit.has_action_type_queued(BaseAction.ActionType.MOVE) and not unit.squad.has_acted and not squad_manager.is_another_squad_active(unit.squad):
		options.append(GAME_MENU_MOVE)
		
	if not unit.has_action_type_queued(BaseAction.ActionType.ATTACK) and not unit.squad.has_acted and not squad_manager.is_another_squad_active(unit.squad) and unit.has_equipped_weapon():
		options.append(GAME_MENU_ATTACK)
		
		#Once Squad is active, squad state cannot change through actions
	if not unit.squad.has_any_queued_actions() and not unit.squad.has_acted and not squad_manager.any_squad_active():
		if can_create_any_squad(unit):
			options.append(GAME_MENU_SQUADUP)
		if can_join_any_squad(unit):
			options.append(GAME_MENU_JOINSQUAD)
		if unit.has_squad():
			options.append(GAME_MENU_LEAVESQUAD)
			if unit.squad.get_leader() == unit:
				options.append(GAME_MENU_DISBAND_SQUAD)

	if unit != null:
		options.append(GAME_MENU_INSPECT)
	
	if squad_manager.active_squad == null:
		options.append(GAME_MENU_WAIT)
		options.append(GAME_MENU_ENDTURN)
	
	if unit != null and unit.has_any_actions(): #TODO separate general cancel and cancel queued plans
		options.append(GAME_MENU_CANCEL)
		
	return options
	
func clip_invalid_projected_squad_movement(unit: Unit):
	var squad = unit.squad	
	for member in squad.get_members():
		if not member.is_leader() and not squad.get_ldr_range_from_cell(squad.leader.get_projected_destination()).has(member.get_projected_destination()):
			squad_manager.remove_actions_for_unit(member)
			
func clip_invalid_squad_movement(unit: Unit):
	for member in unit.squad.get_members():
		if not member.is_leader() and not unit.squad.get_ldr_range_from_cell(unit.get_projected_destination()).has(member.get_projected_destination()):
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
	if dist <= squad.get_max_range() and squad.leader.get_faction() == joining_unit.get_faction() and not joining_unit.has_squad() and not squad.get_members().has(joining_unit) and not joining_unit.squad.has_acted and squad.action_queue.is_empty() and not squad.has_acted and not joining_unit.has_any_actions():
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
		overlay_manager.redraw_projected_units()
		refresh_action_queue(squad_manager.active_squad)

	
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
	
func refresh_action_queue(squad: Squad) -> void:
	if squad == null:
		squad_action_queue_control.show_display_entries([])
		return
	var entries := squad_manager.get_display_entries_for_squad(squad)
	squad_action_queue_control.show_display_entries(entries)

	
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
		unit.unit_died.connect(_on_unit_died)
		return unit
	return null
	
func _on_unit_died(unit: Unit):
	overlay_manager.handle_unit_death(unit)
	squad_manager.handle_unit_death(unit)
	refresh_action_queue(squad_manager.active_squad)

	
func _on_squad_became_active(squad: Squad, action: BaseAction):
	if squad.leader.has_squad():
		var icons_to_draw = {}
		draw_squad_leader_range(squad, squad.leader.get_projected_destination())
		icons_to_draw = get_squad_icons(squad)
		for unit in icons_to_draw.keys():
			for icontype in icons_to_draw[unit]:
				overlay_manager.create_unit_icon(unit, icontype)
	squad_manager.setup_hold_move_actions(squad)
	refresh_action_queue(squad)


func draw_squad_leader_range(squad: Squad, cell: Vector2i):		
	overlay_manager.show_overlay(OverlayManager.OverlayType.SQUADRANGE, squad.get_ldr_range_from_cell(cell), OVERLAY_DEFAULT_ATLAS)

func _on_squad_has_no_actions(squad: Squad):
	overlay_manager.clear_squad_range()
	refresh_action_queue(squad)
	overlay_manager.redraw_squad_unit_icons(squad)

func _on_unit_action_cancelled(squad: Squad, unit: Unit, actiontype: BaseAction.ActionType):
	overlay_manager.clear_planned_path(unit)
	if squad_manager.active_squad == squad:
		overlay_manager.create_unit_icon(unit, OverlayIcon.IconType.SQUADMEMBER)
		if unit.is_leader():
			overlay_manager.create_unit_icon(unit, OverlayIcon.IconType.CROWN)

	if unit.is_leader():
		draw_squad_leader_range(squad, squad.leader.get_projected_destination())
		
	if actiontype == BaseAction.ActionType.MOVE:
		unit.visuals.set_projected(false)

	squad_manager.validate_squad_plan(squad)
	overlay_manager.redraw_planned_paths()
	overlay_manager.redraw_projected_units()
	refresh_action_queue(squad)
	overlay_manager.redraw_squad_unit_icons(squad)

func _on_unit_action_queued(squad: Squad, action: BaseAction):
	var unit = action.actor

	if action.action_type == BaseAction.ActionType.MOVE and action.is_valid and not action.is_hold_position:
		unit.visuals.set_projected(true)
	if squad_manager.active_squad == squad and unit.has_squad():
		draw_squad_leader_range(squad, squad.leader.get_projected_destination())
		overlay_manager.clear_target_icon_by_cell(unit.movement.cell, OverlayIcon.IconType.SQUADMEMBER)  
	squad_manager.validate_squad_plan(squad)
	refresh_action_queue(squad)

	if unit.has_squad():
		overlay_manager.redraw_squad_unit_icons(squad)

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
			
			if move_cost > CANNOT_WALK_TILE:  #TODO Later will need more values if some tiles can be walked over by some units (fliers) but some tiles can't be walked over by anything  
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

		#Members must stay within the leader's LDR range, measured from the leader's
		#projected destination (which falls back to their current cell if no move is queued)
		if not unit.is_leader() and GridUtils.manhattan_distance(cell, unit.squad.get_leader().get_projected_destination()) > unit.squad.get_max_range():
			squad_unreachable[cell] = cost_so_far[cell]
			continue
			
		# Cannot walk onto spaces with non-squad members (and even those are potentially invalid - check SquadManager)
		if other_unit != null and not unit.squad.get_members().has(other_unit):
			continue
		
		#Cannot move onto own tile
		if other_unit == unit:
			continue

		reachable[cell] = cost_so_far[cell]
		
	return {
		# reachable: { Vector2i cell : int movement_cost }
		# Cells this unit can legally select as movement destinations.
		"reachable": reachable,
		
		# came_from: { Vector2i cell : Vector2i previous_cell }
		# Used to reconstruct the path from the unit's start cell to a selected destination.
		"came_from": came_from,
		
		# squad_unreachable: { Vector2i cell : int movement_cost }
		# Cells physically reachable by this unit, but invalid because they fall outside
		# the squad leader's current/projected LDR range.
		"squad_unreachable": squad_unreachable
	}

#	"reachable": Dictionary[Vector2i, int],
#		# Cells this unit is allowed to select as movement destinations.
#		# Key = reachable cell.
#		# Value = total movement cost from the unit's start cell to that cell.
#
#	"came_from": Dictionary[Vector2i, Vector2i],
#		# Path reconstruction map for every cell found by the movement search.
#		# Key = discovered cell.
#		# Value = previous cell on the cheapest known path from start to that cell.
#		# Used by reconstruct_path(came_from, start, goal).
#
#	"squad_unreachable": Dictionary[Vector2i, int],
#		# Cells the unit could physically reach with its movement range,
#		# but cannot legally select because they fall outside the squad leader's LDR range.
#		# Key = physically reachable but squad-invalid cell.
#		# Value = total movement cost from the unit's start cell to that cell.
	
func draw_joinable_squads(joining_unit: Unit):
	overlay_manager.clear_all()
	var cells: Array[Vector2i] = []
	for unit in units_root.get_children():
		if can_join_squad(joining_unit, unit.squad) and unit.is_leader():
			for cell in GridUtils.cells_within_manhattan_range(unit.get_projected_destination(), unit.get_base_stat("LDR")):
				if get_unit_at_cell(cell) == null:
					cells.append(cell)
			overlay_manager.create_unit_icon(unit, OverlayIcon.IconType.CROWN)
			overlay_manager.create_unit_icon(unit, OverlayIcon.IconType.SQUADMEMBER)
	overlay_manager.show_overlay(OverlayManager.OverlayType.SQUAD, cells, OVERLAY_DEFAULT_ATLAS)

func get_squad_icons(squad: Squad) -> Dictionary: #Includes hovered unit
	var icons = {} # { Unit : Icon }
	for member in squad.get_members():
		if member != squad.leader:
			icons[member] = [OverlayIcon.IconType.SQUADMEMBER]
		if member == squad.leader:
			icons[member] = [OverlayIcon.IconType.SQUADMEMBER, OverlayIcon.IconType.CROWN]
	return icons

func draw_create_squad(unit: Unit):
	overlay.clear()
	var cells: Array[Vector2i] = []
	for cell in GridUtils.cells_within_manhattan_range(unit.get_projected_destination(), unit.get_base_stat("LDR")):
		var target_unit = get_unit_at_cell(cell)
		if cell != unit.movement.cell:
			cells.append(cell)
		if target_unit != null and can_squad_up(target_unit, unit.squad):
			overlay_manager.create_unit_icon(target_unit, OverlayIcon.IconType.TARGET)
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
	test_enemy.add_item(test_item.duplicate(true))

	var generic_stats := Stats.STAT_DEFAULTS.duplicate()
	
	var data1 = UnitFactory.create_unit_data(generic_stats, "GoodGuy 2", Team.Faction.PLAYER)
	var data2 = UnitFactory.create_unit_data(generic_stats, "GoodGuyThree", Team.Faction.PLAYER)
	var data3 = UnitFactory.create_unit_data(generic_stats, "BaddyNumeroDos", Team.Faction.ENEMY)
	
	spawn_unit(data1, Vector2i(-6, -5))
	spawn_unit(data2, Vector2i(-8, -5))
	spawn_unit(data3, Vector2i(4, 6))

func gather_attack_victims(attacker: Unit, affected_cells: Array[Vector2i]) -> Array[Unit]:
	var victims: Array[Unit] = []
	var weapon := attacker.get_equipped_weapon()
	var hits_allies: bool = weapon != null and weapon.hits_allies

	for cell in affected_cells:
		var unit := get_unit_at_cell(cell)
		if unit != null and unit.get_projected_destination() != cell:
			unit = null #occupant is planning to leave this cell; their projected cell is what counts
		if unit == null:
			unit = squad_manager.get_projected_unit_from_cell(cell)

		if unit == null or unit == attacker or victims.has(unit):
			continue

		if attacker.combat.can_attack(attacker, unit):
			victims.append(unit)
		elif hits_allies:
			victims.append(unit)

	return victims
	
func update_hover_visuals(hoveredCell: Vector2i, mousepos: Vector2i):
	var hoveredUnit : Unit = get_unit_at_cell(hoveredCell)
	var projectedHoveredUnit : Unit = squad_manager.get_projected_unit_from_cell(hoveredCell)
	if hoveredUnit != null and hoveredUnit.has_action_type_queued(BaseAction.ActionType.MOVE):
		hoveredUnit = null
	if projectedHoveredUnit != null:
		hoveredUnit = projectedHoveredUnit
	
	
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
		
	if game_state == GameState.IDLE: 
		#Always show selected tile and info for what you're hovering over
		cursor_controller.set_cursor_pos(hoveredCell)
		overlay_manager.clear_all()

		if hoveredUnit != null:
			
			if squad_manager.active_squad == null:
				clear_icons([OverlayIcon.IconType.CROWN, OverlayIcon.IconType.SQUADMEMBER, OverlayIcon.IconType.TARGET])
			
			if hoveredUnit.has_squad():
				draw_squad_leader_range(hoveredUnit.squad, hoveredUnit.squad.leader.get_projected_destination())

			overlay_manager.show_overlay(OverlayManager.OverlayType.MOVE, get_move_range(compute_move_range(hoveredUnit), hoveredUnit), OVERLAY_DEFAULT_ATLAS)
			hover_info_panel.set_unit(hoveredUnit)
			var unreachable = compute_move_range(hoveredUnit).squad_unreachable.keys()
			overlay_manager.show_overlay(OverlayManager.OverlayType.INVALIDMOVE, unreachable, OVERLAY_DEFAULT_ATLAS)
			if hoveredUnit.has_squad() and squad_manager.active_squad == null: #TODO later change this to muted colors if other squads are active
				icons_to_draw = get_squad_icons(hoveredUnit.squad) #Have this add to the dictionary of icons. 
		else:
			hover_info_panel.clear()
			overlay_manager.clear_all()
			cursor_controller.set_state(CursorController.CursorState.DEFAULT)
			if squad_manager.active_squad == null:
				clear_icons([OverlayIcon.IconType.CROWN, OverlayIcon.IconType.SQUADMEMBER, OverlayIcon.IconType.TARGET])

	
	if game_state == GameState.TILE_SELECTED:
		cursor_controller.set_state(CursorController.CursorState.TARGET)
		cursor_controller.set_cursor_pos(last_clicked_cell)
		
	if game_state == GameState.CREATING_SQUAD: #TODO - perhaps better targeting on these - green over valid targets, red over invalid, etc
		cursor_controller.set_cursor_pos(hoveredCell)
	
	if game_state == GameState.CHOOSING_SQUAD:
		cursor_controller.set_cursor_pos(hoveredCell)
	
	if game_state == GameState.ATTACK_TARGETING:
		var attacker: Unit = get_unit_at_cell(last_clicked_cell)
		if attacker == null:
			attacker = squad_manager.get_projected_unit_from_cell(last_clicked_cell)
		var preview_cells: Array[Vector2i] = []
		if attacker != null:
			var origin := attacker.get_projected_destination()
			if attacker.combat.can_hit_cell_from(origin, hoveredCell):
				preview_cells = attacker.combat.get_affected_cells_from(origin, hoveredCell)
		overlay_manager.show_overlay(OverlayManager.OverlayType.HOVER, preview_cells, OVERLAY_DEFAULT_ATLAS)

		if preview_cells.is_empty():
			cursor_controller.set_state(CursorController.CursorState.INVALID)
		else:
			cursor_controller.set_state(CursorController.CursorState.VALID)
		cursor_controller.set_cursor_pos(hoveredCell)		
	if game_state == GameState.CHOOSING_MOVE:
		var unit = get_unit_at_cell(last_clicked_cell)
		overlay_manager.clear_hover_move_path()
		if unit.is_leader(): 
			overlay_manager.clear_squad_range()
		if unit.is_leader() and unit.has_squad() and compute_move_range(unit).reachable.keys().has(hoveredCell):
			draw_squad_leader_range(unit.squad, hoveredCell)
			overlay_manager.redraw_planned_paths()
			overlay_manager.redraw_projected_units()
		if compute_move_range(unit).reachable.keys().has(hoveredCell) or compute_move_range(unit).squad_unreachable.keys().has(hoveredCell):
			cursor_controller.set_state(CursorController.CursorState.VALID)
			var path = reconstruct_path(compute_move_range(unit).came_from, last_clicked_cell, hoveredCell)
			var move = MoveAction.new()
			var squad = unit.squad
			move.init(unit, path,GridUtils.get_terrain_icon_at_cell(grid, path.back()))
			
			squad_manager.validate_squad_plan_preview(squad, move)
			
			overlay_manager.show_hover_move_path(move)
			#unit.visuals.set_projected(!move.is_valid)
			
			if unit.has_squad():
				overlay_manager.redraw_squad_unit_icons(squad)

			overlay_manager.redraw_planned_paths()
			overlay_manager.redraw_projected_units()
			refresh_action_queue(squad)
		else:
			cursor_controller.set_state(CursorController.CursorState.INVALID)
		cursor_controller.set_cursor_pos(hoveredCell)

	for unit in icons_to_draw.keys():
		for icontype in icons_to_draw[unit]:
			overlay_manager.create_unit_icon(unit, icontype)


func _handle_tile_brush(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			brush_painting = event.pressed
			if event.pressed:
				_paint_tile()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_erase_tile()
	elif event is InputEventMouseMotion and brush_painting:
		_paint_tile()

func _paint_tile():
	var cell = grid.local_to_map(grid.to_local(get_global_mouse_position()))
	grid.set_cell(cell, 0, dev_overlay.tile_brush.selected_tile)

func _erase_tile():
	var cell = grid.local_to_map(grid.to_local(get_global_mouse_position()))
	grid.erase_cell(cell)

func clear_icons(icons: Array[OverlayIcon.IconType]):
	overlay_manager.clear_unit_icon_types(icons)
	
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
