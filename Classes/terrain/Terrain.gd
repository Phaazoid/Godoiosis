class_name Terrain
extends Object

const BURNING_TILE_DAMAGE := 5
const COVER_DEF := 2   # flat DEF a Cover tile grants its occupant (#84 Burrow) — a tuning dial

# Tile vocabulary for #50 — deliberately SEPARATE from Elemental (dev call 2026-06-28).
# A tile's condition is its own enum, not Elemental.State; the two stay independent until
# something explicitly bridges them. docs/design/terrain.md owns the persistent bookkeeping.

# Dynamic per-cell condition an attack deposits and a reaction reads. Stored in
# TerrainStateManager + (later) ScenarioData.tile_data, so it serializes as an int:
# APPEND-ONLY. NONE = 0 = unset default.
enum TileState {
	NONE,
	BURNING,
	FROZEN,  # Permanent (no STATE_DURATIONS entry -> never ticks out) since 2026-08-12 playtest
			 # feedback -- ice held a 3-turn clock like BURNING until the dev found an auto-thaw
			 # unwelcome. Removed only by states_removed (the authored FIRE Melt reaction,
			 # Resources/TerrainReactions/Melt.tres), same mechanism as COVER.
	COVER,   # #84: Burrow-dug entrenchment. Permanent (no STATE_DURATIONS entry -> never ticks out);
			 # removed only by a destructive hit (states_removed), never by a timer.
	BLAZE    # #174: authored set-dressing fire -- BURNING's permanent sibling (COVER's no-timer
			 # mechanism). Same end-of-turn damage; deposited only by the dev brush so far.
}

# "Is this tile on fire?" has ONE spelling (#174): FIRE_STATES is which states count, is_burning
# the predicate over a cell's states, TerrainStateManager.burning_cells the enumeration form.
# No reader may enumerate fire members itself.
const FIRE_STATES: Array[TileState] = [TileState.BURNING, TileState.BLAZE]

static func is_burning(states: Array[TileState]) -> bool:
	for state in states:
		if FIRE_STATES.has(state):
			return true
	return false

# Static authored tile content, read straight off the tileset's "terrain_type" int
# custom-data layer (Resources/TestTiles.tres). Serialized in the .tres: APPEND-ONLY.
# NONE = 0 = unset default (decorative tiles carry no kind).
enum Kind {
	NONE,
	GRASS,
	MUD,
	ROCK,
	TREE,
	WATER,
	DIRT,  # bare ground: no reactions key on it, so it cannot catch fire -- the non-flammable
		   # default ground beside GRASS (which ignites)
	VOID   # #259: a bottomless hole -- chasm, airship edge, train side. Unwalkable like water, but
		   # a shove FLIES OVER it and a shove that ENDS on it removes the unit outright (the #116
		   # kill doctrine). The two authored `hole` tiles carry it; the headless no-tile sentinel
		   # renamed to "offmap" so this member owns the word.
}

# Which way a ramp cell RISES (#218/#257). Stored per-cell in BoardHeights and serialized into
# ScenarioData as an int: APPEND-ONLY. NONE = 0 = unset default (an ordinary flat cell).
#
# A DIRECTION, not an axis, and that is the whole point: docs/design/verticality.md sketched
# {NONE, NS, EW}, which cannot say which side is high — a ramp at height N with a NS axis could
# climb to either neighbour, and if both sit at N+1 the rule has no answer. One field carries the
# axis AND the high side, and the dev's "ramps connect exactly their high/low sides, no sideways
# entry" ruling becomes a single question: does this step run along the rise axis?
enum RampRise {
	NONE,
	NORTH,
	SOUTH,
	EAST,
	WEST
}

const RISE_DIRECTIONS: Dictionary[RampRise, Vector2i] = {
	RampRise.NONE: Vector2i.ZERO,
	RampRise.NORTH: Vector2i.UP,
	RampRise.SOUTH: Vector2i.DOWN,
	RampRise.EAST: Vector2i.RIGHT,
	RampRise.WEST: Vector2i.LEFT
}

# The step direction that climbs this ramp. ZERO for NONE, which is what makes is_on_rise_axis
# below refuse every direction on a flat cell without a special case.
static func rise_direction(rise: RampRise) -> Vector2i:
	return RISE_DIRECTIONS[rise]

# Does a step run along this ramp's slope (either up it or down it)? The "no sideways entry" rule,
# in one place — a ramp may only be entered or left along the axis it rises on.
static func is_on_rise_axis(rise: RampRise, step: Vector2i) -> bool:
	var dir := rise_direction(rise)
	return dir != Vector2i.ZERO and (step == dir or step == -dir)

# --- Corner heights (#427) ---------------------------------------------------------------------
# Ground geometry is FOUR CORNER HEIGHTS per cell, stored in BoardHeights; RampRise above is the
# derived READING of a flat-or-cardinal-ramp shape, no longer stored truth. Corners are per-TILE and
# never a shared vertex grid — neighbours may disagree, and disagreement IS a cliff.

# One elevation unit is HALF a level, so a 45 deg ramp rises 2 units over one cell (dev, 2026-08-23:
# "our current 45 degree angle platforms will now just hop 2 levels instead of one"). Re-basing the
# integer is what lets half elevations exist without turning any comparison into a float — the
# objection verticality.md records against half-steps.
const UNITS_PER_LEVEL := 2

# The corner order packed into a Vector4i is NW, NE, SE, SW — clockwise from north-west, north being
# -Y to match RISE_DIRECTIONS. Slice 3 needs to address one by name, so the convention is now a bit
# per corner as well, in the same order.
const CORNER_NW := 1
const CORNER_NE := 2
const CORNER_SE := 4
const CORNER_SW := 8

# A cell's FORM is a MASK of which corners are raised, plus how far (#427 slice 3) — never an enum
# member per diagonal. #263 found the same shape for wall facings: a facing became a mask of EDGES,
# and the corner fell out for free as an L. Here the cardinal ramp stops being its own thing and
# becomes one member of a family: 0 is flat, the four single bits are outer corners, the four
# ADJACENT pairs are exactly the cardinal ramps RampRise already names, the four triples are inner
# corners, and the two OPPOSITE pairs are the saddles the dev refused ("no saddles", 2026-08-23).
#
# 15 is unreachable by construction, which is worth stating because it looks like a gap: the mask
# names corners strictly ABOVE the cell's own low corner, and a cell always has one, so all four can
# never be raised at once. Flat is 0 and only 0.
const SADDLE_MASKS: Array[int] = [CORNER_NW | CORNER_SE, CORNER_NE | CORNER_SW]

# The 45 deg steepness cap ("steepness cap at 45 is good" — dev, 2026-08-23) is UNITS_PER_LEVEL and
# has no constant of its own: a climb is a whole number of units and one level is the most a legal
# form may span, so is_legal_corners compares against the unit that already says it. It became a real
# check in slice 3 — before that corners_of_ramp was the only writer and could not break it.

# Which corners each cardinal ramp raises. ONE table, read in BOTH directions — corners_of_ramp
# composes through it and rise_of_corners reads back through it — so a direction cannot compose one
# way and read another, which is a quarter of every ramp being silently wrong.
const RISE_MASKS: Dictionary[RampRise, int] = {
	RampRise.NONE: 0,
	RampRise.NORTH: CORNER_NW | CORNER_NE,
	RampRise.SOUTH: CORNER_SE | CORNER_SW,
	RampRise.EAST: CORNER_NE | CORNER_SE,
	RampRise.WEST: CORNER_NW | CORNER_SW
}

# THE composer (#427 slice 3): a form is a raised-corner MASK plus how far it rises. `low` is the
# cell's own height in units, because a ramp's height is its LOW side (verticality.md, DECIDED).
#
# The climb DEFAULTS to a full level (#427 slice 2), which is what every pre-slice-2 caller means and
# why ~60 fixtures needed no sweep. A climb of 1 is the RCT gentle slope: half a level over one cell
# of run, i.e. atan(1/2) = 26.6 deg, the angle the dev half-remembered as 30.
static func corners_of_form(low: int, mask: int, climb := UNITS_PER_LEVEL) -> Vector4i:
	if mask == 0 or climb <= 0:
		return Vector4i(low, low, low, low)
	var high := low + climb
	return Vector4i(
		high if (mask & CORNER_NW) != 0 else low,
		high if (mask & CORNER_NE) != 0 else low,
		high if (mask & CORNER_SE) != 0 else low,
		high if (mask & CORNER_SW) != 0 else low)


# The cardinal-ramp spelling of it, which is what the BRUSH authors and what ~60 fixtures build.
# Not a second composer -- it names a mask out of the one table above.
static func corners_of_ramp(low: int, rise: RampRise, climb := UNITS_PER_LEVEL) -> Vector4i:
	return corners_of_form(low, RISE_MASKS[rise], climb)

# How far this cell's surface climbs, in units — 0 for flat ground. The SECOND question a ramp
# answers (#427 slice 2), and its own accessor rather than a member of RampRise: which way a slope
# faces and how steep it is are different questions, and folding them together would double an
# append-only enum while making is_on_rise_axis unpack a direction out of a compound value.
static func climb_of_corners(corners: Vector4i) -> int:
	var low := mini(mini(corners.x, corners.y), mini(corners.z, corners.w))
	return maxi(maxi(corners.x, corners.y), maxi(corners.z, corners.w)) - low


# The cell's LOW corner — its rule height, and the base every other reading is relative to.
static func low_of_corners(corners: Vector4i) -> int:
	return mini(mini(corners.x, corners.y), mini(corners.z, corners.w))


# WHICH corners are raised — the cell's form (#427 slice 3). Bits in the Vector4i's own order, so a
# reader never has to remember which component is which compass point.
static func corner_mask(corners: Vector4i) -> int:
	var high := low_of_corners(corners) + climb_of_corners(corners)
	if climb_of_corners(corners) == 0:
		return 0
	var mask := 0
	if corners.x == high:
		mask |= CORNER_NW
	if corners.y == high:
		mask |= CORNER_NE
	if corners.z == high:
		mask |= CORNER_SE
	if corners.w == high:
		mask |= CORNER_SW
	return mask


# May ground be this shape? THREE refusals, and each is a dev ruling rather than a taste:
#
# - more than two distinct heights is not a FORM at all. A form is a mask plus a climb, which is the
#   RCT model the reframe asks for, so a cell has a low corner and a raised set and nothing between.
#   The corner-drag tool (slice 4) is meant to be structurally unable to author one.
# - a climb over UNITS_PER_LEVEL breaks the 45 degree cap ("steepness cap at 45 is good").
# - the two OPPOSITE-pair masks are saddles ("no saddles"). Refused GROUND, not a legal form.
#
# Nothing can author an illegal shape today -- corners_of_ramp is still the only writer, and the
# brush only speaks cardinal -- so this is deliberately a PREDICATE rather than a lint tier. A check
# wired to a surface nothing can reach is a check that cannot fire (#390); the tier arrives with the
# tool that can break it.
static func is_legal_corners(corners: Vector4i) -> bool:
	var climb := climb_of_corners(corners)
	if climb == 0:
		return true
	if climb > UNITS_PER_LEVEL:
		return false
	var low := low_of_corners(corners)
	var high := low + climb
	for corner: int in [corners.x, corners.y, corners.z, corners.w]:
		if corner != low and corner != high:
			return false   # a third height: not a mask-and-climb form
	return not SADDLE_MASKS.has(corner_mask(corners))


# The two corner heights along the edge this cell shares with its `dir` neighbour, in a fixed SPATIAL
# order — west-to-east for a north or south edge, north-to-south for an east or west edge (#427
# slice 3). That ordering is the whole point: one edge named from either side gives the same two
# points in the same order, so `edge_of_corners(a, d) == edge_of_corners(a + d, -d)` IS the question
# "do these two surfaces meet here?", with no per-caller pairing rule to get wrong.
#
# It replaces comparing a height DELTA against a ramp's climb, and the sideways-entry guard falls out
# of it: a north-rising ramp's east edge reads (high, low) against its flat neighbour's (low, low),
# so the step is refused by the same comparison rather than by a clause of its own.
static func edge_of_corners(corners: Vector4i, dir: Vector2i) -> Vector2i:
	match dir:
		Vector2i.UP:
			return Vector2i(corners.x, corners.y)   # north: NW, NE
		Vector2i.DOWN:
			return Vector2i(corners.w, corners.z)   # south: SW, SE
		Vector2i.RIGHT:
			return Vector2i(corners.y, corners.z)   # east: NE, SE
		Vector2i.LEFT:
			return Vector2i(corners.x, corners.w)   # west: NW, SW
	return Vector2i.ZERO


# The surface height, in UNITS, at a point inside the cell — u east across it, v south down it, both
# 0..1. A quad with four independent corner heights is NOT planar, so the cell is two triangles and
# WHICH DIAGONAL splits them is real geometry: joining the two EQUAL corners gives every legal form a
# flat half and a sloped half, which is the RCT shape. Take the other diagonal and an outer corner
# becomes a hip roof instead.
#
# THE MESH GENERATOR READS THIS TOO, and it has to: if the query and the drawn cap disagreed about
# the diagonal, a sprite crossing a corner cell would float or sink by up to a quarter of the climb —
# half a level on a steep corner, which is visible. One question, one answer.
#
# Flat and cardinal forms are planar, so either diagonal is exact for them and the test below simply
# picks one.
static func height_at_uv(corners: Vector4i, u: float, v: float) -> float:
	var nw := float(corners.x)
	var ne := float(corners.y)
	var se := float(corners.z)
	var sw := float(corners.w)
	if corners.y == corners.w:
		# Split NE--SW. NW's triangle is u + v <= 1.
		if u + v <= 1.0:
			return nw + (ne - nw) * u + (sw - nw) * v
		return se + (sw - se) * (1.0 - u) + (ne - se) * (1.0 - v)
	# Split NW--SE. NE's triangle is v <= u.
	if v <= u:
		return nw + (ne - nw) * u + (se - ne) * v
	return nw + (sw - nw) * v + (se - sw) * u


# How the cell's surface SLOPES, in units per cell, as (east, south) — the best-fit plane through the
# four corners. Exact for every planar form (flat and the cardinal ramps), and for a corner form it is
# the average the markup and the tilt want: a diagonal downhill rather than a cardinal one.
static func gradient_of_corners(corners: Vector4i) -> Vector2:
	var east := float((corners.y - corners.x) + (corners.z - corners.w)) * 0.5
	var south := float((corners.w - corners.x) + (corners.z - corners.y)) * 0.5
	return Vector2(east, south)


# The height at the cell's CENTRE — where anything lying on the surface pivots. The corners' mean,
# which for a cardinal ramp is its low side plus half its climb, exactly as before.
static func centre_height_of_corners(corners: Vector4i) -> float:
	return float(corners.x + corners.y + corners.z + corners.w) * 0.25


# Which cardinal ramp these corners describe, or NONE. STILL THE AUTHORING vocabulary — the brush
# paints cardinal ramps and corners_of_ramp composes them — but no longer the universal READING: a
# corner form is a shape RampRise cannot name, so this answers NONE for one rather than erroring.
#
# It stopped push_error-ing in slice 3, and that is the migration itself: the refusal existed to find
# every reader that would quietly read a corner form as flat, and those readers now ask the corners.
# The remaining callers genuinely want "is this one of the four cardinal ramps?" and NONE is the true
# answer for anything else. is_legal_corners is what refuses ground that should not exist.
static func rise_of_corners(corners: Vector4i) -> RampRise:
	var mask := corner_mask(corners)
	if mask == 0:
		return RampRise.NONE
	for rise: RampRise in RISE_MASKS:
		if RISE_MASKS[rise] == mask:
			return rise
	return RampRise.NONE   # an outer or inner corner: a shape RampRise cannot name

# Which whole LEVEL a height in units amounts to. FLOOR rather than truncation, so a descent of one
# and a half levels charges for one rather than for two.
#
# It is NOT a presentation conversion any more (#427 slice 2): a GridMap row is now one unit, so the
# 3D stack reads units directly and this is left to the rules that genuinely count LEVELS — fall
# damage, and the "Fell 2!" popup beside it. A caller reaching for it to place geometry is asking
# the wrong question.
static func level_of(units: int) -> int:
	return floori(float(units) / float(UNITS_PER_LEVEL))

# The player-facing spellings ("Burning", "Water") — Elemental.display_name's rule applied to the
# tile vocabularies. Hover readouts and the Glossary's composed lines read these; dev readouts
# that deliberately show the raw enum key keep doing so.
static func tile_state_display_name(s: TileState) -> String:
	return TileState.keys()[s].capitalize()

static func kind_display_name(k: Kind) -> String:
	return Kind.keys()[k].capitalize()

static func ramp_rise_display_name(r: RampRise) -> String:
	return RampRise.keys()[r].capitalize()
