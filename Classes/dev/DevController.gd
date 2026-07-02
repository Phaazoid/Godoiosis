extends Node
class_name DevController

# Dev-only board manipulation, pulled out of game.gd (#22): unit move/duplicate arming,
# tile-brush paint/erase, and map resize. Holds a back-ref to the Game coordinator for the
# board primitives it needs. Isolating this keeps the shipping coordinator clean and the dev
# glue strippable.

enum PendingAction { NONE, MOVE, DUPLICATE }

var game   # the Game coordinator (Node2D); set by game._ready()

var _pending_action: PendingAction = PendingAction.NONE
var _pending_unit: Unit = null
var _brush_painting := false

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
	copy.unit_instance.set_current_hp(source.get_current_hp())
	for i in range(source.inventory.size()):
		var item: Item = source.inventory[i]
		copy.inventory[i] = item.duplicate(true) if item != null else null
	var equipped := source.get_equipped_weapon()
	if equipped != null:
		var idx := source.inventory.find(equipped)
		if idx != -1 and copy.inventory[idx] is WeaponData:
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
	if game.dev_overlay.tile_brush.paint_mode == TileBrushTool.PaintMode.ZONE:
		_paint_zone(cell)
	else:
		_paint_tile(cell)

func _erase() -> void:
	var cell = game.grid.local_to_map(game.grid.to_local(game.get_global_mouse_position()))
	if game.dev_overlay.tile_brush.paint_mode == TileBrushTool.PaintMode.ZONE:
		_erase_zone(cell)
	else:
		_erase_tile(cell)

func _paint_tile(cell: Vector2i) -> void:
	game.grid.set_cell(cell, 0, game.dev_overlay.tile_brush.selected_tile)
	game.camera_controller.refresh_bounds(game.grid)

func _erase_tile(cell: Vector2i) -> void:
	game.grid.erase_cell(cell)
	game.camera_controller.refresh_bounds(game.grid)

func _paint_zone(cell: Vector2i) -> void:
	var zone_name = game.dev_overlay.tile_brush.selected_zone_name()
	if zone_name == "":
		return
	game.zone_manager.paint_cell(zone_name, cell)
	game.overlay_manager.redraw_zones(game.zone_manager)

func _erase_zone(cell: Vector2i) -> void:
	game.zone_manager.erase_cell(cell)
	game.overlay_manager.redraw_zones(game.zone_manager)
	
func resize_map(width: int, height: int, fill_tile: Vector2i) -> void:
	width = maxi(1, width)
	height = maxi(1, height)
	game.grid.clear()
	for x in range(width):
		for y in range(height):
			game.grid.set_cell(Vector2i(x, y), 0, fill_tile)
	game.camera_controller.refresh_bounds(game.grid)
