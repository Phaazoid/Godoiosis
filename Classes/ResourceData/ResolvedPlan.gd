extends RefCounted
class_name ResolvedPlan

# The output of one resolver pass (resolution-pipeline.md R1/R8): the player attacks
# (in queue order) and the derived counters, each with its `.resolved` outcome filled.
# Preview AND execution both consume THIS one plan (R3). Moves carry no outcome, so
# they're not here — callers read them straight from the queue.

var attacks: Array[AttackAction] = []
var counters: Array[CounterAttackAction] = []
