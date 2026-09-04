extends Object
class_name QueueStyle

# The one answer to what the action-queue panel LOOKS like (#685). The panel's sections and rows are
# code-built, so their chrome cannot live in a .tscn sub-resource the way BackgroundPanel's does --
# and two files hand-rolling the same StyleBoxFlat is how three surfaces ended up disagreeing about
# the queue's colour in the first place.
#
# The palette is Scenes/UnitInfoPanel.tscn's, verbatim where it fits: the inspect panel is the
# newest deliberately designed surface in the game and it is docked on the opposite edge of the same
# screen, so matching it is what makes the battle UI read as one system (dev ruling, 2026-09-03).
#
# NO KNOBS ON THE CHROME, deliberately: the panel/section/row values are a copy of a neighbouring
# panel that has none either, so a knob would be a second place to tune one look. The exception is a
# colour this panel INVENTS and that has to read against the element chips -- EVENT_TINT below --
# which gets a row for the same reason ElementPalette's seven do: it is a feel value sitting beside
# knobs he is already dragging, and an un-tunable neighbour is the inert-slider problem in reverse.

# --- the slate palette ---------------------------------------------------------------------------
const PANEL_BG := Color(0.12, 0.12, 0.14, 0.97)        # UnitInfoPanel.tscn's panel fill
const PANEL_BORDER := Color(0.227, 0.227, 0.259)
const SECTION_BG := Color(0.09, 0.09, 0.1, 0.7)        # ...and its section fill
const SECTION_BORDER := Color(0.2, 0.2, 0.22)          # ...and its section border
const HEADER_BG := Color(1, 1, 1, 0.035)
const HEADER_TEXT := Color(0.604, 0.627, 0.671)

# The one warm value left in the panel: the queue's old parchment identity survives as INK on a dark
# ground rather than as a second palette.
const TITLE_TEXT := Color(0.902, 0.827, 0.678)

# A ROW SITS ABOVE ITS SECTION, NOT IN IT. First pass had the row at 0.137 against a 0.09 section
# card, i.e. a step of nothing -- the dev's reading was that the row "doesn't stand out from the
# rest of the menu, and it's hard to see things against the background" (2026-09-03). The section is
# the gutter and the row is the card lying on it, so the contrast belongs here rather than in a
# darker section.
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

# --- CODE-BUILT values only ----------------------------------------------------------------------
# Deliberately NOT here: the title's font size, the readout's, and the rail's width. Those nodes are
# authored in the .tscn (scene for static, code for dynamic), so a const beside them would be a
# second answer to a question the scene already settles.
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
		var box := _flat(PANEL_BG, PANEL_BORDER, 2, 6)
		box.set_content_margin_all(0.0)   # BackgroundPanel's own MarginContainer owns the inset
		return box)


static func section_box() -> StyleBoxFlat:
	return _cached("section", func() -> StyleBoxFlat:
		var box := _flat(SECTION_BG, SECTION_BORDER, 1, 6)
		box.set_content_margin_all(1.0)   # the border alone: the header strip spans the card
		return box)


static func header_box() -> StyleBoxFlat:
	return _cached("header", func() -> StyleBoxFlat:
		var box := _flat(HEADER_BG, SECTION_BORDER, 0, 0)
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
		var bg: Color = ROW_REFUSED_BG if refused else (ROW_HOVER_BG if hovered else ROW_BG)
		var border: Color
		if refused:
			border = ROW_REFUSED_HOVER_BORDER if hovered else ROW_REFUSED_BORDER
		else:
			border = ROW_HOVER_BORDER if hovered else ROW_BORDER
		var box := _flat(bg, border, 1, 4)
		box.set_content_margin_all(1.0)   # the rail rides flush inside the border
		return box)


static func execute_box() -> StyleBoxFlat:
	return _cached("execute", func() -> StyleBoxFlat:
		return _flat(EXECUTE_BG, EXECUTE_BORDER, 1, 5))


static func execute_hover_box() -> StyleBoxFlat:
	return _cached("execute_hover", func() -> StyleBoxFlat:
		return _flat(EXECUTE_HOVER_BG, EXECUTE_BORDER, 1, 5))


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


static func _cached(key: String, build: Callable) -> StyleBoxFlat:
	if not _cache.has(key):
		_cache[key] = build.call()
	return _cache[key]
