# The bottom-right End Turn button (#189) -- read at the RENDERED node (visible/flashing) rather
# than the predicate behind it, mirroring test_mission_status_panel.gd's doctrine: the wire cases
# drive the real dispatch (a menu WAIT pick, the button's own pressed signal), so a dropped
# refresh_end_turn_button() call or a broken .connect() goes red here, not just a wrong bool.
#
# Real game scene (the #114 fixture -- root MUST be named "Main" under /root).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

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
	game.turn_manager.set_active_faction(Team.Faction.PLAYER)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


func _flashing() -> bool:
	return game.end_turn_button.is_urgent()


# The card the early-press confirm puts up, if any.
func _open_confirm() -> ConfirmCard:
	for child in game.card_layer.get_children():
		if child is ConfirmCard:
			return child
	return null


# ==============================================================================
#  The flash -- what the old visibility rule became (#467)
# ==============================================================================

# THE #467 rule, and the reason every case below asks about the flash instead: End Turn left the
# action ring, so this button is the only door there is and the FLASH predicate may never hide it.
# Asserted across the states that used to -- nothing acted, and a locked board.
#
# What DOES hide it is a different predicate: #541's (the AI's turn, a squad mid-queue, in the
# section below) and #722's cinematic (test_hud_hides_for_the_cinematic.gd). A locked board on the
# player's own turn is neither -- a finished mission here, which is also #541's declared residual.
func test_the_flash_predicate_never_hides_the_button() -> void:
	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	game.refresh_end_turn_button()
	assert_bool(game.end_turn_button.visible) \
		.override_failure_message("hidden with actions still to spend -- the only door to ending a turn").is_true()

	game.main_action_menu.on_pressed(MainActionMenu.WAIT, unit)
	assert_bool(game.end_turn_button.visible).is_true()

	game.game_state = game.GameState.MISSION_OVER
	game.refresh_end_turn_button()
	assert_bool(game._board_locked_for_player()).override_failure_message(
		"fixture: the board is not locked, so this leg asks nothing").is_true()
	assert_bool(game.end_turn_button.visible) \
		.override_failure_message("a locked board hid the button -- the lock is the flash's clause, not a hide").is_true()


func test_not_flashing_with_one_unacted_squad() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	game.refresh_end_turn_button()
	assert_bool(_flashing()).is_false()


func test_flashes_once_the_last_squad_waits_through_the_real_menu_pick() -> void:
	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	assert_bool(_flashing()).is_false()

	game.main_action_menu.on_pressed(MainActionMenu.WAIT, unit)

	assert_bool(_flashing()) \
		.override_failure_message("End Turn button did not appear once the only squad waited") \
		.is_true()


func test_stays_unlit_until_every_squad_has_acted() -> void:
	var first := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var second := _spawn(Team.Faction.PLAYER, Vector2i(2, 2))

	game.main_action_menu.on_pressed(MainActionMenu.WAIT, first)
	assert_bool(_flashing()) \
		.override_failure_message("Button showed with a second squad still unacted") \
		.is_false()

	game.main_action_menu.on_pressed(MainActionMenu.WAIT, second)
	assert_bool(_flashing()).is_true()


func test_a_downed_squadmate_does_not_block_the_others() -> void:
	# faction_all_squads_acted only counts squads with an ACTIVE leader (mirrors
	# AIController.take_faction_turn's own filter) -- a squad whose leader is down has nothing
	# left to click either, so it must not hold the button hostage.
	var standing := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var downed := _spawn(Team.Faction.PLAYER, Vector2i(2, 2))
	downed.die()

	game.main_action_menu.on_pressed(MainActionMenu.WAIT, standing)

	assert_bool(_flashing()).is_true()


# ==============================================================================
#  The wire -- pressing the button actually ends the turn
# ==============================================================================

func test_pressing_the_button_ends_the_turn() -> void:
	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	game.main_action_menu.on_pressed(MainActionMenu.WAIT, unit)
	assert_bool(unit.squad.has_acted).is_true()

	game.end_turn_button.end_turn_requested.emit()   # the real .connect() site, not the handler directly
	await await_idle_frame()

	# Only PLAYER units are on the board, so the cycle hands the turn straight back to PLAYER,
	# which resets has_acted -- an observable side effect only reachable if the signal actually
	# drove game.end_turn() through to the turn handoff.
	assert_bool(unit.squad.has_acted) \
		.override_failure_message("end_turn_requested didn't reach game.end_turn() -- the turn never handed off") \
		.is_false()


# The other half of the same fact (#467): the button asks EXACTLY when it is not flashing, so a
# press that arrives with work left cannot quietly throw the turn away. Two squads, one waited --
# `has_acted` on the waited one is the observable, since only a real handoff resets it.
func test_pressing_with_actions_left_asks_first_and_no_means_no() -> void:
	var waited := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.PLAYER, Vector2i(4, 1))
	game.main_action_menu.on_pressed(MainActionMenu.WAIT, waited)
	game.refresh_end_turn_button()
	assert_bool(_flashing()) \
		.override_failure_message("the fixture had everyone done, so this case asks nothing").is_false()

	game.end_turn_button.end_turn_requested.emit()
	await await_idle_frame()

	var card := _open_confirm()
	assert_object(card) \
		.override_failure_message("a press with a squad still unspent ended the turn without asking").is_not_null()

	card.answered.emit(false)
	await await_idle_frame()
	assert_bool(waited.squad.has_acted) \
		.override_failure_message("answering No ended the turn anyway").is_true()


func test_answering_yes_to_the_early_press_ends_the_turn() -> void:
	var waited := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.PLAYER, Vector2i(4, 1))
	game.main_action_menu.on_pressed(MainActionMenu.WAIT, waited)

	game.end_turn_button.end_turn_requested.emit()
	await await_idle_frame()
	var card := _open_confirm()
	assert_object(card).is_not_null()

	card.answered.emit(true)
	await await_idle_frame()
	assert_bool(waited.squad.has_acted) \
		.override_failure_message("answering Yes did not reach the turn handoff").is_false()


# A press while everyone IS done goes straight through -- no card, which is what makes the flash
# mean "this will not interrupt you".
func test_a_press_while_the_button_flashes_never_asks() -> void:
	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	game.main_action_menu.on_pressed(MainActionMenu.WAIT, unit)
	game.refresh_end_turn_button()
	assert_bool(_flashing()).is_true()

	game.end_turn_button.end_turn_requested.emit()
	await await_idle_frame()

	assert_object(_open_confirm()) \
		.override_failure_message("a flashing button still asked").is_null()


func test_stops_flashing_after_the_turn_handoff() -> void:
	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	game.main_action_menu.on_pressed(MainActionMenu.WAIT, unit)
	assert_bool(_flashing()).is_true()

	game.end_turn_button.end_turn_requested.emit()
	await await_idle_frame()

	# Only PLAYER units are on the board, so the cycle hands the turn straight back to PLAYER --
	# freshly reset, nothing has acted yet.
	assert_bool(_flashing()) \
		.override_failure_message("Button stayed up into the next turn instead of resetting")\
		.is_false()


# ==============================================================================
#  Sharing the bottom-right corner with the objectives box
# ==============================================================================

func test_the_button_and_the_objectives_box_never_overlap() -> void:
	# Both live bottom-right (#189): the button at the corner, MissionStatusPanel lifted
	# BUTTON_CLEARANCE above its slot. The slot is reserved even while the button is hidden,
	# so this holds whenever both are visible at once.
	for cell: Vector2i in [Vector2i(3, 3)]:
		game.zone_manager.paint_cell("Point", ZoneManager.Kind.CAPTURE, cell)
	var typed: Array[MissionRules.Objective] = []
	typed.assign([MissionRules.Objective.CAPTURE])
	game.mission_controller.set_objectives(typed)

	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	game.main_action_menu.on_pressed(MainActionMenu.WAIT, unit)
	await await_idle_frame()

	assert_bool(_flashing()).is_true()
	assert_bool(game.mission_status_panel._panel.visible).is_true()
	var button_rect: Rect2 = game.end_turn_button._button.get_global_rect()
	var panel_rect: Rect2 = game.mission_status_panel._panel.get_global_rect()
	assert_bool(button_rect.intersects(panel_rect)) \
		.override_failure_message("End Turn button and objectives box overlap: %s vs %s" % [button_rect, panel_rect]) \
		.is_false()


func test_the_objectives_box_clears_the_execute_orders_button() -> void:
	# The other tenant of the right edge: while a plan is open, the queue dock's Execute button is
	# the lowest thing in it, and the objectives box -- lifted above the End Turn slot (#189) --
	# must not ride up into it. Found overlapping in play, 2026-08-11.
	for cell: Vector2i in [Vector2i(3, 3)]:
		game.zone_manager.paint_cell("Point", ZoneManager.Kind.CAPTURE, cell)
	var typed: Array[MissionRules.Objective] = []
	typed.assign([MissionRules.Objective.CAPTURE])
	game.mission_controller.set_objectives(typed)

	# The panel's own render path, fed a minimal view model: any non-empty entry list shows the
	# dock and its Execute button, which is all this layout question needs.
	var entries: Array[ActionQueueDisplayEntry] = [ActionQueueDisplayEntry.header("MOVE")]
	game.squad_action_queue_control.show_display_entries(entries)
	await await_idle_frame()

	assert_bool(game.squad_action_queue_control.visible).is_true()
	assert_bool(game.mission_status_panel._panel.visible).is_true()
	var execute_rect: Rect2 = game.squad_action_queue_control.execute_button.get_global_rect()
	var panel_rect: Rect2 = game.mission_status_panel._panel.get_global_rect()
	assert_bool(execute_rect.intersects(panel_rect)) \
		.override_failure_message("Execute Orders button and objectives box overlap: %s vs %s" % [execute_rect, panel_rect]) \
		.is_false()


# ==============================================================================
#  Locked-board guard
# ==============================================================================

func test_stops_flashing_while_the_board_is_locked() -> void:
	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	game.main_action_menu.on_pressed(MainActionMenu.WAIT, unit)
	assert_bool(_flashing()).is_true()

	game.game_state = game.GameState.AI_TURN
	game.refresh_end_turn_button()

	assert_bool(_flashing()).is_false()


# ==============================================================================
#  #541 -- not on the AI's turn, not while a squad is queuing
# ==============================================================================

# Every change to the button's `visible` from now on, each stamped with whose turn it was. An ARRAY
# because a lambda captures a local by value; `visibility_changed` fires on real changes only.
func _record_visibility() -> Array:
	var seen: Array = []
	var button: Control = game.end_turn_button
	button.visibility_changed.connect(func() -> void:
		seen.append([button.visible, game.turn_manager.active_faction()]))
	return seen


# A real order through the one queue door, which is what sets active_squad. Rev is the cheapest
# real main action to author: it only needs a chainsword in hand.
func _queue_a_rev(unit: Unit) -> RevAction:
	unit.equipped_weapon = H.make_weapon()
	var rev := RevAction.new()
	rev.init(unit)
	assert_bool(game.squad_manager.queue_action(unit.squad, rev)).override_failure_message(
		"fixture: the rev was refused, so nothing is queuing").is_true()
	return rev


func test_hidden_once_an_order_is_queued() -> void:
	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	game.refresh_end_turn_button()
	assert_bool(game.end_turn_button.visible).override_failure_message(
		"fixture: End Turn was already down").is_true()

	_queue_a_rev(unit)

	assert_bool(game.end_turn_button.visible).override_failure_message(
		"End Turn stayed up under Execute while a squad's plan was open").is_false()


# THE ORDERING CASE. The X ends in revert_if_only_hold, which empties the queue -- firing
# squad_became_empty -- and only THEN nulls active_squad. A refresh hung on the queue signal reads
# the squad as still queuing and leaves the button down for good.
func test_back_when_the_queue_is_cancelled() -> void:
	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var rev := _queue_a_rev(unit)
	assert_bool(game.end_turn_button.visible).is_false()

	game._on_queue_cancel_requested(rev)

	assert_object(game.squad_manager.active_squad).override_failure_message(
		"fixture: the cancel left the squad active, so this asks nothing").is_null()
	assert_bool(game.end_turn_button.visible).override_failure_message(
		"End Turn never came back after the queue was cancelled").is_true()


# The player's OWN pass, with the zoom off so the cinematic term stays out of it. active_squad
# holds for the whole pass and is let go in _end_squad_turn, so the one change is the return -- and
# it comes AFTER the blow, which is what the victim's HP at that moment says. A pass cannot be
# sampled mid-flight headlessly (Pacing collapses every beat), so the stamp is the only witness.
func test_hidden_through_the_players_own_pass_and_back_on_the_settled_board() -> void:
	var was_zoom := PlayerSettings.choice_of(PlayerSettings.Setting.BATTLE_ZOOM_MODE)
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, PlayerSettings.BattleZoom.OFF)
	var attacker := _spawn(Team.Faction.PLAYER, Vector2i(2, 2))
	var victim := _spawn(Team.Faction.ENEMY, Vector2i(3, 2))
	var hp_before := victim.get_current_hp()
	assert_bool(game.squad_manager.queue_action(attacker.squad, H.stamped_attack(attacker, victim))) \
		.override_failure_message("fixture: the attack was refused").is_true()
	assert_bool(game.end_turn_button.visible).is_false()
	var seen: Array = []
	var button: Control = game.end_turn_button
	button.visibility_changed.connect(func() -> void:
		seen.append([button.visible, victim.get_current_hp() < hp_before]))

	await game.order_executor.execute_orders(attacker)
	PlayerSettings.set_choice(PlayerSettings.Setting.BATTLE_ZOOM_MODE, was_zoom)

	assert_bool(attacker.squad.has_acted).override_failure_message(
		"fixture: the pass never ran, so an empty recording would prove nothing").is_true()
	assert_array(seen).override_failure_message(
		"End Turn moved mid-pass, came back before the blow landed, or never came back " \
		+ "([visible, blow landed]): %s" % [seen]) \
		.is_equal([[true, true]])


# The whole enemy turn, driven by the real press. One hide stamped ENEMY -- at the handoff, before
# the TURN_HANDOFF beat -- and one show stamped PLAYER. Anything between is the button standing up
# in a gap between enemy squads.
func test_hidden_for_the_whole_enemy_turn() -> void:
	var enemy_only: Array[Team.Faction] = [Team.Faction.ENEMY]
	game.ai_controller.set_ai_factions(enemy_only)
	var unit := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.ENEMY, Vector2i(9, 9))
	_spawn(Team.Faction.ENEMY, Vector2i(9, 7))
	game.main_action_menu.on_pressed(MainActionMenu.WAIT, unit)
	assert_bool(_flashing()).override_failure_message(
		"fixture: the press would ask first").is_true()
	var seen := _record_visibility()

	game.end_turn_button.end_turn_requested.emit()
	for _i in 600:
		if game.turn_manager.active_faction() == Team.Faction.PLAYER and not game.playback_owns_board():
			break
		await await_idle_frame()

	assert_int(game.turn_manager.active_faction()).override_failure_message(
		"fixture: the enemy turn never handed back").is_equal(Team.Faction.PLAYER)
	assert_array(seen).override_failure_message(
		"End Turn did not stand down for exactly the enemy turn: %s" % [seen]) \
		.is_equal([[false, Team.Faction.ENEMY], [true, Team.Faction.PLAYER]])


# "The AI's turn", never "not PLAYER's turn": a second faction with nobody driving it is a human
# at the controls (how the dev tests), and ending that turn is theirs to do.
func test_a_human_second_faction_keeps_its_end_turn() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.ENEMY, Vector2i(5, 5))
	game.turn_manager.set_active_faction(Team.Faction.ENEMY)
	game.refresh_end_turn_button()
	assert_bool(game.end_turn_button.visible).override_failure_message(
		"End Turn hid on a hotseat faction's turn").is_true()

	var enemy_only: Array[Team.Faction] = [Team.Faction.ENEMY]
	game.ai_controller.set_ai_factions(enemy_only)
	game.refresh_end_turn_button()
	assert_bool(game.end_turn_button.visible).override_failure_message(
		"End Turn stood up on the AI's turn").is_false()


# The threat preview runs the enemy's real archetypes through the queue door and rolls them back
# (#710), so active_squad goes to an enemy squad and back inside one call. It repaints nothing.
func test_the_threat_preview_does_not_move_it() -> void:
	var enemy_only: Array[Team.Faction] = [Team.Faction.ENEMY]
	game.ai_controller.set_ai_factions(enemy_only)
	_spawn(Team.Faction.PLAYER, Vector2i(2, 2))
	_spawn(Team.Faction.ENEMY, Vector2i(3, 2))
	game.refresh_end_turn_button()
	assert_bool(game.end_turn_button.visible).is_true()
	var seen := _record_visibility()

	game.ai_controller.preview_faction_turn(Team.Faction.PLAYER)

	assert_int(AIController.previewed_squad_count).override_failure_message(
		"fixture: the preview planned nobody, so nothing was queued").is_greater(0)
	assert_array(seen).override_failure_message(
		"the threat preview moved End Turn: %s" % [seen]).is_empty()
