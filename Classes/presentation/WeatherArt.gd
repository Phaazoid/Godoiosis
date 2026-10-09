extends Object
class_name WeatherArt

# The pixel art the weather draws (#1260), generated rather than drawn: a rain streak, a splash ring's
# frames and the queue row's icon. GasPuffArt's shape -- a tune shows the moment the art is rebuilt,
# and a sheet replaces any of it once someone draws one. The icon especially is a PLACEHOLDER.
#
# Pure and static: every function returns a fresh Image or a cached texture, and nothing reads a node.

const ICON_SIZE := GridUtils.TILE_SIZE
# How many frames a splash ring plays, and the square each is drawn in, in art pixels.
const SPLASH_FRAMES := 4
const SPLASH_SIDE := 9

static var _icon: Texture2D = null


# A rain streak `texels` art pixels long and one wide, brightest at its leading (bottom) end. The
# draw quad stretches it over texels / UnitSprite3D.texels_per_unit world units, so it shares the
# sprites' density whatever that is tuned to.
static func streak(texels: int, color: Color) -> Image:
	var length := maxi(texels, 1)
	var image := Image.create_empty(1, length, false, Image.FORMAT_RGBA8)
	for y in length:
		var lead := float(y + 1) / float(length)   # 0 at the tail, 1 at the head
		image.set_pixel(0, y, Color(color.r, color.g, color.b, color.a * lerpf(0.35, 1.0, lead)))
	return image


# A splash ring's frames side by side, each SPLASH_SIDE square: a ring one pixel thick that widens
# and thins out frame by frame. Drawn as a circle; the quad lies flat on the ground, so perspective
# makes the ellipse.
static func splash_strip(color: Color) -> Image:
	var image := Image.create_empty(SPLASH_SIDE * SPLASH_FRAMES, SPLASH_SIDE, false, Image.FORMAT_RGBA8)
	var centre := Vector2(SPLASH_SIDE - 1, SPLASH_SIDE - 1) * 0.5
	for frame in SPLASH_FRAMES:
		var radius := 1.0 + float(frame) * (centre.x - 1.0) / float(SPLASH_FRAMES - 1)
		var alpha := color.a * (1.0 - float(frame) / float(SPLASH_FRAMES))
		for y in SPLASH_SIDE:
			for x in SPLASH_SIDE:
				if absf(Vector2(x, y).distance_to(centre) - radius) < 0.5:
					image.set_pixel(frame * SPLASH_SIDE + x, y, Color(color.r, color.g, color.b, alpha))
	return image


# The END OF TURN row's icon: three slanted streaks and a drop on a board-icon canvas. A placeholder.
static func icon() -> Texture2D:
	if _icon == null:
		var canvas := Image.create_empty(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
		var ink := Color(0.62, 0.78, 1.0)
		var shade := Color(0.36, 0.5, 0.82)
		for start: Vector2i in [Vector2i(4, 1), Vector2i(9, 0), Vector2i(13, 3)]:
			for step in 5:
				var at := start + Vector2i(-(step >> 1), step)
				if at.x >= 0 and at.y < ICON_SIZE:
					canvas.set_pixelv(at, ink if step < 4 else shade)
		for at: Vector2i in [Vector2i(7, 10), Vector2i(6, 11), Vector2i(7, 11), Vector2i(8, 11),
				Vector2i(6, 12), Vector2i(7, 12), Vector2i(8, 12), Vector2i(7, 13)]:
			canvas.set_pixelv(at, ink)
		canvas.set_pixelv(Vector2i(8, 12), shade)
		_icon = ImageTexture.create_from_image(canvas)
	return _icon
