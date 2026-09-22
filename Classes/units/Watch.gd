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
var footprint: Array[Vector2i] = []  # the watched cells, frozen -- its paths back to back (#1057)
# Where each path in `footprint` ends -- AttackShape's flat pair. EMPTY means ONE path, the whole
# footprint in order, which is what a watch saved before #1057 was: every watch is single-target
# (#1040), so a saved line reads back as the line it always was, nearest first.
var path_lengths: Array[int] = []
var attack: AttackData = null        # what fires; stamped at declare, never re-picked
var spent := false                   # absorbed its one trigger
# Broken by a blow (#810, dev 2026-09-09): the watcher was hit, so the watch is off. A SECOND fact
# beside `spent`, not a reuse of it -- "you took your shot" and "it was shot off you" are different
# endings, and the shared grammar names three of them now (triggered / cancelled / lapsed). Both
# stop the watch firing; neither gives the reaction back, which is Unit.is_standing_watch's business
# and deliberately reads past both.
var cancelled := false

# Arm order, so "earlier-armed fires first" holds ACROSS passes and not merely inside one: two
# watchers can arm on different factions' turns, and board-iteration order is not an arming order.
# Within a single pass the resolver's own queue walk already orders them.
var sequence: int = 0

static var _next_sequence := 1


# A watch with no arm stamp: the resolver's projection of an order that is still only queued.
# Its position in the pass's list is its order, so it needs no sequence of its own.
static func make(watching_unit: Unit, origin: Vector2i, aim: Vector2i,
		watched_cells: Array[Vector2i], fired_attack: AttackData, lengths: Array[int] = []) -> Watch:
	var w := Watch.new()
	w.watcher = watching_unit
	w.anchor_cell = origin
	w.aim_cell = aim
	w.footprint = watched_cells.duplicate()
	w.path_lengths = lengths.duplicate()
	w.attack = fired_attack
	return w


# A watch that is actually going live on a unit, stamped with its arm order.
static func arm(watching_unit: Unit, origin: Vector2i, aim: Vector2i,
		watched_cells: Array[Vector2i], fired_attack: AttackData, lengths: Array[int] = []) -> Watch:
	var w := make(watching_unit, origin, aim, watched_cells, fired_attack, lengths)
	w.sequence = _next_sequence
	_next_sequence += 1
	return w


# The resolver's working copy for one pass. The pass marks copies spent as they fire; the live
# watch is spent by EXECUTION, once, off the outcome that used it (GuardWard's rule).
func copy() -> Watch:
	var w := make(watcher, anchor_cell, aim_cell, footprint, attack, path_lengths)
	w.spent = spent
	w.cancelled = cancelled
	w.sequence = sequence
	return w


# The watcher is still on the board and still pointing at something. Says nothing about position or
# lifecycle — those are the caller's stage, the same split GuardWard.is_intact() makes.
func is_intact() -> bool:
	return watcher != null and is_instance_valid(watcher) \
		and not watcher.is_queued_for_deletion() \
		and attack != null and not footprint.is_empty()

# THE "could this watch still fire" predicate, and the one spelling of it (#810). It was written out
# longhand at five surfaces before this -- the resolver's trigger filter, the pass's live-watch
# collection, the board markup and both Play API readouts -- so adding a second ending would have
# meant finding all five. is_intact() stays its own question (does the watcher and its geometry
# still exist) because ScenarioUnitEntry asks exactly that and must still SEE a spent or cancelled
# watch in order to save the flag.
#
# CAN THE WEAPON STILL PAY? #810's original question, and it belongs HERE rather than in the
# resolver's trigger filter: a filter that refuses the shot leaves the watch un-fired and un-drawn-
# down, so the board would keep promising a shot that will never come (Law #2). One clause here
# reaches the trigger, the collection, the markup and both readouts at once, and needs no execution
# stamp -- fireability is a LIVE DERIVED FACT re-read at every resolve and every redraw, never a
# state transition somebody has to record.
#
# THIS SETTLES #810'S ORIGINAL FORK as REFUSE (dev, 2026-09-09), over "fire anyway" and "fire
# downgraded": a footprint promising a shot the weapon cannot pay for is a lie either way. The
# consequence is a DOUBLE PENALTY -- a watch that goes dry neither fires nor gives the reaction back
# -- which is the one-round rule (Unit.is_standing_watch, deliberately reading past this) applied to
# a third ending, consistent with the other two.
#
# THE INVARIANT THIS REPLACES: parts 1 and 2 closed the dry-watch hole by ARGUING that nothing can
# change a weapon's fireability while a watch stands -- true today (readiness moves only on firing
# or a Reload-class main, and a watcher can do neither), but enforced nowhere. A family that gates
# firing on anything TIMER-DECAYED or externally changed would have re-opened it silently.
# `tick_weapon_rev` is the standing precedent for such a decay. This asks instead of arguing.
#
# Says nothing about the ANCHOR, deliberately: that predicate takes a positional fact the caller
# owns, and the resolver feeds it a threaded cell while a redraw feeds the live one.
func is_armed() -> bool:
	return is_intact() and not spent and not cancelled \
		and watcher.is_attack_fireable(attack)


# THE anchor predicate, and it takes the positional fact rather than reading it (GuardWard.in_range's
# shape): the resolver feeds a THREADED cell so a mid-pass shove of the WATCHER really does drop the
# watch, while a redraw feeds the live one. One rule, two positional sources.
func is_anchored(watcher_cell: Vector2i) -> bool:
	return watcher_cell == anchor_cell


func covers(cell: Vector2i) -> bool:
	return footprint.has(cell)


# The footprint read back as the paths the shot walks, each in its own order.
func paths() -> Array[Array]:
	if not path_lengths.is_empty():
		return AttackShape.split_paths(footprint, path_lengths)
	var one: Array[Array] = []
	one.append(footprint.duplicate())
	return one
