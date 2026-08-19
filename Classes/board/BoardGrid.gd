extends TileMapLayer
class_name BoardGrid

# The 2D board's tile layer — the authority for what terrain is painted where, and (since #319) the
# one place a terrain write ANNOUNCES itself so the 3D mirror can reconcile just the cells that
# moved instead of re-walking the board every frame.
#
# NAMED DOORS, not overrides of set_cell/erase_cell/clear. Two reasons, in order:
#   1. Godot's native_method_override warning is an ERROR in this project, so shadowing them would
#      not compile.
#   2. Even if it did, an override only intercepts GDScript callers — engine-internal writes would
#      slip past it, which is a worse hole than the honest one below, because it would look covered.
#
# THE BULK WRITE used to be the declared hole here: `tile_map_data` assigned wholesale on every
# board load, safe only because a load emits board_loaded -> battle3d.rebuild(), which full-syncs.
# restore() below closed it (#391) -- an authoring undo needs the same wholesale write and would
# have been the SECOND writer relying on that argument, which is one more than an argument like
# that survives. tests/law/test_board_writes_announce.gd now scans for the assignment too, and has
# no exceptions left.
#
# The dirty set is deliberately not consulted by anything in this class — the grid announces, and
# what to do about it is the mirror's business.

var dirty := DirtyCells.new()


# The paint door. `alternative` is carried because item_for_tile reads it: a flipped or rotated
# tile deliberately has no meshlib item of its own and falls back to its Kind block, so a caller
# that could not express one would silently paint a different 3D cell than it asked for.
func paint(cell: Vector2i, source_id: int, coords: Vector2i, alternative := 0) -> void:
	set_cell(cell, source_id, coords, alternative)
	dirty.mark(cell)


func erase(cell: Vector2i) -> void:
	erase_cell(cell)
	dirty.mark(cell)


# The clear() door. Named reset() rather than clear() for the override reason above; it marks ALL
# rather than enumerating, since a wipe has no cell list and the consumer will full-sync regardless.
func reset() -> void:
	clear()
	dirty.mark_all()


# The BULK door (#391): every cell replaced at once, from a scenario load or an undo. mark_all for
# the reason reset() uses it -- a wholesale write has no cell list to enumerate, and DirtyCells
# already spells ALL as "no cell list exists" rather than "every cell marked".
#
# This is the only reason the raw assignment is reachable at all now: it cannot be doored as a
# property, so it is doored as a method, and the law scans for the property being written anywhere
# else.
func restore(data: PackedByteArray) -> void:
	# The clear() is NOT belt-and-braces, it is the whole reason this is a method. MEASURED on
	# 4.7.1: assigning an EMPTY buffer to tile_map_data does nothing at all -- the setter returns
	# early rather than wiping -- so restoring a board back to bare ground left every painted cell
	# standing. Every previous caller happened to clear first (apply_scenario runs clear_board), so
	# the quirk was invisible until an undo asked for the empty board directly.
	clear()
	tile_map_data = data
	dirty.mark_all()
