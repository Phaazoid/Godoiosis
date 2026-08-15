extends Node
class_name DevController

# Dev-only board manipulation, pulled out of game.gd (#22): unit move/duplicate arming,
# tile-brush paint/erase, and map resize. Holds a back-ref to the Game coordinator for the
# board primitives it needs. Isolating this keeps the shipping coordinator clean and the dev
# glue strippable. Also the one home for the dev KEYS (F1/F2/F3, #154) -- see _input.

enum PendingAction { NONE, MOVE, DUPLICATE }

var game   # the Game coordinator (Node2D); set by game._ready()

# Injectable brush-cell source (#231), the HoverPresenter.pointer_source twin: a host whose
# pointer is NOT this viewport's mouse (the 3D picker) supplies the brush cell directly.
# Applied inside _mouse_cell(), so paint, erase and the ghost poll inherit it from ONE place.
# Unset = the mouse derivation below, i.e. the flat 2D game is untouched.
var cell_source: Callable

var _pending_action: PendingAction = PendingAction.NONE
var _pending_unit: Unit = null
var _brush_painting := false
var _brush_erasing := false
var _brush_ghost: TileMapLayer = null

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

# Is the brush armed and taking mouse input? Asked by game.gd's 2D input arm, Battle3D's 3D
# arm (#231) and the ghost poll below -- ONE predicate, so a third caller cannot drift a third
# answer. Deliberately NOT paint_mode-aware: every mode paints, only the ghost is TERRAIN-only.
func brush_armed() -> bool:
	return game.game_state == game.GameState.DEV_MODE \
		and game.dev_overlay != null \
		and game.dev_overlay.tile_brush.brush_active

# Both buttons are hold-to-drag (erase gained it 2026-08-12); paint wins if both are held.
func handle_tile_brush(event) -> void:
	if event is InputEventMouseButton:
		# The wheel is read FIRST and returns (#260), so it can never reach the drag flags below:
		# scrolling to change the level mid-stroke must not end the stroke. Godot emits a press AND
		# a release per notch, hence the pressed gate -- otherwise every notch counts twice.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_nudge_elevation(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_brush_painting = event.pressed
			if event.pressed:
				_paint()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_brush_erasing = event.pressed
			if event.pressed:
				_erase()
	elif event is InputEventMouseMotion:
		if _brush_painting:
			_paint()
		elif _brush_erasing:
			_erase()

func _mouse_cell() -> Vector2i:
	if cell_source.is_valid():
		var injected: Vector2i = cell_source.call()   # typed local: .call() erases to Variant
		return injected
	return game.grid.local_to_map(game.grid.to_local(game.get_global_mouse_position()))

# The ghost POLLS the mouse per frame (HoverPresenter's mechanism), not the event stream:
# while the Dev Tools OS window holds focus, the unfocused game window receives no mouse-motion
# events until a click refocuses it -- the polled selector followed the cursor there while an
# evented ghost sat stale. One driver; the gate mirrors game.gd's brush-input gate, so the
# ghost shows exactly when a click would paint.
func _process(_delta: float) -> void:
	_sync_brush_ghost()

func _sync_brush_ghost() -> void:
	if game == null or game.process_mode == Node.PROCESS_MODE_DISABLED:
		return   # modal freeze: painting is frozen, the ghost holds with it
	var cell := brush_ghost_cell()
	if cell == GridUtils.NO_CELL:
		hide_brush_ghost()
		return
	update_brush_ghost(cell)


# The ghost's INTENT, for ANY renderer: the cell the brush would paint, or NO_CELL when it
# would show nothing. A 3D mirror reads THIS and never the 2D ghost's `.visible` -- under a 3D
# host that field has a second writer and a second meaning ("the 2D board draws at all"), which
# is the #232/#238 trap exactly. Ask the question, not the field it happens to live in.
func brush_ghost_cell() -> Vector2i:
	if not brush_armed():
		return GridUtils.NO_CELL
	if game.dev_overlay.tile_brush.paint_mode != TileBrushTool.PaintMode.TERRAIN:
		return GridUtils.NO_CELL
	return _mouse_cell()


# What that preview would BE -- handed over as the LAYER, not as a decoded property of it. The
# ghost layer already holds the brush's pick as a REAL placed tile, so a 3D twin resolves it with
# the same call it uses on the real grid and the two cannot drift into disagreeing about what is
# being painted. It returned the Kind until #250, which was one decode too early: the 3D board
# now draws a cell from its ATLAS COORDS, and a kind-shaped answer could no longer describe the
# block that paint would produce.
func brush_ghost_layer() -> TileMapLayer:
	return _brush_ghost

# Half-transparent twin of the real paint: a second TileMapLayer on the grid's own tileset, so a
# multi-cell tile (the lantern) previews exactly as set_cell will draw it. Child of the grid --
# same transform, and it freezes with the Game subtree like painting itself does.
func update_brush_ghost(cell: Vector2i) -> void:
	_ensure_brush_ghost()
	if _brush_ghost.tile_set != game.grid.tile_set:
		_brush_ghost.tile_set = game.grid.tile_set
	var brush: TileBrushTool = game.dev_overlay.tile_brush
	if _brush_ghost.visible and _brush_ghost.get_cell_source_id(cell) == brush.selected_source \
			and _brush_ghost.get_cell_atlas_coords(cell) == brush.selected_tile:
		return   # same cell, same pick: skip the per-frame clear/set churn
	_brush_ghost.clear()
	_brush_ghost.set_cell(cell, brush.selected_source, brush.selected_tile)
	_brush_ghost.visible = true

func hide_brush_ghost() -> void:
	if _brush_ghost == null or not _brush_ghost.visible:
		return
	_brush_ghost.clear()
	_brush_ghost.visible = false

func _ensure_brush_ghost() -> void:
	if _brush_ghost != null:
		return
	_brush_ghost = TileMapLayer.new()
	_brush_ghost.name = "BrushGhost"
	_brush_ghost.tile_set = game.grid.tile_set
	_brush_ghost.modulate = Color(1, 1, 1, 0.5)
	_brush_ghost.z_index = 1   # above the board tiles, below units (Unit.BASE_SPRITE_INDEX)
	_brush_ghost.visible = false
	game.grid.add_child(_brush_ghost)

# The scroll wheel sets the level the elevation brush places at (#260). Mode-gated: the wheel is
# unbound everywhere else in the 2D game, and silently retuning a brush you can't see would be a
# surprise the next time you switched to Elevation.
func _nudge_elevation(delta: int) -> void:
	var brush: TileBrushTool = game.dev_overlay.tile_brush
	if brush.paint_mode != TileBrushTool.PaintMode.ELEVATION:
		return
	brush.nudge_elevation(delta)

func _paint() -> void:
	var cell := _mouse_cell()
	match game.dev_overlay.tile_brush.paint_mode:
		TileBrushTool.PaintMode.ZONE:
			_paint_zone(cell)
		TileBrushTool.PaintMode.STATE:
			_paint_state(cell)
		TileBrushTool.PaintMode.ELEVATION:
			_paint_elevation(cell)
		TileBrushTool.PaintMode.TERRAIN:
			_paint_tile(cell)

func _erase() -> void:
	var cell := _mouse_cell()
	match game.dev_overlay.tile_brush.paint_mode:
		TileBrushTool.PaintMode.ZONE:
			_erase_zone(cell)
		TileBrushTool.PaintMode.STATE:
			_erase_state(cell)
		TileBrushTool.PaintMode.ELEVATION:
			_erase_elevation(cell)
		TileBrushTool.PaintMode.TERRAIN:
			_erase_tile(cell)

func _paint_tile(cell: Vector2i) -> void:
	var brush: TileBrushTool = game.dev_overlay.tile_brush
	game.grid.set_cell(cell, brush.selected_source, brush.selected_tile)
	game.camera_controller.refresh_bounds(game.grid)

func _erase_tile(cell: Vector2i) -> void:
	game.grid.erase_cell(cell)
	# The states go with the ground (#245). The forbid stops NEW deposits on a groundless cell but
	# says nothing about ones already sitting there when the tile is taken away. The REDRAW is not
	# optional either: without it the store is correct and the icon stays on screen, which is how
	# this shipped broken the first time -- the 3D mirror then faithfully mirrors a stale sprite.
	if game.terrain_states.prune_groundless():
		game.overlay_manager.redraw_terrain_live(game.terrain_states)
	_prune_groundless_heights()
	game.camera_controller.refresh_bounds(game.grid)

func _paint_zone(cell: Vector2i) -> void:
	var zone_name: String = game.dev_overlay.tile_brush.selected_zone_name()
	if zone_name == "":
		return
	game.zone_manager.paint_cell(zone_name, game.dev_overlay.tile_brush.selected_zone_kind(), cell)
	game.overlay_manager.redraw_zones(game.zone_manager)
	game.dev_overlay.tile_brush.update_zone_highlight()

# Scoped to the picked zone (overlap, 2026-08-12): erase must be able to carve one zone out from
# under another. No zone picked = no-op, mirroring paint's no-name rule.
func _erase_zone(cell: Vector2i) -> void:
	var zone_name: String = game.dev_overlay.tile_brush.selected_zone_name()
	if zone_name == "":
		return
	game.zone_manager.erase_cell_from(zone_name, cell)
	game.overlay_manager.redraw_zones(game.zone_manager)
	game.dev_overlay.tile_brush.update_zone_highlight()

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

# Elevation + ramp painting (#260). One click writes BOTH fields, because set_cell takes both and a
# cell is one answer. Groundless cells are refused for the same reason a state deposit is (#245):
# height under no tile is invisible junk that would resurrect the moment ground was repainted there.
func _paint_elevation(cell: Vector2i) -> void:
	if not GridUtils.has_ground(game.grid, cell):
		return
	var brush: TileBrushTool = game.dev_overlay.tile_brush
	game.board_heights.set_cell(cell, brush.selected_elevation(), brush.selected_rise())
	_refresh_height_readout()

# Right-click returns the cell to flat ground -- both fields, mirroring the whole-cell state erase.
func _erase_elevation(cell: Vector2i) -> void:
	game.board_heights.set_cell(cell, 0, Terrain.RampRise.NONE)
	_refresh_height_readout()

# Null in a build with dev tools stripped; BoardHeights has no signals to redraw off (it is a data
# store, not a subject), so every writer here pushes.
func _refresh_height_readout() -> void:
	if game.height_debug_overlay != null:
		game.height_debug_overlay.refresh()

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
	# The SECOND way to take ground away (#245), and the one a per-cell clear at the erase site
	# would have missed: shrinking strands every state that sat outside the new rectangle.
	if game.terrain_states.prune_groundless():
		game.overlay_manager.redraw_terrain_live(game.terrain_states)
	_prune_groundless_heights()
	game.camera_controller.refresh_bounds(game.grid)

# Elevation goes with the ground too (#260), at both sites the states do. The redraw is inside the
# refresh, which no-ops when the readout is hidden.
func _prune_groundless_heights() -> void:
	if game.board_heights.prune_groundless(func(cell: Vector2i) -> bool: return GridUtils.has_ground(game.grid, cell)):
		_refresh_height_readout()
	
