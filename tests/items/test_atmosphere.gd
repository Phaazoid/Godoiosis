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

# A recipe that draws each ambient substance from the air and nothing else (#1324's local air): literal
# strings, checked by test_each_draws_recipe_draws_exactly_its_substance.
const DRAWS: Dictionary[String, String] = {
	"inert_air": "Push(A2)",
	"vital_air": FIREBALL,
	"vapor": "Break(A, W) + Push(W2)",
	"atom_fire": "Push(F)",
	"atom_aether": "Bind(Q, Q)",
}

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


# --- a gas moves the air where it lies (#1324) ---------------------------------------------
# What a gas does to the air is AUTHORED (Resources/GasRules/), so every expectation is read off
# GasRules.for_kind and no gas's number is named here.

# Every kind whose rules move the air; failing loudly when none does, since every case below would be
# vacuous.
func _air_gases() -> Array[Gas.Kind]:
	var out: Array[Gas.Kind] = []
	for kind: Gas.Kind in Gas.Kind.values():
		var rules := GasRules.for_kind(kind)
		if rules != null and not rules.air.is_empty():
			out.append(kind)
	assert_array(out).override_failure_message("no gas's rules move the air, so nothing here is checked").is_not_empty()
	return out


func _board_with(field: GasField) -> BoardContext:
	var no_units: Array[Unit] = []
	return BoardContext.new(null, no_units, null, null, null, null, field)


func _expected(id: String, base: Dictionary, nudge: Dictionary) -> int:
	return clampi(Atmosphere.percent_of(id, base) + int(nudge.get(id, 0)), 0, 100)


func test_each_draws_recipe_draws_exactly_its_substance() -> void:
	for id: String in Atmosphere.SUBSTANCES:
		assert_bool(DRAWS.has(id)).override_failure_message("DRAWS has no recipe for %s" % id).is_true()
		assert_array(_drawn(DRAWS[id])).contains_exactly([id])


func test_every_gas_moves_its_own_cell_by_its_air_times_its_level_and_no_other() -> void:
	var beside := HERE + Vector2i.RIGHT
	for kind: Gas.Kind in _air_gases():
		var air := GasRules.for_kind(kind).air
		for id: String in air:
			assert_bool(Atmosphere.SUBSTANCES.has(id)).override_failure_message(
					"%s's rules move '%s', which is not in the air" % [Gas.name_of(kind), id]).is_true()
		for level: int in [Gas.Level.THIN, Gas.Level.MEDIUM, Gas.Level.THICK]:
			var field := GasField.new()
			field.set_level(HERE, kind, level)
			var board := _board_with(field)
			var here := board.air_at(HERE)
			for id: String in Atmosphere.SUBSTANCES:
				assert_int(Atmosphere.percent_of(id, here)).override_failure_message("%s at level %d left %s at %d"
						% [Gas.name_of(kind), level, id, Atmosphere.percent_of(id, here)]) \
						.is_equal(clampi(int(Atmosphere.NORMAL[id]) + int(air.get(id, 0)) * level, 0, 100))
			assert_dict(board.air_at(beside)).override_failure_message(
					"%s moved the air of a cell it does not lie on" % Gas.name_of(kind)).is_equal(board.atmosphere)


# The dev ruled the feature needs a gas that SUBTRACTS (#1324): both directions must be exercised.
func test_some_gas_raises_the_air_and_some_lowers_it() -> void:
	var raises := false
	var lowers := false
	for kind: Gas.Kind in _air_gases():
		for id: String in GasRules.for_kind(kind).air:
			raises = raises or GasRules.for_kind(kind).air[id] > 0
			lowers = lowers or GasRules.for_kind(kind).air[id] < 0
	assert_bool(raises).override_failure_message("no gas raises the air, so the raising half is unchecked").is_true()
	assert_bool(lowers).override_failure_message("no gas lowers the air, so the subtracting half is unchecked").is_true()


# A gas MADE of an ambient substance (SubstanceMap.GASES, what it is) raises that substance where it
# lies, and touches nobody (#1427): heat haze is free heat, and released heat moves damage, never
# presence (Phaazoid@, 2026-10-14) -- no state, no damage, nothing held while standing.
func test_a_gas_made_of_an_ambient_substance_raises_it_and_touches_nobody() -> void:
	var found := 0
	for kind: Gas.Kind in Gas.Kind.values():
		var id := SubstanceMap.of_gas(kind)
		if not Atmosphere.SUBSTANCES.has(id):
			continue
		found += 1
		var rules := GasRules.for_kind(kind)
		assert_object(rules).override_failure_message("%s is %s, which is in the air, and has no rules to raise it"
				% [Gas.name_of(kind), id]).is_not_null()
		if rules == null:
			continue
		assert_int(int(rules.air.get(id, 0))).override_failure_message(
				"%s is %s and does not raise it where it lies" % [Gas.name_of(kind), id]).is_greater(0)
		assert_int(rules.state).override_failure_message("%s gives a state" % Gas.name_of(kind)).is_equal(Elemental.State.NONE)
		assert_dict(rules.damage).override_failure_message("%s deals damage" % Gas.name_of(kind)).is_empty()
		assert_bool(rules.while_standing).override_failure_message("%s holds a unit standing in it"
				% Gas.name_of(kind)).is_false()
	assert_int(found).override_failure_message(
			"fixture: no gas is made of an ambient substance, so nothing here is checked").is_greater(0)


func test_two_gases_on_one_cell_add_up() -> void:
	var kinds := _air_gases()
	assert_int(kinds.size()).override_failure_message("fixture: fewer than two gases move the air").is_greater_equal(2)
	var field := GasField.new()
	field.set_level(HERE, kinds[0], Gas.Level.THIN)
	field.set_level(HERE, kinds[1], Gas.Level.THIN)
	var here := _board_with(field).air_at(HERE)
	for id: String in Atmosphere.SUBSTANCES:
		var sum := int(GasRules.for_kind(kinds[0]).air.get(id, 0)) + int(GasRules.for_kind(kinds[1]).air.get(id, 0))
		assert_int(Atmosphere.percent_of(id, here)).is_equal(clampi(int(Atmosphere.NORMAL[id]) + sum, 0, 100))


# A cell starts from what the board plays under (BoardContext.atmosphere: authored + weather), never
# from Normal, and still holds 0..100 at both ends.
func test_a_cell_starts_from_the_boards_own_reading_and_stays_within_0_100() -> void:
	for kind: Gas.Kind in _air_gases():
		var field := GasField.new()
		field.set_level(HERE, kind, Gas.Level.THICK)
		var nudge := GasRules.air_of(field.packed_at(HERE))
		for base: Dictionary[String, int] in [_rich(Atmosphere.SUBSTANCES[0], 1), _all_at(0), _all_at(100)]:
			var board := _board_with(field)
			board.atmosphere = base
			var here := board.air_at(HERE)
			for id: String in Atmosphere.SUBSTANCES:
				assert_int(Atmosphere.percent_of(id, here)).is_equal(_expected(id, base, nudge))


func _all_at(percent: int) -> Dictionary[String, int]:
	var reading: Dictionary[String, int] = {}
	for id: String in Atmosphere.SUBSTANCES:
		reading[id] = percent
	return reading


func test_no_gas_field_or_a_gas_that_moves_nothing_reads_the_board() -> void:
	var board := _board_with(null)
	board.atmosphere = _rich("vapor", 2)
	assert_dict(board.air_at(HERE)).is_equal(board.atmosphere)
	var still: Array[Gas.Kind] = []
	for kind: Gas.Kind in Gas.Kind.values():
		var rules := GasRules.for_kind(kind)
		if rules == null or rules.air.is_empty():
			still.append(kind)
	assert_array(still).override_failure_message("fixture: every gas moves the air now").is_not_empty()
	for kind: Gas.Kind in still:
		var field := GasField.new()
		field.set_level(HERE, kind, Gas.Level.THICK)
		var gassy := _board_with(field)
		gassy.atmosphere = board.atmosphere
		assert_dict(gassy.air_at(HERE)).override_failure_message(
				"%s has no air rule and moved the air" % Gas.name_of(kind)).is_equal(board.atmosphere)


func test_the_board_names_what_a_cell_differs_in() -> void:
	var kind: Gas.Kind = _air_gases()[0]
	var field := GasField.new()
	field.set_level(HERE, kind, Gas.Level.THICK)
	var board := _board_with(field)
	var moved: Array[String] = []
	for id: String in Atmosphere.SUBSTANCES:
		if Atmosphere.percent_of(id, board.air_at(HERE)) != Atmosphere.percent_of(id, board.atmosphere):
			moved.append(id)
	assert_array(moved).override_failure_message("fixture: a thick %s moves nothing on a Normal board"
			% Gas.name_of(kind)).is_not_empty()
	assert_array(Atmosphere.differs(board.air_at(HERE), board.atmosphere)).is_equal(moved)
	assert_array(Atmosphere.differs(board.atmosphere, board.atmosphere)).is_empty()


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


# One aim at a foe, resolved on a board whose air reads `reading` (and whose gas is `gas`, #1324's local
# air); the hit's outcome.
func _resolve(caster: Unit, carving: TransmutationData, foe: Unit, reading: Dictionary[String, int],
		gas: GasField = null) -> ResolvedOutcome:
	caster.squad._clear_all_actions()
	caster.active_attack = carving
	var aim := AttackAction.declare(caster, caster.get_projected_destination(), foe.movement.cell)
	caster.active_attack = null
	caster.squad._queue_action(aim)
	_sm.active_squad = caster.squad
	var board: BoardContext = _sm.board_source.call()
	board.atmosphere = reading
	board.gas = gas
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


# --- the air where the caster stands (#1324) ------------------------------------------------

func _gas_on(cell: Vector2i, kind: Gas.Kind, level: int) -> GasField:
	var field := GasField.new()
	field.set_level(cell, kind, level)
	return field


# Every gas, every substance it moves, the carving that draws that substance: cast from the gas's own
# cell against the same cast with the gas one cell over. Raising and lowering both run here.
func test_a_carving_draws_the_air_of_the_cell_its_caster_stands_on() -> void:
	var none: Dictionary[String, int] = {}
	var row := 0
	for kind: Gas.Kind in _air_gases():
		for id: String in GasRules.for_kind(kind).air:
			var origin := Vector2i(-12 + 4 * row, -10)
			row += 1
			var carving := _carving(DRAWS[id])
			var caster := _alchemist(carving)
			caster.movement.cell = origin
			var foe := H.spawn_solo(self, _sm, ENEMY, origin + Vector2i.RIGHT, { Stats.Stat.MHP: 60 })
			var here := _gas_on(origin, kind, Gas.Level.THICK)
			var expected := Atmosphere.steps_for(carving.parsed(), _board_with(here).air_at(origin))
			assert_dict(expected).override_failure_message("fixture: a thick %s does not move %s's draw"
					% [Gas.name_of(kind), id]).is_not_empty()
			var inside := _resolve(caster, carving, foe, none, here)
			var beside := _resolve(caster, carving, foe, none, _gas_on(origin + Vector2i.LEFT, kind, Gas.Level.THICK))
			assert_dict(inside.air_steps).override_failure_message("%s under the caster: air_steps %s, not %s"
					% [Gas.name_of(kind), inside.air_steps, expected]).is_equal(expected)
			assert_int(beside.air_steps.size()).override_failure_message(
					"%s one cell over moved the cast" % Gas.name_of(kind)).is_equal(0)
			assert_int(inside.base_damage - beside.base_damage).is_equal(Atmosphere.bonus_of(expected))


func _move(unit: Unit, to: Vector2i) -> MoveAction:
	var move := MoveAction.new()
	var path: Array[Vector2i] = [unit.movement.cell, to]
	move.init(unit, path, null)
	return move


# The cell a queued move ends on is the one cast from (the resolver's projected position), so walking
# into the gas counts and the cell walked out of does not.
func test_a_queued_move_into_the_gas_is_cast_from_there() -> void:
	var kind: Gas.Kind = _air_gases()[0]
	var id: String = GasRules.for_kind(kind).air.keys()[0]
	var carving := _carving(DRAWS[id])
	carving.max_range = 3
	var caster := _alchemist(carving)
	var foe := H.spawn_solo(self, _sm, ENEMY, FOE_CELL, { Stats.Stat.MHP: 60 })
	var into := HERE + Vector2i.DOWN
	var none: Dictionary[String, int] = {}
	var expected := Atmosphere.steps_for(carving.parsed(), _board_with(_gas_on(into, kind, Gas.Level.THICK)).air_at(into))
	assert_dict(expected).override_failure_message("fixture: a thick %s does not move this draw" % Gas.name_of(kind)).is_not_empty()
	for gas_cell: Vector2i in [into, HERE]:
		caster.squad._clear_all_actions()
		caster.squad._queue_action(_move(caster, into))
		caster.active_attack = carving
		var aim := AttackAction.declare(caster, caster.get_projected_destination(), foe.movement.cell)
		caster.active_attack = null
		caster.squad._queue_action(aim)
		_sm.active_squad = caster.squad
		var board: BoardContext = _sm.board_source.call()
		board.atmosphere = none
		board.gas = _gas_on(gas_cell, kind, Gas.Level.THICK)
		var plan := _sm.resolve_plan(caster.squad, board, ReactionCatalog.get_all())
		var outcome := _outcome_of(plan, caster)
		if gas_cell == into:
			assert_dict(outcome.air_steps).override_failure_message(
					"the gas on the cell the caster moves to did not reach the cast").is_equal(expected)
		else:
			assert_int(outcome.air_steps.size()).override_failure_message(
					"the gas on the cell the caster walks out of still reached the cast").is_equal(0)
		_break_volleys(plan)


func _outcome_of(plan: ResolvedPlan, actor: Unit) -> ResolvedOutcome:
	for atk in plan.attacks:
		if atk.actor == actor and atk.resolved != null:
			return atk.resolved
	assert_bool(false).override_failure_message("%s landed no attack" % actor.name).is_true()
	return null


func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for ctr in plan.counters:
		ctr.volley = empty


# The board as it stands: a gas this pass deposits is not there for a later cast in the same pass, the
# limit fizzle and empowerment declare. One squadmate's carving leaves the gas on the cell the other
# casts from; the second cast reads the air without it.
func test_gas_this_pass_leaves_does_not_move_a_later_cast_in_it() -> void:
	var kind: Gas.Kind = _air_gases()[0]
	var id: String = GasRules.for_kind(kind).air.keys()[0]
	var thrower_carving := _carving(DRAWS["inert_air"])
	thrower_carving.hits_allies = true
	thrower_carving.gases = {kind: Gas.Level.THICK}
	var thrower := _alchemist(thrower_carving)
	var caster_carving := _carving(DRAWS[id])
	var caster := _alchemist(caster_carving)
	var cast_from := HERE + Vector2i.DOWN
	caster.movement.cell = cast_from
	var foe := H.spawn_solo(self, _sm, ENEMY, cast_from + Vector2i.RIGHT, { Stats.Stat.MHP: 60 })
	_sm.join_squad(caster, thrower.squad)
	thrower.active_attack = thrower_carving
	var drop := AttackAction.declare(thrower, thrower.movement.cell, cast_from)
	thrower.active_attack = null
	caster.active_attack = caster_carving
	var cast := AttackAction.declare(caster, cast_from, foe.movement.cell)
	caster.active_attack = null
	thrower.squad._queue_action(drop)
	thrower.squad._queue_action(cast)
	_sm.active_squad = thrower.squad
	var board: BoardContext = _sm.board_source.call()
	board.gas = GasField.new()
	var plan := _sm.resolve_plan(thrower.squad, board, ReactionCatalog.get_all())
	var deposited := 0
	for effect in plan.cell_effects:
		if effect.cell == cast_from:
			deposited += int(effect.gas_added.get(kind, 0))
	assert_int(deposited).override_failure_message(
			"fixture: the first carving left no %s where the second is cast from" % Gas.name_of(kind)).is_greater(0)
	assert_int(_outcome_of(plan, caster).air_steps.size()).override_failure_message(
			"a gas this pass deposits moved a cast later in the same pass").is_equal(0)
	_break_volleys(plan)


# The AI's seek groups cells by everything the resolver reads off the origin (AITactics._group_key), the
# air now among them: two origins that differ only in their gas must not share a key.
func test_the_ai_seek_tells_two_cells_apart_by_their_air() -> void:
	var kind: Gas.Kind = _air_gases()[0]
	var id: String = GasRules.for_kind(kind).air.keys()[0]
	var carving := _carving(DRAWS[id])
	carving.max_range = 3
	var caster := _alchemist(carving)
	var target := HERE + Vector2i(3, 0)
	var near := HERE + Vector2i(1, 0)
	caster.active_attack = carving
	var from_here := AttackAction.declare(caster, HERE, target)
	var from_near := AttackAction.declare(caster, near, target)
	caster.active_attack = null
	# The fixture's real board: the key also asks empowerment, which reads the ground.
	var clear: BoardContext = _sm.board_source.call()
	clear.gas = GasField.new()
	assert_str(AITactics._group_key(from_here, clear)).override_failure_message(
			"fixture: the two origins differ in more than their air").is_equal(AITactics._group_key(from_near, clear))
	var gassy: BoardContext = _sm.board_source.call()
	gassy.gas = _gas_on(HERE, kind, Gas.Level.THICK)
	assert_str(AITactics._group_key(from_here, gassy)).override_failure_message(
			"two cells whose air differs share one seek key").is_not_equal(AITactics._group_key(from_near, gassy))
