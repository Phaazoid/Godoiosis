extends Node2D
class_name CameraController

@onready var camera: Camera2D = $Camera2D
const TILE_SIZE = 16
const CELL_WORLD := TILE_SIZE * 2   # 32px/cell — matches your existing min/max_world math
const EDIT_MARGIN_CELLS := 8

var map_width = 32
var map_height = 20
var edge_size = 64
var is_moving := false
var keyboard_direction := Vector2.ZERO
var lock_manual_input := false
var last_move_dir := Vector2.ZERO
var was_moving := false
var ai_locked := false        # true for the whole duration of an AI-controlled turn
var follow_unit: Unit = null  # while set, target_position tracks this unit every frame
var _panning := false         # true while pan_to's tween owns global_position -- _process yields to it

@export var move_speed := 14
@export var scroll_speed := 250

var target_position: Vector2 = global_position

var min_world := Vector2(
	-map_width / 2.0 * TILE_SIZE * 2,
	-map_height / 2.0 * TILE_SIZE * 2
)

var max_world := Vector2(
	map_width / 2.0 * TILE_SIZE * 2,
	map_height / 2.0 * TILE_SIZE * 2
)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	global_position = target_position
	
func center_on_position(world_pos: Vector2):
	lock_manual_input = true
	target_position = world_pos
	clamp_target_position()

func clamp_target_position():
	var viewport_size = get_viewport_rect().size
	var visible_size = viewport_size / camera.zoom
	var half_view = visible_size / 2
	target_position.x = _clamp_axis(target_position.x, min_world.x, max_world.x, half_view.x)
	target_position.y = _clamp_axis(target_position.y, min_world.y, max_world.y, half_view.y)

func _clamp_axis(value: float, lo: float, hi: float, half: float) -> float:
	# Map smaller than the view on this axis -> bounds invert (lo+half > hi-half).
	# Center the map instead of letting clamp() thrash.
	if hi - lo <= half * 2.0:
		return (lo + hi) / 2.0
	return clamp(value, lo + half, hi - half)

func refresh_bounds(grid: TileMapLayer):
	var used := grid.get_used_rect()
	var margin := Vector2(EDIT_MARGIN_CELLS, EDIT_MARGIN_CELLS) * CELL_WORLD
	min_world = Vector2(used.position) * CELL_WORLD - margin
	max_world = Vector2(used.position + used.size) * CELL_WORLD + margin
	clamp_target_position()
	
func _process(delta: float):
	if _panning:
		return

	if is_instance_valid(follow_unit):
		target_position = follow_unit.global_position

	if global_position.distance_to(target_position) < 1:
		global_position = target_position
		is_moving = false
	
	#Always scroll at least one cell, and never snap back.  
	keyboard_direction = Vector2.ZERO
	if not lock_manual_input and not ai_locked:
		if Input.is_action_pressed("cam_right"):
			keyboard_direction.x += 1
		if Input.is_action_pressed("cam_left"):
			keyboard_direction.x -= 1
		if Input.is_action_pressed("cam_up"):
			keyboard_direction.y -= 1
		if Input.is_action_pressed("cam_down"):
			keyboard_direction.y += 1
		
	if keyboard_direction != Vector2.ZERO:
		was_moving = true
		last_move_dir = keyboard_direction
		target_position += (keyboard_direction.normalized() * scroll_speed * delta)
	
	clamp_target_position()
	
	global_position = global_position.lerp(target_position, move_speed * delta)
	
	if keyboard_direction == Vector2.ZERO:
		if global_position.distance_to(target_position) < 2:
			#Doing this to stop jerky movements.  Always move to the next tile over.  
			if was_moving:
				snap_to_grid()
				was_moving = false

	if global_position.distance_to(target_position) < 2:
		lock_manual_input = false

func snap_to_grid():
	if last_move_dir.x > 0:
		target_position.x = ceil(target_position.x / TILE_SIZE) * TILE_SIZE
	elif last_move_dir.x < 0:
		target_position.x = floor(target_position.x / TILE_SIZE) * TILE_SIZE
	else:
		target_position.x = round(target_position.x / TILE_SIZE) * TILE_SIZE
		
	if last_move_dir.y > 0:
		target_position.y = ceil(target_position.y / TILE_SIZE) * TILE_SIZE
	elif last_move_dir.y < 0:
		target_position.y = floor(target_position.y / TILE_SIZE) * TILE_SIZE
	else:
		target_position.y = round(target_position.y / TILE_SIZE) * TILE_SIZE		

func set_ai_locked(locked: bool) -> void:
	ai_locked = locked
	if not locked:
		follow_unit = null

func follow(unit: Unit) -> void:
	follow_unit = unit
	
# Smoothly pans from wherever the camera currently is to `unit`'s position over a FIXED
# duration (not fixed speed) -- a short hop and a cross-map jump read at the same pace,
# giving the player a consistent beat to reorient before the next squad acts. Switches to
# continuous follow() once the pan lands.
func pan_to(unit: Unit, duration: float = 2.0) -> void:
	follow_unit = null
	_panning = true
	var start := global_position
	var dest: Vector2 = unit.global_position
	var tween := create_tween()
	tween.tween_method(_apply_pan_position, start, dest, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	_panning = false
	follow(unit)

func _apply_pan_position(pos: Vector2) -> void:
	global_position = pos
	target_position = pos
