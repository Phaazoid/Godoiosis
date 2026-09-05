extends RefCounted
class_name Watch

# One armed Overwatch (#413, docs/design/standing-reactions.md): a watcher, the cell it aimed FROM,
# the cells it aimed AT, and the attack that fires. GuardWard's sibling — `Unit.watch` is the index,
# this is the answer, and a resolver pass can carry a list of these with nothing else attached.
#
# The FOOTPRINT is frozen here and nowhere earlier. A queued OverwatchAction re-derives its cells
# every resolve, from the actor's projected cell and the board's terrain, exactly like a stored
# attack aim does (#15), so re-planning the walk that precedes it moves the preview honestly; the
# geometry only becomes a fact when the order executes, arming the cells THAT PASS stamped (#756 —
# the resolve owns them, because a spread's shape is a question about the board and no action can
# reach one at execute time). What is frozen at DECLARE is the attack and the aim
# (OverwatchAction's `fired_attack` / `target_cell` stamps).
#
# Lifetime is the shared standing-reaction grammar: arms at its queue slot, absorbs exactly one
# trigger, lapses when the owner's faction's next turn begins (Unit.lapse_watch, from the turn-start
# tick pass) — plus the ANCHOR rule, which is Overwatch's alone: the footprint is geometry aimed
# from one cell, so the watcher leaving that cell drops the watch however it happened.

var watcher: Unit                    # who is standing watch
var anchor_cell: Vector2i            # the cell it was aimed FROM; leaving it drops the watch
var aim_cell: Vector2i               # the cell it was aimed AT — the shot's target cell when it fires
var footprint: Array[Vector2i] = []  # the watched cells, frozen
var attack: AttackData = null        # what fires; stamped at declare, never re-picked
var spent := false                   # absorbed its one trigger

# Arm order, so "earlier-armed fires first" holds ACROSS passes and not merely inside one: two
# watchers can arm on different factions' turns, and board-iteration order is not an arming order.
# Within a single pass the resolver's own queue walk already orders them.
var sequence: int = 0

static var _next_sequence := 1


# A watch with no arm stamp: the resolver's projection of an order that is still only queued.
# Its position in the pass's list is its order, so it needs no sequence of its own.
static func make(watching_unit: Unit, origin: Vector2i, aim: Vector2i,
		watched_cells: Array[Vector2i], fired_attack: AttackData) -> Watch:
	var w := Watch.new()
	w.watcher = watching_unit
	w.anchor_cell = origin
	w.aim_cell = aim
	w.footprint = watched_cells.duplicate()
	w.attack = fired_attack
	return w


# A watch that is actually going live on a unit, stamped with its arm order.
static func arm(watching_unit: Unit, origin: Vector2i, aim: Vector2i,
		watched_cells: Array[Vector2i], fired_attack: AttackData) -> Watch:
	var w := make(watching_unit, origin, aim, watched_cells, fired_attack)
	w.sequence = _next_sequence
	_next_sequence += 1
	return w


# The resolver's working copy for one pass. The pass marks copies spent as they fire; the live
# watch is spent by EXECUTION, once, off the outcome that used it (GuardWard's rule).
func copy() -> Watch:
	var w := make(watcher, anchor_cell, aim_cell, footprint, attack)
	w.spent = spent
	w.sequence = sequence
	return w


# The watcher is still on the board and still pointing at something. Says nothing about position or
# lifecycle — those are the caller's stage, the same split GuardWard.is_intact() makes.
func is_intact() -> bool:
	return watcher != null and is_instance_valid(watcher) \
		and not watcher.is_queued_for_deletion() \
		and attack != null and not footprint.is_empty()


# THE anchor predicate, and it takes the positional fact rather than reading it (GuardWard.in_range's
# shape): the resolver feeds a THREADED cell so a mid-pass shove of the WATCHER really does drop the
# watch, while a redraw feeds the live one. One rule, two positional sources.
func is_anchored(watcher_cell: Vector2i) -> bool:
	return watcher_cell == anchor_cell


func covers(cell: Vector2i) -> bool:
	return footprint.has(cell)
