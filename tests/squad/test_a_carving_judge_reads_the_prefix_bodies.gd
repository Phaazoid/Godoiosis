# A CANDIDATE carving is judged with the BODIES the queued orders leave (#1529): a neighbour an earlier
# queued hit soaks lends its water, and one an earlier hit dries lends none. The pass has read its own
# bodies since #1480 stage 4; these cases pin that every judge OUTSIDE it -- the ring's row, the aim
# cycle, the red reach, the queue gate and the Play API's listing and focus line -- reads the same ones,
# both ways, and that the pass agrees.
#
# The door is SquadManager.candidate_bodies (the attack prefix's hypo, ResolvedPlan.prefix_hypo), the
# body twin of candidate_board. A candidate lands after the queued ATTACKS and before the counters, so a
# counter's soak is no water for it: the last case tells the prefix from the end of the pass.
#
# The carving is tests/runes/test_fizzle_wires.gd's Spray, `Focus(W2) + Push(W2)`, which needs water
# beside the caster; the grass offers none, so the only water is what a neighbour carries. The reactions
# are authored here (H.only_reactions), never the catalog's. Fixture is
# tests/squad/test_a_candidate_meets_the_planned_ground.gd's game host.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const BoardView := preload("res://play/board_view.gd")
const PlaySession := preload("res://play/play_session.gd")

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const WIDTH := 8
const HEIGHT := 5

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const FIRE := Elemental.Element.FIRE
const WATER := Elemental.Element.WATER
const AIR := Elemental.Element.AIR
const WET := Elemental.State.WET

const CASTER := Vector2i(2, 2)
const FOE := Vector2i(4, 2)
const BESIDE := Vector2i(2, 1)      # within Materia.REACH of CASTER
const MATE := Vector2i(1, 1)        # beside BESIDE, out of the caster's reach
const PAST := Vector2i(2, 0)        # beside BESIDE, out of the caster's reach

var _main: Node
var game: Node2D
var sm: SquadManager


func before_test() -> void:
	# A water hit soaks; a fire hit dries a soaked unit.
	var soak := ElementalReaction.new()
	soak.incoming_element = WATER
	soak.add_states.assign([WET])
	H.only_reactions([soak, H.stripping(FIRE, WET)])
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	sm = game.squad_manager
	game.mission_controller._close_mission_select()
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(WIDTH):
		for y in range(HEIGHT):
			game.grid.paint(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	game.scenario_manager.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	ReactionCatalog.refresh()


# --- the board ----------------------------------------------------------------------------------

func _spawn(faction: Team.Faction, cell: Vector2i, mhp := 200) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: mhp}, faction), cell)
	assert_object(unit).override_failure_message("fixture: nothing would spawn at %s" % cell).is_not_null()
	unit.set_current_hp(unit.get_max_hp())
	return unit


static func _blow(element := Elemental.Element.NONE) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.display_name = "Blow"
	attack.power = 1
	attack.elemental_damage_type = element
	return attack


func _arm(unit: Unit, attack: WeaponAttackData) -> void:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = attack
	assert_bool(unit.add_item(WeaponInstance.make(t))).override_failure_message("fixture: the weapon did not fit").is_true()


func _mate(lead: Unit, cell: Vector2i, attack: WeaponAttackData) -> Unit:
	var mate := _spawn(PLAYER, cell)
	_arm(mate, attack)
	sm.join_squad(mate, lead.squad)
	return mate


static func _carving(carving_name: String, recipe: String) -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = carving_name
	t.power = 4
	t.recipe = recipe
	t.targets = EquippableData.TargetMode.UNIT
	P.point(t, 2)
	return t


static func _spray() -> TransmutationData:
	return _carving("Spray", "Focus(W2) + Push(W2)")


func _alchemist(cell: Vector2i, carvings: Array[TransmutationData]) -> Unit:
	var u := _spawn(PLAYER, cell)
	var elements: Array[Elemental.Element] = [FIRE, WATER, AIR]
	var aura: Dictionary[Elemental.Element, int] = {}
	for element in elements:
		aura[element] = 4
	u.unit_instance.aura = aura
	u.unit_instance.affinity = elements
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	for carving in carvings:
		assert_bool(rune.inscribe(carving)).override_failure_message("fixture: a carving did not inscribe").is_true()
	assert_bool(u.add_item(rune)).override_failure_message("fixture: the rune did not fit").is_true()
	u.equipped_weapon = rune
	for carving in carvings:
		assert_bool(u.is_attack_fireable(carving)).override_failure_message(
				"fixture: %s must be channelable, or the fizzle is not what is measured" % carving.display_name).is_true()
	return u


# --- the orders ---------------------------------------------------------------------------------

func _declare(unit: Unit, attack: AttackData, at: Vector2i) -> AttackAction:
	unit.active_attack = attack
	var aim := AttackAction.declare(unit, unit.get_projected_destination(), at)
	unit.active_attack = null
	return aim


func _try(unit: Unit, action: BaseAction) -> String:
	var refusal := sm.try_queue_action(unit.squad, action)
	game.refresh_action_queue(unit.squad)
	return refusal


func _queue_hit(unit: Unit, at: Vector2i) -> void:
	var refusal := _try(unit, _declare(unit, null, at))
	assert_str(refusal).override_failure_message("fixture: the hit at %s was refused" % str(at)).is_equal("")


func _row(unit: Unit, row_name: String) -> Dictionary:
	return _find(game.main_action_menu.build_tree(unit), row_name)


static func _find(nodes: Array, row_name: String) -> Dictionary:
	for node: Dictionary in nodes:
		if String(node.get("name", "")) == row_name:
			return node
		var below := _find(node.get("children", []), row_name)
		if not below.is_empty():
			return below
	return {}


static func _expanded(plan: ResolvedPlan, actor: Unit) -> AttackAction:
	for attack in plan.attacks:
		if attack.actor == actor:
			return attack
	return null


# The ground the prefix leaves holds no water of its own, so the bodies are what is measured -- asked
# where a carving is expected to FIND water, which ground water would make vacuous.
func _no_water_underfoot(caster: Unit, spray: TransmutationData) -> void:
	assert_str(CellSubstances.fizzle_reason(spray, CASTER, sm.candidate_board(caster.squad), caster.state)) \
		.override_failure_message("fixture: the ground the queued orders leave must hold no water").is_not_empty()


# ==============================================================================
#  A neighbour an earlier hit soaks
# ==============================================================================

# A squadmate's queued water hit soaks the unit beside the caster: the row is live, the gate takes the
# order, and the pass casts it.
func test_a_carving_draws_on_a_neighbour_an_earlier_hit_soaks() -> void:
	var spray := _spray()
	var carvings: Array[TransmutationData] = [spray]
	var caster := _alchemist(CASTER, carvings)
	_spawn(ENEMY, FOE)
	var neighbour := _spawn(ENEMY, BESIDE)
	var soaker := _mate(caster, MATE, _blow(WATER))
	assert_bool(_row(caster, "Spray").get("disabled", false)).override_failure_message(
			"fixture: the row must be greyed with nobody wet").is_true()

	_queue_hit(soaker, BESIDE)

	assert_bool(PlanResolver.projected_states(neighbour, sm.resolved_plan_for(caster.squad).hypo).has(WET)) \
		.override_failure_message("fixture: the queued water hit must soak the neighbour").is_true()
	_no_water_underfoot(caster, spray)
	assert_bool(_row(caster, "Spray").get("disabled", false)).override_failure_message(
			"the ring greys a carving a neighbour a queued hit soaks would feed").is_false()

	var cast := _declare(caster, spray, FOE)
	assert_str(_try(caster, cast)).override_failure_message(
			"the gate refuses a carving a neighbour a queued hit soaks would feed").is_equal("")
	var landed := _expanded(sm.resolved_plan_for(caster.squad), caster)
	assert_object(landed).override_failure_message("the cast expanded to nothing").is_not_null()
	if landed != null:
		assert_bool(landed.resolved.fizzled).override_failure_message("the pass fizzles the cast the gate took").is_false()
	assert_bool(cast.is_valid).override_failure_message("the queued cast is red: %s" % ", ".join(cast.validation_errors)).is_true()


# The aim cycle offers it from a weapon in hand, the rune carried (#929's F cycle): the same bodies.
func test_the_aim_cycle_offers_a_carving_a_neighbour_an_earlier_hit_soaks() -> void:
	var spray := _spray()
	var carvings: Array[TransmutationData] = [spray]
	var caster := _alchemist(CASTER, carvings)
	var blade := H.make_weapon()
	assert_bool(caster.add_item(blade)).override_failure_message("fixture: nothing to carry the blade in").is_true()
	caster.equipped_weapon = blade
	_spawn(ENEMY, FOE)
	_spawn(ENEMY, BESIDE)
	var soaker := _mate(caster, MATE, _blow(WATER))

	_queue_hit(soaker, BESIDE)

	game.select_unit(caster, CASTER)
	game.enter_attack_mode(caster)
	assert_object(caster.get_fired_attack()).override_failure_message(
			"fixture: the aim must open on the blade").is_same(blade.effective_main(caster.state))
	game.cycle_aimed_attack(1)
	assert_object(caster.get_fired_attack()).override_failure_message(
			"the aim cycle skips a carving a neighbour a queued hit soaks would feed").is_same(spray)
	game.exit_current_mode()


# The red reach drawn under the ring asks the row's question with the same bodies. Spray alone, so no
# other attack draws the same cells.
func test_the_reach_overlay_counts_a_neighbour_an_earlier_hit_soaks() -> void:
	var carvings: Array[TransmutationData] = [_spray()]
	var caster := _alchemist(CASTER, carvings)
	_spawn(ENEMY, FOE)
	_spawn(ENEMY, BESIDE)
	var soaker := _mate(caster, MATE, _blow(WATER))
	game.show_player_reach(caster, CASTER)
	assert_array(game.overlay_manager.reach_overlay.get_used_cells()).override_failure_message(
			"fixture: a carving with nobody wet must draw no reach").is_empty()

	_queue_hit(soaker, BESIDE)

	game.show_player_reach(caster, CASTER)
	var red: Array[Vector2i] = game.overlay_manager.reach_overlay.get_used_cells()
	assert_array(red).override_failure_message(
			"the red reach omits a carving a neighbour a queued hit soaks would feed").contains([FOE])


# ==============================================================================
#  A neighbour an earlier hit dries
# ==============================================================================

# A wet unit beside the caster that a squadmate's queued fire dries lends no water: the row greys with the
# reason, the gate refuses in those words, and the pass would fizzle it.
func test_a_carving_whose_wet_neighbour_an_earlier_hit_dries_is_refused() -> void:
	var spray := _spray()
	var carvings: Array[TransmutationData] = [spray]
	var caster := _alchemist(CASTER, carvings)
	_spawn(ENEMY, FOE)
	var neighbour := _spawn(ENEMY, BESIDE)
	neighbour.add_element_state(WET)
	var drier := _mate(caster, MATE, _blow(FIRE))
	assert_bool(_row(caster, "Spray").get("disabled", false)).override_failure_message(
			"fixture: beside a wet unit the row must be live").is_false()

	_queue_hit(drier, BESIDE)

	assert_bool(PlanResolver.projected_states(neighbour, sm.resolved_plan_for(caster.squad).hypo).has(WET)) \
		.override_failure_message("fixture: the queued fire must dry the neighbour").is_false()
	var row := _row(caster, "Spray")
	assert_bool(row.get("disabled", false)).override_failure_message(
			"the ring offers a carving whose wet neighbour a queued hit dries").is_true()
	assert_str(String(row.get("tooltip", ""))).contains("Fizzles")
	var cast := _declare(caster, spray, FOE)
	assert_str(_try(caster, cast)).override_failure_message(
			"the gate takes a carving whose wet neighbour a queued hit dries").starts_with("Fizzles")
	var one: Array[BaseAction] = [cast]
	var landed := _expanded(sm.resolve_hypothetical(caster.squad, one, game._board()), caster)
	assert_bool(landed != null and landed.resolved.fizzled).override_failure_message(
			"fixture: the pass must fizzle the cast the gate refused").is_true()
	game.refresh_action_queue(caster.squad)


# ==============================================================================
#  The moment: the attack prefix, not the end of the pass
# ==============================================================================

# A foe's COUNTER soaks the squadmate beside the caster. The counters run after every queued attack, a
# candidate's included, so that water is there by the end of the pass and not when the cast goes off:
# the row stays greyed, the gate refuses, and the pass fizzles it.
func test_a_counter_that_soaks_a_neighbour_feeds_no_candidate() -> void:
	var spray := _spray()
	var carvings: Array[TransmutationData] = [spray]
	var caster := _alchemist(CASTER, carvings)
	_spawn(ENEMY, FOE)
	var striker := _mate(caster, BESIDE, _blow())
	var soaker := _spawn(ENEMY, PAST)
	_arm(soaker, _blow(WATER))

	_queue_hit(striker, PAST)

	var plan := sm.resolved_plan_for(caster.squad)
	assert_str(CellSubstances.fizzle_reason(spray, CASTER, sm.candidate_board(caster.squad),
			PlanResolver.state_of(caster, plan.hypo), plan.hypo)).override_failure_message(
			"fixture: by the end of the pass the counter's water must feed the carving").is_equal("")
	assert_bool(_row(caster, "Spray").get("disabled", false)).override_failure_message(
			"the ring counts water a counter brings after the cast").is_true()
	var cast := _declare(caster, spray, FOE)
	assert_str(_try(caster, cast)).override_failure_message(
			"the gate counts water a counter brings after the cast").starts_with("Fizzles")
	var one: Array[BaseAction] = [cast]
	var landed := _expanded(sm.resolve_hypothetical(caster.squad, one, game._board()), caster)
	assert_bool(landed != null and landed.resolved.fizzled).override_failure_message(
			"fixture: the pass must fizzle a cast that goes off before the counter").is_true()
	game.refresh_action_queue(caster.squad)


# ==============================================================================
#  The Play API: the same bodies, headless
# ==============================================================================

func _headless_unit(b: Dictionary, faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = BoardBuilder.spawn(b, H.make_unit_data({Stats.Stat.MHP: 200}, faction), cell)
	unit.set_current_hp(unit.get_max_hp())
	return unit


func test_the_play_api_lists_a_carving_a_neighbour_an_earlier_hit_soaks() -> void:
	var b := BoardBuilder.build(self, "PrefixBodiesCarving")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(0, 0, WIDTH, HEIGHT))
	var caster := _headless_unit(b, PLAYER, CASTER)
	var elements: Array[Elemental.Element] = [WATER, AIR]
	caster.unit_instance.aura = {WATER: 4, AIR: 4}
	caster.unit_instance.affinity = elements
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	assert_bool(rune.inscribe(_spray())).is_true()
	assert_bool(caster.add_item(rune)).is_true()
	caster.equipped_weapon = rune
	_headless_unit(b, ENEMY, FOE)
	_headless_unit(b, ENEMY, BESIDE)
	var soaker := _headless_unit(b, PLAYER, MATE)
	_arm(soaker, _blow(WATER))
	(b.squad_manager as SquadManager).join_squad(soaker, caster.squad)
	var sess = PlaySession.new(b)
	var handle: String = sess.handle_for(caster)
	assert_bool(sess.legal_targets(handle, "Spray").ok).override_failure_message(
			"fixture: with nobody wet the carving must have no aims").is_false()
	assert_str(BoardView.render_focus(sess, handle)).override_failure_message(
			"fixture: with nobody wet the focus line must say the carving fizzles").contains("Fizzles")

	var soaked: Dictionary = sess.queue_attack(sess.handle_for(soaker), BESIDE)
	assert_bool(soaked.ok).override_failure_message("fixture: the soaker was refused: %s" % str(soaked.get("error", ""))).is_true()

	var after: Dictionary = sess.legal_targets(handle, "Spray")
	assert_bool(after.ok).override_failure_message(
			"the Play API lists no aims for a carving a neighbour a queued hit soaks: %s" % str(after.get("error", ""))).is_true()
	assert_str(BoardView.render_focus(sess, handle)).override_failure_message(
			"the focus line says a carving a neighbour a queued hit soaks fizzles").not_contains("Fizzles")
	var cast: Dictionary = sess.queue_attack(handle, FOE, "Spray")
	assert_bool(cast.ok).override_failure_message(
			"the Play API refuses a carving a neighbour a queued hit soaks: %s" % str(cast.get("error", ""))).is_true()
