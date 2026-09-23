class_name PathPalette
extends Object

# THE COLOURS A PATH IS DRAWN IN, one per path by index (#1079, #1057 part 2). Two surfaces draw paths:
# the Attack Editor's grid (PathArrows, in Classes/dev) and the shape plate on the fitting and rune
# cards (PathLines). The hues live here, beside the shipping one, because a card reading a dev class
# would be the wrong direction; the editor reads them from here.
#
# The editor draws its arrows over dark cells in these hues as authored. The plate draws its lines
# over the YELLOW footprint, where the editor's orange all but vanishes, so it asks for each hue
# pushed DARK instead (dev, 2026-09-22: "a palette of dark colors for being readable when displayed
# on yellow") -- derived, never a second authored set, so a path keeps its colour family on both.

# The editor's six, cycled by path index.
const HUES: Array[Color] = [
	Color("ffb45e"), Color("4fd8c8"), Color("c39bff"),
	Color("ff7a9a"), Color("9be06a"), Color("6aaeff"),
]

# How far a dark line must stand off the ground it is drawn on, as a WCAG contrast ratio. A
# readability floor rather than a look: every hue is pushed just past it, so the six stay distinct.
const MIN_CONTRAST := 6.5

static var _dark_cache: Dictionary = {}


static func hue(index: int) -> Color:
	return HUES[index % HUES.size()]


# Path `index`'s hue, darkened in OKHSL lightness -- which keeps the hue itself -- until it clears
# MIN_CONTRAST against `ground`. Black if nothing on the way does.
static func dark(index: int, ground: Color) -> Color:
	var key := "%d|%s" % [index % HUES.size(), ground.to_html()]
	if _dark_cache.has(key):
		return _dark_cache[key]
	var base := hue(index)
	var found := Color.BLACK
	var lightness := 0.6
	while lightness > 0.0:
		var candidate := Color.from_ok_hsl(base.ok_hsl_h, maxf(0.8, base.ok_hsl_s), lightness)
		if contrast(candidate, ground) >= MIN_CONTRAST:
			found = candidate
			break
		lightness -= 0.01
	_dark_cache[key] = found
	return found


# WCAG 2 contrast ratio between two opaque colours, 1 (none) to 21 (black on white).
static func contrast(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear().get_luminance()
	var lb := b.srgb_to_linear().get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
