extends Object
class_name StatusArt

# WHERE an element state goes on a unit's art (#358): the one scan the status shader reads, so the
# shader stays a renderer and every rule about the art is ordinary arithmetic a headless case can
# state. One EFFECT MAP per sampled image, the same size as it, read with the same UV:
#
#   R  rime -- 1 on a top-facing opaque texel, RIME_SIDE on a side edge in the upper body
#   G  icicle depth k / ICICLE_SCALE on a TRANSPARENT texel k rows under an overhang
#   B  ink-height fraction of an opaque texel, 0 at the head and 1 at the feet (the sheen band)
#   A  ink-width fraction of an opaque texel, 0 at the left edge (the band's slant)
#
# An OVERHANG is an opaque texel with transparency under it. The ones icicles hang from are also
# where slice 2's drips will fall from -- `overhangs` is that one answer, so Chilled's icicles and
# Wet's drops can never disagree about where the body drips.
#
# Icicle LENGTH is deliberately not baked in: the map carries every free row under a chosen overhang
# and the shader clips against the knobs, so no knob can leave a stale map in this cache.

const OPAQUE := 0.5              # BoardMirror.opaque_bounds' threshold: one rule for "is this ink"
const ICICLE_SCALE := 8.0        # G = k / ICICLE_SCALE, so k survives 8-bit storage exactly
const MAX_ICICLE_TEXELS := 6
const MAX_ICICLES := 5
const MIN_FREE_ROWS := 2         # an overhang with less room under it than this hangs nothing
const RIME_SIDE := 0.35
const RIME_SIDE_REACH := 0.7     # side-edge rime stops this far down the body


class Map extends RefCounted:
	var image: Image
	var texture: ImageTexture
	# The overhang texel of every icicle column, left to right.
	var overhangs: Array[Vector2i] = []


static var _cache: Dictionary[String, Map] = {}


# The map for whatever image this texture's UVs actually index. A Sprite3D draws an AtlasTexture
# frame with UVs into the atlas's PARENT sheet (BoardOverlays measured the same fact for quads), so
# the map is built for the parent and the frame's own region needs no handling here.
static func map_for(art: Texture2D) -> Map:
	var sampled := sampled_texture(art)
	if sampled == null:
		return null
	var key := sampled.resource_path
	if key.is_empty():
		key = str(sampled.get_instance_id())
	if not _cache.has(key):
		var image := sampled.get_image()
		if image == null:
			return null
		if image.is_compressed():
			image = image.duplicate()
			image.decompress()
		_cache[key] = build(image)
	return _cache[key]


static func sampled_texture(art: Texture2D) -> Texture2D:
	var sampled := art
	var atlas := sampled as AtlasTexture
	while atlas != null and atlas.atlas != null:
		sampled = atlas.atlas
		atlas = sampled as AtlasTexture
	return sampled


static func build(image: Image) -> Map:
	var map := Map.new()
	var size := image.get_size()
	var out := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var ink := BoardMirror.opaque_bounds(image, Rect2i(Vector2i.ZERO, size))
	var top := ink.position.y
	var bottom := ink.end.y - 1
	var left := ink.position.x
	var right := ink.end.x - 1
	var tall := float(maxi(1, bottom - top))
	var wide := float(maxi(1, right - left))
	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			if not _opaque(image, x, y):
				continue
			var down := float(y - top) / tall
			var rime := 0.0
			if not _opaque(image, x, y - 1):
				rime = 1.0
			elif down < RIME_SIDE_REACH and (not _opaque(image, x - 1, y) or not _opaque(image, x + 1, y)):
				rime = RIME_SIDE
			out.set_pixel(x, y, Color(rime, 0.0, down, float(x - left) / wide))
	for hang: Vector2i in _icicle_overhangs(image, top, bottom, left, right):
		map.overhangs.append(hang)
		var k := 1
		while k <= MAX_ICICLE_TEXELS and _hangs_free(image, hang.x, hang.y + k, bottom):
			out.set_pixel(hang.x, hang.y + k, Color(0.0, float(k) / ICICLE_SCALE, 0.0, 0.0))
			k += 1
	map.image = out
	map.texture = ImageTexture.create_from_image(out)
	return map


# Which overhangs wear an icicle: per column, the one with the most room under it; then columns in
# the order of a fixed hash, never two side by side, at most MAX_ICICLES. Deterministic per image,
# so the same art always hangs the same icicles.
static func _icicle_overhangs(image: Image, top: int, bottom: int, left: int, right: int) -> Array[Vector2i]:
	var best: Dictionary[int, Vector2i] = {}
	var room: Dictionary[int, int] = {}
	for x in range(left, right + 1):
		for y in range(top, bottom):
			if not _opaque(image, x, y) or _opaque(image, x, y + 1):
				continue
			var free := 0
			while free < MAX_ICICLE_TEXELS and _hangs_free(image, x, y + free + 1, bottom):
				free += 1
			var had: int = room.get(x, 0)
			if free >= MIN_FREE_ROWS and free > had:
				room[x] = free
				best[x] = Vector2i(x, y)
	var columns: Array[int] = []
	columns.assign(best.keys())
	columns.sort_custom(func(a: int, b: int) -> bool:
		return _column_hash(a) < _column_hash(b) or (_column_hash(a) == _column_hash(b) and a < b))
	var chosen: Array[int] = []
	for x in columns:
		if chosen.size() >= MAX_ICICLES:
			break
		if chosen.has(x - 1) or chosen.has(x + 1):
			continue
		chosen.append(x)
	chosen.sort()
	var hangs: Array[Vector2i] = []
	for x in chosen:
		hangs.append(best[x])
	return hangs


# A texel an icicle may occupy: transparent, and strictly above the feet row.
static func _hangs_free(image: Image, x: int, y: int, bottom: int) -> bool:
	return y < bottom and not _opaque(image, x, y)


static func _opaque(image: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return false
	return image.get_pixel(x, y).a >= OPAQUE


static func _column_hash(x: int) -> float:
	var n := (x * 374761393 + 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0
