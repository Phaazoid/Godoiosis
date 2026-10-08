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
	await game.order_executor.execute_orders(actor.squad.get_leader())
	var played: Dictionary = _sess.execute()
	assert_bool(played.get("ok", false)).override_failure_message(
			"the headless pass did not execute: %s" % str(played.get("error", ""))).is_true()
	return {"game": game_units, "play": play_units, "plan": plan}


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


# A cast that draws on a vial's charge burns it (#697), in both hosts.
func test_a_vial_burn() -> void:
	var fire := Elemental.Element.FIRE
	var path := _author("vial", func() -> void:
		var alchemist := _spawn(PLAYER, Vector2i(1, 1))
		alchemist.unit_instance.aura = {fire: 4}
		var affinity: Array[Elemental.Element] = [fire]
		alchemist.unit_instance.affinity = affinity
		var fireball := TransmutationData.new()
		fireball.display_name = "Fireball"
		fireball.power = 4
		fireball.sigils.assign([fire])
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
		_spawn(ENEMY, Vector2i(3, 1), 200))
	# Popped through the inventory's own door, on each host's copy -- a live attunement is not saved.
	var attune := func(units: Dictionary) -> void:
		var alchemist: Unit = units[Vector2i(1, 1)]
		var at := -1
		for i in alchemist.inventory.size():
			if alchemist.inventory[i] is VialData:
				at = i
		assert_str(alchemist.use_vial(at)).override_failure_message("fixture: the vial would not pop").is_equal("")

	var ran: Dictionary = await _run(path, [{"verb": "attack", "from": Vector2i(1, 1), "at": Vector2i(3, 1)}], attune)

	var plan: ResolvedPlan = ran.plan
	var burned := false
	for attack in plan.attacks:
		burned = burned or (attack.resolved != null and attack.resolved.burned_vial != null)
	assert_bool(burned).override_failure_message("fixture: the cast drew on no charge").is_true()
	_assert_hosts_agree(ran)
