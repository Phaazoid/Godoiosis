extends Object
class_name SentryArchetype

# Zone-bound guard (#29). Its painted zone limits where it WALKS, never what it hits (#1377, dev
# 2026-10-21): every destination is clamped to zone∪post, and it fights anyone it can attack this turn
# from there, wherever that enemy stands. With nobody in reach it pursues an intruder inside the zone;
# with nobody there either it walks back to its post (the leader's scenario spawn cell), and at the post
# it attacks whatever is in reach. Re-derived fresh each turn: no engaged/returning state is stored.
static func take_squad_turn(squad: Squad, board: BoardContext, squad_manager: SquadManager) -> void:
	var leader := squad.get_leader()
	if squad.home_cell == Squad.NO_HOME:
		squad.home_cell = leader.movement.cell

	var zone_set := _zone_set(squad, board)
	if zone_set.is_empty():
		# No zone assigned (or it was fully erased): guard in place.
		HoldArchetype.take_squad_turn(squad, board, squad_manager)
		return

	var allowed := zone_set.duplicate()
	allowed[squad.home_cell] = true   # the post counts as inside even if painted over

	# `allowed` is the footing -- the cells this sentry may fight FROM -- and the only leash engagement
	# reads. `zone_set` is asked by pursuit alone: with nobody to hit this turn it walks at an intruder
	# inside its zone, never at anyone outside it.
	var target := AITactics.choose_engagement_target(leader, board, squad_manager, zone_set, allowed)
	if target != null:
		AITactics.engage(squad, target, board, squad_manager, allowed)
		return

	if leader.movement.cell != squad.home_cell:
		var destination := AITactics.closest_reachable_cell_to(leader, squad.home_cell, board, allowed)
		if destination != leader.movement.cell:
			AITactics.group_move(squad, destination, board, squad_manager, allowed)
		return

	# AT THE POST with nobody to engage: whatever a member can hit from where it stands (a longer attack
	# than the one the fork reads included), then the fallback verbs -- a drill digs in, a chainsword
	# revs, a carbine tops off (#726). The walk-home branch stays silent on purpose: entrenching a cell
	# you are leaving is waste.
	AITactics.queue_main_actions_for_squad(squad, board, squad_manager)


static func _zone_set(squad: Squad, board: BoardContext) -> Dictionary:
	var cells := {}
	if squad.zone_name == "" or board.zones == null:
		return cells
	for cell in board.zones.cells_in(squad.zone_name):
		cells[cell] = true
	return cells
