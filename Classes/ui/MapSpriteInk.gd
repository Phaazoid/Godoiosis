extends Object
class_name MapSpriteInk

# WHERE THE CHARACTER ACTUALLY IS inside a map sprite -- the measurement, not one surface's pixels
# (#930, hoisting #560's scan).
#
# Every shipped map sprite draws its ink in the LOWER part of its canvas, ending on the bottom row.
# So anything that frames a portrait -- a ring, a disc, a crop window -- and centres on the CANVAS
# frames padding and misses the character. #560 found this scanning the deployed-force strip's disc;
# #930's aura ring is the second consumer, at a different size.
#
# WHY A SHARED HOME RATHER THAN A SECOND CONSTANT: PreMissionScreen.INK_OFFSET is this measurement
# already solved, but solved AT 24px -- a number, not the fact under it. A second surface needing the
# same fact at 52px cannot reuse a px offset, and retyping the texel rect is how two answers to one
# question start drifting.
#
# THE BASELINE IS NOW BUILT, NOT FOUND (#937). The Fire Emblem art shared a baseline by luck -- every
# one of those 18 sprites happened to end on row 31 -- and the Zerie art replacing it does not: its
# feet landed anywhere from row 54 to row 60 of a 100px cell. `tools/sprites/extract_stills.gd`
# re-canvasses each still onto SHEET x SHEET with its feet on the bottom row, so the spread is zero
# by construction rather than by an artist's care. Re-run that tool if the art is ever re-cut, and
# take INK_RECT from what it prints.

const SHEET := 64
# The MEDIAN ink box over all 42 characters, feet on the last row. Median rather than union, for
# #560's reason: a ring sized to the widest member hangs slack around everyone else, and the outliers
# (Werebear, Orc rider, Minotaur, Flame Golem) are this pack's Dragon -- they overflow it on purpose.
const INK_RECT := Rect2i(20, 44, 23, 20)


# Where the character's middle sits when the sheet is drawn into a box_px square.
static func ink_centre(box_px: float) -> Vector2:
	var scale := box_px / float(SHEET)
	return (Vector2(INK_RECT.position) + Vector2(INK_RECT.size) * 0.5) * scale


# How far the ink box reaches from that centre -- half its diagonal, which is what a ring has to
# clear to frame the character rather than cut through it.
static func ink_reach(box_px: float) -> float:
	return Vector2(INK_RECT.size).length() * 0.5 * (box_px / float(SHEET))


# Where to put a sheet-sized sprite inside a square window so the INK lands centred. Rounded, because
# a half-pixel offset on a nearest-filtered sprite samples the wrong texel.
static func window_offset(window_px: float) -> Vector2:
	return (Vector2(window_px, window_px) * 0.5 - ink_centre(SHEET)).round()


# The ZOOM answer, as against window_offset()'s 1:1 CROP: the destination rect for drawing a whole
# sheet so that its INK ends up centred on `centre` and reaching `reach` px from it. Everything
# outside the ink box is drawn too -- it is one texture -- so a caller wanting the overflow cut off
# clips its own rect (#990).
#
# THE CELL IS NOT THE ART (#937). Fitting the sheet into a box is only correct while the character
# fills its canvas: the pack's cell is 64 holding a ~23x20 character, so a 52px box spends two thirds
# of itself on padding. ActionMenuController._draw_centre_sprite asks the same question the other way
# round (fit the ink's LONGEST SIDE, feet on a seat) and keeps its own arithmetic for that reason.
static func ink_fit_rect(centre: Vector2, reach: float) -> Rect2:
	var scale := reach / ink_reach(SHEET)
	return Rect2(centre - ink_centre(SHEET) * scale, Vector2(SHEET, SHEET) * scale)


# The TEXTURE answer, for a slot that can only be handed one (#1082): a window_px square of the sheet
# at 1:1, the ink centred across and the feet on the window's floor. Floor rather than centred because
# the sheet ends at the feet, so a centred window would run past it -- and the floor gives the tall
# outliers the whole window's headroom. Anything not SHEET square is not a map sprite (a move row's
# 16px terrain icon) and passes through untouched.
static func portrait(texture: Texture2D, window_px: int) -> Texture2D:
	if texture == null or Vector2i(texture.get_size()) != Vector2i(SHEET, SHEET):
		return texture
	var window := mini(window_px, SHEET)
	var x := clampi(roundi(ink_centre(SHEET).x - window * 0.5), 0, SHEET - window)
	var crop := AtlasTexture.new()
	crop.atlas = texture
	crop.region = Rect2(x, SHEET - window, window, window)
	return crop
