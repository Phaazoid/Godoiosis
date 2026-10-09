# F / Shift+F WHILE AIMING cycle every attack the unit could aim, across every weapon it carries
# (#929), on the real game scene.
#
# The key is pressed the way project.godot binds it -- an InputEventKey on its physical keycode into
# game._input -- so the fork between the two cycles is asserted at the key, not at a function. The aim
# is opened through the ring's own pick (MainActionMenu._pick_attack / _pick_watch), and the commit is
# a real click on the board.
#
# The claim that carries the ticket is that a PREVIEW WRITES NOTHING: cycling onto another weapon's
# attack never equips it, and only the click does -- recorded once, as the dock's own gear act.
#
# Fixture is tests/ui/test_cycle_squad_member.gd's.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D
var _acts: Array = []


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	await await_idle_frame()
	game.mission_controller._close_mission_select()
	game.scenario_manager.clear_board()
	game.scenario_director.disarm()
	game.turn_manager.set_active_faction(Team.Faction.PLAYER)
	game.game_state = game.GameState.IDLE
	for x in range(10):
		for y in range(4):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	_acts = []
	game.loadout_acted.connect(func(unit: Unit, verb: String, index: int) -> void:
		_acts.append([unit, verb, index]))
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


# --- fixture -------------------------------------------------------------------------------------

func _spawn(cell: Vector2i, faction := Team.Faction.PLAYER) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


func _attack(attack_name: String, power := 3) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.display_name = attack_name
	attack.power = power
	return attack


# A pattern-less weapon (adjacency reach) whose main is the first attack named and whose stock
# extras are the rest.
func _weapon(weapon_name: String, attacks: Array[WeaponAttackData],
		family := WeaponData.WeaponType.CHAINSWORD) -> WeaponInstance:
	var template := WeaponData.new()
	template.display_name = weapon_name
	template.weapon_type = family
	template.main_attack = attacks[0]
	for i in range(1, attacks.size()):
		template.extra_attacks.append(attacks[i])
	return WeaponInstance.make(template)


# Carried in order, the first in hand.
func _arm(unit: Unit, carried: Array[EquippableData]) -> void:
	for item: EquippableData in carried:
		assert_bool(unit.add_item(item)).override_failure_message("fixture: the unit could not carry it").is_true()
	assert_bool(unit.set_equipped_weapon(carried[0])).override_failure_message("fixture: could not equip").is_true()


func _aim(unit: Unit, attack: AttackData) -> void:
	game.select_unit(unit, unit.movement.cell)
	game.main_action_menu._pick_attack(unit, attack)
	assert_int(game.game_state).override_failure_message("fixture: the pick opened no aim") \
		.is_equal(game.GameState.ATTACK_TARGETING)


func _press_f(shift := false) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.shift_pressed = shift
	key.pressed = true
	game._input(key)


func _strip_text() -> String:
	var strip: AimStrip = game.aim_strip
	return strip.shown_text() if strip.visible else ""


# ------------------------------------------------------------------------------
#  The cycle
# ------------------------------------------------------------------------------

func test_f_while_aiming_steps_to_the_next_attack_and_cycles_no_squadmate() -> void:
	var leader := _spawn(Vector2i(1, 1))
	var mate := _spawn(Vector2i(2, 1))
	game.squad_manager.join_squad(mate, leader.squad)
	var slash := _attack("Slash")
	var thrust := _attack("Thrust")
	var weapons: Array[EquippableData] = [_weapon("Sword", [slash, thrust])]
	_arm(leader, weapons)
	_aim(leader, slash)

	_press_f()

	assert_object(leader.active_attack).is_same(thrust)
	assert_object(game.selected_unit).override_failure_message(
			"F moved the selection to a squadmate while an aim was open").is_same(leader)
	assert_int(game.game_state).is_equal(game.GameState.ATTACK_TARGETING)
	assert_object(game.aim_source).is_null()


func test_f_walks_onto_a_carried_weapon_without_equipping_it() -> void:
	var unit := _spawn(Vector2i(1, 1))
	var slash := _attack("Slash")
	var smash := _attack("Smash")
	var sword := _weapon("Sword", [slash])
	var mace := _weapon("Mace", [smash])
	var weapons: Array[EquippableData] = [sword, mace]
	_arm(unit, weapons)
	_aim(unit, slash)

	_press_f()

	assert_object(unit.active_attack).is_same(smash)
	assert_object(game.aim_source).is_same(mace)
	assert_object(unit.get_equipped_weapon()).override_failure_message(
			"cycling onto another weapon's attack equipped it -- a preview must write nothing").is_same(sword)
	var text := _strip_text()
	assert_str(text).contains("Smash")
	assert_str(text).contains("Mace")
	assert_str(text).contains(AimStrip.SWAP_TEXT)
	assert_int(_acts.size()).override_failure_message("a cycle step was recorded as a gear act").is_equal(0)


func test_shift_f_goes_back_and_wraps() -> void:
	var unit := _spawn(Vector2i(1, 1))
	var slash := _attack("Slash")
	var thrust := _attack("Thrust")
	var smash := _attack("Smash")
	var weapons: Array[EquippableData] = [_weapon("Sword", [slash, thrust]), _weapon("Mace", [smash])]
	_arm(unit, weapons)
	_aim(unit, slash)

	_press_f(true)
	assert_object(unit.active_attack).override_failure_message("Shift+F did not wrap to the last attack") \
		.is_same(smash)
	_press_f(true)
	assert_object(unit.active_attack).override_failure_message("Shift+F went forward") \
		.is_same(thrust)
	_press_f()
	_press_f()
	assert_object(unit.active_attack).override_failure_message("F did not wrap to the first attack") \
		.is_same(slash)


func test_what_cannot_be_equipped_or_fired_is_left_out() -> void:
	var unit := _spawn(Vector2i(1, 1))
	var jab := _attack("Jab")
	var lunge := _attack("Lunge")
	lunge.requires_readiness = true
	var spear := _weapon("Spear", [jab, lunge], WeaponData.WeaponType.SPRINGSPEAR) as SpringspearWeaponInstance
	assert_object(spear).override_failure_message("fixture: the spear family built no spear").is_not_null()
	spear.ready = false   # sprung: Lunge cannot fire until it is wound again
	var blank := RuneData.new()   # nothing inscribed, so nobody can channel it (#157)
	var smash := _attack("Smash")
	var weapons: Array[EquippableData] = [spear, blank, _weapon("Mace", [smash])]
	_arm(unit, weapons)

	var listed: Array[AttackData] = []
	for option: Unit.AimOption in unit.aim_options(false):
		listed.append(option.attack)
	assert_array(listed).override_failure_message(
			"the cycle should hold exactly what the click could queue").contains_exactly([jab, smash])


func test_clicking_a_carried_weapons_attack_equips_it_queues_it_and_records_the_swap() -> void:
	var unit := _spawn(Vector2i(1, 1))
	var enemy := _spawn(Vector2i(2, 1), Team.Faction.ENEMY)
	var slash := _attack("Slash")
	var smash := _attack("Smash")
	var mace := _weapon("Mace", [smash])
	var weapons: Array[EquippableData] = [_weapon("Sword", [slash]), mace]
	_arm(unit, weapons)
	_aim(unit, slash)
	_press_f()

	game._on_left_click(enemy.movement.cell)

	assert_object(unit.get_equipped_weapon()).is_same(mace)
	var stamped: Array[AttackData] = []
	for action in unit.squad.get_actions():
		var attack := action as AttackAction
		if attack != null and attack.actor == unit:
			stamped.append(attack.fired_attack)
	assert_array(stamped).override_failure_message("the queued order did not fire the cycled attack") \
		.contains_exactly([smash])
	assert_int(_acts.size()).override_failure_message("the swap should be recorded exactly once").is_equal(1)
	assert_str(String(_acts[0][1])).is_equal(GearVerbs.name_of(GearVerbs.Verb.EQUIP))
	assert_int(int(_acts[0][2])).is_equal(unit.inventory.find(mace))


func test_backing_out_after_cycling_leaves_the_weapon_and_records_nothing() -> void:
	var unit := _spawn(Vector2i(1, 1))
	var slash := _attack("Slash")
	var sword := _weapon("Sword", [slash])
	var weapons: Array[EquippableData] = [sword, _weapon("Mace", [_attack("Smash")])]
	_arm(unit, weapons)
	_aim(unit, slash)
	_press_f()

	game._on_right_click()

	assert_object(unit.get_equipped_weapon()).is_same(sword)
	assert_int(_acts.size()).is_equal(0)
	assert_object(game.aim_source).is_null()
	assert_bool(game.aim_strip.visible).override_failure_message("the strip outlived its aim").is_false()


func test_a_watch_aim_cycles_watch_attacks() -> void:
	var unit := _spawn(Vector2i(1, 1))
	var guard_a := _attack("Bead")
	guard_a.can_overwatch = true
	var guard_b := _attack("Vigil")
	guard_b.can_overwatch = true
	var weapons: Array[EquippableData] = [
		_weapon("Carbine", [_attack("Shot"), guard_a]), _weapon("Bow", [_attack("Loose"), guard_b])]
	_arm(unit, weapons)
	game.select_unit(unit, unit.movement.cell)
	game.main_action_menu._pick_watch(unit, guard_a)

	_press_f()

	assert_object(unit.active_attack).is_same(guard_b)
	assert_int(game.aim_intent).override_failure_message("the cycle dropped the watch verb") \
		.is_equal(game.AimIntent.WATCH)


func test_one_attack_shows_its_name_and_no_keys() -> void:
	var unit := _spawn(Vector2i(1, 1))
	var slash := _attack("Slash")
	var weapons: Array[EquippableData] = [_weapon("Sword", [slash])]
	_arm(unit, weapons)
	_aim(unit, slash)

	var text := _strip_text()
	assert_str(text).contains("Slash")
	assert_str(text).contains("Sword")
	assert_str(text).override_failure_message("a cycle of one advertised its keys") \
		.not_contains(Controls.key_for_action("select_next_squadmate"))


# ------------------------------------------------------------------------------
#  The forecast leaves the board as it found it
# ------------------------------------------------------------------------------

# Every fire aim now resolves a hypothetical per hovered cell, and a hypothetical PUBLISHES the
# candidate's shoves (#1058 D2b): unrestored, the board would draw the target already thrown before
# anything was queued, and the next queue gate would read a shove nobody ordered.
func test_hovering_an_aim_forecasts_it_and_leaves_no_shove_behind() -> void:
	var unit := _spawn(Vector2i(1, 1))
	var enemy := _spawn(Vector2i(2, 1), Team.Faction.ENEMY)
	var shove := _attack("Shove")
	shove.knockback = 1
	var weapons: Array[EquippableData] = [_weapon("Mace", [shove])]
	_arm(unit, weapons)
	_aim(unit, shove)

	game.hover_presenter.update_hover_visuals(enemy.movement.cell)

	var forecast: ResolvedPlan = game.aim_forecast
	assert_object(forecast).override_failure_message("a legal aim forecast nothing").is_not_null()
	assert_bool(PlanResolver.plan_changes(enemy, forecast.hypo)).override_failure_message(
			"the forecast does not touch the unit the aim is on").is_true()
	assert_that(enemy.get_projected_destination()).override_failure_message(
			"the hover left the forecast's shove published on the board") \
		.is_equal(enemy.movement.cell)
