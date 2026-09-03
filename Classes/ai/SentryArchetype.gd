extends Object
class_name SentryArchetype

# Zone-bound guard (#29): holds its post until an enemy stands in the squad's painted
# zone, then rushes it down with every destination clamped to the zone -- it can't be lured
# out. When the zone empties it walks back to its post (the leader's scenario spawn cell)
# and stands down. Re-derived fresh each turn: no engaged/returning state is stored.
# AT the post it still takes the fallback main actions -- reload, rev, burrow -- never an attack
# (#726, dev 2026-09-03: "at the post only").
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

	# `allowed` as well as `zone_set`: the leash decides which cells this sentry may fight FROM, and
	# a target it cannot legally walk to is not one it can engage.
	var intruder := AITactics.choose_engagement_target(leader, board, squad_manager, zone_set, allowed)
	if intruder != null:
		AITactics.engage(squad, intruder, board, squad_manager, allowed)
		return

	if leader.movement.cell != squad.home_cell:
		var destination := AITactics.closest_reachable_cell_to(leader, squad.home_cell, board, allowed)
		if destination != leader.movement.cell:
			squad_manager.queue_group_move(squad, destination, board, allowed)
		return

	# AT THE POST with nobody in the zone: the fallback verbs, never ATTACK -- an enemy in reach but
	# outside the zone is bait, and the lure-proofing above still holds. A drill digs in, a
	# chainsword revs, a carbine tops off; this branch queued nothing before #726, so an idle sentry
	# never reloaded either. The walk-home branch stays silent on purpose: entrenching a cell you
	# are leaving is waste.
	AITactics.queue_fallback_actions_for_squad(squad, board, squad_manager)


static func _zone_set(squad: Squad, board: BoardContext) -> Dictionary:
	var cells := {}
	if squad.zone_name == "" or board.zones == null:
		return cells
	for cell in board.zones.cells_in(squad.zone_name):
		cells[cell] = true
	return cells
