extends Object
class_name HoldArchetype

# Hold means "don't move," not "don't fight" -- attack anything already in range from the
# squad's current positions, but never reposition to chase.
static func take_squad_turn(squad: Squad, board: BoardContext, squad_manager: SquadManager) -> void:
	for member in squad.get_members():
		AITactics.queue_main_action(member, board, squad_manager, AIArchetype.main_action_priority(squad.archetype))
