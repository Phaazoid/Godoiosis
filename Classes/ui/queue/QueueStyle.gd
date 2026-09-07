extends Object
class_name QueueStyle

# The one answer to what the action-queue panel LOOKS like (#685). The panel's sections and rows are
# code-built, so their chrome cannot live in a .tscn sub-resource the way BackgroundPanel's does --
# and two files hand-rolling the same StyleBoxFlat is how three surfaces ended up disagreeing about
# the queue's colour in the first place.
#
# TWO PALETTES SINCE ROUND 5, and the player picks between them (PlayerSettings.QUEUE_PALETTE): the
# shipped SLATE, and the PARCHMENT the #685 grill offered and lost. #422's aim-palette shape exactly
# -- the dev authors what is IN a palette, the player picks BETWEEN palettes, two axes.
#
# THE SPLIT THAT MAKES THAT WORK: chrome is AUTHORED per palette, elements are ADAPTED.
#   * A chrome colour is a ROLE. Near-white header text on slate has to become near-black on cream --
#     an inversion, not a lightness shift -- so there is nothing to derive and PALETTES holds a value.
#   * An element colour is SEMANTIC. Fire is orange in both palettes, so only its ink WEIGHT may move
#     and _adapt derives it from the same seven statics the dev's knobs write. That is why this is
#     the first palette here whose alternative leaves those knobs LIVE, where AIM_PALETTES re-authors
#     its colours and makes them inert. See docs/design/presentation-effects.md.
#
# NO KNOBS ON THE CHROME, deliberately: the panel/section/row values are a copy of a neighbouring
# panel that has none either, so a knob would be a second place to tune one look. The exceptions are
# colours this panel INVENTS and that have to read against the element chips -- EVENT_TINT, and the
# two parchment ink values -- which get rows for the same reason ElementPalette's seven do: they are
# feel values sitting beside knobs he is already dragging.

# A TEXT ROLE IS A WEIGHT AND A GROUND, and the second half was invisible until #814. Under slate
# every ground is dark, so one value answered both questions; parchment inverts the paper and splits
# them. The grid, with the empty cell left empty on purpose -- nothing needs body text on the frame:
#
#                     on the dark FRAME          on PAPER (section / row)
#     title           TITLE_TEXT                 NAME_TEXT
#     body            --                         BODY_TEXT
#     muted           FRAME_TEXT                 HEADER_TEXT
#     refused         FRAME_REFUSED_TEXT         ROW_REFUSED_BORDER
#
# Each of the three added there took its SLATE value from what its sites already rendered -- the
# engine default for BODY_TEXT, TITLE_TEXT's own for NAME_TEXT, HEADER_TEXT's for FRAME_TEXT -- so
# slate is unchanged by construction and only the parchment column is new authorship. Picking a role
# by weight alone is what put cream text on a cream card and brown ink on the brown frame.

# Every colour this panel answers for. The enum is what PALETTES is keyed on, so a role added here
# without a parchment value is caught by test_queue_palette's coverage case rather than by a hole on
# screen. OverlayManager.AimChannel's shape, one panel further out.
enum Role {
	PANEL_BG,
	PANEL_BORDER,
	SECTION_BG,
	SECTION_BORDER,
	HEADER_BG,
	HEADER_TEXT,
	TITLE_TEXT,
	BODY_TEXT,
	NAME_TEXT,
	FRAME_TEXT,
	FRAME_REFUSED_TEXT,
	ROW_BG,
	ROW_BORDER,
	ROW_HOVER_BG,
	ROW_HOVER_BORDER,
	ROW_REFUSED_BG,
	ROW_REFUSED_BORDER,
	ROW_REFUSED_HOVER_BORDER,
	EXECUTE_BG,
	EXECUTE_BORDER,
	EXECUTE_HOVER_BG,
	EXECUTE_TEXT,
	READOUT_ALLY,
	READOUT_ENEMY,
	EVENT_TINT,
	RAIL_NEUTRAL,
}

# --- SLATE: the authored set, and DEFAULT's fall-through ------------------------------------------
#
# These are Scenes/UnitInfoPanel.tscn's, verbatim where they fit: the inspect panel is the newest
# deliberately designed surface in the game and it is docked on the opposite edge of the same screen,
# so matching it is what makes the battle UI read as one system (dev ruling, 2026-09-03).
#
# THEY ARE NOT A ROW IN PALETTES, and that is the whole anti-drift mechanism (#422's ruling): a
# DEFAULT row would be a COPY of these, so the day one is tuned the panel and the table disagree, and
# EVENT_TINT's knob would write a static nobody reads. ink() falls through to _authored() instead.
const PANEL_BG := Color(0.12, 0.12, 0.14, 0.97)        # UnitInfoPanel.tscn's panel fill
const PANEL_BORDER := Color(0.227, 0.227, 0.259)
const SECTION_BG := Color(0.09, 0.09, 0.1, 0.7)        # ...and its section fill
const SECTION_BORDER := Color(0.2, 0.2, 0.22)          # ...and its section border
const HEADER_BG := Color(1, 1, 1, 0.035)
const HEADER_TEXT := Color(0.604, 0.627, 0.671)

# The one warm value left in the panel: the queue's old parchment identity survives as INK on a dark
# ground rather than as a second palette. Round 5 gave that second palette back as a CHOICE, which
# does not change what this value is doing in the slate one.
const TITLE_TEXT := Color(0.902, 0.827, 0.678)

# The three ground-aware roles (#814). Every value here is what its sites ALREADY rendered, which is
# what makes slate byte-identical rather than merely close -- test_queue_palette pins each to its
# provenance, so a tweak here is a deliberate change to the shipped look and not a drift.
#
# BODY_TEXT is the engine's own Label default. Those labels carried no override at all, so on slate
# they were right by accident and on parchment they were white on cream -- the report's own words.
const BODY_TEXT := Color(1, 1, 1)
# What a card is OF -- the unit it names, the job it holds, the piece being carried. TITLE_TEXT's
# value, because that is the role these three sites reached for: correct on the dark card, and the
# same colour as the cream one. A name in a LIST is a row rather than a heading and takes BODY_TEXT,
# which is also what those rows already render.
const NAME_TEXT := Color(0.902, 0.827, 0.678)
# ...and HEADER_TEXT's, for the muted text that turned out to be sitting on the FRAME rather than on
# a row: the region headers, the stash hint, the fitting card's readouts.
const FRAME_TEXT := Color(0.604, 0.627, 0.671)

# A REFUSAL is the fourth weight, and it needed the frame's half for the same reason: those hints
# borrowed ROW_REFUSED_BORDER, which is the dark red a refused ROW wears on paper. Slate's value,
# again, so nothing shipped moves.
const FRAME_REFUSED_TEXT := Color(0.78, 0.35, 0.28)

# A ROW SITS ABOVE ITS SECTION, NOT IN IT. First pass had the row at 0.137 against a 0.09 section
# card, i.e. a step of nothing -- the dev's reading was that the row "doesn't stand out from the
# rest of the menu, and it's hard to see things against the background" (2026-09-03). The section is
# the gutter and the row is the card lying on it, so the contrast belongs here rather than in a
# darker section. Parchment keeps that DIRECTION -- its row is lighter than its section too -- even
# though both ends moved to the other end of the scale.
const ROW_BG := Color(0.23, 0.23, 0.27)
const ROW_BORDER := Color(0.35, 0.35, 0.4)
const ROW_HOVER_BG := Color(0.3, 0.3, 0.35)
const ROW_HOVER_BORDER := Color(0.48, 0.48, 0.55)

# The BORDER is validity's channel and element's is the rail -- one motif per meaning
# (visual-clarity.md principle 2), which is what a colour-per-element border would have collided
# with on a row that is both elemental and refused.
const ROW_REFUSED_BG := Color(0.27, 0.17, 0.17)
const ROW_REFUSED_BORDER := Color(0.78, 0.35, 0.28)
const ROW_REFUSED_HOVER_BORDER := Color(0.93, 0.47, 0.38)

# Execute has to read as ACT NOW against the slate, which the engine's default button chrome cannot:
# it is grey on a grey panel and simply disappeared (dev, 2026-09-03). Crimson rather than the old
# pure-red #ED0000, which fought every other saturated thing on screen. The DISABLED state needs no
# second style -- set_execute_state modulates by EXECUTE_DULL, which mutes this to a dead maroon.
const EXECUTE_BG := Color(0.62, 0.16, 0.12)
const EXECUTE_BORDER := Color(0.95, 0.45, 0.33)
const EXECUTE_HOVER_BG := Color(0.74, 0.21, 0.15)
const EXECUTE_TEXT := Color(1, 0.93, 0.9)

# The hp->hp readout, team-coloured: green when a friendly is losing HP, red for an enemy.
const READOUT_ALLY := Color(0.486, 0.878, 0.561)
const READOUT_ENEMY := Color(1.0, 0.541, 0.478)

# What the WORLD did, not what an element did -- "Fell 2!", "Drowning!", "Into the void!",
# "Insulated!". These wore ElementPalette.NEUTRAL until the dev read them off the screen
# (2026-09-03): that value is the RAIL's off state, a structural grey chosen to disappear, and text
# in it is grey on grey. Deliberately OUTSIDE the element wheel -- every element colour is
# saturated, so a cool near-white cannot be mistaken for one, and Earth's ochre is close enough that
# the obvious warm amber would have collided.
static var EVENT_TINT := Color(0.82, 0.84, 0.88)

# --- PARCHMENT: the alternative, authored ---------------------------------------------------------
#
# Eleven values are the #685 mockup's own; the other eleven follow the same reasoning slate used, and
# two of those reasonings INVERT rather than transpose:
#   * a HOVER goes DARKER here. Slate lifts a row off its section; a row already at 0.98 has nowhere
#     up to go, so warmth is the only step left.
#   * the HEADER strip DARKENS its section here where slate's lightens it -- which is why HEADER_BG
#     is opaque rather than slate's white wash at alpha 0.035. A wash is a direction, not a colour.
# Two roles deliberately do NOT invert: TITLE_TEXT sits on the dark outer frame and EXECUTE_TEXT on
# crimson, in BOTH palettes, so both stay light. Blanket-inverting a palette is how a button loses
# its own label.
#
# NO DEFAULT ROW HERE. See the slate block above.
const PALETTES := {
	PlayerSettings.QueuePalette.PARCHMENT: {
		Role.PANEL_BG: Color(0.231, 0.165, 0.129, 0.97),   # the dark frame the paper lies on
		Role.PANEL_BORDER: Color(0.478, 0.345, 0.247),
		# Opaque where slate is 0.7: a translucent card over slate stays slate, over dark brown it
		# goes muddy. Alpha is a per-palette decision, not a shared constant.
		Role.SECTION_BG: Color(0.941, 0.863, 0.776, 1.0),
		Role.SECTION_BORDER: Color(0.541, 0.400, 0.278),
		Role.HEADER_BG: Color(0.878, 0.780, 0.663, 1.0),
		Role.HEADER_TEXT: Color(0.420, 0.271, 0.188),
		Role.TITLE_TEXT: Color(0.941, 0.863, 0.776),       # on the dark frame -- stays light
		# The three that INVERT with their ground (#814). Body is the darkest thing on the paper --
		# the numbers a player reads off a card -- and a NAME is warmer rather than lighter, echoing
		# what TITLE_TEXT is doing on the slate side without giving up the page's authority.
		Role.BODY_TEXT: Color(0.157, 0.110, 0.078),
		Role.NAME_TEXT: Color(0.208, 0.129, 0.086),
		# Muted, on the dark frame: light here, where HEADER_TEXT is ink. Kept clearly under
		# TITLE_TEXT's cream so a region's header still reads quieter than its count.
		Role.FRAME_TEXT: Color(0.769, 0.694, 0.612),
		# An alarm on the dark frame: light where the row's refusal is a dark red, and warmer than
		# FRAME_TEXT beside it so a refusal still reads as one rather than as emphasis.
		Role.FRAME_REFUSED_TEXT: Color(0.910, 0.494, 0.412),
		Role.ROW_BG: Color(0.984, 0.945, 0.886),
		Role.ROW_BORDER: Color(0.769, 0.659, 0.514),
		Role.ROW_HOVER_BG: Color(0.949, 0.894, 0.812),
		Role.ROW_HOVER_BORDER: Color(0.612, 0.486, 0.314),
		Role.ROW_REFUSED_BG: Color(0.969, 0.871, 0.847),
		Role.ROW_REFUSED_BORDER: Color(0.659, 0.204, 0.165),
		Role.ROW_REFUSED_HOVER_BORDER: Color(0.490, 0.122, 0.094),
		Role.EXECUTE_BG: Color(0.659, 0.204, 0.165),
		Role.EXECUTE_BORDER: Color(0.851, 0.549, 0.353),   # a warm rim: it sits on the dark frame
		Role.EXECUTE_HOVER_BG: Color(0.769, 0.259, 0.227),
		Role.EXECUTE_TEXT: Color(0.992, 0.941, 0.894),     # on crimson -- stays light
		Role.READOUT_ALLY: Color(0.173, 0.435, 0.235),
		Role.READOUT_ENEMY: Color(0.659, 0.204, 0.165),
		# Slate's reasoning, pointed at a light ground: a COOL near-neutral, because every element
		# ink on parchment is a saturated dark and a warm dull brown would sit beside Earth's ochre.
		Role.EVENT_TINT: Color(0.247, 0.259, 0.282),
		# The rail's OFF state, with the same job here: DISAPPEAR. A hair under the row, the way
		# slate's sits a hair over it -- promoting either to text is the round-4 bug.
		Role.RAIL_NEUTRAL: Color(0.910, 0.855, 0.773),
	},
}

# How an element's colour becomes INK on parchment. The seven statics are tuned to GLOW against a
# dark ground; unchanged on cream they are pastel mush, so both ROLE properties of a colour move and
# its HUE does not.
#
# A fixed DEPTH rather than a scale, so all seven read with one authority the way body text does --
# which is also what makes contrast against the row a property a test can assert. A saturation GAIN
# rather than a floor, so the dev's relative choices stay monotonic; it is clamped at 1.0, which is
# the only place his ordering can flatten.
#
# BOTH ARE INERT WHILE SLATE IS LIVE, and that is #422's cost pointed the other way -- acceptable
# here for a reason it is not there: you tune them while LOOKING at parchment, and the panel repaints
# under the slider. The seven element knobs themselves are inert under neither palette, which is the
# whole point of adapting rather than re-authoring.
static var PARCHMENT_INK_DEPTH := 0.62
static var PARCHMENT_INK_SATURATION := 1.5

# --- reads ----------------------------------------------------------------------------------------

# One role's colour in whichever palette the player has picked. DEFAULT returns the authored const --
# never a table row -- which is what keeps the dev's knob and the shipped default one value.
#
# A palette with no row, or a row with no colour, is a table that has fallen behind its enums. Say so
# and paint the authored value: a panel that is the wrong colour is legible, one that crashed the
# draw is not (OverlayManager._palette_color's exact degradation).
static func ink(role: Role) -> Color:
	var picked := _palette()
	if picked == PlayerSettings.QueuePalette.DEFAULT:
		return _authored(role)
	if not PALETTES.has(picked):
		push_error("QueueStyle: queue palette %d has no colours -- falling back to the authored ones"
				% picked)
		return _authored(role)
	var row: Dictionary = PALETTES[picked]
	if not row.has(role):
		push_error("QueueStyle: queue palette %d has no colour for role %s"
				% [picked, Role.keys()[role]])
		return _authored(role)
	var painted: Color = row[role]
	return painted

# What an ELEMENT looks like in this panel right now. ElementPalette answers "what colour is Fire"
# and stays the authored registry; this answers "what does Fire look like on THIS ground". A declared
# second projection of one store, not a second store (Law #4) -- the words color_for_state uses.
static func element_ink(element: Elemental.Element) -> Color:
	return _adapt(ElementPalette.color_for_element(element))

static func state_ink(state: Elemental.State) -> Color:
	return _adapt(ElementPalette.color_for_state(state))


# The third projection of _adapt (#814), for a tint a SURFACE authored inline rather than one off the
# element wheel -- a prosthetic's blue, an ability's violet. Same argument as the two above: the HUE
# is what carries the meaning, so only its weight is the ground's business, and a pair of chrome
# roles would have authored the same two hues twice. Identity under slate, so nothing shipped moves.
static func adapted_ink(authored: Color) -> Color:
	return _adapt(authored)

static func _palette() -> int:
	return PlayerSettings.choice_of(PlayerSettings.Setting.QUEUE_PALETTE)

# Hue is carried through untouched -- that is the semantic half -- and so is alpha. Only value and
# saturation are the ground's business. Identity under slate, so every authored colour reaches the
# shipped panel exactly as it did before there was a second palette.
static func _adapt(authored: Color) -> Color:
	if _palette() != PlayerSettings.QueuePalette.PARCHMENT:
		return authored
	var adapted := Color.from_hsv(authored.h,
			minf(1.0, authored.s * PARCHMENT_INK_SATURATION), PARCHMENT_INK_DEPTH)
	adapted.a = authored.a
	return adapted

# A match rather than a const Dictionary, and not by preference: EVENT_TINT is a static var the dev's
# knob writes and RAIL_NEUTRAL lives on ElementPalette, so a const table would snapshot both at parse
# time and the knob would move a value nobody reads.
static func _authored(role: Role) -> Color:
	match role:
		Role.PANEL_BG: return PANEL_BG
		Role.PANEL_BORDER: return PANEL_BORDER
		Role.SECTION_BG: return SECTION_BG
		Role.SECTION_BORDER: return SECTION_BORDER
		Role.HEADER_BG: return HEADER_BG
		Role.HEADER_TEXT: return HEADER_TEXT
		Role.TITLE_TEXT: return TITLE_TEXT
		Role.BODY_TEXT: return BODY_TEXT
		Role.NAME_TEXT: return NAME_TEXT
		Role.FRAME_TEXT: return FRAME_TEXT
		Role.FRAME_REFUSED_TEXT: return FRAME_REFUSED_TEXT
		Role.ROW_BG: return ROW_BG
		Role.ROW_BORDER: return ROW_BORDER
		Role.ROW_HOVER_BG: return ROW_HOVER_BG
		Role.ROW_HOVER_BORDER: return ROW_HOVER_BORDER
		Role.ROW_REFUSED_BG: return ROW_REFUSED_BG
		Role.ROW_REFUSED_BORDER: return ROW_REFUSED_BORDER
		Role.ROW_REFUSED_HOVER_BORDER: return ROW_REFUSED_HOVER_BORDER
		Role.EXECUTE_BG: return EXECUTE_BG
		Role.EXECUTE_BORDER: return EXECUTE_BORDER
		Role.EXECUTE_HOVER_BG: return EXECUTE_HOVER_BG
		Role.EXECUTE_TEXT: return EXECUTE_TEXT
		Role.READOUT_ALLY: return READOUT_ALLY
		Role.READOUT_ENEMY: return READOUT_ENEMY
		Role.EVENT_TINT: return EVENT_TINT
		Role.RAIL_NEUTRAL: return ElementPalette.NEUTRAL
	push_error("QueueStyle: no authored colour for role %d" % role)
	return Color.MAGENTA

# --- CODE-BUILT values only ----------------------------------------------------------------------
# Deliberately NOT here: the title's font size, the readout's, and the rail's width. Those nodes are
# authored in the .tscn (scene for static, code for dynamic), so a const beside them would be a
# second answer to a question the scene already settles. None of them forks by palette either -- a
# palette is a COLOUR decision, and a dock that changed shape under one would be a second layout.
const HEADER_FONT_SIZE := 10
const CONSEQUENCE_FONT_SIZE := 10
const ROW_GAP := 2          # a row wrapper's own top/bottom margin inside its section
const ROW_INSET := 3        # a row's clearance from its section's edges
const CHIP_ICON := 16       # a state chip's icon, rendered size

# Built once and shared: a StyleBox is immutable in use here, and one box per row would be a fresh
# resource per render pass.
static var _cache: Dictionary = {}


static func panel_box() -> StyleBoxFlat:
	return _cached("panel", func() -> StyleBoxFlat:
		var box := _flat(ink(Role.PANEL_BG), ink(Role.PANEL_BORDER), 2, 6)
		box.set_content_margin_all(0.0)   # BackgroundPanel's own MarginContainer owns the inset
		return box)


# ACCENTED is the same card wearing the friendly ink -- a pre-mission unit that is coming with you.
# The BORDER carries it, never the fill: the fill is the ground every chip and number on that card is
# read against, and tinting it would fight all of them at once (visual-clarity.md, one motif per
# meaning). The content margin stays 1.0 across both states ON PURPOSE, so a card does not resize the
# instant it is deployed -- the border thickens into the padding it already had.
static func section_box(accented: bool = false) -> StyleBoxFlat:
	return _cached("section_%s" % accented, func() -> StyleBoxFlat:
		var border: Color = ink(Role.READOUT_ALLY) if accented else ink(Role.SECTION_BORDER)
		var box := _flat(ink(Role.SECTION_BG), border, 2 if accented else 1, 6)
		box.set_content_margin_all(1.0)   # the border alone: the header strip spans the card
		return box)


static func header_box() -> StyleBoxFlat:
	return _cached("header", func() -> StyleBoxFlat:
		var box := _flat(ink(Role.HEADER_BG), ink(Role.SECTION_BORDER), 0, 0)
		box.border_width_bottom = 1
		box.corner_radius_top_left = 5
		box.corner_radius_top_right = 5
		box.content_margin_left = 7.0
		box.content_margin_right = 7.0
		box.content_margin_top = 3.0
		box.content_margin_bottom = 3.0
		return box)


# A row's chrome answers two independent questions at once -- is this order refused, and is the
# pointer on it -- so all four combinations are real states rather than a base plus a tint.
static func row_box(refused: bool, hovered: bool) -> StyleBoxFlat:
	var key := "row_%s_%s" % [refused, hovered]
	return _cached(key, func() -> StyleBoxFlat:
		var bg: Color = ink(Role.ROW_REFUSED_BG) if refused else (
				ink(Role.ROW_HOVER_BG) if hovered else ink(Role.ROW_BG))
		var border: Color
		if refused:
			border = ink(Role.ROW_REFUSED_HOVER_BORDER) if hovered else ink(Role.ROW_REFUSED_BORDER)
		else:
			border = ink(Role.ROW_HOVER_BORDER) if hovered else ink(Role.ROW_BORDER)
		var box := _flat(bg, border, 1, 4)
		box.set_content_margin_all(1.0)   # the rail rides flush inside the border
		return box)


static func execute_box() -> StyleBoxFlat:
	return _cached("execute", func() -> StyleBoxFlat:
		return _flat(ink(Role.EXECUTE_BG), ink(Role.EXECUTE_BORDER), 1, 5))


static func execute_hover_box() -> StyleBoxFlat:
	return _cached("execute_hover", func() -> StyleBoxFlat:
		return _flat(ink(Role.EXECUTE_HOVER_BG), ink(Role.EXECUTE_BORDER), 1, 5))


# An element-tinted pill, for a state chip and for a fired reaction's word alike. NOT cached: the
# colour is a knob the dev drags, so a box built once would go stale the moment he moved it.
static func tint_box(tint: Color) -> StyleBoxFlat:
	var box := _flat(Color(tint.r, tint.g, tint.b, 0.2), tint, 1, 4)
	box.content_margin_left = 4.0
	box.content_margin_right = 4.0
	box.content_margin_top = 1.0
	box.content_margin_bottom = 1.0
	return box


static func _flat(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_border_width_all(width)
	box.border_color = border
	box.set_corner_radius_all(radius)
	return box


# THE PALETTE IS PART OF THE KEY, and it lives here rather than at each caller so that nothing has to
# remember: every box above is built out of ink(), so a cache keyed on the name alone hands the
# parchment panel the slate box it built first and the swap does nothing at all.
static func _cached(key: String, build: Callable) -> StyleBoxFlat:
	var full := "%d|%s" % [_palette(), key]
	if not _cache.has(full):
		_cache[full] = build.call()
	return _cache[full]
