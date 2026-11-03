# #1563 (PV-6): a heal on a body is a save only when nobody WILL rescue it (ruling 16, read as "will"
# with the dev, 2026-11-03). A squadmate beside the body who has an attack to make makes it (#711:
# ATTACK sits above RESCUE in every list that rescues), so it is no rescuer, and neither is one whose
# main action is already queued. AITactics._stakes_for counted both, and the healer left the body to
# bleed out.
#
# Every case drives the real AIController.take_faction_turn and reads the body after it. The two
# halves are ORDER-dependent -- who wins the joint pass's first round -- so each has its own board:
#   - the mate's removal wins round 1, and round 2 must not count it (its main is spent);
#   - the healer's own swing wins round 1, so the mate must already read as busy then.
# Fixture shape is test_ai_candidate_aims._body_board(true), in the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true, move_cost=1 in TestTiles.tres
const FOE_HP := 30

var _main: Node
var game: Node2D


func before_test() -> void:
	AIProfiles.use_fixtures({"": AIProfile.new()})   # #1230: this suite owns its AI profile
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	AIProfiles.clear_fixtures()
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i, overrides := {}, power := 3) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data(overrides, faction), cell)
	assert_object(unit).is_not_null()
	unit.equipped_weapon = H.make_weapon(power)
	return unit


func _heal(power: int, reach := 2) -> WeaponAttackData:
	var heal := WeaponAttackData.new()
	heal.power = power
	heal.heals = true
	heal.hits_allies = true   # as every authored heal is
	P.point(heal, reach)
	return heal


# A Hold squad: a healer at (2,2) with a player beside it to swing at, a mate at (1,4) beside the body
# at (2,4), in the heal's reach. `mate_foe_hp` > 0 puts a player beside the mate at (0,4) with that HP.
func _body_board(healer_power: int, mate_power: int, mate_foe_hp: int) -> Dictionary:
	for x in range(8):
		for y in range(8):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	var healer := _spawn(Team.Faction.ENEMY, Vector2i(2, 2), {}, healer_power)
	var extras: Array[WeaponAttackData] = [_heal(8)]
	(healer.get_equipped_weapon() as WeaponInstance).template.extra_attacks = extras
	var healer_foe := _spawn(Team.Faction.PLAYER, Vector2i(3, 2), {Stats.Stat.MHP: FOE_HP})
	healer_foe.squad.archetype = AIArchetype.Type.HOLD
	var body := _spawn(Team.Faction.ENEMY, Vector2i(2, 4))
	var mate := _spawn(Team.Faction.ENEMY, Vector2i(1, 4), {}, mate_power)
	var mate_foe: Unit = null
	if mate_foe_hp > 0:
		mate_foe = _spawn(Team.Faction.PLAYER, Vector2i(0, 4), {Stats.Stat.MHP: FOE_HP})
		mate_foe.squad.archetype = AIArchetype.Type.HOLD
		mate_foe.set_current_hp(mate_foe_hp)
	await await_idle_frame()
	game.squad_manager.join_squad(mate, healer.squad)
	healer.squad.archetype = AIArchetype.Type.HOLD   # its list carries RESCUE, and Hold never moves
	body.force_down()
	game.ai_controller.set_faction_ai_enabled(Team.Faction.ENEMY, true)
	game.turn_manager.set_active_faction(Team.Faction.ENEMY)
	await await_idle_frame()
	return {"body": body, "healer_foe": healer_foe, "mate_foe": mate_foe}


func _assert_body_saved(body: Unit) -> void:
	assert_bool(is_instance_valid(body)).override_failure_message("fixture: the body died outright").is_true()
	if not is_instance_valid(body):
		return
	assert_bool(body.is_active() or body.downed_turns_remaining < 0).override_failure_message(
			"the body was left to bleed out: its clock still runs (%d) and nobody rescued it, because the "
			% body.downed_turns_remaining + "squadmate counted as its rescuer attacked instead").is_true()


# The mate's foe is one hit from down, so the mate's removal outranks the healer's save and wins round
# 1. In round 2 the mate's main action is spent: the body is the healer's to save.
func test_a_body_whose_rescuer_already_attacked_is_healed() -> void:
	var board: Dictionary = await _body_board(1, 3, 1)
	var mate_foe: Unit = board.mate_foe

	await game.ai_controller.take_faction_turn(Team.Faction.ENEMY)

	assert_bool(is_instance_valid(mate_foe) and mate_foe.is_active()).override_failure_message(
			"fixture: the mate never downed its foe, so it never attacked").is_false()
	_assert_body_saved(board.body)


# The healer's own swing outranks the mate's, so under "could rescue" the healer chose first and swung
# while the mate still looked free -- then the mate attacked too. The mate must read as busy at once.
func test_a_body_whose_rescuer_is_about_to_attack_is_healed() -> void:
	var board: Dictionary = await _body_board(6, 1, FOE_HP)
	var mate_foe: Unit = board.mate_foe

	await game.ai_controller.take_faction_turn(Team.Faction.ENEMY)

	assert_int(mate_foe.get_current_hp()).override_failure_message(
			"fixture: the mate never attacked its foe").is_less(FOE_HP)
	_assert_body_saved(board.body)


# The other side of the rule: a mate with nothing to hit WILL rescue, so the healer swings at its own
# foe and leaves the body to it. A rule that released too much would spend the healer on the body.
func test_a_free_rescuer_still_carries_the_body() -> void:
	var board: Dictionary = await _body_board(1, 3, 0)
	var body: Unit = board.body
	var healer_foe: Unit = board.healer_foe

	await game.ai_controller.take_faction_turn(Team.Faction.ENEMY)

	assert_bool(is_instance_valid(body) and body.is_active()).override_failure_message(
			"the free squadmate did not rescue the body").is_true()
	assert_int(healer_foe.get_current_hp()).override_failure_message(
			"the healer spent its turn on a body its squadmate rescues instead of swinging at its foe") \
			.is_less(FOE_HP)
