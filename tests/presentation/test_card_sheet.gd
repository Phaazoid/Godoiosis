# Reading a card-format spritesheet (#629): where the frames are, how long each is held, and where
# one animation ends and the next begins.
#
# THE EXACT CASES RUN ON A SHEET THIS FILE DRAWS, and that is the content razor rather than
# convenience. `Art/Units/ZoomAnimations/Sage.png` is authored art the dev may replace tomorrow, so
# asserting that it holds 26 attack frames would be pinning his content -- `b057f6e` already cost 49
# cases by doing exactly that one level up. The real sheet gets PROPERTY checks only: every rect is
# a card, every rect is inside the sheet, every duration is positive, nothing errors.
#
# What the synthetic cases can and cannot show. They exercise the PLUMBING -- finding cards, locating
# a label, grouping rows, splitting animations, reading order -- and the matcher's exactness. They
# do NOT prove the glyph TABLE maps the right shapes to the right numbers, because they draw their
# labels from that same table. That mapping is argued by provenance instead, at the table itself:
# the one ambiguous glyph was settled against the sheet's own printed "go to Attack frame 3", and
# the table's predicted counts match the row structure independently.
extends GdUnitTestSuite

const PAGE := Color8(200, 100, 200)
const CARD := Color8(240, 90, 190)
const INK := Color8(20, 20, 60)
const CARD_SIZE := Vector2i(24, 16)
const SHEET_SIZE := Vector2i(140, 120)
const NAMES: Array = ["swing", "flinch"]

# Two animations, the first WRAPPING over two rows -- which is the case a gap-size heuristic gets
# wrong and the name-label rule gets right.
const ROWS: Array = [
	[30, [20, 50, 80], true],    # y, card x positions, does a name label sit to its left
	[60, [20, 50], false],
	[90, [20, 50], true],
]
const DURATIONS: Array = [60, 6, 13, 8, 4, 11, 20]

# The shipped sheet is read once for the whole suite: the histogram alone walks 2.6M pixels, and
# every property case wants the same answer.
static var _shipped: Dictionary = {}


# --- the plumbing, on a sheet we drew ------------------------------------------------------------


func test_it_reads_the_frames_durations_and_animation_split_of_a_card_sheet() -> void:
	var read := CardSheet.read(_build(), Rect2i(Vector2i.ZERO, SHEET_SIZE), NAMES)
	assert_int(_errors(read).size()).override_failure_message(
			"unexpected: %s" % _errors(read)).is_equal(0)

	var animations: Array = read["animations"]
	assert_int(animations.size()).is_equal(2)
	assert_str(animations[0]["name"]).is_equal("swing")
	assert_str(animations[1]["name"]).is_equal("flinch")

	# The first animation wraps rows one and two; the third row starts the second.
	assert_int((animations[0]["cards"] as Array).size()).is_equal(5)
	assert_int((animations[1]["cards"] as Array).size()).is_equal(2)

	assert_array(animations[0]["durations"]).is_equal(DURATIONS.slice(0, 5))
	assert_array(animations[1]["durations"]).is_equal(DURATIONS.slice(5, 7))


func test_a_frame_is_the_WHOLE_card_and_not_the_ink_inside_it() -> void:
	# The card is a viewport: where the sprite sits inside it IS the per-frame offset. A reader that
	# trimmed to content would lose the animation's own footwork and play back as a jitter.
	var img := _build()
	# Put a lone speck near one card's corner -- content-trimming would move that frame's rect.
	img.set_pixel(22, 32, INK)
	var read := CardSheet.read(img, Rect2i(Vector2i.ZERO, SHEET_SIZE), NAMES)
	assert_int(_errors(read).size()).override_failure_message(
			"unexpected: %s" % _errors(read)).is_equal(0)
	var first: Rect2i = (read["animations"][0]["cards"] as Array)[0]
	assert_vector(first.position).is_equal(Vector2i(20, 30))
	assert_vector(first.size).is_equal(CARD_SIZE)


func test_a_sprite_overhanging_its_gutter_does_not_weld_two_frames_into_one() -> void:
	# THE reason cards are found by card colour rather than by "not the page colour". A sprite that
	# spills across the gutter joins its neighbour under a not-the-page scan; the Sage does this,
	# and it showed up as a 136px run where two 66px cards should be.
	var img := _build()
	for x in range(40, 56):
		img.set_pixel(x, 35, INK)   # bridges the gutter between the first two cards of row one

	var read := CardSheet.read(img, Rect2i(Vector2i.ZERO, SHEET_SIZE), NAMES)
	assert_int(_errors(read).size()).override_failure_message(
			"unexpected: %s" % _errors(read)).is_equal(0)
	var cards: Array = read["animations"][0]["cards"]
	assert_int(cards.size()).is_equal(5)
	assert_vector((cards[0] as Rect2i).position).is_equal(Vector2i(20, 30))
	assert_vector((cards[1] as Rect2i).position).is_equal(Vector2i(50, 30))
	assert_vector((cards[0] as Rect2i).size).is_equal(CARD_SIZE)


func test_frames_come_back_in_reading_order() -> void:
	var read := CardSheet.read(_build(), Rect2i(Vector2i.ZERO, SHEET_SIZE), NAMES)
	var cards: Array = read["animations"][0]["cards"]
	# Rows top to bottom, and within a row left to right -- never the other way round.
	var seen: Array[Vector2i] = []
	for c: Rect2i in cards:
		seen.append(c.position)
	assert_array(seen).is_equal([
		Vector2i(20, 30), Vector2i(50, 30), Vector2i(80, 30),
		Vector2i(20, 60), Vector2i(50, 60),
	])


func test_a_label_it_cannot_read_exactly_is_refused_rather_than_guessed() -> void:
	# A wrong duration is invisible in the output and shows up only as bad feel, so a near miss must
	# never resolve to the nearest glyph.
	var img := _build()
	var mask := CardSheet.label_mask(img, PAGE.to_rgba32(), CARD.to_rgba32(),
			Rect2i(20, 30, CARD_SIZE.x, CARD_SIZE.y))
	assert_int(mask.size()).is_greater(0)
	img.set_pixel(24, 20, INK)   # one pixel the glyph does not have

	var read := CardSheet.read(img, Rect2i(Vector2i.ZERO, SHEET_SIZE), NAMES)
	assert_int(_errors(read).size()).is_greater(0)
	assert_str(_first_error(read)).contains("unreadable duration label")


func test_a_row_without_a_name_beside_it_continues_the_animation_before_it() -> void:
	# Erase the third row's name label: its frames should now belong to the animation above rather
	# than starting one, and the name count no longer matches, which is refused.
	var img := _build()
	_fill(img, Rect2i(0, 88, 20, 20), PAGE)
	var read := CardSheet.read(img, Rect2i(Vector2i.ZERO, SHEET_SIZE), NAMES)
	assert_int(_errors(read).size()).is_greater(0)
	assert_str(_first_error(read)).contains("found 1 animations but 2 names")


func test_a_sheet_with_no_clear_card_colour_is_refused() -> void:
	# Answering with a sprite colour would make everything downstream nonsense built on it.
	var img := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	img.fill(PAGE)
	_fill(img, Rect2i(0, 0, 10, 10), CARD)
	_fill(img, Rect2i(20, 0, 10, 10), INK)   # just as much ink as card
	assert_int(CardSheet.card_colour(img, PAGE.to_rgba32())).is_equal(-1)


# --- the shipped sheet: properties only ----------------------------------------------------------


func test_the_shipped_sheet_reads_without_error() -> void:
	var read := _shipped_read()
	assert_int(_errors(read).size()).override_failure_message(
			"unexpected: %s" % _errors(read)).is_equal(0)
	assert_array(read["animations"]).is_not_empty()


func test_every_frame_of_the_shipped_sheet_is_a_card_lying_inside_the_sheet() -> void:
	var read := _shipped_read()
	var img: Image = read["_image"]
	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	var card: int = read["card"]
	var frames := 0
	for anim: Dictionary in (read["animations"] as Array):
		for c: Rect2i in (anim["cards"] as Array):
			frames += 1
			assert_bool(bounds.encloses(c)).override_failure_message(
					"frame %s falls outside the sheet" % c).is_true()
			# Its own corners are card-coloured, so it really is a card and not some other region.
			for corner: Vector2i in [c.position, Vector2i(c.end.x - 1, c.position.y),
					Vector2i(c.position.x, c.end.y - 1), c.end - Vector2i.ONE]:
				assert_int(img.get_pixelv(corner).to_rgba32()).override_failure_message(
						"frame %s has a corner at %s that is not card-coloured" % [c, corner]
						).is_equal(card)
	assert_int(frames).override_failure_message(
			"the shipped sheet yielded no frames at all").is_greater(0)


func test_every_frame_of_the_shipped_sheet_is_held_for_a_positive_time() -> void:
	var read := _shipped_read()
	for anim: Dictionary in (read["animations"] as Array):
		var durations: Array = anim["durations"]
		assert_int(durations.size()).is_equal((anim["cards"] as Array).size())
		for d: int in durations:
			assert_int(d).override_failure_message(
					"%s holds a frame for %d" % [anim["name"], d]).is_greater(0)


func test_the_shipped_sheet_reads_in_reading_order() -> void:
	var read := _shipped_read()
	for anim: Dictionary in (read["animations"] as Array):
		var previous := Vector2i(-1, -1)
		for c: Rect2i in (anim["cards"] as Array):
			var ordered := c.position.y > previous.y \
					or (c.position.y == previous.y and c.position.x > previous.x)
			assert_bool(ordered).override_failure_message(
					"%s reads %s after %s" % [anim["name"], c.position, previous]).is_true()
			previous = c.position


# --- where the character stands (#634) ------------------------------------------------------------


func test_the_stand_point_is_the_inks_bottom_centre_and_not_the_cards() -> void:
	# The Sage's own shape, in miniature: a card far wider than the pose needs, with the character
	# standing LEFT of centre and clear of the bottom edge, because the space is lunge room. Hanging
	# such a card from its own centre is exactly the bug -- so the card's centre is asserted to be a
	# DIFFERENT answer, or this case would pass on an implementation that never measured anything.
	var img := Image.create(40, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(6, 4, 8, 10), INK)   # ink spans x 6..13, y 4..13

	var point := CardSheet.ground_point(img, Rect2i(Vector2i.ZERO, Vector2i(40, 20)))
	assert_float(point.x).is_equal_approx(10.0, 0.001)   # 6 + 8/2, the ink's centre
	assert_float(point.y).is_equal_approx(14.0, 0.001)   # one past the last ink row
	assert_vector(point).override_failure_message(
			"the stand point came back as the CARD's centre, which is the thing being measured away"
			).is_not_equal(Vector2(20.0, 10.0))


func test_a_card_with_nothing_drawn_on_it_is_refused_rather_than_answered() -> void:
	# opaque_bounds falls back to the whole region when it finds no ink, so an unguarded measurement
	# would confidently return the card's centre for a blank card. A wrong anchor is invisible in the
	# output and shows up as art hanging off its tile, which is the same class of silent error the
	# duration matcher refuses rather than guesses at.
	var img := Image.create(40, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	assert_vector(CardSheet.ground_point(img, Rect2i(Vector2i.ZERO, Vector2i(40, 20)))
			).is_equal(Vector2(-1, -1))


func test_the_shipped_set_carries_a_stand_point_inside_its_own_idle_card() -> void:
	# A PROPERTY of the generated artifact, never its value: what the Sage measures to is content the
	# dev may replace. What must hold is that the set carries a measurement at all -- a regeneration
	# that dropped it would put every frame back on the 32px map pivot with nothing saying so.
	var frames: SpriteFrames = load("res://Resources/ZoomAnimations/Sage.tres")
	assert_object(frames).is_not_null()
	assert_bool(frames.has_meta(&"ground_point")).override_failure_message(
			"the shipped set carries no ground_point -- regenerate it with tools/zoomanim (#634)"
			).is_true()
	var point: Vector2 = frames.get_meta(&"ground_point")
	var names := frames.get_animation_names()
	assert_int(names.size()).is_greater(0)
	for anim_name: String in names:
		var card := frames.get_frame_texture(anim_name, 0).get_size()
		assert_bool(Rect2(Vector2.ZERO, card).has_point(point)).override_failure_message(
				"%s: stand point %s falls outside its own %s card" % [anim_name, point, card]
				).is_true()


# --- helpers -------------------------------------------------------------------------------------


# Read through the generator's OWN manifest rather than restating its region and names here -- one
# answer to what the Sage sheet is, so the tool and this suite cannot drift apart.
func _shipped_read() -> Dictionary:
	if not _shipped.is_empty():
		return _shipped
	var tool_script: GDScript = load("res://tools/zoomanim/gen_zoom_animations.gd")
	var sheets: Dictionary = tool_script.get_script_constant_map()["SHEETS"]
	var spec: Dictionary = sheets["Sage"]
	var img := Image.new()
	assert_int(img.load(spec["source"] as String)).is_equal(OK)
	_shipped = CardSheet.read(img, spec["region"] as Rect2i, spec["animations"] as Array)
	_shipped["_image"] = img
	return _shipped


func _build() -> Image:
	var img := Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(PAGE)
	var next := 0
	for row: Array in ROWS:
		var y: int = row[0]
		if row[2]:
			_fill(img, Rect2i(8, y, 6, 6), INK)   # the animation's name, to the LEFT of the row
		for x: int in (row[1] as Array):
			_fill(img, Rect2i(x, y, CARD_SIZE.x, CARD_SIZE.y), CARD)
			_glyph(img, DURATIONS[next], x, y - 12)
			next += 1
	return img


func _fill(img: Image, r: Rect2i, colour: Color) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			img.set_pixel(x, y, colour)


func _glyph(img: Image, value: int, card_x: int, top: int) -> void:
	var rows: Array = []
	for entry: Array in CardSheet.DURATION_GLYPHS:
		if int(entry[0]) == value:
			rows = entry[1]
	assert_array(rows).override_failure_message(
			"no glyph in the table for %d" % value).is_not_empty()
	var width: int = (rows[0] as String).length()
	var x0: int = card_x + (CARD_SIZE.x - width) / 2
	for r in rows.size():
		var line: String = rows[r]
		for c in line.length():
			if line[c] == "#":
				img.set_pixel(x0 + c, top + r, INK)


# TYPE IT BEFORE ASSERTING ON IT. A PackedStringArray reached through a Dictionary arrives as a
# Variant, and both things you would reach for silently misbehave: indexing the chain fails at
# runtime, and `assert_array()` reports it EMPTY whatever it holds -- so `is_empty()` on one passes
# vacuously and can never fail. Caught here the honest way: the case that corrupts a glyph went
# green against a reader that was correctly refusing it. Assert on `.size()` of a typed local.
func _errors(read: Dictionary) -> Array:
	return read["errors"]


func _first_error(read: Dictionary) -> String:
	var errors := _errors(read)
	return "" if errors.is_empty() else errors[0]
