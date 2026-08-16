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
# THE HOLE THAT REMAINS, declared rather than hidden: `tile_map_data` is assigned wholesale by
# ScenarioManager on every board load, and a property assignment cannot be doored at all. That is
# safe because a load emits board_loaded -> battle3d.rebuild(), which full-syncs; it is NOT safe to
# add a second bulk writer without the same guarantee. tests/law/test_board_writes_announce.gd
# keeps every OTHER writer on the door.
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
