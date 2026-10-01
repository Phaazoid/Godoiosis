extends Object
class_name GasPuffArt

# The pixel art the puff style draws (#508's look harness), generated from each GasLook's palette and
# shape rather than drawn, so a palette tune shows the moment the art is rebuilt. Ported from round 4's
# probe. A sprite sheet replaces it once a style is picked.
#
# One Texture2DArray holds every kind's drawings, STRIDE layers a kind: three sizes x three variants
# of its puff, then its extra's frames. Each is drawn bottom-centred on one LAYER_SIZE canvas, so every
# quad stands on its own feet whichever drawing it shows.

const LAYER_SIZE := Vector2i(40, 32)
const STRIDE := 16
const EXTRA_BASE := 9

# Width x height of the three puff sizes, per shape.
const SIZES := {
	GasLook.PuffShape.CUMULUS: [Vector2i(18, 11), Vector2i(26, 15), Vector2i(34, 19)],
	GasLook.PuffShape.PLUME: [Vector2i(20, 17), Vector2i(28, 23), Vector2i(36, 29)],
	GasLook.PuffShape.MOUND: [Vector2i(22, 10), Vector2i(30, 13), Vector2i(38, 16)],
	GasLook.PuffShape.STRATUS: [Vector2i(24, 8), Vector2i(32, 10), Vector2i(40, 12)],
	GasLook.PuffShape.STORM: [Vector2i(20, 17), Vector2i(28, 23), Vector2i(36, 29)],
	GasLook.PuffShape.CURL: [Vector2i(18, 12), Vector2i(26, 16), Vector2i(34, 20)],
}


static func layer_of_puff(kind: Gas.Kind, size: int, variant: int) -> int:
	return int(kind) * STRIDE + size * 3 + variant


static func layer_of_extra(kind: Gas.Kind, frame: int) -> int:
	return int(kind) * STRIDE + EXTRA_BASE + frame


static func build() -> Texture2DArray:
	var layers: Array[Image] = []
	for kind: Gas.Kind in Gas.Kind.values():
		var look := GasLook.for_kind(kind)
		var drawings: Array[Image] = []
		var sizes: Array = SIZES[look.puff_shape]
		var name_length := Gas.name_of(kind).length()
		for s in sizes.size():
			for v in 3:
				drawings.append(puff_image(look.puff_shape, s * 10 + v + 7 + name_length * 31, sizes[s],
					look.palette(), look.soft))
		drawings.append_array(extra_frames(look.extra, look.palette()))
		for i in STRIDE:
			layers.append(_on_canvas(drawings[i] if i < drawings.size() else null))
	var array := Texture2DArray.new()
	array.create_from_images(layers)
	return array


# A drawing placed bottom-centred on the shared canvas; a puff's feet are its quad's origin.
static func _on_canvas(drawing: Image) -> Image:
	var canvas := Image.create_empty(LAYER_SIZE.x, LAYER_SIZE.y, false, Image.FORMAT_RGBA8)
	if drawing == null:
		return canvas
	drawing.convert(Image.FORMAT_RGBA8)
	var at := Vector2i((LAYER_SIZE.x - drawing.get_width()) / 2, LAYER_SIZE.y - drawing.get_height())
	canvas.blit_rect(drawing, Rect2i(Vector2i.ZERO, drawing.get_size()), at)
	return canvas


# A cluster of lumps (x, y, r in pixels; squash flattens them), three flat tones lit from the upper
# left, then an ink outline -- or, soft, a dithered fringe instead, so a dark gas reads as something
# to see through rather than a stone. `swirl` scratches a curl into the body.
static func blob(lumps: Array, size: Vector2i, pal: Array[Color], squash: float, swirl: bool,
		soft := false) -> Image:
	var w := size.x
	var h := size.y
	var light := Vector3(-0.45, -0.65, 0.6).normalized()
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var inside := PackedByteArray()
	inside.resize(w * h)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var best := 0.0
			var n := Vector3.ZERO
			for lump: Vector3 in lumps:
				var d := Vector2(p.x - lump.x, (p.y - lump.y) / squash)
				var k := 1.0 - d.length() / lump.z
				if k > best:
					best = k
					var q := d / lump.z
					n = Vector3(q.x, q.y, sqrt(maxf(0.0, 1.0 - q.length_squared())))
			if best <= 0.0:
				continue
			inside[y * w + x] = 1
			var lam := n.dot(light)
			var col: Color = pal[0] if lam > 0.55 else (pal[1] if lam > 0.12 else pal[2])
			if soft:
				col = pal[0] if lam > 0.62 else (pal[1] if lam > -0.3 else pal[2])
			img.set_pixel(x, y, col)
	if swirl:
		var c := Vector2(w * 0.5, h * 0.55)
		for i in 40:
			var a := float(i) * 0.33
			var r := 0.6 + float(i) * 0.12
			var q := Vector2i(c + Vector2(cos(a), sin(a) * 0.8) * r)
			if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and inside[q.y * w + q.x] == 1:
				img.set_pixel(q.x, q.y, pal[2])
	if not soft:
		for y in h:
			for x in w:
				if inside[y * w + x] == 1:
					continue
				for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q := Vector2i(x, y) + o
					if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and inside[q.y * w + q.x] == 1:
						img.set_pixel(x, y, pal[3])
						break
		return img
	var ring := PackedByteArray()
	ring.resize(w * h)
	for y in h:
		for x in w:
			if inside[y * w + x] == 0:
				continue
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x, y) + o
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or inside[q.y * w + q.x] == 0:
					ring[y * w + x] = 1
					break
	for y in h:
		for x in w:
			if ring[y * w + x] == 1:
				img.set_pixel(x, y, Color(0, 0, 0, 0) if (x + y) % 2 == 0 else pal[2])
	return img


# One puff drawing: the shape decides the lumps, the seed their wobble.
static func puff_image(shape: GasLook.PuffShape, seed: int, size: Vector2i, pal: Array[Color], soft := false) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var w := float(size.x)
	var h := float(size.y)
	match shape:
		GasLook.PuffShape.PLUME:
			# Narrow at the foot, widest in the middle, two lumps on top: a column, not a boulder.
			var r := w * 0.2
			return blob([Vector3(w * 0.4, h - r * 0.8 - 1.0, r * 0.75), Vector3(w * 0.62, h - r * 0.8 - 1.0, r * 0.7),
				Vector3(w * 0.2, h * 0.52, r * rng.randf_range(0.85, 1.0)),
				Vector3(w * 0.5, h * 0.48, r * rng.randf_range(1.0, 1.15)),
				Vector3(w * 0.8, h * 0.54, r * rng.randf_range(0.8, 0.95)),
				Vector3(w * rng.randf_range(0.3, 0.42), r * 1.1, r * rng.randf_range(0.8, 0.95)),
				Vector3(w * rng.randf_range(0.58, 0.7), r * 1.3, r * rng.randf_range(0.7, 0.85))],
				size, pal, 1.0, false, soft)
		GasLook.PuffShape.MOUND:
			# Low heavy mounds that hug the ground.
			var r := h * 0.55
			return blob([Vector3(w * 0.22, h - r * 0.72 - 1.0, r * rng.randf_range(0.85, 1.0)),
				Vector3(w * 0.5, h - r * 0.72 - 1.0, r * rng.randf_range(0.95, 1.1)),
				Vector3(w * 0.78, h - r * 0.72 - 1.0, r * rng.randf_range(0.8, 0.95)),
				Vector3(w * rng.randf_range(0.35, 0.65), h - r * 1.25 - 1.0, r * 0.8)], size, pal, 0.72, false, soft)
		GasLook.PuffShape.STRATUS:
			var r := h * 0.7
			var lumps: Array = []
			for i in 5:
				lumps.append(Vector3(w * (0.12 + 0.19 * i), h - r * 0.45 - 1.0 - (1.5 if i % 2 == 1 else 0.0),
					r * rng.randf_range(0.75, 0.95)))
			return blob(lumps, size, pal, 0.42, false, soft)
		GasLook.PuffShape.STORM:
			# A thunderhead: tall, scalloped all round, darker than a cloud should be.
			var r := h * 0.24
			var lumps: Array = []
			for i in 4:
				lumps.append(Vector3(w * (0.17 + 0.22 * i), h - r - 1.5, r * rng.randf_range(0.8, 0.95)))
			for i in 3:
				lumps.append(Vector3(w * (0.28 + 0.22 * i), h * 0.5, r * rng.randf_range(1.0, 1.15)))
			lumps.append(Vector3(w * 0.4, r * 1.2, r * rng.randf_range(0.85, 1.0)))
			lumps.append(Vector3(w * 0.62, r * 1.35, r * rng.randf_range(0.8, 0.95)))
			return blob(lumps, size, pal, 1.0, false, soft)
		GasLook.PuffShape.CURL:
			var r := h * 0.36
			return blob([Vector3(w * 0.22, h - r - 1.5, r * 0.9), Vector3(w * 0.5, h - r - 1.5, r * 1.05),
				Vector3(w * 0.78, h - r - 1.5, r * 0.85),
				Vector3(w * rng.randf_range(0.4, 0.6), h - r * 1.6, r * rng.randf_range(0.8, 0.95))],
				size, pal, 1.0, true, soft)
	var r := h * 0.36
	return blob([Vector3(w * 0.22, h - r - 1.5, r * 0.9),
		Vector3(w * 0.50, h - r - 1.5, r * rng.randf_range(0.95, 1.1)),
		Vector3(w * 0.78, h - r - 1.5, r * rng.randf_range(0.8, 0.95)),
		Vector3(w * rng.randf_range(0.35, 0.65), h - r * 1.6 - 1.0, r * rng.randf_range(0.8, 1.0))],
		size, pal, 1.0, false, soft)


# The little extra that moves above a cell: each gas's own tell.
static func extra_frames(extra: GasLook.Extra, pal: Array[Color]) -> Array[Image]:
	var out: Array[Image] = []
	match extra:
		GasLook.Extra.WISP:
			out.append(blob([Vector3(4.5, 6.5, 3.2), Vector3(9.5, 6.5, 3.0), Vector3(7, 4, 3.2)], Vector2i(14, 10), pal, 1.0, false))
			out.append(blob([Vector3(3.5, 4.5, 2.4), Vector3(6.5, 3.5, 2.4)], Vector2i(10, 7), pal, 1.0, false))
		GasLook.Extra.SOOT:
			var img := Image.create_empty(3, 3, false, Image.FORMAT_RGBA8)
			img.fill_rect(Rect2i(0, 0, 2, 2), pal[3])
			img.set_pixel(1, 1, pal[2])
			out.append(img)
		GasLook.Extra.BUBBLE:
			var b := Image.create_empty(7, 7, false, Image.FORMAT_RGBA8)
			for y in 7:
				for x in 7:
					var d := Vector2(x + 0.5 - 3.5, y + 0.5 - 3.5).length()
					if d < 3.4 and d > 2.2:
						b.set_pixel(x, y, pal[3])
					elif d <= 2.2:
						b.set_pixel(x, y, pal[1])
			b.set_pixel(2, 2, pal[0])
			b.set_pixel(3, 2, pal[0])
			out.append(b)
			var pop := Image.create_empty(7, 7, false, Image.FORMAT_RGBA8)
			for p: Vector2i in [Vector2i(3, 0), Vector2i(3, 6), Vector2i(0, 3), Vector2i(6, 3), Vector2i(1, 1),
					Vector2i(5, 1), Vector2i(1, 5), Vector2i(5, 5)]:
				pop.set_pixel(p.x, p.y, pal[0])
			out.append(pop)
		GasLook.Extra.SNOW:
			var s := Image.create_empty(5, 5, false, Image.FORMAT_RGBA8)
			for p: Vector2i in [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 3), Vector2i(2, 4), Vector2i(0, 2),
					Vector2i(1, 2), Vector2i(3, 2), Vector2i(4, 2)]:
				s.set_pixel(p.x, p.y, pal[0])
			s.set_pixel(2, 2, Color(1, 1, 1))
			for p: Vector2i in [Vector2i(1, 1), Vector2i(3, 1), Vector2i(1, 3), Vector2i(3, 3)]:
				s.set_pixel(p.x, p.y, pal[3])
			out.append(s)
		GasLook.Extra.BOLT:
			var bolt := Image.create_empty(9, 20, false, Image.FORMAT_RGBA8)
			var path: Array[Vector2i] = [Vector2i(5, 0), Vector2i(3, 6), Vector2i(6, 7), Vector2i(2, 14),
				Vector2i(5, 14), Vector2i(3, 19)]
			var core := Color(1.0, 0.98, 0.8)
			var glow := Color(1.0, 0.86, 0.3)
			for i in path.size() - 1:
				var a := Vector2(path[i])
				var b2 := Vector2(path[i + 1])
				for k in 24:
					var q := Vector2i(a.lerp(b2, k / 23.0).round())
					for o: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0)]:
						var qq := q + o
						if qq.x >= 0 and qq.x < 9 and bolt.get_pixel(qq.x, qq.y).a == 0.0:
							bolt.set_pixel(qq.x, qq.y, glow)
					bolt.set_pixel(q.x, q.y, core)
			out.append(bolt)
		GasLook.Extra.CURL:
			var base := Image.create_empty(9, 9, false, Image.FORMAT_RGBA8)
			for i in 26:
				var a := float(i) * 0.42
				var r := 0.4 + float(i) * 0.15
				var q := Vector2i(Vector2(4.5, 4.5) + Vector2(cos(a), sin(a)) * r)
				if q.x >= 0 and q.y >= 0 and q.x < 9 and q.y < 9:
					base.set_pixel(q.x, q.y, pal[1] if i < 18 else pal[2])
			for k in 4:
				var f := base.duplicate() as Image
				for j in k:
					f.rotate_90(CLOCKWISE)
				out.append(f)
	return out
