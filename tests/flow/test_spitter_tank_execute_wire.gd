# The GAME's half of the tank spend (#97), on a real Main.tscn board through the real
# OrderExecutor.
#
# WHY IT IS ITS OWN FILE, and this is the whole point of it. play_session._apply_attack is a
# declared HAND-COPIED TWIN of AttackAction.execute, and the play path never calls execute() at all
# -- measured, by mutation: deleting execute()'s tank spend leaves tests/play AND tests/weapons
# entirely green, 326 of 326. So the twin's suite (tests/play/test_spitter_tank_spend.gd) cannot
# cover this line however carefully it is written, and one mutant cannot cover both twins.
#
# That is #697's finding pointed the other way: there, the twin was MISSING the spend and the play
# case caught it. Here, the game is the side nothing else watches.
#
# Everything about the tank's RULES lives in tests/weapons/test_spitter_tank.gd. This file asserts
# one thing: that firing through the game's own executor spends what the resolver stamped.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const CORROSION := Elemental.Element.CORROSION

var _main: Node
var game: Node2D


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
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


func _spitter_template() -> WeaponData:
	var charged := WeaponAttackData.new()
	charged.display_name = "Pressurised Spray"
	charged.elemental_damage_type = CORROSION
	charged.power = 20
	P.point(charged, 2)

	var spray := WeaponAttackData.new()
	spray.display_name = "Spray"
	spray.elemental_damage_type = CORROSION
	spray.power = 4
	P.point(spray, 2)
	spray.empowered_form = charged

	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHEMICAL_SPITTER
	t.main_attack = spray
	return t


func test_firing_through_the_game_executor_spends_a_tank_charge() -> void:
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	var foe := _spawn(Team.Faction.ENEMY, Vector2i(2, 0))
	foe.unit_instance.stats[Stats.Stat.MHP] = 200
	foe.set_current_hp(200)
	hero.equipped_weapon = WeaponInstance.make(_spitter_template())
	await await_idle_frame()

	var tank := hero.get_equipped_weapon() as ChemicalSpitterWeaponInstance
	tank.charges = ChemicalSpitterWeaponInstance.TANK_SIZE
	var before := tank.charges

	# declare() is the one factory that stamps fired_attack (#78) -- the same call game.gd's click
	# handler makes, so the substitution is exercised rather than hand-assigned.
	var action := AttackAction.declare(hero, hero.movement.cell, foe.movement.cell)
	assert_bool(game.squad_manager.queue_action(hero.squad, action)).override_failure_message(
		"fixture: the attack never queued, so nothing was executed").is_true()
	assert_object(action.fired_attack).override_failure_message(
		"fixture: a full tank did not reach the declared stamp, so this case is about the wrong shot"
		).is_same(tank.template.main_attack.empowered_form)

	await game.order_executor.execute_orders(hero.squad.get_leader())

	assert_int(tank.charges).override_failure_message(
		"the game's executor fired the charged form and spent nothing -- AttackAction.execute is the"
		+ " only place this can happen, and the headless twin's suite cannot see it").is_equal(
		before - 1)
