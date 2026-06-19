extends Node2D
class_name CameraController

@onready var camera: Camera2D = $Camera2D
const TILE_SIZE = 16
const CELL_WORLD := TILE_SIZE * 2   # 32px/cell — matches your existing min/max_world math

var map_width = 32
var map_height = 20
var edge_size = 64
var is_moving := false
var keyboard_direction := Vector2.ZERO
var lock_manual_input := false
var last_move_dir := Vector2.ZERO
var was_moving := false


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

func check_edge_scroll(mouse_pos: Vector2i):
	var viewport_size = get_viewport_rect().size
	var move_dir = Vector2i.ZERO

	if mouse_pos.x < edge_size:
		move_dir.x -= 1
	elif mouse_pos.x > viewport_size.x - edge_size:
		move_dir.x += 1
	
	if mouse_pos.y < edge_size:
		move_dir.y -= 1
	elif mouse_pos.y > viewport_size.y - edge_size:
		move_dir.y += 1
	
	if move_dir != Vector2i.ZERO:
		move_by_cell()
	
func move_by_cell():
	if is_moving: 
		return
	is_moving = true
	clamp_target_position()
	
	
func clamp_target_position():
	var viewport_size = get_viewport_rect().size
	var visible_size = viewport_size / camera.zoom
	var half_view = visible_size / 2
	target_position.x = clamp(
		target_position.x,
		min_world.x + half_view.x,
		max_world.x - half_view.x
	)
	target_position.y = clamp(
		target_position.y,
		min_world.y + half_view.y,
		max_world.y - half_view.y
	)
	
func refresh_bounds(grid: TileMapLayer):
	var used := grid.get_used_rect()
	min_world = Vector2(used.position) * CELL_WORLD
	max_world = Vector2(used.position + used.size) * CELL_WORLD
	clamp_target_position()
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float):
	if global_position.distance_to(target_position) < 1:
		global_position = target_position
		is_moving = false
	
	#Always scroll at least one cell, and never snap back.  
	keyboard_direction = Vector2.ZERO
	if not lock_manual_input:
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

	
	
	
	
	
	
	
	
