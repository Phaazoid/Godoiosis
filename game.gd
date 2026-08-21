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

@onready var grid : BoardGrid = $Grid
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
@onready var mission_status_panel: MissionStatusPanel = $UILayer/MissionStatusPanel
@onready var end_turn_button: EndTurnButton = $UILayer/EndTurnButton
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
# The dev INTENT changed. ONE notification path for it: set_dev_mode used to push straight into
# dev_overlay.sync_dev_mode_button, and a second consumer (the 3D badge) would have made that push
# one of two ways the same fact travels. Both listeners connect; nothing polls.
signal dev_mode_changed(active: bool)
signal unit_selected(unit: Unit)   # fired at the one select write point (select_unit); #182 lesson triggers
# Dev INTENT (the toggle), written only by set_dev_mode. game_state == DEV_MODE is where the board
# RESTS right now; the two split (declared, Law #4) because transient flows -- loads, turn handoffs,
# mission ends -- reset game_state, and the board must return to _base_state() so dev mode survives
# them (2026-08-11: every dev-window Load silently dropped the board to IDLE under an ON toggle).
var dev_mode_enabled := false
# A 3D host (#222) delivers picked board cells straight to _on_left_click/_on_right_click,
# so _unhandled_input's own cell derivation must stand down or the click acts twice. Set by
# Battle3D at boot; false everywhere else, which is what keeps the flat 2D game untouched.
var board_input_delegated := false
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
var scenario_director: ScenarioDirector   # fires authored DialogBeats (#182)
var terrain_states: TerrainStateManager
var board_heights: BoardHeights   # per-cell elevation + ramps (#257); RefCounted, so not a child
var height_debug_overlay: HeightDebugOverlay   # F5 readout, dev builds only; deleted when art lands
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
	camera_controller.game = self   # so its WASD poll can see board_input_delegated (#176 4d)
	camera_controller.refresh_bounds(grid)
	# The front door (#96 slice 2). TestBoard is no longer spawned at boot — it is a row on the
	# menu now. Lock the board synchronously, but DEFER opening the screen by a frame: during
	# _ready the SubViewport container hasn't sized its viewport yet, and a full-rect Control
	# built against a 0x0 rect lays itself out in the corner.
	game_state = GameState.MENU
	mission_controller.open_mission_select.call_deferred()

# Null in a demo build. DevTools decides, so this never depends on when the overlay frees itself.
#
# RELATIVE, not "/root/Main/DevOverlay": the game is hosted under Battle3D now, where Main sits
# at /root/Battle3D/Main and the absolute path resolved to nothing — F1 silently did nothing in
# the 3D build. Walking up from Game (GameView -> GameContainer -> Main) asks the same question
# without caring where Main is mounted.
func _find_dev_overlay() -> DevOverlay:
	if not DevTools.enabled():
		return null
	return get_node_or_null("../../../DevOverlay")

func _build_collaborators() -> void:
	dev_controller = DevController.new()
	dev_controller.game = self
	add_child(dev_controller)

	ai_controller = AIController.new()
	ai_controller.game = self
	add_child(ai_controller)

	scenario_director = ScenarioDirector.new()
	scenario_director.game = self
	add_child(scenario_director)   # after @onready: _ready here connects turn_manager / squad_manager

	terrain_states = TerrainStateManager.new()
	terrain_states.name = "TerrainStateManager"
	# A tile state needs a tile under it (#245). Reads `grid` live rather than capturing it, so a
	# board swap cannot leave the rule judging against the previous scenario's terrain.
	terrain_states.ground_source = func(cell: Vector2i) -> bool: return GridUtils.has_ground(grid, cell)
	add_child(terrain_states)

	board_heights = BoardHeights.new()   # no add_child: RefCounted, and it needs nothing from the tree

	if DevTools.enabled():
		height_debug_overlay = HeightDebugOverlay.new()
		height_debug_overlay.name = "HeightDebugOverlay"
		height_debug_overlay.grid = grid
		height_debug_overlay.heights = board_heights
		grid.add_child(height_debug_overlay)   # child of the grid so map_to_local needs no conversion

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

	# Standing squad rings follow membership (#423 slice 1). squad_created covers every LEAVE as
	# well as every birth -- leave_squad ends in create_squad -- so the two ejection sweeps that
	# nobody authored need no signal of their own.
	squad_manager.squad_created.connect(func(_s: Squad): refresh_squad_rings())
	squad_manager.squad_deleted.connect(func(_s: Squad): refresh_squad_rings())
	squad_manager.squad_member_joined.connect(func(_s: Squad, _u: Unit): refresh_squad_rings())
	# The per-squad redraw clears the whole channel, so it has to know the standing set too.
	overlay_manager.standing_rings_drawer = draw_standing_rings

	squad_action_queue_control.execute_requested.connect(_on_queue_execute_requested)
	squad_action_queue_control.cancel_requested.connect(_on_queue_cancel_requested)
	squad_action_queue_control.reorder_attacks_requested.connect(_on_queue_reorder_attacks)
	squad_action_queue_control.row_hover_changed.connect(hover_presenter.on_queue_row_hover_changed)
	end_turn_button.end_turn_requested.connect(_on_end_turn_button_pressed)

	# HoverPresenter connects its own handlers in its _ready, so this one runs after them.
	hover_presenter.hovered_unit_changed.connect(overlay_manager.on_hovered_unit_changed)

# ==============================================================================
#  Input
# ==============================================================================

# Dev keys (F1/F2/F3) are NOT here -- they live on DevController, which is exempt from the modal
# freeze. A dev key added back here would silently die whenever a card is up.
func _input(event: InputEvent) -> void:
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
	# A 3D host (#222) picks board cells itself and calls _on_left_click/_on_right_click
	# directly, so this derivation would act a SECOND time on the same physical click --
	# at whatever cell the hidden 2D camera happens to be showing. Set by Battle3D only;
	# the flat 2D game never touches it. Still above the dev-brush and SPACE arms, but the
	# REASON changed with #231: those used to be unreachable in 3D because the view had no
	# dev tools at all. It has them now -- the 3D host routes both arms itself, off its own
	# picker's cells -- so this gate standing down is what stops the two paths acting twice
	# on one physical event. It is no longer "the 3D view hides the dev overlay".
	if board_input_delegated:
		return

	if dev_controller.brush_armed():
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

	# Elevation readout (#257) — throwaway until the real 2D height render lands. Gated like
	# Battle3D's F4 so it cannot reach a shipped build.
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_F5 \
			and DevTools.enabled() and height_debug_overlay != null:
		height_debug_overlay.toggle()

# Esc during play. MENU locks the board while the card is up; the prior state is restored on
# Resume so an in-progress aim survives the pause.
func _open_pause_menu() -> void:
	var prior: GameState = game_state
	game_state = GameState.MENU
	# Grabbed here, before the card draws: a report opened FROM the pause menu wants a picture of
	# the board, not of the pause menu. Locking first means the extra frame is not interactive.
	var frame: Image = await bug_reporter.capture_frame()
	var choice: PauseMenu.Choice = await PauseMenu.show_menu(self, mission_controller.can_restart(),
		ScenarioManager.any_save_exists())
	match choice:
		PauseMenu.Choice.RESTART:
			game_state = GameState.IDLE
			mission_controller.restart_mission()
		PauseMenu.Choice.SAVE_GAME:
			var _saved: int = await SaveLoadScreen.show_screen(self, SaveLoadScreen.Mode.SAVE)
			# Same restore-before-reopen rule as GLOSSARY/REPORT below.
			game_state = prior
			_open_pause_menu()
		PauseMenu.Choice.LOAD_GAME:
			# confirm_load: unlike the title screen, loading here discards live progress.
			var slot: int = await SaveLoadScreen.show_screen(self, SaveLoadScreen.Mode.LOAD, true)
			if slot >= 0:
				# The RESTART shape. Belt-and-braces: resume_from_slot's own clear_board ->
				# exit_current_mode re-derives the state either way, synchronously.
				game_state = GameState.IDLE
				mission_controller.resume_from_slot(slot)
			else:
				game_state = prior
				_open_pause_menu()
		PauseMenu.Choice.TITLE:
			mission_controller.abandon_mission()
		PauseMenu.Choice.QUIT:
			get_tree().quit()
		PauseMenu.Choice.GLOSSARY:
			await GlossaryScreen.show_screen(self)
			# Same restore-before-reopen rule as REPORT below: reopening with MENU stashed as
			# `prior` would leave the board locked for good on Resume.
			game_state = prior
			_open_pause_menu()
		PauseMenu.Choice.SETTINGS:
			await SettingsScreen.show_screen(self)
			# PlayerSettings has no changed signal by design, so the ring setting is applied
			# where the player hands the board back rather than by polling for it.
			refresh_squad_rings()
			# GLOSSARY's shape exactly, restore included -- a settings page is another read-only
			# detour that must hand the player back to the menu they opened it from.
			game_state = prior
			_open_pause_menu()
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

# Right-click carries TWO meanings, and the open mode wins (#228, dev call): it leaves whatever
# is open -- an aim, a move pick, a target pick -- and only from a board already at rest does it
# undo the last order. One button unwinding in the exact reverse order the player built it up,
# and it can never eat a queued order out from under someone mid-aim. Position-blind either way.
# Both callers gate on _board_locked_for_player (_unhandled_input, battle3d._cancel), so this is
# unreachable during an AI turn -- do not add a third guard here.
#
# MOVES get one extra rung in between (#417 round 2, dev call): a queued move re-opens its
# planning rather than being deleted, so the press cycles move queued -> planning -> nothing.
# The second press needs no code -- planning already spent the order on entry.
func _on_right_click() -> void:
	if game_state == GameState.CHOOSING_MOVE:
		overlay_manager.clear_planned_path(selected_unit)
	# Read BEFORE exiting, since exit_current_mode is what returns the board to rest.
	var was_at_rest := game_state == _base_state()
	exit_current_mode()
	unit_info_panel.clear()   #TODO Add close button to this panel
	if was_at_rest:
		_pop_last_gesture()

# The LIFO undo. Thin caller by design (Law #4): every removal goes through the queue panel's own
# cancel, so the move-before-main cascade, the plan revalidate and the hold-only deactivation are
# ITS answers, not a second set beside them. The has() guard is real, not belt-and-braces --
# cancelling the last real order fires revert_if_only_hold, which clears the whole queue out from
# under this loop, and a stale entry would otherwise re-queue a hold and reactivate the squad.
func _pop_last_gesture() -> void:
	var squad: Squad = squad_manager.active_squad
	if squad == null:
		return
	var gesture := squad_manager.last_gesture_actions(squad)
	var replan := _lone_queued_move(gesture)
	if replan != null:
		select_unit(replan.actor, replan.actor.movement.cell)
		begin_move_planning(replan.actor)
		return
	for action in gesture:
		if squad.action_queue.has(action):
			_on_queue_cancel_requested(action)

# The newest gesture when it is one unit's OWN move -- the only shape right-click re-plans instead
# of undoing. A formation stays one decision and pops whole: "as if you hit Move again" has no
# meaning for it, since Group Move is itself hidden once a move is queued (#417).
func _lone_queued_move(gesture: Array[BaseAction]) -> MoveAction:
	if gesture.size() != 1:
		return null
	var move := gesture[0] as MoveAction
	if move == null or move.is_hold_position:
		return null
	return move

# Clicking a unit selects it and opens its action menu. Controlling enemies is deliberately
# still allowed here for hotseat/testing; the AI_TURN lock above is what stops it in play.
func _click_idle(cell: Vector2i) -> void:
	var target := unit_at_pointer(cell)
	if target == null:
		return
	select_unit(target, cell)
	game_state = GameState.TILE_SELECTED
	main_action_menu.show_main_menu(target, get_viewport().get_mouse_position())

# THE select write point (#107) -- the selection is stored, never re-derived from a cell. Two doors
# reach it: a click on the board, and right-click re-opening a queued move's planning.
func select_unit(unit: Unit, cell: Vector2i) -> void:
	last_clicked_cell = cell
	selected_unit = unit
	unit_selected.emit(unit)   # ScenarioDirector's lesson listens (#182)

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
		# Directional weapons aim by direction; point weapons need the cell in range AND within
		# the attack's vertical tolerance (#258) -- the board carries the elevations.
		if Reach.is_directional_attack(aiming) or Reach.can_hit_cell_from(attacker, origin, cell, aiming, _board()):
			# #47: cells are the target. A legal aim is queueable whether or not a unit is
			# there — victims (and terrain effects, #50) are derived at resolve time (#15).
			# Store the AIM only (actor + aimed cell); null target = derived later.
			var attack := AttackAction.declare(attacker, origin, cell)
			squad_manager.queue_action(attacker.squad, attack)
	exit_current_mode() #TODO will need different logic later.  Show enemy stats before trying attack, not exit back to idle after attack, etc

func _click_picking_target(cell: Vector2i) -> void:
	# unit_at_pointer, not get_unit_at_cell (#126): this is a POINTER question, and the board draws one
	# sprite per unit at its PROJECTED cell. The last click handler that still resolved against the live
	# board -- which made a rescue aimed at a shoved body's landing cell hit nothing at all.
	var picked := unit_at_pointer(cell)
	if target_pick_cells.has(cell) and picked != null:
		_target_pick_callback.call(picked)
	exit_current_mode()

# ==============================================================================
#  Turn flow
# ==============================================================================

func _on_turn_started(faction: Team.Faction):
	_run_turn_start_ticks(faction)
	refresh_guard_markers()   # the ticks lapsed this faction's Guards -- pull their markers with them
	# AFTER the ticks: melting ice can strand a squadmate across water it walked over while frozen
	# (#151) -- the other way a squad splits without any move having authored it.
	squad_manager.enforce_contact()
	# An ejection here changed membership without any signal a redraw path listens to.
	refresh_squad_rings()
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
	# A turn HANDOFF resets actions; a menu arrival trusts the file (#144). Keep this out of
	# start_faction_turn -- the menu paths call it, and a resumed save's has_acted must survive.
	squad_manager.reset_faction_actions(faction)
	refresh_end_turn_button()
	turn_banner.show_label("%s Turn" % Team.faction_name(faction))
	start_faction_turn(faction)

func start_faction_turn(faction: Team.Faction):
	game_state = GameState.BETWEEN_TURNS
	await Pacing.beat(self, Pacing.TURN_HANDOFF)
	game_state = _base_state()   # AI_TURN below still overrides -- the lock is not negotiable

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

# The bottom-right End Turn button's one caller (#189) -- same guard `_on_queue_execute_requested`
# uses, since the button can only be reached while the board is unlocked anyway, but a stale frame
# shouldn't be trusted over the live state.
func _on_end_turn_button_pressed() -> void:
	if _board_locked_for_player():
		return
	end_turn()

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
		unit.lapse_guard()            # #414: last turn's Guard is gone BEFORE this turn's move phase

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

# The Move GESTURE, as against enter_move_mode's bare mode entry below (which several presentation
# suites use purely to paint the overlay -- folding this in would start deleting their orders).
# Re-planning SPENDS the order it replaces (#417), so backing out of the pick leaves no move;
# revert_if_only_hold goes with the cancel or a hold-only queue strands the squad active.
# The CALLER owns the selection -- _click_choosing_move reads selected_unit, and both doors have it
# already: the menu opened on a click, the right-click cycle selects before it calls here.
func begin_move_planning(unit: Unit) -> void:
	if unit.has_action_type_queued(BaseAction.ActionType.MOVE):
		squad_manager.cancel_move_for_unit(unit)
		squad_manager.revert_if_only_hold(unit.squad)
	enter_move_mode(unit)

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
	# cell-membership one, so it doesn't touch that invariant. Neither does the vertically-BLOCKED
	# state (#258): membership stays the full union, blocked cells just wear a distinct tile.
	overlay_manager.set_attack_reach_color(aiming)
	var reach_origin := unit.get_projected_destination()
	overlay_manager.show_attack_reach(
		Reach.get_all_attack_cells_from(unit, reach_origin, aiming),
		Reach.blocked_cells_from(unit, reach_origin, aiming, _board()))

# Generic "pick one highlighted unit" mode (rescue, intimidate, future targeted actions):
# overlay the candidates' cells, hand the clicked unit to on_pick. Attack targeting stays
# its own mode — directional aiming doesn't fit this shape.
# mark_candidates false means the CALLER is already marking them some other way (#442: join-squad's
# pulsing rings). target_pick_cells is filled either way -- _click_picking_target validates against
# it, so suppressing the draw must never suppress the click.
func enter_target_pick_mode(candidates: Array[Unit], on_pick: Callable, mark_candidates := true) -> void:
	game_state = GameState.PICKING_TARGET
	target_pick_cells = _unit_cells(candidates)
	_target_pick_callback = on_pick
	if mark_candidates:
		overlay_manager.show_overlay(OverlayManager.OverlayType.ATTACK, target_pick_cells, OverlayManager.TARGET_ATLAS_COORDS)

func set_dev_mode(active: bool):
	# Intent first: exit_current_mode's clear_selection rests the board on _base_state.
	dev_mode_enabled = active
	exit_current_mode()
	dev_mode_changed.emit(active)

func exit_current_mode():
	if game_state == GameState.ATTACK_TARGETING:
		_clear_aiming_pick()
	overlay_manager.clear_target_pulse()
	overlay_manager.clear_ring_pulse()
	overlay_manager.clear_sight_trace()
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

# Where the board rests when nothing is happening: dev mode if the dev asked for it, else IDLE.
func _base_state() -> GameState:
	return GameState.DEV_MODE if dev_mode_enabled else GameState.IDLE

func clear_selection():
	game_state = _base_state()

	target_pick_cells = []
	_target_pick_callback = Callable()   # drop captured refs

	overlay_manager.clear_selection_overlays()
	if squad_manager.active_squad == null:
		overlay_manager.clear_squad_range()
	if squad_manager.active_squad == null:
		clear_selection_icons()

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

func queue_guard(guarding_unit: Unit, ward: Unit) -> void:
	var guard := GuardAction.new()
	guard.init(guarding_unit, ward)
	squad_manager.queue_action(guarding_unit.squad, guard)

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

# The mission-status HUD (#134). Called from MissionController's five write points (check, capture,
# set_objectives, restore_progress, reset) plus the dev Scenario tab's live objective toggle — the
# refresh_action_queue pattern, not a signal. No objectives (sandbox, cleared board) hides the panel.
func refresh_mission_status() -> void:
	var instruction := scenario_director.active_instruction()   # tutorial row (#182) rides the same panel
	if mission_controller.objectives.is_empty() and instruction == "":
		mission_status_panel.clear()
		return
	mission_status_panel.show_status(mission_controller, _board(), instruction)

# The bottom-right End Turn affordance (#189): flashes with the SAME Pulse cue as Execute Orders
# once every squad on the active faction has acted or waited -- there's nothing left to click but
# this. Called from has_acted's write points (SquadManager.set_has_acted's callers) and the turn
# handoff -- the refresh_mission_status pattern above (#134), a write-point call, not a signal.
func refresh_end_turn_button() -> void:
	var faction: Team.Faction = turn_manager.active_faction()
	var show: bool = (not _board_locked_for_player()
		and not ai_controller.is_ai_faction(faction)
		and squad_manager.faction_all_squads_acted(faction))
	end_turn_button.set_active(show)

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
	# Attacks AND counters (#259 closed the gap: counter shoves were never previewed). The path
	# is the trail's one source -- a landing tumble can bend it, so endpoints cannot describe it.
	var all_hits: Array = []
	all_hits.append_array(plan.attacks)
	all_hits.append_array(plan.counters)
	var shoves: Array = []
	for atk: AttackAction in all_hits:
		if atk.resolved != null and atk.resolved.knockback_applied and atk.target != null and is_instance_valid(atk.target):
			shoves.append({"target": atk.target, "path": atk.resolved.knockback_path,
				"to": atk.resolved.knockback_to, "removed": atk.resolved.removed,
				"landing_index": atk.resolved.knockback_landing_index})
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
	var joinable := joinable_squads(unit)
	draw_joinable_squads(unit, joinable)
	var candidates: Array[Unit] = []
	for squad: Squad in joinable:
		candidates.append_array(squad.get_members())
	# The rings ARE the candidate marking now (#442), so the generic ground marker would be a second
	# spelling of the same fact -- #346's own complaint about the TARGET icon Squad Up already lost.
	# The cells still go in: what is suppressed is the DRAW, never the clickability.
	enter_target_pick_mode(candidates, func(picked: Unit): squad_manager.join_squad(unit, picked.squad), false)
	overlay_manager.set_ring_pulse(candidates)

# WHICH squads this unit could join -- THE one answer, read by the marking and by the candidate list
# alike. They used to enumerate it separately and disagree: the drawing marked LEADERS, while every
# member of a joinable squad was clickable.
func joinable_squads(joining_unit: Unit) -> Array[Squad]:
	var joinable: Array[Squad] = []
	for squad: Squad in squad_manager.squads:
		if is_instance_valid(squad) and squad_manager.can_join_squad(joining_unit, squad):
			joinable.append(squad)
	return joinable

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
	var has_squadmates: bool = squad.has_squadmates()
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
	scenario_manager.board_loaded.emit()  # the one board build outside apply_scenario (#222)

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
	# that deferral exists for. Missing until 2026-07-29, which left _process_downed_pending (and
	# the since-deleted Crisis offer poll, #158) unreachable: downed units were never ejected, so
	# their tiles stayed walkable to squadmates and a downed leader kept the squad.
	unit.went_downed.connect(order_executor.on_unit_downed)
	return unit

func _on_unit_died(unit: Unit):
	# The selection is stored (#107) and die() frees the node -- release it or every reader dangles.
	if unit == selected_unit:
		selected_unit = null
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
	# Subject = the forming leader; the per-RECRUIT gate is can_squad_up, asked by the
	# enter_target_pick_mode candidate query below. The bubble is where a squad could stand;
	# WHO may join is marked on the ground by that mode (#346 -- this loop used to hang a
	# TARGET icon over each recruit as well, two markings of one fact).
	for cell in SquadCohesion.cells(unit.squad, unit.get_projected_destination(), unit, _board()):
		if cell != unit.movement.cell:
			cells.append(cell)
	overlay_manager.show_overlay(OverlayManager.OverlayType.SQUAD, cells, OverlayManager.ATLAS_COORDS)

# The joinable squads' own rings ARE the marking (#442) -- drawn through draw_squad_unit_icons, so
# with ALWAYS_SHOW_SQUAD_RINGS on this is idempotent over the standing set and only the PULSE
# changes, while with it off this is what puts them on screen. One path, both of the dev's cases.
#
# The cohesion bubble stays: WHERE THE JOINER WOULD STAND is a different fact from WHOSE SQUAD THIS
# IS, so it is not the duplication this ticket removed.
func draw_joinable_squads(joining_unit: Unit, joinable: Array[Squad]):
	overlay_manager.clear_selection_overlays()
	var cells: Array[Vector2i] = []
	for squad: Squad in joinable:
		var leader: Unit = squad.get_leader()
		# Subject = the JOINER: these are cells it would stand on, so its own traversal decides.
		for cell in SquadCohesion.cells(squad, leader.get_projected_destination(), joining_unit, _board()):
			if get_unit_at_cell(cell) == null:
				cells.append(cell)
		overlay_manager.draw_squad_unit_icons(squad)
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
#
# It drops the SELECTION's markers and no others, which is why the standing rings go straight back
# up: they are not the selection's. That is the whole of the 2026-08-21 bug the dev found by
# playing -- _hover_idle calls this on EVERY hover change while nothing is selected, bare ground
# included, so the first mouse movement after a board came up wiped the standing set and only a
# hover brought it back.
func clear_selection_icons() -> void:
	clear_icons([OverlayIcon.IconType.CROWN, OverlayIcon.IconType.SQUADMEMBER])
	draw_standing_rings()

# --- Standing squad rings (ALWAYS_SHOW_SQUAD_RINGS) ----------------------------------------
# WHICH squads wear a standing ring: THE one answer. Empty while the setting is off, which is what
# keeps every path above behaving exactly as it did.
#
# Gated on the squad having squadmates -- Unit.has_squad's question, the one _repaint_squad_plan
# also asks -- and NOT on ring_hue: a hue is dealt once at the first squadmate and never reset, so
# a squad that shrank back to one would keep wearing its colour.
func standing_ring_squads() -> Array[Squad]:
	var standing: Array[Squad] = []
	if not PlayerSettings.is_on(PlayerSettings.Setting.ALWAYS_SHOW_SQUAD_RINGS):
		return standing
	for squad: Squad in squad_manager.squads:
		if is_instance_valid(squad) and squad.has_squadmates():
			standing.append(squad)
	return standing

# Put the standing set onto a channel that has just been cleared -- THE one implementation, called
# by clear_selection_icons above and, through OverlayManager.standing_rings_drawer, by the
# per-squad redraw the hover and plan paths use. A marker channel that is cleared whole has to be
# redrawn whole, and this is the one thing that knows what "whole" means when nothing is selected.
func draw_standing_rings() -> void:
	for squad: Squad in standing_ring_squads():
		overlay_manager.draw_squad_unit_icons(squad)

# Membership changed, so the standing set may have gained or lost a squad. Rebuilds rather than
# adds, which is what makes a marker DISAPPEAR again -- create_unit_icon only ever adds, so a squad
# dropping back to one member would otherwise leave its rings behind.
#
# The setting guard is NOT redundant with standing_ring_squads' empty list: while the setting is
# off this must not touch the channel at all, where clearing it would wipe the selection's markers
# and put nothing back.
func refresh_squad_rings() -> void:
	if not PlayerSettings.is_on(PlayerSettings.Setting.ALWAYS_SHOW_SQUAD_RINGS):
		return
	clear_selection_icons()

# Armed-Guard markers (#414). Deliberately NOT part of clear_selection_icons' channel: a Guard is
# board information that has to survive selection changes and the whole enemy phase -- and since
# #435 that channel redraws the standing squad rings on every clear, which is a different question
# (a player SETTING about membership) from this one (live ward state).
# Called from the three moments a ward can appear, be spent, or lapse -- a settled pass, a turn
# start, a board load.
func refresh_guard_markers() -> void:
	overlay_manager.redraw_guard_wards(_all_units())

# ==============================================================================
#  Board queries
# ==============================================================================

func _board() -> BoardContext:
	return BoardContext.new(grid, _all_units(), squad_manager, terrain_states, zone_manager, board_heights)

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

# Where a set of units' SPRITES are -- projected, not live (#126), so the target-pick overlay marks the
# tile the player can actually see and click. Both no-plan callers (squad-up, join-squad) are gated on an
# empty queue, so projected == live for them; rescue and intimidate are the two that needed it.
func _unit_cells(units: Array[Unit]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for unit in units:
		cells.append(unit.get_projected_destination())
	return cells
