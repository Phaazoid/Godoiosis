extends Node2D

# Input/game-state coordinator — the root node of the game scene (game.tscn), instanced inside
# the GameView SubViewport (CLAUDE.md "Sharp edges"). Owns the GameState machine and routes
# clicks into the right mode handler; PICKING_TARGET is the one generic "pick a highlighted
# unit" mode (rescue/intimidate/squad-up/join-squad all ride it via enter_target_pick_mode) —
# ATTACK_TARGETING and the CHOOSING_MOVE/GROUP_MOVE cell-pickers stay their own modes on
# purpose (see CLAUDE.md's Actions bullet). The seam most cross-system wiring hangs off of.
#
# Reorganized 2026-07-26 into the sections marked below. Three collaborators were split out;
# each is built in _build_collaborators and holds a back-ref here (the DevController pattern):
#   MainActionMenu (ui/)     — every menu: what's offered, how it's drawn, where a pick goes
#   HoverPresenter (board/)  — mouse position -> cursor, overlays, hover card, row highlight
#   OrderExecutor (actions/) — running a squad's plan, and the Crisis/downed fallout it makes
#
# Still the heaviest file in the project. Prefer moving domain logic out to the system that
# owns it when you touch this, rather than adding here.

@onready var grid : TileMapLayer = $Grid
@onready var units_root: Node2D = $Units
@onready var turn_manager = $TurnManager
@onready var turn_banner = $TurnBanner
@onready var ui_layer: CanvasLayer = $UILayer
@onready var unit_info_panel: Control = $UILayer/UnitInfoPanelControl
@onready var hover_info_panel: Control = $UILayer/HoverInfoPanelControl
@onready var dev_overlay: DevOverlay = _find_dev_overlay()
@onready var overlay_manager: OverlayManager = $OverlayManager
@onready var squad_manager: SquadManager = $SquadManager
@onready var squad_action_queue_control: SquadActionQueueControl = $UILayer/SquadActionQueueControl
@onready var cursor_controller: CursorController = $CursorController
@onready var camera_controller: CameraController = $CameraController
@onready var scenario_manager: ScenarioManager = $ScenarioManager

enum GameState {
	IDLE,
	TILE_SELECTED,
	ATTACK_TARGETING,
	CHOOSING_MOVE,
	CHOOSING_GROUP_MOVE,
	BETWEEN_TURNS,
	DEV_MODE,
	PICKING_TARGET,
	AI_TURN,
	MISSION_OVER,
	MENU
}

var game_state: GameState = GameState.IDLE
var last_clicked_cell: Vector2i = GridUtils.NO_CELL
# Set once at selection, never re-derived from a cell (#107). Cleared in exit_current_mode, NOT in
# clear_selection — that runs on every menu PICK, i.e. on the way INTO a mode.
var selected_unit: Unit = null
# Destinations the whole squad can follow to; built by enter_group_move_mode, cleared on exit.
# EMPTY means "nowhere", not "unset", so there is no recompute-if-empty fallback.
var group_move_followable: Dictionary = {}
var target_pick_cells: Array[Vector2i] = []   # candidates while PICKING_TARGET; read by HoverPresenter
var _target_pick_callback: Callable           # func(picked: Unit) -> void

# Collaborators built in _build_collaborators (not placed in game.tscn — each needs its
# back-ref set before anything touches it).
var dev_controller: DevController
var ai_controller: AIController
var terrain_states: TerrainStateManager
var zone_manager: ZoneManager
var main_action_menu: MainActionMenu
var hover_presenter: HoverPresenter
var mission_controller: MissionController
var order_executor: OrderExecutor
var bug_reporter: BugReporter

# ==============================================================================
#  Lifecycle
# ==============================================================================

func _ready() -> void:
	_build_collaborators()

	# SubViewports default to LINEAR filtering and per-node texture_filter only patches part of
	# the tree — set the viewport default instead (CLAUDE.md "Sharp edges"). Do not undo.
	RenderingServer.viewport_set_default_canvas_item_texture_filter(get_viewport().get_viewport_rid(), RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)

	_wire_signals()
	camera_controller.refresh_bounds(grid)
	# The front door (#96 slice 2). TestBoard is no longer spawned at boot — it is a row on the
	# menu now. Lock the board synchronously, but DEFER opening the screen by a frame: during
	# _ready the SubViewport container hasn't sized its viewport yet, and a full-rect Control
	# built against a 0x0 rect lays itself out in the corner.
	game_state = GameState.MENU
	mission_controller.open_mission_select.call_deferred()

# Null in a demo build. DevTools decides, so this never depends on when the overlay frees itself.
func _find_dev_overlay() -> DevOverlay:
	if not DevTools.enabled():
		return null
	return get_node_or_null("/root/Main/DevOverlay")

func _build_collaborators() -> void:
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

	order_executor = OrderExecutor.new()
	order_executor.game = self
	add_child(order_executor)

	mission_controller = MissionController.new()
	mission_controller.game = self
	add_child(mission_controller)

	hover_presenter = HoverPresenter.new()
	hover_presenter.game = self
	add_child(hover_presenter)

	bug_reporter = BugReporter.new()
	bug_reporter.game = self
	add_child(bug_reporter)

func _wire_signals() -> void:
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.round_completed.connect(_on_round_completed)

	# Cohesion reads live terrain (#151): _board builds a FRESH BoardContext per call, so a melted
	# ice tile is seen by the very next validation. Never hand it a stored board.
	squad_manager.board_source = _board

	squad_manager.squad_action_cancelled.connect(_on_unit_action_cancelled)
	squad_manager.squad_action_queued.connect(_on_unit_action_queued)
	squad_manager.squad_became_active.connect(_on_squad_became_active)
	squad_manager.squad_became_empty.connect(_on_squad_has_no_actions)

	squad_action_queue_control.execute_requested.connect(_on_queue_execute_requested)
	squad_action_queue_control.cancel_requested.connect(_on_queue_cancel_requested)
	squad_action_queue_control.reorder_attacks_requested.connect(_on_queue_reorder_attacks)
	squad_action_queue_control.row_hover_changed.connect(hover_presenter.on_queue_row_hover_changed)

	# HoverPresenter connects its own handlers in its _ready, so this one runs after them.
	hover_presenter.hovered_unit_changed.connect(overlay_manager.on_hovered_unit_changed)

# ==============================================================================
#  Input
# ==============================================================================

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_dev_overlay") and dev_overlay != null:
		if not dev_overlay.visible:
			dev_overlay.show_beside()
			set_dev_mode(true)
		else:
			set_dev_mode(game_state != GameState.DEV_MODE)
	if event.is_action_pressed("dev_report_bug"):
		# The dev's zero-friction path: no card, no note, and nothing covering the board, so it is
		# the one caller that can let report() grab its own frame.
		bug_reporter.report(GameState.keys()[game_state], BugReporter.Kind.BUG, "", null)
	# The modal check is belt-and-braces since #131: a modal pauses the tree, and a paused node
	# receives no input at all, so this handler is already silent while one is up. Kept because it
	# states the intent at the gate rather than relying on a consequence of the pause.
	if event.is_action_pressed("ui_cancel") and not ModalLock.any_open(get_tree()):
		if _board_locked_for_player():
			# A locked board is an AI turn, a finished mission, or the menu -- exactly the moments
			# a stranger most wants to complain, and the ones the pause menu cannot serve. Esc
			# still reaches the report card there; it just cannot reach Resume or Restart.
			open_report_card(BugReporter.Kind.BUG)
		else:
			_open_pause_menu()

func _unhandled_input(event: InputEvent) -> void:
	if game_state == GameState.DEV_MODE and dev_overlay != null and dev_overlay.tile_brush.brush_active:
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			dev_controller.handle_tile_brush(event)
			return

	if _board_locked_for_player():
		return

	if event is InputEventMouseButton and event.pressed:
		var clicked_cell: Vector2i = grid.local_to_map(grid.to_local(get_global_mouse_position()))
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click(clicked_cell)
		elif event.button_index == MOUSE_BUTTON_RIGHT and game_state != GameState.DEV_MODE:
			_on_right_click()

	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_SPACE:
		if game_state == GameState.DEV_MODE and dev_overlay != null:
			dev_overlay.spawn.try_spawn_at(hover_presenter.last_hovered_cell)
		else:
			camera_controller.center_on_position(get_global_mouse_position())

# Esc during play. MENU locks the board while the card is up; the prior state is restored on
# Resume so an in-progress aim survives the pause.
func _open_pause_menu() -> void:
	var prior: GameState = game_state
	game_state = GameState.MENU
	# Grabbed here, before the card draws: a report opened FROM the pause menu wants a picture of
	# the board, not of the pause menu. Locking first means the extra frame is not interactive.
	var frame: Image = await bug_reporter.capture_frame()
	var choice: PauseMenu.Choice = await PauseMenu.show_menu(self, mission_controller.can_restart())
	match choice:
		PauseMenu.Choice.RESTART:
			game_state = GameState.IDLE
			mission_controller.restart_mission()
		PauseMenu.Choice.TITLE:
			mission_controller.abandon_mission()
		PauseMenu.Choice.QUIT:
			get_tree().quit()
		PauseMenu.Choice.REPORT:
			# The state named is the one from BEFORE the pause, not MENU: a report should say what
			# the player was doing when they reached for it.
			await bug_reporter.open_card(GameState.keys()[prior], BugReporter.Kind.BUG, frame)
			# Restore before reopening, or the second card captures MENU as its prior and Resume
			# leaves the board locked for good.
			game_state = prior
			_open_pause_menu()   # back to the menu they came from, not straight into the board
		_:
			game_state = prior

# game.gd owns the GameState enum, so it is the one place that can name the current state for a
# report. Every surface that is not the pause menu comes through here (#131).
func open_report_card(default_kind: BugReporter.Kind) -> void:
	bug_reporter.open_card(GameState.keys()[game_state], default_kind)

# One handler per mode, mirroring HoverPresenter's branches. Each is responsible for leaving
# the mode it handles (exit_current_mode), so the dispatcher stays a plain table.
func _on_left_click(cell: Vector2i) -> void:
	hover_presenter.update_hover_visuals(cell)

	match game_state:
		GameState.IDLE:
			_click_idle(cell)
		GameState.CHOOSING_MOVE:
			_click_choosing_move(cell)
		GameState.CHOOSING_GROUP_MOVE:
			_click_choosing_group_move(cell)
		GameState.DEV_MODE:
			_click_dev_mode(cell)
		GameState.ATTACK_TARGETING:
			_click_attack_targeting(cell)
		GameState.PICKING_TARGET:
			_click_picking_target(cell)

func _on_right_click() -> void:
	if game_state == GameState.CHOOSING_MOVE:
		overlay_manager.clear_planned_path(selected_unit)
	exit_current_mode()
	unit_info_panel.clear()   #TODO Add close button to this panel

# Clicking a unit selects it and opens its action menu. Controlling enemies is deliberately
# still allowed here for hotseat/testing; the AI_TURN lock above is what stops it in play.
func _click_idle(cell: Vector2i) -> void:
	var target := unit_at_pointer(cell)
	if target == null:
		return
	last_clicked_cell = cell
	selected_unit = target
	game_state = GameState.TILE_SELECTED
	main_action_menu.show_main_menu(target, get_viewport().get_mouse_position())

func _click_choosing_move(cell: Vector2i) -> void:
	var unit := selected_unit
	var moverange := compute_move_range(unit)
	# Physical reach is the click's business; whether the SQUAD permits landing there is queue_action's.
	if moverange.reachable.keys().has(cell) or moverange.squad_unreachable.keys().has(cell):
		var path := RulesService.reconstruct_path(moverange.came_from, unit.movement.cell, cell)
		var move := MoveAction.new()
		move.init(unit, path, GridUtils.get_terrain_icon_at_cell(grid, path.back()))
		if squad_manager.queue_action(unit.squad, move):
			overlay_manager.show_planned_path(unit, move)
			overlay_manager.show_projected_unit(unit, move.destination)
	exit_current_mode()

func _click_choosing_group_move(cell: Vector2i) -> void:
	var leader := selected_unit
	# The two questions the overlay painted, in the same order: can the leader get there, and can the
	# squad follow. A red tile is clickable and does nothing, exactly like a squadmate's own.
	if compute_move_range(leader).reachable.keys().has(cell) and group_move_followable.has(cell):
		squad_manager.queue_group_move(leader.squad, cell, _board())
	exit_current_mode()

func _click_dev_mode(cell: Vector2i) -> void:
	if dev_controller.is_armed():
		dev_controller.resolve_pending(cell)
		return
	# The pointer resolver, matching _hover_dev_mode -- the editor opens on the sprite you clicked.
	var clicked := unit_at_pointer(cell)
	if clicked != null and dev_overlay != null:
		dev_overlay.unit_editor.edit_unit(clicked)

func _click_attack_targeting(cell: Vector2i) -> void:
	var attacker := selected_unit
	if attacker != null:
		var origin := attacker.get_projected_destination()
		var aiming := attacker.get_fired_attack()   # exactly what declare() will stamp (#102)
		# Directional weapons aim by direction; point weapons need the cell in range.
		if Reach.is_directional_attack(aiming) or Reach.can_hit_cell_from(attacker, origin, cell, aiming):
			# #47: cells are the target. A legal aim is queueable whether or not a unit is
			# there — victims (and terrain effects, #50) are derived at resolve time (#15).
			# Store the AIM only (actor + aimed cell); null target = derived later.
			var attack := AttackAction.declare(attacker, origin, cell)
			squad_manager.queue_action(attacker.squad, attack)
	exit_current_mode() #TODO will need different logic later.  Show enemy stats before trying attack, not exit back to idle after attack, etc

func _click_picking_target(cell: Vector2i) -> void:
	var picked := get_unit_at_cell(cell)
	if target_pick_cells.has(cell) and picked != null:
		_target_pick_callback.call(picked)
	exit_current_mode()

# ==============================================================================
#  Turn flow
# ==============================================================================

func _on_turn_started(faction: Team.Faction):
	_run_turn_start_ticks(faction)
	# AFTER the ticks: melting ice can strand a squadmate across water it walked over while frozen
	# (#151) -- the other way a squad splits without any move having authored it.
	squad_manager.enforce_contact()
	# AFTER the ticks: an expiring downed countdown kills, and that is the one death that
	# happens outside a resolution pass (#96).
	mission_controller.check()
	if mission_controller.is_over():
		return
	# A faction with no commandable (active) units has nothing to do — its downed clocks already
	# ticked above, so pass straight to the next. The guard against an all-downed board stays:
	# the mission check above catches the case that should be a LOSS, but an uncontested dev
	# sandbox board can still reach all-downed, and this is what keeps that inert not hung.
	var board := _board()
	if not board.faction_has_active_units(faction) and board.has_active_units():
		turn_manager.end_turn(board.present_factions())
		return
	turn_banner.show_label("%s Turn" % Team.faction_name(faction))
	start_faction_turn(faction)

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

func end_turn():
	await order_executor.apply_burning_tile_damage(turn_manager.active_faction())
	mission_controller.check()   # a burning tile can take the last unit (#96)
	if mission_controller.is_over():
		return
	clear_selection()
	unit_info_panel.clear()
	turn_manager.end_turn(_board().present_factions())

func _on_round_completed() -> void:
	terrain_states.tick_states()
	overlay_manager.redraw_terrain_live(terrain_states)

# Per-unit state that decays at the owning faction's turn start (downed clocks, crisis surge,
# weapon rev, …). One pass; each tick self-guards, so no per-effect pre-filter. Add a new
# turn-start tick as one line here — no wrapper, no _on_turn_started edit.
func _run_turn_start_ticks(faction: Team.Faction) -> void:
	for unit in _all_units():
		if unit.get_faction() != faction:
			continue
		unit.tick_downed_countdown()
		unit.tick_stat_effects()      # BEFORE the surge below: an effect applied this turn must not tick this turn
		unit.advance_crisis_surge()
		unit.tick_weapon_rev()

# The board is fully hands-off for the player while an AI faction resolves its turn, while the
# end-of-mission card is up, and while Mission Select is up.
func _board_locked_for_player() -> bool:
	return game_state == GameState.AI_TURN or game_state == GameState.MISSION_OVER or game_state == GameState.MENU

func can_control(unit: Unit) -> bool:
	if unit == null:
		return false
	if game_state == GameState.DEV_MODE:
		return true
	if not unit.is_active():        # downed/dead units can't be commanded (will-and-death.md)
		return false
	return unit.get_faction() == turn_manager.active_faction()

# ==============================================================================
#  Modes — entering and leaving
# ==============================================================================

func enter_move_mode(unit: Unit):
	var moverange := compute_move_range(unit)
	game_state = GameState.CHOOSING_MOVE
	if unit.has_squad():
		draw_squad_leader_range(unit.squad, unit.squad.leader.get_projected_destination())
	overlay_manager.show_overlay(OverlayManager.OverlayType.MOVE, get_move_range(moverange, unit), OverlayManager.ATLAS_COORDS)
	if not unit.is_leader():
		var unreachable = moverange.squad_unreachable.keys()
		overlay_manager.show_overlay(OverlayManager.OverlayType.INVALIDMOVE, unreachable, OverlayManager.ATLAS_COORDS)

func enter_group_move_mode(unit: Unit):
	game_state = GameState.CHOOSING_GROUP_MOVE
	if unit.has_squad():
		draw_squad_leader_range(unit.squad, unit.squad.leader.get_projected_destination())
	# The SQUAD's range, not the leader's: what the slowest member cannot follow into cohesion gets
	# the same red as a squadmate's own out-of-range tiles. Swept once here — per-SQUAD work, the
	# same cost for one destination as for forty — and the hover and click read the result.
	var destinations := get_move_range(compute_move_range(unit), unit)
	group_move_followable = GroupMoveSolver.followable_destinations(unit.squad, _board(), destinations)
	var green: Array[Vector2i] = []
	var red: Array[Vector2i] = []
	for cell in destinations:
		if group_move_followable.has(cell):
			green.append(cell)
		else:
			red.append(cell)
	overlay_manager.show_overlay(OverlayManager.OverlayType.MOVE, green, OverlayManager.ATLAS_COORDS)
	overlay_manager.show_overlay(OverlayManager.OverlayType.INVALIDMOVE, red, OverlayManager.ATLAS_COORDS)

func enter_attack_mode(unit: Unit):
	game_state = GameState.ATTACK_TARGETING
	var aiming := unit.get_fired_attack()
	# The reach layer is the whole range and NEVER changes. What an aim will actually affect is
	# pulsed by HoverPresenter instead -- one tile per cell means any marker drawn here erases the
	# range underneath it, which is exactly what wiped whole ForwardWide lanes. Its COLOR does
	# change (#123 follow-up) -- green for a heal, red otherwise -- which is a paint choice, not a
	# cell-membership one, so it doesn't touch that invariant.
	overlay_manager.set_attack_reach_color(aiming)
	overlay_manager.show_overlay(OverlayManager.OverlayType.ATTACK, Reach.get_all_attack_cells_from(unit, unit.get_projected_destination(), aiming), OverlayManager.ATLAS_COORDS)

# Generic "pick one highlighted unit" mode (rescue, intimidate, future targeted actions):
# overlay the candidates' cells, hand the clicked unit to on_pick. Attack targeting stays
# its own mode — directional aiming doesn't fit this shape.
func enter_target_pick_mode(candidates: Array[Unit], on_pick: Callable) -> void:
	game_state = GameState.PICKING_TARGET
	target_pick_cells = _unit_cells(candidates)
	_target_pick_callback = on_pick
	overlay_manager.show_overlay(OverlayManager.OverlayType.ATTACK, target_pick_cells, OverlayManager.TARGET_ATLAS_COORDS)

func set_dev_mode(active: bool):
	exit_current_mode()
	if active:
		game_state = GameState.DEV_MODE
	if dev_overlay != null:
		dev_overlay.sync_dev_mode_button(active)

func exit_current_mode():
	if game_state == GameState.ATTACK_TARGETING:
		_clear_aiming_pick()
	overlay_manager.clear_target_pulse()
	overlay_manager.clear_hover_move_path()
	last_clicked_cell = GridUtils.NO_CELL
	selected_unit = null
	group_move_followable = {}
	clear_selection()
	if squad_manager.active_squad != null:
		squad_manager.validate_squad_plan(squad_manager.active_squad)
		overlay_manager.redraw_planned_paths()
		overlay_manager.redraw_projected_units()
		refresh_action_queue(squad_manager.active_squad)

# Aiming is over — committed or cancelled — so the pick dies with the mode it belonged to. Since
# #102 nothing outside aiming reads it (a queued order carries its own stamped fired_attack), so
# this can no longer change how anything resolves; it just stops a spent pick from surviving into
# next turn's menu gates and overlays.
func _clear_aiming_pick() -> void:
	if selected_unit != null:
		selected_unit.active_attack = null

func clear_selection():
	game_state = GameState.IDLE

	target_pick_cells = []
	_target_pick_callback = Callable()   # drop captured refs

	overlay_manager.clear_selection_overlays()
	if squad_manager.active_squad == null:
		overlay_manager.clear_squad_range()
	if squad_manager.active_squad == null:
		clear_icons([OverlayIcon.IconType.CROWN, OverlayIcon.IconType.SQUADMEMBER])

# ==============================================================================
#  Queueing orders
# ==============================================================================

# The no-argument main-action verbs: all four differed only by which BaseAction subclass got
# instantiated, so they share one queue path (dev call 2026-07-28). Rescue/intimidate/capture stay
# separate on purpose — they take real arguments (a unit, a unit, a cell), and forcing them
# through this signature would just move the branching into a parameter bag.
func queue_simple_action(unit: Unit, type: BaseAction.ActionType):
	var action := _make_simple_action(type)
	if action == null:
		push_error("queue_simple_action: no class registered for %s" % BaseAction.ActionType.keys()[type])
		return
	action.init(unit)
	squad_manager.queue_action(unit.squad, action)
	clear_selection()

# A match rather than a class dictionary: class references aren't const-foldable, and this keeps
# every branch statically typed. An unregistered type returns null and is a loud failure above.
func _make_simple_action(type: BaseAction.ActionType) -> BaseAction:
	match type:
		BaseAction.ActionType.RALLY:
			return RallyAction.new()
		BaseAction.ActionType.RELOAD:
			return ReloadAction.new()
		BaseAction.ActionType.REV:
			return RevAction.new()
		BaseAction.ActionType.BURROW:
			return BurrowAction.new()
	return null

# The cell comes from the PROJECTED destination, so a capture queued behind a move claims the
# tile the move ends on (#96 slice 3).
func queue_capture(unit: Unit):
	var capture := CaptureAction.new()
	capture.init(unit, unit.get_projected_destination(), mission_controller)
	squad_manager.queue_action(unit.squad, capture)
	clear_selection()

func queue_rescue(rescuer: Unit, target: Unit) -> void:
	var rescue := RescueAction.new()
	rescue.init(rescuer, target)
	squad_manager.queue_action(rescuer.squad, rescue)

func queue_intimidate(intimidator: Unit, target: Unit) -> void:
	var intimidate := IntimidateAction.new()
	intimidate.init(intimidator, target)
	squad_manager.queue_action(intimidator.squad, intimidate)

# ==============================================================================
#  The action-queue panel
# ==============================================================================

func _on_queue_execute_requested():
	if _board_locked_for_player():
		return
	var squad := squad_manager.active_squad
	if squad == null:
		return
	order_executor.execute_orders(squad.get_leader())

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

func _on_queue_reorder_attacks(ordered_actors: Array) -> void:
	if _board_locked_for_player():
		return
	var squad: Squad = squad_manager.active_squad
	if squad == null or not is_instance_valid(squad):
		return
	squad.reorder_attacks_by_actor(ordered_actors)
	refresh_action_queue(squad)   # re-resolve + redraw: the queue now reflects the new combo order

func refresh_action_queue(squad: Squad):
	if squad == null:
		squad_action_queue_control.show_display_entries([])
		overlay_manager.clear_terrain_preview()
		overlay_manager.clear_knockback_preview()
		squad_action_queue_control.set_execute_state(SquadActionQueueControl.ExecuteState.DISABLED)
		return
	# ONE resolve feeds both the queue rows and the board preview — they used to resolve
	# independently, doubling every refresh (docs/performance.md).
	var plan := squad_manager.resolve_plan(squad, _board())
	# Re-validate AFTER the resolve and WITH the plan: the resolve that expanded each aim is what
	# knows whether it still hits anyone, in the order the aims land.
	squad_manager.validate_squad_plan(squad, plan)
	squad_action_queue_control.show_display_entries(ActionQueueDisplayEntry.build_for(squad, plan))
	_preview_plan_effects(plan)
	var can_execute: bool = (squad_manager.active_squad == squad
		and not squad_manager.only_hold_actions(squad)
		and not squad_manager.squad_has_invalid_actions(squad)
		and not _board_locked_for_player())
	if not can_execute:
		squad_action_queue_control.set_execute_state(SquadActionQueueControl.ExecuteState.DISABLED)
	elif _squad_all_committed(squad):
		squad_action_queue_control.set_execute_state(SquadActionQueueControl.ExecuteState.ALL_COMMITTED)
	else:
		squad_action_queue_control.set_execute_state(SquadActionQueueControl.ExecuteState.READY)

# Law #2 board preview: consequences of the active plan the queue panel also shows, derived from
# the same resolver pass and ghosted as "pending" — terrain ignites (#50) + knockback shoves (#84).
func _preview_plan_effects(plan: ResolvedPlan) -> void:
	var deposits: Array = []
	var seen := {}
	for effect in plan.cell_effects:
		for state in effect.states_added:
			# Vector3i key = (cell.x, cell.y, state) — dedupes per cell-AND-state, so two
			# attacks igniting one cell draw one icon but a cell gaining two states draws both.
			var key := Vector3i(effect.cell.x, effect.cell.y, state)
			if seen.has(key):
				continue
			seen[key] = true
			deposits.append({"cell": effect.cell, "state": state})
	overlay_manager.show_terrain_preview(deposits)
	var shoves: Array = []
	for atk in plan.attacks:
		if atk.resolved != null and atk.resolved.knockback_applied and atk.target != null and is_instance_valid(atk.target):
			shoves.append({"target": atk.target, "from": atk.resolved.knockback_from, "to": atk.resolved.knockback_to})
	overlay_manager.show_knockback_preview(shoves)

func _squad_all_committed(squad: Squad) -> bool:
	# True when every member has locked in at least one REAL order — a main action, or a
	# non-hold move. A bare hold-position move does not count.
	for member in squad.get_members():
		if not (member.has_main_action_queued() or member.has_valid_move_queued()):
			return false
	return true

# ==============================================================================
#  Squads
# ==============================================================================

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

func _on_squad_has_no_actions(squad: Squad):
	overlay_manager.clear_squad_range()
	refresh_action_queue(squad)
	overlay_manager.redraw_squad_unit_icons(squad)

func _on_unit_action_queued(squad: Squad, action: BaseAction):
	var unit = action.actor

	# Per-UNIT and cheap: every member needs this, batch or not.
	if action.action_type == BaseAction.ActionType.MOVE and action.is_valid and not action.is_hold_position:
		unit.visuals.set_projected(true)

	# Squad-level and expensive: during a batch this runs once at the end instead of per order.
	if squad_manager.batching:
		return
	_repaint_squad_plan(squad)

# Re-derive and repaint everything that depends on a squad's whole plan. Idempotent, which is what
# lets the batch collapse N of these into one (docs/performance.md).
func _repaint_squad_plan(squad: Squad) -> void:
	# Squad-wide, so equivalent to the old per-actor unit.has_squad().
	var has_squadmates: bool = squad.get_members().size() > 1
	if squad_manager.active_squad == squad and has_squadmates:
		draw_squad_leader_range(squad, squad.leader.get_projected_destination())
	squad_manager.validate_squad_plan(squad)
	refresh_action_queue(squad)

	if has_squadmates:
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

# ==============================================================================
#  Populating the board
# ==============================================================================

# The hardcoded five-unit board, now reached from Mission Select's Sandbox row instead of _ready
# (#96 slice 2). Still the ONLY TestBoard call site, so retiring it stays a one-line deletion.
# Clearing last_loaded_path matters: without it the end-of-mission Retry button would reload
# whatever scenario was loaded before the sandbox.
func spawn_sandbox() -> void:
	scenario_manager.clear_board()
	scenario_manager.last_loaded_path = ""
	TestBoard.spawn(self)

# Returns null when the cell can't take a unit. NB: UnitFactory.create_unit already instantiated
# the node, so every refusal path has to free it — an un-parented Unit is an orphan nothing else
# will ever collect.
func spawn_unit(data: UnitData, pos: Vector2i) -> Unit:
	var unit: Unit = UnitFactory.create_unit(data, grid, pos)

	if grid.get_cell_tile_data(pos) == null:
		unit.queue_free()
		return null  # outside the map

	# One walkability answer for the whole game (#109). The inline `walkable` custom-data read this
	# replaced couldn't see tile state, so dev-mode refused to place a unit on a FROZEN water tile
	# that movement, pathing and knockback all treat as solid ground. Occupancy stays a SEPARATE
	# question: is_walkable answers "may a unit stand here", never "is someone already standing here".
	#TODO later change the walkability half for various unit types, i.e. flyers can spawn on rocks, etc
	if not _board().is_walkable(pos) or get_unit_at_cell(pos) != null:
		unit.queue_free()
		return null

	units_root.add_child(unit)
	squad_manager.create_squad(unit)
	unit.unit_died.connect(_on_unit_died)
	# The DOWN twin of the line above. It goes straight to OrderExecutor rather than through a
	# game.gd handler because OrderExecutor owns the DEFERRAL (_downed_pending, drained by
	# _process_downed_pending at pass end) -- restructuring squads mid-await was the original bug
	# that deferral exists for. Missing until 2026-07-29, which left _process_downed_pending and
	# _offer_pending_crisis both unreachable: downed units were never ejected, so their tiles
	# stayed walkable to squadmates and a downed leader kept the squad.
	unit.went_downed.connect(order_executor.on_unit_downed)
	return unit

func _on_unit_died(unit: Unit):
	overlay_manager.handle_unit_death(unit)
	squad_manager.handle_unit_death(unit)
	refresh_action_queue(squad_manager.active_squad)

# ==============================================================================
#  Board visuals
# ==============================================================================

# The UNION of the members' path-bubbles (#151): cohesion is per-member (a Waterwalker's crosses
# water), and the overlay must show every cell SOME member may hold or it lies about the rule. For
# a uniform squad the union collapses to one field, drawn the same way move range is.
func draw_squad_leader_range(squad: Squad, cell: Vector2i):
	var board := _board()
	var union := {}
	for member in squad.get_members():
		for c in SquadCohesion.field(squad, cell, member, board):
			union[c] = true
	var cells: Array[Vector2i] = []
	for c in union:
		cells.append(c)
	overlay_manager.show_overlay(OverlayManager.OverlayType.SQUADRANGE, cells, OverlayManager.ATLAS_COORDS)

func draw_create_squad(unit: Unit):
	var cells: Array[Vector2i] = []
	# Subject = the forming leader; the per-RECRUIT gate is can_squad_up below, which asks the
	# recruit's own path. The bubble is where a squad could stand, the icons are who may join.
	for cell in SquadCohesion.cells(unit.squad, unit.get_projected_destination(), unit, _board()):
		var target_unit = get_unit_at_cell(cell)
		if cell != unit.movement.cell:
			cells.append(cell)
		if target_unit != null and squad_manager.can_squad_up(target_unit, unit.squad):
			overlay_manager.create_unit_icon(target_unit, OverlayIcon.IconType.TARGET)
	overlay_manager.show_overlay(OverlayManager.OverlayType.SQUAD, cells, OverlayManager.ATLAS_COORDS)

func draw_joinable_squads(joining_unit: Unit):
	overlay_manager.clear_selection_overlays()
	var cells: Array[Vector2i] = []
	for unit in units_root.get_children():
		if squad_manager.can_join_squad(joining_unit, unit.squad) and unit.is_leader():
			# Subject = the JOINER: these are cells it would stand on, so its own traversal decides.
			for cell in SquadCohesion.cells(unit.squad, unit.get_projected_destination(), joining_unit, _board()):
				if get_unit_at_cell(cell) == null:
					cells.append(cell)
			overlay_manager.create_unit_icon(unit, OverlayIcon.IconType.CROWN)
			overlay_manager.create_unit_icon(unit, OverlayIcon.IconType.SQUADMEMBER)
	overlay_manager.show_overlay(OverlayManager.OverlayType.SQUAD, cells, OverlayManager.ATLAS_COORDS)

func get_squad_icons(squad: Squad) -> Dictionary: #Includes hovered unit
	var icons = {} # { Unit : Icon }
	for member in squad.get_members():
		if member != squad.leader:
			icons[member] = [OverlayIcon.IconType.SQUADMEMBER]
		if member == squad.leader:
			icons[member] = [OverlayIcon.IconType.SQUADMEMBER, OverlayIcon.IconType.CROWN]
	return icons

func clear_icons(icons: Array[OverlayIcon.IconType]):
	overlay_manager.clear_unit_icon_types(icons)

# The full selection-marker set, as its own method rather than a literal callers pass in:
# HoverPresenter/OrderExecutor reach this through an UNTYPED `game` ref, and a bare array
# literal sent that way never gets coerced to clear_icons' typed parameter (it fails at
# runtime, not at parse time). Keeping the literal on this side of the boundary avoids it.
func clear_selection_icons() -> void:
	clear_icons([OverlayIcon.IconType.CROWN, OverlayIcon.IconType.SQUADMEMBER, OverlayIcon.IconType.TARGET])

# ==============================================================================
#  Board queries
# ==============================================================================

func _board() -> BoardContext:
	return BoardContext.new(grid, _all_units(), squad_manager, terrain_states, zone_manager)

func _all_units() -> Array[Unit]:
	var result: Array[Unit] = []
	for child in units_root.get_children():
		result.append(child as Unit)
	return result

# Linear scan, deliberately — boards are single-digit unit counts, so an index would buy nothing
# and cost an invariant. Reviewed 2026-07-26; docs/performance.md → Known-and-accepted costs.
func get_unit_at_cell(cell: Vector2i) -> Unit:
	for unit in units_root.get_children():
		if unit.movement.cell == cell:
			return unit
	return null

# Which unit's SPRITE is on this cell? The one answer for every pointer question -- what a click
# selects, what the hover card shows, what hovered_unit_changed names.
#
# Nothing is derived here. The board draws exactly one sprite per unit, at that unit's PROJECTED
# cell: both ghost-drawers pair "hide the real sprite" with "draw a ghost" (redraw_projected_units
# for a valid queued move, show_knockback_preview for a shove), so the inverse of the projection
# (#105) already IS the pointer answer. The plan's answer and the pointer's answer being identical
# is Law #2 working, not a coincidence -- if they diverged, the board would be previewing something
# the plan does not do.
func unit_at_pointer(cell: Vector2i) -> Unit:
	return squad_manager.get_projected_unit_from_cell(cell)

func compute_move_range(unit: Unit) -> Dictionary:
	return RulesService.compute_move_range(unit, _board())

# The reachable cells worth DRAWING: everything the unit can reach except where it already is.
func get_move_range(result: Dictionary, unit: Unit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in result.reachable.keys():
		if cell == unit.movement.cell:
			continue
		cells.append(cell)
	return cells

func _unit_cells(units: Array[Unit]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for unit in units:
		cells.append(unit.movement.cell)
	return cells
