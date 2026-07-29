extends Node
class_name HoverPresenter

# Turns "where is the mouse" into board feedback: cursor state/position, the hover info card,
# range + preview overlays, and the queue panel's row-hover highlight. Pulled out of game.gd
# 2026-07-26, where it lived as one 133-line per-state switch; holds a back-ref to the Game
# coordinator (same pattern as DevController/AIController/MainActionMenu).
#
# Detection lives here too: _process watches for a hovered-CELL change and fires the two
# signals. This node is its own first listener (see _ready), so external listeners -- wired
# from game._ready -- always run after it.
#
# Explicit types throughout this file: `game` is untyped (game.gd has no class_name), so every
# game.* call reads as Variant and `:=` cannot infer from it.
#
# One branch per GameState, mirroring game.gd's click handlers. The branches are read-only on
# game state; anything that needs to MUTATE it belongs on the coordinator. The one deliberate
# exception is CHOOSING_MOVE, which re-validates the squad plan as the mouse sweeps: that live
# preview IS the feature (CLAUDE.md's Actions bullet), not a leak.

signal hovered_cell_changed(cell: Vector2i)
signal hovered_unit_changed(previous_unit: Unit, new_unit: Unit)

var game   # the Game coordinator (Node2D); set by game._ready()

var last_hovered_cell: Vector2i = GridUtils.NO_CELL

var _highlighted_queue_units: Array[Unit] = []

func _ready() -> void:
	# Self-wiring: this node is both the detector and the first listener of its own signals.
	hovered_unit_changed.connect(_on_hovered_unit_changed)
	hovered_cell_changed.connect(update_hover_visuals)

func _process(_delta: float) -> void:
	var mouse_world: Vector2 = game.get_global_mouse_position()
	var hovered_cell: Vector2i = game.grid.local_to_map(game.grid.to_local(mouse_world))

	if hovered_cell == last_hovered_cell:   # everything below only runs on a CELL change
		return

	var previous: Unit = game.unit_at_pointer(last_hovered_cell)
	var current: Unit = game.unit_at_pointer(hovered_cell)
	hovered_unit_changed.emit(previous, current)
	hovered_cell_changed.emit(hovered_cell)
	last_hovered_cell = hovered_cell

# ==============================================================================
#  Board hover, per mode
# ==============================================================================

# Repaint for wherever the mouse already is, without waiting for a cell change -- for when the
# MODE changed under a stationary mouse (a menu closing, for one).
func refresh() -> void:
	update_hover_visuals(last_hovered_cell)

func update_hover_visuals(hovered_cell: Vector2i) -> void:
	if game.grid.get_cell_tile_data(hovered_cell) == null:
		return   # off the map -- every mode draws nothing out there

	# Only IDLE produces squad icons. They're collected rather than drawn inline because that
	# branch clears icon types partway through; drawing once at the end survives the clear.
	var icons_to_draw := {}
	var state = game.game_state

	if state == game.GameState.DEV_MODE:
		_hover_dev_mode(hovered_cell)
	elif state == game.GameState.IDLE:
		icons_to_draw = _hover_idle(hovered_cell)
	elif state == game.GameState.TILE_SELECTED:
		_hover_tile_selected()
	elif state == game.GameState.PICKING_TARGET:
		_hover_picking_target(hovered_cell)
	elif state == game.GameState.CHOOSING_GROUP_MOVE:
		_hover_choosing_group_move(hovered_cell)
	elif state == game.GameState.ATTACK_TARGETING:
		_hover_attack_targeting(hovered_cell)
	elif state == game.GameState.CHOOSING_MOVE:
		_hover_choosing_move(hovered_cell)

	for unit in icons_to_draw.keys():
		for icontype in icons_to_draw[unit]:
			game.overlay_manager.create_unit_icon(unit, icontype)

func _hover_dev_mode(cell: Vector2i) -> void:
	if not _is_walkable(cell) or game.unit_at_pointer(cell) != null:
		game.cursor_controller.set_state(CursorController.CursorState.INVALID)
	else:
		game.cursor_controller.set_state(CursorController.CursorState.DEFAULT)
	game.cursor_controller.set_cursor_pos(cell)

# Returns the squad icons to draw (empty when there's nothing hovered worth marking).
func _hover_idle(cell: Vector2i) -> Dictionary:
	game.cursor_controller.set_cursor_pos(cell)
	game.overlay_manager.clear_selection_overlays()

	var hovered: Unit = game.unit_at_pointer(cell)
	if hovered == null:
		game.hover_info_panel.clear()
		game.overlay_manager.clear_selection_overlays()
		game.cursor_controller.set_state(CursorController.CursorState.DEFAULT)
		if game.squad_manager.active_squad == null:
			game.clear_selection_icons()
		return {}

	var moverange: Dictionary = game.compute_move_range(hovered)
	if game.squad_manager.active_squad == null:
		game.clear_selection_icons()

	if hovered.has_squad():
		game.draw_squad_leader_range(hovered.squad, hovered.squad.leader.get_projected_destination())

	game.overlay_manager.show_overlay(OverlayManager.OverlayType.MOVE, game.get_move_range(moverange, hovered), OverlayManager.ATLAS_COORDS)
	_show_hover_panel(hovered)
	game.overlay_manager.show_overlay(OverlayManager.OverlayType.INVALIDMOVE, moverange.squad_unreachable.keys(), OverlayManager.ATLAS_COORDS)

	if hovered.has_squad() and game.squad_manager.active_squad == null:   #TODO later change this to muted colors if other squads are active
		return game.get_squad_icons(hovered.squad)
	return {}

func _hover_tile_selected() -> void:
	game.cursor_controller.set_state(CursorController.CursorState.TARGET)
	game.cursor_controller.set_cursor_pos(game.last_clicked_cell)

func _hover_picking_target(cell: Vector2i) -> void:
	var preview_cells: Array[Vector2i] = []
	if game.target_pick_cells.has(cell):
		preview_cells.append(cell)
	game.overlay_manager.show_overlay(OverlayManager.OverlayType.HOVER, preview_cells, OverlayManager.ATLAS_COORDS)
	_set_cursor_for_preview(cell, not preview_cells.is_empty())

func _hover_choosing_group_move(cell: Vector2i) -> void:
	var leader: Unit = game.selected_unit
	game.overlay_manager.clear_hover_move_path()

	var reachable: bool = leader != null and game.compute_move_range(leader).reachable.keys().has(cell)
	if reachable:
		game.overlay_manager.show_hover_move_paths(GroupMoveSolver.plan(leader.squad, cell, game._board()))
	_set_cursor_for_preview(cell, reachable)

func _hover_attack_targeting(cell: Vector2i) -> void:
	var attacker: Unit = game.selected_unit

	var preview_cells: Array[Vector2i] = []
	if attacker != null:
		var origin := attacker.get_projected_destination()
		var aiming := attacker.get_fired_attack()   # aiming: the live pick IS the question (#102)
		# Directional: any non-zero facing is a legal aim (the whole spread is the target).
		# Point: the hovered cell itself must be in range.
		if Reach.is_directional_attack(aiming) or Reach.can_hit_cell_from(attacker, origin, cell, aiming):
			preview_cells = Reach.get_affected_cells_from(attacker, origin, cell, aiming)

	game.overlay_manager.show_overlay(OverlayManager.OverlayType.HOVER, preview_cells, OverlayManager.ATLAS_COORDS)
	_set_cursor_for_preview(cell, not preview_cells.is_empty())

func _hover_choosing_move(cell: Vector2i) -> void:
	var unit: Unit = game.selected_unit
	game.overlay_manager.clear_hover_move_path()
	var moverange: Dictionary = game.compute_move_range(unit)

	if unit.is_leader():
		game.overlay_manager.clear_squad_range()
	if unit.is_leader() and unit.has_squad() and moverange.reachable.keys().has(cell):
		game.draw_squad_leader_range(unit.squad, cell)
		game.overlay_manager.redraw_planned_paths()
		game.overlay_manager.redraw_projected_units()

	if not moverange.reachable.keys().has(cell) and not moverange.squad_unreachable.keys().has(cell):
		_set_cursor_for_preview(cell, false)
		return

	# Live preview: build the move this click WOULD queue and validate the plan against it, so
	# the arrow and the queue panel show the real consequence before anything is committed.
	var path := RulesService.reconstruct_path(moverange.came_from, unit.movement.cell, cell)
	var move := MoveAction.new()
	move.init(unit, path, GridUtils.get_terrain_icon_at_cell(game.grid, path.back()))

	var squad = unit.squad
	game.squad_manager.validate_squad_plan_preview(squad, move)
	game.overlay_manager.show_hover_move_path(move)

	if unit.has_squad():
		game.overlay_manager.redraw_squad_unit_icons(squad)

	game.overlay_manager.redraw_planned_paths()
	game.overlay_manager.redraw_projected_units()
	game.refresh_action_queue(squad)
	_set_cursor_for_preview(cell, true)

# ==============================================================================
#  Queue-panel row hover
# ==============================================================================

func on_queue_row_hover_changed(action: BaseAction, hovering: bool) -> void:
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

func _highlight_unit(unit: Unit, on: bool) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	# A unit with a valid queued move is drawn as a projected "ghost" (its real sprite is
	# hidden). Highlight whichever sprite is actually on screen.
	if game.overlay_manager.has_projected_unit(unit):
		game.overlay_manager.set_projected_unit_highlighted(unit, on)
	else:
		unit.visuals.set_highlighted(on)

func _on_hovered_unit_changed(previous_unit: Unit, new_unit: Unit) -> void:
	if previous_unit != null and is_instance_valid(previous_unit):
		previous_unit.visuals.set_hovered(false)

	if new_unit != null and is_instance_valid(new_unit):
		new_unit.visuals.set_hovered(true)

# ==============================================================================
#  Shared helpers
# ==============================================================================

func _is_walkable(cell: Vector2i) -> bool:
	var tile_data: TileData = game.grid.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	if not tile_data.has_custom_data("walkable"):
		return true   # a tile that doesn't declare the flag is walkable
	return tile_data.get_custom_data("walkable")

# Every pick mode reads the same way: nothing previewed means the aim is illegal.
func _set_cursor_for_preview(cell: Vector2i, valid: bool) -> void:
	if valid:
		game.cursor_controller.set_state(CursorController.CursorState.VALID)
	else:
		game.cursor_controller.set_state(CursorController.CursorState.INVALID)
	game.cursor_controller.set_cursor_pos(cell)

func _show_hover_panel(hovered: Unit) -> void:
	# Inspect + hover must never overlap. The inspect panel is a docked left column (#68):
	#   - hovering the inspected unit adds nothing -> suppress the hover card
	#   - any other unit -> the card keeps its own top/bottom logic, shifted right of the column
	if game.unit_info_panel.is_showing():
		if game.unit_info_panel.is_showing_unit(hovered):
			game.hover_info_panel.clear()
			return
		game.hover_info_panel.set_unit(hovered, int(game.unit_info_panel.panel_width()) + 8)
	else:
		game.hover_info_panel.set_unit(hovered)
