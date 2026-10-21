# The air's reading (#1324): what a recipe draws from the air (CarvingRecipe.drawn_from), how many
# steps a percentage is from Normal (Atmosphere.steps_of), and that the resolver moves a carving's
# damage by exactly those steps. Canon: docs/design/deep-alchemy.md -> What is built.
#
# Recipes are literal strings over the library's substances, never an authored carving (tests/README.md
# rule 9), and every expectation is derived from Atmosphere.NORMAL and STEP rather than retyped, so a
# retune never reds this suite (rule 8).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const HERE := Vector2i(8, 8)
const FOE_CELL := Vector2i(9, 8)
const FIREBALL := "Break(F, A) + Push(F2)"

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _drawn(recipe: String) -> Array[String]:
	var parsed := CarvingRecipe.parse(recipe)
	assert_str(parsed.error).override_failure_message("fixture recipe '%s' does not parse: %s"
			% [recipe, parsed.error]).is_empty()
	return parsed.drawn_from(Atmosphere.SUBSTANCES)


# --- what a recipe draws from the air -----------------------------------------------------

# Zap Cannon's shape: the Break makes the heat the Bind needs, so only the vital air and the aether
# come from the air.
func test_a_need_an_earlier_step_made_is_not_drawn_from_the_air() -> void:
	assert_array(_drawn("Break(F, A) + Bind(Q, F) + Push(QF)")) \
		.contains_exactly_in_any_order(["vital_air", "atom_aether"])


func test_a_need_a_source_supplies_is_not_drawn_from_the_air() -> void:
	assert_array(_drawn("Focus(W2) + Push(W2)")).is_empty()


# The air holds one of anything (#1328), so a need of more is a real source's and the reading does not
# scale it -- even of a substance the air holds.
func test_a_need_of_more_than_one_is_not_drawn_from_the_air() -> void:
	assert_array(_drawn("Push(A2)")).contains_exactly(["inert_air"])
	assert_array(_drawn("Push(3A2)")).is_empty()
	assert_array(_drawn("Break(3F, 3A) + Push(F2)")).is_empty()


func test_a_substance_drawn_twice_counts_once() -> void:
	assert_array(_drawn("Bind(Q, Q)")).contains_exactly(["atom_aether"])


# --- steps --------------------------------------------------------------------------------

func test_a_missing_key_reads_normal() -> void:
	var none: Dictionary[String, int] = {}
	for id: String in Atmosphere.SUBSTANCES:
		assert_int(Atmosphere.percent_of(id, none)).is_equal(int(Atmosphere.NORMAL[id]))
		assert_int(Atmosphere.steps_of(id, none)).is_equal(0)
	assert_bool(Atmosphere.is_normal(none)).is_true()


func test_a_step_counts_whole_steps_toward_zero_on_both_sides() -> void:
	for id: String in Atmosphere.SUBSTANCES:
		var normal := int(Atmosphere.NORMAL[id])
		var step := int(Atmosphere.STEP[id])
		assert_int(Atmosphere.steps_of(id, {id: normal + step})).override_failure_message(
				"%s one step up" % id).is_equal(1)
		assert_int(Atmosphere.steps_of(id, {id: normal + 2 * step})).is_equal(2)
		if step > 1:
			assert_int(Atmosphere.steps_of(id, {id: normal + step - 1})).override_failure_message(
					"%s just short of a step read as one" % id).is_equal(0)
			if normal >= step - 1:
				assert_int(Atmosphere.steps_of(id, {id: normal - step + 1})).is_equal(0)
		if normal >= step:
			assert_int(Atmosphere.steps_of(id, {id: normal - step})).override_failure_message(
					"%s one step down" % id).is_equal(-1)


# off_normal is what the corner HUD lists, and is_normal is derived from it: off Normal is any
# percent but Normal's own, a step or not, in SUBSTANCES order.
func test_off_normal_names_every_substance_off_its_normal_percent_in_order() -> void:
	var reading: Dictionary[String, int] = {}
	var expected: Array[String] = []
	for i in range(Atmosphere.SUBSTANCES.size() - 1, -1, -1):   # authored back to front
		var id: String = Atmosphere.SUBSTANCES[i]
		if i % 2 == 0:
			reading[id] = int(Atmosphere.NORMAL[id]) + 1
			expected.push_front(id)
	assert_array(Atmosphere.off_normal(reading)).contains_exactly(expected)
	assert_bool(Atmosphere.is_normal(reading)).is_false()

	var at_normal: Dictionary[String, int] = {}
	for id: String in Atmosphere.SUBSTANCES:
		at_normal[id] = int(Atmosphere.NORMAL[id])   # stored, but at Normal
	assert_array(Atmosphere.off_normal(at_normal)).is_empty()
	assert_bool(Atmosphere.is_normal(at_normal)).is_true()


func test_a_reading_words_its_percent_and_signs_its_steps_and_drops_a_zero() -> void:
	for id: String in Atmosphere.SUBSTANCES:
		var normal := int(Atmosphere.NORMAL[id])
		var step := int(Atmosphere.STEP[id])
		assert_str(Atmosphere.percent_text(id, {id: normal + 2 * step})).is_equal("%d%%" % (normal + 2 * step))
		assert_str(Atmosphere.steps_text(id, {id: normal + 2 * step})).is_equal("+2")
		assert_str(Atmosphere.steps_text(id, {})).override_failure_message(
				"%s at Normal still printed a step" % id).is_empty()
		if normal >= step:
			assert_str(Atmosphere.steps_text(id, {id: normal - step})).is_equal("-1")


# Every ambient substance names a real file and has a Normal and a step.
func test_every_ambient_substance_is_real_and_tuned() -> void:
	var real := SubstanceCatalog.get_all()
	for id: String in Atmosphere.SUBSTANCES:
		assert_bool(real.has(id)).override_failure_message("'%s' names no substance file" % id).is_true()
		assert_bool(Atmosphere.NORMAL.has(id) and Atmosphere.STEP.has(id)).override_failure_message(
				"'%s' has no Normal or step" % id).is_true()
		assert_int(int(Atmosphere.STEP[id])).is_greater(0)
	var grouped: Array[String] = []
	for group: String in Atmosphere.GROUPS:
		for id: String in Atmosphere.GROUPS[group]:
			grouped.append(id)
	assert_array(grouped).contains_exactly_in_any_order(Atmosphere.SUBSTANCES)


# --- the weather's nudge (#1324) ----------------------------------------------------------
# Which weather moves what, and by how much, is AUTHORED (Resources/WeatherRules/), so these read every
# expectation off WeatherRules.air_of and never name a weather's number.

func test_a_nudge_adds_its_points_and_holds_each_substance_to_0_100() -> void:
	for id: String in Atmosphere.SUBSTANCES:
		var normal := int(Atmosphere.NORMAL[id])
		var step := int(Atmosphere.STEP[id])
		assert_int(Atmosphere.percent_of(id, Atmosphere.nudged({}, {id: step}))).override_failure_message(
				"%s did not rise by its nudge" % id).is_equal(normal + step)
		assert_int(Atmosphere.percent_of(id, Atmosphere.nudged({}, {id: -(normal + 1)}))).override_failure_message(
				"%s fell below 0%%" % id).is_equal(0)
		assert_int(Atmosphere.percent_of(id, Atmosphere.nudged({}, {id: 101}))).override_failure_message(
				"%s rose above 100%%" % id).is_equal(100)
	# A substance the nudge does not name keeps what was authored.
	var first: String = Atmosphere.SUBSTANCES[0]
	var last: String = Atmosphere.SUBSTANCES[-1]
	var authored: Dictionary[String, int] = {first: int(Atmosphere.NORMAL[first]) + int(Atmosphere.STEP[first])}
	assert_int(Atmosphere.percent_of(first, Atmosphere.nudged(authored, {last: 1}))).is_equal(authored[first])


func test_a_weather_with_no_rules_leaves_the_authored_reading_alone() -> void:
	var authored := _rich(Atmosphere.SUBSTANCES[0], 2)
	assert_object(WeatherRules.for_kind(Weather.Kind.CLEAR)).override_failure_message(
			"fixture: CLEAR has a rules file now").is_null()
	assert_dict(Atmosphere.effective(authored, Weather.Kind.CLEAR)).is_equal(authored)


# Every authored nudge, against an authored reading a step off Normal everywhere: the composition adds
# exactly the weather's points, clamped, and leaves every other substance alone.
func test_every_weather_moves_the_air_by_exactly_its_authored_nudge() -> void:
	var authored: Dictionary[String, int] = {}
	for id: String in Atmosphere.SUBSTANCES:
		authored[id] = int(Atmosphere.NORMAL[id]) + int(Atmosphere.STEP[id])
	var moving := 0
	for kind: Weather.Kind in Weather.Kind.values():
		var nudge := WeatherRules.air_of(kind)
		if not nudge.is_empty():
			moving += 1
		for id: String in nudge:
			assert_bool(Atmosphere.SUBSTANCES.has(id)).override_failure_message(
					"%s's rules nudge '%s', which is not in the air" % [Weather.name_of(kind), id]).is_true()
		var air := Atmosphere.effective(authored, kind)
		for id: String in Atmosphere.SUBSTANCES:
			var expected := clampi(authored[id] + int(nudge.get(id, 0)), 0, 100)
			assert_int(Atmosphere.percent_of(id, air)).override_failure_message("%s left %s at %d, not %d"
					% [Weather.name_of(kind), id, Atmosphere.percent_of(id, air), expected]).is_equal(expected)
	assert_int(moving).override_failure_message(
			"no weather's rules move the air, so nothing here is checked").is_greater(0)


func test_a_weather_names_exactly_what_it_moves_and_says_which_way() -> void:
	for kind: Weather.Kind in Weather.Kind.values():
		var nudge := WeatherRules.air_of(kind)
		var moved := 0
		for id: String in Atmosphere.SUBSTANCES:
			var points := int(nudge.get(id, 0))
			if points != 0:
				moved += 1
			assert_bool(Atmosphere.weather_moves(id, kind)).override_failure_message(
					"%s and %s" % [Weather.name_of(kind), id]).is_equal(points != 0)
			var text := Atmosphere.weather_text(id, kind)
			if points == 0:
				assert_str(text).is_empty()
				continue
			assert_str(text).starts_with(Weather.display_name(kind))
			assert_str(text).contains("%d%%" % absi(points))
			assert_str(text).contains(SubstanceCatalog.name_of(id).to_lower())
			assert_str(text).contains("adds" if points > 0 else "lowers")
		assert_int(Atmosphere.weather_lines(kind).size()).is_equal(moved)


# --- through the resolver -----------------------------------------------------------------

func _carving(recipe: String, no_damage := false) -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = "Air Test"
	t.power = 5
	t.targets = EquippableData.TargetMode.BOTH
	t.recipe = recipe
	t.deals_no_damage = no_damage
	return t


func _alchemist(carving: TransmutationData) -> Unit:
	var u := H.spawn_solo(self, _sm, PLAYER, HERE, { Stats.Stat.MHP: 60 }, false)
	var aura: Dictionary[Elemental.Element, int] = {}
	var affinity: Array[Elemental.Element] = []
	for e: Elemental.Element in carving.distinct_elements():
		aura[e] = 6
		affinity.append(e)
	u.unit_instance.aura = aura
	u.unit_instance.affinity = affinity
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	assert_bool(rune.inscribe(carving)).override_failure_message("fixture carving failed to inscribe").is_true()
	u.equipped_weapon = rune
	assert_bool(u.is_attack_fireable(carving)).override_failure_message(
			"fixture: the carving must be channelable").is_true()
	return u


# One aim at a foe, resolved on a board whose air reads `reading`; the hit's outcome.
func _resolve(caster: Unit, carving: TransmutationData, foe: Unit, reading: Dictionary[String, int]) -> ResolvedOutcome:
	caster.squad._clear_all_actions()
	caster.active_attack = carving
	var aim := AttackAction.declare(caster, caster.get_projected_destination(), foe.movement.cell)
	caster.active_attack = null
	caster.squad._queue_action(aim)
	_sm.active_squad = caster.squad
	var board: BoardContext = _sm.board_source.call()
	board.atmosphere = reading
	var plan := _sm.resolve_plan(caster.squad, board, ReactionCatalog.get_all())
	assert_int(plan.attacks.size()).override_failure_message("the aim was not expanded").is_equal(1)
	var outcome: ResolvedOutcome = plan.attacks[0].resolved
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for ctr in plan.counters:
		ctr.volley = empty
	return outcome


func _rich(id: String, steps: int) -> Dictionary[String, int]:
	var reading: Dictionary[String, int] = {}
	reading[id] = int(Atmosphere.NORMAL[id]) + steps * int(Atmosphere.STEP[id])
	return reading


func test_richer_air_moves_a_carving_by_exactly_its_steps() -> void:
	var carving := _carving(FIREBALL)
	var caster := _alchemist(carving)
	var foe := H.spawn_solo(self, _sm, ENEMY, FOE_CELL, { Stats.Stat.MHP: 60 })
	var none: Dictionary[String, int] = {}
	var normal := _resolve(caster, carving, foe, none)
	var rich := _resolve(caster, carving, foe, _rich("vital_air", 2))
	assert_int(rich.base_damage - normal.base_damage).override_failure_message(
			"two steps of vital air did not add two to a carving that breaks it").is_equal(2)
	assert_int(rich.air_steps.size()).is_equal(1)
	assert_int(rich.air_steps.get("vital_air", 0)).is_equal(2)
	assert_int(normal.air_steps.size()).is_equal(0)
	var thin := _resolve(caster, carving, foe, _rich("vital_air", -1))
	assert_int(normal.base_damage - thin.base_damage).is_equal(1)


# Air the recipe never draws on moves nothing: a fire carving ignores the vapor.
func test_air_a_recipe_does_not_draw_moves_nothing() -> void:
	var carving := _carving(FIREBALL)
	var caster := _alchemist(carving)
	var foe := H.spawn_solo(self, _sm, ENEMY, FOE_CELL, { Stats.Stat.MHP: 60 })
	var none: Dictionary[String, int] = {}
	var normal := _resolve(caster, carving, foe, none)
	var humid := _resolve(caster, carving, foe, _rich("vapor", 3))
	assert_int(humid.base_damage).is_equal(normal.base_damage)
	assert_int(humid.air_steps.size()).is_equal(0)


func test_a_damageless_carving_stays_at_zero_in_any_air() -> void:
	var carving := _carving(FIREBALL, true)
	var caster := _alchemist(carving)
	var foe := H.spawn_solo(self, _sm, ENEMY, FOE_CELL, { Stats.Stat.MHP: 60 })
	var rich := _resolve(caster, carving, foe, _rich("vital_air", 3))
	assert_int(rich.base_damage).is_equal(0)
	assert_int(rich.air_steps.size()).is_equal(0)


func test_thin_air_never_takes_a_carving_below_zero() -> void:
	var carving := _carving(FIREBALL)
	var caster := _alchemist(carving)
	assert_int(carving.base_damage(caster, [], -1000)).is_equal(0)


# The vial burns only when IT changed the answer, so the air has to sit on both sides of that compare:
# a vial in an element the carving does not deliver changes nothing, rich air or not.
func test_the_air_alone_never_burns_a_vial() -> void:
	var carving := _carving(FIREBALL)
	var caster := _alchemist(carving)
	var foe := H.spawn_solo(self, _sm, ENEMY, FOE_CELL, { Stats.Stat.MHP: 60 })
	caster.attunement = _vial(Elemental.Element.FIRE)
	assert_object(_resolve(caster, carving, foe, _rich("vital_air", 2)).burned_vial).override_failure_message(
			"fixture: a matching vial should burn, or the case below proves nothing").is_not_null()
	caster.attunement = _vial(Elemental.Element.WATER)
	assert_object(_resolve(caster, carving, foe, _rich("vital_air", 2)).burned_vial).override_failure_message(
			"the air's bonus was counted on one side of the vial's compare").is_null()


func _vial(element: Elemental.Element) -> VialData:
	var vial := VialData.new()
	vial.display_name = "Test Vial"
	vial.element = element
	return vial
