# ONE ACTION PER SQUAD PER TURN (#1556), on a real Main.tscn board through the real doors: ring picks
# (the controller's `cancelled` then `action_selected`, the order a real pick emits), board clicks
# (game._on_left_click) and the queue panel's Execute signal.
#
# Two holes, each its own half:
# - A mode open when Execute was pressed outlived the pass. Its gate (MainActionMenu's
#   _can_take_main_action) was asked when it opened, so one more click queued a second action for
#   the spent squad. Execute now leaves the mode first.
# - A member ejected from its squad got a fresh solo squad, and a fresh squad read as un-acted, so
#   the ring offered it a whole second turn. eject carries has_acted now, and a squad is spent from
#   the moment its pass begins (SquadManager.spend_turn), since its own pass ejects before it ends.
#
# Every board is laid out in the case; nothing here pins authored content. The ring's answer is
# read off MainActionMenu.populate, the list the ring is built from.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const MD := preload("res://tests/support/menu_drive.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const DEEP_WATER := Vector2i(5, 6)   # play/board_builder.gd's: walkable only frozen
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
# The ring rows that spend a turn. An acted squad's member must be offered none of them.
const TURN_ROWS: Array[int] = [MainActionMenu.MOVE, MainActionMenu.GROUP_MOVE, MainActionMenu.ATTACK,
		MainActionMenu.WEAPON_ACTION, MainActionMenu.GUARD, MainActionMenu.WAIT]

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.mission_controller._close_mission_select()
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	game.turn_manager.set_active_faction(PLAYER)
	for x in range(10):
		for y in range(5):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	game.scenario_manager.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# --- fixture -------------------------------------------------------------------------------------

func _spawn(faction: Team.Faction, cell: Vector2i, stats: Dictionary = {}, power := 3,
		knockback := 0) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data(stats, faction), cell)
	assert_object(unit).override_failure_message("fixture: nothing would spawn at %s" % cell).is_not_null()
	var weapon := H.make_weapon(power)
	(weapon.template.main_attack as WeaponAttackData).knockback = knockback
	unit.equipped_weapon = weapon
	unit.set_current_hp(unit.get_max_hp())
	return unit


func _squad(leader: Unit, members: Array[Unit]) -> void:
	for member in members:
		game.squad_manager.join_squad(member, leader.squad)
	assert_int(leader.squad.members.size()).override_failure_message(
			"fixture: the squad did not form").is_equal(members.size() + 1)


# Open the unit's ring the way a player does: a click where its sprite stands.
func _open_ring(unit: Unit) -> ActionMenuController:
	game._on_left_click(unit.get_projected_destination())
	var controller := MD.controller_of(game)
	assert_object(controller).override_failure_message(
			"fixture: no ring opened on %s" % unit.movement.cell).is_not_null()
	return controller


func _pick(action_id: int, unit: Unit) -> void:
	var controller := _open_ring(unit)
	controller.cancelled.emit(controller)
	controller.action_selected.emit(action_id, unit)


# The ring's first attack: a synthetic leaf, so it is found by walking the tree the ring shows.
func _pick_first_attack(unit: Unit) -> void:
	var controller := _open_ring(unit)
	var leaf := MD.first_leaf_under(controller.level_nodes(), MD.kit_category(game, unit))
	assert_bool(leaf.is_empty()).override_failure_message("fixture: the ring offered no attack").is_false()
	controller.cancelled.emit(controller)
	controller.action_selected.emit(int(leaf.get("id", 0)), unit)
	assert_int(game.game_state).override_failure_message(
			"fixture: the attack pick opened no aim").is_equal(game.GameState.ATTACK_TARGETING)


# Aim and click: the order a player queues.
func _attack(attacker: Unit, cell: Vector2i) -> void:
	_pick_first_attack(attacker)
	game._on_left_click(cell)
	assert_bool(attacker.has_main_action_queued()).override_failure_message(
			"fixture: the attack at %s never queued" % cell).is_true()


# The queue panel's Execute, then wait for the pass to END: executing_plan is released there.
func _execute() -> void:
	game.squad_action_queue_control.execute_requested.emit()
	for _i in range(600):
		if game.order_executor.executing_plan == null and not game.playback_owns_board():
			break
		await await_idle_frame()
	await await_idle_frame()


func _turn_rows_offered(unit: Unit) -> Array[String]:
	var offered: Array[String] = []
	var rows: Array = game.main_action_menu.populate(unit)
	for id: int in TURN_ROWS:
		if rows.has(id):
			offered.append(String(MainActionMenu.ACTION_DATA[id]["name"]))
	return offered


func _assert_spent(unit: Unit, how: String) -> void:
	assert_bool(unit.squad.has_acted).override_failure_message(
			"%s: the member's new squad reads as not having acted" % how).is_true()
	assert_array(_turn_rows_offered(unit)).override_failure_message(
			"%s: the ring offered the member a second turn: %s" % [how, _turn_rows_offered(unit)]).is_empty()


# --- Execute leaves the open mode ----------------------------------------------------------------

func test_execute_pressed_mid_aim_leaves_no_aim_to_click() -> void:
	var hero := _spawn(PLAYER, Vector2i(1, 2))
	var foe := _spawn(ENEMY, Vector2i(3, 2), {Stats.Stat.MHP: 200})
	_pick(MainActionMenu.MOVE, hero)
	game._on_left_click(Vector2i(2, 2))
	assert_int(hero.squad.action_queue.size()).override_failure_message(
			"fixture: the move never queued").is_greater(0)
	_pick_first_attack(hero)   # the aim is open, and the player presses Execute instead of a target

	await _execute()

	assert_bool(hero.squad.has_acted).override_failure_message("fixture: the pass never ran").is_true()
	assert_int(game.game_state).override_failure_message(
			"the aim outlived the pass it was opened before").is_equal(game._base_state())
	assert_bool(game.aim_strip.visible).override_failure_message(
			"the aim strip outlived the pass").is_false()
	game._on_left_click(foe.movement.cell)
	assert_bool(hero.squad.action_queue.is_empty()).override_failure_message(
			"a click after the pass queued %d orders for the squad that had acted" % hero.squad.action_queue.size()) \
		.is_true()
	assert_object(game.squad_manager.active_squad).override_failure_message(
			"the spent squad became the active squad again").is_not_same(hero.squad)


func test_execute_pressed_mid_move_pick_leaves_no_pick_to_click() -> void:
	var lead := _spawn(PLAYER, Vector2i(1, 2), {Stats.Stat.LDR: 10})
	var member := _spawn(PLAYER, Vector2i(1, 3))
	_squad(lead, [member])
	_pick(MainActionMenu.MOVE, member)
	game._on_left_click(Vector2i(2, 3))
	assert_bool(member.has_action_type_queued(BaseAction.ActionType.MOVE)).override_failure_message(
			"fixture: the member's move never queued").is_true()
	_pick(MainActionMenu.MOVE, lead)
	assert_int(game.game_state).override_failure_message(
			"fixture: the leader's move pick never opened").is_equal(game.GameState.CHOOSING_MOVE)
	var step := Vector2i(-1, -1)
	for cell: Vector2i in game.get_move_range(game.move_mode_range, lead):
		if cell != lead.movement.cell and cell != Vector2i(2, 3):
			step = cell
			break
	assert_that(step).override_failure_message("fixture: the pick offered no cell").is_not_equal(Vector2i(-1, -1))

	await _execute()

	assert_bool(lead.squad.has_acted).override_failure_message("fixture: the pass never ran").is_true()
	assert_int(game.game_state).override_failure_message(
			"the move pick outlived the pass it was opened before").is_equal(game._base_state())
	game._on_left_click(step)
	assert_bool(lead.squad.action_queue.is_empty()).override_failure_message(
			"a click after the pass queued a move for the squad that had acted").is_true()


# --- An ejected member stays spent ---------------------------------------------------------------

# test_split_forecast's counter-shove layout: the member's own attack draws a counter that knocks
# it out of its leader's reach, and the pass-end sweep ejects it.
func test_a_member_its_own_pass_shoves_out_stays_spent() -> void:
	var lead := _spawn(PLAYER, Vector2i(1, 3), {Stats.Stat.LDR: 10})
	var member := _spawn(PLAYER, Vector2i(4, 2), {}, 1)
	_squad(lead, [member])
	_spawn(ENEMY, Vector2i(3, 2), {Stats.Stat.MHP: 200}, 1, 2)
	_attack(member, Vector2i(3, 2))

	await _execute()

	assert_bool(member.squad == lead.squad).override_failure_message(
			"fixture: the counter never shoved the member out of contact").is_false()
	_assert_spent(member, "ejected at its own pass's end")


# The leader dies to the counter MID-pass; the heir cannot reach `far`, so the handover ejects it
# while the pass is still playing -- before the pass's end could mark anything.
func test_a_member_a_mid_pass_handover_strands_stays_spent() -> void:
	var lead := _spawn(PLAYER, Vector2i(4, 2), {Stats.Stat.LDR: 10})
	var heir := _spawn(PLAYER, Vector2i(6, 2), {Stats.Stat.LDR: 4})
	var far := _spawn(PLAYER, Vector2i(1, 2))
	_squad(lead, [heir, far])
	_spawn(ENEMY, Vector2i(4, 3), {Stats.Stat.MHP: 200}, 200)
	_attack(lead, Vector2i(4, 3))

	await _execute()

	assert_bool(is_instance_valid(lead) and lead.is_active()).override_failure_message(
			"fixture: the counter never felled the leader").is_false()
	assert_bool(far.squad == heir.squad).override_failure_message(
			"fixture: the heir kept the member it cannot reach").is_false()
	_assert_spent(far, "ejected by a mid-pass handover")


# A squad that has already acted (it Waited) loses a member to ANOTHER squad's pass. An attack aimed
# at an ally whiffs ("nothing to hit"), so the displacement is test_split_forecast's melt instead: a
# fire on the one ice crossing between leader and member. The member leaves a spent squad, so it
# stays spent.
func test_a_member_a_later_pass_ejects_from_a_spent_squad_stays_spent() -> void:
	var grid: BoardGrid = game.grid
	for x in range(10):
		grid.paint(Vector2i(x, 2), GRASS_SOURCE, DEEP_WATER)
	var ice := ResolvedCellEffect.new()
	ice.cell = Vector2i(1, 2)
	ice.states_added.assign([Terrain.TileState.FROZEN])
	game.terrain_states.apply(ice)
	var lead := _spawn(PLAYER, Vector2i(2, 1), {Stats.Stat.LDR: 10, Stats.Stat.COH: 3})
	var member := _spawn(PLAYER, Vector2i(1, 3))
	_squad(lead, [member])
	_pick(MainActionMenu.WAIT, lead)
	assert_bool(lead.squad.has_acted).override_failure_message("fixture: Wait never spent the squad").is_true()
	var burner := _spawn(PLAYER, Vector2i(1, 1))
	var flame: WeaponAttackData = (burner.get_equipped_weapon() as WeaponInstance).template.main_attack
	flame.elemental_damage_type = Elemental.Element.FIRE
	flame.targets = EquippableData.TargetMode.BOTH
	_attack(burner, ice.cell)

	await _execute()

	assert_bool(member.squad == lead.squad).override_failure_message(
			"fixture: the melt never cut the member off from its leader").is_false()
	_assert_spent(member, "ejected from a squad that had waited")
