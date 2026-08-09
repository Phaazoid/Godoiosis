extends RefCounted
class_name ResolvedPlan

# The output of one resolver pass (resolution-pipeline.md R1/R8): the player attacks
# (in queue order) and the derived counters, each with its `.resolved` outcome filled.
# Preview AND execution both consume THIS one plan (R3). Moves carry no outcome, so
# they're not here — callers read them straight from the queue.

var attacks: Array[AttackAction] = []
var counters: Array[CounterAttackAction] = []

# Terrain consequences derived this pass (#50). Empty unless the resolver ran with a board.
var cell_effects: Array[ResolvedCellEffect] = []

# The threaded hypothetical the pass resolved through (Unit -> PlanResolver._Hypo), kept on the
# plan instead of dying as a resolver local (#124): "what state does this pass LEAVE a unit in?"
# is a question the resolver already answered, and re-deriving it from outcomes would be a second
# ladder. Read through PlanResolver.projected_hp / projected_lifecycle, never written after the pass.
var hypo: Dictionary = {}
