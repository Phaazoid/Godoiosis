extends AIWeaponRoutine
class_name DrillWeaponRoutine

# Drill (#726): a drill with nothing to hit digs in where it stands -- ONCE. Burrow lays permanent
# COVER on the digger's cell and can_burrow() is unconditionally true, so with no rule an idle drill
# re-burrows the same covered cell every turn: a no-op deposit (TerrainStateManager.fold dedupes),
# but an order and an AI_PLAN_READ beat spent on nothing, forever.
#
# THE CELL IS THE PROJECTED DESTINATION, not movement.cell. The deposit lands where the digger ENDS
# (SquadManager.resolve_plan; pinned by test_cover_lands_where_the_digger_ends_up), and the fallback
# walk runs after the group move is queued -- so asking about the cell it is leaving is Law #4's
# exact drift: two cells for one question. Read through board.cover_def_at, the rules' one
# read-point for cover, never terrain_states directly.


func allows_preparation(unit: Unit, verb: BaseAction.ActionType, board: BoardContext) -> bool:
	if verb != BaseAction.ActionType.BURROW:
		return true
	return board.cover_def_at(unit.get_projected_destination()) == 0
