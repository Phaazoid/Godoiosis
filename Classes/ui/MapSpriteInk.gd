extends Object
class_name MapSpriteInk

# WHERE THE CHARACTER ACTUALLY IS inside a 32x32 map sprite -- the measurement, not one surface's
# pixels (#930, hoisting #560's scan).
#
# Every shipped map sprite draws its ink in the LOWER half of its canvas: x 8..23, y 13..31, ending
# on row 31. So anything that frames a portrait -- a ring, a disc, a crop window -- and centres on
# the CANVAS frames padding and misses the character by a third of the box. #560 found this scanning
# the deployed-force strip's disc; #930's aura ring is the second consumer, at a different size.
#
# WHY A SHARED HOME RATHER THAN A SECOND CONSTANT: PreMissionScreen.INK_OFFSET is this measurement
# already solved, but solved AT 24px -- a number, not the fact under it. A second surface needing the
# same fact at 52px cannot reuse a px offset, and retyping the texel rect is how two answers to one
# question start drifting. window_offset() below reproduces the shipped offset exactly, which is what
# makes this a MOVE rather than a rewrite (test_aura_ring pins that).

const SHEET := 32
# x 8..23, y 13..31 inclusive -- Rect2i's size is exclusive, hence 16 x 19.
const INK_RECT := Rect2i(8, 13, 16, 19)


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
