# Stage-1 proof (#205): the picking seam driven live in the look-dev scene. Every
# frame: mouse -> camera ray -> BoardPicker -> a highlight quad glued to the picked
# cell's standing point + a cell readout. No game logic; the seam and its demo only.
# Column tops are built once from the GridMap (the board is static here) — a live
# board would rebuild on change (stage 2+ business).
extends Node3D

@onready var _board: GridMap = $"../Board"
@onready var _camera: Camera3D = $"../CameraRig/Pitch/Camera"
@onready var _highlight: MeshInstance3D = $Highlight
@onready var _readout: Label = $"../UI/CellReadout"

var _tops: Dictionary[Vector2i, int] = {}


func _ready() -> void:
	_tops = BoardPicker.column_tops_from(_board)


func _process(_delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	var cell := BoardPicker.pick_cell(
		_camera.project_ray_origin(mouse), _camera.project_ray_normal(mouse), _tops)
	if cell == BoardSpace.NO_CELL:
		_highlight.visible = false
		_readout.text = ""
		return
	_highlight.visible = true
	_highlight.global_position = BoardSpace.standing_point(cell) + Vector3(0.0, 0.02, 0.0)
	_readout.text = "cell (%d, %d, %d)" % [cell.x, cell.y, cell.z]
