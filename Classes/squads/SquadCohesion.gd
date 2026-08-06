extends Object
class_name SquadCohesion

# The ONE definition of "is this cell within a squad's cohesion range of its leader?" -- the leash
# that keeps a squad together. Extracted here because ELEVEN sites were asking it and only two went
# through SquadPlanValidator.cohesion_ok; the other nine hand-rolled the same arithmetic (the
# validator, the solver's stay-put check and its dilation, compute_move_range's squad_unreachable
# clamp, the squad-up/join gates in SquadManager and the Play API, and three overlay draws). Nine
# independent copies of a rule is how the 2026-08-04 cohesion hole shipped: relaxing it at the one
# surface that motivated the change left the others enforcing the old answer.
#
# TWO FORMS, and keeping them consistent is the whole job: `in_range` decides, `cells` draws and
# iterates. They must accept exactly the same set or the overlay paints a tile the validator
# refuses -- pinned by tests/squad/test_squad_cohesion.gd.
#
# The metric is MANHATTAN distance today, and that is the next thing to change: walls do not block
# it, so a squad can be "cohesive" while split by a castle wall, which is what let a Rushdown squad
# freeze for a whole battle (#127 -> #151). Everything above exists so that swap is one edit here
# instead of eleven. #151 also adds the parameters this signature deliberately lacks -- the member
# and a BoardContext -- because path distance is per-unit (Waterwalk now, flight later).
#
# The range VALUE is the leader's COH stat (Squad.get_max_squad_range, #142); nothing here knows or
# cares where the number comes from.

static func in_range(squad: Squad, leader_cell: Vector2i, cell: Vector2i) -> bool:
	return GridUtils.manhattan_distance(cell, leader_cell) <= squad.get_max_squad_range()

# Every cell in the bubble, INCLUDING the leader's own -- callers that must exclude it (the
# squad-up overlay wants somewhere to put a recruit) filter it themselves, because "in the bubble"
# and "a legal destination" are different questions and only the first one lives here.
static func cells(squad: Squad, leader_cell: Vector2i) -> Array[Vector2i]:
	return GridUtils.cells_within_manhattan_range(leader_cell, squad.get_max_squad_range())
