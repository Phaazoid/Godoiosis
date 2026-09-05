class_name LooseSheet
extends Object

# What a LOOSE spritesheet says -- one with no cards, no printed timing and no registration (#635).
# `CardSheet`'s sibling, and deliberately not a mode of it: a card sheet is READ, a loose one is
# RECONSTRUCTED, and the two make different promises. Static and pure for CardSheet's reason -- the
# rule is worth exercising against a sheet a test draws, which the generator never could be.
#
# THE PROMISE IS WEAKER THAN CardSheet'S, AND THAT IS THE POINT. A card is a fixed viewport, so a
# card sheet CARRIES the animation's footwork. A loose sheet threw it away: its frames were ripped to
# tight bounding boxes and laid out by hand, so the only thing left to align them by is the ink. This
# re-cards them -- ink bottom on the card's bottom edge, ink centred across it -- which hands the
# rest of #629's pipeline the uniform artifact it already knows how to read. What no tool can hand
# back is where the character actually STOOD.
#
# Two consequences, both visible, neither a bug to be fixed here:
#   - VERTICAL is right by construction: the lowest ink IS the ground, so a frame drawn mid-air
#     keeps its height whenever the rip drew a shadow under it (the Brigand's leap, whose shadow is
#     that frame's lowest ink).
#   - HORIZONTAL drifts with the bounding box. An axe swung out to one side widens the box on that
#     side and walks the body the other way. Hand-authored per-frame offsets are the only real cure
#     and they are #635's own fork 2, unpicked.
#
# There is no MERGE step here, deliberately. The other two sheets #635 names fail the opposite way --
# the Soldier's attack row comes back as one 257px blob because a spear sweep crosses into its
# neighbour -- so they need SPLITTING, and a merger written now would be machinery for a problem
# nobody has. A sheet whose frames do come back broken says so through the duration count.


# Below this, in either dimension, a region is not a frame: it is a letter of the animation's
# printed name. The Brigand's narrowest frame is 26px and its label glyphs cap at 8.
const MIN_FRAME := 16


# Read `region` of `source` as ONE animation of `durations.size()` frames, in reading order.
#
# Returns {"frames": Array[Rect2i] (SOURCE space), "at": Array[Vector2i] (each frame's top-left
# INSIDE its own card), "card": Vector2i, "ground": Vector2 (card-local stand point), "durations":
# Array[int], "notes": Array[String], "errors": Array[String]}. A non-empty `errors` means nothing
# may be written -- CardSheet's discipline, for CardSheet's reason.
static func read(source: Image, region_wanted: Rect2i, durations: Array) -> Dictionary:
	# Arrays rather than PackedStringArrays: a Packed*Array is a VALUE type, so appending through
	# `out["errors"]` would append to a copy and every refusal would vanish silently (#629).
	var notes: Array[String] = []
	var errors: Array[String] = []
	var out := {
		"frames": [], "at": [], "card": Vector2i.ZERO, "ground": Vector2.ZERO,
		"durations": [], "notes": notes, "errors": errors,
	}
	var region: Rect2i = region_wanted.intersection(Rect2i(Vector2i.ZERO, source.get_size()))
	if region.size.x <= 0 or region.size.y <= 0:
		errors.append("the region lies outside the sheet")
		return out

	var page: int = source.get_pixel(0, 0).to_rgba32()
	var found := components(source, page, region)
	var frames: Array[Rect2i] = []
	var dropped := 0
	for r: Rect2i in found:
		if r.size.x >= MIN_FRAME and r.size.y >= MIN_FRAME:
			frames.append(r)
		else:
			dropped += 1
	if dropped > 0:
		notes.append("ignored %d regions too small to be frames (the animation's printed name)"
				% dropped)
	if frames.is_empty():
		errors.append("no frames found -- is the region right?")
		return out

	frames = in_reading_order(frames)
	if frames.size() != durations.size():
		errors.append("found %d frames but %d durations were given -- one per frame, in reading order"
				% [frames.size(), durations.size()])
		return out

	# One card for the set: the widest frame's width, the tallest frame's height. Every frame then
	# sits with its ink BOTTOM on the card's bottom edge and its ink CENTRED across it, which is what
	# makes the stand point one number for the whole animation rather than a per-frame correction.
	var card := Vector2i.ZERO
	for r: Rect2i in frames:
		card = card.max(r.size)
	var at: Array[Vector2i] = []
	for r: Rect2i in frames:
		# Integer division on the x, so a frame an odd number of pixels narrower than its card lands
		# half a texel off centre rather than off the pixel grid. Half a texel at the board's density
		# is 1/64 of a cell; landing between pixels would be visible as a shimmer.
		at.append(Vector2i((card.x - r.size.x) / 2, card.y - r.size.y))

	out["frames"] = frames
	out["at"] = at
	out["card"] = card
	# Bottom-centre of the card, matching CardSheet.ground_point's definition exactly (the ink's
	# bottom-centre, with `end.y` one past the last ink row) so both kinds of sheet mean one thing by
	# a stand point.
	out["ground"] = Vector2(card.x / 2.0, card.y)
	out["durations"] = durations.duplicate()
	return out


# Connected regions of NOT-page pixels, 8-connected.
#
# Both properties differ from CardSheet.components and both are deliberate. It scans NOT-THE-PAGE
# rather than one colour because a loose frame has no card colour to find -- the sprite IS the
# region. And it is 8-CONNECTED because it must not split a sprite whose parts touch only at a
# corner: an axe blade meeting a hand diagonally is one frame, and 4-connectivity would file it as
# two. CardSheet needs the opposite of both, which is why this is a second function and not a
# parameter on that one.
static func components(img: Image, page: int, region: Rect2i) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var seen: Dictionary = {}
	var stride := img.get_width()
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if seen.has(y * stride + x) or img.get_pixel(x, y).to_rgba32() == page:
				continue
			var lo := Vector2i(x, y)
			var hi := lo
			var stack: Array[Vector2i] = [lo]
			seen[y * stride + x] = true
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				lo = lo.min(p)
				hi = hi.max(p)
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var q := p + Vector2i(dx, dy)
						if not region.has_point(q) or seen.has(q.y * stride + q.x):
							continue
						if img.get_pixel(q.x, q.y).to_rgba32() == page:
							continue
						seen[q.y * stride + q.x] = true
						stack.append(q)
			out.append(Rect2i(lo, hi - lo + Vector2i.ONE))
	return out


# Frames in READING ORDER: rows top to bottom, each row left to right.
#
# What makes two frames the same ROW is vertical overlap of more than half the shorter one, not a
# gap threshold -- because a frame can be much taller than its neighbours and still belong beside
# them. The Brigand's leap runs 74px against its row's 33, and it overlaps that row nearly fully
# while overlapping the row BELOW by 8 of 48. A rule reading gaps or tops puts it in its own row and
# silently reorders the whole animation.
static func in_reading_order(frames: Array[Rect2i]) -> Array[Rect2i]:
	var sorted := frames.duplicate()
	sorted.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.position.y < b.position.y)
	var rows: Array = []
	var span := Rect2i()
	for r: Rect2i in sorted:
		if rows.is_empty() or not _shares_a_row(span, r):
			rows.append([] as Array)
			span = r
		else:
			span = span.merge(r)
		(rows[-1] as Array).append(r)
	var out: Array[Rect2i] = []
	for row: Array in rows:
		row.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.position.x < b.position.x)
		for r: Rect2i in row:
			out.append(r)
	return out


static func _shares_a_row(span: Rect2i, frame: Rect2i) -> bool:
	var overlap := mini(span.end.y, frame.end.y) - maxi(span.position.y, frame.position.y)
	return overlap * 2 > mini(span.size.y, frame.size.y)


# The frames re-carded into one horizontal strip, page keyed to transparent.
#
# UNLIKE CardSheet.paint, a rect in this atlas is NOT a rect on the source: every frame has been
# moved to sit on its card's ground. That is the whole artifact -- the source coordinates are gone
# by design, and the sheet's README says so.
static func paint(source: Image, read: Dictionary, into: Image, at_row: int) -> Array[Rect2i]:
	var page: int = source.get_pixel(0, 0).to_rgba32()
	var card: Vector2i = read["card"]
	var frames: Array = read["frames"]
	var inside: Array = read["at"]
	var cards: Array[Rect2i] = []
	for i in frames.size():
		var frame: Rect2i = frames[i]
		var origin := Vector2i(i * card.x, at_row) + (inside[i] as Vector2i)
		for y in range(frame.size.y):
			for x in range(frame.size.x):
				var col := source.get_pixel(frame.position.x + x, frame.position.y + y)
				if col.to_rgba32() == page:
					continue
				into.set_pixelv(origin + Vector2i(x, y), col)
		cards.append(Rect2i(Vector2i(i * card.x, at_row), card))
	return cards
