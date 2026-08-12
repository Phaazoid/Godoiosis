extends Node
class_name DevController

# Dev-only board manipulation, pulled out of game.gd (#22): unit move/duplicate arming,
# tile-brush paint/erase, and map resize. Holds a back-ref to the Game coordinator for the
# board primitives it needs. Isolating this keeps the shipping coordinator clean and the dev
# glue strippable. Also the one home for the dev KEYS (F1/F2/F3, #154) -- see _input.

enum PendingAction { NONE, MOVE, DUPLICATE }

var game   # the Game coordinator (Node2D); set by game._ready()

var _pending_action: PendingAction = PendingAction.NONE
var _pending_unit: Unit = null
var _brush_painting := false

# --- dev keys ---

# The dev layer sits ABOVE the game rules: ALWAYS keeps these keys alive while ModalLock has the
# Game subtree DISABLED. A freeze stops callbacks, not method calls, so the frozen collaborators
# below still answer.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if not DevTools.enabled():
		return
	if event.is_action_pressed("toggle_dev_overlay"):
		_toggle_dev_overlay()
	elif event.is_action_pressed("dev_reset_scenario"):
		game.scenario_manager.reload_current()
	elif event.is_action_pressed("dev_report_bug"):
		# The zero-friction path: no card, no note, nothing covering the board, so it is the one
		# caller that lets report() grab its own frame.
		var state_name: String = game.GameState.keys()[game.game_state]
		var reporter: BugReporter = game.bug_reporter
		reporter.report(state_name, BugReporter.Kind.BUG, "", null)

func _toggle_dev_overlay() -> void:
	var overlay: DevOverlay = game.dev_overlay
	if overlay == null:
		return
	if not overlay.visible:
		overlay.show_beside()
		game.set_dev_mode(true)
	else:
		game.set_dev_mode(not game.dev_mode_enabled)   # toggle the INTENT, never infer from game_state

# --- unit move / duplicate ---

func arm_move(unit: Unit) -> void:
	_pending_action = PendingAction.MOVE
	_pending_unit = unit

func arm_duplicate(unit: Unit) -> void:
	_pending_action = PendingAction.DUPLICATE
	_pending_unit = unit

func is_armed() -> bool:
	return _pending_action != PendingAction.NONE

func resolve_pending(cell: Vector2i) -> void:
	var unit := _pending_unit
	var action := _pending_action
	_pending_action = PendingAction.NONE   # consume regardless, so we never get stuck armed
	_pending_unit = null
	if not is_instance_valid(unit):
		return
	if game.grid.get_cell_tile_data(cell) == null:   # clicked off the map
		return
	var board: BoardContext = game._board()
	if not board.is_walkable(cell):                  # #109: the same answer spawn_unit gives, so
		return                                       # dev-move and dev-duplicate can't disagree
	if game.get_unit_at_cell(cell) != null:          # occupied (incl. the unit's own cell) -> no-op
		return
	match action:
		PendingAction.MOVE:
			unit.movement.set_cell(cell)             # set_cell snaps world position too
		PendingAction.DUPLICATE:
			duplicate_unit(unit, cell)

# Independent deep copy of `source` at `cell`. UnitData is duplicated so the copy owns its
# identity; runtime state (stats, HP) lives on the instance, copied post-spawn; inventory items
# are duplicate(true)'d (shallow would share the nested attack_pattern - CLAUDE.md "Sharp edges").
func duplicate_unit(source: Unit, cell: Vector2i) -> Unit:
	var data: UnitData = source.unit_data.duplicate(true)
	var copy = game.spawn_unit(data, cell)
	if copy == null:
		return null
	copy.unit_instance.stats = source.unit_instance.stats.duplicate(true)
	for i in range(source.inventory.size()):
		var item: Item = source.inventory[i]
		copy.inventory[i] = item.copy_equippable() if item is EquippableData else (item.duplicate(true) if item != null else null)
	copy.set_current_hp(source.get_current_hp())   # after gear: the clamp reads a gear-aware max (#106)
	var equipped := source.get_equipped_weapon()
	if equipped != null:
		var idx := source.inventory.find(equipped)
		if idx != -1 and copy.inventory[idx] is EquippableData:
			copy.set_equipped_weapon(copy.inventory[idx])
	return copy

# --- tile brush / map resize ---

func handle_tile_brush(event) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_brush_painting = event.pressed
			if event.pressed:
				_paint()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_erase()
	elif event is InputEventMouseMotion and _brush_painting:
		_paint()

func _paint() -> void:
	var cell = game.grid.local_to_map(game.grid.to_local(game.get_global_mouse_position()))
	match game.dev_overlay.tile_brush.paint_mode:
		TileBrushTool.PaintMode.ZONE:
			_paint_zone(cell)
		TileBrushTool.PaintMode.STATE:
			_paint_state(cell)
		TileBrushTool.PaintMode.TERRAIN:
			_paint_tile(cell)

func _erase() -> void:
	var cell = game.grid.local_to_map(game.grid.to_local(game.get_global_mouse_position()))
	match game.dev_overlay.tile_brush.paint_mode:
		TileBrushTool.PaintMode.ZONE:
			_erase_zone(cell)
		TileBrushTool.PaintMode.STATE:
			_erase_state(cell)
		TileBrushTool.PaintMode.TERRAIN:
			_erase_tile(cell)

func _paint_tile(cell: Vector2i) -> void:
	var brush: TileBrushTool = game.dev_overlay.tile_brush
	game.grid.set_cell(cell, brush.selected_source, brush.selected_tile)
	game.camera_controller.refresh_bounds(game.grid)

func _erase_tile(cell: Vector2i) -> void:
	game.grid.erase_cell(cell)
	game.camera_controller.refresh_bounds(game.grid)

func _paint_zone(cell: Vector2i) -> void:
	var zone_name = game.dev_overlay.tile_brush.selected_zone_name()
	if zone_name == "":
		return
	game.zone_manager.paint_cell(zone_name, game.dev_overlay.tile_brush.selected_zone_kind(), cell)
	game.overlay_manager.redraw_zones(game.zone_manager)

func _erase_zone(cell: Vector2i) -> void:
	game.zone_manager.erase_cell(cell)
	game.overlay_manager.redraw_zones(game.zone_manager)

# Dynamic tile-state painting (#174). Writes through TerrainStateManager.apply -- the ONE deposit
# seam -- so a painted BURNING starts its real 3-turn clock; permanent fire is what BLAZE is for.
func _paint_state(cell: Vector2i) -> void:
	var state: Terrain.TileState = game.dev_overlay.tile_brush.selected_tile_state()
	if game.terrain_states.has_state(cell, state):
		return   # a drag repaints every motion event: skip the redraw churn and the timer rewind
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([state])
	game.terrain_states.apply(effect)
	game.overlay_manager.redraw_terrain_live(game.terrain_states)

# Right-click clears the WHOLE cell's states, mirroring terrain erase.
func _erase_state(cell: Vector2i) -> void:
	var current: Array[Terrain.TileState] = game.terrain_states.states_at(cell)
	if current.is_empty():
		return
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_removed.assign(current)
	game.terrain_states.apply(effect)
	game.overlay_manager.redraw_terrain_live(game.terrain_states)
	
func resize_map(width: int, height: int, fill_source: int, fill_tile: Vector2i) -> void:
	width = maxi(1, width)
	height = maxi(1, height)
	game.grid.clear()
	for x in range(width):
		for y in range(height):
			game.grid.set_cell(Vector2i(x, y), fill_source, fill_tile)
	game.camera_controller.refresh_bounds(game.grid)
	
