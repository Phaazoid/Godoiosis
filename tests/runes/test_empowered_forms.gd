# A carving's EMPOWERED FORM (#695): the delta a carving fires instead where its caster is empowered in
# every element the form requires. Canon: docs/design/alchemy-kit.md -> Empowerment.
#
# The rule asked here is Materia.form_choice, the one chooser, and these cases pin that every place that
# reads a carving's geometry asks it: the pass (at the caster's cell AT ITS SLOT), the queue gate, the AI's
# candidate builder, the threat field, a watch (chosen at arm, kept), a counter (at the reactor's cell),
# the save, and the Play API's words. The fixture form is a Plus set down on the aimed cell, one power
# softer, so which form fired is read off how many bodies the volley holds.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const FIRE := Elemental.Element.FIRE
const AIR := Elemental.Element.AIR

const VEIN := Vector2i(0, 0)
const BESIDE := Vector2i(1, 0)        # within Materia.REACH of VEIN
const FOE := Vector2i(3, 0)           # two from BESIDE: the carving's one ring
const NEIGHBOUR := Vector2i(3, 1)     # a Plus arm around FOE, outside the base's one cell
const FAR_FOE := Vector2i(4, 0)       # three from BESIDE: only a Plus set down on FOE reaches it
const START := Vector2i(1, 3)         # beyond REACH of VEIN, three steps from BESIDE
const AWAY := Vector2i(1, 6)          # beyond REACH of VEIN
const AWAY_FOE := Vector2i(3, 6)
const AWAY_NEIGHBOUR := Vector2i(3, 7)

var _sm: SquadManager
var _veins: VeinField


func before_test() -> void:
	_sm = H.make_manager(self)
	_veins = VeinField.new()
	var grid: TileMapLayer = (_sm.board_source.call() as BoardContext).grid
	_sm.board_source = func() -> BoardContext:
		var board := BoardContext.new(grid, _sm._all_units(), _sm)
		board.veins = _veins
		return board


func _board() -> BoardContext:
	return _sm.board_source.call()


# Plus-shaped, one softer, requiring what the hit delivers (fire) unless a case says otherwise.
static func _burst() -> EmpoweredForm:
	var form := EmpoweredForm.new()
	form.display_name = "Burst"
	form.attack_shape = P.shape([Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
			Vector2i(0, -1)] as Array[Vector2i])
	form.power_bonus = -1
	return form


# Makes its own flame out of the air (test_vial_empowerment's Fireball), so no grass fizzles it.
static func _carving(formed := true) -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = "Fireball"
	t.power = 4
	t.recipe = "Break(F, A) + Push(F2)"
	t.targets = EquippableData.TargetMode.UNIT
	P.point(t, 2, 2)
	if formed:
		t.empowered = _burst()
	return t


func _alchemist(faction: Team.Faction, cell: Vector2i, carving: TransmutationData) -> Unit:
	var u := H.spawn_solo(self, _sm, faction, cell, {Stats.Stat.MHP: 200}, false)
	u.unit_instance.aura = {FIRE: 4, AIR: 4}
	var affinity: Array[Elemental.Element] = [FIRE, AIR]
	u.unit_instance.affinity = affinity
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	assert_bool(rune.inscribe(carving)).override_failure_message("fixture: the carving did not inscribe").is_true()
	assert_bool(u.add_item(rune)).override_failure_message("fixture: the rune did not fit").is_true()
	u.equipped_weapon = rune
	u.set_current_hp(u.get_max_hp())
	return u


func _foe(cell: Vector2i) -> Unit:
	var u := H.spawn_solo(self, _sm, ENEMY, cell, {Stats.Stat.MHP: 200})
	u.set_current_hp(u.get_max_hp())
	return u


func _aim(caster: Unit, carving: TransmutationData, cell: Vector2i) -> AttackAction:
	caster.active_attack = carving
	var aim := AttackAction.declare(caster, caster.get_projected_destination(), cell)
	caster.active_attack = null
	return aim


func _walk(unit: Unit, path: Array[Vector2i]) -> MoveAction:
	var move := MoveAction.new()
	move.init(unit, path, null)
	return move


# Queue through the player's own gate, resolve, and hand back the caster's hits.
func _cast(caster: Unit, carving: TransmutationData, at: Vector2i) -> Array[AttackAction]:
	var refusal := _sm.try_queue_action(caster.squad, _aim(caster, carving, at))
	assert_str(refusal).override_failure_message("fixture: the cast was refused (%s)" % refusal).is_equal("")
	_sm.active_squad = caster.squad
	return _hits_by(_sm.resolve_plan(caster.squad, _board()), caster)


func _hits_by(plan: ResolvedPlan, caster: Unit) -> Array[AttackAction]:
	var out: Array[AttackAction] = []
	for attack in plan.attacks:
		if attack.actor == caster:
			out.append(attack)
	_break_volleys(plan)
	return out


func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for ctr in plan.counters:
		ctr.volley = empty
	for shot in plan.watch_shots:
		shot.volley = empty


func _vial(element: Elemental.Element) -> VialData:
	var v := VialData.new()
	v.element = element
	v.display_name = "Vial of %s" % Elemental.display_name(element)
	return v


func _attune(unit: Unit, element: Elemental.Element) -> VialData:
	var vial := _vial(element)
	assert_bool(unit.add_item(vial)).override_failure_message("fixture: the vial did not fit").is_true()
	assert_str(unit.use_vial(unit.inventory.find(vial))).is_equal("")
	return vial


static func _fired_form(hits: Array[AttackAction], carving: TransmutationData) -> bool:
	return not hits.is_empty() and hits[0].fired_attack.form_of == carving


# ==============================================================================
#  Which form fires
# ==============================================================================

func test_beside_a_source_the_form_fires() -> void:
	_veins.set_kind(VEIN, Vein.Kind.FIRE)
	var carving := _carving()
	var caster := _alchemist(PLAYER, BESIDE, carving)
	_foe(FOE)
	_foe(NEIGHBOUR)

	var hits := _cast(caster, carving, FOE)

	assert_bool(_fired_form(hits, carving)).override_failure_message(
			"beside the fire vein the volley still carried the base carving").is_true()
	assert_int(hits.size()).override_failure_message(
			"the Plus set down on the foe should take its neighbour too").is_equal(2)


func test_away_from_a_source_the_base_fires() -> void:
	_veins.set_kind(VEIN, Vein.Kind.FIRE)
	var carving := _carving()
	var caster := _alchemist(PLAYER, AWAY, carving)
	_foe(AWAY_FOE)
	_foe(AWAY_NEIGHBOUR)

	var hits := _cast(caster, carving, AWAY_FOE)

	assert_int(hits.size()).is_equal(1)
	assert_object(hits[0].fired_attack).is_same(carving)


# ORDER: the form is chosen where the walk queued ahead of the cast LEAVES the caster, never where it
# stands now. Read the live cell instead and this goes red (the falsification this case was written for).
func test_a_walk_onto_the_source_fires_the_form() -> void:
	_veins.set_kind(VEIN, Vein.Kind.FIRE)
	var carving := _carving()
	var caster := _alchemist(PLAYER, START, carving)
	_foe(FOE)
	_foe(NEIGHBOUR)
	var path: Array[Vector2i] = [START, Vector2i(1, 2), Vector2i(1, 1), BESIDE]
	assert_str(_sm.try_queue_action(caster.squad, _walk(caster, path))).override_failure_message(
			"fixture: the walk to the vein was refused").is_equal("")

	var hits := _cast(caster, carving, FOE)

	assert_bool(_fired_form(hits, carving)).override_failure_message(
			"the cast read where the caster stands now, not where its walk leaves it").is_true()


func test_a_walk_off_the_source_fires_the_base() -> void:
	_veins.set_kind(VEIN, Vein.Kind.FIRE)
	var carving := _carving()
	var caster := _alchemist(PLAYER, BESIDE, carving)
	_foe(Vector2i(3, 3))
	_foe(Vector2i(3, 4))
	var path: Array[Vector2i] = [BESIDE, Vector2i(1, 1), Vector2i(1, 2), START]
	assert_str(_sm.try_queue_action(caster.squad, _walk(caster, path))).override_failure_message(
			"fixture: the walk off the vein was refused").is_equal("")

	var hits := _cast(caster, carving, Vector2i(3, 3))

	assert_int(hits.size()).is_equal(1)
	assert_object(hits[0].fired_attack).override_failure_message(
			"the caster walked off the vein and still fired the form").is_same(carving)


# ==============================================================================
#  What the form is worth
# ==============================================================================

# R2: the form REPLACES the +1. It hits at the base's power plus its own bonus; a formless carving keeps
# the +1 beside the same vein.
func test_the_form_replaces_the_plus_one() -> void:
	_veins.set_kind(VEIN, Vein.Kind.FIRE)
	var formed := _carving()
	var bare := _alchemist(PLAYER, AWAY, formed)
	_foe(AWAY_FOE)
	var base_damage := _cast(bare, formed, AWAY_FOE)[0].resolved.damage

	var beside := _alchemist(PLAYER, BESIDE, formed)
	_foe(FOE)
	var formed_damage := _cast(beside, formed, FOE)[0].resolved.damage
	assert_int(formed_damage).override_failure_message(
			"the form should hit at the base's power less one, with no +1 (%d vs %d unempowered)" % [
				formed_damage, base_damage]).is_equal(base_damage - 1)


# The ruled default: a carving partly empowered for its form fires its base at plain power, no +1.
# The checklist names AIR as well, so fire alone is not enough.
func test_a_partly_empowered_form_fires_the_base_with_no_plus_one() -> void:
	_veins.set_kind(VEIN, Vein.Kind.FIRE)
	var carving := _carving()
	carving.empowered.requires.assign([FIRE, AIR])
	var bare := _alchemist(PLAYER, AWAY, carving)
	_foe(AWAY_FOE)
	var plain := _cast(bare, carving, AWAY_FOE)[0].resolved.damage

	var caster := _alchemist(PLAYER, BESIDE, carving)
	_foe(FOE)
	_foe(NEIGHBOUR)
	var hits := _cast(caster, carving, FOE)

	assert_int(hits.size()).override_failure_message("fire alone fired a form that requires air too").is_equal(1)
	assert_int(hits[0].resolved.damage).override_failure_message(
			"a partly empowered formed carving took the +1").is_equal(plain)


# R1: the checklist, once ticked, is the whole requirement.
func test_the_requires_checklist_is_the_requirement() -> void:
	_veins.set_kind(VEIN, Vein.Kind.FIRE)
	_veins.set_kind(Vector2i(1, -1), Vein.Kind.AIR)
	var carving := _carving()
	carving.empowered.requires.assign([FIRE, AIR])
	var caster := _alchemist(PLAYER, BESIDE, carving)
	_foe(FOE)
	_foe(NEIGHBOUR)

	assert_bool(_fired_form(_cast(caster, carving, FOE), carving)).override_failure_message(
			"empowered in fire and air, the form that requires both did not fire").is_true()


# ==============================================================================
#  The vial (R4): burned only when it changes which form fires
# ==============================================================================

func test_a_vial_that_flips_the_form_burns() -> void:
	var carving := _carving()
	var caster := _alchemist(PLAYER, AWAY, carving)
	var vial := _attune(caster, FIRE)
	_foe(AWAY_FOE)
	_foe(AWAY_NEIGHBOUR)

	var hits := _cast(caster, carving, AWAY_FOE)

	assert_bool(_fired_form(hits, carving)).override_failure_message(
			"the fire vial did not empower the form").is_true()
	assert_object(hits[0].resolved.burned_vial).override_failure_message(
			"the vial made the form fire and was not burned").is_same(vial)


func test_a_natural_source_spares_the_vial() -> void:
	_veins.set_kind(VEIN, Vein.Kind.FIRE)
	var carving := _carving()
	var caster := _alchemist(PLAYER, BESIDE, carving)
	_attune(caster, FIRE)
	_foe(FOE)
	_foe(NEIGHBOUR)

	var hits := _cast(caster, carving, FOE)

	assert_bool(_fired_form(hits, carving)).is_true()
	for hit in hits:
		assert_object(hit.resolved.burned_vial).override_failure_message(
				"the vein already gave the form, yet the vial burned").is_null()


# ==============================================================================
#  The derived carving
# ==============================================================================

func test_the_form_keeps_the_bases_recipe_and_its_price() -> void:
	var carving := _carving()
	var form := carving.empowered_carving()
	assert_str(form.recipe).is_equal(carving.recipe)
	assert_int(form.cost()).is_equal(carving.cost())
	assert_dict(form.demand()).is_equal(carving.demand())
	assert_int(form.min_range).is_equal(carving.min_range)
	assert_int(form.max_range).is_equal(carving.max_range)
	assert_str(form.display_name).is_equal("Burst")
	assert_int(form.power).is_equal(carving.power - 1)


# ONE object until an edit, and an edit to either half reaches it: every dev-tools writer emits
# `changed`. Drop the invalidation and the first edit below reads the stale form.
func test_the_form_follows_an_edit_to_either_half() -> void:
	var carving := _carving()
	var form := carving.empowered_carving()
	assert_object(carving.empowered_carving()).override_failure_message(
			"two asks built two forms: an AI key compares instance ids").is_same(form)

	carving.power = 9
	carving.emit_changed()
	assert_int(carving.empowered_carving().power).override_failure_message(
			"an edit to the base carving did not reach its form").is_equal(8)

	carving.empowered.power_bonus = -3
	carving.empowered.emit_changed()
	assert_int(carving.empowered_carving().power).override_failure_message(
			"an edit to the form's delta did not reach it").is_equal(6)


# ==============================================================================
#  Every judge before the click asks the same chooser
# ==============================================================================

# The candidate's whiff: an aim at an empty cell whose Plus takes the foe beyond it is a real aim
# beside the vein, and a whiff away from it.
func test_an_aim_only_the_form_reaches_is_taken() -> void:
	_veins.set_kind(VEIN, Vein.Kind.FIRE)
	var carving := _carving()
	var caster := _alchemist(PLAYER, BESIDE, carving)
	_foe(FAR_FOE)
	assert_str(_sm.try_queue_action(caster.squad, _aim(caster, carving, FOE))).override_failure_message(
			"the gate judged the aim by the base, which finds nobody there").is_equal("")

	var bare := _alchemist(PLAYER, AWAY, carving)
	_foe(AWAY_FOE + Vector2i(1, 0))
	assert_str(_sm.try_queue_action(bare.squad, _aim(bare, carving, AWAY_FOE))).override_failure_message(
			"away from the vein the same aim should whiff").is_not_empty()


func test_the_ai_aims_the_form() -> void:
	_veins.set_kind(VEIN, Vein.Kind.FIRE)
	var carving := _carving()
	var caster := _alchemist(ENEMY, BESIDE, carving)
	H.spawn_solo(self, _sm, PLAYER, FAR_FOE, {Stats.Stat.MHP: 200})

	var aims: Array[Vector2i] = []
	for candidate in AITactics._attack_candidates(caster, _board(), BESIDE, {}):
		aims.append(candidate.target_cell)
	assert_array(aims).override_failure_message(
			"the AI never offered the aim only the form reaches").contains([FOE])

	_veins.set_kind(VEIN, Vein.Kind.NONE)
	assert_array(AITactics._attack_candidates(caster, _board(), BESIDE, {})).override_failure_message(
			"with no vein the base reaches nobody, yet the AI offered an aim").is_empty()


# The field stays a superset of what the AI can aim: a Hold enemy (one origin) beside a vein threatens
# the cell its form's Plus reaches past the ring.
func test_the_threat_field_reaches_with_the_form() -> void:
	_veins.set_kind(VEIN, Vein.Kind.FIRE)
	var carving := _carving()
	var caster := _alchemist(ENEMY, BESIDE, carving)
	caster.squad.archetype = AIArchetype.Type.HOLD

	var reach := ThreatField.build(_board(), PLAYER).reach_of(caster)
	assert_array(reach).override_failure_message("the field missed the form's reach").contains([FAR_FOE])

	_veins.set_kind(VEIN, Vein.Kind.NONE)
	assert_array(ThreatField.build(_board(), PLAYER).reach_of(caster)).override_failure_message(
			"fixture: the base alone already reaches that cell").not_contains([FAR_FOE])


# ==============================================================================
#  A watch picks its form at arm and keeps it (R6); a save keeps it too
# ==============================================================================

func _watcher(cell: Vector2i) -> Dictionary:
	var carving := _carving()
	carving.can_overwatch = true
	var watcher := _alchemist(PLAYER, cell, carving)
	assert_bool(watcher.overwatch_attacks().has(carving)).override_failure_message(
			"fixture: the carving is not in the watch view").is_true()
	return {"unit": watcher, "carving": carving}


func _arm(watcher: Unit, carving: TransmutationData, aim: Vector2i) -> void:
	var order := OverwatchAction.new()
	order.init(watcher, aim, carving)
	var refusal := _sm.try_queue_action(watcher.squad, order)
	assert_str(refusal).override_failure_message("fixture: the watch was refused (%s)" % refusal).is_equal("")
	_sm.active_squad = watcher.squad
	_break_volleys(_sm.resolve_plan(watcher.squad, _board()))
	order.execute()
	assert_object(watcher.watch).override_failure_message("fixture: the watch did not arm").is_not_null()


func test_a_watch_keeps_its_form_after_the_source_goes_out() -> void:
	_veins.set_kind(VEIN, Vein.Kind.FIRE)
	var w := _watcher(BESIDE)
	var watcher: Unit = w.unit
	var carving: TransmutationData = w.carving
	_arm(watcher, carving, FOE)
	assert_bool(watcher.watch.empowered).override_failure_message("the watch armed its base beside the vein").is_true()
	assert_array(watcher.watch.footprint).contains([NEIGHBOUR])

	_veins.set_kind(VEIN, Vein.Kind.NONE)
	var walker := _foe(Vector2i(5, 1))
	var path: Array[Vector2i] = [Vector2i(5, 1), Vector2i(4, 1), NEIGHBOUR]
	assert_str(_sm.try_queue_action(walker.squad, _walk(walker, path))).is_equal("")
	_sm.active_squad = walker.squad
	var plan := _sm.resolve_plan(walker.squad, _board())
	var shots := plan.watch_shots.filter(func(s: AttackAction) -> bool: return s.actor == watcher)
	var fired: AttackData = shots[0].fired_attack if not shots.is_empty() else null
	_break_volleys(plan)

	assert_int(shots.size()).override_failure_message("the walk into the form's lane drew no shot").is_greater(0)
	assert_object(fired).override_failure_message(
			"the vein went out and the watch fired its base: the form is chosen at arm").is_not_same(carving)
	if fired != null:
		assert_object((fired as TransmutationData).form_of).is_same(carving)


func test_a_watch_armed_on_the_vial_saves_both_flags() -> void:
	var w := _watcher(AWAY)
	var watcher: Unit = w.unit
	_attune(watcher, FIRE)
	_arm(watcher, w.carving, AWAY_FOE)
	assert_bool(watcher.watch.empowered).override_failure_message("fixture: the vial did not form the watch").is_true()
	assert_bool(watcher.watch.leans_on_vial).is_true()

	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(watcher)
	var loaded := H.spawn_unit(self, PLAYER, Vector2i(9, 9), {}, false)
	entry.apply_unit_state(loaded)

	assert_object(loaded.watch).override_failure_message("fixture: the watch did not survive the save").is_not_null()
	if loaded.watch != null:
		assert_bool(loaded.watch.empowered).override_failure_message("the save dropped the armed form").is_true()
		assert_bool(loaded.watch.leans_on_vial).override_failure_message(
				"the save dropped the vial the form leans on").is_true()


# ==============================================================================
#  A counter picks its form at the reactor's cell (R7)
# ==============================================================================

func test_a_counter_fires_the_form_its_cell_gives() -> void:
	_veins.set_kind(VEIN, Vein.Kind.FIRE)
	var carving := _carving()
	var reactor := _alchemist(PLAYER, BESIDE, carving)
	reactor.active_attack = carving
	var attacker := _foe(FOE)
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack.max_range = 2
	_foe(NEIGHBOUR)

	attacker.squad._queue_action(H.stamped_attack(attacker, reactor))
	_sm.active_squad = attacker.squad
	var plan := _sm.resolve_plan(attacker.squad, _board())
	var counters := plan.counters.filter(func(c: CounterAttackAction) -> bool: return c.actor == reactor)
	var fired: AttackData = counters[0].fired_attack if not counters.is_empty() else null
	var count := counters.size()
	_break_volleys(plan)

	assert_int(count).override_failure_message(
			"the counter should be the Plus on the attacker, taking its neighbour (%d hits)" % count).is_equal(2)
	if fired != null:
		assert_object((fired as TransmutationData).form_of).override_failure_message(
				"the counter fired its base beside the vein").is_same(carving)


# ==============================================================================
#  The Play API says what fires
# ==============================================================================

func test_the_play_api_names_the_form() -> void:
	var b := BoardBuilder.build(self, "FormRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 12, 12))
	(b.vein_field as VeinField).set_kind(VEIN, Vein.Kind.FIRE)
	var hero: Unit = BoardBuilder.spawn(b, UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Alchemist",
			PLAYER), BESIDE)
	BoardBuilder.spawn(b, UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Foe", ENEMY), FOE)
	hero.unit_instance.aura = {FIRE: 4, AIR: 4}
	var affinity: Array[Elemental.Element] = [FIRE, AIR]
	hero.unit_instance.affinity = affinity
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	rune.inscriptions.assign([_carving()])
	hero.add_item(rune)
	var sess = PlaySession.new(b)

	var listed: Dictionary = sess.legal_targets(sess.handle_for(hero))

	assert_bool(listed.ok).override_failure_message("fixture: %s" % listed.get("error", "")).is_true()
	assert_str(String(listed.get("attack", ""))).override_failure_message(
			"the aims listing does not say the form fires").contains("fires Burst")
