class_name AimFlash2D
extends Node2D

# THE AIM'S TRAVEL-ORDER FLASH (#1057 part 2): each tile of the aim footprint flashes WHITE on the step
# the attack reaches it, then the loop rests and plays again (#1054 rulings 19 and 27). A true AoE is
# all step 0, so it flashes at once; a swing flashes in the order it travels, and a revisited tile
# flashes on each visit. The yellow under it is the hover layer's, untouched -- the flash only ever
# ADDS white, which is what keeps the covered tiles readable between flashes.
#
# THE 2D IS THE AUTHORITY AND THIS IS ITS CLOCK. OverlayMirror copies levels() into the diorama's AIM
# quads every frame and keeps no clock of its own, so the two views cannot drift -- and because this
# node lives under Game, ModalLock's freeze holds the flash still in both views for free.
#
# PHOTOSENSITIVITY (#217) holds every tile still, GRADED IN WHITE by step (ruling 28): the first step
# palest, the last plain. It is polled, because PlayerSettings has no changed signal.
#
# The rule is static and pure (level / still_level), so a case states a time and reads a brightness.

# Game-tab knobs (GameKnobs.CLASS_KNOBS, Aiming). Feel values: no test pins them.
static var STEP_SECONDS := 0.14    # between one step of travel and the next
static var FLASH_SECONDS := 0.35   # one tile's whole flash
static var REST_SECONDS := 0.75    # quiet time before the loop plays again
static var FLASH_PEAK := 0.85      # how white a tile gets at the top of its flash
static var STILL_PEAK := 0.6       # how white the first step holds with photosensitivity on

# The envelope's shape inside one flash: a quick rise, a hold at the peak, a longer fall.
const RISE_SHARE := 0.2
const HOLD_SHARE := 0.3

var steps: Dictionary[Vector2i, Array] = {}
var clock := 0.0
var _still := false


# A new footprint starts the travel from the top; the SAME one keeps its running loop, so holding one
# aim never restarts it on a re-hover.
func show_steps(new_steps: Dictionary[Vector2i, Array]) -> void:
	if new_steps == steps:
		return
	steps = new_steps.duplicate(true)
	clock = 0.0
	queue_redraw()


func clear() -> void:
	var none: Dictionary[Vector2i, Array] = {}
	show_steps(none)


func _process(delta: float) -> void:
	if steps.is_empty():
		return
	var still := not motion_allowed()
	if still:
		if not _still:
			queue_redraw()
	else:
		clock += delta
		queue_redraw()
	_still = still


# Every footprint tile's whiteness right now, 0 to 1. The one read both views draw from.
func levels() -> Dictionary[Vector2i, float]:
	var out: Dictionary[Vector2i, float] = {}
	if steps.is_empty():
		return out
	var last := last_step(steps)
	var moving := motion_allowed()
	var t := fposmod(clock, loop_seconds(last))
	for cell: Vector2i in steps:
		out[cell] = level(steps[cell], t) if moving else still_level(steps[cell], last)
	return out


func _draw() -> void:
	var size := Vector2.ONE * float(GridUtils.TILE_SIZE)
	var at := levels()
	for cell: Vector2i in at:
		if at[cell] > 0.0:
			draw_rect(Rect2(Vector2(cell) * float(GridUtils.TILE_SIZE), size), Color(1, 1, 1, at[cell]))


# --- The rule ---------------------------------------------------------------------------------------

static func motion_allowed() -> bool:
	return not PlayerSettings.is_on(PlayerSettings.Setting.PHOTOSENSITIVITY)


static func last_step(timed: Dictionary[Vector2i, Array]) -> int:
	var last := 0
	for cell: Vector2i in timed:
		for step: int in timed[cell]:
			last = maxi(last, step)
	return last


# One loop: the whole travel, the last tile's flash, then the rest.
static func loop_seconds(last: int) -> float:
	return last * STEP_SECONDS + FLASH_SECONDS + REST_SECONDS


# One flash, `dt` seconds after it began: 0 before and after, 1 at the peak.
static func envelope(dt: float) -> float:
	var rise := FLASH_SECONDS * RISE_SHARE
	var hold := FLASH_SECONDS * HOLD_SHARE
	if dt < 0.0 or dt > FLASH_SECONDS:
		return 0.0
	if dt < rise:
		return dt / rise
	if dt < rise + hold:
		return 1.0
	return 1.0 - (dt - rise - hold) / (FLASH_SECONDS - rise - hold)


# A tile's whiteness at loop time `t`, reached on each of `visits`.
static func level(visits: Array, t: float) -> float:
	var best := 0.0
	for step: int in visits:
		best = maxf(best, envelope(t - step * STEP_SECONDS))
	return best * FLASH_PEAK


# The photosensitive still: graded by the tile's FIRST step, palest first, the last step plain. An
# attack with no order to show (a true AoE, one tile) is plain throughout.
static func still_level(visits: Array, last: int) -> float:
	if last <= 0 or visits.is_empty():
		return 0.0
	var first: int = visits.min()
	return STILL_PEAK * (1.0 - float(first) / float(last))


# A footprint colour whitened by a level -- the diorama's twin of drawing white over the 2D tile.
static func tint(base: Color, whiteness: float) -> Color:
	var lit := base.lerp(Color.WHITE, whiteness)
	return Color(lit.r, lit.g, lit.b, base.a)
