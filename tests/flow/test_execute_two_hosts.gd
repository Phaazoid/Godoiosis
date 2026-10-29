# TWO HOSTS, ONE PASS (#46). A queued plan is played by two executors -- the game's OrderExecutor and
# the headless PlaySession.execute -- and since #46 both run the same state code for it: an attack's
# open_playback / land / remove / settle, a walk's soaking at the moments ResolvedPlan.walk_moments
# names, and the pass end's two sweeps (SquadManager.settle_downed, then enforce_contact). The one
# declared per-host difference is HOW a shoved body gets to its landing (the game slides it, headless
# teleports it). This is the law that keeps the rest honest: one board, authored through the game's
# own capture and loaded by both hosts, given the same orders through each host's own doors, must come
# out of the pass the same in both, unit by unit.
#
# What it cannot see, by construction: a fault inside one of the shared steps moves both hosts together
# and they still agree. The per-mechanic suites (test_healing, test_carbine, the ford cases in
# test_watch_shot_interrupts_the_walk, test_guard, test_payload_play, test_vial_burn, ...) pin those.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const TEST_SAVE_DIR := "user://__test_saves_execute_two_hosts/"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const SHALLOW_WATER := Vector2i(6, 6)   # TestTiles' wadeable water (#116)
const DEEP_WATER := Vector2i(5, 6)      # TestTiles' deep water, which drowns and freezes
const HOLE_TILE := Vector2i(18, 2)      # TestTiles' authored VOID tile
const WIDTH := 10
const HEIGHT := 4

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _main: Node
var game: Node2D
var sm: ScenarioManager
var _sess
var _written: Array[String] = []


func before_test() -> void:
	ScenarioManager.save_dir = TEST_SAVE_DIR
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	sm = game.scenario_manager
	game.mission_controller._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	ScenarioManager.save_dir = ScenarioManager.DEFAULT_SAVE_DIR
	ReactionCatalog.refresh()   # the ford case's H.only_electrocution goes with it
	_sess = null
	for path in _written:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_written.clear()


# --- authoring, on the game's board -------------------------------------------------------------

func _spawn(faction: Team.Faction, cell: Vector2i, mhp := 80) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: mhp}, faction), cell)
	assert_object(unit).override_failure_message("fixture: nothing would spawn at %s" % cell).is_not_null()
	unit.set_current_hp(unit.get_max_hp())
	return unit


# A one-attack weapon, carried (add_item) rather than assigned, so the capture saves it.
func _weapon(attack: WeaponAttackData, family := WeaponData.WeaponType.CHAINSWORD) -> WeaponInstance:
	var t := WeaponData.new()
	t.weapon_type = family
	t.main_attack = attack
	return WeaponInstance.make(t)


func _blow(power: int) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.display_name = "Blow"
	attack.power = power
	return attack


func _arm(unit: Unit, attack: WeaponAttackData, family := WeaponData.WeaponType.CHAINSWORD) -> void:
	assert_bool(unit.add_item(_weapon(attack, family))).override_failure_message("fixture: the weapon did not fit").is_true()


# Paint, let `build` place everything, and save the game's own capture of it. A file of its own per
# case: load() serves the resource cache, so a second board saved over one path comes back as the first.
func _author(tag: String, build: Callable) -> String:
	for x in range(WIDTH):
		for y in range(HEIGHT):
			game.grid.paint(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	build.call()
	var path := "user://__execute_two_hosts_%s.tres" % tag
	assert_int(ResourceSaver.save(sm.capture_scenario("execute_two_hosts_%s" % tag), path)).is_equal(OK)
	_written.append(path)
	return path


# --- the two hosts ------------------------------------------------------------------------------

# Every unit by the cell it stood on as the board loaded -- the one identity both hosts share.
static func _by_cell(units: Array[Unit]) -> Dictionary:
	var by_cell := {}
	for unit in units:
		by_cell[unit.movement.cell] = unit
	return by_cell


func _order_game(units: Dictionary, order: Dictionary) -> void:
	var unit: Unit = units[order.from]
	game.select_unit(unit, unit.movement.cell)
	match order.verb:
		"move":
			game.enter_move_mode(unit)
			game._click_choosing_move(order.to)
			var moved := false
			for action in unit.squad.action_queue:
				moved = moved or (action is MoveAction and action.actor == unit and not (action as MoveAction).is_hold_position)
			assert_bool(moved).override_failure_message("the game refused the move %s" % str(order)).is_true()
		"attack":
			game.enter_attack_mode(unit)
			game._click_attack_targeting(order.at)
			assert_bool(unit.has_action_type_queued(BaseAction.ActionType.ATTACK)) \
				.override_failure_message("the game refused the attack %s" % str(order)).is_true()


func _order_headless(units: Dictionary, order: Dictionary) -> void:
	var unit: Unit = units[order.from]
	var handle: String = _sess.handle_for(unit)
	var res: Dictionary = {}
	match order.verb:
		"move":
			res = _sess.queue_move(handle, order.to)
		"attack":
			res = _sess.queue_attack(handle, order.at)
	assert_bool(res.get("ok", false)).override_failure_message(
			"the Play API refused %s: %s" % [str(order), str(res.get("error", ""))]).is_true()


# One saved board into both hosts, `prepare` run on each the same way, the orders given through each
# host's own doors and the pass played by each. Answers both hosts' units by their loading cell, and
# the game's plan as it was resolved before its pass ran.
func _run(path: String, orders: Array[Dictionary], prepare: Callable = Callable()) -> Dictionary:
	sm.load_scenario(path)
	await await_idle_frame()
	var board := BoardBuilder.build(self, "ExecuteTwoHostsHeadless")
	auto_free(board.root)
	await BoardBuilder.load_scenario(board, path)
	_sess = PlaySession.new(board)

	var game_units := _by_cell(game._all_units())
	var play_units := _by_cell(_sess.live_units())
	assert_array(play_units.keys()).override_failure_message("the two loaders placed different units") \
		.contains_exactly_in_any_order(game_units.keys())
	if prepare.is_valid():
		prepare.call(game_units)
		prepare.call(play_units)

	for order in orders:
		_order_game(game_units, order)
		_order_headless(play_units, order)

	var actor: Unit = game_units[orders[0].from]
	var plan: ResolvedPlan = game.squad_manager.resolve_plan(actor.squad, game._board())
	var planned := _planned_tiles(plan)
	var game_before := _tiles_of(game.terrain_states, game.gas_field)
	var play_before := _tiles_of(board.terrain_states, board.gas_field)
	await game.order_executor.execute_orders(actor.squad.get_leader())
	var played: Dictionary = _sess.execute()
	assert_bool(played.get("ok", false)).override_failure_message(
			"the headless pass did not execute: %s" % str(played.get("error", ""))).is_true()
	return {"game": game_units, "play": play_units, "plan": plan, "planned": planned,
			"tiles": {"game": [game_before, _tiles_of(game.terrain_states, game.gas_field)],
				"play": [play_before, _tiles_of(board.terrain_states, board.gas_field)]},
			"events": played.get("events", [])}


# --- the tiles ----------------------------------------------------------------------------------

const NO_TILE := "[] gas=0"


static func _tile(states: Array[Terrain.TileState], packed: int) -> String:
	var sorted := states.duplicate()
	sorted.sort()
	return "%s gas=%d" % [str(sorted), packed]


# Every cell either store holds anything on, as one comparable line each.
static func _tiles_of(states: TerrainStateManager, gas: GasField) -> Dictionary:
	var out := {}
	var cells: Array[Vector2i] = []
	cells.assign(states.to_state_dict().keys())
	for cell in gas.cells():
		if not cells.has(cell):
			cells.append(cell)
	for cell in cells:
		out[cell] = _tile(states.states_at(cell), gas.packed_at(cell))
	return out


# Where the plan says the pass leaves each cell it touches (ResolvedPlan.tiles), read before anything plays.
static func _planned_tiles(plan: ResolvedPlan) -> Dictionary:
	var out := {}
	if plan.tiles == null:
		return out
	for cell in plan.tiles.cells():
		out[cell] = _tile(plan.tiles.states_at(cell), plan.tiles.gas_at(cell))
	return out


# THE TILE HALF OF LAW #2 (#1498): in both hosts, every cell the plan touches ends as the plan said, and
# every other cell ends as it started.
func _assert_tiles_as_planned(ran: Dictionary) -> void:
	var planned: Dictionary = ran.planned
	for host: String in ["game", "play"]:
		var before: Dictionary = ran.tiles[host][0]
		var after: Dictionary = ran.tiles[host][1]
		var cells := {}
		for cell: Vector2i in before.keys() + after.keys() + planned.keys():
			cells[cell] = true
		for cell: Vector2i in cells:
			var want: String = planned[cell] if planned.has(cell) else before.get(cell, NO_TILE)
			assert_str(after.get(cell, NO_TILE)).override_failure_message(
					"the %s host left %s as %s; the plan said %s" % [host, cell, after.get(cell, NO_TILE), want]) \
				.is_equal(want)


# THE BODY HALF: the game's live units after the pass against the plan the game resolved before it.
static func _body(hp: int, lifecycle: Unit.LifecycleState, cell: Vector2i, states: Array[Elemental.State]) -> String:
	var sorted := states.duplicate()
	sorted.sort()
	return "hp=%d %s cell=%s states=%s" % [hp, Unit.LifecycleState.keys()[lifecycle], cell, str(sorted)]


func _assert_bodies_as_planned(ran: Dictionary) -> void:
	var plan: ResolvedPlan = ran.plan
	for at: Vector2i in ran.game:
		var held: Variant = ran.game[at]
		if not is_instance_valid(held) or (held as Node).is_queued_for_deletion():
			continue
		var unit := held as Unit
		var body := PlanResolver.state_of(unit, plan.hypo)
		var want := _body(body.get_current_hp(), body.lifecycle_state, PlanResolver.projected_position(unit, plan.hypo),
				body.element_states)
		var got := _body(unit.get_current_hp(), unit.lifecycle_state, unit.movement.cell, unit.element_states)
		assert_str(got).override_failure_message(
				"the unit loaded at %s left the pass as %s; the plan said %s" % [at, got, want]).is_equal(want)


# Everything the pass can leave on a unit, by loading cell so the two hosts' objects compare.
static func _picture(units: Dictionary, cell: Vector2i) -> String:
	var held: Variant = units[cell]
	if not is_instance_valid(held) or (held as Node).is_queued_for_deletion():
		return "gone"
	var unit := held as Unit
	var cell_of := {}
	for at: Vector2i in units:
		cell_of[units[at]] = at
	var states: Array[Elemental.State] = unit.element_states.duplicate()
	states.sort()
	var effects: Array[String] = []
	for effect in unit.stat_effects:
		effects.append("%s:%d" % [effect.source_name, effect.turns_remaining])
	effects.sort()
	var guard := "none"
	if unit.guard != null:
		guard = "spent=%s ward=%s" % [unit.guard.spent, cell_of.get(unit.guard.ward, "?") if is_instance_valid(unit.guard.ward) else "gone"]
	var watch := "none"
	if unit.watch != null:
		watch = "spent=%s cancelled=%s" % [unit.watch.spent, unit.watch.cancelled]
	var equipped: Variant = unit.get_equipped_weapon()
	var weapon: Dictionary = (equipped as WeaponInstance).capture_battle_state() if equipped is WeaponInstance else {}
	var squad := unit.squad
	return str({
		"hp": unit.get_current_hp(),
		"lifecycle": Unit.LifecycleState.keys()[unit.lifecycle_state],
		"cell": unit.movement.cell,
		"states": states,
		"effects": effects,
		"guard": guard,
		"watch": watch,
		"weapon": weapon,
		"attuned": unit.attunement != null,
		"leader": cell_of.get(squad.leader, "?"),
		"members": squad.get_members().size(),
		"acted": squad.has_acted,
	})


func _assert_hosts_agree(ran: Dictionary) -> void:
	var game_units: Dictionary = ran.game
	var play_units: Dictionary = ran.play
	for cell: Vector2i in game_units:
		var in_game := _picture(game_units, cell)
		var headless := _picture(play_units, cell)
		assert_str(headless).override_failure_message(
				"the unit loaded at %s left the pass differently:\n  game     %s\n  headless %s" % [cell, in_game, headless]) \
			.is_equal(in_game)
	_assert_bodies_as_planned(ran)
	_assert_tiles_as_planned(ran)


# --- the cases ----------------------------------------------------------------------------------

func test_a_heal() -> void:
	var path := _author("heal", func() -> void:
		var healer := _spawn(PLAYER, Vector2i(1, 1))
		var mend := _blow(6)
		mend.heals = true
		mend.hits_allies = true
		_arm(healer, mend)
		var patient := _spawn(PLAYER, Vector2i(2, 1), 40)
		patient.set_current_hp(10))

	var ran: Dictionary = await _run(path, [{"verb": "attack", "from": Vector2i(1, 1), "at": Vector2i(2, 1)}])

	var patient: Unit = ran.game[Vector2i(2, 1)]
	assert_int(patient.get_current_hp()).override_failure_message("fixture: the heal restored nothing in the game").is_greater(10)
	_assert_hosts_agree(ran)


# A counter the pass skips: the hero's blow drops the foe, so the foe's Carbine counter never fires.
func test_a_skipped_carbine_counter() -> void:
	var path := _author("carbine", func() -> void:
		_arm(_spawn(PLAYER, Vector2i(1, 1)), _blow(5))
		var foe := _spawn(ENEMY, Vector2i(2, 1))
		var shot := _blow(4)
		shot.requires_readiness = true
		shot.consumes_readiness = true
		_arm(foe, shot, WeaponData.WeaponType.CARBINE)
		foe.set_current_hp(1))

	var ran: Dictionary = await _run(path, [{"verb": "attack", "from": Vector2i(1, 1), "at": Vector2i(2, 1)}])

	var plan: ResolvedPlan = ran.plan
	var skipped := false
	for counter in plan.counters:
		skipped = skipped or (counter.resolved != null and counter.resolved.skipped)
	assert_bool(skipped).override_failure_message("fixture: the plan skips no counter").is_true()
	_assert_hosts_agree(ran)


# A walk through a ford with a shock watch over it: the soaking and the shot that strips it (#884).
func test_a_ford_walk_under_a_shock_watch() -> void:
	H.only_electrocution()
	var ford := Vector2i(2, 1)
	var path := _author("ford", func() -> void:
		game.grid.paint(ford, GRASS_SOURCE, SHALLOW_WATER)
		_spawn(PLAYER, Vector2i(0, 1))
		var watcher := _spawn(ENEMY, Vector2i(2, 3))
		var zap := _blow(4)
		zap.elemental_damage_type = Elemental.Element.SHOCK
		zap.can_overwatch = true   # the capture saves a watch by its place among the watch attacks
		_arm(watcher, zap)
		var footprint: Array[Vector2i] = [ford]
		watcher.arm_watch(watcher.movement.cell, ford, footprint, watcher.overwatch_attacks()[0])
		assert_object(watcher.watch).override_failure_message("fixture: the watch did not arm").is_not_null())

	var ran: Dictionary = await _run(path, [{"verb": "move", "from": Vector2i(0, 1), "to": Vector2i(3, 1)}])

	var plan: ResolvedPlan = ran.plan
	assert_int(plan.mid_walk_shots().size()).override_failure_message("fixture: the ford's watch never fired").is_greater(0)
	_assert_hosts_agree(ran)


# A shove into a hole: the slide in the game, the teleport headlessly -- the one declared difference.
func test_a_void_shove() -> void:
	var path := _author("void", func() -> void:
		game.grid.paint(Vector2i(3, 1), GRASS_SOURCE, HOLE_TILE)
		var shove := _blow(2)
		shove.knockback = 1
		_arm(_spawn(PLAYER, Vector2i(1, 1)), shove)
		_spawn(ENEMY, Vector2i(2, 1)))

	var ran: Dictionary = await _run(path, [{"verb": "attack", "from": Vector2i(1, 1), "at": Vector2i(2, 1)}])

	assert_str(_picture(ran.game, Vector2i(2, 1))).override_failure_message("fixture: nobody went into the hole").is_equal("gone")
	_assert_hosts_agree(ran)


# A Guard armed before the board was saved takes the blow aimed at its ward (#414).
func test_a_guard() -> void:
	var path := _author("guard", func() -> void:
		_arm(_spawn(PLAYER, Vector2i(1, 1)), _blow(4))
		var ward := _spawn(ENEMY, Vector2i(2, 1))
		var blocker := _spawn(ENEMY, Vector2i(3, 1))
		blocker.arm_guard(ward, blocker.get_guard_range())
		assert_object(blocker.guard).override_failure_message("fixture: the guard did not arm").is_not_null())

	var ran: Dictionary = await _run(path, [{"verb": "attack", "from": Vector2i(1, 1), "at": Vector2i(2, 1)}])

	var blocker: Unit = ran.game[Vector2i(3, 1)]
	assert_bool(blocker.guard != null and blocker.guard.spent).override_failure_message(
			"fixture: the guard absorbed nothing in the game").is_true()
	_assert_hosts_agree(ran)


# A member a displacement the plan never chose left out of its leader's reach splits when ANY pass
# settles -- the game's own pass-end wire case (test_squad_cohesion), here with a bystander's walk.
func test_a_contact_split() -> void:
	var path := _author("contact", func() -> void:
		_spawn(PLAYER, Vector2i(1, 1))
		var leader := _spawn(ENEMY, Vector2i(9, 0))
		var member := _spawn(ENEMY, Vector2i(8, 0))
		game.squad_manager.join_squad(member, leader.squad))
	var displace := func(units: Dictionary) -> void:
		(units[Vector2i(8, 0)] as Unit).movement.set_cell(Vector2i(0, 3))

	var ran: Dictionary = await _run(path, [{"verb": "move", "from": Vector2i(1, 1), "to": Vector2i(2, 1)}], displace)

	var member: Unit = ran.game[Vector2i(8, 0)]
	assert_int(member.squad.get_members().size()).override_failure_message(
			"fixture: the member was never split off in the game").is_equal(1)
	_assert_hosts_agree(ran)


# A hit that DROPS a payload (#1058): the payload lands, and spends none of what its thrower carries.
func test_a_payload() -> void:
	var path := _author("payload", func() -> void:
		var spring := _blow(3)
		spring.consumes_readiness = true
		P.point(spring, 1)
		var tap := _blow(1)
		P.point(tap, 1)
		tap.payload = spring
		_arm(_spawn(PLAYER, Vector2i(1, 1)), tap, WeaponData.WeaponType.SPRINGSPEAR)
		_spawn(ENEMY, Vector2i(2, 1), 200))

	var ran: Dictionary = await _run(path, [{"verb": "attack", "from": Vector2i(1, 1), "at": Vector2i(2, 1)}])

	var plan: ResolvedPlan = ran.plan
	var dropped := false
	for attack in plan.attacks:
		dropped = dropped or attack.dropped_by != null
	assert_bool(dropped).override_failure_message("fixture: the hit dropped no payload").is_true()
	_assert_hosts_agree(ran)


# A lake an attack freezes, and an enemy whose counter throws a squadmate into it (#1498's probe).
const LAKE := Vector2i(4, 1)
const FROSTER_AT := Vector2i(4, 0)
const MATE_AT := Vector2i(3, 1)
const FOE_AT := Vector2i(2, 1)


func _author_frozen_lake(tag: String) -> String:
	return _author(tag, func() -> void:
		game.grid.paint(LAKE, GRASS_SOURCE, DEEP_WATER)
		var froster := _spawn(PLAYER, FROSTER_AT)
		var frost := _blow(1)
		frost.elemental_damage_type = Elemental.Element.ICE
		frost.targets = EquippableData.TargetMode.MAP
		_arm(froster, frost)
		var mate := _spawn(PLAYER, MATE_AT)
		_arm(mate, _blow(2))
		game.squad_manager.join_squad(froster, mate.squad)
		var shove := _blow(2)
		shove.knockback = 1
		_arm(_spawn(ENEMY, FOE_AT), shove))


func _lake_orders() -> Array[Dictionary]:
	return [{"verb": "attack", "from": FROSTER_AT, "at": LAKE}, {"verb": "attack", "from": MATE_AT, "at": FOE_AT}]


# The live counter that answers the squadmate's blow.
static func _counter_on(plan: ResolvedPlan, mate: Unit) -> CounterAttackAction:
	for counter in plan.counters:
		if counter.target == mate and counter.resolved != null and not counter.resolved.skipped:
			return counter
	return null


func _assert_the_lake_freezes_and_the_counter_throws(ran: Dictionary) -> CounterAttackAction:
	var plan: ResolvedPlan = ran.plan
	var freezes := false
	for effect in plan.cell_effects:
		freezes = freezes or (effect.cell == LAKE and effect.states_added.has(Terrain.TileState.FROZEN))
	assert_bool(freezes).override_failure_message("fixture: the froster's attack never froze the lake").is_true()
	var counter := _counter_on(plan, ran.game[MATE_AT])
	assert_object(counter).override_failure_message("fixture: the enemy never countered the squadmate").is_not_null()
	if counter != null:
		assert_that(counter.resolved.knockback_to).override_failure_message(
				"fixture: the counter did not throw the squadmate into the lake").is_equal(LAKE)
	return counter


# #1498's verify-first probe, kept as the arc's guard. The froster's attack freezes the lake, and the
# enemy's counter throws the squadmate onto it: ruling 2, a tile change counts at the hit that makes it,
# so the squadmate lands on the ice and does not drown -- in the row, and in both hosts.
func test_a_counter_throws_a_squadmate_onto_ice_the_pass_froze() -> void:
	var ran: Dictionary = await _run(_author_frozen_lake("ice"), _lake_orders())

	var counter := _assert_the_lake_freezes_and_the_counter_throws(ran)
	if counter == null:
		return
	assert_int(counter.resolved.drown_damage).override_failure_message(
			"the counter drowns the squadmate in a lake the pass has already frozen").is_equal(0)
	assert_that(PlanResolver.projected_lifecycle(ran.game[MATE_AT], (ran.plan as ResolvedPlan).hypo)) \
		.is_equal(Unit.LifecycleState.ACTIVE)
	_assert_hosts_agree(ran)


# An alchemist whose one carving is a range-2 Fireball, carrying a Vial of Sulfur for _attune_at.
func _alchemist(cell: Vector2i) -> Unit:
	var fire := Elemental.Element.FIRE
	var alchemist := _spawn(PLAYER, cell)
	alchemist.unit_instance.aura = {fire: 4}
	var affinity: Array[Elemental.Element] = [fire]
	alchemist.unit_instance.affinity = affinity
	var fireball := TransmutationData.new()
	fireball.display_name = "Fireball"
	fireball.power = 4
	# Its flame made out of the ambient air: a lone Push(F2) FIZZLES on a board with no fire on it
	# (Deep Alchemy Phase 2), and a fizzle burns no vial.
	fireball.recipe = "Break(F, A) + Push(F2)"
	fireball.targets = EquippableData.TargetMode.UNIT
	P.point(fireball, 2)
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	rune.inscriptions.assign([fireball])
	assert_bool(alchemist.add_item(rune)).override_failure_message("fixture: the rune did not fit").is_true()
	var vial := VialData.new()
	vial.element = fire
	vial.display_name = "Vial of Sulfur"
	assert_bool(alchemist.add_item(vial)).override_failure_message("fixture: the vial did not fit").is_true()
	return alchemist


# The `prepare` that pops the alchemist's vial through the inventory's own door, on each host's copy --
# a live attunement is not saved.
func _attune_at(cell: Vector2i) -> Callable:
	return func(units: Dictionary) -> void:
		var alchemist: Unit = units[cell]
		var at := -1
		for i in alchemist.inventory.size():
			if alchemist.inventory[i] is VialData:
				at = i
		assert_str(alchemist.use_vial(at)).override_failure_message("fixture: the vial would not pop").is_equal("")


# A cast that draws on a vial's charge burns it (#697), in both hosts.
func test_a_vial_burn() -> void:
	var path := _author("vial", func() -> void:
		_alchemist(Vector2i(1, 1))
		_spawn(ENEMY, Vector2i(3, 1), 200))

	var ran: Dictionary = await _run(path, [{"verb": "attack", "from": Vector2i(1, 1), "at": Vector2i(3, 1)}],
			_attune_at(Vector2i(1, 1)))

	var plan: ResolvedPlan = ran.plan
	var burned := false
	for attack in plan.attacks:
		burned = burned or (attack.resolved != null and attack.resolved.burned_vial != null)
	assert_bool(burned).override_failure_message("fixture: the cast drew on no charge").is_true()
	_assert_hosts_agree(ran)


# A second hit on a target the pass already killed WHIFFS and still spends (#1350; dev, 2026-10-21: "It
# should whiff and still spend, and the preview should reflect that"). The killer swings first; the
# alchemist's cast then finds the foe gone. The preview stamps the whiff and the vial it burns, and both
# hosts burn that vial. Until #1350 both skipped the swing outright, keeping a charge the queue showed spent.
func test_a_whiff_on_a_target_the_pass_killed() -> void:
	var killer_cell := Vector2i(2, 1)
	var alchemist_cell := Vector2i(2, 2)
	var foe_cell := Vector2i(3, 1)
	var path := _author("whiff", func() -> void:
		var killer := _spawn(PLAYER, killer_cell)
		_arm(killer, _blow(40))
		game.squad_manager.join_squad(_alchemist(alchemist_cell), killer.squad)
		_spawn(ENEMY, foe_cell).set_current_hp(1))

	var ran: Dictionary = await _run(path, [
			{"verb": "attack", "from": killer_cell, "at": foe_cell},
			{"verb": "attack", "from": alchemist_cell, "at": foe_cell}], _attune_at(alchemist_cell))

	var plan: ResolvedPlan = ran.plan
	var cast: AttackAction = null
	for attack in plan.attacks:
		if attack.actor == ran.game[alchemist_cell]:
			cast = attack
	assert_object(cast).override_failure_message("fixture: the alchemist's aim expanded to nothing").is_not_null()
	assert_bool(cast.resolved.whiffed).override_failure_message("the preview did not show the cast whiffing").is_true()
	assert_object(cast.resolved.burned_vial).override_failure_message("the preview's whiff burns no vial").is_not_null()
	# ...and what the preview spent, each host spends.
	for host: String in ["game", "play"]:
		var units: Dictionary = ran[host]
		assert_str(_picture(units, foe_cell)).override_failure_message(
				"fixture: the killer's blow did not kill in %s" % host).is_equal("gone")
		assert_object((units[alchemist_cell] as Unit).attunement).override_failure_message(
				"the %s host kept the vial the preview showed the whiff burning" % host).is_null()
	_assert_hosts_agree(ran)


# ...and the AoE shape of it: a volley whose LEAD victim the pass killed still fires. The lead whiffs, the
# second victim takes its hit, the round is spent once and the blow publishes its one impact. Until #1350
# the dead lead refused playback, and with it the whole volley's spend and its volley_struck.
func test_a_volley_whose_lead_the_pass_killed() -> void:
	var killer_cell := Vector2i(2, 1)
	var gunner_cell := Vector2i(2, 2)
	var lead_cell := Vector2i(3, 1)
	var second_cell := Vector2i(4, 1)
	var path := _author("whiff_volley", func() -> void:
		var killer := _spawn(PLAYER, killer_cell)
		_arm(killer, _blow(40))
		var gunner := _spawn(PLAYER, gunner_cell)
		var burst := _blow(4)
		burst.requires_readiness = true
		burst.consumes_readiness = true
		# The aimed cell and the one east of it, as a true AoE: a placed shape emits west to east within
		# a row, so the foe on the aimed cell is the volley's lead.
		P.stamped(burst, 2, [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
		burst.swing = false
		_arm(gunner, burst, WeaponData.WeaponType.CARBINE)
		game.squad_manager.join_squad(gunner, killer.squad)
		_spawn(ENEMY, lead_cell).set_current_hp(1)
		_spawn(ENEMY, second_cell))
	var struck: Array[AttackAction] = []
	game.order_executor.volley_struck.connect(func(attack: AttackAction) -> void: struck.append(attack))

	var ran: Dictionary = await _run(path, [
			{"verb": "attack", "from": killer_cell, "at": lead_cell},
			{"verb": "attack", "from": gunner_cell, "at": lead_cell}])

	var gunner: Unit = ran.game[gunner_cell]
	var volley: Array[AttackAction] = []
	for attack in (ran.plan as ResolvedPlan).attacks:
		if attack.actor == gunner:
			volley.append(attack)
	assert_int(volley.size()).override_failure_message("fixture: the burst reached %d victims" % volley.size()).is_equal(2)
	assert_object(volley[0].target).override_failure_message("fixture: the killed foe is not the lead").is_same(ran.game[lead_cell])
	assert_bool(volley[0].resolved.whiffed).override_failure_message("the dead lead did not whiff").is_true()
	assert_bool(volley[1].resolved.whiffed).override_failure_message("the living second victim whiffed").is_false()

	var impacts := struck.filter(func(attack: AttackAction) -> bool: return attack.actor == gunner).size()
	assert_int(impacts).override_failure_message("the gunner's volley published %d impacts, not one" % impacts).is_equal(1)
	for host: String in ["game", "play"]:
		var units: Dictionary = ran[host]
		var second: Unit = units[second_cell]
		assert_int(second.get_current_hp()).override_failure_message(
				"the %s host's volley never reached its living victim" % host).is_less(second.get_max_hp())
		var carbine := (units[gunner_cell] as Unit).get_equipped_weapon() as CarbineWeaponInstance
		assert_int(carbine.shots_remaining).override_failure_message(
				"the %s host's volley spent no round for its dead lead" % host).is_equal(CarbineWeaponInstance.MAGAZINE_SIZE - 1)
	_assert_hosts_agree(ran)


# --- WHEN a pass's tiles land (#1498 stage 2) ----------------------------------------------------
#
# A volley's tile changes land once its LAST member has played (ruling 3: one blast is one moment), in
# both hosts: the game's read at each blow's impact (volley_struck), the headless one by where its lines
# fall in the event log. The tiles are the attack's own smoke (AttackData.gases), so no reaction need fire,
# and where it lies is read off the resolve rather than named here.

const SMOKE := Gas.Kind.SMOKE


func _smoky(power: int) -> WeaponAttackData:
	var attack := _blow(power)
	attack.gases = {SMOKE: Gas.Level.THICK}
	return attack


static func _smoke_cells(gas: GasField) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in gas.cells():
		if Gas.level_in(gas.packed_at(cell), SMOKE) > 0:
			out.append(cell)
	return out


# Where the game's live field held smoke at each blow's impact, as the game plays the pass.
func _smoke_at_each_impact() -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	game.order_executor.volley_struck.connect(func(attack: AttackAction) -> void:
		seen.append({"actor": attack.actor, "smoke": _smoke_cells(game.gas_field)}))
	return seen


# Whether `cell` held smoke when `actor`'s first blow struck in the game; null if it never struck.
static func _smoke_when(seen: Array[Dictionary], actor: Unit, cell: Vector2i) -> Variant:
	for impact in seen:
		if impact.actor == actor:
			return (impact.smoke as Array).has(cell)
	return null


# Where `actor`'s blow laid its smoke, by the plan; (-1, -1) for nowhere.
static func _laid_by(plan: ResolvedPlan, actor: Unit) -> Vector2i:
	for effect in plan.cell_effects:
		var by := effect.cause as AttackAction
		if by != null and by.actor == actor and effect.gas_added.has(SMOKE):
			return effect.cell
	return Vector2i(-1, -1)


static func _line(events: Array, prefix: String) -> int:
	for i in events.size():
		if str(events[i]).begins_with(prefix):
			return i
	return -1


func _hit(ran: Dictionary, from: Vector2i, to: Vector2i) -> String:
	return "%s hits %s for " % [_sess.handle_for(ran.play[from]), _sess.handle_for(ran.play[to])]


func _assert_lines_found(events: Array, at: Dictionary) -> bool:
	for what: String in at:
		assert_int(int(at[what])).override_failure_message("fixture: no %s line in\n%s" % [what, "\n".join(events)]) \
			.is_not_equal(-1)
	return not at.values().has(-1)


# A two-victim volley's smoke lands after its SECOND victim's hit, and before the next attack.
func test_a_volley_lands_its_tiles_after_its_last_member() -> void:
	var gunner_cell := Vector2i(2, 2)
	var next_cell := Vector2i(2, 1)
	var lead_cell := Vector2i(3, 1)
	var second_cell := Vector2i(4, 1)
	var path := _author("volley_lands", func() -> void:
		var gunner := _spawn(PLAYER, gunner_cell)
		var burst := _smoky(2)
		# The aimed cell and the one east of it, as a true AoE: a placed shape emits west to east within
		# a row, so the foe on the aimed cell is the volley's lead.
		P.stamped(burst, 2, [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
		burst.swing = false
		_arm(gunner, burst)
		var next := _spawn(PLAYER, next_cell)
		_arm(next, _blow(2))
		game.squad_manager.join_squad(next, gunner.squad)
		_spawn(ENEMY, lead_cell, 200)
		_spawn(ENEMY, second_cell, 200))
	var seen := _smoke_at_each_impact()

	var ran: Dictionary = await _run(path, [
			{"verb": "attack", "from": gunner_cell, "at": lead_cell},
			{"verb": "attack", "from": next_cell, "at": lead_cell}])

	var laid := _laid_by(ran.plan, ran.game[gunner_cell])
	assert_that(laid).override_failure_message("fixture: the volley laid no smoke").is_not_equal(Vector2i(-1, -1))
	var events: Array = ran.events
	var at := {"second victim's hit": _line(events, _hit(ran, gunner_cell, second_cell)),
			"smoke": _line(events, "%s gains" % str(laid)),
			"next attack's hit": _line(events, _hit(ran, next_cell, lead_cell))}
	if _assert_lines_found(events, at):
		assert_int(at["smoke"]).override_failure_message(
				"the headless host landed the volley's smoke before its last member played:\n%s" % "\n".join(events)) \
			.is_greater(at["second victim's hit"])
		assert_int(at["smoke"]).override_failure_message(
				"the headless host landed the volley's smoke only after the next attack:\n%s" % "\n".join(events)) \
			.is_less(at["next attack's hit"])
	assert_that(_smoke_when(seen, ran.game[gunner_cell], laid)).override_failure_message(
			"the game's smoke was down before the volley that lays it struck").is_equal(false)
	assert_that(_smoke_when(seen, ran.game[next_cell], laid)).override_failure_message(
			"the volley's smoke was not down when the next attack struck in the game").is_equal(true)
	_assert_hosts_agree(ran)


# A counter's smoke lands after that counter -- not before the counters start, where the one batch was.
func test_a_counter_lands_its_tiles_after_it_plays() -> void:
	var hero_cell := Vector2i(1, 1)
	var foe_cell := Vector2i(2, 1)
	var path := _author("counter_lands", func() -> void:
		_arm(_spawn(PLAYER, hero_cell), _blow(2))
		_arm(_spawn(ENEMY, foe_cell, 200), _smoky(2)))
	var seen := _smoke_at_each_impact()

	var ran: Dictionary = await _run(path, [{"verb": "attack", "from": hero_cell, "at": foe_cell}])

	var foe: Unit = ran.game[foe_cell]
	var laid := _laid_by(ran.plan, foe)
	assert_that(laid).override_failure_message("fixture: the counter laid no smoke").is_not_equal(Vector2i(-1, -1))
	var events: Array = ran.events
	var at := {"counter's hit": _line(events, _hit(ran, foe_cell, hero_cell)),
			"smoke": _line(events, "%s gains" % str(laid))}
	if _assert_lines_found(events, at):
		assert_int(at["smoke"]).override_failure_message(
				"the headless host landed the counter's smoke before the counter:\n%s" % "\n".join(events)) \
			.is_greater(at["counter's hit"])
	assert_that(_smoke_when(seen, foe, laid)).override_failure_message(
			"the counter's smoke was down in the game before the counter struck").is_equal(false)
	assert_bool(_smoke_cells(game.gas_field).has(laid)).override_failure_message(
			"the counter's smoke never landed in the game").is_true()
	_assert_hosts_agree(ran)


# A walk-phase watch shot's smoke lands at its step, before the attack phase -- not after it.
func test_a_walk_shot_lands_its_tiles_at_its_step() -> void:
	var walker_cell := Vector2i(0, 1)
	var crossing := Vector2i(2, 1)
	var watcher_cell := Vector2i(2, 3)
	var foe_cell := Vector2i(4, 1)
	var path := _author("walk_lands", func() -> void:
		_arm(_spawn(PLAYER, walker_cell), _blow(2))
		var watcher := _spawn(ENEMY, watcher_cell)
		var puff := _smoky(2)
		puff.can_overwatch = true   # the capture saves a watch by its place among the watch attacks
		_arm(watcher, puff)
		var footprint: Array[Vector2i] = [crossing]
		watcher.arm_watch(watcher.movement.cell, crossing, footprint, watcher.overwatch_attacks()[0])
		assert_object(watcher.watch).override_failure_message("fixture: the watch did not arm").is_not_null()
		_spawn(ENEMY, foe_cell, 200))
	var seen := _smoke_at_each_impact()

	var ran: Dictionary = await _run(path, [
			{"verb": "move", "from": walker_cell, "to": Vector2i(3, 1)},
			{"verb": "attack", "from": walker_cell, "at": foe_cell}])

	var plan: ResolvedPlan = ran.plan
	assert_int(plan.mid_walk_shots().size()).override_failure_message("fixture: the watch never fired mid-walk").is_greater(0)
	var laid := _laid_by(plan, ran.game[watcher_cell])
	assert_that(laid).override_failure_message("fixture: the watch shot laid no smoke").is_not_equal(Vector2i(-1, -1))
	var events: Array = ran.events
	var at := {"watch shot's hit": _line(events, _hit(ran, watcher_cell, walker_cell)),
			"smoke": _line(events, "%s gains" % str(laid)),
			"attack's hit": _line(events, _hit(ran, walker_cell, foe_cell))}
	if _assert_lines_found(events, at):
		assert_int(at["smoke"]).override_failure_message(
				"the headless host landed the walk shot's smoke before the shot:\n%s" % "\n".join(events)) \
			.is_greater(at["watch shot's hit"])
		assert_int(at["smoke"]).override_failure_message(
				"the headless host landed the walk shot's smoke only after the attack phase:\n%s" % "\n".join(events)) \
			.is_less(at["attack's hit"])
	assert_that(_smoke_when(seen, ran.game[watcher_cell], laid)).override_failure_message(
			"the walk shot's smoke was down in the game before the shot struck").is_equal(false)
	assert_that(_smoke_when(seen, ran.game[walker_cell], laid)).override_failure_message(
			"the walk shot's smoke was not down when the walker's attack struck in the game").is_equal(true)
	_assert_hosts_agree(ran)


# --- A tile change counts at the hit that makes it (#1498 stage 3) -------------------------------
#
# Each case is a combination the pass used to resolve on the ground it started on: a later hit meets an
# earlier one's tile change (ruling 2), a melt sinks whoever stands on it right there (ruling 4), and
# water a walk shot melted catches the walker (ruling 5) -- in the plan, and in both hosts.

const POOL := Vector2i(4, 1)
const ICE_AT := Vector2i(4, 1)


func _map_blow(element: Elemental.Element) -> WeaponAttackData:
	var attack := _blow(1)
	attack.elemental_damage_type = element
	attack.targets = EquippableData.TargetMode.MAP
	return attack


# Deep water at `cell`, iced over -- frozen before anyone is spawned on it, since spawn refuses water.
func _ice(cell: Vector2i) -> void:
	game.grid.paint(cell, GRASS_SOURCE, DEEP_WATER)
	var freeze := ResolvedCellEffect.new()
	freeze.cell = cell
	freeze.states_added.assign([Terrain.TileState.FROZEN])
	game.terrain_states.apply(freeze)


# Two squadmates, each carrying one attack.
func _pair(first_at: Vector2i, first: WeaponAttackData, second_at: Vector2i, second: WeaponAttackData) -> void:
	var lead := _spawn(PLAYER, first_at)
	_arm(lead, first)
	var mate := _spawn(PLAYER, second_at)
	_arm(mate, second)
	game.squad_manager.join_squad(mate, lead.squad)


# What `actor`'s attack laid at `cell`, by the plan; null for nothing.
static func _laid_at(plan: ResolvedPlan, actor: Unit, cell: Vector2i) -> ResolvedCellEffect:
	for effect in plan.cell_effects:
		var by := effect.cause as AttackAction
		if by != null and by.actor == actor and effect.cell == cell:
			return effect
	return null


static func _attack_by(plan: ResolvedPlan, actor: Unit) -> AttackAction:
	for attack in plan.attacks:
		if attack.actor == actor:
			return attack
	return null


static func _sink_of(plan: ResolvedPlan, unit: Unit) -> SinkAction:
	for sink in plan.sinks:
		if sink.actor == unit:
			return sink
	return null


func test_ice_then_fire_melts_the_ice_rather_than_boiling_the_water() -> void:
	var path := _author("melt_not_boil", func() -> void:
		game.grid.paint(POOL, GRASS_SOURCE, DEEP_WATER)
		_pair(Vector2i(4, 0), _map_blow(Elemental.Element.ICE), Vector2i(4, 2), _map_blow(Elemental.Element.FIRE)))

	var ran: Dictionary = await _run(path, [{"verb": "attack", "from": Vector2i(4, 0), "at": POOL},
			{"verb": "attack", "from": Vector2i(4, 2), "at": POOL}])

	var fire := _laid_at(ran.plan, ran.game[Vector2i(4, 2)], POOL)
	assert_object(fire).override_failure_message("the fire left the frozen pool alone").is_not_null()
	if fire != null:
		assert_bool(fire.states_removed.has(Terrain.TileState.FROZEN)).override_failure_message(
				"the fire did not melt the ice the frost had just made").is_true()
		assert_bool(fire.gas_added.has(Gas.Kind.STEAM)).override_failure_message(
				"the fire boiled water the frost had already frozen").is_false()
	_assert_hosts_agree(ran)


func test_fire_then_water_douses_the_blaze() -> void:
	var grass := Vector2i(4, 1)
	var path := _author("douse", func() -> void:
		_pair(Vector2i(4, 0), _map_blow(Elemental.Element.FIRE), Vector2i(4, 2), _map_blow(Elemental.Element.WATER)))

	var ran: Dictionary = await _run(path, [{"verb": "attack", "from": Vector2i(4, 0), "at": grass},
			{"verb": "attack", "from": Vector2i(4, 2), "at": grass}])

	var lit := _laid_at(ran.plan, ran.game[Vector2i(4, 0)], grass)
	assert_bool(lit != null and lit.states_added.has(Terrain.TileState.BURNING)).override_failure_message(
			"fixture: the fire did not light the grass").is_true()
	var water := _laid_at(ran.plan, ran.game[Vector2i(4, 2)], grass)
	assert_bool(water != null and water.states_removed.has(Terrain.TileState.BURNING)).override_failure_message(
			"the water did not douse the blaze the fire had just lit").is_true()
	_assert_hosts_agree(ran)


# The attack-phase twin of the counter case above: the squadmate's shove lands its victim on the ice.
func test_a_shove_lands_on_ice_an_earlier_attack_froze() -> void:
	var path := _author("shove_onto_ice", func() -> void:
		game.grid.paint(LAKE, GRASS_SOURCE, DEEP_WATER)
		var shove := _blow(2)
		shove.knockback = 1
		_pair(FROSTER_AT, _map_blow(Elemental.Element.ICE), FOE_AT, shove)
		_spawn(ENEMY, MATE_AT, 200))

	var ran: Dictionary = await _run(path, [{"verb": "attack", "from": FROSTER_AT, "at": LAKE},
			{"verb": "attack", "from": FOE_AT, "at": MATE_AT}])

	var blow := _attack_by(ran.plan, ran.game[FOE_AT])
	assert_object(blow).override_failure_message("fixture: the shove expanded to nothing").is_not_null()
	if blow != null:
		assert_that(blow.resolved.knockback_to).override_failure_message(
				"fixture: the shove did not throw its victim onto the lake").is_equal(LAKE)
		assert_int(blow.resolved.drown_damage).override_failure_message(
				"the shove drowned its victim in a lake the pass had already frozen").is_equal(0)
	assert_that(PlanResolver.projected_lifecycle(ran.game[MATE_AT], (ran.plan as ResolvedPlan).hypo)) \
		.is_equal(Unit.LifecycleState.ACTIVE)
	_assert_hosts_agree(ran)


# A carving draws on fire beside its caster (#694), so fire an earlier attack lit there empowers it.
# Against the same cast with nothing lit first, on the same board.
func test_a_carving_draws_on_fire_an_earlier_attack_lit() -> void:
	var caster_at := Vector2i(1, 1)
	var foe_at := Vector2i(3, 1)
	var lighter_at := Vector2i(0, 0)
	var kindling := Vector2i(1, 0)   # beside the caster, within Materia.REACH
	var path := _author("lit_carving", func() -> void:
		var caster := _alchemist(caster_at)
		var lighter := _spawn(PLAYER, lighter_at)
		_arm(lighter, _map_blow(Elemental.Element.FIRE))
		game.squad_manager.join_squad(lighter, caster.squad)
		_spawn(ENEMY, foe_at, 200))

	var alone: Dictionary = await _run(path, [{"verb": "attack", "from": caster_at, "at": foe_at}])
	var unlit := _attack_by(alone.plan, alone.game[caster_at])
	var ran: Dictionary = await _run(path, [{"verb": "attack", "from": lighter_at, "at": kindling},
			{"verb": "attack", "from": caster_at, "at": foe_at}])
	var cast := _attack_by(ran.plan, ran.game[caster_at])

	assert_bool(unlit != null and cast != null).override_failure_message("fixture: a cast expanded to nothing").is_true()
	if unlit == null or cast == null:
		return
	assert_int(cast.resolved.damage).override_failure_message(
			"the cast did not draw on the fire lit beside its caster earlier in the pass").is_greater(unlit.resolved.damage)
	_assert_hosts_agree(ran)


# Ruling 4: the melt sinks its stander right after the blast that melts it, before the NEXT attack -- in
# the game read at that attack's impact, headlessly by where the lines fall. The next attack strikes
# somebody else, so nobody finishes the body off.
func test_a_melt_sinks_its_stander_before_the_next_attack() -> void:
	var hero_at := Vector2i(3, 1)
	var mate_at := Vector2i(4, 0)
	var other_at := Vector2i(5, 0)
	var path := _author("sink_before_next", func() -> void:
		_ice(ICE_AT)
		var fire := _blow(2)
		fire.elemental_damage_type = Elemental.Element.FIRE
		fire.targets = EquippableData.TargetMode.BOTH
		_pair(hero_at, fire, mate_at, _blow(2))
		_spawn(ENEMY, ICE_AT, 30)
		_spawn(ENEMY, other_at, 200))
	var on_the_ice: Array[Dictionary] = []   # who stood on the ice, and how, at each impact
	game.order_executor.volley_struck.connect(func(attack: AttackAction) -> void:
		for unit: Unit in game._all_units():
			if unit.movement.cell == ICE_AT:
				on_the_ice.append({"actor": attack.actor, "lifecycle": unit.lifecycle_state}))

	var ran: Dictionary = await _run(path, [{"verb": "attack", "from": hero_at, "at": ICE_AT},
			{"verb": "attack", "from": mate_at, "at": other_at}])

	var plan: ResolvedPlan = ran.plan
	var sink := _sink_of(plan, ran.game[ICE_AT])
	assert_object(sink).override_failure_message("fixture: the melt sank nobody").is_not_null()
	if sink == null:
		return
	assert_object(sink.cause).override_failure_message("the sinking is not caused by the blast that melted the ice") \
		.is_same(_attack_by(plan, ran.game[hero_at]))
	var at_the_mate: Variant = null
	for impact in on_the_ice:
		if impact.actor == ran.game[mate_at]:
			at_the_mate = impact.lifecycle
	assert_that(at_the_mate).override_failure_message("fixture: the mate's blow never struck in the game").is_not_null()
	assert_that(at_the_mate).override_failure_message(
			"the game's next attack struck while the stander still stood on the ice it had lost").is_equal(
			Unit.LifecycleState.DOWNED)
	var events: Array = ran.events
	var at := {"blast": _line(events, _hit(ran, hero_at, ICE_AT)),
			"sinking": _line(events, "%s goes under" % _sess.handle_for(ran.play[ICE_AT])),
			"next attack": _line(events, _hit(ran, mate_at, other_at))}
	if _assert_lines_found(events, at):
		assert_int(at["sinking"]).override_failure_message(
				"the headless host sank the stander before the blast:\n%s" % "\n".join(events)).is_greater(at["blast"])
		assert_int(at["sinking"]).override_failure_message(
				"the headless host sank the stander only after the next attack:\n%s" % "\n".join(events)).is_less(at["next attack"])
	_assert_hosts_agree(ran)


# ...and a refreeze later in the same pass closes the ice over the body that went under (its look is #1506).
func test_a_refreeze_closes_over_a_sunk_body() -> void:
	var hero_at := Vector2i(3, 1)
	var froster_at := Vector2i(4, 0)
	var path := _author("refreeze", func() -> void:
		_ice(ICE_AT)
		var fire := _blow(2)
		fire.elemental_damage_type = Elemental.Element.FIRE
		fire.targets = EquippableData.TargetMode.BOTH
		_pair(hero_at, fire, froster_at, _map_blow(Elemental.Element.ICE))
		_spawn(ENEMY, ICE_AT, 30))

	var ran: Dictionary = await _run(path, [{"verb": "attack", "from": hero_at, "at": ICE_AT},
			{"verb": "attack", "from": froster_at, "at": ICE_AT}])

	assert_object(_sink_of(ran.plan, ran.game[ICE_AT])).override_failure_message(
			"the melt sank nobody because a later attack refroze it").is_not_null()
	assert_bool(game.terrain_states.has_state(ICE_AT, Terrain.TileState.FROZEN)).override_failure_message(
			"the refreeze did not close over the water in the game").is_true()
	assert_bool((ran.game[ICE_AT] as Unit).is_downed()).override_failure_message(
			"the body under the ice is not down in the game").is_true()
	_assert_hosts_agree(ran)


# Ruling 5: a walk shot melts ice ahead of the walker, and the water catches them -- they halt there
# and go under, in the plan and in both hosts.
func test_water_a_walk_shot_melted_catches_the_walker() -> void:
	var walker_at := Vector2i(0, 1)
	var crossing := Vector2i(2, 1)
	var thin_ice := Vector2i(3, 1)
	var path := _author("walker_caught", func() -> void:
		_ice(thin_ice)
		_spawn(PLAYER, walker_at)
		var watcher := _spawn(ENEMY, Vector2i(2, 3))
		var flare := _blow(1)
		flare.elemental_damage_type = Elemental.Element.FIRE
		flare.targets = EquippableData.TargetMode.BOTH
		P.stamped(flare, 2, [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
		flare.swing = false
		flare.can_overwatch = true   # the capture saves a watch by its place among the watch attacks
		_arm(watcher, flare)
		# Two paths, so the ice is struck even though the walker on the first one stops that path (#1057).
		var footprint: Array[Vector2i] = [crossing, thin_ice]
		var lengths: Array[int] = [1, 1]
		watcher.arm_watch(watcher.movement.cell, crossing, footprint, watcher.overwatch_attacks()[0], false, false,
				lengths)
		assert_object(watcher.watch).override_failure_message("fixture: the watch did not arm").is_not_null())

	var ran: Dictionary = await _run(path, [{"verb": "move", "from": walker_at, "to": Vector2i(4, 1)}])

	var plan: ResolvedPlan = ran.plan
	var melted := false
	for effect in plan.cell_effects:
		melted = melted or (effect.cell == thin_ice and effect.states_removed.has(Terrain.TileState.FROZEN))
	assert_bool(melted).override_failure_message("fixture: the walk shot never melted the ice ahead").is_true()
	var sink := _sink_of(plan, ran.game[walker_at])
	assert_object(sink).override_failure_message("the walker walked on over water a walk shot had melted").is_not_null()
	if sink != null:
		assert_bool(sink.cause is MoveAction).override_failure_message("the walker's sinking is not its walk's").is_true()
		assert_that(sink.cell).is_equal(thin_ice)
	for host: String in ["game", "play"]:
		var caught: Unit = ran[host][walker_at]
		assert_that(caught.movement.cell).override_failure_message(
				"the %s host's walker did not stop where the water took it" % host).is_equal(thin_ice)
		assert_bool(caught.is_downed()).override_failure_message(
				"the %s host's walker is standing in the water" % host).is_true()
	_assert_hosts_agree(ran)
