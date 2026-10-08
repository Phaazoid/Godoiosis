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

# What the END OF TURN pass will do to this squad's own units (#419) — derived LAST, after
# everything above, because that is when it happens. Its own list for the reason watch_shots is:
# nothing walking `attacks` may treat a tile's damage as an attack.
var tile_hits: Array[TileHitAction] = []

# Who the pass's own terrain dropped into the water (#922), in the order they went under. Its own list
# for tile_hits' reason, and each is stamped with its MOMENT, which is when both execution twins play it.
var sinks: Array[SinkAction] = []

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


# WHEN each of those shots plays (#567), answered once for the surfaces that ask — OrderExecutor,
# which plays them, and BeatSheet, which mirrors it. The THREE partitions are total and disjoint:
# every shot carries a moment, so every shot plays exactly once. #1003 added the third; keep that
# property when adding a fourth, or a shot plays twice or not at all.

# The shots a WALK walked into: each halts its mover mid-path while it plays.
func mid_walk_shots() -> Array[AttackAction]:
	var shots: Array[AttackAction] = []
	for shot in watch_shots:
		if shot.triggered_at_step >= 0:
			shots.append(shot)
	return shots


# The walk phase as both hosts play it (#567, #46): one entry per moment a walk halts at, in the order
# the resolve made them -- the walk, the step, whether the walk's own soaking lands there, and every
# shot that halt set off (a pinball chain included, since the cascade shares the moment that started
# it). `moves` is the squad's moves in queue order, which IS that order: resolve_move walks the queue
# one move at a time, and every shot a walk sets off is stamped during its own walk.
#
# A SOAKING (#884) is a moment only when a walk-phase shot lands on that walker: its order against
# those shots is then the outcome, so it plays where the resolve soaked it, before that step's shots.
# A soaking nothing lands on keeps to the walk's end, so a ford nobody fires at walks as it always has.
func walk_moments(moves: Array) -> Array[Dictionary]:
	var shots := mid_walk_shots()
	var struck: Dictionary[Unit, bool] = {}
	for shot in shots:
		if shot.target != null:
			struck[shot.target] = true
	var moments: Array[Dictionary] = []
	for action in moves:
		var move := action as MoveAction
		if move == null:
			continue
		var soak := move.resolved_soak_step if struck.has(move.actor) else -1
		for shot in shots:
			if shot.triggered_during != move:
				continue
			var step: int = shot.triggered_at_step
			if soak >= 0 and step >= soak:
				moments.append({"move": move, "step": soak, "soak": true, "shots": []})
				soak = -1
			if not moments.is_empty() and moments[-1]["move"] == move and int(moments[-1]["step"]) == step:
				(moments[-1]["shots"] as Array).append(shot)
				continue
			moments.append({"move": move, "step": step, "soak": false, "shots": [shot]})
		if soak >= 0:
			moments.append({"move": move, "step": soak, "soak": true, "shots": []})
	return moments


# ...and the shots an order in the SIDE-CHANNEL TAIL set off (#1003) — today an Overwatch arming
# onto a cell an enemy already occupies. They play in the tail, after the counters, because that is
# where the order that fired them plays; splitting them out of attack_playback() is what keeps the
# resolve order and the playback order the same order.
func coda_shots() -> Array[AttackAction]:
	var shots: Array[AttackAction] = []
	for shot in watch_shots:
		if shot.triggered_at_step < 0 and _plays_in_the_tail(shot):
			shots.append(shot)
	return shots


# The shots ONE order set off, in trigger order — the one answer to that question, asked by the
# executor (which interleaves them behind their order), BeatSheet (which gives each its beat) and
# the queue panel (which indents a row under the order). Spelled three times it would be three
# rules about what a shot belongs to.
func shots_fired_during(order: BaseAction) -> Array[AttackAction]:
	var shots: Array[AttackAction] = []
	if order == null:
		return shots
	for shot in watch_shots:
		if shot.triggered_during == order:
			shots.append(shot)
	return shots


# The sinkings that play at one moment (#922) -- the executor's and the Play API's one read.
func sinks_at(moment: SinkAction.Moment) -> Array[SinkAction]:
	var at: Array[SinkAction] = []
	for sink in sinks:
		if sink.moment == moment:
			at.append(sink)
	return at


# ...and the ones a row's deposit caused, which the queue panel hangs under that row.
func sinks_caused_by(action: BaseAction) -> Array[SinkAction]:
	var caused: Array[SinkAction] = []
	if action == null:
		return caused
	for sink in sinks:
		if sink.cause == action:
			caused.append(sink)
	return caused


func has_sunk(unit: Unit) -> bool:
	for sink in sinks:
		if sink.actor == unit:
			return true
	return false


# The partition boundary, asked of the MOMENT rather than of the verb: a shot whose order executes
# in the tail plays in the tail. Reading SIDE_CHANNEL_ORDER rather than naming OVERWATCH is what
# makes a second tail verb that can fire one need no edit here.
static func _plays_in_the_tail(shot: AttackAction) -> bool:
	var during := shot.triggered_during
	return during != null and BaseAction.SIDE_CHANNEL_ORDER.has(during.action_type)


# ...and the attack phase's own playback: `attacks` with every remaining shot spliced in after the
# volley member whose shove set it off. A FRESH array each call and never written back — a triggered
# shot in `attacks` would be counter-bait, which is the whole reason watch_shots is its own list.
#
# Spliced on the ACTION OBJECT rather than on an index into `attacks`: an index is a copy of a
# position and goes stale silently. A shot whose moment is not in this list falls to the end, so a
# moment nobody could honour still plays instead of vanishing.
func attack_playback() -> Array[AttackAction]:
	var trailing: Array[AttackAction] = []
	var following: Dictionary[AttackAction, Array] = {}
	for shot in watch_shots:
		if shot.triggered_at_step >= 0 or _plays_in_the_tail(shot):
			continue
		var after := shot.triggered_during as AttackAction
		if after == null or not attacks.has(after):
			trailing.append(shot)
			continue
		if not following.has(after):
			following[after] = []
		following[after].append(shot)

	var played: Array[AttackAction] = []
	for attack in attacks:
		played.append(attack)
		for shot: AttackAction in following.get(attack, []):
			played.append(shot)
	played.append_array(trailing)
	return played

# What this pass leaves on the ground, one entry per cell AND state ({"cell", "state"}) or cell AND
# gas kind ({"cell", "gas"}), so two attacks igniting one cell count once while a cell gaining two
# states counts twice. The board ghosts exactly this (game._preview_plan_effects) and the Play API's
# preview prints it (#46): one answer to what the plan deposits.
func pending_deposits() -> Array[Dictionary]:
	var deposits: Array[Dictionary] = []
	var seen := {}
	for effect in cell_effects:
		for state in effect.states_added:
			var key := Vector3i(effect.cell.x, effect.cell.y, state)
			if seen.has(key):
				continue
			seen[key] = true
			deposits.append({"cell": effect.cell, "state": state})
		for kind: Gas.Kind in effect.gas_added:
			var gas_key := "%s/%s/gas%d" % [effect.cell.x, effect.cell.y, kind]
			if seen.has(gas_key):
				continue
			seen[gas_key] = true
			deposits.append({"cell": effect.cell, "gas": kind})
	return deposits

# The threaded hypothetical the pass resolved through (Unit -> PlanResolver._Hypo), kept on the
# plan instead of dying as a resolver local (#124): "what state does this pass LEAVE a unit in?"
# is a question the resolver already answered, and re-deriving it from outcomes would be a second
# ladder. Read through PlanResolver.projected_hp / projected_lifecycle, never written after the pass.
var hypo: Dictionary = {}
