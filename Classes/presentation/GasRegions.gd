extends Object
class_name GasRegions

# Where the gas volume must march (#508): one box per connected patch of gas cells, grown by a cell
# all round for the soft edge and tall enough for the tallest column, then MERGED wherever two boxes
# meet. The compute pass marches every box a ray crosses one after another, so two overlapping boxes
# would count the gas between them twice; kept disjoint, a ray's intervals never overlap.
#
# Pure: cells and two answers about them in, boxes out. GasMirror calls it once for the board and
# once for a tear-out's lifted copy, whose boxes ride the stage offset.

const PAD := 1.0      # cells of room round a patch
const BELOW := 0.2    # world units under the lowest ground
const ABOVE := 0.6    # world units over the tallest column


# `ground_span(cell) -> Vector2` is the lowest and highest world y of a cell's surface;
# `column_top(cell) -> float` how far above its ground the tallest gas there may stand.
static func boxes(cells: Array[Vector2i], ground_span: Callable, column_top: Callable,
		offset := Vector3.ZERO) -> Array[AABB]:
	var out: Array[AABB] = []
	for patch in patches(cells):
		out.append(_box_of(patch, ground_span, column_top))
	out = merged(out)
	for i in out.size():
		out[i].position += offset
	return out


# The cells in 8-connected patches. Sorted, so the boxes come out in one order every time.
static func patches(cells: Array[Vector2i]) -> Array[Array]:
	var left: Dictionary[Vector2i, bool] = {}
	for cell in cells:
		left[cell] = true
	var sorted := cells.duplicate()
	sorted.sort()
	var out: Array[Array] = []
	for start: Vector2i in sorted:
		if not left.has(start):
			continue
		var patch: Array[Vector2i] = []
		var frontier: Array[Vector2i] = [start]
		left.erase(start)
		while not frontier.is_empty():
			var cell: Vector2i = frontier.pop_back()
			patch.append(cell)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var next := cell + Vector2i(dx, dy)
					if left.has(next):
						left.erase(next)
						frontier.append(next)
		out.append(patch)
	return out


# Merge every pair of boxes that overlap, until none do.
static func merged(boxes_in: Array[AABB]) -> Array[AABB]:
	var out := boxes_in.duplicate()
	var changed := true
	while changed:
		changed = false
		for i in out.size():
			for j in range(i + 1, out.size()):
				if out[i].intersects(out[j]):
					out[i] = out[i].merge(out[j])
					out.remove_at(j)
					changed = true
					break
			if changed:
				break
	return out


static func _box_of(patch: Array, ground_span: Callable, column_top: Callable) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for cell: Vector2i in patch:
		var span: Vector2 = ground_span.call(cell)
		var top: float = column_top.call(cell)
		lo = lo.min(Vector3(cell.x, span.x, cell.y))
		hi = hi.max(Vector3(cell.x + 1.0, span.y + top, cell.y + 1.0))
	lo -= Vector3(PAD, BELOW, PAD)
	hi += Vector3(PAD, ABOVE, PAD)
	return AABB(lo, hi - lo)
