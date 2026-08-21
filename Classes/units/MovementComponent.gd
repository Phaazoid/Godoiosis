extends Node
class_name MovementComponent

# Attached to Unit as a child component ($MovementComponent). Owns the unit's board position and
# the walk animation. `cell` is the AUTHORITATIVE position — read all over the codebase as
# unit.movement.cell — so the two mutators are deliberately different verbs:
#   set_cell()        teleports (spawn, scenario load, knockback) — position snaps, no animation
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

signal movement_finished

var grid: TileMapLayer
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
var slide_landing_cell: Vector2i   # where flight ends -- the mirror forks ramp/flat contact on it
var _flight_entries_left := 0

# The void plummet's state (#431): how far below its landing surface the sprite has fallen, in
# cells, while `plummeting` is on. UnitMirror is the one reader -- this is 3D-ONLY motion by
# construction, because the flat board has no height to fall through, so the 2D view still simply
# loses the unit when die() runs. A declared #292 asymmetry, not drift.
var plummeting := false
var plummet_depth := 0.0

# `owner` rather than get_parent(): matches UnitVisuals, and survives the
# component being reparented under a sub-node of the Unit.
func _unit() -> Node2D:
	return owner as Node2D

func set_grid(grid_layer: TileMapLayer):
	grid = grid_layer

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

	# Airborne through the segment INTO the landing cell -- the drop happens on arrival there.
	airborne = _flight_entries_left > 0
	_flight_entries_left -= 1

	var next_cell: Vector2i = path.pop_front()
	var target_pos := grid.map_to_local(next_cell)

	cell = next_cell

	var unit := _unit()
	var duration := unit.position.distance_to(target_pos) / maxf(SHOVE_SLIDE_SPEED, 1.0)
	var tween := create_tween()
	tween.tween_property(unit, "position", target_pos, duration)

	tween.finished.connect(_slide_to_next_cell)


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

