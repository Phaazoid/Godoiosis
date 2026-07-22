extends Node2D

# Input/game-state coordinator — the root node of the game scene (game.tscn), instanced inside
# the GameView SubViewport (CLAUDE.md "Sharp edges"). Owns the GameState machine and routes
# clicks/hover into the right mode handler; PICKING_TARGET is the one generic "pick a
# highlighted unit" mode (rescue/intimidate/squad-up/join-squad all ride it via
# enter_target_pick_mode) — ATTACK_TARGETING and the CHOOSING_MOVE/GROUP_MOVE cell-pickers stay
# their own modes on purpose (see CLAUDE.md's Actions bullet). The seam most cross-system wiring
# (dev overlay, squad manager, turn manager) hangs off of. Known-overweight — prefer moving
# domain logic out into the owning system when touching it, not adding here.

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

enum GameState {
	IDLE,
	TILE_SELECTED,
	ATTACK_TARGETING,
	CHOOSING_MOVE,
	CHOOSING_GROUP_MOVE,
	BETWEEN_TURNS,
	DEV_MODE,
	PICKING_TARGET,
	AI_TURN
}

var game_state: GameState = GameState.IDLE
var last_clicked_cell: Vector2i = Vector2i(-999, -999)
var last_hovered_cell: Vector2i = Vector2i(-999, -999)
var _downed_pending: Array[Unit] = []   # units downed mid-execution; ejected after the pass (see _process_downed_pending)
var _highlighted_queue_units: Array[Unit] = []
var _target_pick_cells: Array[Vector2i] = []   # candidates while PICKING_TARGET
var _target_pick_callback: Callable            # func(picked: Unit) -> void
var dev_controller: DevController
var ai_controller: AIController
var terrain_states: TerrainStateManager
var zone_manager: ZoneManager
var main_action_menu: MainActionMenu

func _ready() -> void:
	dev_controller = DevController.new()
	dev_controller.game = self
	add_child(dev_controller)
	
	ai_controller = AIController.new()
	ai_controller.game = self
	add_child(ai_controller)
	
	terrain_states = TerrainStateManager.new()
	terrain_states.name = "TerrainStateManager"
	add_child(terrain_states)

	zone_manager = ZoneManager.new()
	zone_manager.name = "ZoneManager"
	add_child(zone_manager)
	
	main_action_menu = MainActionMenu.new()
	main_action_menu.game = self
	add_child(main_action_menu)
	
	RenderingServer.viewport_set_default_canvas_item_texture_filter(get_viewport().get_viewport_rid(), RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
	spawn_test_units()
	hovered_cell_changed.connect(update_hover_visuals)
	turn_manager.connect("turn_started", _on_turn_started)
	squad_manager.squad_action_cancelled.connect(_on_unit_action_cancelled)
	squad_manager.squad_action_queued.connect(_on_unit_action_queued)
	squad_manager.squad_became_active.connect(_on_squad_became_active)
	squad_manager.squad_became_empty.connect(_on_squad_has_no_actions)
	squad_action_queue_control.execute_requested.connect(_on_queue_execute_requested)
	squad_action_queue_control.cancel_requested.connect(_on_queue_cancel_requested)
	squad_action_queue_control.row_hover_changed.connect(_on_queue_row_hover_changed)
	squad_action_queue_control.reorder_attacks_requested.connect(_on_queue_reorder_attacks)
	hovered_unit_changed.connect(_on_hovered_unit_changed)
	turn_manager.round_completed.connect(_on_round_completed)
	hovered_unit_changed.connect(overlay_manager.on_hovered_unit_changed)
	camera_controller.refresh_bounds(grid)
	

func _on_turn_started(faction: Team.Faction):
	_tick_downed_countdowns(faction)
	_tick_crisis_surges(faction)
	# A faction with no commandable (active) units has nothing to do — its downed clocks already
	# ticked above, so pass straight to the next. Guard against an all-downed board, where skipping
	# would recurse with no faction left to stop on.
	var board := _board()
	if not board.faction_has_active_units(faction) and board.has_active_units():
		turn_manager.end_turn(board.present_factions())
		return
	turn_banner.show_label("%s Turn" % Team.faction_name(faction))
	start_faction_turn(faction)

# The board is fully hands-off for the player while an AI faction resolves its turn -- no
# selection, no menu, no queue-panel interaction (Execute/Cancel/reorder).
func _board_locked_for_player() -> bool:
	return game_state == GameState.AI_TURN

func can_control(unit: Unit) -> bool:
	if unit == null:
		return false
	if game_state == GameState.DEV_MODE:
		return true
	if not unit.is_active():        # downed/dead units can't be commanded (will-and-death.md)
		return false
	return unit.get_faction() == turn_manager.active_faction()
		
# Attack entry (#30 C, generalized #72): a rune with several channelable carvings, or a weapon
# with several stock attacks, opens a pick menu first; a single choice auto-selects. Reset first
# so a stale pick never leaks into a new aim.
func _begin_attack(unit: Unit) -> void:
	unit.active_attack = null
	var choices := unit.get_selectable_attacks()
	if choices.size() > 1:
		show_attack_menu(get_viewport().get_mouse_position(), choices, unit)
		return
	if not choices.is_empty():
		unit.active_attack = choices[0]
	enter_attack_mode(unit)

func show_attack_menu(pos: Vector2i, attacks: Array[AttackData], unit: Unit) -> void:
	var controller := ActionMenuController.new()
	add_child(controller)
	controller.setup(unit)

	# Synthetic items: index -> {name}, so the Control-based ActionMenuController (#26) renders the
	# attack list without a bespoke menu class. Works for either kind since display_name lives on
	# the shared AttackData base (#72). An unfireable pick (a sprung weapon, #73) stays LISTED but
	# disabled — Law #2: the menu shows an unready attack, never hides it.
	var items := []
	var data := {}
	for i in range(attacks.size()):
		items.append(i)
		var entry := { "name": attacks[i].display_name }
		if not unit.is_attack_fireable(attacks[i]):
			entry["disabled"] = true
			entry["tooltip"] = "Not ready — reload the weapon first"
		data[i] = entry

	controller.action_selected.connect(func(idx, picking_unit): _on_attack_picked(picking_unit, attacks[idx]))
	controller.cancelled.connect(clear_selection_controller)
	controller.cancelled.connect(_on_action_menu_cancelled)

	controller.populate(items, data)
	controller.setpos(pos)

func _on_attack_picked(unit: Unit, attack: AttackData) -> void:
	unit.active_attack = attack
	enter_attack_mode(unit)

func end_turn():
	await _apply_burning_tile_damage(turn_manager.active_faction())
	clear_selection()
	update_selection_overlay()
	unit_info_panel.clear()
	turn_manager.end_turn(_board().present_factions())

func _on_round_completed() -> void:
	terrain_states.tick_states()
	overlay_manager.redraw_terrain_live(terrain_states)

# End-of-phase burn: a unit standing in fire when ITS faction's turn ends takes damage. Routed
# through take_damage so downs/kills apply, then the crisis-offer + eject the attack pass uses.
func _apply_burning_tile_damage(faction: Team.Faction) -> void:
	for cell in terrain_states.cells_with(Terrain.TileState.BURNING):
		var unit := get_unit_at_cell(cell)
		if unit != null and unit.is_active() and unit.get_faction() == faction:
			unit.take_damage(Terrain.BURNING_TILE_DAMAGE)
	await _offer_pending_crisis()
	_process_downed_pending()

func queue_spring_load(unit: Unit):
	var spring_load := SpringLoadAction.new()
	spring_load.init(unit)
	squad_manager.queue_action(unit.squad, spring_load)
	clear_selection()

# Generic "pick one highlighted unit" mode (rescue, intimidate, future targeted actions):
# overlay the candidates' cells, hand the clicked unit to on_pick. Attack targeting stays
# its own mode — directional aiming doesn't fit this shape.
func enter_target_pick_mode(candidates: Array[Unit], on_pick: Callable) -> void:
	game_state = GameState.PICKING_TARGET
	_target_pick_cells = _unit_cells(candidates)
	_target_pick_callback = on_pick
	overlay_manager.show_overlay(OverlayManager.OverlayType.ATTACK, _target_pick_cells, OVERLAY_TARGET_ATLAS)

func _unit_cells(units: Array[Unit]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for unit in units:
		cells.append(unit.movement.cell)
	return cells

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

	var plan := squad_manager.resolve_plan(squad, _board())
	var move_actions := []
	var side_channel: Dictionary[BaseAction.ActionType, Array] = {}

	for action in squad.action_queue.duplicate():
		action.actor.visuals.set_projected(false)
		if action.action_type == BaseAction.ActionType.MOVE:
			move_actions.append(action)
		elif BaseAction.SIDE_CHANNEL_ORDER.has(action.action_type):
			if not side_channel.has(action.action_type):
				side_channel[action.action_type] = []
			side_channel[action.action_type].append(action)

	await execute_action_phase_parallel(move_actions)
	await execute_action_sequence(plan.attacks)
	_apply_cell_effects(plan.cell_effects)
	await execute_action_sequence(plan.counters)
	for type in BaseAction.SIDE_CHANNEL_ORDER:
		var batch: Array = side_channel.get(type, [])
		await execute_action_sequence(batch)
	_process_downed_pending()

	if not is_instance_valid(squad):
		return

	for action in squad.action_queue.duplicate():
		squad_manager.remove_action(squad, action)

	squad_manager.set_has_acted(squad, true)
	for member in squad.members:
		overlay_manager.clear_planned_path(member)

func enter_group_move_mode(unit: Unit):
	game_state = GameState.CHOOSING_GROUP_MOVE
	if unit.has_squad():
		draw_squad_leader_range(unit.squad, unit.squad.leader.get_projected_destination())
	# Pick the squad's destination from the leader's own reachable tiles.
	overlay_manager.show_overlay(OverlayManager.OverlayType.MOVE, get_move_range(compute_move_range(unit), unit), OVERLAY_DEFAULT_ATLAS)

func _on_queue_execute_requested():
	if _board_locked_for_player():
		return
	var squad := squad_manager.active_squad
	if squad == null:
		return
	execute_orders(squad.get_leader())

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

# Play the resolved terrain deposits into the live store, then redraw the board (#50). Runs after
# the attack phase that produced them. Burning-only for now; generalizes as more tile states land.
func _apply_cell_effects(cell_effects: Array[ResolvedCellEffect]) -> void:
	for effect in cell_effects:
		terrain_states.apply(effect)
	overlay_manager.redraw_terrain_live(terrain_states)

func execute_action_sequence(actions: Array):
	if actions.is_empty():
		return

	for action in actions:
		action.begin_execution()
		action.execute()

		while not action.execution_complete:
			await get_tree().process_frame

		await _offer_pending_crisis()   # live Crisis interrupt: fire the instant a unit drops, before the next hit
	
func cancel_orders(unit): #clears all actions for unit
	squad_manager.remove_actions_for_unit(unit)

func _on_queue_cancel_requested(display_action: BaseAction):
	if _board_locked_for_player():
		return
	if display_action == null or display_action.actor == null:
		return
	var unit: Unit = display_action.actor
	var squad: Squad = unit.squad
	if squad == null:
		return

	if display_action.action_type == BaseAction.ActionType.MOVE:
		# Cancelling a move also cancels the unit's main action: the main is planned from the
		# POST-move position (move-before-main rule), so without the move it's stale — wrong
		# origin/range, and nothing re-validates it. The combo cancels as a unit.
		squad_manager.cancel_move_for_unit(unit)
		_cancel_stored_main_action(unit, squad)
	elif display_action.is_main_action():
		# Every stored main action cancels the same way — displayed attacks are DERIVED volley
		# members (rebuilt each resolve), so removing the stored aim re-derives the volley and
		# its counters away. Derived-only rows (counters) aren't mains; their X stays inert.
		_cancel_stored_main_action(unit, squad)

	# Any cancel that strips the squad down to only hold-position moves (or nothing real) ends its
	# activation, exactly like the other cancel paths. Without this the X button left hold-only
	# squads "active", keeping the queue open and blocking selection of another squad.
	squad_manager.revert_if_only_hold(squad)

func _cancel_stored_main_action(unit: Unit, squad: Squad) -> void:
	for action in squad.action_queue.duplicate():
		if action.actor == unit and action.is_main_action():
			squad_manager.remove_action(squad, action)
			return

func _highlight_unit(unit: Unit, on: bool) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	# A unit with a valid queued move is drawn as a projected "ghost" (its real sprite is
	# hidden). Highlight whichever sprite is actually on screen.
	if overlay_manager.has_projected_unit(unit):
		overlay_manager.set_projected_unit_highlighted(unit, on)
	else:
		unit.visuals.set_highlighted(on)

func _squad_all_committed(squad: Squad) -> bool:
	# True when every member has locked in at least one REAL order — a main action, or a
	# non-hold move. A bare hold-position move does not count.
	for member in squad.get_members():
		if not (member.has_main_action_queued() or member.has_valid_move_queued()):
			return false
	return true

func _on_queue_reorder_attacks(ordered_actors: Array) -> void:
	if _board_locked_for_player():
		return
	var squad: Squad = squad_manager.active_squad
	if squad == null or not is_instance_valid(squad):
		return
	squad.reorder_attacks_by_actor(ordered_actors)
	refresh_action_queue(squad)   # re-resolve + redraw: the queue now reflects the new combo order

func _on_queue_row_hover_changed(action: BaseAction, hovering: bool) -> void:
	for u in _highlighted_queue_units:
		_highlight_unit(u, false)
	_highlighted_queue_units.clear()

	if not hovering or action == null:
		return

	if is_instance_valid(action.actor):
		_highlight_unit(action.actor, true)
		_highlighted_queue_units.append(action.actor)

	if action is AttackAction:
		var target := (action as AttackAction).target
		if target != null and is_instance_valid(target):
			_highlight_unit(target, true)
			_highlighted_queue_units.append(target)

func create_squad(unit: Unit):
	draw_create_squad(unit)
	var candidates: Array[Unit] = []
	for other in _all_units():
		if squad_manager.can_squad_up(other, unit.squad):
			candidates.append(other)
	enter_target_pick_mode(candidates, func(picked: Unit): squad_manager.join_squad(picked, unit.squad))

func join_squad_mode(unit: Unit):
	draw_joinable_squads(unit)
	var candidates: Array[Unit] = []
	for other in _all_units():
		if squad_manager.can_join_squad(unit, other.squad):
			candidates.append(other)
	enter_target_pick_mode(candidates, func(picked: Unit): squad_manager.join_squad(unit, picked.squad))
	
func enter_move_mode(unit: Unit):
	var moverange := compute_move_range(unit)
	game_state = GameState.CHOOSING_MOVE
	if unit.has_squad():
		draw_squad_leader_range(unit.squad, unit.squad.leader.get_projected_destination())
	overlay_manager.show_overlay(OverlayManager.OverlayType.MOVE, get_move_range(moverange, unit), OVERLAY_DEFAULT_ATLAS)
	if not unit.is_leader():
		var unreachable = moverange.squad_unreachable.keys()
		overlay_manager.show_overlay(OverlayManager.OverlayType.INVALIDMOVE, unreachable, OVERLAY_DEFAULT_ATLAS)

func _offer_pending_crisis() -> void:
	# Crisis is a LIVE interrupt (will-and-death.md): the offer must fire the moment a unit goes
	# down — BEFORE a later hit in the same pass kills the downed unit. We poll between hits here
	# (the sequence loop is already async) instead of awaiting inside the synchronous take_damage
	# path, and instead of the old end-of-pass offer (which never fired when a follow-up counter
	# finished the unit first). Squad ejection stays deferred to _process_downed_pending.
	for unit in _downed_pending.duplicate():
		if not is_instance_valid(unit) or unit.is_queued_for_deletion():
			continue
		if unit.crisis_offered_pending:
			unit.crisis_offered_pending = false
			if await _offer_crisis(unit):
				unit.enter_crisis()
				_downed_pending.erase(unit)   # back on its feet — not ejected at pass end

func enter_attack_mode(unit: Unit):
	game_state = GameState.ATTACK_TARGETING
	overlay_manager.show_overlay(OverlayManager.OverlayType.ATTACK, unit.combat.get_all_attack_cells_from(unit.get_projected_destination()), OVERLAY_DEFAULT_ATLAS)

func disband_squad(unit: Unit):
	squad_manager.disband_squad(unit.squad)

func get_unit_at_cell(cell: Vector2i) -> Unit:
	for unit in units_root.get_children():
		if unit.movement.cell == cell:
			return unit
	return null

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
			dev_controller.handle_tile_brush(event)
			return

	if _board_locked_for_player():
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
						show_action_menu(get_viewport().get_mouse_position(), main_action_menu.populate(target), target)
				GameState.CHOOSING_MOVE: 
					#This is checking if you're clicking on a valid tile
					var moverange := compute_move_range(lastUnit)
					if moverange.reachable.keys().has(clickedCell) or moverange.squad_unreachable.keys().has(clickedCell):
						var path = reconstruct_path(moverange.came_from, last_clicked_cell, clickedCell)
						var move = MoveAction.new()
						move.init(lastUnit, path, GridUtils.get_terrain_icon_at_cell(grid, path.back()))
						squad_manager.queue_action(lastUnit.squad, move)
						overlay_manager.show_planned_path(lastUnit, move)
						if move.is_valid:
							overlay_manager.show_projected_unit(lastUnit, move.destination)
					exit_current_mode()
				GameState.CHOOSING_GROUP_MOVE:
					if compute_move_range(lastUnit).reachable.keys().has(clickedCell):
						squad_manager.queue_group_move(lastUnit.squad, clickedCell, _board())
					exit_current_mode()
				GameState.DEV_MODE:
					if dev_controller.is_armed():
						dev_controller.resolve_pending(clickedCell)
					elif clickedUnit != null:
						dev_overlay.unit_editor.edit_unit(clickedUnit)
				GameState.ATTACK_TARGETING:
					if lastUnit != null or lastProjectedUnit != null:
						if lastUnit == null:
							lastUnit = lastProjectedUnit
						var origin = lastUnit.get_projected_destination()
						# Directional weapons aim by direction; point weapons need the cell in range.
						if lastUnit.combat.is_directional_attack() or lastUnit.combat.can_hit_cell_from(origin, clickedCell):
							# #47: cells are the target. A legal aim is queueable whether or not a unit
							# is there — victims (and later terrain effects, #50) are derived at resolve
							# time (#15). Store the AIM only (actor + aimed cell); null target = derived later.
							var attack := AttackAction.create(lastUnit, origin, null, clickedCell)
							attack.fired_attack = lastUnit.get_fired_attack()
							squad_manager.queue_action(lastUnit.squad, attack)
					exit_current_mode() #TODO will need different logic later.  Show enemy stats before trying attack, not exit back to idle after attack, etc						
				GameState.PICKING_TARGET:
					if _target_pick_cells.has(clickedCell) and clickedUnit != null:
						_target_pick_callback.call(clickedUnit)
					exit_current_mode()

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
 
func queue_rescue(rescuer: Unit, target: Unit) -> void:
	var rescue := RescueAction.new()
	rescue.init(rescuer, target)
	squad_manager.queue_action(rescuer.squad, rescue)

func queue_intimidate(intimidator: Unit, target: Unit) -> void:
	var intimidate := IntimidateAction.new()
	intimidate.init(intimidator, target)
	squad_manager.queue_action(intimidator.squad, intimidate)

func queue_rally(unit: Unit):
	var rally := RallyAction.new()
	rally.init(unit)
	squad_manager.queue_action(unit.squad, rally)
	clear_selection()
	
func start_faction_turn(faction: Team.Faction):
	game_state = GameState.BETWEEN_TURNS
	await get_tree().create_timer(1.0).timeout #later make small waits between each enemy movement.
	game_state = GameState.IDLE
	squad_manager.reset_faction_actions(faction)

	if ai_controller.is_ai_faction(faction):
		game_state = GameState.AI_TURN
		camera_controller.set_ai_locked(true)
		await ai_controller.take_faction_turn(faction, _board())
		camera_controller.set_ai_locked(false)
		return
	
	#TODO This should probably be it's own game state - IN_MENU or something.  
	#Can call an end menu function from the popup hide that calls update visuals instead.  
	#Right now, mouse icon changes while menu is up and you hover around, so a new state could be used to stop erratic behavoir like that
func show_action_menu(pos: Vector2i, items: Array, unit: Unit):
	var controller := ActionMenuController.new()
	add_child(controller)
	controller.setup(unit)

	controller.action_selected.connect(main_action_menu.on_pressed)
	controller.cancelled.connect(clear_selection_controller)
	controller.cancelled.connect(_on_action_menu_cancelled)

	controller.populate(items, MainActionMenu.ACTION_DATA)
	controller.setpos(pos)

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

func _tick_downed_countdowns(faction: Team.Faction):
	for unit in _all_units():
		if unit.is_downed() and unit.get_faction() == faction:
			unit.tick_downed_countdown()

func _tick_crisis_surges(faction: Team.Faction):
	for unit in _all_units():
		if unit.get_faction() == faction:
			unit.advance_crisis_surge()

func clear_selection():
	game_state = GameState.IDLE

	_target_pick_cells = []
	_target_pick_callback = Callable()   # drop captured refs
	
	overlay.clear()
	overlay_manager.clear_all()
	overlay_manager.clear_terrain_preview()
	if squad_manager.active_squad == null:
		overlay_manager.clear_squad_range()
	if squad_manager.active_squad == null:
		clear_icons([OverlayIcon.IconType.CROWN, OverlayIcon.IconType.SQUADMEMBER])

func clear_selection_controller(controller):
	clear_selection()

func update_selection_overlay():
	overlay.clear()
	
func refresh_action_queue(squad: Squad):
	if squad == null:
		squad_action_queue_control.show_display_entries([])
		overlay_manager.clear_terrain_preview()
		squad_action_queue_control.set_execute_state(SquadActionQueueControl.ExecuteState.DISABLED)
		return
	var entries := squad_manager.get_display_entries_for_squad(squad, _board())
	squad_action_queue_control.show_display_entries(entries)
	_preview_terrain_effects(squad)
	var can_execute: bool = (squad_manager.active_squad == squad
		and not squad_manager.only_hold_actions()
		and not squad_manager.squad_has_invalid_actions(squad)
		and not _board_locked_for_player())
	if not can_execute:
		squad_action_queue_control.set_execute_state(SquadActionQueueControl.ExecuteState.DISABLED)
	elif _squad_all_committed(squad):
		squad_action_queue_control.set_execute_state(SquadActionQueueControl.ExecuteState.ALL_COMMITTED)
	else:
		squad_action_queue_control.set_execute_state(SquadActionQueueControl.ExecuteState.READY)

# Law #2 board preview: the cells the active plan WILL ignite, derived from the same resolver pass
# the queue panel reads. Ghosted so it reads as "pending", not "already on fire".
func _preview_terrain_effects(squad: Squad) -> void:
	var plan := squad_manager.resolve_plan(squad, _board())
	var cells: Array[Vector2i] = []
	for effect in plan.cell_effects:
		if effect.states_added.has(Terrain.TileState.BURNING) and not cells.has(effect.cell):
			cells.append(effect.cell)
	overlay_manager.show_terrain_preview(cells)

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
		unit.went_downed.connect(_on_unit_downed)
		return unit
	return null
	
func _on_unit_died(unit: Unit):
	overlay_manager.handle_unit_death(unit)
	squad_manager.handle_unit_death(unit)
	refresh_action_queue(squad_manager.active_squad)
	
func _on_unit_downed(unit: Unit):
	# The down fires INSIDE AttackAction.execute(). The unit's state (DOWNED, 1 HP) is already
	# set in _go_downed; defer the squad/overlay cleanup until the execution pass settles, so
	# we never mutate squads while execute_orders is mid-await.
	if not _downed_pending.has(unit):
		_downed_pending.append(unit)

func _process_downed_pending() -> void:
	if _downed_pending.is_empty():
		return
	for unit in _downed_pending:
		if not is_instance_valid(unit) or unit.is_queued_for_deletion():
			continue   # finished off later in the same pass — the death path already cleaned it up
		overlay_manager.handle_unit_death(unit)   # clear its planning overlays (not its board presence)
		squad_manager.handle_unit_downed(unit)    # eject into a solo squad — safe now, execution is over
	_downed_pending.clear()
	refresh_action_queue(squad_manager.active_squad)

func _offer_crisis(unit: Unit) -> bool:
	# Non-player factions decide by archetype stance — deterministic, so the player's queue
	# previewed this exact outcome (Law #2; R9: enemy Crisis is never a BREAK). The PLAYER
	# faction keeps the live prompt, except when AI-driven (dev toggle) — nothing to block on.
	if unit.get_faction() != Team.Faction.PLAYER or ai_controller.is_ai_faction(unit.get_faction()):
		return AIArchetype.accepts_crisis(unit.squad.archetype)
	return await CrisisPrompt.show_prompt($UILayer, unit.get_unit_name())

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
	overlay_manager.show_overlay(OverlayManager.OverlayType.SQUADRANGE, squad.get_squad_range_from_cell(cell), OVERLAY_DEFAULT_ATLAS)

func _on_squad_has_no_actions(squad: Squad):
	overlay_manager.clear_squad_range()
	refresh_action_queue(squad)
	overlay_manager.redraw_squad_unit_icons(squad)

func _on_unit_action_cancelled(squad: Squad, unit: Unit, actiontype: BaseAction.ActionType):
	# Only a MOVE cancel may clear the unit's move visuals. Cancelling a main action
	# (attack/rescue) must leave a still-queued move — arrow and projected ghost — untouched.
	if actiontype == BaseAction.ActionType.MOVE:
		overlay_manager.clear_planned_path(unit)
		unit.visuals.set_projected(false)

	if squad_manager.active_squad == squad:
		overlay_manager.create_unit_icon(unit, OverlayIcon.IconType.SQUADMEMBER)
		if unit.is_leader():
			overlay_manager.create_unit_icon(unit, OverlayIcon.IconType.CROWN)

	if unit.is_leader():
		draw_squad_leader_range(squad, squad.leader.get_projected_destination())

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

func _all_units() -> Array[Unit]:
	var result: Array[Unit] = []
	for child in units_root.get_children():
		result.append(child as Unit)
	return result
	
func _board() -> BoardContext:
	return BoardContext.new(grid, _all_units(), squad_manager, terrain_states, zone_manager)

func compute_move_range(unit: Unit) -> Dictionary:
	return RulesService.compute_move_range(unit, _board())

func draw_joinable_squads(joining_unit: Unit):
	overlay_manager.clear_all()
	var cells: Array[Vector2i] = []
	for unit in units_root.get_children():
		if squad_manager.can_join_squad(joining_unit, unit.squad) and unit.is_leader():
			for cell in GridUtils.cells_within_manhattan_range(unit.get_projected_destination(), unit.squad.get_max_squad_range()):
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
	for cell in GridUtils.cells_within_manhattan_range(unit.get_projected_destination(), unit.squad.get_max_squad_range()):
		var target_unit = get_unit_at_cell(cell)
		if cell != unit.movement.cell:
			cells.append(cell)
		if target_unit != null and squad_manager.can_squad_up(target_unit, unit.squad):
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
	return RulesService.reconstruct_path(came_from, start, goal)

func spawn_test_units():
	var test_data_baddy := preload("res://Resources/BadGuy1.tres")
	var test_data_goody := preload("res://Resources/GoodGuy1.tres")
	
	var test_cells := [
		Vector2i(-1, -5)
	]
	for cell in test_cells:
		spawn_unit(test_data_goody, cell)
		
	var test_enemy : Unit = spawn_unit(test_data_baddy, Vector2i(4,4))
	var test_item : WeaponData = preload("res://Resources/Weapons/MainVarieties/ChainSword.tres")
	test_enemy.add_item(WeaponInstance.make(test_item))


	var generic_stats := Stats.STAT_DEFAULTS.duplicate()
	
	var data1 = UnitFactory.create_unit_data(generic_stats, "GoodGuy 2", Team.Faction.PLAYER)
	var data2 = UnitFactory.create_unit_data(generic_stats, "GoodGuyThree", Team.Faction.PLAYER)
	var data3 = UnitFactory.create_unit_data(generic_stats, "BaddyNumeroDos", Team.Faction.ENEMY)
	
	spawn_unit(data1, Vector2i(-6, -5))
	spawn_unit(data2, Vector2i(-8, -5))
	spawn_unit(data3, Vector2i(4, 6))

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
			var moverange := compute_move_range(hoveredUnit)
			if squad_manager.active_squad == null:
				clear_icons([OverlayIcon.IconType.CROWN, OverlayIcon.IconType.SQUADMEMBER, OverlayIcon.IconType.TARGET])
			
			if hoveredUnit.has_squad():
				draw_squad_leader_range(hoveredUnit.squad, hoveredUnit.squad.leader.get_projected_destination())

			overlay_manager.show_overlay(OverlayManager.OverlayType.MOVE, get_move_range(moverange, hoveredUnit), OVERLAY_DEFAULT_ATLAS)
			_show_hover_panel(hoveredUnit)
			var unreachable = moverange.squad_unreachable.keys()
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
		
	if game_state == GameState.PICKING_TARGET:
		var preview_cells: Array[Vector2i] = []
		if _target_pick_cells.has(hoveredCell):
			preview_cells.append(hoveredCell)
		overlay_manager.show_overlay(OverlayManager.OverlayType.HOVER, preview_cells, OVERLAY_DEFAULT_ATLAS)

		if preview_cells.is_empty():
			cursor_controller.set_state(CursorController.CursorState.INVALID)
		else:
			cursor_controller.set_state(CursorController.CursorState.VALID)
		cursor_controller.set_cursor_pos(hoveredCell)

	if game_state == GameState.CHOOSING_GROUP_MOVE:
		var leader = get_unit_at_cell(last_clicked_cell)
		overlay_manager.clear_hover_move_path()
		if leader != null and compute_move_range(leader).reachable.keys().has(hoveredCell):
			cursor_controller.set_state(CursorController.CursorState.VALID)
			overlay_manager.show_hover_move_paths(squad_manager.plan_group_move(leader.squad, hoveredCell, _board()))
		else:
			cursor_controller.set_state(CursorController.CursorState.INVALID)
		cursor_controller.set_cursor_pos(hoveredCell)
	
	if game_state == GameState.ATTACK_TARGETING:
		var attacker: Unit = get_unit_at_cell(last_clicked_cell)
		if attacker == null:
			attacker = squad_manager.get_projected_unit_from_cell(last_clicked_cell)
		var preview_cells: Array[Vector2i] = []
		if attacker != null:
			var origin := attacker.get_projected_destination()
			# Directional: any non-zero facing is a legal aim (the whole spread is the target).
			# Point: the hovered cell itself must be in range.
			if attacker.combat.is_directional_attack() or attacker.combat.can_hit_cell_from(origin, hoveredCell):
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
		var moverange := compute_move_range(unit)
		if unit.is_leader(): 
			overlay_manager.clear_squad_range()
		if unit.is_leader() and unit.has_squad() and moverange.reachable.keys().has(hoveredCell):
			draw_squad_leader_range(unit.squad, hoveredCell)
			overlay_manager.redraw_planned_paths()
			overlay_manager.redraw_projected_units()
		if moverange.reachable.keys().has(hoveredCell) or moverange.squad_unreachable.keys().has(hoveredCell):
			cursor_controller.set_state(CursorController.CursorState.VALID)
			var path = reconstruct_path(moverange.came_from, last_clicked_cell, hoveredCell)
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

func _show_hover_panel(hovered: Unit) -> void:
	# Inspect + hover must never overlap. While a unit is inspected:
	#   - hovering that SAME unit adds nothing -> suppress the hover panel
	#   - hovering a DIFFERENT unit -> force it onto the opposite screen half
	if unit_info_panel.is_showing():
		if unit_info_panel.is_showing_unit(hovered):
			hover_info_panel.clear()
			return
		var half: int = HoverInfoPanelControl.Half.BOTTOM if unit_info_panel.is_on_top() else HoverInfoPanelControl.Half.TOP
		hover_info_panel.set_unit(hovered, half)
	else:
		hover_info_panel.set_unit(hovered)

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
