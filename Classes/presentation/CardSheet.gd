class_name CardSheet
extends Object

# What a CARD-FORMAT spritesheet says, read out of the pixels (#629). Static and pure: it is handed
# an Image and answers with frames, durations and animation boundaries, touching no file and no
# scene. `tools/zoomanim/gen_zoom_animations.gd` is the CLI that writes the artifacts; this is the
# rule -- AttackLint's shape, and for AttackLint's reason: the rule is worth exercising against a
# sheet a TEST draws, which a SceneTree script full of ResourceSaver calls could never be.
#
# A card-format sheet lays every frame in a fixed-size rectangle of one flat colour, prints the
# frame's duration above it, and prints the animation's name to the left of the row it starts on.
# The Sage sheet is one. The project's three other GBA rips are not, and carry neither timing nor
# registration, so nothing here applies to them.
#
# THE CARD IS A VIEWPORT, NOT A CROP, and that is the whole reason a frame's rect is always the
# entire card and never the ink inside it: where the sprite sits within its card IS the per-frame
# offset -- the animation's own footwork. Trimming to content throws that away, and the result plays
# back as a jitter rather than a step.


# How far above a card its duration label may sit. Generous on purpose: a label drifting further
# than this is unreadable, and refusing is the wanted outcome.
const LABEL_LOOKUP := 24

# Below this, a card-coloured region is a pocket enclosed by the sprite -- the gap between cape and
# body -- rather than a card. What a card IS is decided by the modal size, so this only trims noise.
const MIN_COMPONENT := 8

# GBA frames, matched as whole labels against the sheet's own printed digits. Whole labels rather
# than per-digit templates because the digits TOUCH: every two-digit label on the Sage is a single
# connected run, so there is no column gap to segment on.
#
# The 1/3 pair is the one that could have gone wrong. At 10x the second digit of `13` reads equally
# well as a 5, and 13 vs 15 is a silent two-frame error on eight cards. It was settled against the
# sheet's OWN text: the sheet prints "go to Attack frame 3", and that glyph is pixel-identical to
# this one. Cross-check -- this table predicts 24 cards at 8 and 8 at 60, which is exactly what the
# row structure gives independently.
const DURATION_GLYPHS: Array = [
	[8, ["..###...", ".#####..", "#######.", "#######.", ".#####..",
		".######.", "########", "#######.", ".#####..", "..###..."]],
	[6, ["...###..", "..#####.", ".#####..", ".#####..", "#######.",
		"########", "########", "#######.", ".#####..", "..###..."]],
	[60, ["...###....###..", "..#####..#####.", ".#####..#######", ".#####.########",
		"###############", "###############", "###############", "##############.",
		".#####..#####..", "..###....###..."]],
	[13, ["....#....#####.", "..####..#######", ".#####.#######.", "..####..#.###..",
		"..####...#####.", "..####...######", "..####..#######", ".#############.",
		"#############..", ".######..###..."]],
	[4, [".....#..", "....###.", "...####.", "..#####.", ".######.",
		"########", "#######.", ".######.", "..######", "...####."]],
	[20, ["..####....###..", ".######..#####.", "###############", "###.###########",
		".#..###########", "...###.########", "..###.#########", ".#############.",
		"#############..", ".######..###..."]],
	[11, ["....#......#...", "..####...####..", ".#####..#####..", "..####...####..",
		"..####...####..", "..####...####..", "..####...####..", ".######.######.",
		"###############", ".######.######."]],
	[18, ["....#....###...", "..####..#####..", ".#####.#######.", "..####.#######.",
		"..####..#####..", "..####..######.", "..####.########", ".#############.",
		"#############..", ".######..###..."]],
]


# Read `region` of `source` as N animations named by `names`, in reading order.
#
# Returns {"animations": [{name, cards: Array[Rect2i], durations: Array[int]}], "card": int,
# "page": int, "notes": Array[String], "errors": Array[String]}. A non-empty `errors` means
# nothing may be written -- every failure here is one that would otherwise ship silently wrong.
static func read(source: Image, region_wanted: Rect2i, names: Array) -> Dictionary:
	# Arrays rather than PackedStringArrays, and NOT a style choice: a Packed*Array is a VALUE type,
	# so appending through `out["errors"]` would append to a copy and every refusal would vanish
	# silently -- which is the one failure mode this whole seam exists to prevent.
	var notes: Array[String] = []
	var errors: Array[String] = []
	var out := {
		"animations": [], "card": -1, "page": -1, "notes": notes, "errors": errors,
	}
	var region: Rect2i = region_wanted.intersection(Rect2i(Vector2i.ZERO, source.get_size()))
	var page: int = source.get_pixel(0, 0).to_rgba32()
	out["page"] = page

	var card := card_colour(source, page)
	if card < 0:
		errors.append(
				"no colour wins by a clear enough margin to be the card colour")
		return out
	out["card"] = card

	var found := components(source, card, region)
	var cards := modal_sized(found)
	if cards.is_empty():
		errors.append("no cards found -- is the region right?")
		return out
	if found.size() > cards.size():
		notes.append(
				"ignored %d card-coloured regions that are not card sized (pockets enclosed by the sprite)"
				% (found.size() - cards.size()))
	var stray := outside(source, card, region)
	if stray > 0:
		notes.append(
				"%d card-coloured px lie OUTSIDE the region and were not read (the sheet's other palette blocks and its credit box)"
				% stray)

	var animations: Array = []
	for row: Array in rows(cards):
		var first: Rect2i = row[0]
		if animations.is_empty() or has_name_label(source, page, card, first, region):
			animations.append({"name": "", "cards": [], "durations": []})
		var current: Dictionary = animations[-1]
		for c: Rect2i in row:
			var duration := duration_of(source, page, card, c)
			if duration <= 0:
				errors.append(
						"unreadable duration label over the card at %s" % c.position)
				return out
			(current["cards"] as Array).append(c)
			(current["durations"] as Array).append(duration)

	if animations.size() != names.size():
		errors.append(
				"found %d animations but %d names were given (%s)"
				% [animations.size(), names.size(), ", ".join(PackedStringArray(names))])
		return out
	for i in animations.size():
		animations[i]["name"] = names[i]
	out["animations"] = animations
	return out


# The most common colour that is not the page. Refused unless it wins by a clear margin -- on a
# sheet where it does not, this is about to answer with a SPRITE colour and everything downstream
# would be nonsense built on it.
static func card_colour(img: Image, page: int) -> int:
	var hist: Dictionary = {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y).to_rgba32()
			if c != page:
				hist[c] = int(hist.get(c, 0)) + 1
	var best := -1
	var best_n := 0
	var second_n := 0
	for k: int in hist:
		var n := int(hist[k])
		if n > best_n:
			second_n = best_n
			best_n = n
			best = k
		elif n > second_n:
			second_n = n
	return best if best_n >= second_n * 3 else -1


# Connected regions of the card colour.
#
# By CARD COLOUR rather than "not the page colour", and that is the difference between working and
# not: a sprite may overhang its card into the gutter, and a not-the-page scan then welds it to its
# neighbour -- measured on the Sage as a 136px run where two 66px cards should be. Overhanging
# SPRITE pixels are not CARD pixels, so this cannot be fooled that way.
static func components(img: Image, card: int, region: Rect2i) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var seen: Dictionary = {}
	var stride := img.get_width()
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if seen.has(y * stride + x) or img.get_pixel(x, y).to_rgba32() != card:
				continue
			var lo := Vector2i(x, y)
			var hi := lo
			var stack: Array[Vector2i] = [lo]
			seen[y * stride + x] = true
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				lo = lo.min(p)
				hi = hi.max(p)
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = p + d
					if not region.has_point(q):
						continue
					if seen.has(q.y * stride + q.x) or img.get_pixel(q.x, q.y).to_rgba32() != card:
						continue
					seen[q.y * stride + q.x] = true
					stack.append(q)
			var r := Rect2i(lo, hi - lo + Vector2i.ONE)
			if r.size.x >= MIN_COMPONENT and r.size.y >= MIN_COMPONENT:
				out.append(r)
	return out


# What a card IS, measured rather than declared: the size the most regions share.
static func modal_sized(found: Array[Rect2i]) -> Array[Rect2i]:
	var tally: Dictionary = {}
	for r: Rect2i in found:
		tally[r.size] = int(tally.get(r.size, 0)) + 1
	var best := Vector2i.ZERO
	var best_n := 0
	for k: Vector2i in tally:
		if int(tally[k]) > best_n:
			best_n = int(tally[k])
			best = k
	var out: Array[Rect2i] = []
	for r: Rect2i in found:
		if r.size == best:
			out.append(r)
	return out


static func outside(img: Image, card: int, region: Rect2i) -> int:
	if region.encloses(Rect2i(Vector2i.ZERO, img.get_size())):
		return 0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if not region.has_point(Vector2i(x, y)) and img.get_pixel(x, y).to_rgba32() == card:
				n += 1
	return n


# Cards grouped into rows, each row left-to-right, the rows top-to-bottom. Reading order.
static func rows(cards: Array[Rect2i]) -> Array:
	var by_y: Dictionary = {}
	for r: Rect2i in cards:
		var row: Array = by_y.get(r.position.y, [])
		row.append(r)
		by_y[r.position.y] = row
	var keys: Array = by_y.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		var row: Array = by_y[k]
		row.sort_custom(func(a: Rect2i, b: Rect2i): return a.position.x < b.position.x)
		out.append(row)
	return out


# Does this row START an animation? A row that does has the animation's name printed to its LEFT; a
# continuation row has nothing there. That is the sheet's own structure, not a guess about how big
# the vertical gap between animations is -- the Sage's Attack wraps over three rows and its Crit
# over two, and both split correctly on it.
static func has_name_label(img: Image, page: int, card: int, first: Rect2i, region: Rect2i) -> bool:
	for y in range(first.position.y, first.end.y):
		for x in range(region.position.x, first.position.x):
			var c := img.get_pixel(x, y).to_rgba32()
			if c != page and c != card:
				return true
	return false


# The duration printed above a card, in GBA frames. 0 = unreadable, which callers must treat as a
# hard failure: a wrong duration is invisible in the output and shows up only as bad feel weeks
# later, where a refusal names the card and is fixed in a minute.
static func duration_of(img: Image, page: int, card: int, c: Rect2i) -> int:
	var mask := label_mask(img, page, card, c)
	if mask.is_empty():
		return 0
	for entry: Array in DURATION_GLYPHS:
		if PackedStringArray(entry[1]) == mask:
			return entry[0]
	return 0


# The ink above a card, as rows of "#" and ".". Public so a failure can print what it could not read.
static func label_mask(img: Image, page: int, card: int, c: Rect2i) -> PackedStringArray:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for y in range(maxi(0, c.position.y - LABEL_LOOKUP), c.position.y):
		for x in range(c.position.x, c.end.x):
			var p := img.get_pixel(x, y).to_rgba32()
			if p == page or p == card:
				continue
			lo = lo.min(Vector2i(x, y))
			hi = hi.max(Vector2i(x, y))
	if hi.x < 0:
		return PackedStringArray()
	var mask: PackedStringArray = []
	for y in range(lo.y, hi.y + 1):
		var line := ""
		for x in range(lo.x, hi.x + 1):
			var p := img.get_pixel(x, y).to_rgba32()
			line += "#" if (p != page and p != card) else "."
		mask.append(line)
	return mask


# The cards, cropped out of `region` with every background keyed to transparent.
#
# Returns {"image": Image, "lifted": int, "lo": Vector2i, "hi": Vector2i} -- the box being the
# EVIDENCE that keying the backdrop was safe, not decoration. The assumption worth checking is that
# the character never wears the backdrop's colour, since a flat key would then punch holes in him.
# On the Sage it was measured: over all 55 cards the union box of every backdrop-coloured pixel is
# the bush's own box, the five frames without the bush have none of the colour at all, and the
# per-card counts cap at exactly the unoccluded bush. A backdrop the character also wore would
# spread that box across the whole card instead.
static func paint(source: Image, region: Rect2i, animations: Array, card: int,
		backdrop: int) -> Dictionary:
	var clipped: Rect2i = region.intersection(Rect2i(Vector2i.ZERO, source.get_size()))
	var atlas := Image.create(clipped.size.x, clipped.size.y, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	var report := {"image": atlas, "lifted": 0, "lo": Vector2i(1 << 30, 1 << 30), "hi": Vector2i(-1, -1)}
	for anim: Dictionary in animations:
		for c: Rect2i in (anim["cards"] as Array):
			for y in range(c.position.y, c.end.y):
				for x in range(c.position.x, c.end.x):
					var col := source.get_pixel(x, y)
					var rgba := col.to_rgba32()
					if rgba == card:
						continue
					if backdrop >= 0 and rgba == backdrop:
						var rel := Vector2i(x, y) - c.position
						report["lifted"] = int(report["lifted"]) + 1
						report["lo"] = (report["lo"] as Vector2i).min(rel)
						report["hi"] = (report["hi"] as Vector2i).max(rel)
						continue
					atlas.set_pixelv(Vector2i(x, y) - clipped.position, col)
	return report


# Where the character STANDS inside a card, in card-local texels: the bottom-centre of the ink
# (#634). `Vector2(-1, -1)` for a card with nothing drawn on it, which callers must treat as a hard
# failure -- opaque_bounds falls back to the whole region when it finds no ink, so a silent answer
# here would hand the generator the card's own centre and ship a confidently wrong anchor.
#
# THE CARD IS A VIEWPORT, so this is asked of ONE card -- the idle pose every animation opens on --
# and never per frame. A frame's own ink moves within its card by design; that is the registration,
# and correcting it per frame would delete the footwork the card format exists to carry. Measured on
# the Sage: the ink's bottom sits at row 41 of 42 on all 58 frames, while its centre sweeps columns
# 16 to 46 across an attack.
#
# Bounds come from BoardMirror.opaque_bounds -- the project's one answer to where visible art starts,
# already read by the crown lift and the meshlib generator. A second scan here would put a unit's
# feet and its head on subtly different alpha thresholds for no reason anyone could reconstruct.
static func ground_point(image: Image, card: Rect2i) -> Vector2:
	if not _has_ink(image, card):
		return Vector2(-1, -1)
	var bounds := BoardMirror.opaque_bounds(image, card)
	return Vector2(bounds.position.x + bounds.size.x / 2.0, bounds.end.y)


# Whether anything at all is drawn in `card`. Its own scan rather than an opaque_bounds result,
# because that function answers "the whole region" for an empty one and for a full one alike.
static func _has_ink(image: Image, card: Rect2i) -> bool:
	for y in range(card.position.y, card.end.y):
		for x in range(card.position.x, card.end.x):
			if image.get_pixel(x, y).a >= 0.5:
				return true
	return false
