# THE BLOW-LANDED WIRE (#887), on a real Main.tscn board through the real OrderExecutor.
#
# The first per-attack event the game publishes. Everything a presentation layer knew about a hit
# until now came from UnitMirror watching HP fall, which knows that a number moved and nothing about
# what moved it -- so an effect that draws the ATTACK needed a channel of its own, and this file is
# the only place that channel can be seen end to end: AttackAction emits it from inside execute(),
# after the lunge, and OrderExecutor re-publishes it.
#
# WHAT A GREEN SUITE WOULD MISS WITHOUT THIS. A signal with no listener is legal GDScript and a
# listener nobody connects is a silent no-op; both ends of this wire can be perfectly written while
# nothing joins them (#103's thirteen-month gap). Neither the emit nor the connect is observable from
# any suite that does not drive a real pass.
#
# The two facts under test are the CHANNEL and its GATE -- one blast is one moment, however many it
# hits. What a bolt looks like is tests/presentation/test_arc_lightning.gd's, and none of it is here.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D
var _struck: Array[AttackAction] = []


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		for y in range(3):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	_struck = []
	var executor: OrderExecutor = game.order_executor
	executor.volley_struck.connect(_on_struck)
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _on_struck(attack: AttackAction) -> void:
	_struck.append(attack)


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


# A wide stamp so one aim covers three cells at range, and enough power to matter but not enough to
# kill -- a body removed mid-volley would change the shape of what is being counted.
func _blaster(map_too := false) -> WeaponData:
	var swing := WeaponAttackData.new()
	swing.display_name = "Arc Rod"
	swing.elemental_damage_type = Elemental.Element.SHOCK
	swing.power = 4
	swing.hits_allies = true
	# BOTH is what the shock runes carry (Zap's own) and what makes an aim at open ground a legal
	# order rather than a whiff -- an attack that touches the MAP has something to do there with
	# nobody standing on it. Only the cell-attack case needs it, and it takes it deliberately: the
	# volley case is about the gate on the number of blows, not about what an aim may be pointed at.
	if map_too:
		swing.targets = EquippableData.TargetMode.BOTH
	var offsets: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0)]
	P.stamped(swing, 3, offsets)

	var template := WeaponData.new()
	# REQUIRED, not decoration: WeaponInstance.make has no subclass for the default type, so it
	# push_errors and hands back null -- and a push_error reds no case, so the unit comes up with no
	# weapon, `declare` stamps a null attack, and every rule downstream reads it as bare fists.
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = swing
	return template


func _arm(hero: Unit, map_too := false) -> void:
	hero.equipped_weapon = WeaponInstance.make(_blaster(map_too))


func _fire_at(hero: Unit, cell: Vector2i) -> void:
	var action := AttackAction.declare(hero, hero.movement.cell, cell)
	assert_object(action.fired_attack).override_failure_message(
		"fixture: nothing was stamped to fire, so this is a bare-fisted swing").is_not_null()
	assert_bool(game.squad_manager.queue_action(hero.squad, action)).override_failure_message(
		"fixture: the attack never queued (%s), so nothing was executed"
		% ", ".join(action.validation_errors)).is_true()
	await game.order_executor.execute_orders(hero.squad.get_leader())


# THREE VICTIMS, ONE MOMENT. The count is the whole case: an emit that is not gated on the lead
# would fire once per body and every effect downstream would play three times over.
func test_a_three_victim_volley_publishes_one_blow() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 2))
	_arm(hero)
	var left := _spawn(Team.Faction.ENEMY, Vector2i(1, 0))
	var middle := _spawn(Team.Faction.ENEMY, Vector2i(2, 0))
	var right := _spawn(Team.Faction.ENEMY, Vector2i(3, 0))
	for body in [left, middle, right]:
		body.unit_instance.stats[Stats.Stat.MHP] = 200
		body.set_current_hp(200)
	await await_idle_frame()

	await _fire_at(hero, Vector2i(2, 0))

	assert_int(_struck.size()).override_failure_message(
		"a three-victim volley published %d blows -- one blast is one moment" % _struck.size()
		).is_equal(1)
	assert_bool(_struck[0].is_secondary_hit).override_failure_message(
		"the blow published was a secondary volley member, not the lead").is_false()
	assert_object(_struck[0].actor).is_same(hero)


# The branch with no victim at all (#47), which is the reason the emit sits ABOVE the target block
# rather than inside it. An attack that touches the MAP may legally be aimed at open ground, and
# every shock rune is one -- so a shock into an empty river hits nobody, lights the whole river, and
# would publish nothing from inside a clause guarded on having somebody to hit.
func test_an_attack_on_empty_ground_publishes_its_blow_too() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 2))
	_arm(hero, true)
	await await_idle_frame()

	await _fire_at(hero, Vector2i(2, 0))

	assert_int(_struck.size()).override_failure_message(
		"a cell attack published %d blows" % _struck.size()).is_equal(1)
	assert_object(_struck[0].target).override_failure_message(
		"fixture: something was standing there, so this is not the cell-attack branch").is_null()


# A pass with no attack in it publishes nothing -- the wire is an ATTACK's, and a walk is not one.
func test_a_walk_publishes_no_blow() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 2))
	_arm(hero)
	await await_idle_frame()

	var move := MoveAction.new()
	move.init(hero, [Vector2i(1, 2)], null)
	assert_bool(game.squad_manager.queue_action(hero.squad, move)).override_failure_message(
		"fixture: the move never queued").is_true()
	await game.order_executor.execute_orders(hero.squad.get_leader())

	assert_array(_struck).is_empty()
