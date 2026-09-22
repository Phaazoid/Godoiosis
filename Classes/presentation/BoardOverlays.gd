extends Node3D
class_name BoardOverlays

# The 3D presentation stack's board markup (#213 / #176 stages 3+4c): the one owner
# of per-cell overlay layers. Four marker kinds — FILL (pooled unshaded quads lying
# on the cell's top face; the dev's ruling that gameplay markup must never read as
# terrain, which a lit Decal cannot honor), BRACKET (the voxel corner-bracket
# pointer), SPRITE (a ground quad with per-marker texture+tint — path arrows,
# knockback trails, terrain icons, pick markers), BILLBOARD (a camera-facing
# Sprite3D above the cell — selection icons). Layer colors deliberately mirror the
# 2D OverlayManager's constants — one declared representation per presentation
# stack (the parallel-stacks doctrine); change a color in both places or say why not.
#
# Contract: a dumb idempotent sink. set_cells/set_markers replace a layer wholesale
# and are cheap ONLY when the caller diffs first (OverlayMirror does); marker pos is
# the cell's top-face ANCHOR (the mirror's geometry), and the LAYER adds its own
# lift — board shape stays the caller's business.
#
# The layers are PARTITIONED BY WRITER, which is why there is no whole-sink wipe: battle3d owns
# HOVER (the pointer bracket, the one layer deliberately not mirrored) and OverlayMirror owns the
# rest, caching what it has pushed. Emptying every layer at once is therefore always one writer
# reaching across that line and desyncing the other's cache — the clear_all() this used to carry
# did exactly that on every board load (#318). Clear the layers you own.
#
# The mask contract: fill/sprite quads render on WORLD_RENDER_LAYER only, and
# UnitSprite3D lives on UNIT_RENDER_LAYER. Both constants live HERE; a drift test
# pins them disjoint.

enum Layer {
	MOVE, ATTACK, ZONE_CAPTURE, ZONE_EXTRACTION, HOVER,
	INVALID_MOVE, AIM,
	TARGET_PICK, PATH_ARROWS, KNOCKBACK, TERRAIN, TERRAIN_PREVIEW, ICONS,
	ZONE_PATROL, ZONE_HIGHLIGHT, GROUND_ICONS, ATTACK_BLOCKED, SIGHT_TRACE,
	GUARD_ICONS, GUARD_LINK, WATCH_ICONS,
	ZONE_DEPLOYMENT, ZONE_DEFEND,
	REACH, THREAT, ENEMY_FOCUS_EDGE, REACH_LINES,
	COHESION_EDGE, TETHERS, TETHER_GHOST, TETHER_STRAIN,
}
enum Kind { FILL, BRACKET, SPRITE, BILLBOARD, LINE }

const WORLD_RENDER_LAYER := 1  # bit for layer index 0 — the board and props
const UNIT_RENDER_LAYER := 2   # bit for layer index 1 — UnitSprite3D sets this
# Every unit sprite (real or planning ghost) sorts ABOVE every overlay layer, structurally
# rather than by numeric luck — the 3D twin of the 2D's "tile overlays sit below
# Unit.BASE_SPRITE_INDEX". Must stay greater than any LAYERS "sort"; pinned by a test.
# It only ARBITRATES in the alpha queue, though (#317): an OPAQUE_PREPASS sprite is held above
# markup by the depth it writes instead, and it writes none where alpha is under the prepass
# threshold — which is why UnitMirror builds the translucent ghosts alpha_cut DISABLED.
const UNIT_RENDER_PRIORITY := 32
# Fire's 3D form is a STANDING effect, not markup lying on the tile face, so it sorts above every
# overlay layer — the same structural claim units make, one band below them so the flame-vs-sprite
# relationship #236 argued over is untouched. Found in play (#245): the flame set no priority at
# all, so it sat at 0 while Layer.TERRAIN sorts at 2, and painting a frost icon onto a burning
# tile drew straight over the flame. The fire read as erased; the store was perfectly correct.
#
# NAMED FOR THE BAND rather than for fire since #887, which is its third tenant -- the slam dust
# (#656) was the second, and the previous name's own comment asked for this rename when a third
# arrived. Everything standing in the world that is not markup and not a body sorts here: fire, the
# tear-out's dust, and an arc's bolts. The two laws below it still speak of fire because fire is
# what a layer drawing over this band would visibly erase.
const EFFECT_RENDER_PRIORITY := 16
# The band above the units: HUD hung in the volume over a unit's head (#229's health readout), which
# must never be sorted behind the sprite it describes. It lives HERE with the other two because the
# relationship between the bands is the thing worth pinning, and a table is the only place a
# relationship can be read at a glance. The readout claims this value and the SIX above it: five
# coplanar quads (outline, missing, fill, the predicted span, the notch) then the number's outline
# and its glyphs.
const UNIT_HUD_RENDER_PRIORITY := 48

const LAYERS: Dictionary[Layer, Dictionary] = {
	# BLUE since #1066, and it is the player's half of a Fire Emblem readout: your unit says where it
	# may STAND in blue and where it could HIT from there in red, while an enemy is one undifferentiated
	# field. Sort 0 keeps it at the TOP of the range stack, which is what makes the intersect with an
	# enemy's purple read as tinted blue rather than as purple -- the composite the dev ruled on.
	# GRIDLINES rather than a wash since #1069 (dev, on 3D FE: "the player movement tiles don't
	# actually flood fill, only the gridlines of the tiles get the color highlights"), and since #1074
	# a line that runs to the tile's EDGE plus a faint square of the same blue inside it -- MoveGrid's
	# art, generated from four Game-tab knobs. It is STILL a Kind.FILL, so the sort, the lift, the
	# ramp tilt, the corner fold and the mirror's tint copy are untouched. Only YOUR movement range:
	# the reach under it and the enemy's field under that stay washes, on his ruling.
	# NB `"grid"` goes LAST -- see _texture_for.
	Layer.MOVE: {"color": Color(0.25, 0.45, 1.0, 0.8863), "sort": 0, "kind": Kind.FILL,
		"grid": true},
	Layer.ATTACK: {"color": Color(1, 0, 0, 0.5), "sort": 1, "kind": Kind.FILL},
	# Reach cells past the aim's vertical tolerance (#258). Shares ATTACK's sort safely: the 2D
	# splits the one layer by atlas coords, so the two cell sets are disjoint by construction and
	# can never z-fight. Colour here is only the no-mirror fallback -- OverlayMirror drives it per
	# frame as the live reach modulate x OverlayManager.BLOCKED_REACH_DIM (so no colour knob here).
	Layer.ATTACK_BLOCKED: {"color": Color(0.45, 0, 0, 0.5), "sort": 1, "kind": Kind.FILL},
	# The zone BAND sits at the bottom, with the picked-zone highlight alone above it. In 2D
	# the highlight wins by TREE ORDER (appended last); 3D has no such thing, so the sort
	# number IS the relationship and a test pins it rather than the values (#231).
	#
	# THE WHOLE NEGATIVE STACK HAS MOVED DOWN TWICE, both times for #710: slice 3 opened two slots
	# for the enemy's range tones, slice 4 two more for the dimmed CROWD beneath them, and each time
	# there were no free integers between SQUAD and MOVE. Downward, not upward: the positive side is
	# packed to 15 under the effect ceiling at 16, so lifting MOVE would cascade into it. Nothing
	# here pins a VALUE -- the laws are relationships (highlight above zones, PATROL == CAPTURE) and
	# they survive a uniform shift. What does NOT survive one is the FLOOR: _lift_of is fill_lift +
	# sort * lift_step, so the lowest sort must still clear the tile's own OPAQUE top face -- a real
	# z-fight, unlike the transparent-vs-transparent case below. At slice 3 that meant 0.02 -> 0.03;
	# at slice 4, -7 would have landed at 0.002 and fill_lift went to 0.04. The floor is a law.
	Layer.ZONE_CAPTURE: {"color": Color(0.3, 0.9, 1, 0.5), "sort": -7, "kind": Kind.FILL},
	Layer.ZONE_EXTRACTION: {"color": Color(0.4, 1, 0.5, 0.5), "sort": -7, "kind": Kind.FILL},
	Layer.ZONE_PATROL: {"color": OverlayManager.ZONE_PATROL_MODULATE, "sort": -7, "kind": Kind.FILL},
	# #736. In the band with the others: it is markup lying on the tile face like every zone, and it
	# is gone before any of them matter -- turn 1 stops it being drawn at all.
	Layer.ZONE_DEPLOYMENT: {"color": Color(0.65, 0.5, 1, 0.45), "sort": -7, "kind": Kind.FILL},
	# #571, and in the band for ZONE_DEPLOYMENT's reason. Reads its colour off OverlayManager rather
	# than restating it, the way ZONE_PATROL does -- the three literals above predate that rule.
	Layer.ZONE_DEFEND: {"color": OverlayManager.ZONE_DEFEND_MODULATE, "sort": -7, "kind": Kind.FILL},
	# Three literals the mirror overwrites from the 2D every poll (#710), ATTACK's shape: the
	# authored value is OverlayManager's static (or ThreatLines2D's), which a const table cannot name.
	Layer.ZONE_HIGHLIGHT: {"color": Color(1, 1, 1, 0.45), "sort": -6, "kind": Kind.FILL},
	# The PLAYER's reach (#1066): where the hovered or selected unit could hit from anywhere in the
	# blue above. Red, UNDER the blue, so it survives as the halo past the move envelope -- the same
	# relationship the enemy's own two tones had before this slice collapsed them.
	Layer.REACH: {"color": Color(1, 0.15, 0.1, 0.38), "sort": -1, "kind": Kind.FILL},
	# ...and the ENEMY's whole field under both of yours: move and reach together, ONE unbroken
	# reddish purple with no internal seam. That REPEALS #710 slice 3's pair and its ordering ruling,
	# on the dev's own instruction ("let's go with what fire emblem does"): the fine grain of "where
	# could it stand" as against "where could it hit" is a question you ask about your OWN unit.
	#
	# The ORDER is the whole design. Yours sorts ABOVE theirs, so a cell both fields cover composites
	# as blue TINTED purple rather than as purple -- which is what says "both" without a third colour
	# being authored anywhere. A sort IS a plane (_lift_of), so that is a real depth relationship and
	# not pool-allocation luck. A test pins THREAT < REACH < MOVE.
	#
	# Sorts -3 and -4 fell vacant when slice 4's dim pair went (the dev: "they shouldn't dim at
	# all"), and -5 when #1070 retired the orange squad fills for lines. They are left vacant rather
	# than compacted: the FLOOR is what a shift threatens --
	# _lift_of is fill_lift + sort * lift_step, and the -7 zones sit at 0.012 with fill_lift 0.04.
	Layer.THREAT: {"color": Color(0.72, 0.15, 0.28, 0.5), "sort": -2, "kind": Kind.FILL},
	# ...and a stroke round the OUTSIDE of the hovered enemy's whole footprint (slice 4, the dev's
	# addition to the mockup). Since #1066 it carries the WHOLE job of saying which enemy the pointer
	# is on -- every other enemy's field stays at full strength beside it, on his ruling that nothing
	# may dim. One two-point segment per outward-facing cell edge; no chaining into loops, because a
	# solid stroke draws identically either way.
	#
	# Sort 13 is the first free integer and it must be free: the rule in this table is that a layer
	# may not share a sort with any layer whose CELLS it can overlap, and a board-wide outline can
	# cross all of them. It lies ON the ground, which is what "lift_sort" says -- see _lift_of -- and
	# that number is the first ABOVE every FILL, so the stroke clears anything it can be drawn over
	# without anyone having to reason about which two layers can be up at once. Its
	# own beam parameters too ("beam"), because the shared trio is tuned for a LASER: at the sight
	# bead's width and its >1.2 bloom this would be a glowing rope around forty cells.
	Layer.ENEMY_FOCUS_EDGE: {"color": Color(1, 1, 1, 0.85), "sort": 13, "lift_sort": 5,
		"beam": "outline", "kind": Kind.LINE},
	# WHO CAN REACH THE CELL YOU ARE HOVERING (#1069) -- one mark per enemy whose field covers your
	# candidate destination, running enemy -> that cell, drawn ONLY while you are choosing a move.
	#
	# That REPEALS #710 slice 2's intent readout, on the dev's own ruling after looking at 3D FE:
	# "they aren't conveying enemy intent at all, just who can reach who. And they don't show all
	# the time, just during move hover mode." It is slice 1's reach lines coming back with the
	# narrower trigger that answers why slice 3 deleted them ("a bit too much") -- what was too much
	# was a board-wide beam channel standing up at rest, not the channel itself.
	#
	# ONE LAYER, where the intent pair was two. The second existed to carry "flash" for a FELLING
	# intent, and reachability cannot know lethality without running the ladder -- slice 1's lines
	# had no fatal variant either. Declared rather than forgotten; the flash channel went with it.
	#
	# Above the sight beam at 7 -- this is the authoritative readout over a cell the aim may also be
	# tracing -- and clear of the guard channels at 8/9, which
	# test_both_guard_channels_sorts_are_unshared caught the intent layer taking on its first draft.
	# Its own beam set ("mark"): this is markup that TRAVELS, so it carries the bead and is tuned
	# nothing like the sight laser. Colour arrives per draw from ThreatLines2D's one static.
	Layer.REACH_LINES: {"color": Color(1.0, 0.251, 0.784, 0.95), "sort": 11,
		"beam": "mark", "kind": Kind.LINE},
	# Above its own line at 11 and under the lawful ceiling: EFFECT_RENDER_PRIORITY is 16 and
	# ICONS holds 15, both pinned by laws in test_board_overlays. A number that drew over fire
	# would erase the flame it sits beside, which is how #245 found this rule.
	Layer.HOVER: {"color": Color(1, 0.9, 0.3, 0.9), "sort": 2, "kind": Kind.BRACKET},
	# Tiles you could walk to that the SQUAD will not let you take -- a member's past the leader's range,
	# a leader's that would strand somebody. GREY GRIDLINES since #1070, where they were a mauve wash in
	# the enemy purple's own family: MOVE's lattice switched off, which is what "walkable, not now" is.
	# Its cells never meet MOVE's (one tile is one or the other), so sharing sort 0 cannot fight.
	Layer.INVALID_MOVE: {"color": Color(0.8, 0.82, 0.86, 0.75), "sort": 0, "kind": Kind.FILL,
		"grid": true},
	# THE SQUAD'S LINES (#1070), which replaced the orange SQUAD / SQUAD_RANGE fills -- see
	# SquadLines2D. The range's stroke LIES ON THE GROUND the way the enemy focus edge does, so it names
	# a lift_sort above every FILL; its sort is render priority only, and sits under the tethers because
	# a line in the air should read over one on the floor. Colours arrive per draw from SquadLines2D's
	# statics, so these entries are fallbacks; all four share the "squad" beam set, which is what makes
	# the range and the tethers read as one system.
	Layer.COHESION_EDGE: {"color": Color(1.0, 0.55, 0.12, 0.95), "sort": 12, "lift_sort": 6,
		"beam": "squad", "kind": Kind.LINE},
	# ...and the tethers, one layer per STATE because a layer is one material: the pluck is a uniform,
	# and only the strained tethers may shake. They hang at the body's middle and a ribbon writes no
	# depth, so the three share 14, the last free sort under ICONS. `cone_alpha` puts their arrowhead on
	# the SEE-THROUGH cone, so a tether colour's alpha fades the arrow with the shaft (dev, 2026-09-22);
	# the reach mark's stays solid, which was #1069's ruling for an intent.
	Layer.TETHERS: {"color": Color(1.0, 0.55, 0.12, 0.95), "sort": 14, "beam": "squad",
		"kind": Kind.LINE, "cone_alpha": true},
	Layer.TETHER_GHOST: {"color": Color(0.72, 0.42, 0.16, 0.5), "sort": 14, "beam": "squad",
		"kind": Kind.LINE, "cone_alpha": true},
	Layer.TETHER_STRAIN: {"color": Color(1.0, 0.18, 0.14, 0.95), "sort": 14, "beam": "squad",
		"kind": Kind.LINE, "cone_alpha": true},
	Layer.AIM: {"color": Color(1, 1, 0, 1), "sort": 4, "kind": Kind.FILL},
	Layer.TARGET_PICK: {"color": Color.WHITE, "sort": 5, "kind": Kind.SPRITE},
	Layer.PATH_ARROWS: {"color": Color.WHITE, "sort": 6, "kind": Kind.SPRITE},
	Layer.KNOCKBACK: {"color": Color.WHITE, "sort": 6, "kind": Kind.SPRITE},
	# The aim's sight line (#258) -- a laser polyline at the trajectory's own heights, not cell
	# markup. Colour arrives per set_line call (the 2D SightTrace2D verdict colours, copied by the
	# mirror -- parallel-stacks rule); the entry colour is only the fallback.
	Layer.SIGHT_TRACE: {"color": Color.WHITE, "sort": 7, "kind": Kind.LINE},
	# The ground form of the selection icons (#325 experiment): membership rings + the leader's
	# crown decal lying on the cell surface. Above terrain state, below the aim pulse, pick
	# markers and arrows (a ring must never eat an arrowhead) -- AIM/TARGET_PICK/arrows each
	# moved up one to open this slot. Colour stays WHITE: the tint is per-entry (the squad hue,
	# copied off the 2D sprite), which is also why this layer can never take a GameKnobs colour row.
	Layer.GROUND_ICONS: {"color": Color.WHITE, "sort": 3, "kind": Kind.SPRITE},
	# The armed-Guard ward mark (#414) gets its OWN layer purely so it stops Z-FIGHTING the squad
	# ring, which it shared a cell and a layer with. A layer IS a plane here -- _lift_of is
	# fill_lift + sort * lift_step -- so two markers on one layer are coplanar by construction and
	# no per-marker nudge can separate them without breaking that rule (#432's own lesson).
	#
	# Sort 8 rather than 4: it may not share a sort with any layer whose CELLS it can overlap, and a
	# warded unit's cell can carry an aim fill (4), a target-pick marker (5), an arrow (6) or a sight
	# trace (7). 8 is the first free slot above all of them. Consequence, deliberate: the ward mark
	# reads OVER ground markup, which is #346's rule -- the interaction is the thing you must not
	# miss, and ambient membership yielding to it is the trade. One integer if that reads wrong.
	Layer.GUARD_ICONS: {"color": Color.WHITE, "sort": 8, "kind": Kind.SPRITE},
	# The blocker->ward arrow (#450), and its own layer for the reason the shield above has one: a
	# layer is a plane, and this trail's two cells are exactly the cells the shield, an aim fill, a
	# target-pick mark, a path arrow or a sight trace can already be sitting on.
	#
	# ABOVE the shield rather than under it, which is a decision and not the leftover integer: the
	# 2D draws these into ArrowIconOverlay, a later sibling than IconOverlay at the same z_index, so
	# the arrowhead lands over the shield there whatever this number says -- and the two views must
	# agree. Reverse BOTH (swap with 8, give the 2D link RING_Z_INDEX) if the head crowds the shield.
	Layer.GUARD_LINK: {"color": Color.WHITE, "sort": 9, "kind": Kind.SPRITE},
	# The watched-footprint threat mark (#413), and it takes a layer of its OWN for the same reason
	# the ward mark did: a layer IS a plane, so a marker that can share a CELL with another marker
	# must not share its sort. A watched cell can carry an aim fill (4), a target-pick marker (5), an
	# arrow (6), a sight trace (7), a ward mark (8) and now the ward LINK (9) -- a warded pair
	# standing in a watched line is an ordinary board state, not a corner case -- so 10 is the first
	# sort free of all of them. #413 and #450 both landed on 9 on their own branches; this is the one
	# that moved, because the link's 9 encodes a stated relationship to the shield's 8 and this does
	# not care which side of the pair it sits on, only that it is not IN it.
	# Colour stays WHITE here: OverlayMirror copies the 2D sprite's own modulate, which is the
	# knob-tuned OverlayManager.WATCH_MARK_COLOR, so a second value here could only disagree with it.
	Layer.WATCH_ICONS: {"color": Color.WHITE, "sort": 10, "kind": Kind.SPRITE},
	# Sort 2, NOT above the arrows: the 2D is the authority and it puts terrain state at
	# TERRAIN_Z_INDEX (above the board, below unit sprites) with arrows above it. At 6 this
	# was the top of the table, so freeze icons drew over path arrows and planning ghosts.
	Layer.TERRAIN: {"color": Color.WHITE, "sort": 2, "kind": Kind.SPRITE},
	Layer.TERRAIN_PREVIEW: {"color": Color.WHITE, "sort": 2, "kind": Kind.SPRITE},
	# The ONE layer that hangs in the AIR rather than lying on the floor, so it sorts above
	# every floor layer. It sat at 0 while nothing could overlap it; #325 then put a ring
	# decal (3) directly under every crown, which drew straight over it. 15 is the top of
	# the lawful band -- a law pins every layer under EFFECT_RENDER_PRIORITY. A BILLBOARD
	# ignores _lift_of and rides billboard_lift, so this moves PRIORITY only, not geometry.
	Layer.ICONS: {"color": Color.WHITE, "sort": 15, "kind": Kind.BILLBOARD},
}

const FILL_TEXTURE_PATH := "res://Art/LookDev/cell_fill.png"
# Colocated with its only consumer rather than in a shaders folder the project does not have.
const SIGHT_BEAM_SHADER_PATH := "res://Classes/presentation/sight_beam.gdshader"
# ...and the SOLID cone's own (#1069). A second file rather than a flag on the one above, because
# what a volume must not have -- the rim falloff and `depth_draw_never` -- are a fragment constant
# and a render_mode, and render_mode is per shader file. See that file's header.
const REACH_CONE_SHADER_PATH := "res://Classes/presentation/reach_cone.gdshader"
# ...and its SEE-THROUGH twin (#1070 follow-up), for a layer whose spec carries `cone_alpha`: a third
# file for the same reason, since blending and back-face culling are render_mode too.
const REACH_CONE_ALPHA_SHADER_PATH := "res://Classes/presentation/reach_cone_alpha.gdshader"
# The fixed world direction the cone's facets are shaded against. NOT the camera and NOT a knob:
# the shade is baked into vertex colour when a mark is rebuilt (on a hover change), so a
# camera-relative bake is stale the instant the rig orbits, and a direction is three sliders nobody
# drags. Over the left shoulder and well above, which is where the diorama's own key light sits.
const CONE_LIGHT := Vector3(-0.45, 0.85, 0.35)
# The 2D art's metric: a 16px texture covers exactly one board cell.
const ART_PIXELS_PER_CELL := 16.0

# How much of a column the hover selector encloses (#427 slice 2 follow-up). An ENUM rather than a
# row count because the vocabulary is fixed and because a knob carrying `options` renders as a
# picker (DevWidgets.add_knob_row) -- LookKnobs' tonemap_mode is the same shape.
#
# LEVEL is one whole block, which is what the selector marked before slice 2 re-metricked a GridMap
# row to a HEIGHT UNIT. HALF is one unit, for reading a half-step apart from the level it sits in.
enum SelectorDepth { LEVEL, HALF }

# Eye-knobs (the tuning rule); read when markers build/place.
@export var bracket_arm := 0.22
@export var bracket_thickness := 0.04
@export var bracket_scale := 1.02
# NOT a plain field: the HOVER layer only repaints when the pointer CELL changes (battle3d's
# _update_pointer early-outs on an unchanged one), so turning this with the mouse still would move
# nothing until you nudged it -- a knob that appears to do nothing is the one failure that makes a
# knob worthless (#324's rule, where every flame value rebuilds what is already standing).
@export var selector_depth: SelectorDepth = SelectorDepth.LEVEL: set = _set_selector_depth
# The stack's ZERO, not its bottom: the lowest sort is negative, so the real floor is
# fill_lift + min_sort * lift_step and THAT is what must clear the tile's opaque top face.
# Raised twice as the negative stack moved down for #710: 0.02 -> 0.03 at slice 3 (the floor landed
# at exactly 0.0), 0.03 -> 0.04 at slice 4 (it landed at 0.002). The law demands a whole lift_step.
@export var fill_lift := 0.04          # quad height above the top face — the z-fight gap
@export var lift_step := 0.004         # per-sort spacing so stacked layers never coincide
@export var billboard_lift := 0.85     # icon height above the cell's top face
@export var billboard_pixel_size := 1.0 / 32.0
# What the hover bracket turns when the pointer is over something the 2D calls INVALID (#245).
# A knob because there is nothing to mirror here: 2D says "invalid" with a negative-icon TEXTURE,
# and a bracket has no texture to swap, so the colour is a fresh aesthetic call.
@export var invalid_bracket_color := Color(1.0, 0.3, 0.3, 0.9)

# The sight beam's shape (#506). Each one re-applies on write rather than being read at build time:
# a knob that only takes effect on the next rebuild is a slider the dev drags with nothing moving,
# and a standing trace does not rebuild until the pointer does. The pools may not exist yet when a
# setter runs (member initializers, and a LINE pool is built lazily by set_line), which is why
# _apply_beam_params tolerates an empty one instead of guarding at each call site.
#
# COLOUR is deliberately absent: it arrives per draw as the aim's verdict tint, copied from
# SightTrace2D so the flat view and the diorama cannot disagree about what "blocked" looks like.
# Brightness is here rather than folded into that colour -- see the shader's own note. WIDTH is the
# whole offset: the screen-pixel FLOOR that used to sit beside it is gone, and the shader says why.
#
# THE `: set = _name` SUFFIX IS REQUIRED, NOT A STYLE CHOICE, and tidying these three into inline
# `set(value):` blocks silently breaks the file. `KnobSource.DECLARATION_LINE` carries that suffix
# but has no clause for a block, so it matches an inline-block declaration anyway and eats the
# trailing colon with the value -- Save rewrites `x := 0.06:` to `x := 0.99` and leaves the block
# beneath it orphaned, i.e. a parse error in the script the whole 3D stack hangs off, written
# silently the first time the dev tunes a beam and presses Save. Measured, not reasoned.
@export var beam_width := 0.075: set = _set_beam_width              # world units; a cell is 1.0
@export var beam_softness := 1.1: set = _set_beam_softness         # edge falloff exponent
@export var beam_intensity := 3.9: set = _set_beam_intensity       # ALBEDO multiplier; >1.2 blooms
# The focus outline's own two (slice 4), same re-apply contract as the trio above. Thin and UNLIT
# by comparison, because this is board markup rather than a laser: at the bead's width and bloom a
# stroke around forty cells reads as a rope of light laid over the terrain.
@export var outline_width := 0.03: set = _set_outline_width
@export var outline_intensity := 1.0: set = _set_outline_intensity
# ...and the reach mark's own set (#1042, renamed with the channel at #1069), which is neither:
# wider than a stroke, dimmer than a laser, and the only beam in the game that MOVES.
@export var mark_width := 0.055: set = _set_mark_width
@export var mark_intensity := 2.4: set = _set_mark_intensity
# The BEAD -- one bright pulse running enemy -> victim, which is what says which end is which
# without the cone having to be read. Speed and length are in CELLS, so a mark of any length
# pulses at the same pace; `bead_gap` is how far apart two beads run, so a long mark can hold more
# than one. Zero length is no bead at all.
@export var bead_speed := 3.4: set = _set_bead_speed
@export var bead_length := 0.55: set = _set_bead_length
@export var bead_gap := 9.0: set = _set_bead_gap
# THE CONE'S OWN THREE (#1069), because a SOLID has a property a ribbon does not: which way its
# faces point. Everything else about the mark -- length, base width, colour, bow, inset -- is
# already tunable and unchanged; these are the values that had no home while the cone was a
# tapering ribbon whose rim faded to nothing.
#
# The glow is SPLIT from the shaft's rather than shared, and that is the one number #1069 did not
# carry over. `mark_intensity` is 2.4, which is right for a ribbon whose rim reaches zero alpha --
# most of its area is far dimmer than the multiplier says. A solid surface at 2.4 is 2.4 EVERYWHERE,
# past the diorama's glow_hdr_threshold of 1.2 across the whole face, so it blooms into a white blob
# and the shading below is invisible.
@export var cone_intensity := 1.0: set = _set_cone_intensity
# The FLOOR of the baked facet shading: 1.0 is flat and unreadable, 0.0 is hard black on a facet
# pointing away from the light. What sells a cone as a volume rather than a silhouette.
@export var cone_shading := 0.45: set = _set_cone_shading
# Radial segments round the cone. Low reads as a cut gem, high as smooth; the base cap uses the
# same count, so this is the whole shape's resolution.
@export var cone_facets := 12: set = _set_cone_facets
# The squad lines' own pair (#1070), shared by the range's stroke and the three tether layers so the
# two read as one system. Thin and near the bloom threshold, like the outline -- these are markup. The
# DASHES are not here: they are SquadLines2D statics, because the flat view draws them too.
@export var squad_line_width := 0.045: set = _set_squad_line_width
@export var squad_line_intensity := 1.2: set = _set_squad_line_intensity


func _set_squad_line_width(value: float) -> void:
	squad_line_width = value
	_apply_beam_params()


func _set_squad_line_intensity(value: float) -> void:
	squad_line_intensity = value
	_apply_beam_params()


func _set_mark_width(value: float) -> void:
	mark_width = value
	_apply_beam_params()


func _set_mark_intensity(value: float) -> void:
	mark_intensity = value
	_apply_beam_params()


func _set_bead_speed(value: float) -> void:
	bead_speed = value
	_apply_beam_params()


func _set_bead_length(value: float) -> void:
	bead_length = value
	_apply_beam_params()


func _set_bead_gap(value: float) -> void:
	bead_gap = value
	_apply_beam_params()


func _set_cone_intensity(value: float) -> void:
	cone_intensity = value
	_apply_beam_params()


func _set_cone_shading(value: float) -> void:
	cone_shading = value
	_rebuild_cones()


func _set_cone_facets(value: int) -> void:
	cone_facets = maxi(value, 3)
	_rebuild_cones()


func _set_beam_width(value: float) -> void:
	beam_width = value
	_apply_beam_params()


func _set_outline_width(value: float) -> void:
	outline_width = value
	_apply_beam_params()


func _set_outline_intensity(value: float) -> void:
	outline_intensity = value
	_apply_beam_params()


func _set_beam_softness(value: float) -> void:
	beam_softness = value
	_apply_beam_params()


func _set_beam_intensity(value: float) -> void:
	beam_intensity = value
	_apply_beam_params()

var fill_texture: Texture2D

# MoveGrid's art at the diorama's resolution (#1074), shared by every marker on a `"grid"` layer and
# replaced wholesale by restyle_grid. Lazy -- a board that never shows a move range pays nothing.
var _grid_texture: ImageTexture

var _beams_animating := true   # the last composed photosensitivity read; see poll_beam_motion

var _markers: Dictionary[Layer, Array] = {}       # layer -> node pool (all kinds)
var _cells: Dictionary[Layer, Array] = {}         # set_cells layers: the current cell list
var _marker_data: Dictionary[Layer, Array] = {}   # set_markers layers: the current entries
var _lines: Dictionary[Layer, Array] = {}   # LINE layers: the current segments (Array[PackedVector3Array])
# A LINE layer's SOLID cones (#1069): a second node beside the ribbon, because the cone is opaque
# geometry on a different shader and a material carries one shader. Kept out of the `_markers` pool
# so nothing that walks a pool -- visibility, colour, the beam sweep -- has to learn there are two
# kinds of node in it; `_cone_batches` is what a knob change re-emits from, the way `intent_shafts`
# is what a mark knob re-derives from one layer up.
var _cones: Dictionary[Layer, MeshInstance3D] = {}
var _cone_batches: Dictionary[Layer, Array] = {}
var _cone_colors: Dictionary[Layer, Color] = {}
var _layer_colors: Dictionary[Layer, Color] = {}  # runtime fill colors (set_layer_modulate)
var _bracket_mesh: ArrayMesh
var _quad_mesh: PlaneMesh
# The folded quads corner-cell markup lies on (#427 slice 4 follow-up), keyed by the cell's SHAPE --
# its corners relative to the low one -- so a whole board of corner cells costs at most twelve masks
# times two climbs. See _surface_mesh for why a transform cannot carry the fold.
var _bent_meshes: Dictionary[Vector4i, ArrayMesh] = {}


func _ready() -> void:
	if fill_texture == null:
		fill_texture = load(FILL_TEXTURE_PATH) as Texture2D


# What art a FILL layer draws with. The default is the wash every markup layer has always worn; a
# layer marked `"grid"` wears MoveGrid's generated lattice instead (#1069, re-cut by #1074), which is
# how MOVE draws as GRIDLINES without becoming a second render Kind -- every law this table already
# carries (the sort, the lift, the ramp tilt, the corner-cell fold, set_layer_modulate, the mirror's
# per-frame tint copy) goes on applying to it untouched, because it IS still a fill.
#
# The key is declared LAST on its LAYERS line, and that is not style: KnobSource's colour rewriter
# is a regex requiring `"color"` to be an entry's FIRST key, so a key ahead of it would make every
# colour save in the dev panel fail silently.
func _texture_for(spec: Dictionary) -> Texture2D:
	if spec.get("grid", false):
		return grid_texture()
	return fill_texture


func grid_texture() -> Texture2D:
	if _grid_texture == null:
		_grid_texture = ImageTexture.create_from_image(MoveGrid.image(MoveGrid.ART_TEXELS))
	return _grid_texture


# A turned MoveGrid knob (#1074): a fresh texture, handed to every standing grid marker, so the range
# already on the board changes this frame -- a knob that only took effect on the next hover would be
# a slider the dev drags with nothing moving.
#
# A NEW object rather than ImageTexture.update() on the old one, which would have spared the pool
# walk: the suite runs on the dummy renderer, where update() never reaches the pixels a read sees, so
# an in-place write is a wire no headless case can observe. Measured -- both cases that pin this went
# red against a correct update() and green against this.
func restyle_grid() -> void:
	if _grid_texture == null:
		return
	_grid_texture = ImageTexture.create_from_image(MoveGrid.image(MoveGrid.ART_TEXELS))
	for layer: Layer in LAYERS:
		if not LAYERS[layer].get("grid", false):
			continue
		for node: Node3D in _pool_for(layer):
			var material := (node as MeshInstance3D).material_override as StandardMaterial3D
			material.albedo_texture = _grid_texture


# Replaces the layer's cells wholesale (idempotent — calling twice with the same
# set changes nothing; extras from a previous, larger set are hidden, not leaked).
# FILL/BRACKET layers only — variant layers go through set_markers.
#
# `heights` is what lets a fill LIE ON a ramp rather than hang level through it (#281). Taken as a
# parameter rather than held, the way BoardMirror.sync takes it: null reads as flat, which is what
# the headless Play boards and the pooled-clear path both want.
func set_cells(layer: Layer, cells: Array[Vector3i], heights: BoardHeights = null) -> void:
	var spec: Dictionary = LAYERS[layer]
	if spec["kind"] != Kind.FILL and spec["kind"] != Kind.BRACKET:
		push_error("set_cells on a %s layer — use set_markers" % Kind.keys()[spec["kind"]])
		return
	_cells[layer] = cells.duplicate()
	var pool: Array = _pool_for(layer)
	while pool.size() < cells.size():
		pool.append(_make_marker(layer))
	for i in pool.size():
		var marker := pool[i] as Node3D
		if i < cells.size():
			marker.visible = true
			marker.transform = _marker_transform(spec, cells[i], heights)
			# A FILL rides the surface, so on a corner cell the fold is in its MESH rather than in
			# the transform above (#427 slice 4 follow-up). A BRACKET marks a VOLUME and keeps its
			# box. Assigned unconditionally because the pool is reused: a marker that was on a
			# corner and is now on flat ground has to be handed the flat quad back.
			if spec["kind"] == Kind.FILL:
				(marker as MeshInstance3D).mesh = _surface_mesh(_corners_under(cells[i], heights))
		else:
			marker.visible = false


# Replaces a variant layer wholesale: one entry per marker, {"pos": Vector3 (the
# cell's top-face anchor), "texture": Texture2D, "modulate": Color, "basis": Basis
# (optional — how the surface under it is tilted, identity on flat ground),
# "corners": Vector4i (optional — the SHAPE of the cell it lies on, so a corner
# cell's fold reaches the mesh; absent or ZERO means it lies on nothing, which is
# what an airborne marker wants)}. Same idempotent-pool contract as set_cells.
# SPRITE/BILLBOARD layers only.
func set_markers(layer: Layer, markers: Array[Dictionary]) -> void:
	var spec: Dictionary = LAYERS[layer]
	if spec["kind"] != Kind.SPRITE and spec["kind"] != Kind.BILLBOARD:
		push_error("set_markers on a %s layer — use set_cells" % Kind.keys()[spec["kind"]])
		return
	_marker_data[layer] = markers.duplicate()
	var pool: Array = _pool_for(layer)
	while pool.size() < markers.size():
		pool.append(_make_marker(layer))
	for i in pool.size():
		var node := pool[i] as Node3D
		if i < markers.size():
			node.visible = true
			_apply_marker(spec, node, markers[i])
		else:
			node.visible = false


# Runtime recolor of a FILL or BRACKET layer's pool (the heal-green reach, the aim pulse —
# colors the 2D layer modulates live; and the hover bracket's invalid red, #245). Skip-if-equal
# so a per-frame poll is free. Both kinds are a MeshInstance3D with a StandardMaterial3D
# override, which is why one loop serves them; SPRITE/BILLBOARD carry per-marker tints instead
# and would need their entry data rewritten, not their pool.
func set_layer_modulate(layer: Layer, color: Color) -> void:
	var spec: Dictionary = LAYERS[layer]
	if spec["kind"] != Kind.FILL and spec["kind"] != Kind.BRACKET:
		push_error("set_layer_modulate is for FILL and BRACKET layers")
		return
	if _layer_colors.get(layer, spec["color"]) == color:
		return
	_layer_colors[layer] = color
	for node: Node3D in _pool_for(layer):
		var material := (node as MeshInstance3D).material_override as StandardMaterial3D
		material.albedo_color = color


# Replaces a LINE layer's polyline wholesale -- one pooled MeshInstance3D whose ImmediateMesh is
# rebuilt per call (a hovered aim changes every mouse move; a ribbon rebuild of ~15 points is
# nothing). Points arrive in WORLD space at the trajectory's own heights; fewer than 2 hides it.
#
# The centreline is emitted TWICE per point (#506) -- same position, side flag 0 then 1 -- and
# sight_beam.gdshader pushes the pair apart to face the camera. So the mesh is a TRIANGLE_STRIP of
# 2N vertices, and what it stores is still just the centreline: `line_of` and every caller upstream
# are unchanged, which is what let the ribbon land without touching Reach or OverlayMirror.
func set_line(layer: Layer, points: PackedVector3Array, color: Color) -> void:
	var segments: Array[PackedVector3Array] = []
	if points.size() >= 2:
		segments.append(points)
	set_lines(layer, segments, color)


# The same layer carrying SEVERAL polylines (#710's threat lines): one pooled mesh, one surface
# per segment. Each segment is its own MARK, so nothing chains between them.
func set_lines(layer: Layer, segments: Array[PackedVector3Array], color: Color) -> void:
	var marks: Array[Array] = []
	for points in segments:
		marks.append([points])
	set_marks(layer, marks, color)


# A layer carrying several MARKS, each of which may be several strokes (#1059's intent: a bowed arc
# and the cone at its victim's end). One pooled mesh, one surface per stroke.
#
# DISTANCE CHAINS WITHIN A MARK AND RESTARTS BETWEEN THEM, which is the whole reason this exists
# rather than a longer `set_lines`: the bead is a window in world distance, so the cone has to
# continue the arc's measure or each stroke runs its own little pulse. Chained, the bead sweeps the
# arc and arrives through the cone.
#
# `widths` is shaped like `marks` -- a per-point scale for each stroke -- and empty means every
# stroke is drawn at the layer's own width, which is what `set_lines` and its three other layers want.
func set_marks(layer: Layer, marks: Array[Array], color: Color,
		widths: Array[Array] = [], cones: Array[Dictionary] = []) -> void:
	var spec: Dictionary = LAYERS[layer]
	if spec["kind"] != Kind.LINE:
		push_error("set_marks on a %s layer" % Kind.keys()[spec["kind"]])
		return
	var flat: Array[PackedVector3Array] = []
	for strokes in marks:
		for stroke: PackedVector3Array in strokes:
			flat.append(stroke)
	_lines[layer] = flat
	var pool: Array = _pool_for(layer)
	if pool.is_empty():
		pool.append(_make_marker(layer))
	var node := pool[0] as MeshInstance3D
	var mesh := node.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var drawn := false
	var batch: Array[Dictionary] = []
	for m in marks.size():
		var strokes: Array = marks[m]
		var scales: Array = widths[m] if m < widths.size() else []
		var cone: Dictionary = cones[m] if m < cones.size() else {}
		# A SOLID cone is not a ribbon, so its own stroke is dropped from the strip pass and the
		# shaft simply ENDS where the cone's base begins -- no overlap to z-fight and no tapering
		# ribbon left inside the volume. `_lines` still holds every stroke, because that store is
		# the geometry this layer represents rather than a list of what got rasterized how.
		var strip_count: int = strokes.size()
		if not cone.is_empty() and strip_count > 1:
			strip_count -= 1
		var travelled := 0.0
		for s in strip_count:
			var stroke: PackedVector3Array = strokes[s]
			var scale: PackedFloat32Array = PackedFloat32Array() if s >= scales.size() else scales[s]
			if add_beam_strip(mesh, stroke, Color.WHITE, travelled, scale):
				drawn = true
			travelled += _stroke_length(stroke)
		if not cone.is_empty():
			# The bead's measure CONTINUES across the join: the cone starts at the distance the
			# shaft ended at, which is the same chaining set_marks has always done between strokes.
			var entry := cone.duplicate()
			entry["dist"] = travelled
			batch.append(entry)
	node.visible = drawn
	(node.material_override as ShaderMaterial).set_shader_parameter("beam_color", color)
	_cone_batches[layer] = batch
	_cone_colors[layer] = color
	_emit_cones(layer)


# Re-emit every layer's cones from the stored batch. The `restyle` shape one level down: a facet
# count or a shading floor is baked into the MESH, so turning either has to rebuild it -- where
# cone_intensity is a material uniform and rides _apply_beam_params like every other beam number.
# Without this those two would be #264's born-dead sliders.
func _rebuild_cones() -> void:
	for layer: Layer in _cone_batches:
		_emit_cones(layer)


func _emit_cones(layer: Layer) -> void:
	var batch: Array = _cone_batches.get(layer, [])
	var node := _cone_for(layer)
	var mesh := node.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var drawn := false
	for entry: Dictionary in batch:
		if add_beam_cone(mesh, entry["base"], entry["tip"], float(entry["radius"]),
				float(entry.get("dist", 0.0)), cone_shading, cone_facets):
			drawn = true
	node.visible = drawn
	(node.material_override as ShaderMaterial).set_shader_parameter("beam_color",
			_cone_colors.get(layer, Color.WHITE))


# One SOLID cone: a radial fan from `base` to `tip` plus the base cap, emitted as triangles onto a
# shared ImmediateMesh. Static and pure so a case can state a base, a tip and a radius and read the
# vertices back, rather than photographing a viewport.
#
# The FACET SHADE is baked per triangle into the vertex colour, which is the only channel that can
# vary inside one unshaded draw -- UnitHealthBar._build_cube_mesh's trick, and the reason this is
# not a lit StandardMaterial3D (the dev's unshaded ruling for board markup, which
# test_board_overlays enforces over every material under this node).
#
# UV2.x carries the vertex's own distance ALONG THE AXIS from `dist_start`, so the shaft's bead runs
# into the cone and up to the tip as one continuous sweep instead of restarting at the base.
static func add_beam_cone(mesh: ImmediateMesh, base: Vector3, tip: Vector3, radius: float,
		dist_start := 0.0, shading := 0.45, facets := 12) -> bool:
	var axis := tip - base
	var length := axis.length()
	if length <= 0.0 or radius <= 0.0 or facets < 3:
		return false
	axis /= length
	# Any perpendicular will do -- the cone is radially symmetric, so the ring's starting angle is
	# arbitrary. UP unless the axis is nearly vertical, which a steeply bowed mark's tail can be.
	var seed := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var u := axis.cross(seed).normalized()
	var v := axis.cross(u)
	var light := CONE_LIGHT.normalized()
	var ring := PackedVector3Array()
	for i in facets:
		var a := TAU * float(i) / float(facets)
		ring.append(base + (u * cos(a) + v * sin(a)) * radius)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in facets:
		var j := (i + 1) % facets
		_cone_face(mesh, tip, ring[i], ring[j], base, axis, light, dist_start, shading)
		# The cap, wound the other way so its own face normal points back down the axis and it
		# shades as the underside rather than as a copy of the side above it.
		_cone_face(mesh, base, ring[j], ring[i], base, axis, light, dist_start, shading)
	mesh.surface_end()
	return true


static func _cone_face(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, base: Vector3,
		axis: Vector3, light: Vector3, dist_start: float, shading: float) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() > 0.0:
		normal = normal.normalized()
	var lit: float = shading + (1.0 - shading) * maxf(normal.dot(light), 0.0)
	var tint := Color(lit, lit, lit, 1.0)
	# EMITTED a, c, b: `normal` above is the OUTWARD one, and Godot's front face is (v0-v2)x(v0-v1),
	# the opposite turn (measured, #876) -- so emitting a, b, c made the outside a BACK face. Harmless
	# on the opaque cone, which culls nothing; the see-through one culls back faces and would have
	# drawn the cone's inside.
	for p: Vector3 in [a, c, b]:
		mesh.surface_set_color(tint)
		mesh.surface_set_normal(normal)
		mesh.surface_set_uv(Vector2(0.0, 0.5))
		mesh.surface_set_uv2(Vector2(dist_start + (p - base).dot(axis), 0.0))
		mesh.surface_add_vertex(p)


static func _stroke_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	return total


# ONE RIBBON, APPENDED to a mesh as its own surface -- the recipe sight_beam.gdshader is fed, and
# since #887 the one spelling of it. Returns whether anything was built; fewer than two points is
# nothing to draw rather than an error, which is what a blocked-at-source trace produces.
#
# STATIC AND APPENDING, both for the second caller: ArcLightning holds a whole storm of these on ONE
# mesh (a surface per bolt) and rebuilds it every frame, so it owns the clear and cannot be handed a
# node. `tint` rides in the VERTEX COLOUR rather than the material, which is precisely what lets one
# material draw twenty bolts at twenty different ages -- see the shader's own note. The overlay
# layer passes white and is unchanged by it.
# `dist_start` is how far along its MARK this stroke begins, in world units, and it rides UV2.x as
# a running WORLD distance beside UV.x's normalized one. It is a second measure rather than a
# rescaling of the first because they answer different questions: UV.x is "how far through this
# ribbon" (the falloff's and a future wipe's), UV2.x is "how far from the enemy" -- the only one a
# bead can travel at a constant pace whatever the mark's length. Left at its default it is simply
# the stroke's own length, which is what every pre-#1042 caller wants.
#
# `widths` is a per-point WIDTH SCALE (#1059's cone, which tapers to nothing at the victim). A
# ribbon's width is a material uniform, so a shaft and a cone on one layer cannot differ by one --
# and UV2.y is the only free per-vertex channel. It carries `scale - 1.0` rather than `scale`, so
# ZERO MEANS UNCHANGED and the sight beam and ArcLightning's bolts are untouched by construction
# rather than by care; an empty array is the same thing said at the call site.
static func add_beam_strip(mesh: ImmediateMesh, points: PackedVector3Array,
		tint := Color.WHITE, dist_start := 0.0,
		widths := PackedFloat32Array()) -> bool:
	if points.size() < 2:
		return false
	var tangents := beam_tangents(points)
	var last := float(points.size() - 1)
	var travelled := dist_start
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in points.size():
		# UV.x is the position along the beam, UV.y the side flag the shader remaps to -1/+1.
		var along := float(i) / last
		if i > 0:
			travelled += points[i].distance_to(points[i - 1])
		var scale: float = 1.0 if i >= widths.size() else widths[i]
		var measure := Vector2(travelled, scale - 1.0)
		mesh.surface_set_color(tint)
		mesh.surface_set_normal(tangents[i])
		mesh.surface_set_uv(Vector2(along, 0.0))
		mesh.surface_set_uv2(measure)
		mesh.surface_add_vertex(points[i])
		mesh.surface_set_color(tint)
		mesh.surface_set_normal(tangents[i])
		mesh.surface_set_uv(Vector2(along, 1.0))
		mesh.surface_set_uv2(measure)
		mesh.surface_add_vertex(points[i])
	mesh.surface_end()
	return true


# The direction the ribbon is "along" at each point. Interior points AVERAGE their two segments
# rather than taking one: a lob's arc bends at every sample, and a tangent that jumps between
# segments splits the strip open at each joint. Endpoints have one segment and use it. A
# zero-length segment (coincident samples, which a shot blocked at t=0 can produce) contributes
# nothing instead of poisoning the average with a NaN.
#
# Static since #887 -- it reads no instance state and never did, and the arc builds its bolts
# outside this node entirely.
static func beam_tangents(points: PackedVector3Array) -> PackedVector3Array:
	var tangents := PackedVector3Array()
	var count := points.size()
	for i in count:
		var back := Vector3.ZERO
		var ahead := Vector3.ZERO
		if i > 0:
			back = points[i] - points[i - 1]
			if back.length_squared() > 0.0:
				back = back.normalized()
			else:
				back = Vector3.ZERO
		if i < count - 1:
			ahead = points[i + 1] - points[i]
			if ahead.length_squared() > 0.0:
				ahead = ahead.normalized()
			else:
				ahead = Vector3.ZERO
		var joint := back + ahead
		if joint.length_squared() > 0.0:
			tangents.append(joint.normalized())
		else:
			tangents.append(Vector3.FORWARD)
	return tangents


# Pushes the four shape knobs at every built beam. Called by each setter AND by _make_line, which
# is the half that is easy to miss: the LINE pool is built lazily on the first set_line, so a knob
# written before any aim was hovered would otherwise be dropped and the beam would come up with the
# shader's own defaults instead of the authored ones.
func _apply_beam_params() -> void:
	for layer: Layer in _markers:
		if LAYERS[layer]["kind"] != Kind.LINE:
			continue
		for node: Node3D in _markers[layer]:
			_style_beam((node as MeshInstance3D).material_override as ShaderMaterial, LAYERS[layer])
	# ...and the cones beside them, which carry the bead's own three so the pulse stays one sweep.
	for layer: Layer in _cones:
		_style_cone((_cones[layer] as MeshInstance3D).material_override as ShaderMaterial, LAYERS[layer])


# A squad-line knob moved (#1070) -- the dashes live on SquadLines2D, so nothing here would otherwise
# notice. Re-pushes every beam, which is what every setter above does for its own.
func restyle_squad_lines() -> void:
	_apply_beam_params()


# The pluck (#1070): how far the middle of every STRAINED tether is displaced right now, in world
# units. Pushed each frame by OverlayMirror while a shake rings; zero stills it. Only this layer's
# material reads it, which is the whole reason the strained tethers are a layer of their own.
func set_tether_shake(amount: float) -> void:
	for node: Node3D in _markers.get(Layer.TETHER_STRAIN, []):
		((node as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("shake", amount)


# A LINE layer may name its own set (slice 4). The shared trio is tuned for a LASER -- the sight
# bead's width and an intensity whose own comment reads ">1.2 blooms" -- and the focus outline is
# markup, so inheriting them made it a glowing rope around forty cells. Softness stays shared: the
# falloff SHAPE is not a thing the three want to differ about.
#
# Three tenants since #1042, so the binary fork became a named lookup rather than a second ternary
# per parameter -- a fourth adds a row here and nothing else.
func _style_beam(material: ShaderMaterial, spec: Dictionary = {}) -> void:
	if material == null:
		return
	var width := beam_width
	var intensity := beam_intensity
	match spec.get("beam", "") as String:
		"outline":
			width = outline_width
			intensity = outline_intensity
		"mark":
			width = mark_width
			intensity = mark_intensity
		"squad":
			width = squad_line_width
			intensity = squad_line_intensity
	material.set_shader_parameter("beam_width", width)
	material.set_shader_parameter("beam_softness", beam_softness)
	material.set_shader_parameter("beam_intensity", intensity)
	# The bead rides ONLY the layers that ask for it; everything else reads a zero length and the
	# shader's whole motion branch drops out. `motion` is the composed photosensitivity read.
	var carries_bead: bool = spec.get("beam", "") == "mark"
	material.set_shader_parameter("bead_length", bead_length if carries_bead else 0.0)
	material.set_shader_parameter("bead_speed", bead_speed)
	material.set_shader_parameter("bead_gap", maxf(bead_gap, 0.001))
	# ...and the marching DASHES ride only the squad's lines (#1070), off the same statics the flat
	# view cuts its dashes from. A zero period is a solid stroke, which is every other layer.
	var dashed: bool = spec.get("beam", "") == "squad"
	material.set_shader_parameter("dash_period",
			SquadLines2D.dash_period() * BoardSpace.CELL_SIZE if dashed else 0.0)
	material.set_shader_parameter("dash_fill", clampf(SquadLines2D.DASH_FILL, 0.0, 1.0))
	material.set_shader_parameter("dash_speed", SquadLines2D.DASH_SPEED * BoardSpace.CELL_SIZE)
	material.set_shader_parameter("motion", 1.0 if beams_animating() else 0.0)


# The CONE's material (#1069), which is a different shader from the shaft's and therefore a
# different push. It shares the bead's three numbers so the pulse runs off the shaft and into the
# cone as one sweep, and takes its own intensity -- see cone_intensity's own note for why that one
# may not be inherited.
#
# The bead reaches a cone ONLY on a layer whose shaft carries one (#1070): a squad tether ends in the
# same solid cone, and handing it the reach mark's pulse would light an arrowhead whose shaft is dark.
func _style_cone(material: ShaderMaterial, spec: Dictionary = {}) -> void:
	if material == null:
		return
	material.set_shader_parameter("cone_intensity", cone_intensity)
	# The see-through cone declares no bead at all, so it is handed none rather than a zero.
	if spec.get("beam", "") != "mark":
		return
	material.set_shader_parameter("bead_length", bead_length)
	material.set_shader_parameter("bead_speed", bead_speed)
	material.set_shader_parameter("bead_gap", maxf(bead_gap, 0.001))
	material.set_shader_parameter("motion", 1.0 if beams_animating() else 0.0)


# The one composed read of "may board markup MOVE", #217's standing rule in BoardMirror's
# `_flame_animating` shape: the authored rate ANDed with the player's own choice. A frozen mark is
# not a mark with a cue missing -- the cone still says which way it runs, and the flash holds
# at its ALPHA peak (see the shader), so a felling mark stays the louder of the two.
# Static since #1070, whose flat-view squad lines are the first 2D markup that moves: they read this
# rather than asking PlayerSettings themselves, so the two views cannot disagree about whether a dash
# may crawl.
static func beams_animating() -> bool:
	return not PlayerSettings.is_on(PlayerSettings.Setting.PHOTOSENSITIVITY)


# PlayerSettings has no changed signal by design (callers poll it), so the mirror polls this once a
# frame and it re-pushes only on a real flip.
func poll_beam_motion() -> void:
	var animating := beams_animating()
	if animating == _beams_animating:
		return
	_beams_animating = animating
	_apply_beam_params()


func line_of(layer: Layer) -> PackedVector3Array:
	var segments: Array = _lines.get(layer, [])
	if segments.is_empty():
		return PackedVector3Array()
	return (segments[0] as PackedVector3Array).duplicate()


func lines_of(layer: Layer) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	out.assign(_lines.get(layer, []))
	return out


func clear(layer: Layer) -> void:
	var spec: Dictionary = LAYERS[layer]
	if spec["kind"] == Kind.SPRITE or spec["kind"] == Kind.BILLBOARD:
		set_markers(layer, [])
	elif spec["kind"] == Kind.LINE:
		set_line(layer, PackedVector3Array(), LAYERS[layer]["color"])
	else:
		set_cells(layer, [])


func cells_of(layer: Layer) -> Array[Vector3i]:
	var current: Array[Vector3i] = []
	current.assign(_cells.get(layer, []))
	return current


func markers_of(layer: Layer) -> Array[Dictionary]:
	var current: Array[Dictionary] = []
	current.assign(_marker_data.get(layer, []))
	return current


func layer_modulate(layer: Layer) -> Color:
	return _layer_colors.get(layer, LAYERS[layer]["color"])


# What a LINE layer's beam is actually carrying right now -- `layer_modulate`'s twin for the
# parameters a shader holds rather than a modulate. It exists because the beam's motion is composed
# from two places (the authored rate and the player's photosensitivity choice) and the only honest
# question about that wire is what reached the MATERIAL, not what the composer answered.
func beam_parameter(layer: Layer, name: StringName) -> Variant:
	var pool: Array = _markers.get(layer, [])
	if pool.is_empty():
		return null
	var material := (pool[0] as MeshInstance3D).material_override as ShaderMaterial
	return null if material == null else material.get_shader_parameter(name)


# The same question of a layer's SOLID cone (#1069), which is a second node on a second shader and
# so answers about different uniforms -- `cone_intensity` where the ribbon has `beam_intensity`.
func cone_parameter(layer: Layer, name: StringName) -> Variant:
	if not _cones.has(layer) or not is_instance_valid(_cones[layer]):
		return null
	var material := (_cones[layer] as MeshInstance3D).material_override as ShaderMaterial
	return null if material == null else material.get_shader_parameter(name)


# ...and the material itself, for the question a parameter cannot answer: WHICH cone a layer draws,
# the solid or the see-through one, and at what render priority.
func cone_material_of(layer: Layer) -> ShaderMaterial:
	if not _cones.has(layer) or not is_instance_valid(_cones[layer]):
		return null
	return (_cones[layer] as MeshInstance3D).material_override as ShaderMaterial


# A layer's cone geometry as it was actually emitted: one entry per triangle VERTEX, each
# {"point", "shade", "dist"}. Flat rather than grouped, because what a case asks of it is a
# property of the whole surface (every vertex carries a baked shade; the tip continues the shaft's
# measure), and grouping would invite a case to reach for "the third triangle", which is an
# ordering nothing promises.
func cone_vertices_of(layer: Layer) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _cones.has(layer) or not is_instance_valid(_cones[layer]):
		return out
	var mesh := (_cones[layer] as MeshInstance3D).mesh as ImmediateMesh
	if mesh == null:
		return out
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		for i in points.size():
			out.append({
				"point": points[i],
				"shade": 1.0 if i >= colors.size() else colors[i].r,
				"dist": 0.0 if i >= uv2.size() else uv2[i].x,
			})
	return out


# The AUTHORED colour, ignoring any runtime override — what a layer goes back TO. Distinct from
# layer_modulate() above, which answers what it is right NOW; a caller restoring a tint needs this
# one, or it would "restore" to whatever it last set.
func authored_color(layer: Layer) -> Color:
	var color: Color = LAYERS[layer]["color"]
	return color


func marker_count(layer: Layer) -> int:
	var pool: Array = _markers.get(layer, [])
	var visible_count := 0
	for marker: Node3D in pool:
		if marker.visible:
			visible_count += 1
	return visible_count


# --- Marker construction -----------------------------------------------------------

func _pool_for(layer: Layer) -> Array:
	if not _markers.has(layer):
		_markers[layer] = []
	return _markers[layer]


# A BRACKET marks a cell VOLUME and stays axis-aligned; a FILL is ground markup and rides the
# surface, tilt included (#281). The clearance itself is VERTICAL and not along the surface's own
# normal (#432) -- see _lift_of, where the direction turns out to be the whole question on a slope.
#
# The bracket's TOP FACE sits on the cell's surface and its depth reaches DOWN from there (#427
# slice 2 follow-up). It used to be cell_center, which was the same statement while a mirror cell
# was a CUBE -- slice 2 made a row half a level, left the bracket a level tall, and so hung it a
# QUARTER of a level high at both ends: proud of the block on top, short of the floor underneath.
# Dev, with screenshots: "it hovers a half height too high ... hovering above a block, and not going
# to the floor." The same law the brush ghost states, deliberately worded the same way, because the
# two are the only things in the stack that draw a volume rather than lie on one.
#
# No `heights` needed: cell.y is already the picked column's TOP row (battle3d's _tops), so the
# surface is right there.
func _marker_transform(spec: Dictionary, cell: Vector3i, heights: BoardHeights) -> Transform3D:
	if spec["kind"] == Kind.BRACKET:
		var centre := BoardSpace.cell_center(cell)
		centre.y = BoardSpace.surface_y(cell.y) - selector_half_height()
		return Transform3D(Basis.IDENTITY, centre)
	var surface := BoardSpace.lie_on(cell, _corners_under(cell, heights))
	return Transform3D(surface.basis, surface.origin + Vector3.UP * _lift_of(spec))


# The CORNERS a cell's markup lies on, since #427 slice 3 -- not a rise and a climb, because markup
# on a corner form has to follow a DIAGONAL downhill, which the cardinal pair could not describe.
func _corners_under(cell: Vector3i, heights: BoardHeights) -> Vector4i:
	return Vector4i.ZERO if heights == null else heights.corners_at(BoardSpace.flat(cell))


# Which mesh lies on these corners (#427 slice 4 follow-up). The shared flat quad for a PLANAR form,
# which is flat ground and every cardinal ramp -- so nearly every cell on nearly every board is
# untouched and pays one predicate.
#
# A corner form is not planar, and lie_on says so by handing back an identity basis: an affine
# transform maps a plane to a plane, so the fold cannot live in the transform and lives HERE, in four
# vertices at their true heights. That is the whole fix -- a tilted flat quad crossed the ground by a
# quarter of the climb at every corner, which is what the z-fighting on a corner tile's flat half was.
#
# THE MESH CALLS THE QUERY: vertex heights and the diagonal both come from Terrain.height_at_uv, the
# same function the cap meshes are cut by (slice 3's law). Two triangulations of one quad meet at all
# four corners and differ only INSIDE, so a markup quad that split the other way would sit up to a
# quarter of the climb off the ground it is drawn on -- and PlaneMesh's own split is fixed SW--NE,
# which is the wrong one whenever NE and SW differ.
func _surface_mesh(corners: Vector4i) -> Mesh:
	if _quad_mesh == null:
		_quad_mesh = PlaneMesh.new()
		_quad_mesh.size = Vector2.ONE * BoardSpace.CELL_SIZE
	if Terrain.is_planar_form(corners):
		return _quad_mesh
	# Keyed by the SHAPE, not the cell: a form is a mask plus a climb, so twelve non-cardinal masks
	# times two climbs is the whole cache, however big the board.
	var low := Terrain.low_of_corners(corners)
	var shape := corners - Vector4i(low, low, low, low)
	if _bent_meshes.has(shape):
		return _bent_meshes[shape]
	var mesh := _build_bent_mesh(shape)
	_bent_meshes[shape] = mesh
	return mesh


# The four corners in PlaneMesh's own frame: u east across the cell, v south down it, which is the
# frame Terrain.height_at_uv answers in. Measured off PlaneMesh rather than assumed, so a bent quad
# and a flat one carry the same art the same way up.
const _QUAD_UVS: Array[Vector2] = [
	Vector2(0.0, 0.0),   # NW
	Vector2(1.0, 0.0),   # NE
	Vector2(1.0, 1.0),   # SE
	Vector2(0.0, 1.0)    # SW
]


func _build_bent_mesh(shape: Vector4i) -> ArrayMesh:
	var centre := Terrain.height_at_uv(shape, 0.5, 0.5)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	for uv in _QUAD_UVS:
		verts.append(Vector3(
			(uv.x - 0.5) * BoardSpace.CELL_SIZE,
			(Terrain.height_at_uv(shape, uv.x, uv.y) - centre) * BoardSpace.ROW_HEIGHT,
			(uv.y - 0.5) * BoardSpace.CELL_SIZE))
		uvs.append(uv)
		normals.append(Vector3.UP)   # unshaded markup: declared to match PlaneMesh, never lit
	# The diagonal joins the two EQUAL corners, exactly as height_at_uv splits -- so the drawn quad
	# and the queried surface cannot disagree. Winding replicates PlaneMesh's for each case, which is
	# what keeps the face pointing up; the vertex ORDER is the whole of it, since a bent quad is two
	# triangles and the wrong pair would tent the wrong way.
	var index := PackedInt32Array([0, 1, 2, 0, 2, 3])   # NW-SE split: (NW,NE,SE) + (NW,SE,SW)
	if shape.y == shape.w:
		index = PackedInt32Array([2, 3, 1, 3, 0, 1])    # NE-SW split: (SE,SW,NE) + (SW,NW,NE)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Per-sort spacing keeps coplanar stacked fills apart; render_priority (set at
# construction) keeps the alpha blend order stable regardless.
#
# Applied STRAIGHT UP, never along the surface's normal (#432). What the lift buys is a shared
# PLANE -- every marker on a layer the same distance off the ground, which is what lets one
# ribbon run through several of them -- and BoardSpace.surface_height_at already meets exactly at
# shared edges, so a CONSTANT vertical offset stays continuous wherever the ground is. A normal
# lift does not: a ramp's leans, so it decomposed into half up and half DOWNHILL, sliding every
# marker out of its own cell by lift*sin(slope) and stepping the plane at every flat-to-ramp edge.
# The price is that a 45-degree slope's PERPENDICULAR clearance is cos(45) of the flat ground's
# -- fill_lift is the knob if a ramp ever speckles.
# A layer may name the sort its GEOMETRY hangs at separately from the one its material sorts by
# (slice 4). For a FILL the two are the same thing and always will be. For a LINE they never were:
# set_lines applies no lift at all and `sort` has only ever meant render priority there, so the
# focus outline -- which lies ON the ground rather than hanging at EYE_HEIGHT like an intent beam --
# would take its height from a priority chosen to clear the beams, a tenth of a cell off the terrain
# it outlines. Relational either way: it moves with fill_lift instead of becoming a second number.
func _lift_of(spec: Dictionary) -> float:
	return fill_lift + spec.get("lift_sort", spec["sort"]) * lift_step


# How far off its surface this layer's markup sits. Public because a marker that has to MEET other
# markers rather than lie beside them -- the knockback drop pointer, which joins the flat arrows at
# a right angle -- has to land in the plane they were lifted INTO, not on the raw surface (#431).
# Since #432 that plane is the surface plus this, straight up, on a slope as much as on the flat.
func marker_lift(layer: Layer) -> float:
	return _lift_of(LAYERS[layer])


func _apply_marker(spec: Dictionary, node: Node3D, marker: Dictionary) -> void:
	var pos: Vector3 = marker["pos"]
	var texture: Texture2D = marker["texture"]
	var tint: Color = marker.get("modulate", Color.WHITE)
	if spec["kind"] == Kind.BILLBOARD:
		var sprite := node as Sprite3D
		sprite.position = pos + Vector3(0.0, billboard_lift, 0.0)
		sprite.texture = texture
		sprite.modulate = tint
		return
	# Orientation and art scale are ONE write: a basis carries scale, so assigning them separately
	# would have whichever came second wipe the other. Both are set unconditionally because the
	# marker nodes are POOLED — a quad that was on a ramp and is now on flat ground, or that had art
	# and now has none, would otherwise keep the tilt and the size of whatever it drew last.
	var quad := node as MeshInstance3D
	# Which surface this marker LIES on, if it lies on one at all (#427 slice 4 follow-up). Carried
	# ALONGSIDE the basis rather than instead of it: the knockback drop pointer supplies an
	# orientation of its own and STANDS in the world, so `basis` stays "how this is oriented" and
	# `corners` is "the ground it lies flat against" -- absent when there is none, which is flat.
	quad.mesh = _surface_mesh(marker.get("corners", Vector4i.ZERO))
	var tilt: Basis = marker.get("basis", Basis.IDENTITY)
	var art := Vector3.ONE
	if texture != null:
		var size: Vector2 = texture.get_size() / ART_PIXELS_PER_CELL
		art = Vector3(size.x, 1.0, size.y)
	# The layer lift goes straight UP whatever the marker lies on (#432; _lift_of holds the why).
	# Riding the marker's own basis.y instead leaned a ramp's markers downhill out of their cells.
	# A marker that already carries its lift says so with a ZERO lift_dir -- and those two are the
	# only values the key has, now that the direction is no longer a free choice: the knockback drop
	# pointer's ends are the neighbouring arrows' own DRAWN points, so lifting it again would double
	# the clearance and float it off the join it exists to make (#431).
	var lift_dir: Vector3 = marker.get("lift_dir", Vector3.UP)
	quad.transform = Transform3D(tilt * Basis.from_scale(art), pos + lift_dir * _lift_of(spec))
	var material := quad.material_override as StandardMaterial3D
	material.albedo_texture = texture
	material.albedo_color = tint
	# The drop pointer's one render exception, off by default so every flat marker is unchanged:
	# it is double-sided, because it stands in the world rather than lying on a face and free
	# orbit reaches both of its sides (and its consistent band makes the basis left-handed on one
	# travel sign). Reset each time because the markers are pooled. It does NOT skip the depth
	# test: a marker that wins against every surface is an x-ray, visible through the platform
	# the camera panned behind (#431) -- what the pointer needed was to stop being coplanar with
	# a wall, which it now is by position rather than by opting out of depth.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if marker.get("double_sided", false) \
			else BaseMaterial3D.CULL_BACK
	_apply_atlas_uv(material, texture)


# A 3D material samples the WHOLE image behind an AtlasTexture -- a region is a 2D-only notion --
# so a cut from a multi-tile sheet arrives as the entire sheet squeezed into one cell (#316). The
# region is re-expressed as UVs here. The RESET on the plain-texture path is the load-bearing
# half: the marker nodes are pooled, so a quad that drew a cut would keep those UVs over its next
# art. Sprite3D is not affected -- it reads the region itself -- so BILLBOARD needs none of this.
func _apply_atlas_uv(material: StandardMaterial3D, texture: Texture2D) -> void:
	var cut := texture as AtlasTexture
	var sheet := Vector2.ZERO
	if cut != null and cut.atlas != null:
		sheet = cut.atlas.get_size()
	if sheet.x <= 0.0 or sheet.y <= 0.0:
		material.uv1_scale = Vector3.ONE
		material.uv1_offset = Vector3.ZERO
		return
	var region: Rect2 = cut.region
	material.uv1_scale = Vector3(region.size.x / sheet.x, region.size.y / sheet.y, 1.0)
	material.uv1_offset = Vector3(region.position.x / sheet.x, region.position.y / sheet.y, 0.0)


func _make_marker(layer: Layer) -> Node3D:
	var spec: Dictionary = LAYERS[layer]
	match spec["kind"] as Kind:
		Kind.BRACKET:
			# The runtime colour, not the authored one: a bracket built AFTER a set_layer_modulate
			# (the pool grows on demand) would otherwise come back gold on a red layer.
			return _make_bracket(_layer_colors.get(layer, spec["color"]))
		Kind.BILLBOARD:
			return _make_billboard(spec)
		Kind.LINE:
			return _make_line(spec)
		Kind.SPRITE:
			return _make_quad(spec, null, Color.WHITE)
		_:
			return _make_quad(spec, _texture_for(spec), _layer_colors.get(layer, spec["color"]))


# The one fill/sprite recipe: an unshaded alpha quad lying on the cell's top face —
# markup, never terrain (the dev's unshaded ruling; a Decal's albedo modulates the
# lit surface, which is why 4c retired decals).
func _make_quad(spec: Dictionary, texture: Texture2D, color: Color) -> MeshInstance3D:
	if _quad_mesh == null:
		_quad_mesh = PlaneMesh.new()
		_quad_mesh.size = Vector2.ONE * BoardSpace.CELL_SIZE
	var instance := MeshInstance3D.new()
	instance.mesh = _quad_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = texture
	material.albedo_color = color
	material.render_priority = spec["sort"]
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.layers = WORLD_RENDER_LAYER
	add_child(instance)
	return instance


# The sight beam: an ImmediateMesh ribbon, rebuilt by set_line and widened toward the camera by
# sight_beam.gdshader. This WAS a 1-px engine line strip, and the note here said the upgrade would
# be "a camera-facing ribbon built here, with nothing upstream changing" -- #506 is that upgrade,
# and the prediction held: only this function and set_line changed.
#
# extra_cull_margin exists because the mesh's AABB is computed from the CENTRELINE while the shader
# draws outside it. Without the margin a beam whose centreline leaves the frustum pops out while
# its visible width is still on screen. The value is generous next to any sane beam width -- this
# is one small mesh, so there is nothing to save by trimming it.
func _make_line(spec: Dictionary) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = ImmediateMesh.new()
	var material := ShaderMaterial.new()
	material.shader = load(SIGHT_BEAM_SHADER_PATH) as Shader
	material.render_priority = spec["sort"]
	instance.material_override = material
	instance.extra_cull_margin = 1.0
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.layers = WORLD_RENDER_LAYER
	add_child(instance)
	_style_beam(material, spec)
	return instance


# The SOLID cone's node (#1069), built lazily beside the ribbon's on the first mark that carries
# one. Deliberately NOT in the layer's `_markers` pool: everything that walks a pool -- set_cells,
# set_markers, the visibility sweep, _apply_beam_params -- would have to learn that one entry is a
# different shader with different uniforms, and a pool with two kinds of node in it is exactly the
# sort of thing the next reader gets wrong.
#
# No render_priority on the SOLID cone: its shader writes no ALPHA, so it is opaque geometry that
# depth-tests against the world like any object, which is the whole point of the second shader. The
# SEE-THROUGH one blends, so it takes its layer's sort exactly as the layer's ribbons do.
func _cone_for(layer: Layer) -> MeshInstance3D:
	if _cones.has(layer) and is_instance_valid(_cones[layer]):
		return _cones[layer]
	var instance := MeshInstance3D.new()
	instance.mesh = ImmediateMesh.new()
	var material := ShaderMaterial.new()
	if LAYERS[layer].get("cone_alpha", false):
		material.shader = load(REACH_CONE_ALPHA_SHADER_PATH) as Shader
		material.render_priority = LAYERS[layer]["sort"]
	else:
		material.shader = load(REACH_CONE_SHADER_PATH) as Shader
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.layers = WORLD_RENDER_LAYER
	add_child(instance)
	_style_cone(material, LAYERS[layer])
	_cones[layer] = instance
	return instance



func _make_billboard(spec: Dictionary) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.pixel_size = billboard_pixel_size
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.render_priority = spec["sort"]
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.layers = WORLD_RENDER_LAYER
	add_child(sprite)
	return sprite


func _make_bracket(color: Color) -> MeshInstance3D:
	if _bracket_mesh == null:
		_bracket_mesh = _build_bracket_mesh()
	var instance := MeshInstance3D.new()
	instance.mesh = _bracket_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


# How many ROWS of column the selector encloses -- the enum in the units the geometry works in.
func selector_depth_rows() -> int:
	return 1 if selector_depth == SelectorDepth.HALF else Terrain.UNITS_PER_LEVEL


# Half the COLUMN the selector marks -- the volume ITSELF, before bracket_scale swells the drawn box
# around it. The scale belongs to the mesh and not to the placement, exactly as on X and Z where the
# cell's own half is 0.5 * CELL_SIZE and only the mesh multiplies it: fold it in here and the box
# grows downward only, so it sits (scale - 1) * half a row low. Caught by
# test_the_selector_encloses_the_whole_block, which measures the CENTRE for this reason.
func selector_half_height() -> float:
	return 0.5 * float(selector_depth_rows()) * BoardSpace.ROW_HEIGHT


# Turning the knob has to move what is ALREADY on screen -- see the export's own note. Both halves
# are needed and neither implies the other: the box is a different HEIGHT (a new mesh) and it hangs
# from a different POINT (a new transform), and a pool that never repaints would show whichever half
# was forgotten.
func _set_selector_depth(value: SelectorDepth) -> void:
	selector_depth = value
	if _markers.is_empty():
		return   # nothing standing yet -- the mesh builds at the new height on demand
	_bracket_mesh = null
	for layer: Layer in _markers:
		if LAYERS[layer]["kind"] != Kind.BRACKET:
			continue
		if _bracket_mesh == null:
			_bracket_mesh = _build_bracket_mesh()
		var cells: Array = _cells.get(layer, [])
		var pool: Array = _markers[layer]
		for i in pool.size():
			var bracket := pool[i] as MeshInstance3D
			if bracket == null:
				continue
			bracket.mesh = _bracket_mesh
			if i < cells.size():
				var cell: Vector3i = cells[i]
				bracket.transform = _marker_transform(LAYERS[layer], cell, null)


# Three short arms per corner, eight corners: the voxel's corners, nothing else. NOT a cube since
# #427 slice 2 -- X and Z span a CELL, Y spans however many ROWS the selector is set to, because a
# mirror row is half a level and a cube would enclose the wrong volume.
func _build_bracket_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := Vector3(0.5 * BoardSpace.CELL_SIZE, selector_half_height(),
			0.5 * BoardSpace.CELL_SIZE) * bracket_scale
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var corner := Vector3(sx, sy, sz) * half
				_add_arm(st, corner, Vector3(-sx, 0, 0))
				_add_arm(st, corner, Vector3(0, -sy, 0))
				_add_arm(st, corner, Vector3(0, 0, -sz))
	st.commit(mesh)
	return mesh


func _add_arm(st: SurfaceTool, corner: Vector3, inward: Vector3) -> void:
	var arm_end := corner + inward * bracket_arm
	var lo := Vector3(minf(corner.x, arm_end.x), minf(corner.y, arm_end.y), minf(corner.z, arm_end.z))
	var hi := Vector3(maxf(corner.x, arm_end.x), maxf(corner.y, arm_end.y), maxf(corner.z, arm_end.z))
	var pad := Vector3.ONE * (bracket_thickness * 0.5)
	pad -= inward.abs() * (bracket_thickness * 0.5)  # no padding along the arm's own axis
	lo -= pad
	hi += pad
	_add_box(st, lo, hi)


func _add_box(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var corners := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z),
		Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	var faces := [
		[4, 5, 6, 7, Vector3.UP], [3, 2, 1, 0, Vector3.DOWN],
		[7, 6, 2, 3, Vector3.BACK], [5, 4, 0, 1, Vector3.FORWARD],
		[6, 5, 1, 2, Vector3.RIGHT], [4, 7, 3, 0, Vector3.LEFT],
	]
	for face: Array in faces:
		var normal: Vector3 = face[4]
		for index in [0, 1, 2, 0, 2, 3]:
			st.set_normal(normal)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(corners[face[index]])
