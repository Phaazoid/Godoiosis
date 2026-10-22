extends Object
class_name SquadCohesion

# The ONE definition of "may this squadmate stand here?" -- the leash that keeps a squad together.
# Extracted 2026-08-06 because ELEVEN sites hand-rolled it (the 2026-08-04 cohesion hole shipped
# exactly because the rule lived in many places and was relaxed at only one), then re-metered the
# same day for #151: cohesion is PATH DISTANCE over terrain the member can traverse, not Manhattan.
# Walls block cohesion -- you cannot order someone through solid rock you can't see or hear through.
# A squad that is Manhattan-close but split by a castle wall is not a squad, and pretending it was
# is what froze a Rushdown squad for a whole battle (#127).
#
# The metric is a bounded RulesService.path_hops walk from `center` (the leader's cell or projected
# destination), per-MEMBER because traversal is per-unit (#115): a Waterwalker's bubble crosses
# water, a future flyer's crosses cliffs. It deliberately uses the DEFAULT traversal rule -- never
# block_on_occupancy -- so an enemy body can never sever a squad (pinned by
# test_an_enemy_body_does_not_sever_the_cohesion_field).
#
# TWO FORMS, and keeping them consistent is the whole job: `in_range` decides (validator, solver,
# squad-up gates, the ejection sweep), `cells`/`field` draw and iterate (overlays, the solver's
# dilation). Both read one `field`, so they cannot drift -- pinned by
# tests/squad/test_squad_cohesion.gd.
#
# Cost: the walk is bounded at COH, so a field is ~2*COH^2 cells (~41 at COH 4) -- the depth-bounded
# shape docs/performance.md measured as cheaper than the compute_move_range call beside it. Callers
# in a loop over cells should hoist one field() and test membership.
#
# The range VALUE is the leader's COH stat (Squad.get_max_squad_range, #142), less what the cell it
# stands on blinds it with (reach_at, #1335): a leader in smoke can't see, so it holds its squad
# closer. This file is the leash's only production reader, which is why that half lives here and every
# caller gets it for free. The BOARD is a parameter on purpose: terrain state changes mid-battle
# (FROZEN water melts, smoke drifts), so a field is only ever as fresh as the BoardContext handed in
# -- build it at query time, never store one.

static func field(squad: Squad, center: Vector2i, member: Unit, board: BoardContext) -> Dictionary:
	return field_of(squad.leader, center, member, board)

static func in_range(squad: Squad, center: Vector2i, member: Unit, cell: Vector2i, board: BoardContext) -> bool:
	return field(squad, center, member, board).has(cell)

# The same two, keyed on a LEADER rather than a squad (#367): SplitForecast asks about a successor
# the plan has not appointed yet, and a leader is all the range ever read off the squad.
static func field_of(leader: Unit, center: Vector2i, member: Unit, board: BoardContext) -> Dictionary:
	return field_within(reach_at(leader, center, board), center, member, board)

# The walk itself at a GIVEN reach, cell -> path distance. For a caller that walks from somewhere other
# than the leader's cell (GroupMoveSolver.stranding walks from the member's, path distance being
# symmetric) and so must compare each distance with reach_at at the leader's end itself.
static func field_within(reach: int, center: Vector2i, member: Unit, board: BoardContext) -> Dictionary:
	return RulesService.path_hops(center, board, member, maxi(reach, 0))

# How far this leader's leash reaches when it stands at `center`: its COH, plus the COH change of every
# state the gas there gives while standing in it (GasRules.states_while_standing) that it does not
# already HOLD -- a held state is already in its COH, so a smoked leader in smoke is docked once.
static func reach_at(leader: Unit, center: Vector2i, board: BoardContext) -> int:
	var reach := Squad.range_of(leader)
	if board == null:
		return reach
	for state: Elemental.State in GasRules.states_while_standing(board.gas_at(center)):
		if not leader.element_states.has(state):
			reach += int(Elemental.paired_stat_mods(state).get(Stats.Stat.COH, 0))
	return maxi(reach, 0)   # floored: a negative bound is path_hops' UNBOUNDED, a board-wide leash

static func in_range_of(leader: Unit, center: Vector2i, member: Unit, cell: Vector2i, board: BoardContext) -> bool:
	return field_of(leader, center, member, board).has(cell)

# Every cell in `member`'s bubble, INCLUDING the center -- callers that must exclude it (the
# squad-up overlay wants somewhere to put a recruit) filter it themselves, because "in the bubble"
# and "a legal destination" are different questions and only the first one lives here.
static func cells(squad: Squad, center: Vector2i, member: Unit, board: BoardContext) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in field(squad, center, member, board):
		result.append(cell)
	return result
