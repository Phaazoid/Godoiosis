extends Object
class_name SnowCapArt

# The snow that settles on a BILLBOARD prop (#1269) -- a tree, a lantern -- which a decal cannot reach,
# its faces standing upright. One overlay texture per prop art, the art's own size: the snow colour
# (white, tinted by the overlay's modulate) on every top edge of the art and the texel under it, and
# clear elsewhere. BoardMirror lays it over the prop as a second sprite.
#
# A top edge is StatusArt.is_top_edge, the rime's own rule. It is asked of the FRAME, cropped out of
# its sheet, because a tile's neighbour in a packed tileset is not air: asked of the sheet, a tree
# under an opaque tile would wear no cap.
#
# Pure and static; cached per frame for the process, since every cell of one tile shows the same art.

# How far below a top edge the snow reaches, in art pixels, and how much the lower row is shaded.
const DEPTH := 2
const UNDER_SHADE := 0.82

static var _caps_by_frame: Dictionary[String, Texture2D] = {}


# The cap overlay for this art, or null when it has none to draw.
static func cap_for(art: Texture2D) -> Texture2D:
	if art == null:
		return null
	var sampled := StatusArt.sampled_texture(art)
	if sampled == null:
		return null
	var frame := Rect2i(StatusArt.frame_of(art))
	var sheet := sampled.resource_path if not sampled.resource_path.is_empty() else str(sampled.get_instance_id())
	var key := "%s|%s" % [sheet, frame]
	if not _caps_by_frame.has(key):
		var image := sampled.get_image()
		if image == null:
			return null
		if image.is_compressed():
			image = image.duplicate()
			image.decompress()
		var cap := build(image.get_region(frame))
		var texture: Texture2D = null
		if not cap.is_invisible():
			texture = ImageTexture.create_from_image(cap)
		_caps_by_frame[key] = texture
	return _caps_by_frame[key]


# The cap over one frame's own pixels.
static func build(art: Image) -> Image:
	var size := art.get_size()
	var out := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var under := Color(UNDER_SHADE, UNDER_SHADE, UNDER_SHADE + (1.0 - UNDER_SHADE) * 0.6, 1.0)
	for y in size.y:
		for x in size.x:
			if not StatusArt.is_top_edge(art, x, y):
				continue
			out.set_pixel(x, y, Color.WHITE)
			for k in range(1, DEPTH):
				if y + k < size.y and art.get_pixel(x, y + k).a >= StatusArt.OPAQUE \
						and out.get_pixel(x, y + k).a <= 0.0:
					out.set_pixel(x, y + k, under)
	return out
