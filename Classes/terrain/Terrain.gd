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

# The step direction that climbs this ramp. ZERO for NONE.
static func rise_direction(rise: RampRise) -> Vector2i:
	return RISE_DIRECTIONS[rise]

# is_on_rise_axis went with #427 slice 3 — DELETED, not relaxed. It was the "no sideways entry" rule
# and its only callers were can_step's two guards; comparing the shared EDGE answers every case it
# answered, plus the one the dev then ruled on (two adjacent slopes that genuinely meet DO connect).
# A rule that falls out of the geometry does not need a clause standing beside it.

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


# The three sloped SHAPES, which is what the meshes are cut for (#427 slice 3). Twelve legal
# non-flat masks, but only three shapes: the GridMap's own yaw supplies the four rotations of each,
# so eight new forms cost TWO new meshes rather than eight.
enum Form { FLAT, WEDGE, OUTER, INNER }

# The one orientation of each shape the meshes are AUTHORED in, and the anchor every yaw is measured
# from. WEDGE is the cardinal ramp rising NORTH, which is how the wedge mesh has always been drawn
# (high edge at -Z); OUTER raises the NW corner; INNER lowers the SE one, so the two corner families
# are complements in the same orientation and rotate together.
const CANONICAL_MASKS: Dictionary[Form, int] = {
	Form.FLAT: 0,
	Form.WEDGE: CORNER_NW | CORNER_NE,
	Form.OUTER: CORNER_NW,
	Form.INNER: CORNER_NW | CORNER_NE | CORNER_SW
}

# Which shape a mask is — by how many corners it raises, which is the whole classification. An
# illegal mask (a saddle) has no shape and answers FLAT; is_legal_corners is what refuses it, and a
# renderer reaching here for one has already been handed ground that should not exist.
static func form_of_mask(mask: int) -> Form:
	match _bits_in(mask):
		1:
			return Form.OUTER
		2:
			return Form.WEDGE if not SADDLE_MASKS.has(mask) else Form.FLAT
		3:
			return Form.INNER
	return Form.FLAT


static func _bits_in(mask: int) -> int:
	var count := 0
	for bit in [CORNER_NW, CORNER_NE, CORNER_SE, CORNER_SW]:
		if (mask & bit) != 0:
			count += 1
	return count


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


# --- The vertex layer (#427 slice 4) ---

# The four corners a grid VERTEX is. `Vector2i(x, y)` is the NW corner of cell (x, y), and the same
# physical point is (x-1, y)'s NE, (x, y-1)'s SW and (x-1, y-1)'s SE — cell OFFSET to corner BIT, and
# the one place that mapping lives.
#
# Corners stay per-TILE and this is emphatically not a shared vertex grid: two neighbours disagreeing
# about the edge they meet on IS a cliff, and the cell brush still authors that. What a vertex names
# is the point the corner TOOL addresses, so one drag can weld the four surfaces meeting there
# instead of leaving the cut-off gap that opened #427.
const VERTEX_CORNERS: Dictionary[Vector2i, int] = {
	Vector2i(0, 0): CORNER_NW,
	Vector2i(-1, 0): CORNER_NE,
	Vector2i(-1, -1): CORNER_SE,
	Vector2i(0, -1): CORNER_SW
}

# Which Vector4i component each corner bit addresses — the WRITE direction of corner_mask's read, and
# the only bridge between the two spellings. A hand-written `match` at a write site would be a second
# mapping, i.e. a quarter of every corner drag landing silently on the wrong corner.
const CORNER_COMPONENTS: Dictionary[int, int] = {
	CORNER_NW: 0,
	CORNER_NE: 1,
	CORNER_SE: 2,
	CORNER_SW: 3
}

static func with_corner(corners: Vector4i, bit: int, height: int) -> Vector4i:
	var result := corners
	result[CORNER_COMPONENTS[bit]] = height
	return result


static func corner_height(corners: Vector4i, bit: int) -> int:
	return corners[CORNER_COMPONENTS[bit]]


# THE CLAMP (#427 slice 4): the legal shape nearest to "this corner goes to `height`". It ASKS
# is_legal_corners rather than restating which of the three refusals it tripped — the predicate stays
# the one place legality lives, so the tool cannot grow a second opinion about saddles or the 45
# degree cap, and a rule added there reaches the tool for free.
#
# The walk steps from the target TOWARD the corner's current height, which is what makes it
# terminate: `corners` is already legal, so the worst case is the corner not moving at all. That also
# settles the tie — with the cap at UNITS_PER_LEVEL the only value strictly between two legal ones is
# equidistant from both, so "nearest" is genuinely ambiguous there and standing still wins.
#
# Consequence, and it is the "one ring, clamped" ruling working as intended rather than a shortfall:
# a corner stops rising once its own tile would break, so a tall hill takes several strokes across
# neighbouring points instead of one drag that cascades outward across the board.
static func corner_toward(corners: Vector4i, bit: int, height: int) -> Vector4i:
	var current := corner_height(corners, bit)
	var step := signi(current - height)
	var candidate := height
	while candidate != current:
		var shaped := with_corner(corners, bit, candidate)
		if is_legal_corners(shaped):
			return shaped
		candidate += step
	return corners


# Which vertex a point INSIDE a cell is nearest — u east across it, v south down it, both 0..1, the
# same parameterisation height_at_uv takes. ONE derivation, because the flat view and the 3D pick
# reach it from opposite directions (a local position against a ray hit) and must not round
# differently about which corner the cursor has hold of.
#
# Naturally saturating rather than clamped: a hit that lands a hair outside the cell still answers
# that cell's nearer edge, which is the honest reading of a grazing pick.
static func vertex_near(cell: Vector2i, u: float, v: float) -> Vector2i:
	return cell + Vector2i(1 if u >= 0.5 else 0, 1 if v >= 0.5 else 0)



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


# Is this cell's surface a PLANE? Flat ground and the four cardinal ramps are; an outer or inner
# corner is not, because its four surface points are not coplanar (#427 slice 4 follow-up).
#
# It matters wherever a single Transform3D is asked to describe the surface: an affine transform maps
# a plane to a plane, so on a corner form the best-fit plane CROSSES the ground — measured at a
# quarter of the climb at every corner, alternating sign. Whoever asks has to carry the fold some
# other way, and BoardOverlays carries it in the MESH.
#
# Composed from the two answers that already exist rather than testing the mask itself: a cardinal
# rise IS the planar non-flat case, and re-deriving that from CORNER bits would be a second spelling
# of RISE_MASKS.
static func is_planar_form(corners: Vector4i) -> bool:
	return climb_of_corners(corners) == 0 or rise_of_corners(corners) != RampRise.NONE


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
