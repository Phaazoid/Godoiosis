class_name PathLines
extends Control

# A single-target swing's paths on the SHAPE PLATE (#1057 part 2, #1054 ruling 30): each path one line
# over the yellow tiles, a ring where it starts, a BEAD on every tile it stops on, and an arrowhead on
# the last -- so a tile the path jumps gets no bead and the jump shows. Each path wears its own DARK
# colour (PathPalette.dark), readable on the yellow. Approved off the round-2 mockup.
#
# One line rather than the editor's arrow per step: the plate's cells run 7 to 14px, too small for a
# head on every step, and the beads carry what the heads said. Lines sit RIGHT of travel, so an
# out-and-back reads as two.
#
# lines() is the whole model and _draw renders exactly what it returns -- AuraRing.rows()'s shape, so a
# case asserts the drawing without reading a pixel. It places everything off the grid's OWN cell rects
# (PathArrows' rule), so a line cannot drift from the tile it names; it never takes the mouse.

# The meta a ShapePlate cell carries: its offset from the plate's centre.
const CELL_META := &"shape_plate_offset"

# Every size is a share of the cell PITCH (cell plus gap), floored so the smallest plate still reads.
const LANE_SHARE := 0.17
const WIDTH_SHARE := 0.12
const MIN_WIDTH := 1.3
const HEAD_SHARE := 0.4
const MIN_HEAD := 3.4
const HEAD_SPREAD := 0.62   # half the head's width, as a share of its length
const BEAD_SHARE := 0.15
const MIN_BEAD := 1.7
const RING_SHARE := 0.2
const MIN_RING := 2.3
const TIP_SHARE := 0.2      # how far past the last tile's lane point the tip runs, of the cell


# One path, as drawn.
class Line extends RefCounted:
	var shaft := PackedVector2Array()   # start to the head's base
	var ring := Vector2.ZERO            # where the path starts
	var beads := PackedVector2Array()   # every tile it stops on between its first and its last
	var head := PackedVector2Array()    # tip and the two back corners; empty for a one-tile path
	var colour := Color.BLACK
	var width := 0.0
	var bead_radius := 0.0
	var ring_radius := 0.0


var grid: GridContainer
var drawn_paths: Array[Array] = []
var ground := Color.YELLOW
var pitch := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# `footprint` is the colour the tiles under the lines are painted (the plate's aim fill), which the
# dark palette is measured against; `cell_pitch` is one cell plus the gap between two.
func show_paths(paths: Array[Array], footprint: Color, cell_pitch: float) -> void:
	drawn_paths = paths
	ground = footprint
	pitch = cell_pitch
	visible = not paths.is_empty()
	queue_redraw()


# Every cell's centre in this layer's own space, read off the grid's children.
func centres() -> Dictionary:
	var out: Dictionary = {}
	if grid == null:
		return out
	var shift := grid.global_position - global_position
	for child in grid.get_children():
		var cell := child as Control
		if cell == null or not cell.has_meta(CELL_META):
			continue
		out[cell.get_meta(CELL_META)] = shift + cell.position + cell.size / 2.0
	return out


func _draw() -> void:
	var at := centres()
	if at.is_empty():
		return
	for line in lines(drawn_paths, at, pitch, ground):
		if line.shaft.size() >= 2:
			draw_polyline(line.shaft, line.colour, line.width, true)
		if not line.head.is_empty():
			draw_colored_polygon(line.head, line.colour)
		for bead in line.beads:
			draw_circle(bead, line.bead_radius, line.colour)
		draw_circle(line.ring, line.ring_radius, ground)
		draw_arc(line.ring, line.ring_radius, 0.0, TAU, 16, line.colour, line.width * 0.85, true)


# THE MODEL. `centres` maps a path offset to where its tile sits; a path stepping off the plate is
# drawn only as far as its tiles are on it.
static func lines(paths: Array[Array], centres: Dictionary, pitch: float, footprint: Color) -> Array[Line]:
	var out: Array[Line] = []
	for p in paths.size():
		var on_plate: Array[Vector2] = []
		for offset: Vector2i in paths[p]:
			if not centres.has(offset):
				break
			on_plate.append(centres[offset])
		if on_plate.is_empty():
			continue
		out.append(_line(on_plate, pitch, PathPalette.dark(p, footprint)))
	return out


static func _line(points: Array[Vector2], pitch: float, colour: Color) -> Line:
	var line := Line.new()
	line.colour = colour
	line.width = maxf(MIN_WIDTH, pitch * WIDTH_SHARE)
	line.bead_radius = maxf(MIN_BEAD, pitch * BEAD_SHARE)
	line.ring_radius = maxf(MIN_RING, pitch * RING_SHARE)
	var lane := pitch * LANE_SHARE
	var stops: Array[Vector2] = []
	var laned: Array[Vector2] = []
	for i in points.size():
		var inward := (points[i] - points[i - 1]).normalized() if i > 0 else Vector2.ZERO
		var outward := (points[i + 1] - points[i]).normalized() if i + 1 < points.size() else Vector2.ZERO
		if inward != Vector2.ZERO and outward != Vector2.ZERO and inward.dot(outward) < -0.99:
			# A reversal: swing round the far side of the tile, and stop on the far side.
			var far := points[i] + inward * lane
			laned.append_array([points[i] + _right(inward) * lane, far, points[i] + _right(outward) * lane])
			stops.append(far)
			continue
		var normal := _right(inward if outward == Vector2.ZERO else outward)
		var stretch := 1.0
		if inward != Vector2.ZERO and outward != Vector2.ZERO:
			normal = (_right(inward) + _right(outward)).normalized()
			stretch = 1.0 / maxf(0.5, normal.dot(_right(inward)))
		var point := points[i] + normal * lane * stretch
		laned.append(point)
		stops.append(point)
	line.ring = stops[0]
	for i in range(1, stops.size() - 1):
		line.beads.append(stops[i])
	if laned.size() < 2:
		return line   # a one-tile path is its ring alone
	var last := laned[laned.size() - 1]
	var travel := (last - laned[laned.size() - 2]).normalized()
	var head := maxf(MIN_HEAD, pitch * HEAD_SHARE)
	var tip := last + travel * pitch * TIP_SHARE
	var base := tip - travel * head
	var spread := _right(travel) * head * HEAD_SPREAD
	line.head = PackedVector2Array([tip, base + spread, base - spread])
	for i in laned.size() - 1:
		line.shaft.append(laned[i])
	line.shaft.append(base)
	return line


# Right of travel, on screen (y down).
static func _right(travel: Vector2) -> Vector2:
	return Vector2(-travel.y, travel.x)
