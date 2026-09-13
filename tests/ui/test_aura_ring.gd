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
	var ring: AuraRing = auto_free(AuraRing.standing(celest, 160.0))
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
	var ring: AuraRing = auto_free(AuraRing.standing(celest, 160.0))
	assert_that(ring.hovered).is_equal(Elemental.Element.NONE)

	var angle := AuraRing.ARC_START + 3.5 * AuraRing.SECTOR   # sector 3 is AETHER
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(80, 80) + Vector2(cos(angle), sin(angle)) * 60.0
	ring._gui_input(motion)
	assert_that(ring.hovered).is_equal(AETHER)

	motion.position = Vector2(80, 80)
	ring._gui_input(motion)
	assert_that(ring.hovered).is_equal(Elemental.Element.NONE)


# --- the ink box ---------------------------------------------------------------------------------

# MapSpriteInk is a MOVE, not a rewrite: the deployed-force strip's offset was (-4, -11) before #930
# and must still be, or hoisting the measurement silently nudged a shipped surface. Provenance pinned
# against the constant's own consumer rather than against a retyped number (#814's technique).
func test_the_hoisted_ink_box_still_centres_the_deployed_strips_sprite() -> void:
	assert_that(MapSpriteInk.window_offset(PreMissionScreen.RING_WINDOW)).is_equal(Vector2(-4, -11))


# A ring centred on the sprite's BOX would sit a third of the box above the character, because every
# map sprite draws its ink in the lower half. This is the arithmetic that says so.
func test_the_ink_centre_sits_well_below_the_canvas_centre() -> void:
	var box := 52.0
	assert_float(MapSpriteInk.ink_centre(box).y).is_greater(box * 0.5 + 8.0)
	assert_float(MapSpriteInk.ink_centre(box).x).is_equal_approx(box * 0.5, 1.0)


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

	var stats: VBoxContainer = panel.get_node("UnitInfoPanel/Margin/VBox/StatsSection")
	var ring: AuraRing = stats.aura_row.get_child(0)
	assert_object(ring).is_not_null()
	assert_bool(ring.visible).is_true()
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


# The other half of "a section hides with its rows": Rebecca gets the sentence, not a wheel of nothing.
func test_the_panel_swaps_the_wheel_for_a_sentence_when_there_is_no_affinity() -> void:
	var rebecca := _alchemist([], {})
	var panel: Control = auto_free((load(PANEL_SCENE) as PackedScene).instantiate())
	add_child(panel)
	await await_idle_frame()
	panel.set_unit(rebecca)
	await await_idle_frame()

	var stats: VBoxContainer = panel.get_node("UnitInfoPanel/Margin/VBox/StatsSection")
	var ring: AuraRing = stats.aura_row.get_child(0)
	assert_bool(ring.visible).is_false()
	assert_bool(stats.aura_row.get_child(1).visible).is_true()
