extends Object
class_name HoldArchetype

# Hold means "don't move," not "don't fight" -- attack anything already in range from the
# squad's current positions, but never reposition to chase.
static func take_squad_turn(squad: Squad, board: BoardContext, squad_manager: SquadManager) -> void:
	AITactics.queue_main_actions_for_squad(squad, board, squad_manager)
