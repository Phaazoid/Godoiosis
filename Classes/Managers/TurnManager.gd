extends Node2D
class_name TurnManager

enum TurnPhase {
	PLAYER,
	ENEMY
}

signal turn_started(phase)

@export var current_turn : TurnPhase = TurnPhase.PLAYER


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	start_turn(TurnPhase.PLAYER)

func start_turn(phase: TurnPhase):
	current_turn = phase
	emit_signal("turn_started", phase)
	
func is_player_turn() -> bool:
	return current_turn == TurnPhase.PLAYER
	
func end_turn():
	match current_turn:
		TurnPhase.PLAYER: #Later this will need to support other teams as well
			start_turn(TurnPhase.ENEMY)
		TurnPhase.ENEMY:
			current_turn = TurnPhase.PLAYER
			start_turn(TurnPhase.PLAYER)
