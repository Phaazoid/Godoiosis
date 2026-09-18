# The aura readout (#930) -- the first time either aura or affinity has been shown to a player.
#
# WHAT THESE CASES ARE REALLY DEFENDING: affinity and aura are two fields, and every tempting
# simplification collapses them. "Affine" is not "aura >= 1" -- the limb tax empties a pool while the
# growth right survives (UnitInstance.gd's own note), so a readout keyed on the pool erases exactly
# the state the model was split for. test_an_emptied_pool_keeps_its_affinity is that mutant's grave.
#
# WHAT A HEADLESS SUITE CANNOT SEE, said out loud: nothing here proves a tick is legible at 52px, that
# the ring frames the character rather than the sprite's empty top half, or that the hover highlight
# reads as an outline. The first is unmeasurable, the second is pinned only indirectly (the ink box's
# own provenance case below), and all three are the dev's to play. What IS pinned is the model, the
# angle bucket the hover resolves to, and that the panel's wheel actually moves when a limb is lost.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const PANEL_SCENE := "res://Scenes/UnitInfoPanel.tscn"

const FIRE := Elemental.Element.FIRE
const WATER := Elemental.Element.WATER
const EARTH := Elemental.Element.EARTH
const AIR := Elemental.Element.AIR
const AETHER := Elemental.Element.AETHER

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func after_test() -> void:
	# #473's orphan workaround: a frame for queue_free to land, or the runner reports a non-zero
	# verdict with zero failures.
	await await_idle_frame()


# Affinity ORDER is the argument, not a set: rank is what the readout carries now that the ring draws
# no primary marker (dev, #930).
func _alchemist(order: Array[Elemental.Element], aura: Dictionary[Elemental.Element, int],
		cell := Vector2i.ZERO) -> Unit:
	var u: Unit = H.spawn_solo(self, _sm, Team.Faction.PLAYER, cell, {}, false)
	u.unit_instance.affinity = order.duplicate()
	u.unit_instance.aura = aura.duplicate()
	return u


func _row_for(target: Unit, element: Elemental.Element) -> AuraRing.Row:
	for row: AuraRing.Row in AuraRing.rows(target):
		if row.element == element:
			return row
	return null


# --- the model -------------------------------------------------------------------------------------

# Celest as shipped. She is the case that proves rank and depth are different questions: her PRIMARY
# affinity is her SHALLOWEST pool, so a readout that sorted by depth would call her a fire alchemist.
func test_every_sigil_gets_a_row_whether_the_unit_can_touch_it_or_not() -> void:
	var celest := _alchemist([EARTH, FIRE, AETHER], {FIRE: 2, EARTH: 1, AETHER: 2})
	var rows := AuraRing.rows(celest)

	assert_int(rows.size()).is_equal(Elemental.SIGIL_ELEMENTS.size())
	assert_bool(_row_for(celest, FIRE).affine).is_true()
	assert_int(_row_for(celest, FIRE).depth).is_equal(2)
	assert_int(_row_for(celest, EARTH).depth).is_equal(1)
	assert_int(_row_for(celest, AETHER).depth).is_equal(2)
	# The two she can never grow are still drawn -- fixed positions are what make the wheel learnable.
	assert_bool(_row_for(celest, WATER).affine).is_false()
	assert_bool(_row_for(celest, AIR).affine).is_false()


# THE case. A maimed alchemist sits at aura 0 in an element she is still affine to, and the two states
# must not render alike: dim-but-coloured is "yours, and empty", faint grey is "never yours".
func test_an_emptied_pool_keeps_its_affinity() -> void:
	var maimed := _alchemist([EARTH, FIRE], {FIRE: 2, EARTH: 0})
	var earth := _row_for(maimed, EARTH)

	assert_bool(earth.affine).is_true()
	assert_int(earth.depth).is_equal(0)
	# ...and that is a different answer from an element she never had.
	assert_bool(_row_for(maimed, WATER).affine).is_false()


func test_a_unit_with_no_affinity_can_touch_none_of_the_five() -> void:
	var rebecca := _alchemist([], {})
	assert_int(AuraRing.rows(rebecca).size()).is_equal(Elemental.SIGIL_ELEMENTS.size())
	for row: AuraRing.Row in AuraRing.rows(rebecca):
		assert_bool(row.affine).is_false()
		assert_int(row.depth).is_equal(0)


# The hidden sixth is never displayed (alchemy-kit.md). Asserting "no sixth row" would be vacuous --
# rows() walks SIGIL_ELEMENTS and returns five for everybody. The real question is whether the flag
# LEAKS, so this reads Isaac against a twin who does not carry it and demands the same five rows.
func test_the_alkahest_flag_changes_nothing_the_player_sees() -> void:
	var isaac := _alchemist([AETHER, AIR, EARTH, WATER, FIRE],
		{FIRE: 1, WATER: 1, EARTH: 1, AIR: 1, AETHER: 1})
	isaac.unit_instance.is_alkahest_affine = true
	var twin := _alchemist([AETHER, AIR, EARTH, WATER, FIRE],
		{FIRE: 1, WATER: 1, EARTH: 1, AIR: 1, AETHER: 1}, Vector2i(1, 0))

	var his := AuraRing.rows(isaac)
	var hers := AuraRing.rows(twin)
	assert_int(his.size()).is_equal(hers.size())
	for i in his.size():
		assert_that(his[i].element).is_equal(hers[i].element)
		assert_bool(his[i].affine).is_equal(hers[i].affine)
		assert_int(his[i].depth).is_equal(hers[i].depth)


# The wheel reorders the sigils for a reason (both oppositions at maximum separation) -- it must never
# ADD or DROP one. A sixth sigil should fail here rather than silently lose a sector on two screens.
func test_the_wheel_is_a_permutation_of_the_sigils() -> void:
	assert_int(AuraRing.WHEEL.size()).is_equal(Elemental.SIGIL_ELEMENTS.size())
	for element: Elemental.Element in Elemental.SIGIL_ELEMENTS:
		assert_bool(AuraRing.WHEEL.has(element)).is_true()


# --- the readout -------------------------------------------------------------------------------------

func test_the_readout_lists_affinities_in_rank_order_and_names_the_primary() -> void:
	var celest := _alchemist([EARTH, FIRE, AETHER], {FIRE: 2, EARTH: 1, AETHER: 2})
	var text := AuraRing.readout(celest)

	# Rank order, not depth order and not wheel order: Earth leads on 1 while Fire sits on 2.
	assert_int(text.find("Earth 1")).is_greater(-1)
	assert_bool(text.find("Earth 1") < text.find("Fire 2")).is_true()
	assert_bool(text.find("Fire 2") < text.find("Aether 2")).is_true()
	assert_int(text.find("Earth is primary")).is_greater(-1)


func test_the_readout_says_out_loud_that_an_empty_pool_is_still_theirs() -> void:
	var maimed := _alchemist([EARTH, FIRE], {FIRE: 2, EARTH: 0})
	assert_int(AuraRing.readout(maimed).find("still theirs to grow")).is_greater(-1)
	# ...and a unit with nothing empty does not carry the sentence.
	var whole := _alchemist([EARTH], {EARTH: 2}, Vector2i(1, 0))
	assert_int(AuraRing.readout(whole).find("still theirs to grow")).is_equal(-1)


func test_a_unit_with_no_affinity_is_told_so_rather_than_shown_five_zeroes() -> void:
	var rebecca := _alchemist([], {})
	assert_int(AuraRing.readout(rebecca).find("No elemental affinity")).is_greater(-1)


# MAX_TICKS caps the DRAWING, never the truth. Aura has no ceiling in the model, so a pool past five
# has to keep stating its real depth somewhere -- and the readout is that somewhere.
func test_a_pool_past_the_display_cap_still_states_its_real_depth() -> void:
	var prodigy := _alchemist([AETHER], {AETHER: 8})
	assert_int(_row_for(prodigy, AETHER).depth).is_equal(8)
	assert_int(AuraRing.readout(prodigy).find("Aether 8")).is_greater(-1)
	assert_int(AuraRing.MAX_TICKS).is_less(8)   # ...so the ring really is clamping, not coinciding


# --- hover -----------------------------------------------------------------------------------------

# An angle bucket off by one sector is a bug no assertion about colour could catch, and a synthetic
# motion event is the real door -- _gui_input is what the engine calls.
func test_the_hovered_sector_is_the_one_the_cursor_is_in() -> void:
	var celest := _alchemist([EARTH, FIRE, AETHER], {FIRE: 2, EARTH: 1, AETHER: 2})
	var ring := await _sized_ring(celest, 160.0)
	var centre := Vector2(80, 80)

	for i in AuraRing.WHEEL.size():
		# The middle of sector i's own arc, out where the ticks are.
		var angle := AuraRing.ARC_START + (float(i) + 0.5) * AuraRing.SECTOR
		var at := centre + Vector2(cos(angle), sin(angle)) * 60.0
		assert_that(ring.element_at(at)).is_equal(AuraRing.WHEEL[i])

	# The middle is the PORTRAIT, not an element: pointing at the character is not pointing at fire.
	assert_that(ring.element_at(centre)).is_equal(Elemental.Element.NONE)


func test_a_motion_event_sets_and_clears_the_highlight() -> void:
	var celest := _alchemist([EARTH, FIRE, AETHER], {FIRE: 2, EARTH: 1, AETHER: 2})
	var ring := await _sized_ring(celest, 160.0)
	assert_that(ring.hovered).is_equal(Elemental.Element.NONE)

	var angle := AuraRing.ARC_START + 3.5 * AuraRing.SECTOR   # sector 3 is AETHER
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(80, 80) + Vector2(cos(angle), sin(angle)) * 60.0
	ring._gui_input(motion)
	assert_that(ring.hovered).is_equal(AETHER)

	motion.position = Vector2(80, 80)
	ring._gui_input(motion)
	assert_that(ring.hovered).is_equal(Elemental.Element.NONE)


# The ring DERIVES its geometry from the rect it lands in, so a case about angles has to give it one:
# a Control built with .new() and never laid out is 0x0, and every point then falls in one sector.
func _sized_ring(target: Unit, box_px: float) -> AuraRing:
	var ring: AuraRing = auto_free(AuraRing.over_portrait(target))
	add_child(ring)
	ring.size = Vector2(box_px, box_px)
	await await_idle_frame()
	return ring


# --- the ink box ---------------------------------------------------------------------------------

# This pinned the literal (-4, -11) until #937, as provenance that hoisting the measurement out of
# PreMissionScreen had not nudged a shipped surface. That number described the Fire Emblem art, which
# is gone, and re-pinning whatever the Zerie art produces would be a number nobody could check --
# the content razor, arriving at a measurement rather than at a level.
#
# The obvious replacement -- "window_offset() centres ink_centre() in its window" -- is VACUOUS, and
# writing it first is how that was found: `window_offset` is DEFINED as `half the window minus
# ink_centre`, so the assertion holds for any INK_RECT including a badly wrong one. It can never fail.
#
# What is actually at risk is INK_RECT drifting from the art it claims to measure, so ask the ART.
# The load-bearing half is the SHARED BASELINE -- one INK_RECT serves every sprite only while every
# sprite's feet are on the same row -- and that is what re-cutting the art without re-running
# tools/sprites/extract_stills.gd would break. Content is read, never pinned: no count, no name, no
# per-character number appears here.
func test_every_shipped_map_sprite_ends_its_ink_where_INK_RECT_says() -> void:
	var sheet := MapSpriteInk.SHEET
	assert_int(MapSpriteInk.INK_RECT.end.y).is_equal(sheet) \
		.override_failure_message("INK_RECT must sit its feet on the sheet's last row")

	var checked := 0
	for file: String in ResourceDir.files_with_extension("res://Art/Units/MapSprites/", ".png"):
		if file.ends_with("_Moving.png") or file.ends_with("_Downed.png"):
			continue
		var tex: Texture2D = load("res://Art/Units/MapSprites/" + file)
		var image := tex.get_image()
		if image.is_compressed():
			image = image.duplicate()
			image.decompress()
		var ink := image.get_used_rect()
		assert_int(image.get_width()).is_equal(sheet).override_failure_message(
				"%s is %dpx wide; MapSpriteInk.SHEET says %d" % [file, image.get_width(), sheet])
		assert_int(ink.end.y).is_equal(sheet).override_failure_message(
				"%s ends its ink on row %d, not the sheet's last row -- the baseline is not shared, "
				% [file, ink.end.y] + "so one INK_RECT cannot serve every sprite")
		checked += 1
	assert_int(checked).is_greater(0).override_failure_message(
			"scanned no map sprites -- this case would pass vacuously")


# A ring centred on the sprite's BOX would sit a third of the box above the character, because every
# map sprite draws its ink in the lower half. This is the arithmetic that says so -- and it still
# describes the 1:1 CROP the deployed strip uses (window_offset), which is why #990 left it alone even
# though the card no longer fits a cell into its box.
func test_the_ink_centre_sits_well_below_the_canvas_centre() -> void:
	var box := 52.0
	assert_float(MapSpriteInk.ink_centre(box).y).is_greater(box * 0.5 + 8.0)
	assert_float(MapSpriteInk.ink_centre(box).x).is_equal_approx(box * 0.5, 1.0)


# THE CARD'S FACTORY, which nothing in this suite had ever built -- every case above uses the panel's.
# Two properties, both read off the live rect rather than typed: the ring fills the column it is given,
# and the sprite is drawn to FILL that ring rather than fitted into the box cell-and-all (#990).
#
# The texture is a placeholder on purpose: ink_fit_rect answers from MapSpriteInk.SHEET, never from the
# texture handed in, so the geometry here is the same one every shipped sprite gets.
func test_the_cards_ring_fills_its_column_and_the_sprite_fills_the_ring() -> void:
	var celest := _alchemist([EARTH, FIRE], {EARTH: 1, FIRE: 2})
	var box := float(PreMissionCard.SPRITE)
	var ring: AuraRing = auto_free(AuraRing.for_portrait(celest, PlaceholderTexture2D.new(), box))
	add_child(ring)
	ring.size = Vector2(box, box)
	await await_idle_frame()

	assert_float(ring._outer * 2.0).override_failure_message(
		"the ring is %.1f px across inside a %.0f px column" % [ring._outer * 2.0, box]) \
		.is_equal_approx(box, 0.5)

	var scale: float = ring._portrait_rect.size.x / float(MapSpriteInk.SHEET)
	var ink := Rect2(ring._portrait_rect.position + Vector2(MapSpriteInk.INK_RECT.position) * scale,
		Vector2(MapSpriteInk.INK_RECT.size) * scale)
	assert_float(ink.get_center().distance_to(ring._centre)).override_failure_message(
		"the character is drawn off the middle of its own ring").is_less_equal(1.0)
	assert_float(ink.size.length() * 0.5).override_failure_message(
		"the character's ink reaches %.1f px and the band starts at %.1f -- it is not filling the ring"
		% [ink.size.length() * 0.5, ring._inner]).is_equal_approx(ring._inner - AuraRing.CLEARANCE, 0.5)
	# The consequence a caller has to know about, stated rather than left to be discovered: filling the
	# ring with the INK means the CELL is drawn larger than the node, so an outlier sprite's own
	# overflow lands outside the column.
	assert_float(ring._portrait_rect.size.x).override_failure_message(
		"the drawn sheet fits inside the column, so the ink cannot be filling the ring").is_greater(box)


# --- the wire ------------------------------------------------------------------------------------

# THE END-TO-END ONE: a lost limb docks the deepest pool, and the panel has to notice.
#
# It downs the unit FOR REAL rather than calling UnitInstance.spend_will_for_down() directly, and the
# difference is not stylistic: that function emits will_changed BEFORE it applies the aura tax, so a
# panel driven straight off it refreshes against the OLD pool and the case would pass on a broken
# wire. What makes the readout correct in play is Unit._go_downed's NEXT line -- _settle_stat_change()
# -> stats_changed -> _refresh(). take_damage is the door that runs both, so it is the door tested.
# (tests/stats/test_limb_slots.gd writes limbs[slot].state directly, which skips the tax entirely --
# a fixture worth not copying here.)
func test_a_maim_moves_the_panels_wheel() -> void:
	var dorian := _alchemist([AETHER], {AETHER: 3})
	var panel: Control = auto_free((load(PANEL_SCENE) as PackedScene).instantiate())
	add_child(panel)
	await await_idle_frame()
	panel.set_unit(dorian)
	await await_idle_frame()

	var ring := _panel_ring(panel)
	assert_object(ring).is_not_null()
	var before := ring.tooltip_text
	assert_int(before.find("Aether 3")).is_greater(-1)

	dorian.unit_instance.current_will = 0     # cannot afford the down, so it maims
	dorian.take_damage(dorian.get_current_hp())
	await await_idle_frame()

	assert_bool(dorian.unit_instance.is_maimed()).is_true()
	assert_int(dorian.get_element_aura(AETHER)).is_equal(2)
	# The ring is telling the CURRENT story, not the one it was built with.
	assert_str(ring.tooltip_text).is_not_equal(before)
	assert_str(ring.tooltip_text).is_equal(AuraRing.readout(dorian))


# The ring wraps the PORTRAIT on both surfaces, which is the whole reason it fits here at all: the
# panel's body had 72px of headroom against a 720px column, and a wheel in it overflowed by 92.
# Drawn AFTER the texture, so the hover readout lands on the portrait rather than behind it.
func test_the_panels_ring_wraps_its_portrait_and_draws_over_it() -> void:
	var celest := _alchemist([EARTH, FIRE, AETHER], {FIRE: 2, EARTH: 1, AETHER: 2})
	var panel: Control = auto_free((load(PANEL_SCENE) as PackedScene).instantiate())
	add_child(panel)
	await await_idle_frame()
	panel.set_unit(celest)
	await await_idle_frame()

	var portrait: Control = panel.get_node("UnitInfoPanel/Margin/VBox/HeaderRow/PortraitPanel")
	var ring := _panel_ring(panel)
	assert_object(ring.get_parent()).is_same(portrait)
	assert_object(ring.unit).is_same(celest)
	assert_that(ring.ground).is_equal(AuraRing.Ground.AUTHORED)
	# Later sibling = drawn later = on top of the portrait texture.
	assert_int(ring.get_index()).is_greater(portrait.get_node("PortraitTexture").get_index())
	# ...and it carries no sprite of its own, since the node below it is the picture.
	assert_object(ring.portrait).is_null()


# A unit with no affinity gets the all-faint wheel rather than a hidden section -- the card's answer,
# now that both surfaces wear the same ring. The sentence is in the readout.
func test_a_unit_with_no_affinity_still_wears_a_wheel_on_the_panel() -> void:
	var rebecca := _alchemist([], {})
	var panel: Control = auto_free((load(PANEL_SCENE) as PackedScene).instantiate())
	add_child(panel)
	await await_idle_frame()
	panel.set_unit(rebecca)
	await await_idle_frame()

	var ring := _panel_ring(panel)
	assert_bool(ring.visible).is_true()
	assert_int(ring.tooltip_text.find("No elemental affinity")).is_greater(-1)


func _panel_ring(panel: Control) -> AuraRing:
	for node in _walk(panel):
		var ring := node as AuraRing
		if ring != null:
			return ring
	return null


static func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


# --- the demand overlay (#1019) ---------------------------------------------------------------------

# WHAT THESE CANNOT SEE, said out loud beside the header's own list: a hollow tick is drawn as its own
# outline and a halo as a wider bar behind one, and neither leaves anything a headless case can read --
# _draw writes pixels and returns nothing. So what is pinned here is the MODEL that decides both
# states, plus the two arithmetic properties a wrong constant would break silently. Whether a hollow
# bar reads as empty at 116px is the dev's to play.

func _circle(sigils: Array[Elemental.Element], utility := false) -> TransmutationData:
	var carving := TransmutationData.new()
	carving.sigils = sigils.duplicate()
	carving.deals_no_damage = utility
	return carving


func _demand_row(target: Unit, carving: TransmutationData,
		element: Elemental.Element) -> AuraRing.Row:
	for row: AuraRing.Row in AuraRing.rows(target, carving):
		if row.element == element:
			return row
	return null


# Repeats are WEIGHT, so a 2-Fire circle asks for two Fire and the row carries the count rather than a
# deficit -- the deficit and the surplus are both derived from it, and a stored deficit could not say
# which ticks a halo belongs on.
func test_a_carving_asks_sector_by_sector_and_repeats_are_weight() -> void:
	var celest := _alchemist([EARTH, FIRE, AETHER], {FIRE: 2, EARTH: 1, AETHER: 2})
	var circle := _circle([FIRE, FIRE, EARTH])

	assert_int(_demand_row(celest, circle, FIRE).wanted).is_equal(2)
	assert_int(_demand_row(celest, circle, EARTH).wanted).is_equal(1)
	# Every sigil still gets a sector, asked for or not -- fixed positions are what make it learnable.
	assert_int(_demand_row(celest, circle, WATER).wanted).is_equal(0)
	assert_int(_demand_row(celest, circle, AETHER).wanted).is_equal(0)


# THE POOL IS UNTOUCHED BY THE DEMAND LAID OVER IT. A mutant that folded the recipe into `depth` --
# the tempting simplification, since the picture only ever shows their difference -- would render
# identically for a carrier who covers the recipe exactly and lie about everyone else.
func test_showing_a_carving_changes_nothing_about_the_pool_underneath() -> void:
	var celest := _alchemist([EARTH, FIRE, AETHER], {FIRE: 2, EARTH: 1, AETHER: 2})
	var plain := AuraRing.rows(celest)
	var over := AuraRing.rows(celest, _circle([FIRE, FIRE, EARTH]))

	assert_int(over.size()).is_equal(plain.size())
	for i in plain.size():
		assert_that(over[i].element).is_equal(plain[i].element)
		assert_bool(over[i].affine).is_equal(plain[i].affine)
		assert_int(over[i].depth).is_equal(plain[i].depth)


# A rune in the stash is held by NOBODY, and the honest answer there is the demand with nothing paid --
# not an empty model, which is what the old null contract gave. `rows(null)` on its own is still
# empty, unchanged: nothing to say about nobody, when nothing is being asked either.
func test_a_carving_with_no_carrier_is_still_a_model() -> void:
	var circle := _circle([WATER, WATER, AIR])
	var demanded := AuraRing.rows(null, circle)

	assert_int(demanded.size()).is_equal(Elemental.SIGIL_ELEMENTS.size())
	for row: AuraRing.Row in demanded:
		assert_int(row.depth).is_equal(0)
		assert_bool(row.affine).is_false()
	for row: AuraRing.Row in demanded:
		if row.element == WATER:
			assert_int(row.wanted).is_equal(2)
		if row.element == AIR:
			assert_int(row.wanted).is_equal(1)

	assert_array(AuraRing.rows(null)).is_empty()


# The ring explains the marks that are ON SCREEN and no others: a carrier who covers a recipe exactly
# sees neither sentence, because neither mark is drawn. A legend listing every state a widget CAN draw
# is how a readout starts describing a picture nobody is looking at.
func test_the_readout_names_only_the_marks_that_are_actually_drawn() -> void:
	var celest := _alchemist([EARTH, FIRE], {FIRE: 2, EARTH: 1})

	var exact := AuraRing.readout(celest, _circle([FIRE, FIRE, EARTH]))
	assert_int(exact.find("hollow")).is_equal(-1)
	assert_int(exact.find("halo")).is_equal(-1)

	# One Earth short of a 2-Earth circle, and one Fire past what it asks for.
	var lopsided := AuraRing.readout(celest, _circle([FIRE, EARTH, EARTH]))
	assert_int(lopsided.find("hollow")).is_greater(-1)
	assert_int(lopsided.find("halo")).is_greater(-1)

	# And no carving at all says nothing about either, which is every pre-#1019 surface.
	assert_int(AuraRing.readout(celest).find("hollow")).is_equal(-1)
	assert_int(AuraRing.readout(celest).find("halo")).is_equal(-1)


# A halo is drawn because surplus aura is DAMAGE -- base_damage sums the pool over every sigil and is
# uncapped. A utility carving suppresses that scaling outright (#126), so the same picture must not
# carry the same promise: the readout would be pledging a number the resolver never adds.
func test_a_utility_circles_surplus_promises_no_damage() -> void:
	var celest := _alchemist([FIRE], {FIRE: 3})
	assert_int(_flat(AuraRing.readout(celest, _circle([FIRE]))).find("is damage")).is_greater(-1)
	assert_int(_flat(AuraRing.readout(celest, _circle([FIRE], true))).find("is damage")).is_equal(-1)
	# ...and still says a halo is there, because one is.
	assert_int(_flat(AuraRing.readout(celest, _circle([FIRE], true))).find("halo")).is_greater(-1)


# UiText.wrap breaks a line wherever its width runs out, so a PHRASE is searched with the wrapping
# undone. Without this a case goes red because a sentence happened to break across two lines, which is
# a fact about the wrapper and not about the readout.
static func _flat(text: String) -> String:
	return text.replace("\n", " ")


# A HALO MAY NOT FUSE ITS SECTOR INTO ONE ARC -- the failure #930 already paid for once with the hover
# border, where a value that read correctly on the panel's 108px ring drew a solid ribbon on the
# card's 52px one.
#
# WHAT IS ASSERTED IS A DRAWABLE GAP, not a margin anybody chose. The first version of this case asked
# only that a haloed bar stay INSIDE the pitch, and the fuse ratio SURVIVED it: at 0.053 two halos
# stop 0.02px apart, which passes an overlap test and renders as one arc, because a gap thinner than a
# pixel is not a gap. One pixel is a fact about rasterising rather than a taste threshold, and it
# leaves the ratio a wide band to be re-tuned in -- which is the razor's own point.
#
# ONLY THE SIZES A DEMAND IS ACTUALLY DRAWN AT. The 52px pre-mission ring shows no carving and so
# draws no halo; if a hover tip ever adopts the demand at that size, this list is where it gets asked.
func test_a_halo_leaves_a_drawable_gap_at_every_size_that_shows_one() -> void:
	var sizes: Array[float] = [RuneDetailCard.RING_PX as float]
	for box: float in sizes:
		var outer := box * 0.5
		var inner := outer * (1.0 - AuraRing.BAND_RATIO)
		var mid := (inner + outer) * 0.5
		var width := maxf(2.0, mid * AuraRing.TICK_W_RATIO)
		var haloed := width + mid * AuraRing.HALO_SPREAD_RATIO * 2.0
		# The arc distance between two neighbouring ticks, measured where the bars actually sit.
		var pitch := mid * (AuraRing.SECTOR - AuraRing.SECTOR_PAD * 2.0) / float(AuraRing.MAX_TICKS)
		assert_float(pitch - haloed).override_failure_message(
			"two halos on a %.0fpx ring stop %.2fpx apart -- under a pixel, so the sector reads as "
			% [box, pitch - haloed] + "one arc").is_greater_equal(1.0)


# The off-recipe knock-back may NOT land on alpha: DIM_ALPHA and FAINT_ALPHA already spend that
# channel, so a sector that merely dimmed would read as "never grown" rather than as "not asked for" --
# and at a 5px tick the two are the same picture. The channel is the thing pinned, not the amount.
func test_an_off_recipe_sector_is_quieted_without_touching_its_alpha() -> void:
	var lit := ElementPalette.color_for_element(FIRE)
	assert_float(lit.s).override_failure_message(
		"this element has no saturation to lose, so the case proves nothing").is_greater(0.0)

	var quiet := AuraRing.knocked_back(lit)
	assert_float(quiet.a).is_equal(lit.a)
	assert_float(quiet.s).is_less(lit.s)


# --- the demand arc (#1022) -------------------------------------------------------------------------

func _demand_ring(target: Unit, demand: TransmutationData, box_px: float) -> AuraRing:
	var ring: AuraRing = auto_free(AuraRing.for_demand(target, null, box_px))
	add_child(ring)
	ring.size = Vector2(box_px, box_px)
	ring.set_carving(demand)
	await await_idle_frame()
	return ring


# THE ARC LIVES OUTSIDE THE BAND, so the band gives up room for it -- and ONLY when there is one to
# draw. A pad taken unconditionally would quietly shrink the pre-mission card's 52px wheel and the
# inspect panel's 108px one for a mark neither surface shows, which is the cost this conditional
# exists to refuse.
func test_only_a_ring_showing_a_demand_gives_up_room_for_the_arc() -> void:
	var celest := _alchemist([FIRE], {FIRE: 2})
	var plain := await _demand_ring(celest, null, 116.0)
	var asking := await _demand_ring(celest, _circle([FIRE]), 116.0)

	assert_float(plain._arc_room).override_failure_message(
		"a ring with no carving reserved room for an arc it will never draw").is_equal(0.0)
	assert_float(plain._outer).is_equal_approx(58.0, 0.01)
	assert_float(asking._outer).override_failure_message(
		"the band never gave up room, so the arc has nowhere to go but off the node"
		).is_less(plain._outer)


# ...and what it gives up has to be ENOUGH. Both bounds are arithmetic over the three ratios, so a
# re-tune that pushed the arc off the node or back into the ticks reds here rather than in a
# screenshot -- which is the half a headless suite genuinely can answer about a mark it cannot see.
func test_the_demand_arc_clears_the_band_and_stays_inside_the_node() -> void:
	var box := float(RuneDetailCard.RING_PX)
	var half := box * 0.5
	var outer := half - half * AuraRing.ARC_PAD_RATIO
	var radius := outer + half * AuraRing.ARC_GAP_RATIO
	var reach := maxf(1.5, half * AuraRing.ARC_WIDTH_RATIO) * 0.5

	assert_float(radius + reach).override_failure_message(
		"the arc's outer edge lands %.2fpx past the node's own rim and would be clipped"
		% [(radius + reach) - half]).is_less_equal(half)
	assert_float(radius - reach).override_failure_message(
		"the arc's inner edge reaches back into the tick band, so the cost overlaps what is paid"
		).is_greater(outer)
