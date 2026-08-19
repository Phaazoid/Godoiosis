extends RefCounted
class_name BoardHistory

# The Tile Brush's undo stack (#391) -- a LINEAR history of BoardSnapshots with a cursor, rather
# than a stack of before/after pairs. N steps cost N+1 snapshots instead of 2N, and redo is the
# cursor moving the other way instead of a second stack that has to be kept in step with the first.
#
# A STEP IS A STROKE, not a cell: DevController brackets mouse-down to mouse-up and commits once,
# so undoing a forty-cell drag is one press. That is what the drag was -- one decision.
#
# ONE STACK for every authoring edit, not one per store, so the question it answers is "what did I
# last do to this board" and never "what did I last do in this mode". A snapshot could not be split
# per store anyway: erasing a tile prunes that cell's states AND its height (#245/#260).
#
# SNAPSHOTS, NOT DELTAS, for the same reason -- the brush's writes have consequences a delta would
# have to re-derive by hand (the prune above, a zone erased to empty being deleted, a resize
# stranding everything outside the new rectangle). A snapshot cannot miss one. The price is memory:
# tile_data dominates at ~12 bytes/cell, so ~3 KB on the 20x12 test board and ~0.5 MB at the
# 200x200 maximum the resize spinners allow. MAX_STEPS is what bounds it.

const MAX_STEPS := 50

# The board at each point in time, oldest first, with _index pointing at the board as it stands
# NOW. Everything below _index is undoable, everything above is redoable. Empty until reset().
var _snapshots: Array[BoardSnapshot] = []
var _index := 0


# Start again from this board, forgetting everything: what a board LOAD does. The history belongs
# to one board, and a stack that outlived its subject would paste the previous board's terrain onto
# the new one.
func reset(snapshot: BoardSnapshot) -> void:
	_snapshots = [snapshot]
	_index = 0


# Re-stamp what "now" is, at the start of an edit. Not decoration: the cursor entry is a claim
# about the live board, and anything that changed it without committing -- fire spreading over a
# played round, a scenario loaded by some path that forgot to reset -- would otherwise be rewound
# by the next undo as though the brush had done it.
func begin(snapshot: BoardSnapshot) -> void:
	if _snapshots.is_empty():
		reset(snapshot)
		return
	_snapshots[_index] = snapshot


# Close an edit. Returns whether a step was actually recorded, so a caller can skip announcing a
# drag that changed nothing.
func commit(snapshot: BoardSnapshot) -> bool:
	if _snapshots.is_empty():
		reset(snapshot)
		return false
	if snapshot.equals(_snapshots[_index]):
		return false
	# A new edit made after undoing abandons the redo tail -- the future it led to is not the one
	# this board is in any more.
	_snapshots.resize(_index + 1)
	_snapshots.append(snapshot)
	if _snapshots.size() > MAX_STEPS + 1:
		_snapshots.remove_at(0)   # the oldest board falls off; +1 because N steps need N+1 boards
	_index = _snapshots.size() - 1
	return true


# The board to restore, or null when there is nothing left to go back to. The cursor moves here
# rather than at the call site, so "can I" and "do it" cannot disagree.
func undo() -> BoardSnapshot:
	if not can_undo():
		return null
	_index -= 1
	return _snapshots[_index]


func redo() -> BoardSnapshot:
	if not can_redo():
		return null
	_index += 1
	return _snapshots[_index]


func can_undo() -> bool:
	return _index > 0


func can_redo() -> bool:
	return _index < _snapshots.size() - 1


# How many presses of undo are left. The panel's row reads this; nothing else depends on it.
func depth() -> int:
	return _index
