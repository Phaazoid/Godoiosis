extends Object
class_name SentryArchetype

# Zone-bound guard (#29): idles at its post until an enemy stands in the squad's painted
# zone, then rushes it down with every destination clamped to the zone -- it can't be lured
# out. When the zone empties it walks back to its post (the leader's scenario spawn cell)
# and stands down. Re-derived fresh each turn: no engaged/returning state is stored.
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

	var intruder := AITactics.nearest_enemy(leader, board, zone_set)
	if intruder != null:
		var destination := AITactics.best_attack_destination(leader, intruder, board, allowed)
		if destination != leader.movement.cell:
			squad_manager.queue_group_move(squad, destination, board, allowed)
		for member in squad.get_members():
			AITactics.attack_if_possible(member, board, squad_manager)
		return

	if leader.movement.cell != squad.home_cell:
		var destination := AITactics.closest_reachable_cell_to(leader, squad.home_cell, board, allowed)
		if destination != leader.movement.cell:
			squad_manager.queue_group_move(squad, destination, board, allowed)

static func _zone_set(squad: Squad, board: BoardContext) -> Dictionary:
	var cells := {}
	if squad.zone_name == "" or board.zones == null:
		return cells
	for cell in board.zones.cells_in(squad.zone_name):
		cells[cell] = true
	return cells
