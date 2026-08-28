# The 2D board camera: WASD-scrolled with grid snapping, clamped to the board,
# with playback locks (set_playback_locked/follow) and the fixed-duration pan_to beat.
# center_on_position glides via the _process lerp; snap_to_position is the instant
# form (the 3D input bridge maps clicks through the live transform, #220).
#
# Manual scrolling has THREE locks now: lock_manual_input (a glide owns the camera),
# playback_locked (an AI turn or a resolution pass does), and game.board_input_delegated (a 3D host does -- #176
# stage 4d, where WASD would otherwise pan this camera AND the 3D rig off one press).
# Only the keyboard branch is gated: pan_to/follow/snap_to_position must keep working,
# and follow needs this _process to track its unit.
extends Node2D
class_name CameraController

var game   # the Game coordinator (Node2D); set by game._ready()

@onready var camera: Camera2D = $Camera2D
const TILE_SIZE := GridUtils.TILE_SIZE
const CELL_WORLD := TILE_SIZE * 2   # 32px/cell — matches your existing min/max_world math
const EDIT_MARGIN_CELLS := 8

var map_width = 32
var map_height = 20
var edge_size = 64
var is_moving := false
var keyboard_direction := Vector2.ZERO
var lock_manual_input := false
var last_move_dir := Vector2.ZERO
var was_moving := false
# True while something other than the player owns where the camera looks: an AI faction's whole
# turn, OR one squad's resolution pass (#520). Named for the FACT rather than its first caller --
# it was ai_locked until #520, and the player's own Execute needs the identical treatment.
#
# It governs WHERE the camera looks, never how far out it sits: the player keeps the zoom wheel
# throughout (dev, 2026-08-26), which is why battle3d gates zoom on the menu half alone.
var playback_locked := false
var follow_unit: Unit = null  # while set, target_position tracks this unit every frame
# The line the current beat is framed ACROSS, in sim cells (#520) -- [from, to], empty for a beat
# with no direction. THIS camera never rotates and never will; it carries the value because it is
# already what the 3D rig mirrors, and OrderExecutor has no path to the rig (the same reason the pan
# goes through here). The rig turns it into a yaw, since only the rig knows what to measure from.
var directed_line: Array[Vector2i] = []
# The two ends the shot must take IN, in sim cells (#520) -- a walk's start and its destination, so
# the opening shot of a move shows where it begins and where it is going instead of just centring on
# the walker (dev, scratchpad 2026-08-26). Empty for a beat that frames one thing.
#
# Carried here for the reason directed_line is: this is what the 3D rig already mirrors and
# OrderExecutor has no path to the rig. A DIFFERENT question from that one, though, and the two must
# never be folded together -- directed_line is an ANGLE and this is a FIT, so one field answering
# both would spin the camera side-on to every walk.
var framed_span: Array[Vector2i] = []
# How BIG the beat now playing is, 0..1 (#520 diff 2c) -- the collapse of its lethality rungs, from
# Pacing.emphasis_for. The THIRD question this trio answers and the third field, for the reason the
# other two are separate: that one is an ANGLE, that one a FIT, and this is a WEIGHT. The rig turns
# it into a push-in, since only the rig knows distances.
#
# Every beat that frames anything publishes its own, INCLUDING ZERO -- absence does not mean "hold
# what you had", which is directed_line's idiom and would be wrong here: the camera would stay
# pushed in from a kill through every quiet beat after it, and the pass would never breathe.
var beat_emphasis := 0.0
# WHICH PACING PROFILE the beat now playing runs under (#647), from Pacing.profile_for. The FOURTH
# question of the same set and the fourth field: that one is an ANGLE, that one a FIT, that one a
# WEIGHT, and this is the CAUSE the other three are shaped by.
#
# A READER THAT NEEDS "is a zoom happening RIGHT NOW" MUST NOT USE THIS -- see playback_cinematic
# below; held-not-cleared makes this say CINEMATIC for ever after the first clash.
#
# It exists because COMBAT_ONLY made the profile a fact about a BEAT rather than about the pass, and
# the 3D rig has no beat in hand -- it polls. Publishing the cause is more honest than inferring it
# from whether a line or a weight arrived, and it is the only channel the SWAY has at all: a sway is
# a RESTING behaviour, so nothing else about a quiet beat would ever tell the rig to stop drifting.
#
# Held rather than cleared, directed_line's idiom: between passes the last beat's profile stands, and
# nothing reads it while the view is unborrowed.
var beat_profile: Pacing.Profile = Pacing.Profile.BOARD
# DOES THE PASS NOW RUNNING SHOW A FIGHT -- the PASS-level twin of beat_profile, and the fifth field
# of the same set. It exists because the health readout asks a question none of the four above can
# answer: beat_profile is HELD between passes on purpose (see its note), so "is a zoom happening
# right now" cannot be read off it -- it stays CINEMATIC for ever after the first clash.
#
# CLEARED ON BOTH EDGES below, which is the whole of its lifetime: "the pass ended" and "this is
# false" are the same event, so no reader needs a second fact to know when to stop.
var playback_cinematic := false
var _panning := false         # true while pan_to's tween owns global_position -- _process yields to it

@export var move_speed := 14
@export var scroll_speed := 250

var target_position: Vector2 = global_position

var min_world := Vector2(
	-map_width / 2.0 * CELL_WORLD,
	-map_height / 2.0 * CELL_WORLD
)

var max_world := Vector2(
	map_width / 2.0 * CELL_WORLD,
	map_height / 2.0 * CELL_WORLD
)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	global_position = target_position
	
func center_on_position(world_pos: Vector2):
	lock_manual_input = true
	target_position = world_pos
	clamp_target_position()

# Instant, clamped reposition. The 3D input bridge (#220) maps a click's viewport
# position through the LIVE canvas transform, so the camera must already be showing
# the clicked cell when the synthetic event lands — a lerp target isn't enough.
func snap_to_position(world_pos: Vector2) -> void:
	target_position = world_pos
	clamp_target_position()
	_apply_pan_position(target_position)
	camera.force_update_scroll()

func clamp_target_position():
	var viewport_size = get_viewport_rect().size
	var visible_size = viewport_size / camera.zoom
	var half_view = visible_size / 2
	target_position.x = _clamp_axis(target_position.x, min_world.x, max_world.x, half_view.x)
	target_position.y = _clamp_axis(target_position.y, min_world.y, max_world.y, half_view.y)

func _clamp_axis(value: float, lo: float, hi: float, half: float) -> float:
	# Map smaller than the view on this axis -> bounds invert (lo+half > hi-half).
	# Center the map instead of letting clamp() thrash.
	if hi - lo <= half * 2.0:
		return (lo + hi) / 2.0
	return clamp(value, lo + half, hi - half)

func refresh_bounds(grid: TileMapLayer):
	var used := grid.get_used_rect()
	var margin := Vector2(EDIT_MARGIN_CELLS, EDIT_MARGIN_CELLS) * CELL_WORLD
	min_world = Vector2(used.position) * CELL_WORLD - margin
	max_world = Vector2(used.position + used.size) * CELL_WORLD + margin
	clamp_target_position()
	
func _process(delta: float):
	if _panning:
		return

	if is_instance_valid(follow_unit):
		target_position = follow_unit.global_position

	if global_position.distance_to(target_position) < 1:
		global_position = target_position
		is_moving = false
	
	#Always scroll at least one cell, and never snap back.  
	keyboard_direction = Vector2.ZERO
	if not lock_manual_input and not playback_locked and not _input_delegated():
		if Input.is_action_pressed("cam_right"):
			keyboard_direction.x += 1
		if Input.is_action_pressed("cam_left"):
			keyboard_direction.x -= 1
		if Input.is_action_pressed("cam_up"):
			keyboard_direction.y -= 1
		if Input.is_action_pressed("cam_down"):
			keyboard_direction.y += 1
		
	if keyboard_direction != Vector2.ZERO:
		was_moving = true
		last_move_dir = keyboard_direction
		target_position += (keyboard_direction.normalized() * scroll_speed * delta)
	
	clamp_target_position()
	
	# Headless, land now (Pacing.beat / pan_to's escape; third member 2026-08-26): the asymptotic
	# lerp never settles, so a headless test sampling anything camera-derived reads frame timing.
	if DisplayServer.get_name() == "headless":
		global_position = target_position
	else:
		global_position = global_position.lerp(target_position, move_speed * delta)
	
	if keyboard_direction == Vector2.ZERO:
		if global_position.distance_to(target_position) < 2:
			#Doing this to stop jerky movements.  Always move to the next tile over.  
			if was_moving:
				snap_to_grid()
				was_moving = false

	if global_position.distance_to(target_position) < 2:
		lock_manual_input = false

func snap_to_grid():
	if last_move_dir.x > 0:
		target_position.x = ceil(target_position.x / TILE_SIZE) * TILE_SIZE
	elif last_move_dir.x < 0:
		target_position.x = floor(target_position.x / TILE_SIZE) * TILE_SIZE
	else:
		target_position.x = round(target_position.x / TILE_SIZE) * TILE_SIZE
		
	if last_move_dir.y > 0:
		target_position.y = ceil(target_position.y / TILE_SIZE) * TILE_SIZE
	elif last_move_dir.y < 0:
		target_position.y = floor(target_position.y / TILE_SIZE) * TILE_SIZE
	else:
		target_position.y = round(target_position.y / TILE_SIZE) * TILE_SIZE

# Does a 3D host own board input right now? The same one flag game.gd's _unhandled_input
# reads -- one question, one answer. Explicitly typed: `game` is untyped, so `:=` cannot
# infer through it. Null-guarded so a bare CameraController (fixtures) scrolls normally.
func _input_delegated() -> bool:
	if game == null:
		return false
	var delegated: bool = game.board_input_delegated
	return delegated

func set_playback_locked(locked: bool) -> void:
	playback_locked = locked
	# Cleared on BOTH edges, not just the release (#520). Claiming is a fresh pass, and the 3D rig
	# re-solves this line against the detent it squares up to at that moment -- so a line left over
	# from the previous squad would swing the camera off the new baseline before any beat ran.
	directed_line = []
	# The span goes with it, and needs the both-edges clear even more than the line does: the rig
	# widens on the CHANGE, so a span surviving a claim would be the same value the mirror already
	# has and the next squad's walk would open at whatever zoom the last one left.
	framed_span = []
	# ...and the weight, which needs it for the SAME reason the span does: the rig re-solves the
	# push-in every frame from this value, so one surviving a claim would push the next squad's opening
	# shot in on a beat that has not earned it.
	beat_emphasis = 0.0
	# ...and whether the pass shows a fight, which needs the both-edges clear MOST of the four: the
	# health readout reads it to decide whether to override the player's own setting, so one
	# surviving a release would leave every bar on the board up until the next pass turned it off.
	# A claiming pass publishes its own answer immediately after this call.
	playback_cinematic = false
	if not locked:
		follow_unit = null

func follow(unit: Unit) -> void:
	follow_unit = unit
	
# Smoothly pans from wherever the camera currently is to `unit`'s position over a FIXED
# duration (not fixed speed) -- a short hop and a cross-map jump read at the same pace,
# giving the player a consistent beat to reorient before the next squad acts. Switches to
# continuous follow() once the pan lands. The duration is Pacing's (#118); fixed-vs-speed is
# the design, the number is a knob.
func pan_to(unit: Unit, duration: float = Pacing.AI_SQUAD_PAN) -> void:
	await pan_to_position(unit.global_position, duration)
	follow(unit)

# pan_to's POSITION-taking half, and the tween both share (#520): a point that is not a unit -- the
# MIDPOINT of a walk, so the shot opens on both its ends. No closing follow(), and that is the whole
# difference: framing both ends only means anything if the camera HOLDS while the walk crosses it,
# where following would drag the far end straight back out of frame.
func pan_to_position(world_pos: Vector2, duration: float = Pacing.AI_SQUAD_PAN) -> void:
	follow_unit = null
	# Nobody is watching a headless run, and the glide is awaited once per AI squad -- tweening it
	# there is pure suite wall clock. Land on the destination exactly as the tweened path does.
	if DisplayServer.get_name() == "headless":
		_apply_pan_position(world_pos)
		return
	_panning = true
	var start := global_position
	var tween := create_tween()
	tween.tween_method(_apply_pan_position, start, world_pos, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	_panning = false

func _apply_pan_position(pos: Vector2) -> void:
	global_position = pos
	target_position = pos
