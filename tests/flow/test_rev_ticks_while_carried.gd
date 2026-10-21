# Rev counts down on every CARRIED weapon, not only the one in hand (#1357; dev, 2026-10-21: "Tick
# every carried weapon unless otherwise specified"). The turn-start tick used to read equipped_weapon
# alone, so a sword revved and then swapped for a carbine kept its timer frozen until it came back,
# still piercing DEF however many turns later. The rule suites call tick_rev directly and cannot see
# WHICH weapons the boundary reaches, so both cases here drive a real hand-off: one per host, since
# the Play API's end_turn and the game's TurnManager hand-off each land in TurnBoundary.turn_start_ticks.
#
# The swap goes through GearVerbs, the dock's own door (the Play API's gear verb in the headless case).
# What it cannot see: the turn-count the gauge PRINTS for a sword out of hand -- the ring lists only the
# equipped weapon's rows, so nothing is drawn for it until it is equipped again.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _main: Node


func after_test() -> void:
	if _main != null:
		get_tree().root.remove_child(_main)
		_main.free()
		_main = null


func _data(name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), name, fac)


static func _weapon(family: WeaponData.WeaponType) -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = family
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 4
	return WeaponInstance.make(template)


# A chainsword in hand and a carbine in the bag; returns the sword. The sword goes in FIRST so
# add_item's auto-equip puts it in hand.
func _kit(unit: Unit) -> ChainswordWeaponInstance:
	var sword := _weapon(WeaponData.WeaponType.CHAINSWORD) as ChainswordWeaponInstance
	assert_bool(unit.add_item(sword)).override_failure_message("precondition: no room for the sword").is_true()
	assert_bool(unit.add_item(_weapon(WeaponData.WeaponType.CARBINE))) \
		.override_failure_message("precondition: no room for the carbine").is_true()
	assert_object(unit.get_equipped_weapon()).override_failure_message(
		"precondition: the sword is not the weapon in hand").is_same(sword)
	return sword


func _carbine_slot(unit: Unit) -> int:
	for i in unit.inventory.size():
		if unit.inventory[i] is CarbineWeaponInstance:
			return i
	return -1


# --- the Play API host ---------------------------------------------------------------------------

func test_a_sword_swapped_out_still_counts_down_headless() -> void:
	var b: Dictionary = BoardBuilder.build(self, "RevCarriedRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 10, 10))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(7, 7))
	var sword := _kit(hero)
	var sess = PlaySession.new(b)
	var h: String = sess.handle_for(hero)

	var revved: Dictionary = sess.rev(h)
	assert_bool(revved.ok).override_failure_message("precondition: the rev did not queue: %s" % str(revved.get("error", ""))).is_true()
	sess.execute()
	assert_bool(sword.is_revved()).override_failure_message("precondition: the executed rev did not rev the sword").is_true()
	var swapped: Dictionary = sess.gear(h, "equip", _carbine_slot(hero))
	assert_bool(swapped.ok).override_failure_message("precondition: the swap was refused: %s" % str(swapped.get("error", ""))).is_true()
	assert_bool(hero.get_equipped_weapon() is CarbineWeaponInstance).override_failure_message(
		"precondition: the carbine is not in hand after the swap").is_true()

	for turn in ChainswordWeaponInstance.REV_DURATION_TURNS:
		var before := sword.revved_turns_remaining
		assert_bool((sess.end_turn() as Dictionary).ok).is_true()   # PLAYER -> ENEMY
		assert_bool((sess.end_turn() as Dictionary).ok).is_true()   # ENEMY -> PLAYER: the carrier's turn start
		assert_int(sword.revved_turns_remaining).override_failure_message(
			"the hero's turn start skipped the sword in the bag (%d left, was %d)" % [sword.revved_turns_remaining, before]) \
			.is_equal(before - 1)

	assert_bool((sess.gear(h, "equip", hero.inventory.find(sword)) as Dictionary).ok).is_true()
	assert_bool(sword.is_revved()).override_failure_message(
		"the sword came back still revved after %d of its carrier's turns" % ChainswordWeaponInstance.REV_DURATION_TURNS).is_false()
	assert_bool(sword.ignores_def()).is_false()


# --- the game host -------------------------------------------------------------------------------

func test_a_sword_swapped_out_still_counts_down_in_the_game() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	var game: Node2D = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		for y in range(3):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()
	var hero: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), Vector2i(0, 0))
	var foe: Unit = game.spawn_unit(H.make_unit_data({}, ENEMY), Vector2i(7, 2))
	assert_object(hero).is_not_null()
	assert_object(foe).is_not_null()
	await await_idle_frame()
	var sword := _kit(hero)
	hero.rev_weapon()
	assert_bool(sword.is_revved()).override_failure_message("precondition: the sword did not rev").is_true()
	assert_str(GearVerbs.perform(hero, GearVerbs.Verb.EQUIP, _carbine_slot(hero))).is_empty()

	for turn in ChainswordWeaponInstance.REV_DURATION_TURNS:
		var before := sword.revved_turns_remaining
		for hand_off in 2:   # PLAYER -> ENEMY -> PLAYER, through the real TurnManager hand-off
			var present: Array[Team.Faction] = (game._board() as BoardContext).present_factions()
			game.turn_manager.end_turn(present)
			await await_idle_frame()
		assert_int(game.turn_manager.active_faction()).override_failure_message(
			"precondition: two hand-offs did not come back to the player").is_equal(PLAYER)
		assert_int(sword.revved_turns_remaining).override_failure_message(
			"the hero's turn start skipped the sword in the bag (%d left, was %d)" % [sword.revved_turns_remaining, before]) \
			.is_equal(before - 1)

	assert_bool(sword.is_revved()).override_failure_message(
		"the sword is still revved after %d of its carrier's turns" % ChainswordWeaponInstance.REV_DURATION_TURNS).is_false()
