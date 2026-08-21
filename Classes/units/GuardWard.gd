extends RefCounted
class_name GuardWard

# One armed Guard (#414, docs/design/standing-reactions.md): a blocker, the unit it is bodyguarding,
# and how far apart the pair may stand. The PAIR is the fact, so both ends live here rather than the
# blocker being implied by wherever the object is filed -- `Unit.guard` is the index, this is the
# answer, and a resolver pass can carry a list of these with nothing else attached.
#
# Deliberately NOT a StatEffect: substitution is instantaneous within one resolution (Iron Will's
# shape), so nothing here ticks. The lifetime is the shared standing-reaction grammar -- arms at its
# queue slot, absorbs exactly one trigger, lapses when the owner's faction's next turn begins
# (Unit.lapse_guard, called from the turn-start tick pass).

var blocker: Unit          # takes the hit
var ward: Unit             # the unit being protected
var guard_range: int = 1   # authored on the granting content; Abilities.GUARD_BASE_RANGE by default
var spent := false         # absorbed its one trigger

# Arm order, so "earlier-queued absorbs first" holds ACROSS passes and not just within one: two
# blockers can ward the same unit from different squads' passes, and board-iteration order is not
# an arming order. Within a single pass the resolver's own queue walk already orders them.
var sequence: int = 0

static var _next_sequence := 1


# A pair with no arm stamp: the resolver's projection of a Guard that is still only a queued order.
# Its position in ResolvedPlan.guards is its order, so it needs no sequence of its own.
static func make(guarding_unit: Unit, warded_unit: Unit, ward_range: int) -> GuardWard:
	var w := GuardWard.new()
	w.blocker = guarding_unit
	w.ward = warded_unit
	w.guard_range = ward_range
	return w

# A ward that is actually going live on a unit, stamped with its arm order.
static func arm(guarding_unit: Unit, warded_unit: Unit, ward_range: int) -> GuardWard:
	var w := make(guarding_unit, warded_unit, ward_range)
	w.sequence = _next_sequence
	_next_sequence += 1
	return w

# The resolver's working copy for one pass (ResolvedPlan.guards). The pass marks copies spent as
# they absorb; the live ward is spent by EXECUTION, once, off the outcome that used it.
func copy() -> GuardWard:
	var w := make(blocker, ward, guard_range)
	w.spent = spent
	w.sequence = sequence
	return w

# Both ends still on the board and the pair still pointing at each other. Says nothing about
# position or lifecycle -- those are the caller's stage (see PlanResolver._guard_for).
func is_intact() -> bool:
	return blocker != null and ward != null \
		and is_instance_valid(blocker) and is_instance_valid(ward) \
		and not blocker.is_queued_for_deletion() and not ward.is_queued_for_deletion()

# THE range predicate, and it takes the positional fact rather than reading it (the
# SquadPlanValidator.aim_whiffs shape): the resolver feeds THREADED cells so a mid-pass shove moves
# the answer, while the validator and the menu feed PROJECTED cells off an order that has no ward
# object yet. One rule, three positional sources, no second spelling of "is the pair together".
# Distance only -- no line of sight and no height gate: Guard is a stance, not an attack.
static func in_range(blocker_cell: Vector2i, ward_cell: Vector2i, ward_range: int) -> bool:
	return GridUtils.manhattan_distance(blocker_cell, ward_cell) <= ward_range

func pair_in_range(blocker_cell: Vector2i, ward_cell: Vector2i) -> bool:
	return in_range(blocker_cell, ward_cell, guard_range)
