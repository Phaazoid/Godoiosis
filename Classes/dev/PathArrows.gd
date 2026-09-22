extends Control
class_name PathArrows

# The arrow layer over the Attack Editor's shape grid in Paths mode (#1079): each path drawn as
# arrows from tile to tile in the order the swing reaches them, a ring on its first tile, one hue
# per path, the path being written at full strength and the rest faded behind it. Approved off the
# round-3 mockup (dev, 2026-09-22: "little arrows drawn from space to space").
#
# It shares one rect with the grid (both are children of one MarginContainer) and places every
# arrow off the grid's OWN cell rects, so an arrow cannot drift from the cell it names. It never
# takes the mouse: every click falls through to the cell underneath.
#
# segments() is the whole model and _draw renders exactly what it returns -- AuraRing.rows()'s
# shape, so a headless case asserts the arrows without reading a pixel.

enum Kind { START, STEP }

# Cycled by path index. The first three are the mockup's.
const PATH_HUES: Array[Color] = [
	Color("ffb45e"), Color("4fd8c8"), Color("c39bff"),
	Color("ff7a9a"), Color("9be06a"), Color("6aaeff"),
]

const LANE := 3.0          # sideways shift right of travel, so an out-and-back reads as two arrows
const TRIM_START := 7.0
const TRIM_END := 5.0
const HEAD_SPREAD := 0.62  # half the head's width, as a share of its length
const SELECTED_WIDTH := 2.5
const SELECTED_HEAD := 6.5
const SELECTED_RING := 4.5
const SELECTED_RING_WIDTH := 2.0
const OTHER_WIDTH := 1.5
const OTHER_HEAD := 5.0
const OTHER_RING := 4.0
const OTHER_RING_WIDTH := 1.5
const OTHER_ALPHA := 0.5
const SWATCH_PX := 12

var grid: GridContainer

var drawn_paths: Array[Array] = []
var selected_path := -1

static var _swatches: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_paths(paths: Array[Array], selected: int, shown: bool) -> void:
	drawn_paths = paths
	selected_path = selected
	visible = shown
	queue_redraw()


static func hue(index: int) -> Color:
	return PATH_HUES[index % PATH_HUES.size()]


# The picker's mark for a path: a square of its hue.
static func swatch(index: int) -> Texture2D:
	var key := index % PATH_HUES.size()
	if not _swatches.has(key):
		var image := Image.create(SWATCH_PX, SWATCH_PX, false, Image.FORMAT_RGBA8)
		image.fill(PATH_HUES[key])
		_swatches[key] = ImageTexture.create_from_image(image)
	return _swatches[key]


# What gets drawn, in draw order: every other path first, the selected one last so it sits on top.
# Per path a START ring on its first tile, then one STEP per move in travel order.
static func segments(paths: Array[Array], selected: int) -> Array[Dictionary]:
	var order: Array[int] = []
	for p in paths.size():
		if p != selected:
			order.append(p)
	if selected >= 0 and selected < paths.size():
		order.append(selected)
	var out: Array[Dictionary] = []
	for p in order:
		var path: Array = paths[p]
		if path.is_empty():
			continue
		var chosen := p == selected
		out.append({"kind": Kind.START, "from": path[0], "to": path[0], "path": p, "selected": chosen})
		for i in range(1, path.size()):
			out.append({"kind": Kind.STEP, "from": path[i - 1], "to": path[i], "path": p, "selected": chosen})
	return out


# Every cell's centre in this layer's own space, read off the grid's children.
func centres() -> Dictionary:
	var out: Dictionary = {}
	if grid == null:
		return out
	var shift := grid.position - position
	for child in grid.get_children():
		var cell := child as Control
		if cell == null or not cell.has_meta(DevWidgets.CELL_OFFSET_META):
			continue
		out[cell.get_meta(DevWidgets.CELL_OFFSET_META)] = shift + cell.position + cell.size / 2.0
	return out


func _draw() -> void:
	var at := centres()
	for seg in segments(drawn_paths, selected_path):
		if not at.has(seg["from"]) or not at.has(seg["to"]):
			continue
		var chosen: bool = seg["selected"]
		var colour := hue(int(seg["path"]))
		if not chosen:
			colour.a *= OTHER_ALPHA
		var a: Vector2 = at[seg["from"]]
		if seg["kind"] == Kind.START:
			draw_arc(a, SELECTED_RING if chosen else OTHER_RING, 0.0, TAU, 24, colour,
				SELECTED_RING_WIDTH if chosen else OTHER_RING_WIDTH, true)
		else:
			_draw_arrow(a, at[seg["to"]], colour,
				SELECTED_WIDTH if chosen else OTHER_WIDTH, SELECTED_HEAD if chosen else OTHER_HEAD)


func _draw_arrow(a: Vector2, b: Vector2, colour: Color, width: float, head: float) -> void:
	var travel := (b - a).normalized()
	var right := Vector2(-travel.y, travel.x)
	var start := a + travel * TRIM_START + right * LANE
	var tip := b - travel * TRIM_END + right * LANE
	var base := tip - travel * head
	var spread := right * head * HEAD_SPREAD
	draw_line(start, base, colour, width, true)
	draw_colored_polygon(PackedVector2Array([tip, base + spread, base - spread]), colour)
