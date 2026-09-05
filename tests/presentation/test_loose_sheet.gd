# Reading a LOOSE spritesheet -- one with no cards, no printed timing and no registration (#635).
#
# Synthetic sheets throughout, for the reason `test_card_sheet` gives: `Art/Units/ZoomAnimations/`
# holds authored art the dev may replace tomorrow, so a case that asserts what the Brigand HOLDS is
# a case that reds on a content change. The shipped section at the bottom asserts PROPERTIES only.
#
# Frames here are deliberately different sizes. A reader that assumed a grid, or that centred on the
# region rather than on each frame's own ink, passes a uniform fixture and fails every one of these.
extends GdUnitTestSuite

const PAGE := Color(0.0, 0.6, 1.0, 1.0)
const INK := Color(0.1, 0.1, 0.1, 1.0)
const SHEET := Vector2i(200, 90)


# THE ORDERING CASE, and the shape is the Brigand's own: a leap frame twice its row's height, with
# the next row starting under it. Sorting by top edge puts the leap first and silently reorders the
# whole animation; a gap rule puts it in a row of its own. Only "overlaps by more than half the
# shorter one" reads it correctly.
func test_a_frame_much_taller_than_its_row_still_reads_in_that_row() -> void:
	var img := _page()
	_fill(img, Rect2i(10, 10, 20, 20))    # row 1
	_fill(img, Rect2i(40, 10, 20, 20))
	_fill(img, Rect2i(100, 5, 20, 45))    # ...the leap: taller, and starts ABOVE its row
	_fill(img, Rect2i(70, 10, 20, 20))
	_fill(img, Rect2i(10, 55, 20, 20))    # row 2, tucked under the leap
	_fill(img, Rect2i(40, 55, 20, 20))
	var read := LooseSheet.read(img, Rect2i(Vector2i.ZERO, SHEET), [1, 1, 1, 1, 1, 1])
	assert_array(read["errors"]).is_empty()
	var order: Array[Vector2i] = []
	for r: Rect2i in (read["frames"] as Array):
		order.append(r.position)
	assert_array(order).override_failure_message(
			"frames came back in %s -- reading order is rows top to bottom, each left to right" % [order]
			).is_equal([Vector2i(10, 10), Vector2i(40, 10), Vector2i(70, 10), Vector2i(100, 5),
					Vector2i(10, 55), Vector2i(40, 55)])


# A sprite's parts may touch only at a corner -- an axe blade meeting a hand diagonally -- and that
# is ONE frame. CardSheet's flood fill is 4-connected on purpose and would file it as two, which is
# why this reader has its own.
func test_two_masses_touching_only_at_a_corner_are_one_frame() -> void:
	var img := _page()
	_fill(img, Rect2i(10, 10, 20, 20))
	_fill(img, Rect2i(30, 30, 20, 20))    # shares exactly the corner pixel boundary
	var read := LooseSheet.read(img, Rect2i(Vector2i.ZERO, SHEET), [1])
	assert_array(read["errors"]).is_empty()
	assert_int((read["frames"] as Array).size()).override_failure_message(
			"a diagonal join was split into two frames; the fill is 4-connected").is_equal(1)
	assert_that((read["frames"] as Array)[0]).is_equal(Rect2i(10, 10, 40, 40))


# The animation's printed NAME sits inside the band on these sheets. Letters are small and frames
# are not, so size is what separates them -- and the reader SAYS how many it dropped rather than
# quietly swallowing something that might have been a frame.
func test_the_printed_label_is_dropped_by_size_and_reported() -> void:
	var img := _page()
	_fill(img, Rect2i(10, 30, 20, 20))
	_fill(img, Rect2i(40, 30, 20, 20))
	for x in [10, 20, 30, 40]:
		_fill(img, Rect2i(x, 5, 6, 8))    # "Axe Attack", four letters of it
	var read := LooseSheet.read(img, Rect2i(Vector2i.ZERO, SHEET), [1, 1])
	assert_array(read["errors"]).is_empty()
	assert_int((read["frames"] as Array).size()).is_equal(2)
	assert_str(", ".join(PackedStringArray(read["notes"] as Array))).contains("4 regions")


# THE RE-CARDING PROPERTY, and it is the whole reconstruction in one line: every frame, whatever its
# own size, must end up standing on its card's ground. Measured through `CardSheet.ground_point` --
# the project's one answer to where a character stands inside a card -- so the two readers cannot
# drift apart on what a stand point means. A reader that anchored on the bounding box's CENTRE
# instead of its bottom reds here and nowhere else.
func test_every_re_carded_frame_stands_on_the_same_ground() -> void:
	var img := _page()
	_fill(img, Rect2i(10, 20, 20, 30))     # tall and narrow
	_fill(img, Rect2i(40, 26, 34, 24))     # short and wide
	_fill(img, Rect2i(90, 22, 26, 28))
	var read := LooseSheet.read(img, Rect2i(Vector2i.ZERO, SHEET), [1, 1, 1])
	assert_array(read["errors"]).is_empty()
	var card: Vector2i = read["card"]
	assert_that(card).override_failure_message(
			"the card is the widest frame by the tallest, so every frame fits it").is_equal(Vector2i(34, 30))

	var strip := Image.create(card.x * 3, card.y, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0, 0, 0, 0))
	var cards := LooseSheet.paint(img, read, strip, 0)
	var ground: Vector2 = read["ground"]
	assert_that(ground).is_equal(Vector2(card.x / 2.0, card.y))
	for i in cards.size():
		var stands := CardSheet.ground_point(strip, cards[i])
		assert_float(stands.y).override_failure_message(
				"frame %d's ink bottom is at %s, not on the card's ground line %s"
				% [i, stands, ground]).is_equal(ground.y)
		# Half a texel of slack on the x and only there: a frame an odd number of pixels narrower
		# than its card cannot be centred on the pixel grid, and landing between pixels would
		# shimmer. Half a texel is 1/64 of a cell at the board's density.
		assert_float(absf(stands.x - ground.x)).override_failure_message(
				"frame %d stands at column %s, not centred on %s" % [i, stands.x, ground.x]
				).is_less_equal(0.5)


# A count that does not match is a HARD failure, naming both numbers -- the discipline CardSheet
# applies to an unreadable duration, for the same reason. This is also the only signal a sheet has
# that its frames came back merged or split: durations are authored per frame, so a sheet that read
# as 11 frames instead of 12 says so here rather than shipping a silently wrong animation.
func test_a_duration_per_frame_is_required_and_the_refusal_names_both_counts() -> void:
	var img := _page()
	_fill(img, Rect2i(10, 20, 20, 20))
	_fill(img, Rect2i(40, 20, 20, 20))
	_fill(img, Rect2i(70, 20, 20, 20))
	var read := LooseSheet.read(img, Rect2i(Vector2i.ZERO, SHEET), [1, 1])
	var said := ", ".join(PackedStringArray(read["errors"] as Array))
	assert_str(said).contains("3 frames")
	assert_str(said).contains("2 durations")
	assert_array(read["frames"]).is_empty()


# --- the shipped sheet: PROPERTIES only ----------------------------------------------------------

# Read through the generator's OWN manifest rather than restating the region and durations here --
# one answer to what the Brigand sheet is, so the tool and this suite cannot drift apart.
func test_the_shipped_brigand_reads_as_one_gesture_that_can_be_played() -> void:
	var tool_script: GDScript = load("res://tools/zoomanim/gen_zoom_animations.gd")
	var sheets: Dictionary = tool_script.get_script_constant_map()["SHEETS"]
	var spec: Dictionary = sheets["Brigand"]
	var entry: Dictionary = (spec["loose"] as Dictionary)["attack"]
	var img := Image.new()
	assert_int(img.load(spec["source"] as String)).is_equal(OK)
	var read := LooseSheet.read(img, entry["region"] as Rect2i, entry["durations"] as Array)
	assert_array(read["errors"]).override_failure_message(
			"the shipped sheet no longer reads: %s" % [read["errors"]]).is_empty()
	assert_int((read["frames"] as Array).size()).is_greater(1)
	var card: Vector2i = read["card"]
	for r: Rect2i in (read["frames"] as Array):
		assert_bool(r.size.x <= card.x and r.size.y <= card.y).override_failure_message(
				"frame %s does not fit the card %s it was measured for" % [r, card]).is_true()


# The artifact the game actually loads, asserted the way test_card_sheet asserts the Sage's: that it
# carries what a player of it needs, never what it holds.
func test_the_shipped_brigand_set_carries_a_swing_and_a_stand_point() -> void:
	var frames: SpriteFrames = load("res://Resources/ZoomAnimations/Brigand.tres")
	assert_object(frames).is_not_null()
	assert_bool(frames.has_animation(&"attack")).override_failure_message(
			"the set carries no 'attack' -- UnitMirror plays a swing by that name (#603)").is_true()
	assert_bool(frames.has_meta(&"ground_point")).override_failure_message(
			"the set carries no ground_point -- regenerate it with tools/zoomanim (#634)").is_true()
	assert_float(SpriteAnimator.length_of(frames, &"attack")).is_greater(0.0)
	var size := frames.get_frame_texture(&"attack", 0).get_size()
	for i in frames.get_frame_count(&"attack"):
		assert_that(frames.get_frame_texture(&"attack", i).get_size()).override_failure_message(
				"frame %d is a different size from frame 0; the cards are not uniform" % i
				).is_equal(size)
	# The CLOSED box, and the difference from test_card_sheet's identical-looking assertion is the
	# artifact itself: re-carding puts a frame's ink bottom FLUSH with its card's bottom edge, so the
	# stand point lands exactly on `size.y`. `Rect2.has_point` excludes that edge and would refuse a
	# set that is correct.
	var point: Vector2 = frames.get_meta(&"ground_point")
	var inside := point.x >= 0.0 and point.x <= size.x and point.y >= 0.0 and point.y <= size.y
	assert_bool(inside).override_failure_message(
			"stand point %s falls outside its own %s card" % [point, size]).is_true()


# --- helpers -------------------------------------------------------------------------------------


func _page() -> Image:
	var img := Image.create(SHEET.x, SHEET.y, false, Image.FORMAT_RGBA8)
	img.fill(PAGE)
	return img


func _fill(img: Image, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			img.set_pixel(x, y, INK)
