extends Object
class_name RushdownArchetype

# First feel-testing instrument (#29): nearest enemy -> path -> attack. Queues orders through
# SquadManager only (Law #3) -- queue_group_move reuses the same formation solver the
# player's group-move uses, so member positioning isn't AI-special-cased.
static func take_squad_turn(squad: Squad, board: BoardContext, squad_manager: SquadManager) -> void:
	var leader := squad.get_leader()
	var enemy := AITactics.nearest_enemy(leader, board)
	if enemy == null:
		return

	AITactics.engage(squad, enemy, board, squad_manager)
