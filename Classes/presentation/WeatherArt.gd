extends Object
class_name WeatherArt

# The pixel art the weather draws (#1260), generated rather than drawn: a rain streak, a splash ring's
# frames, a snowflake's two frames (#1269), the fog's wisps and its drifting noise (#1285), the wind's
# blown specks (#1286), and the queue row's icon. GasPuffArt's shape -- a tune shows the moment the art
# is rebuilt, and a sheet replaces any of it once someone draws one. The icon, the wisps and the specks
# especially are PLACEHOLDERS.
#
# Pure and static: every function returns a fresh Image or a cached texture, and nothing reads a node.

const ICON_SIZE := GridUtils.TILE_SIZE
# How many frames a splash ring plays, and the square each is drawn in, in art pixels.
const SPLASH_FRAMES := 4
const SPLASH_SIDE := 9
# The square a snowflake's frame is drawn in, in art pixels: room for the big flake's plus.
const FLAKE_SIDE := 3
# A fog wisp's frame, in GROUND art pixels (BoardOverlays.ART_PIXELS_PER_CELL a cell), and how many.
const WISP_SIZE := Vector2i(44, 14)
const WISP_FRAMES := 3
# The fog's breakup and bank noise: one seamless tile, this many pixels a side.
const FOG_NOISE_SIDE := 256
# A blown speck's frame (#1286), in art pixels: the leaves' tumble, then the dust motes.
const SPECK_SIDE := 5
const LEAF_FRAMES := 4
const DUST_FRAMES := 2

static var _icon: Texture2D = null
static var _fog_noise: Texture2D = null


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


# A snowflake's two frames side by side, each FLAKE_SIDE square: one art pixel, and a plus whose
# arms are a shade fainter than its heart. The quad is one frame wide, so a flake keeps the sprites'
# density whatever that is tuned to.
static func flakes(color: Color) -> Image:
	var image := Image.create_empty(FLAKE_SIDE * 2, FLAKE_SIDE, false, Image.FORMAT_RGBA8)
	var mid := FLAKE_SIDE >> 1
	image.set_pixel(mid, mid, color)
	image.set_pixel(FLAKE_SIDE + mid, mid, color)
	var arm := Color(color.r, color.g, color.b, color.a * 0.75)
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		image.set_pixel(FLAKE_SIDE + mid + step.x, mid + step.y, arm)
	return image


# The fog's wisps (#1285): WISP_FRAMES frames side by side, each WISP_SIZE, white with its opacity in
# three steps -- a soft oval broken by noise, so each frame reads as a different scrap of fog. The draw
# shader tints it and fades it.
static func fog_wisps() -> Image:
	var w := WISP_SIZE.x
	var h := WISP_SIZE.y
	var image := Image.create_empty(w * WISP_FRAMES, h, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.11
	var seeds: Array[int] = [11, 23, 37]   # the three the dev picked from, on 2026-10-09's renders
	for frame in WISP_FRAMES:
		noise.seed = seeds[frame % seeds.size()]
		for y in h:
			for x in w:
				var nx := (x + 0.5 - w * 0.5) / (w * 0.5)
				var ny := (y + 0.5 - h * 0.6) / (h * 0.5)
				var a := clampf((1.0 - (nx * nx + ny * ny)) * 1.2 + noise.get_noise_2d(x, y) * 0.7, 0.0, 1.0)
				a = floorf(a * 3.0 + 0.5) / 3.0
				image.set_pixel(frame * w + x, y, Color(1.0, 1.0, 1.0, a))
	return image


# The wind's blown specks (#1286): LEAF_FRAMES frames of a leaf tumbling end over end, then DUST_FRAMES
# motes, side by side, each SPECK_SIDE square. White with the leaf's turned-away side shaded; the draw
# shader tints a leaf and a mote each their own colour. PLACEHOLDERS.
static func specks() -> Image:
	var image := Image.create_empty(SPECK_SIDE * (LEAF_FRAMES + DUST_FRAMES), SPECK_SIDE, false,
			Image.FORMAT_RGBA8)
	var lit := Color.WHITE
	var shade := Color(0.72, 0.72, 0.72)
	# Each frame: [the leaf's lit pixels, its shaded pixels].
	var frames: Array = [
		[[Vector2i(2, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(1, 3), Vector2i(2, 3)],
			[Vector2i(0, 4)]],
		[[Vector2i(3, 1), Vector2i(2, 2), Vector2i(3, 2), Vector2i(1, 3), Vector2i(2, 3)], [Vector2i(1, 4)]],
		[[], [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]],
		[[], [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3),
			Vector2i(3, 3), Vector2i(4, 4)]],
	]
	for i in frames.size():
		var origin := Vector2i(SPECK_SIDE * i, 0)
		for p: Vector2i in frames[i][0]:
			image.set_pixelv(origin + p, lit)
		for p: Vector2i in frames[i][1]:
			image.set_pixelv(origin + p, shade)
	var mid := SPECK_SIDE >> 1
	var dust := Vector2i(SPECK_SIDE * LEAF_FRAMES, 0)
	image.set_pixelv(dust + Vector2i(mid, mid), lit)
	image.set_pixelv(dust + Vector2i(SPECK_SIDE + mid, mid), lit)
	image.set_pixelv(dust + Vector2i(SPECK_SIDE + mid + 1, mid + 1), shade)
	return image


# The fog's noise (#1285), one seamless tile, cached for the process: the breakup and the banks both
# read it, at their own scales. The wind's cloud shadows (#1286) read it too, at a larger one.
static func fog_noise() -> Texture2D:
	if _fog_noise == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.015
		noise.fractal_octaves = 3
		noise.seed = 1285
		_fog_noise = ImageTexture.create_from_image(noise.get_seamless_image(FOG_NOISE_SIDE, FOG_NOISE_SIDE))
	return _fog_noise


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
