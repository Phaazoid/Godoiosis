extends Object
class_name RushdownArchetype

# First feel-testing instrument (#29): nearest enemy -> path -> attack. No enemy on the board ->
# every member still tries its fallback main actions (Reload/Rev) instead of doing nothing for
# the whole turn (AI generalization sweep, finding #3). Queues orders through SquadManager only
# (Law #3) -- queue_group_move reuses the same formation solver the player's group-move uses, so
# member positioning isn't AI-special-cased.
static func take_squad_turn(squad: Squad, board: BoardContext, squad_manager: SquadManager) -> void:
	var leader := squad.get_leader()
	# #571, and RUSHDOWN ONLY (dev, 2026-09-11): a defended point is the win button -- standing in
	# one ends the mission outright -- so a hostile rusher walks at the cargo instead of at the
	# nearest body. This changes the DESTINATION and nothing else: the ordinary main-action pass
	# still runs, so whatever is in reach on arrival still gets hit, and the squad is not suddenly
	# pacifist on the way there. No shipped board paints a DEFEND zone, so every existing one takes
	# the unchanged branch below.
	var cargo := _cargo_cells(leader, board)
	if not cargo.is_empty():
		var goal := _nearest_cargo_cell(leader, cargo, board)
		var approach := AITactics.closest_reachable_cell_to(leader, goal, board)
		if approach != leader.movement.cell:
			squad_manager.queue_group_move(squad, approach, board)
		AITactics.queue_main_actions_for_squad(squad, board, squad_manager)
		return
	var enemy := AITactics.choose_engagement_target(leader, board, squad_manager)
	if enemy != null:
		AITactics.engage(squad, enemy, board, squad_manager)
	else:
		AITactics.queue_main_actions_for_squad(squad, board, squad_manager)


# Every cell of every defended point, when this squad is one the cargo is in danger FROM. A DEFEND
# zone is implicitly the player's (#571 -- it carries no owner, because nothing ever takes it), so
# the gate is hostility to PLAYER: an ALLY squad walking its own side's cargo down would be absurd,
# and a PLAYER squad under AI control on a hotseat board has nothing to gain there either.
static func _cargo_cells(leader: Unit, board: BoardContext) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if board.zones == null or not Team.is_enemy(leader.get_faction(), Team.Faction.PLAYER):
		return cells
	for name in board.zones.zone_names_of(ZoneManager.Kind.DEFEND):
		cells.append_array(board.zones.cells_in(name))
	return cells


# Which cell of the cargo to walk at. NEAREST BY ROUTE, straight-line distance as the tie-break and
# as the fallback -- nearest_enemy's own ladder, for its reason: a cell two tiles off through a wall
# is further away than one eight tiles down an open corridor. The fallback is what matters here,
# because the player DEFENDING the point is exactly what makes every cell of it occupied, and an
# occupancy-blocked flood would otherwise report the whole objective unreachable and send the rusher
# back to hunting bodies. Getting as close as possible is closest_reachable_cell_to's job, not this
# one's. Ties keep the earlier cell (Law #1 -- zone paint order).
static func _nearest_cargo_cell(leader: Unit, cells: Array[Vector2i], board: BoardContext) -> Vector2i:
	var wanted: Dictionary = {}
	for cell in cells:
		wanted[cell] = true
	var route := RulesService.path_hops(leader.movement.cell, board, leader, -1, wanted, true)
	var best: Vector2i = cells[0]
	var best_hops: int = RulesService.UNREACHABLE
	var best_dist: int = GridUtils.manhattan_distance(leader.movement.cell, best)
	for cell in cells:
		var hops: int = route.get(cell, RulesService.UNREACHABLE)
		var dist: int = GridUtils.manhattan_distance(leader.movement.cell, cell)
		if hops < best_hops or (hops == best_hops and dist < best_dist):
			best = cell
			best_hops = hops
			best_dist = dist
	return best
