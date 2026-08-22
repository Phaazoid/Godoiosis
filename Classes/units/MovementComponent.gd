extends Node
class_name MovementComponent

# Attached to Unit as a child component ($MovementComponent). Owns the unit's board position and
# the walk animation. `cell` is the AUTHORITATIVE position — read all over the codebase as
# unit.movement.cell — so the two mutators are deliberately different verbs:
#   set_cell()        teleports (spawn, scenario load) — position snaps, no animation
#   move_along_path() walks the path one cell at a time, emitting movement_finished at the end
#
# NB: _move_to_next_cell assigns `cell` BEFORE its tween runs, so mid-walk the logical position is
# already the cell being entered while the sprite is still travelling. Nothing reads it in flight
# today (MoveAction awaits movement_finished), but a query during the animation would see ahead.

@export var cell: Vector2i
@export var move_speed := 120 #pixels per second

# The shove slide's speed (#259 rework) -- a game constant, tuned on the dev Game tab. Read at
# each segment start, so a change applies from the next shove.
static var SHOVE_SLIDE_SPEED := 120.0  # pixels per second

# The void plummet (#431). How far a unit shoved into a hole keeps falling before it is removed,
# and how long that takes. Game constants beside the slide speed, tuned on the same Game tab --
# they are pure spectacle, and the dev asked for "a good deal longer" rather than a number.
# VOID_PLUMMET_CELLS is read TWICE on purpose: here for the fall itself and by
# OverlayMirror._append_drop for the preview pointer's length, so the arrow promises exactly the
# drop the execution shows (Law #2). Split them only if they should ever disagree.
static var VOID_PLUMMET_CELLS := 8.0     # cells below the landing surface
static var VOID_PLUMMET_SECONDS := 0.9

# How fast a shove's own fall drops, in CELLS per second (#472). A game constant beside the slide
# speed it interleaves with, on the same Game tab and under the same label it always had. It was
# UnitMirror.shove_fall_speed while the fall was an ease the mirror ran AFTER the slide; the fall
# is a BEAT of the slide now, so the rate belongs where the beat is timed.
static var SHOVE_FALL_SPEED := 4.0       # cells per second

signal movement_finished

var grid: TileMapLayer
var heights: BoardHeights
var path: Array[Vector2i] = []
var moving := false

# The shove slide's state (#259 rework): `sliding` is being MOVED rather than moving -- it never
# sets `moving`, so no walk visual, and the 3D mirror holds facing while it is on. `airborne` is
# true while the segment being travelled is still FLIGHT (the resolver's knockback_landing_index),
# which lets the mirror hold the sprite at its launch height over a hole and drop it at the
# landing; slide_origin is the launch cell that height is read from.
var sliding := false
var airborne := false
var slide_origin: Vector2i
var slide_landing_cell: Vector2i   # where flight ends -- _edge_drop forks flight/ground on it
var _flight_entries_left := 0

# The void plummet's state (#431): how far below its landing surface the sprite has fallen, in
# cells, while `plummeting` is on. UnitMirror is the one reader -- this is 3D-ONLY motion by
# construction, because the flat board has no height to fall through, so the 2D view still simply
# loses the unit when die() runs. A declared #292 asymmetry, not drift.
var plummeting := false
var plummet_depth := 0.0

# The landing fall's state (#472): the sprite is dropping at a break in its own slide.
# `landing_fall_top` is the world height that fall starts from -- the flight level at a landing,
# the previous cell's surface at a tumble break -- and `landing_fall_depth` how far below it the
# sprite has got, in cells. Same 3D-ONLY contract as the plummet above: UnitMirror is the one
# reader, and a flat board has no height to fall through.
var landing_falling := false
var landing_fall_top := 0.0
var landing_fall_depth := 0.0

# `owner` rather than get_parent(): matches UnitVisuals, and survives the
# component being reparented under a sub-node of the Unit.
func _unit() -> Node2D:
	return owner as Node2D

func set_grid(grid_layer: TileMapLayer):
	grid = grid_layer

# The height store, injected beside the grid (game.spawn_unit). Board state, not presentation --
# the rules layer reads it through BoardContext too -- and the slide needs it to know where its
# own falls are (#472). Null on a board with no heights wired, which reads as "no cliff anywhere"
# and simply leaves the slide unbroken.
func set_heights(board_heights: BoardHeights) -> void:
	heights = board_heights

func set_cell(new_cell: Vector2i):
	cell = new_cell
	if grid == null:
		push_error("MovementComponent.set_cell before set_grid — position not applied.")
		return
	_unit().position = grid.map_to_local(cell)

func move_along_path(new_path: Array[Vector2i]):
	if new_path.size() <= 1 or grid == null:
		moving = false
		movement_finished.emit()
		return

	path = new_path.duplicate()
	path.pop_front()
	moving = true

	_move_to_next_cell()

func _move_to_next_cell():
	if path.is_empty():
		moving = false
		movement_finished.emit()
		return

	var next_cell : Vector2i = path.pop_front()
	var target_pos := grid.map_to_local(next_cell)

	cell = next_cell

	var unit := _unit()
	var duration := unit.position.distance_to(target_pos) / maxf(move_speed, 1.0)
	var tween := create_tween()
	tween.tween_property(unit, "position", target_pos, duration)

	tween.finished.connect(_move_to_next_cell)

# move_along_path's shove twin (#259 rework): the sprite SLIDES to its resolved landing instead of
# teleporting. Same path walk, same movement_finished; landing_index is the resolver's own
# flight/tumble split (ResolvedOutcome.knockback_landing_index -- Law #2, never re-derived here).
func slide_along_path(new_path: Array[Vector2i], landing_index: int) -> void:
	if new_path.size() <= 1 or grid == null:
		movement_finished.emit()
		return

	path = new_path.duplicate()
	slide_origin = path.pop_front()
	slide_landing_cell = new_path[clampi(landing_index, 0, new_path.size() - 1)]
	_flight_entries_left = landing_index
	sliding = true

	_slide_to_next_cell()

func _slide_to_next_cell() -> void:
	if path.is_empty():
		sliding = false
		airborne = false
		movement_finished.emit()
		return

	# Airborne until the flight's own landing EDGE, where _edge_drop ends it -- no longer all the
	# way through arrival at the landing cell, half a tile further in (#472).
	airborne = _flight_entries_left > 0
	_flight_entries_left -= 1

	var from_cell := cell
	var next_cell: Vector2i = path.pop_front()
	var target_pos := grid.map_to_local(next_cell)

	cell = next_cell

	# A segment whose entry edge BREAKS is travelled in two halves with the fall between them
	# (#472). The edge is exactly where the preview hangs its drop pointer (#431's "it starts
	# falling AT THE EDGE"), so this is the playback finally taking the fall its own trail draws.
	# Asked per EDGE rather than per landing, which is what lets a cliff-then-tumble-then-lip shove
	# fall at BOTH breaks -- the thing the landing flag #431 deleted could never express.
	var unit := _unit()
	var drop := _edge_drop(from_cell, next_cell)
	if drop > 0.0:
		await _slide_leg(unit, grid.map_to_local(from_cell).lerp(target_pos, 0.5))
		await _fall(drop)
		airborne = false   # the flight ENDED at that edge; the rest of this segment is ground
	await _slide_leg(unit, target_pos)
	_slide_to_next_cell()


# One leg of a slide: a whole segment, or half of one bracketing a fall. Speed is read per leg, so
# a knob change lands on the next one exactly as it used to land on the next segment.
func _slide_leg(unit: Node2D, to: Vector2) -> void:
	var duration := unit.position.distance_to(to) / maxf(SHOVE_SLIDE_SPEED, 1.0)
	var tween := create_tween()
	tween.tween_property(unit, "position", to, duration)
	await tween.finished


# How far the sprite FALLS at the edge a step from `from` into `to` crosses, in cells -- 0.0 when
# the two surfaces MEET there and the slide simply carries on. This is the drop pointer's own
# question (OverlayMirror._append_drop) off the same BoardSpace call, because the trail promises
# exactly this fall. A second spelling is how they came to disagree: the mirror used to begin
# ground contact on ANY ramp landing, where the resolver only calls a landing a slide-on at a drop
# of 1 down a matching slope -- so every other ramp landing snapped by the difference, in one
# frame, halfway through the final flight segment (#472, the reported bug).
#
# The upper side is the FLIGHT level while airborne, and `from`'s own surface at that edge once the
# unit is on the ground. A cell the flight merely passes OVER cannot drop -- it is overflown, not
# landed on -- so while airborne only the edge into slide_landing_cell is asked. That is
# _append_drop's flown/airborne fork, spelled the same way for the same reason.
#
# Answering also publishes `landing_fall_top`: the fork that finds the drop is the one that knows
# where it starts, and re-deriving that at the caller would be the second spelling this ticket
# exists to delete -- a TUMBLE break falls from the previous cell's surface rather than from the
# flight, so slide_origin cannot recover it. Published only once a drop is REAL, never on the way
# past an edge that meets: a field that also records non-falls describes the last edge asked about
# rather than the last fall taken, which is a different fact under the same name.
func _edge_drop(from: Vector2i, to: Vector2i) -> float:
	if heights == null:
		return 0.0
	var dir := to - from
	var top: float
	if airborne:
		if to != slide_landing_cell:
			return 0.0
		top = BoardSpace.surface_point(slide_origin, heights).y
	else:
		top = BoardSpace.surface_height_at_edge(from, dir, heights)
	# _append_drop's own meeting test, spelled the same way: a ramp's plane runs through
	# tan(45 deg), which lands a hair under 1.0 in double, so an exact compare fires a
	# zero-length fall on every clean slide-on.
	var here := BoardSpace.surface_height_at_edge(to, -dir, heights)
	if top <= here or is_equal_approx(top, here):
		return 0.0
	landing_fall_top = top
	return top - here


# The fall at a break -- 3D-ONLY spectacle on plummet()'s shape below, with the same headless
# escape and for the same reason: a real timer here would put wall clock on every shove the suite
# runs. UnitMirror is the one reader.
func _fall(cells: float) -> void:
	# Headless (or at a zero rate) the drop is INSTANT rather than absent: the depth still records
	# what fell, so a suite running the real slide can read the beat it has no way to watch.
	if SHOVE_FALL_SPEED <= 0.0 or DisplayServer.get_name() == "headless":
		landing_fall_depth = cells
		return
	landing_fall_depth = 0.0
	landing_falling = true
	var tween := create_tween()
	tween.tween_property(self, "landing_fall_depth", cells, cells / SHOVE_FALL_SPEED)
	await tween.finished
	landing_falling = false


# The third animation, after the walk and the slide (#431): a unit shoved into a VOID keeps falling
# instead of blinking out at the lip. Awaited DIRECTLY rather than signalled -- movement_finished
# was already spent by the slide that brought it here, and awaiting a signal that had already fired
# would hang the caller forever. Same headless escape as Pacing.beat, and for the same reason: the
# suite awaits AttackAction.execute, so a real timer here would put wall clock on every void case.
func plummet() -> void:
	plummet_depth = 0.0
	if VOID_PLUMMET_SECONDS <= 0.0 or DisplayServer.get_name() == "headless":
		return
	plummeting = true
	var tween := create_tween()
	tween.tween_property(self, "plummet_depth", VOID_PLUMMET_CELLS, VOID_PLUMMET_SECONDS)
	await tween.finished
	plummeting = false

