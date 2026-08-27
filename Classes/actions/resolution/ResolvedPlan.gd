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

# The Guards this pass can see (#414), in ARM ORDER — so a stacked pair absorbs earliest-first with
# no precedence rule to write down. Two sources, one list: wards armed in an EARLIER pass (copied
# off the units, oldest sequence first) and Guards queued in THIS plan, appended by
# SquadManager.resolve_plan as its queue walk reaches each one. That append point IS "arms at its
# queue slot" — an attack earlier in the queue simply never sees the entry.
#
# COPIES, never the live GuardWard: the pass marks them spent as they absorb, and the resolver may
# not touch live state (R2). Empty by default, so a plan-less caller resolves exactly as before.
var guards: Array[GuardWard] = []

# The standing watches this pass can see (#413), in ARM ORDER, and COPIES for the same R2 reason the
# wards are: the pass marks them spent as they fire, execution spends the live one. Two sources, one
# list, exactly as guards has — watches armed in an EARLIER pass (the enemy-phase case, and the whole
# point of the mechanic) plus any queued in THIS plan, appended by SquadManager.resolve_plan's own
# queue walk when it reaches their slot. That append point IS "arms at its queue slot", which is what
# makes the shove combo sequence-able: arm the watch, THEN knock them into it.
var watches: Array[Watch] = []

# The shots those watches fired, in trigger order. Deliberately NOT in `attacks`:
# calculate_reactions_for_squad reads that list, so keeping derived shots out of it is how "a
# triggered shot draws no counter" holds structurally instead of by a filter somebody must remember.
var watch_shots: Array[AttackAction] = []

# The threaded hypothetical the pass resolved through (Unit -> PlanResolver._Hypo), kept on the
# plan instead of dying as a resolver local (#124): "what state does this pass LEAVE a unit in?"
# is a question the resolver already answered, and re-deriving it from outcomes would be a second
# ladder. Read through PlanResolver.projected_hp / projected_lifecycle, never written after the pass.
var hypo: Dictionary = {}
