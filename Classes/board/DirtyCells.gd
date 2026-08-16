extends RefCounted
class_name DirtyCells

# "Which cells changed since somebody last looked?" — the one answer, shared by the two stores the
# 3D mirror reads (#319): BoardGrid (what tile is painted) and BoardHeights (how tall a cell is).
#
# It exists because there was no way to ask. BoardMirror.sync re-derived the answer by walking the
# WHOLE board every frame — TileMapLayer.changed does not fire on set_cell in 4.7, so there was no
# signal to hang it on — and that walk is O(board) per frame at ~6.5 us/cell. Prolog is 2560 cells,
# i.e. a whole 60fps frame budget spent discovering that nothing moved. Measurements:
# docs/performance.md -> "board size and the 3D authoring poll".
#
# ONE CONSUMER. Whoever calls clear() speaks for everyone, so a second reader would silently get an
# empty set and stop rendering. Today that consumer is battle3d's authoring poll, and a second one
# is a design change rather than an extra call site.
#
# ALL is not "every cell marked" — it is "no cell list exists". A bulk write (clear(), or assigning
# tile_map_data wholesale) has no cells to enumerate, and pretending otherwise would mean walking
# the board to build a list the consumer is about to discard by full-syncing anyway.

var all := false
var _cells: Dictionary[Vector2i, bool] = {}


# A Dictionary rather than an Array: a brush drag recrosses cells constantly, and the consumer
# wants each one once. Marking under `all` is a deliberate no-op so a bulk repaint (resize_map
# paints every cell through the door) does not pay to build a list nobody reads.
func mark(cell: Vector2i) -> void:
	if all:
		return
	_cells[cell] = true


func mark_all() -> void:
	all = true
	_cells.clear()


func pending() -> bool:
	return all or not _cells.is_empty()


func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_cells.keys())
	return out


func clear() -> void:
	all = false
	_cells.clear()
