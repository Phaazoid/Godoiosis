# The rune card's aura line (#1319): AuraRing's model drawn as one row of ticks above the plate, with
# a carving's demand laid over the pool.
#
# WHAT IS PINNED is the tick rule (tick_state, pure, so the hollow and halo decisions are no longer
# invisible to the suite the way they were inside the ring's _draw), the arithmetic that keeps two
# halos apart, and that the line fits the card. WHAT IS NOT: the pixels -- that a hollow tick reads as
# empty, that the underline reads as "asked for". Those are the dev's to look at.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const FIRE := Elemental.Element.FIRE
const WATER := Elemental.Element.WATER
const EARTH := Elemental.Element.EARTH
const AETHER := Elemental.Element.AETHER

const T := AuraLine.Tick

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _alchemist(order: Array[Elemental.Element], aura: Dictionary[Elemental.Element, int]) -> Unit:
	var u: Unit = H.spawn_solo(self, _sm, Team.Faction.PLAYER, Vector2i.ZERO, {}, false)
	u.unit_instance.affinity = order.duplicate()
	u.unit_instance.aura = aura.duplicate()
	return u


func _circle(recipe: String) -> TransmutationData:
	var carving := TransmutationData.new()
	carving.recipe = recipe
	return carving


func _row(depth: int, wanted: int, scales: bool, affine := true) -> AuraRing.Row:
	var row := AuraRing.Row.new()
	row.element = FIRE
	row.depth = depth
	row.wanted = wanted
	row.scales = scales
	row.affine = affine
	return row


static func _ticks(row: AuraRing.Row) -> Array:
	var out := []
	for k in AuraRing.MAX_TICKS:
		out.append(AuraLine.tick_state(row, k))
	return out


static func _model_row(model: Array[AuraRing.Row], element: Elemental.Element) -> AuraRing.Row:
	for row: AuraRing.Row in model:
		if row.element == element:
			return row
	return null


# --- the tick rule ---------------------------------------------------------------------------------

# Fire 3 against a recipe asking Fire 2, in an element the hit scales off: two paid, one spare (damage,
# so it wears a halo), then the affinity's empty room.
func test_a_point_held_past_the_recipe_is_spare() -> void:
	assert_array(_ticks(_row(3, 2, true))).is_equal([T.HELD, T.HELD, T.SPARE, T.AFFINE, T.AFFINE])


# Fire 1 against Fire 3: one paid, two hollow, and the room past what is asked stays dim.
func test_an_asked_point_not_held_is_hollow() -> void:
	assert_array(_ticks(_row(1, 3, true))).is_equal([T.HELD, T.ASKED, T.ASKED, T.AFFINE, T.AFFINE])


# A SPARE TICK IS DAMAGE, and only where the hit scales: this recipe spends its Fire freeing an earth
# atom and delivers Earth, so the Fire held past it buys nothing and is merely held. Read through the
# real model, since `scales` is the carving's answer (damage_elements), not a flag the case sets.
func test_aura_past_an_element_the_recipe_only_spends_is_not_spare() -> void:
	var celest := _alchemist([EARTH, FIRE], {FIRE: 2, EARTH: 1})
	var fire := _model_row(AuraRing.rows(celest, _circle("Break(F, E) + Push(E2)")), FIRE)
	assert_int(fire.wanted).override_failure_message(
		"fixture: the recipe should ask one Fire, so the second is past it").is_equal(1)

	assert_array(_ticks(fire)).override_failure_message(
		"aura in an element the hit never scales off was drawn as damage"
	).is_equal([T.HELD, T.HELD, T.AFFINE, T.AFFINE, T.AFFINE])


func test_with_no_carving_shown_nothing_is_asked_or_spare() -> void:
	var celest := _alchemist([EARTH, FIRE, AETHER], {FIRE: 3, EARTH: 1})
	for row: AuraRing.Row in AuraRing.rows(celest):
		for tick: AuraLine.Tick in _ticks(row):
			assert_bool(tick == T.ASKED or tick == T.SPARE).override_failure_message(
				"a demand mark was drawn with no carving shown").is_false()


# A rune in the stash: nobody holds anything, so the asked ticks are hollow and the rest is grey.
func test_a_rune_nobody_holds_reads_as_pure_demand() -> void:
	var model := AuraRing.rows(null, _circle("Push(W2)"))
	assert_array(_ticks(_model_row(model, WATER))).is_equal(
		[T.ASKED, T.ASKED, T.NEVER, T.NEVER, T.NEVER])
	assert_array(_ticks(_model_row(model, FIRE))).is_equal(
		[T.NEVER, T.NEVER, T.NEVER, T.NEVER, T.NEVER])


# --- the marks' arithmetic -------------------------------------------------------------------------

# TWO SPARE TICKS SIDE BY SIDE MUST NOT FUSE into one block -- #930's failure, which the ring paid for
# with its hover border. A gap thinner than a pixel is not a gap, so one pixel is the floor.
func test_two_halos_side_by_side_keep_a_drawable_gap() -> void:
	assert_float(AuraLine.GAP - AuraLine.HALO_GROW * 2.0).override_failure_message(
		"two neighbouring halos stop under a pixel apart, so a run of spare ticks reads as one block"
	).is_greater_equal(1.0)


# The off-recipe knock-back may NOT land on alpha: DIM_ALPHA and FAINT_ALPHA already spend that channel,
# so an element that merely dimmed would read as "never grown" rather than as "not asked for".
func test_an_off_recipe_element_is_quieted_without_touching_its_alpha() -> void:
	var lit := ElementPalette.color_for_element(FIRE)
	assert_float(lit.s).override_failure_message(
		"this element has no saturation to lose, so the case proves nothing").is_greater(0.0)

	var quiet := AuraLine.knocked_back(lit)
	assert_float(quiet.a).is_equal(lit.a)
	assert_float(quiet.s).is_less(lit.s)


# --- the widget ------------------------------------------------------------------------------------

func _line(target: Unit, demand: TransmutationData) -> AuraLine:
	var line: AuraLine = auto_free(AuraLine.for_carrier(target))
	add_child(line)
	line.set_carving(demand)
	await await_idle_frame()
	return line


# Five names and twenty-five ticks across the card: it must ask for room, and no more than the card has.
func test_the_line_asks_for_room_and_fits_the_card() -> void:
	var celest := _alchemist([EARTH, FIRE], {FIRE: 2, EARTH: 1})
	var held := await _line(celest, _circle("Push(F2)"))
	var stash := await _line(null, _circle("Push(F2)"))
	for line: AuraLine in [held, stash]:
		var wide := line.get_combined_minimum_size().x
		assert_float(wide).override_failure_message("the line asked for no width at all").is_greater(0.0)
		assert_float(wide).override_failure_message(
			"the line wants %.0fpx, wider than the card's %d" % [wide, RuneDetailCard.CARD_W]
		).is_less_equal(float(RuneDetailCard.CARD_W))


# The tooltip is the model's own sentence, so the ring's surfaces and this line word it once.
func test_the_tooltip_is_the_models_readout() -> void:
	var celest := _alchemist([FIRE], {FIRE: 1})
	var circle := _circle("Push(F2)")
	var line := await _line(celest, circle)
	assert_str(line.tooltip_text).is_equal(AuraRing.readout(celest, circle))
	assert_str(line.tooltip_text).override_failure_message(
		"fixture: one Fire short should explain the hollow mark").contains("hollow")


# Nobody holding it and nothing carved: the model is empty, so there is nothing to draw.
func test_an_empty_model_hides_the_line() -> void:
	var line := await _line(null, null)
	assert_bool(line.visible).is_false()
