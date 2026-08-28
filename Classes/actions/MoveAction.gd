extends BaseAction
class_name MoveAction

var path: Array[Vector2i]
var destination: Vector2i
var destination_texture: Texture2D
var preview: Array[Sprite2D] = []
var is_hold_position := false
# Case 1 feedback: this member ended FURTHER from its leader than it started — following, but
# falling behind. Set by GroupMoveSolver; the only thing that reads it is the arrow's colour.
var is_trailing := false

# Where this walk ACTUALLY ends, once the resolver has walked it (#413): an index into `path`, or -1
# for "all the way". Written every resolve (PlanResolver.resolve_move), so it can never carry a
# previous pass's verdict — GuardAction.resolved_spent's rule. A crosser an overwatch shot downs
# stops at the crossing cell, and so does one it throws.
var resolved_stop_index := -1

# PLAYBACK ONLY (#567): the steps of `path` this walk HALTS at while a triggered shot plays, in
# ascending order. Written by OrderExecutor before execute(), off the moments the resolve stamped on
# the shots — never by the resolver, and never read by anything that decides an outcome. Nothing
# here moves where the walk ends; `resolved_stop_index` stays the one authority on that, and this is
# only how the same walk is animated.
var interrupt_steps: Array[int] = []
var _parked_at := -1

const GENERIC_TILE := preload("res://Art/Icons/BoardIcons/GenericTileIcon.png")
const MOVE_ICON := preload("res://Art/Icons/ActionIcons/MoveActionIcon.png")
const HOLD_ICON := preload("res://Art/Icons/ArrowIcons/nomove.png")
const ARROW_BASE_Z_INDEX = 3
const HOVERED_ARROW_Z_INDEX = 10

func init(unit: Unit, move_path: Array[Vector2i], destination_tile_texture: Texture2D):
	actor = unit 
	path = move_path
	destination = path.back()
	action_type = ActionType.MOVE
	if destination_tile_texture == null:
		destination_texture = GENERIC_TILE
	else:
		destination_texture = destination_tile_texture
	
func init_hold_position(unit: Unit, destination_tile_texture: Texture2D):
	actor = unit
	action_type = ActionType.MOVE
	path = []
	destination = unit.movement.cell
	is_hold_position = true
	if destination_tile_texture == null:
		destination_texture = GENERIC_TILE
	else:
		destination_texture = destination_tile_texture

func actor_can_perform() -> bool:
	# Move-before-main: a unit that locked its main action can't move after it (attacks
	# resolve from the final position — no attack-then-flee).
	return not actor.has_main_action_queued()

func is_reorderable() -> bool:
	# A hold is a filler nobody ordered and crosses nothing — resequencing it means nothing (#412).
	return not is_hold_position

func execute():
	begin_execution()
	# NOT clear_preview_sprites() here (#558, dev 2026-08-26: "have the arrow match the ghost's
	# lifecycle"). The arrow stays up while the unit walks it and goes on ARRIVAL, with the ghost.
	# The old clear was also only durable by luck: redraw_planned_paths rebuilds every arrow from
	# planned_move_by_unit, which still named this unit, so any redraw during a pass put it back.
	#
	# One leg per stretch between interrupts (#567). With none it is the single move_along_path this
	# always was — the legs SHARE their boundary cell, which is the cell the unit is already standing
	# on when the next one starts, and move_along_path pops exactly that.
	_parked_at = -1
	var walk := walked_path()
	var start := 0
	for step in _pause_steps():
		await _walk_leg(walk.slice(start, step + 1))
		start = step
		# Parked: the executor sees it, plays the shot this step fired, and releases. Polled rather
		# than awaited on a signal, so a release that lands before this line cannot hang the walk.
		_parked_at = step
		while _parked_at >= 0 and is_instance_valid(actor):
			await actor.get_tree().process_frame
	await _walk_leg(walk.slice(start))

	finish_execution()


# One stretch of the walk. Guarded because the walk can now outlive its own mover: a shot fired at
# an interrupt may down or remove the crosser, and a halted walk's remaining leg is the one cell it
# is already standing on.
func _walk_leg(leg: Array[Vector2i]) -> void:
	if actor == null or not is_instance_valid(actor) or actor.is_queued_for_deletion():
		return
	actor.movement.move_along_path(leg)

	if actor.movement.moving:
		await actor.movement.movement_finished


# Which of `interrupt_steps` this walk can actually stop at: ascending, de-duplicated, and inside
# the stretch actually walked. A shot that fires ON the last cell still parks — the walk is over,
# but the shot has not played yet, and the leg after it is the single cell it stands on.
func _pause_steps() -> Array[int]:
	var last_cell := walked_path().size() - 1
	var steps: Array[int] = []
	var previous := 0
	for step in interrupt_steps:
		if step <= previous or step > last_cell:
			continue
		steps.append(step)
		previous = step
	return steps


# Halted at an interrupt, or -1. The executor's poll asks this; release() answers it.
func parked_at() -> int:
	return _parked_at


func release() -> void:
	_parked_at = -1


func get_action_icon() -> Texture2D:
	if is_hold_position:
		return HOLD_ICON
	return MOVE_ICON
	
func get_move_path() -> Array[Vector2i]:
	return path

func get_description() -> String:
	if is_hold_position:
		return "%s holds position" % actor.get_unit_name()
	return "%s moves to %s" % [actor.get_unit_name(), str(destination)]
	
func get_target_texture() -> Texture2D:
	return destination_texture
	
func get_destination() -> Vector2i:
	return walked_path().back() if was_halted() else destination

# The pass stopped this walk short of its destination (#413). Read by Unit.projected_cell as well as
# by execution: a mover the shot HALTED did not walk out from under a shove, so the shove wins.
func was_halted() -> bool:
	return resolved_stop_index >= 0 and resolved_stop_index < path.size()

# What the unit actually walks — the whole path, or the prefix a watch shot stopped it at. ONE
# spelling, so the preview's destination and the playback cannot disagree (Law #2).
func walked_path() -> Array[Vector2i]:
	if not was_halted():
		return path
	return path.slice(0, resolved_stop_index + 1)
	
func clear_preview_sprites():
	for sprite in preview:
		if is_instance_valid(sprite):
			sprite.hide()
			sprite.queue_free()
	preview.clear()
	
func set_preview_z_index(value: int):
	for sprite in preview:
		if is_instance_valid(sprite):
			sprite.z_index = value
			
func reset_preview_z_index():
	set_preview_z_index(ARROW_BASE_Z_INDEX)
	
func add_preview_sprite(sprite: Sprite2D):
	preview.append(sprite)
