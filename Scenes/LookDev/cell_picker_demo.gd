# Stage-1 proof (#205): the picking seam driven live in the look-dev scene. Every
# frame: mouse -> camera ray -> BoardPicker -> the hover marker (BoardOverlays'
# voxel corner bracket since #213) + a cell readout. No game logic; the seam and
# its demo only. Column tops are built once from the GridMap (the board is static
# here) — a live board would rebuild on change (stage 4 business).
extends Node3D

@onready var _board: GridMap = $"../Board"
@onready var _camera: Camera3D = $"../CameraRig/Pitch/Camera"
@onready var _overlays: BoardOverlays = $"../BoardOverlays"
@onready var _readout: Label = $"../UI/CellReadout"

var _tops: Dictionary[Vector2i, int] = {}


func _ready() -> void:
	_tops = BoardPicker.column_tops_from(_board)


func _process(_delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	var cell := BoardPicker.pick_at(_camera, mouse, _tops)
	if cell == BoardSpace.NO_CELL:
		_overlays.clear(BoardOverlays.Layer.HOVER)
		_readout.text = ""
		return
	_overlays.set_cells(BoardOverlays.Layer.HOVER, [cell])
	_readout.text = "cell (%d, %d, %d)" % [cell.x, cell.y, cell.z]
