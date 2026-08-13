# The Battle3D shell (#215 / #176 stage 4a): the hidden-2D-game-as-authority
# architecture's first scene. Hosts the REAL Main.tscn with its 2D view hidden —
# the full sim runs untouched — while BoardMirror/UnitMirror render it as an
# HD-2D diorama. 4a is READ-ONLY: auto_play loads Prolog through the real funnel
# and sets both factions AI, so the battle demos itself. Input lands at 4b, the
# 2D/3D chooser + viewport power savings at 4d.
#
# Declared demo-driver liberty: load_mission calls MissionController's private
# _on_mission_chosen — the real mission-entry funnel. 4b formalizes that seam.
extends Node3D

@export var auto_play := true
@export var mission_path := "res://Scenarios/missions/Prolog.tres"

@onready var _main: Node = $Main
@onready var _board_mirror: BoardMirror = $BoardMirror
@onready var _unit_mirror: UnitMirror = $UnitMirror
@onready var _rig: Node3D = $CameraRig

var game: Node2D


func _ready() -> void:
	game = _main.get_node("GameContainer/GameView/Game")
	(_main.get_node("GameContainer") as Control).visible = false
	var dev_overlay: Node = _main.get_node_or_null("DevOverlay")
	if dev_overlay is Window:
		(dev_overlay as Window).visible = false
	_board_mirror.board = $Board
	_unit_mirror.units_root = game.units_root
	game.turn_manager.turn_started.connect(_on_turn_started)
	if auto_play:
		_start.call_deferred()


func _start() -> void:
	await get_tree().process_frame  # let the hidden Mission Select finish its deferred open
	load_mission(mission_path)
	var both: Array[Team.Faction] = [Team.Faction.PLAYER, Team.Faction.ENEMY]
	game.ai_controller.set_ai_factions(both)  # AI-vs-AI: the diorama plays itself


func load_mission(path: String) -> void:
	game.mission_controller._on_mission_chosen(path)
	rebuild()
	_fit_camera()


func rebuild() -> void:
	_board_mirror.rebuild(game.grid, game.terrain_states.to_state_dict())


func _on_turn_started(_faction: int) -> void:
	_board_mirror.refresh_states(game.terrain_states.to_state_dict())


func _fit_camera() -> void:
	var rect: Rect2i = game.grid.get_used_rect()
	var center := Vector2(rect.position) + Vector2(rect.size) * 0.5
	_rig.position = Vector3(center.x, 1.0, center.y)
	_rig.set_zoom(maxf(float(rect.size.x), float(rect.size.y)) * 1.05)
