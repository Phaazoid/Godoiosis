extends Object
class_name BalancedArchetype

# BALANCED (#1220; rulings 11, 13, 14, 18 on #117): the squad that weighs the fight before it walks
# into it. Rushdown pursues the NEAREST enemy when nobody is in reach; this one pursues the nearest it
# can hit without an answer, and only then the nearest at all. With somebody in reach it takes the best
# exchange anywhere, as Rushdown does. Re-picked every turn -- nothing is remembered.
#
# It is the one archetype that weighs SAFETY: where two destinations are otherwise equal (both can
# attack, or neither, and the route is as long), it takes the one the fewest enemies can reach next
# turn. The action list is Hold's and Sentry's whole list, so it rescues, watches and guards.
static func take_squad_turn(squad: Squad, board: BoardContext, squad_manager: SquadManager) -> void:
	var leader := squad.get_leader()
	if AITactics.regroup_walk(squad, board, squad_manager):   # #1230: a stray with nobody to fight
		return
	var enemy := AITactics.choose_balanced_target(leader, board, squad_manager)
	if enemy != null:
		AITactics.engage(squad, enemy, board, squad_manager, null, null, true)
	else:
		AITactics.queue_main_actions_for_squad(squad, board, squad_manager)
