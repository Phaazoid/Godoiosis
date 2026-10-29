# A CANDIDATE order is judged on the ground the queued orders leave (#1498 stage 3b). The pass reads its
# own tiles since stage 3, so a carving cast after a squadmate's fire draws on it and a haul onto ice a
# squadmate froze lands; these cases pin that every judge OUTSIDE the pass -- the queue gate, the ring's
# row, the aim cycle, the rescue pick, the AI's seek key and the Play API -- sees that same ground, both
# ways: a combo the pass allows is offered and queues, and an order an earlier one takes the material
# from is greyed and refused. Each case checks the pass agrees with the judge.
#
# The doors are SquadManager.candidate_board (the attack prefix's tiles, ResolvedPlan.prefix_tiles) and
# rescue_board (the tail's, after the counters, ResolvedPlan.tail_tiles). Fixture is
# tests/flow/test_execute_two_hosts.gd's game host.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const DEEP_WATER := Vector2i(5, 6)   # TestTiles' deep water, which drowns and freezes
const WIDTH := 8
const HEIGHT := 5

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const FIRE := Elemental.Element.FIRE
const ICE := Elemental.Element.ICE
const WATER := Elemental.Element.WATER

# A caster with something to fire at, and the cell beside it a squadmate's attack can change.
const CASTER := Vector2i(2, 2)
const FOE := Vector2i(4, 2)
const BESIDE := Vector2i(2, 1)      # within Materia.REACH of CASTER
const MATE := Vector2i(1, 1)        # beside BESIDE
const SECOND_MATE := Vector2i(3, 1) # beside BESIDE too

# A rescuer beside a body in deep water, and a second water cell beside the rescuer.
const RESCUER := Vector2i(2, 2)
const BODY := Vector2i(3, 2)
const LAKE := Vector2i(2, 3)
const LAKESIDE := Vector2i(1, 3)    # beside LAKE
const LAKESIDE_FOE := Vector2i(0, 3)

const NOT_A_BANK := "Can't pull them out to there any more"

var _main: Node
var game: Node2D
var sm: SquadManager


func before_test() -> void:
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


# --- the board ----------------------------------------------------------------------------------

func _spawn(faction: Team.Faction, cell: Vector2i, mhp := 80) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: mhp}, faction), cell)
	assert_object(unit).override_failure_message("fixture: nothing would spawn at %s" % cell).is_not_null()
	unit.set_current_hp(unit.get_max_hp())
	return unit


static func _blow(power: int, element := Elemental.Element.NONE, map := false) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.display_name = "Blow"
	attack.power = power
	attack.elemental_damage_type = element
	if map:
		attack.targets = EquippableData.TargetMode.MAP
	return attack


func _arm(unit: Unit, attack: WeaponAttackData) -> void:
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = attack
	assert_bool(unit.add_item(WeaponInstance.make(t))).override_failure_message("fixture: the weapon did not fit").is_true()


# A squadmate of `lead` at `cell`, carrying one attack.
func _mate(lead: Unit, cell: Vector2i, attack: WeaponAttackData) -> Unit:
	var mate := _spawn(PLAYER, cell)
	_arm(mate, attack)
	sm.join_squad(mate, lead.squad)
	return mate


static func _carving(carving_name: String, recipe: String, watch := false) -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = carving_name
	t.power = 4
	t.recipe = recipe
	t.targets = EquippableData.TargetMode.UNIT
	t.can_overwatch = watch
	P.point(t, 2)
	return t


# An alchemist at `cell` whose rune holds `carvings`, attuned to `elements`.
func _alchemist(cell: Vector2i, carvings: Array[TransmutationData], elements: Array[Elemental.Element]) -> Unit:
	var u := _spawn(PLAYER, cell)
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


# Deep water at `cell`, iced over.
func _ice(cell: Vector2i) -> void:
	game.grid.paint(cell, GRASS_SOURCE, DEEP_WATER)
	var freeze := ResolvedCellEffect.new()
	freeze.cell = cell
	freeze.states_added.assign([Terrain.TileState.FROZEN])
	game.terrain_states.apply(freeze)


# A rescuer beside a body lying in deep water at BODY, ejected the way a pass leaves one. LAKE is
# painted by the caller first, since nothing may spawn on it.
func _rescuer_beside_a_drowning_body() -> Dictionary:
	var rescuer := _spawn(PLAYER, RESCUER)
	rescuer.equipped_weapon = H.make_weapon()
	var body := _spawn(PLAYER, BODY)
	var bystander := _spawn(ENEMY, Vector2i(WIDTH - 1, 0))
	await await_idle_frame()
	body.take_damage(body.get_current_hp())
	assert_bool(body.is_downed()).override_failure_message("fixture: the body did not go down").is_true()
	await game.order_executor.execute_orders(bystander)   # an empty pass: settles the ejection
	game.grid.paint(BODY, GRASS_SOURCE, DEEP_WATER)
	return {"rescuer": rescuer, "body": body}


# --- the orders ---------------------------------------------------------------------------------

func _declare(unit: Unit, attack: AttackData, at: Vector2i) -> AttackAction:
	unit.active_attack = attack
	var aim := AttackAction.declare(unit, unit.get_projected_destination(), at)
	unit.active_attack = null
	return aim


# Queue an order through the gate and refresh as the game does after one; answers the refusal.
func _try(unit: Unit, action: BaseAction) -> String:
	var refusal := sm.try_queue_action(unit.squad, action)
	game.refresh_action_queue(unit.squad)
	return refusal


func _queue_fire(unit: Unit, at: Vector2i) -> void:
	var refusal := _try(unit, _declare(unit, null, at))
	assert_str(refusal).override_failure_message("fixture: the attack at %s was refused" % str(at)).is_equal("")


func _watch(unit: Unit, attack: AttackData, at: Vector2i) -> OverwatchAction:
	var order := OverwatchAction.new()
	order.init(unit, at, attack)
	return order


# The ring row named `row_name` as the ring builds it for `unit`, or {} when there is none.
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


# The banks the menu's rescue pick flashes for `body`: the RESCUE row, the body click, the tile pick.
func _flashed_banks(rescuer: Unit, body: Unit) -> Array[Vector2i]:
	assert_array(game.main_action_menu.populate(rescuer)).override_failure_message(
			"fixture: the Rescue row never appeared").contains([MainActionMenu.RESCUE])
	game.select_unit(rescuer, rescuer.movement.cell)
	game.main_action_menu.on_pressed(MainActionMenu.RESCUE, rescuer)
	game._click_picking_target(body.movement.cell)
	var banks: Array[Vector2i] = game.target_pick_cells.duplicate()
	return banks


static func _queued_rescue(squad: Squad) -> RescueAction:
	for action in squad.action_queue:
		if action is RescueAction:
			return action as RescueAction
	return null


# ==============================================================================
#  A carving: the ring, the aim cycle, the gate and the pass
# ==============================================================================

# Fire a squadmate's queued attack lights beside the caster is fire to draw on: the row is live, the
# aim cycle offers the carving, the gate takes the order, and the pass casts it.
func test_a_carving_draws_on_fire_an_earlier_order_lights() -> void:
	var ember := _carving("Ember", "Break(F, A) + Push(F2)")   # makes its own fire: never fizzles
	var ignite := _carving("Ignite", "Push(F2)")
	var carvings: Array[TransmutationData] = [ember, ignite]
	var fire_only: Array[Elemental.Element] = [FIRE]
	var caster := _alchemist(CASTER, carvings, fire_only)
	_spawn(ENEMY, FOE, 200)
	var lighter := _mate(caster, MATE, _blow(1, FIRE, true))

	var reason := CellSubstances.fizzle_reason(ignite, CASTER, game._board(), caster.state)
	assert_str(reason).override_failure_message("fixture: Ignite must fizzle with nothing lit").is_not_empty()
	assert_bool(_row(caster, "Ignite").get("disabled", false)).override_failure_message(
			"fixture: the row must be greyed with nothing lit").is_true()

	_queue_fire(lighter, BESIDE)

	assert_bool(_row(caster, "Ignite").get("disabled", false)).override_failure_message(
			"the ring greys a carving the fire a queued order lights beside it would feed").is_false()
	game.select_unit(caster, CASTER)
	caster.active_attack = ember
	game.enter_attack_mode(caster)
	game.cycle_aimed_attack(1)
	assert_object(caster.get_fired_attack()).override_failure_message(
			"the aim cycle skips a carving the fire a queued order lights would feed").is_same(ignite)
	game.exit_current_mode()
	caster.active_attack = null

	var cast := _declare(caster, ignite, FOE)
	assert_str(_try(caster, cast)).override_failure_message(
			"the gate refuses a carving the fire a queued order lights would feed").is_equal("")
	var landed := _expanded(sm.resolved_plan_for(caster.squad), caster)
	assert_object(landed).override_failure_message("the cast expanded to nothing").is_not_null()
	if landed != null:
		assert_bool(landed.resolved.fizzled).override_failure_message("the pass fizzles the cast the gate took").is_false()
	assert_bool(cast.is_valid).override_failure_message("the queued cast is red: %s" % ", ".join(cast.validation_errors)).is_true()


# The red reach drawn under the ring asks the row's question of the same ground: it grows from a
# carving the fire a queued order lights. Ignite alone, so no other attack draws the same cells.
func test_the_reach_overlay_counts_fire_an_earlier_order_lights() -> void:
	var carvings: Array[TransmutationData] = [_carving("Ignite", "Push(F2)")]
	var fire_only: Array[Elemental.Element] = [FIRE]
	var caster := _alchemist(CASTER, carvings, fire_only)
	_spawn(ENEMY, FOE, 200)
	var lighter := _mate(caster, MATE, _blow(1, FIRE, true))
	game.show_player_reach(caster, CASTER)
	assert_array(game.overlay_manager.reach_overlay.get_used_cells()).override_failure_message(
			"fixture: a carving with nothing lit must draw no reach").is_empty()

	_queue_fire(lighter, BESIDE)

	game.show_player_reach(caster, CASTER)
	var red: Array[Vector2i] = game.overlay_manager.reach_overlay.get_used_cells()
	assert_array(red).override_failure_message(
			"the red reach omits a carving the fire a queued order lights would feed").contains([FOE])


# Water a squadmate's queued attack freezes is no water to draw on: the row greys with the reason, the
# gate refuses in those words, and the pass would fizzle it.
func test_a_carving_whose_water_an_earlier_order_freezes_is_refused() -> void:
	game.grid.paint(BESIDE, GRASS_SOURCE, DEEP_WATER)
	var spray := _carving("Spray", "Focus(W2) + Push(W2)")
	var carvings: Array[TransmutationData] = [spray]
	var water_and_air: Array[Elemental.Element] = [WATER, Elemental.Element.AIR]
	var caster := _alchemist(CASTER, carvings, water_and_air)
	_spawn(ENEMY, FOE, 200)
	var froster := _mate(caster, MATE, _blow(1, ICE, true))
	assert_bool(_row(caster, "Spray").get("disabled", false)).override_failure_message(
			"fixture: beside open water the row must be live").is_false()

	_queue_fire(froster, BESIDE)

	var row := _row(caster, "Spray")
	assert_bool(row.get("disabled", false)).override_failure_message(
			"the ring offers a carving whose water a queued order freezes").is_true()
	assert_str(String(row.get("tooltip", ""))).contains("Fizzles")
	var cast := _declare(caster, spray, FOE)
	var refusal := _try(caster, cast)
	assert_str(refusal).override_failure_message(
			"the gate takes a carving whose water a queued order freezes").starts_with("Fizzles")
	var one: Array[BaseAction] = [cast]
	var trial := sm.resolve_hypothetical(caster.squad, one, game._board())
	var landed := _expanded(trial, caster)
	assert_bool(landed != null and landed.resolved.fizzled).override_failure_message(
			"fixture: the pass must fizzle the cast the gate refused").is_true()
	game.refresh_action_queue(caster.squad)


# ==============================================================================
#  A watch: judged where it arms
# ==============================================================================

# A stored watch is judged at its own queue slot (fork 2): fire lit by an order queued BEFORE it feeds
# it, one queued after it does not count for or against it, and taking the earlier fire away reds it.
func test_a_watch_is_judged_on_the_ground_at_its_slot() -> void:
	var watchfire := _carving("Watchfire", "Push(F2)", true)
	var carvings: Array[TransmutationData] = [watchfire]
	var fire_only: Array[Elemental.Element] = [FIRE]
	var watcher := _alchemist(CASTER, carvings, fire_only)
	var lighter := _mate(watcher, MATE, _blow(1, FIRE, true))
	var douser := _mate(watcher, SECOND_MATE, _blow(1, WATER, true))
	assert_str(_try(watcher, _watch(watcher, watchfire, FOE))).override_failure_message(
			"fixture: a watch with nothing lit must be refused").starts_with("Fizzles")

	_queue_fire(lighter, BESIDE)
	var watch := _watch(watcher, watchfire, FOE)
	assert_str(_try(watcher, watch)).override_failure_message(
			"the gate refuses a watch the fire a queued order lights would feed").is_equal("")
	assert_bool(watch.is_valid).override_failure_message("a watch over lit ground is red").is_true()

	_queue_fire(douser, BESIDE)
	assert_bool(watch.resolved_fizzles).override_failure_message(
			"a douse queued AFTER the watch counted at its slot").is_false()
	assert_bool(watch.is_valid).override_failure_message(
			"a douse queued after the watch reds it: %s" % ", ".join(watch.validation_errors)).is_true()

	sm.remove_action(lighter.squad, _queued_attack_of(lighter.squad, lighter))
	game.refresh_action_queue(watcher.squad)
	assert_bool(watch.resolved_fizzles).override_failure_message(
			"the watch still finds fire once the order lighting it is gone").is_true()
	assert_array(watch.validation_errors).override_failure_message(
			"a watch whose fire is gone stays green").contains(["Fizzles where they'll be standing"])

	_queue_fire(lighter, BESIDE)
	assert_bool(watch.resolved_fizzles).override_failure_message(
			"fire lit by an order queued AFTER the watch counted at its slot").is_true()


static func _queued_attack_of(squad: Squad, actor: Unit) -> BaseAction:
	for action in squad.action_queue:
		if action.actor == actor and action is AttackAction:
			return action
	return null


# ==============================================================================
#  A rescue: the banks the tail leaves
# ==============================================================================

# Water a squadmate's queued attack freezes beside the rescuer is a bank: flashed, taken at the gate,
# and the haul lands in the pass.
func test_a_haul_onto_ice_an_earlier_order_freezes() -> void:
	game.grid.paint(LAKE, GRASS_SOURCE, DEEP_WATER)
	var f: Dictionary = await _rescuer_beside_a_drowning_body()
	var rescuer: Unit = f.rescuer
	var body: Unit = f.body
	var froster := _mate(rescuer, LAKESIDE, _blow(1, ICE, true))
	assert_bool(RulesService.rescue_landings(rescuer, body, game._board()).has(LAKE)).override_failure_message(
			"fixture: open water must be no bank").is_false()

	_queue_fire(froster, LAKE)

	assert_array(_flashed_banks(rescuer, body)).override_failure_message(
			"the rescue pick does not flash ice a queued order makes").contains([LAKE])
	game._click_picking_target(LAKE)
	var rescue := _queued_rescue(rescuer.squad)
	assert_object(rescue).override_failure_message("the click on the frozen lake queued no rescue").is_not_null()
	if rescue == null:
		return
	game.refresh_action_queue(rescuer.squad)
	assert_that(rescue.haul_to).is_equal(LAKE)
	assert_bool(rescue.resolved_haul_lands).override_failure_message("the pass does not land the haul the gate took").is_true()
	assert_bool(rescue.is_valid).override_failure_message("the haul is red: %s" % ", ".join(rescue.validation_errors)).is_true()


# Ice a squadmate's queued fire melts is no bank: not flashed, refused at the gate in the validator's
# words, and the pass would not land it.
func test_a_haul_onto_ice_an_earlier_order_melts_is_refused() -> void:
	_ice(LAKE)
	var f: Dictionary = await _rescuer_beside_a_drowning_body()
	var rescuer: Unit = f.rescuer
	var body: Unit = f.body
	var lighter := _mate(rescuer, LAKESIDE, _blow(1, FIRE, true))
	assert_bool(RulesService.rescue_landings(rescuer, body, game._board()).has(LAKE)).override_failure_message(
			"fixture: the ice must be a bank to begin with").is_true()

	_queue_fire(lighter, LAKE)

	assert_array(_flashed_banks(rescuer, body)).override_failure_message(
			"the rescue pick flashes ice a queued order melts").not_contains([LAKE])
	game.exit_current_mode()
	var rescue := RescueAction.new()
	rescue.init(rescuer, body, LAKE)
	assert_str(_try(rescuer, rescue)).override_failure_message(
			"the gate takes a haul onto ice a queued order melts").contains(NOT_A_BANK)
	var one: Array[BaseAction] = [rescue]
	sm.resolve_hypothetical(rescuer.squad, one, game._board())
	assert_bool(rescue.resolved_haul_lands).override_failure_message(
			"fixture: the pass must refuse the haul the gate refused").is_false()
	game.refresh_action_queue(rescuer.squad)


# A rescue meets the ground AFTER the counters (fork 1): an enemy's counter that freezes the lake makes
# a bank the tail has and the attack prefix does not -- the case that tells the two snapshots apart.
func test_a_counter_that_freezes_the_lake_makes_a_bank() -> void:
	game.grid.paint(LAKE, GRASS_SOURCE, DEEP_WATER)
	var f: Dictionary = await _rescuer_beside_a_drowning_body()
	var rescuer: Unit = f.rescuer
	var body: Unit = f.body
	var mate := _mate(rescuer, LAKESIDE, _blow(2))
	var foe := _spawn(ENEMY, LAKESIDE_FOE, 200)
	var frost := _blow(1, ICE)
	frost.targets = EquippableData.TargetMode.BOTH
	var plus: Array[Vector2i] = [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	P.stamped(frost, 1, plus)
	_arm(foe, frost)

	_queue_fire(mate, LAKESIDE_FOE)

	var plan := sm.resolved_plan_for(rescuer.squad)
	assert_bool(plan.tail_tiles.has_state(LAKE, Terrain.TileState.FROZEN)).override_failure_message(
			"fixture: the foe's counter must freeze the lake").is_true()
	assert_bool(RulesService.rescue_landings(rescuer, body, sm.candidate_board(rescuer.squad)).has(LAKE)) \
		.override_failure_message("fixture: the attack prefix must not have the counter's ice").is_false()
	assert_array(_flashed_banks(rescuer, body)).override_failure_message(
			"the rescue pick does not flash ice a counter makes before the rescue runs").contains([LAKE])
	game._click_picking_target(LAKE)
	var rescue := _queued_rescue(rescuer.squad)
	assert_object(rescue).override_failure_message("the gate refused a haul onto the counter's ice").is_not_null()
	if rescue == null:
		return
	game.refresh_action_queue(rescuer.squad)
	assert_bool(rescue.resolved_haul_lands).override_failure_message("the pass does not land the haul the gate took").is_true()


# ==============================================================================
#  The AI's seek: one key per fate, read on the planned ground
# ==============================================================================

# Two origins that differ only in the fire a queued order lights beside one of them share a key on the
# live board, and must not on the ground the base plan leaves: the resolve empowers the one beside it.
func test_the_seek_key_reads_the_base_plans_ground() -> void:
	var ignite := _carving("Ignite", "Push(F2)")
	var carvings: Array[TransmutationData] = [ignite]
	var fire_only: Array[Elemental.Element] = [FIRE]
	var caster := _alchemist(Vector2i(WIDTH - 1, HEIGHT - 1), carvings, fire_only)
	var kindling := Vector2i(1, 1)
	var lit_side := Vector2i(2, 1)      # beside kindling
	var far_side := Vector2i(2, 3)      # past Materia.REACH of it
	var target := Vector2i(4, 2)
	var lighter := _mate(caster, Vector2i(1, 0), _blow(1, FIRE, true))
	_queue_fire(lighter, kindling)

	var board: BoardContext = game._board()
	var none: Array[BaseAction] = []
	var base_plan := sm.resolve_hypothetical(caster.squad, none, board)
	var candidates: Array[AttackAction] = [
		AttackAction.declare(caster, lit_side, target), AttackAction.declare(caster, far_side, target)]
	for candidate in candidates:
		candidate.fired_attack = ignite
	var bare := AITactics._group_keys(candidates, board, null)
	assert_str(bare[0]).override_failure_message("fixture: the two origins differ in more than the fire").is_equal(bare[1])

	var keys := AITactics._group_keys(candidates, board, base_plan.prefix_tiles)
	assert_str(keys[0]).override_failure_message(
			"two origins the base plan's fire tells apart share one seek key").is_not_equal(keys[1])
	assert_object(board.tiles).override_failure_message("the seek's board kept the tiles it was lent").is_null()
	game.refresh_action_queue(caster.squad)


# ==============================================================================
#  The Play API: the same judges, headless
# ==============================================================================

func _headless(root_name: String) -> Dictionary:
	var b := BoardBuilder.build(self, root_name)
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(0, 0, WIDTH, HEIGHT))
	return b


func _headless_unit(b: Dictionary, faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = BoardBuilder.spawn(b, H.make_unit_data({Stats.Stat.MHP: 80}, faction), cell)
	unit.set_current_hp(unit.get_max_hp())
	return unit


func _headless_mate(b: Dictionary, lead: Unit, cell: Vector2i, attack: WeaponAttackData) -> Unit:
	var mate := _headless_unit(b, PLAYER, cell)
	_arm(mate, attack)
	(b.squad_manager as SquadManager).join_squad(mate, lead.squad)
	return mate


func test_the_play_api_lists_a_carving_an_earlier_orders_fire_feeds() -> void:
	var b := _headless("CandidateGroundCarving")
	var caster := _headless_unit(b, PLAYER, CASTER)
	caster.unit_instance.aura = {FIRE: 4}
	var fire_only: Array[Elemental.Element] = [FIRE]
	caster.unit_instance.affinity = fire_only
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	assert_bool(rune.inscribe(_carving("Ignite", "Push(F2)"))).is_true()
	assert_bool(caster.add_item(rune)).is_true()
	caster.equipped_weapon = rune
	_headless_unit(b, ENEMY, FOE)
	var lighter := _headless_mate(b, caster, MATE, _blow(1, FIRE, true))
	var sess = PlaySession.new(b)
	var before: Dictionary = sess.legal_targets(sess.handle_for(caster), "Ignite")
	assert_bool(before.ok).override_failure_message("fixture: with nothing lit the carving must have no aims").is_false()

	var lit: Dictionary = sess.queue_attack(sess.handle_for(lighter), BESIDE)
	assert_bool(lit.ok).override_failure_message("fixture: the lighter was refused: %s" % str(lit.get("error", ""))).is_true()

	var after: Dictionary = sess.legal_targets(sess.handle_for(caster), "Ignite")
	assert_bool(after.ok).override_failure_message(
			"the Play API lists no aims for a carving a queued order's fire feeds: %s" % str(after.get("error", ""))).is_true()
	if after.ok:
		assert_array(after.aims).is_not_empty()


func test_the_play_api_rescues_onto_ice_an_earlier_order_freezes() -> void:
	var b := _headless("CandidateGroundRescue")
	BoardBuilder.paint_cell(b.grid, LAKE, BoardBuilder.WATER_ATLAS)
	var rescuer := _headless_unit(b, PLAYER, RESCUER)
	var body := _headless_unit(b, PLAYER, BODY)
	BoardBuilder.paint_cell(b.grid, BODY, BoardBuilder.WATER_ATLAS)
	var froster := _headless_mate(b, rescuer, LAKESIDE, _blow(1, ICE, true))
	var sess = PlaySession.new(b)   # after every unit: the session names the units it starts with
	body.take_damage(body.get_current_hp())
	sess._process_downed_pending()
	var refused: Dictionary = sess.rescue(sess.handle_for(rescuer), sess.handle_for(body), LAKE)
	assert_bool(refused.ok).override_failure_message("fixture: open water must be no bank").is_false()

	var frozen: Dictionary = sess.queue_attack(sess.handle_for(froster), LAKE)
	assert_bool(frozen.ok).override_failure_message("fixture: the froster was refused: %s" % str(frozen.get("error", ""))).is_true()

	var res: Dictionary = sess.rescue(sess.handle_for(rescuer), sess.handle_for(body), LAKE)
	assert_bool(res.ok).override_failure_message(
			"the Play API refuses a haul onto ice a queued order makes: %s" % str(res.get("error", ""))).is_true()
