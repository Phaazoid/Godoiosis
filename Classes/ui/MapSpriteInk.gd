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


# The TEXTURE answer, for a slot that can only be handed one (#1082): the square of the sheet around
# THIS sprite's own ink, its longest side edge to edge, centred across with the feet on the floor. The
# slot's TextureRect stretches that square to fill itself, so every unit fills its slot and they stop
# sharing one scale (dev ruling: a wizard draws bigger than a lancer, and nothing is ever cut off).
# That is why this reads ink_of rather than INK_RECT, which the shared-scale surfaces above keep.
# Anything not SHEET square is not a map sprite (a move row's 16px terrain icon) and passes through
# untouched.
static func portrait(texture: Texture2D) -> Texture2D:
	if texture == null or Vector2i(texture.get_size()) != Vector2i(SHEET, SHEET):
		return texture
	var ink := ink_of(texture)
	var side := maxi(ink.size.x, ink.size.y)
	var x := clampi(roundi(ink.position.x + ink.size.x * 0.5 - side * 0.5), 0, SHEET - side)
	var y := clampi(ink.end.y - side, 0, SHEET - side)
	var crop := AtlasTexture.new()
	crop.atlas = texture
	crop.region = Rect2(x, y, side, side)
	return crop


# One sprite's own ink box in its sheet. BoardMirror.opaque_bounds is the one "is this ink" rule
# (UnitSprite3D and StatusArt read it too), so the queue cannot disagree with the diorama about where a
# character is. Cached per texture, UnitSprite3D._art_top_cache's idiom: decoding an imported texture
# is real work and the queue asks on every rebuild. An unreadable image answers the median.
static var _ink_cache: Dictionary[String, Rect2i] = {}


static func ink_of(texture: Texture2D) -> Rect2i:
	var key := texture.resource_path
	if key.is_empty():
		key = str(texture.get_instance_id())
	if not _ink_cache.has(key):
		var image := texture.get_image()
		if image == null:
			return INK_RECT
		if image.is_compressed():
			image = image.duplicate()
			image.decompress()
		_ink_cache[key] = BoardMirror.opaque_bounds(image, Rect2i(Vector2i.ZERO, image.get_size()))
	return _ink_cache[key]
