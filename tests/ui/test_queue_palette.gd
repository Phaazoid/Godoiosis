# The action-queue panel's two palettes (#685 round 5) -- Slate, which shipped, and the Parchment the
# grill offered and lost, now a PlayerSettings choice.
#
# These are pure statics: no scene, no board. What they pin is the SHAPE of the palette rather than
# any look, because both halves of it are things a later edit makes tempting to get wrong:
#
#   * DEFAULT IS A FALL-THROUGH, NOT A ROW. Copying the slate values into PALETTES would look tidier
#     and would silently orphan EVENT_TINT's knob -- #422's ruling, and the case below is what
#     refuses it.
#   * ELEMENTS ADAPT, CHROME IS AUTHORED. An element's hue is semantic and must survive the swap
#     untouched; only its ink weight is the ground's business. That is what keeps the dev's seven
#     colour knobs live under BOTH palettes, which is the whole reason parchment derives its element
#     colours instead of authoring a second seven.
#
# NO CASE ASSERTS WHAT A COLOUR IS -- the seven elements, EVENT_TINT and the two ink values are all
# GameKnobs rows the dev drags (the tuning razor, tests/README.md #8). The contrast law below is
# asserted on PARCHMENT only, and deliberately: parchment's ink is DERIVED, so its readability is a
# property of _adapt and no setting of a colour knob can trip it. Putting the same floor over the
# authored SLATE seven would be a new constraint on seven knobs that this ticket never agreed to.
extends GdUnitTestSuite

# Generous on purpose: every readable choice clears it by miles, and at the shipped ink depth the
# floor is met BY CONSTRUCTION -- an HSV colour at value v has luma <= v, so 0.949 - 0.62 = 0.33 is
# the worst case for any hue at all. A red here means the ink depth has been tuned pale, not that an
# element colour was.
const CONTRAST_FLOOR := 0.25
# ...and its opposite, for the one colour whose whole job is to NOT be seen.
const QUIET_CEILING := 0.15

var _fire: Color
var _event: Color
var _depth: float
var _saturation: float


func before_test() -> void:
	PlayerSettings.reset_for_test()
	# Every one of these is a static that outlives a case, so a case that moves one has to put it
	# back or the next suite in the run reads a colour this file tuned.
	_fire = ElementPalette.ELEMENT_FIRE
	_event = QueueStyle.EVENT_TINT
	_depth = QueueStyle.PARCHMENT_INK_DEPTH
	_saturation = QueueStyle.PARCHMENT_INK_SATURATION


func after_test() -> void:
	ElementPalette.ELEMENT_FIRE = _fire
	QueueStyle.EVENT_TINT = _event
	QueueStyle.PARCHMENT_INK_DEPTH = _depth
	QueueStyle.PARCHMENT_INK_SATURATION = _saturation
	PlayerSettings.reset_for_test()


func _pick(palette: int) -> void:
	PlayerSettings.set_choice(PlayerSettings.Setting.QUEUE_PALETTE, palette)


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _contrast(ink: Color, ground: Color) -> float:
	return absf(_luma(ink) - _luma(ground))


# Hue is a circle, so 0.99 and 0.01 are neighbours rather than opposites.
func _hue_gap(a: float, b: float) -> float:
	var raw := absf(a - b)
	return minf(raw, 1.0 - raw)


# ==================================================================================================
#  The shape: DEFAULT falls through, PARCHMENT is a complete table
# ==================================================================================================

# #422's ruling, and the reason it is a ruling rather than a preference: a DEFAULT row would be a
# COPY of the authored consts, so EVENT_TINT's GameKnobs row would write a static the panel had
# stopped reading, and the copy would drift the first time either was tuned.
#
# Asserted BEHAVIOURALLY as well as structurally -- the table check alone would pass against an
# ink() that read a hardcoded value, which is the same bug wearing different clothes.
func test_the_default_palette_is_a_fall_through_and_not_a_table_row() -> void:
	assert_bool(QueueStyle.PALETTES.has(PlayerSettings.QueuePalette.DEFAULT)) \
		.override_failure_message("PALETTES has grown a DEFAULT row -- that is a COPY of the authored consts, and it orphans every knob that writes one of them") \
		.is_false()

	_pick(PlayerSettings.QueuePalette.DEFAULT)
	QueueStyle.EVENT_TINT = Color(0.1, 0.9, 0.2)
	assert_that(QueueStyle.ink(QueueStyle.Role.EVENT_TINT)) \
		.override_failure_message("the slate palette stopped reading the static the knob writes -- something is answering from a copy") \
		.is_equal(Color(0.1, 0.9, 0.2))


# A role added without a parchment value would fall back to the authored SLATE colour, i.e. one
# near-white label on a cream row, and nothing else would say so.
func test_every_role_has_a_parchment_colour() -> void:
	var row: Dictionary = QueueStyle.PALETTES[PlayerSettings.QueuePalette.PARCHMENT]
	var missing: Array[String] = []
	for role: QueueStyle.Role in QueueStyle.Role.values():
		if not row.has(role):
			missing.append(String(QueueStyle.Role.keys()[role]))
	assert_array(missing) \
		.override_failure_message("the parchment palette has no colour for %s -- it would fall back to the slate value, on a cream ground" % [missing]) \
		.is_empty()


# The degradation OverlayManager._palette_color chose, for the same reason: a panel that is the wrong
# colour is legible, one that crashed the draw is not. The push_error it emits is the point; gdUnit4
# does not red a case for one.
func test_a_palette_with_no_colours_falls_back_to_the_authored_ones() -> void:
	PlayerSettings.set_value(PlayerSettings.Setting.QUEUE_PALETTE, 99)
	assert_that(QueueStyle.ink(QueueStyle.Role.ROW_BG)) \
		.override_failure_message("a palette the table has never heard of did not fall back to the authored row colour") \
		.is_equal(QueueStyle.ROW_BG)


# ==================================================================================================
#  The elements: hue survives, weight adapts, the knobs stay live
# ==================================================================================================

# The claim the whole fork rests on. Fire is orange on cream and orange on slate; what changes is how
# heavily it is inked. A rebuild that picked its own hue would be a second answer to "what colour is
# Fire", which is exactly what adapting exists to avoid.
func test_parchment_keeps_every_element_hue() -> void:
	for element: Elemental.Element in Elemental.Element.values():
		if element == Elemental.Element.NONE:
			continue
		_pick(PlayerSettings.QueuePalette.DEFAULT)
		var authored := QueueStyle.element_ink(element)
		_pick(PlayerSettings.QueuePalette.PARCHMENT)
		var inked := QueueStyle.element_ink(element)
		assert_float(_hue_gap(authored.h, inked.h)) \
			.override_failure_message("%s changed HUE across the palette swap (%.3f -> %.3f) -- only its weight may move"
				% [Elemental.display_name(element), authored.h, inked.h]) \
			.is_less(0.01)


# Slate must be untouched by any of this: the shipped panel reads the authored colour exactly as it
# did before there were two palettes.
func test_slate_inks_an_element_exactly_as_authored() -> void:
	_pick(PlayerSettings.QueuePalette.DEFAULT)
	assert_that(QueueStyle.element_ink(Elemental.Element.FIRE)) \
		.override_failure_message("the adaptation leaked into the slate palette") \
		.is_equal(ElementPalette.ELEMENT_FIRE)
	assert_that(QueueStyle.state_ink(Elemental.State.WET)) \
		.override_failure_message("the adaptation leaked into the slate palette's state chips") \
		.is_equal(ElementPalette.color_for_state(Elemental.State.WET))


# The payoff of adapting rather than authoring a second seven, and the thing a re-authored palette
# structurally cannot do: OverlayManager's aim palettes make the dev's colour knobs inert while an
# alternative is picked, and these do not.
func test_a_colour_knob_still_reaches_the_parchment_palette() -> void:
	_pick(PlayerSettings.QueuePalette.PARCHMENT)
	var before := QueueStyle.element_ink(Elemental.Element.FIRE)
	# A different HUE, since hue is the one property that survives the adaptation -- moving only the
	# lightness would be erased by the ink depth and the case would pass against a hardcoded table.
	ElementPalette.ELEMENT_FIRE = Color(0.2, 0.4, 0.9)
	assert_that(QueueStyle.element_ink(Elemental.Element.FIRE)) \
		.override_failure_message("the Fire knob no longer reaches the parchment palette -- it is reading an authored copy, not the static") \
		.is_not_equal(before)


# Readability, as a property rather than a colour. Every element, every state, and the event pill.
func test_every_element_reads_against_the_parchment_row() -> void:
	_pick(PlayerSettings.QueuePalette.PARCHMENT)
	var ground := QueueStyle.ink(QueueStyle.Role.ROW_BG)

	for element: Elemental.Element in Elemental.Element.values():
		if element == Elemental.Element.NONE:
			continue
		var ink := QueueStyle.element_ink(element)
		assert_float(_contrast(ink, ground)) \
			.override_failure_message("%s inks at luma %.2f against a parchment row at %.2f -- that is the pastel-mush the adaptation exists to prevent"
				% [Elemental.display_name(element), _luma(ink), _luma(ground)]) \
			.is_greater(CONTRAST_FLOOR)

	for state: Elemental.State in Elemental.State.values():
		if state == Elemental.State.NONE:
			continue
		var ink := QueueStyle.state_ink(state)
		assert_float(_contrast(ink, ground)) \
			.override_failure_message("the %s chip inks at luma %.2f against a parchment row at %.2f"
				% [Elemental.state_display_name(state), _luma(ink), _luma(ground)]) \
			.is_greater(CONTRAST_FLOOR)

	# Authored rather than adapted, so this one CAN be got wrong by hand -- and it is the exact
	# colour round 4 had to fix on the slate side.
	var event := QueueStyle.ink(QueueStyle.Role.EVENT_TINT)
	assert_float(_contrast(event, ground)) \
		.override_failure_message("the world-event pill sits at luma %.2f against a parchment row at %.2f -- round 4's grey-on-grey, on the other ground"
			% [_luma(event), _luma(ground)]) \
		.is_greater(CONTRAST_FLOOR)


# ...and its mirror, which is the rule round 4 actually wrote down: a colour picked to RECEDE must
# stay receded. The rail's off state has that job in both palettes, and it is the value that got
# promoted to text once already.
func test_the_rail_off_state_stays_quiet_in_both_palettes() -> void:
	for palette: int in [PlayerSettings.QueuePalette.DEFAULT, PlayerSettings.QueuePalette.PARCHMENT]:
		_pick(palette)
		var rail := QueueStyle.ink(QueueStyle.Role.RAIL_NEUTRAL)
		var ground := QueueStyle.ink(QueueStyle.Role.ROW_BG)
		assert_float(_contrast(rail, ground)) \
			.override_failure_message("palette %d draws its neutral rail at luma %.2f against a row at %.2f -- an off state that loud is a rail saying something"
				% [palette, _luma(rail), _luma(ground)]) \
			.is_less(QUIET_CEILING)


# ==================================================================================================
#  The cache
# ==================================================================================================

# Every stylebox in the panel is built out of ink(), and they are built ONCE and shared. Keyed on the
# name alone, the first palette to ask wins for the life of the process -- so the swap would repaint
# every chip and leave the panel, the sections and the rows exactly as they were.
func test_the_stylebox_cache_does_not_serve_the_other_palettes_box() -> void:
	_pick(PlayerSettings.QueuePalette.DEFAULT)
	var slate_row := QueueStyle.row_box(false, false).bg_color
	var slate_panel := QueueStyle.panel_box().bg_color

	_pick(PlayerSettings.QueuePalette.PARCHMENT)
	assert_that(QueueStyle.row_box(false, false).bg_color) \
		.override_failure_message("the parchment row was handed the slate box the cache built first") \
		.is_not_equal(slate_row)
	assert_that(QueueStyle.panel_box().bg_color) \
		.override_failure_message("the parchment panel was handed the slate box the cache built first") \
		.is_not_equal(slate_panel)

	# ...and back, because a cache that answered by "whatever was asked last" would pass the above.
	_pick(PlayerSettings.QueuePalette.DEFAULT)
	assert_that(QueueStyle.row_box(false, false).bg_color) \
		.override_failure_message("switching back did not restore the slate row box") \
		.is_equal(slate_row)
