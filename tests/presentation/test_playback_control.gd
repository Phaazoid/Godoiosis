# The playback speed setting, the held fast-forward and the skip (#545): PlaybackControl deciding,
# Pacing owning the one write to Engine.time_scale, and the fade and key hint it draws in the HUD.
#
# HEADLESS IS ALREADY UNWATCHED, and that is the structural limit worth stating first: Pacing.unwatched()
# answers true in every case here whether or not a skip is on, so no case can watch a skip collapse a
# pause or a pan. What IS observable: the speed each state asks for, the latch's edges, the fade, the
# mute, and that a skipped pass still ends the way an unskipped one does. That the escapes ASK the
# predicate is a source law (tests/law/test_playback_escapes_ask_unwatched.gd); how long the screen
# stays dark is a play-check.
#
# Cases that need exact timings switch the control's own _process off and drive tick() by hand; the
# wire cases leave it on and press the real action.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"

var _board := SharedBoard.new(SCENE_PATH, PROLOG)
var _scene: Node3D
var _game: Node2D
var _control: PlaybackControl
var _rig: CameraRig3D
var _fake_card: Node = null


func before() -> void:
	await _board.open(self)


func before_test() -> void:
	await _board.reset(self)
	_scene = _board.scene
	_game = _board.scene.game
	_control = _game.playback_control
	_rig = _scene.get_node("CameraRig") as CameraRig3D
	_control.reset()


# The knobs this writes (FAST_FORWARD, SKIP_FADE) are CLASS_KNOBS rows, which SharedBoard's own
# _restore_tuning puts back -- a second copy here would be a hand-maintained duplicate of it.
func after_test() -> void:
	Input.action_release("fast_forward")
	if _fake_card != null:
		_fake_card.free()
		_fake_card = null
	var director: ScenarioDirector = _game.scenario_director
	director._dialog_active = false
	_control.set_process(true)
	_control.reset()
	while Pacing.is_frozen():
		Pacing._unfreeze()
	Pacing.reset_playback()
	PlayerSettings.reset_for_test()
	_cam().set_playback_locked(false)
	_game.game_state = _game.GameState.IDLE
	_game.refresh_end_turn_button()
	await _board.check(self)


func after() -> void:
	_board.close()


# --- the one writer --------------------------------------------------------------------------------

func test_a_freeze_comes_back_to_the_playback_speed_not_to_one() -> void:
	_control.set_process(false)
	Pacing.set_playback_speed(3.0)
	assert_float(Engine.time_scale).is_equal_approx(3.0, 0.001)
	Pacing._freeze()
	assert_float(Engine.time_scale).override_failure_message(
			"a hitstop did not stop the world under a fast-forward").is_equal(0.0)
	Pacing._unfreeze()
	assert_float(Engine.time_scale).override_failure_message(
			"a hitstop ended a fast-forward -- the freeze restored 1x instead of the playback speed") \
		.is_equal_approx(3.0, 0.001)
	Pacing.reset_playback()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.001)


# --- the speed each state asks for ---------------------------------------------------------------

func test_the_hold_runs_only_while_playback_owns_the_board() -> void:
	assert_float(Pacing.FAST_FORWARD).override_failure_message(
			"precondition: a fast-forward of 1x makes every assertion below vacuous").is_not_equal(1.0)
	Input.action_press("fast_forward")
	await _settle()
	assert_float(Engine.time_scale).override_failure_message(
			"fast-forward ran with the board in the player's hands").is_equal_approx(1.0, 0.001)

	_claim_like_an_ai_turn()
	await _settle()
	assert_float(Engine.time_scale).override_failure_message(
			"holding fast-forward through an enemy turn did nothing") \
		.is_equal_approx(Pacing.FAST_FORWARD, 0.001)

	_game.game_state = _game.GameState.MENU
	await _settle()
	assert_float(Engine.time_scale).override_failure_message(
			"the pause menu ran at fast-forward").is_equal_approx(1.0, 0.001)

	_game.game_state = _game.GameState.AI_TURN
	_fake_card = Node.new()
	_fake_card.add_to_group(ModalLock.GROUP)
	add_child(_fake_card)
	await _settle()
	assert_float(Engine.time_scale).override_failure_message(
			"a card opened mid-fast-forward and kept the speed").is_equal_approx(1.0, 0.001)

	_fake_card.free()
	_fake_card = null
	await _settle()
	assert_float(Engine.time_scale).override_failure_message(
			"the fast-forward did not come back when the card closed") \
		.is_equal_approx(Pacing.FAST_FORWARD, 0.001)


# The fast-forward knob is set either side of the setting on purpose: at one value "max" and
# "the hold wins" agree, and at the other "max" and "they multiply" would.
func test_the_setting_is_the_base_and_the_hold_takes_the_faster_never_both() -> void:
	_control.set_process(false)
	PlayerSettings.set_choice(PlayerSettings.Setting.PLAYBACK_SPEED, PlayerSettings.PlaybackSpeed.DOUBLE)
	var base: float = PlayerSettings.PLAYBACK_MULTIPLIERS[PlayerSettings.PlaybackSpeed.DOUBLE]
	_claim_like_an_ai_turn()

	_control.tick(0.0, false)
	assert_float(Engine.time_scale).override_failure_message(
			"the playback speed setting did not reach playback").is_equal_approx(base, 0.001)

	Pacing.FAST_FORWARD = base * 0.75
	_control.tick(0.0, true)
	assert_float(Engine.time_scale).override_failure_message(
			"holding fast-forward SLOWED playback below the player's setting") \
		.is_equal_approx(base, 0.001)

	Pacing.FAST_FORWARD = base * 2.5
	_control.tick(0.0, true)
	assert_float(Engine.time_scale).override_failure_message(
			"the hold and the setting stacked instead of the faster one winning") \
		.is_equal_approx(base * 2.5, 0.001)


# The wire: the real action, a real pass, the control's own _process.
func test_a_held_fast_forward_speeds_a_real_pass_and_lets_go_with_it() -> void:
	var mover := _mobile_player_unit()
	assert_object(mover).override_failure_message(
			"fixture: no player unit on this board can move").is_not_null()
	_queue_a_move(mover)
	Input.action_press("fast_forward")

	_game.order_executor.execute_orders(mover)   # not awaited -- sampled per frame below
	var fastest := 1.0
	var frames := 0
	var saw_hint_lit := false
	while _game.order_executor.executing_plan != null:
		await await_idle_frame()
		fastest = maxf(fastest, Engine.time_scale)
		saw_hint_lit = saw_hint_lit or (_control.hint().visible and _control.hint().is_held())
		frames += 1
	await _settle()

	assert_int(frames).override_failure_message(
			"the pass took no frames, so nothing below was ever sampled").is_greater(0)
	assert_float(fastest).override_failure_message(
			"holding fast-forward never reached a real pass").is_equal_approx(Pacing.FAST_FORWARD, 0.001)
	assert_bool(saw_hint_lit).override_failure_message(
			"the hint never showed, lit, during the player's own pass").is_true()
	assert_bool(_control.hint().visible).override_failure_message(
			"the hint outlived the pass").is_false()
	assert_float(Engine.time_scale).override_failure_message(
			"the pass ended and playback stayed fast on the player's own board") \
		.is_equal_approx(1.0, 0.001)


# --- the skip --------------------------------------------------------------------------------------

func test_the_effects_go_quiet_only_while_a_skip_resolves() -> void:
	_control.set_process(false)
	await _settle()
	assert_bool(AudioServer.is_bus_mute(_sfx_bus())).override_failure_message(
			"precondition: the effects bus starts muted, so the case below proves nothing").is_false()
	Pacing.set_skipping(true)
	await _settle()
	assert_bool(AudioServer.is_bus_mute(_sfx_bus())).override_failure_message(
			"a skip played its sound effects").is_true()
	Pacing.set_skipping(false)
	await _settle()
	assert_bool(AudioServer.is_bus_mute(_sfx_bus())).override_failure_message(
			"the effects stayed muted after the skip").is_false()


# THE INVARIANT, driven through the phase that owns it: a skip changes how fast a pass runs and
# whether anyone sees it, never which code runs. So the skipped pass must end the way any pass does --
# the squad spent (_end_squad_turn), the borrowed view handed back (#520's "restored after, including
# on skip", owed to this ticket) -- and leave nothing of the skip behind.
func test_a_skipped_pass_still_ends_and_still_brings_the_view_home() -> void:
	Pacing.SKIP_FADE = 0.0
	var mover := _mobile_player_unit()
	assert_object(mover).override_failure_message(
			"fixture: no player unit on this board can move").is_not_null()
	_queue_a_move(mover)
	var squad: Squad = mover.squad

	_game.order_executor.execute_orders(mover)   # claims the lock synchronously, then walks
	assert_bool(_control.request_skip()).override_failure_message(
			"a skip was refused in the middle of a pass").is_true()
	var saw_skip := false
	var saw_borrowed := false
	var saw_muted := false
	while _game.order_executor.executing_plan != null:
		await await_idle_frame()
		saw_skip = saw_skip or (Pacing.skipping() and is_equal_approx(Engine.time_scale, Pacing.SKIP_SPEED))
		saw_borrowed = saw_borrowed or _rig._view_borrowed
		saw_muted = saw_muted or AudioServer.is_bus_mute(_sfx_bus())
	await _settle()

	assert_bool(saw_skip).override_failure_message(
			"the skip never ran the pass at skip speed").is_true()
	assert_bool(saw_muted).override_failure_message(
			"a skipped pass played its sound effects -- a whole turn's blows in one burst").is_true()
	assert_bool(saw_borrowed).override_failure_message(
			"precondition: the pass never borrowed the view, so its return proves nothing").is_true()
	assert_bool(squad.has_acted).override_failure_message(
			"a skipped pass never reached _end_squad_turn").is_true()
	assert_bool(_rig._view_borrowed).override_failure_message(
			"a skipped pass left the camera where the pass did -- the view never came home").is_false()
	assert_bool(Pacing.skipping()).override_failure_message(
			"the skip outlived the pass -- the player's own turn would run unwatched").is_false()
	assert_int(_control.phase).is_equal(PlaybackControl.Phase.IDLE)
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.001)
	assert_bool(AudioServer.is_bus_mute(_sfx_bus())).override_failure_message(
			"the effects stayed muted after the skip").is_false()


func test_a_skip_is_refused_on_the_players_board_and_while_a_dialog_talks() -> void:
	_control.set_process(false)
	assert_bool(_control.request_skip()).override_failure_message(
			"a skip latched with the board in the player's hands").is_false()

	_claim_like_an_ai_turn()
	var director: ScenarioDirector = _game.scenario_director
	director._dialog_active = true
	_control.tick(0.0, false)
	assert_bool(_control.request_skip()).override_failure_message(
			"Space advanced a dialog and skipped the turn behind it").is_false()

	# The press that ends a timeline's last line has already ended it by the time the frame asks.
	director._dialog_active = false
	assert_bool(_control.request_skip()).override_failure_message(
			"the press that ended a dialog also started a skip").is_false()

	_control.tick(0.0, false)
	assert_bool(_control.request_skip()).override_failure_message(
			"control: with the dialog gone a frame, a skip should take").is_true()


func test_the_skip_survives_the_pause_menu_and_ends_the_frame_playback_lets_go() -> void:
	_control.set_process(false)
	Pacing.SKIP_FADE = 0.0
	_claim_like_an_ai_turn()
	assert_bool(_control.request_skip()).is_true()
	_control.tick(0.0, false)
	assert_int(_control.phase).is_equal(PlaybackControl.Phase.SKIPPING)
	assert_float(Engine.time_scale).is_equal_approx(Pacing.SKIP_SPEED, 0.001)

	_game.game_state = _game.GameState.MENU
	_control.tick(0.0, false)
	assert_int(_control.phase).override_failure_message(
			"opening the pause menu threw the skip away").is_equal(PlaybackControl.Phase.SKIPPING)
	assert_float(Engine.time_scale).override_failure_message(
			"the pause menu ran at skip speed").is_equal_approx(1.0, 0.001)

	_game.game_state = _game.GameState.AI_TURN
	_cam().set_playback_locked(false)
	_game.game_state = _game.GameState.MISSION_OVER
	_control.tick(0.0, false)
	assert_bool(Pacing.skipping()).override_failure_message(
			"the skip outlived playback").is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.001)
	_control.tick(0.0, false)
	assert_int(_control.phase).is_equal(PlaybackControl.Phase.IDLE)


func test_a_board_swap_mid_skip_ends_it() -> void:
	_control.set_process(false)
	Pacing.SKIP_FADE = 0.0
	_claim_like_an_ai_turn()
	assert_bool(_control.request_skip()).is_true()
	_control.tick(0.0, false)
	assert_bool(Pacing.skipping()).is_true()

	var manager: ScenarioManager = _game.scenario_manager
	manager.clear_board()
	_control.tick(0.0, false)
	assert_bool(Pacing.skipping()).override_failure_message(
			"a skip survived the board it was skipping").is_false()


# The skip state turns on only at FULL black, or the player watches the pass snap through the fade.
func test_the_fade_is_drawn_and_the_skip_waits_for_full_black() -> void:
	_control.set_process(false)
	Pacing.SKIP_FADE = 1.0
	_claim_like_an_ai_turn()
	assert_bool(_control.request_skip()).is_true()

	_control.tick(0.5, false)
	assert_int(_control.phase).is_equal(PlaybackControl.Phase.FADING_OUT)
	assert_bool(Pacing.skipping()).override_failure_message(
			"the skip ran before the screen was dark").is_false()
	var rect := _control.fade_rect()
	assert_object(rect).override_failure_message("nothing built the fade").is_not_null()
	assert_float(rect.color.a).is_equal_approx(0.5, 0.01)
	assert_bool(rect.visible).is_true()

	_control.tick(0.5, false)
	assert_bool(Pacing.skipping()).override_failure_message(
			"the screen went dark and the skip never started").is_true()

	_cam().set_playback_locked(false)
	_game.game_state = _game.GameState.IDLE
	_control.tick(0.5, false)
	_control.tick(0.5, false)
	_control.tick(0.5, false)
	assert_int(_control.phase).is_equal(PlaybackControl.Phase.IDLE)
	assert_bool(rect.visible).override_failure_message(
			"the fade stayed up after the skip ended").is_false()


# THE BUG THIS ROUND FIXED: the fade was a rect in Battle3D's own CanvasLayer, which draws over the
# whole game viewport -- pause menu included -- so Esc mid-skip opened a menu under the black. Layer
# numbers only order layers WITHIN one viewport, so the law asks both: same viewport as the cards,
# and a lower layer than the dialogue and every card.
func test_the_fade_sits_under_the_dialogue_and_every_card() -> void:
	var rect := _control.fade_rect()
	var cards: CanvasLayer = _game.card_layer
	assert_object(rect.get_viewport()).override_failure_message(
			"the fade draws in a different viewport from the cards, so no layer number can order them") \
		.is_same(cards.get_viewport())
	var layer := rect.get_canvas_layer_node()
	assert_object(layer).override_failure_message("the fade is on no CanvasLayer").is_not_null()
	assert_int(layer.layer).override_failure_message(
			"the fade draws over the dialogue -- a line spoken mid-skip would be hidden") \
		.is_less(UiLayers.LAYER_DIALOGUE)
	assert_int(layer.layer).override_failure_message(
			"the fade draws over the cards -- a pause menu opened mid-skip would be hidden") \
		.is_less(cards.layer)


# --- the hint ----------------------------------------------------------------------------------------

func test_the_hint_shows_only_while_playback_owns_the_board() -> void:
	_control.set_process(false)
	_control.tick(0.0, false)
	assert_bool(_control.hint().visible).override_failure_message(
			"the playback keys are advertised on the player's own board").is_false()
	_claim_like_an_ai_turn()
	_control.tick(0.0, false)
	assert_bool(_control.hint().visible).override_failure_message(
			"an enemy turn is playing and the hint is not up").is_true()
	_cam().set_playback_locked(false)
	_game.game_state = _game.GameState.IDLE
	_control.tick(0.0, false)
	assert_bool(_control.hint().visible).override_failure_message(
			"the hint outlived playback").is_false()


func test_the_hint_steps_aside_for_a_menu_a_card_and_a_skip() -> void:
	_control.set_process(false)
	Pacing.SKIP_FADE = 1.0
	_claim_like_an_ai_turn()
	_control.tick(0.0, false)
	assert_bool(_control.hint().visible).override_failure_message(
			"precondition: the hint should be up before anything covers it").is_true()

	_game.game_state = _game.GameState.MENU
	_control.tick(0.0, false)
	assert_bool(_control.hint().visible).override_failure_message(
			"the hint stayed up under the pause menu").is_false()

	_game.game_state = _game.GameState.AI_TURN
	_fake_card = Node.new()
	_fake_card.add_to_group(ModalLock.GROUP)
	add_child(_fake_card)
	_control.tick(0.0, false)
	assert_bool(_control.hint().visible).override_failure_message(
			"the hint stayed up under a card").is_false()
	_fake_card.free()
	_fake_card = null

	assert_bool(_control.request_skip()).is_true()
	_control.tick(0.25, false)
	assert_int(_control.phase).is_equal(PlaybackControl.Phase.FADING_OUT)
	assert_bool(_control.hint().visible).override_failure_message(
			"the hint stayed up while the screen faded for a skip").is_false()


# One slot, one occupant: End Turn stays up through the player's own end-of-turn burn.
func test_the_hint_yields_to_a_visible_end_turn() -> void:
	_control.set_process(false)
	_claim_like_an_ai_turn()
	var end_turn: EndTurnButton = _game.end_turn_button
	end_turn.set_offered(true)
	end_turn.set_hidden_for_playback(false)
	assert_bool(end_turn.visible).override_failure_message(
			"precondition: End Turn should be up for this case").is_true()
	_control.tick(0.0, false)
	assert_bool(_control.hint().visible).override_failure_message(
			"the hint drew over End Turn in the same corner").is_false()


func test_holding_shift_lights_the_hint() -> void:
	_control.set_process(false)
	_claim_like_an_ai_turn()
	_control.tick(0.0, true)
	assert_bool(_control.hint().is_held()).override_failure_message(
			"Shift is down and the hint does not say so").is_true()
	_control.tick(0.0, false)
	assert_bool(_control.hint().is_held()).override_failure_message(
			"the hint stayed lit after Shift came up").is_false()


# The F3 sign's rule: a key on screen is the registry's key, so it cannot name one the game lacks.
func test_the_hint_names_the_keys_the_registry_holds() -> void:
	var readout := _control.hint().readout()
	for action: String in [PlaybackHint.FAST_FORWARD_ACTION, PlaybackHint.SKIP_ACTION]:
		var key := Controls.key_for_action(action)
		assert_str(key).override_failure_message("nothing documents %s" % action).is_not_empty()
		assert_bool(readout.contains(key)).override_failure_message(
				"the hint does not name %s's key (%s): %s" % [action, key, readout]).is_true()


# --- the dev pause (#705) --------------------------------------------------------------------------
#
# P freezes a pass mid-blow and hands the dev the camera, so a shot can be SHOWN rather than
# described. Whether the camera FEELS right to drive while paused is a play-check: headless, the rig's
# eases land in one frame whatever clock they run on.

func test_a_dev_pause_holds_time_at_zero_at_any_speed_and_through_a_hitstop() -> void:
	_control.set_process(false)
	Pacing.set_playback_speed(3.0)
	Pacing.set_dev_paused(true)
	assert_float(Engine.time_scale).override_failure_message(
			"a dev pause did not stop the world").is_equal(0.0)
	Pacing.set_playback_speed(Pacing.FAST_FORWARD)
	assert_float(Engine.time_scale).override_failure_message(
			"a speed change -- PlaybackControl's every-frame write -- undid the pause").is_equal(0.0)
	Pacing._freeze()
	Pacing._unfreeze()
	assert_float(Engine.time_scale).override_failure_message(
			"a hitstop's release -- its timer ignores time scale -- undid the pause").is_equal(0.0)
	Pacing.set_dev_paused(false)
	assert_float(Engine.time_scale).override_failure_message(
			"resuming did not come back to the playback speed") \
		.is_equal_approx(Pacing.FAST_FORWARD, 0.001)
	Pacing.set_dev_paused(true)
	Pacing.reset_playback()
	assert_bool(Pacing.dev_paused()).override_failure_message(
			"a reset left the game paused").is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.001)


func test_p_pauses_only_a_pass_and_works_from_either_window() -> void:
	_control.set_process(false)
	var dev: DevController = _game.dev_controller
	dev.handle_dev_key(_p_press())
	assert_bool(Pacing.dev_paused()).override_failure_message(
			"P froze a board nobody was playing out -- the camera is already the dev's there").is_false()
	_claim_like_an_ai_turn()
	var overlay: DevOverlay = _game.dev_overlay
	overlay._input(_p_press())
	assert_bool(Pacing.dev_paused()).override_failure_message(
			"P from the dev-tools window did not pause the pass (the two-window rule)").is_true()
	dev.handle_dev_key(_p_press())
	assert_bool(Pacing.dev_paused()).override_failure_message(
			"a second P did not resume").is_false()


func test_a_dev_pause_hands_over_the_camera_and_gives_the_directors_frame_back() -> void:
	_control.set_process(false)
	_claim_like_an_ai_turn()
	_scene._process(0.016)
	assert_bool(_rig.manual_input_enabled).override_failure_message(
			"precondition: playback did not take the camera off the player").is_false()
	Pacing.set_dev_paused(true)
	_scene._process(0.016)
	assert_bool(_rig.manual_input_enabled).override_failure_message(
			"paused, and the dev still cannot move the camera").is_true()
	var label: Label = _scene.dev_pause_label()
	assert_bool(label.visible).override_failure_message("nothing on screen says it is paused").is_true()
	var director_frame: Dictionary = _scene._held_frame.duplicate()
	assert_bool(director_frame.is_empty()).override_failure_message(
			"the pause did not keep the director's frame").is_false()
	# The dev frames something else entirely...
	var moved := _rig._target_aim + Vector3(3.0, 0.0, 2.0)
	_rig.hold_at(moved)
	_rig.set_zoom(_rig._target_distance + 4.0)
	_rig._target_yaw_degrees += 90.0
	_scene._mirror_camera()
	assert_bool(_rig._target_aim.is_equal_approx(moved)).override_failure_message(
			"the director put the camera back while the dev held it").is_true()
	# ...and resuming cuts straight back to the director's frame.
	Pacing.set_dev_paused(false)
	_scene._mirror_camera()
	var back := _rig.snapshot_view()
	for channel: String in ["target_aim", "target_yaw", "target_distance", "target_pitch", "distance"]:
		assert_bool(back[channel] == director_frame[channel] \
				or (back[channel] is Vector3 and (back[channel] as Vector3).is_equal_approx(director_frame[channel])) \
				or (back[channel] is float and is_equal_approx(back[channel], director_frame[channel]))) \
			.override_failure_message("resume left %s at %s, not the director's %s" % [
					channel, back[channel], director_frame[channel]]).is_true()
	assert_bool(label.visible).override_failure_message("the PAUSED label outlived the pause").is_false()


func test_space_and_the_key_hint_are_off_while_paused() -> void:
	_control.set_process(false)
	_claim_like_an_ai_turn()
	assert_bool(_control.hint_shown(true)).override_failure_message(
			"precondition: the hint is not up during a pass").is_true()
	Pacing.set_dev_paused(true)
	assert_bool(_control.request_skip()).override_failure_message(
			"a skip started under a dev pause, with every tween frozen under its fade").is_false()
	assert_bool(_control.hint_shown(true)).override_failure_message(
			"the hint offered keys that do nothing while paused").is_false()


func test_playback_letting_go_releases_the_pause() -> void:
	_control.set_process(false)
	_claim_like_an_ai_turn()
	Pacing.set_dev_paused(true)
	_cam().set_playback_locked(false)
	_game.game_state = _game.GameState.IDLE
	_control.tick(0.016, false)
	assert_bool(Pacing.dev_paused()).override_failure_message(
			"the pass let go (F2, a board swap, its end) and left the game frozen").is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.001)


func test_the_camera_runs_on_the_wall_clock_only_while_paused() -> void:
	_rig._last_usec = Time.get_ticks_usec() - 50_000
	assert_float(_rig._camera_delta(0.0)).override_failure_message(
			"unpaused, the camera stopped following game time").is_equal(0.0)
	Pacing.set_dev_paused(true)
	_rig._last_usec = Time.get_ticks_usec() - 50_000
	var step := _rig._camera_delta(0.0)
	assert_float(step).override_failure_message(
			"paused, the camera stepped %.3fs -- frozen with the pass, it cannot be framed with" % step) \
		.is_between(0.04, 0.1)


func test_a_long_dev_pause_does_not_spend_the_wait_for_the_camera_to_come_home() -> void:
	_control.set_process(false)
	_claim_like_an_ai_turn()
	Pacing.set_dev_paused(true)
	await _settle()   # the claim's own edge zeroes the drop; let it pass before going down the pit
	_rig._drop = 1.0
	_rig._target_drop = 1.0
	await _settle()   # the mirror publishes the rig's depth as fall_depth on its next frame
	assert_float(_cam().fall_depth).override_failure_message(
			"precondition: the camera is not down a pit, so the wait returns at once").is_greater(0.5)
	var done: Array[bool] = [false]
	var waits := func() -> void:
		await _game.order_executor._wait_for_the_camera_to_come_home()
		done[0] = true
	waits.call()
	for i in 640:
		await get_tree().process_frame
	assert_bool(done[0]).override_failure_message(
			"a pause longer than the wait's frame budget sent the tiles home under a camera still in the pit") \
		.is_false()
	_rig._drop = 0.0
	_rig._target_drop = 0.0
	Pacing.set_dev_paused(false)
	for i in 4:
		await get_tree().process_frame
	assert_bool(done[0]).override_failure_message(
			"the camera came home and the wait never noticed").is_true()


func _p_press() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_P
	event.pressed = true
	return event


# --- helpers --------------------------------------------------------------------------------------

# The AI-turn shape: the state and the lock, held for a whole turn -- and End Turn down, as #541 has
# it on an AI faction's turn (this fixture keeps the player's faction active, so it says so itself).
func _claim_like_an_ai_turn() -> void:
	_game.game_state = _game.GameState.AI_TURN
	_cam().set_playback_locked(true)
	var end_turn: EndTurnButton = _game.end_turn_button
	end_turn.set_offered(false)


func _cam() -> CameraController:
	return _game.camera_controller


func _sfx_bus() -> int:
	var director: AudioDirector = _game.audio_director
	return director.bus_of(PlayerSettings.Setting.SFX_VOLUME)


func _queue_a_move(unit: Unit) -> void:
	var moverange = _game.compute_move_range(unit)
	var destinations: Array[Vector2i] = _game.get_move_range(moverange, unit)
	var path := RulesService.reconstruct_path(moverange.came_from, unit.movement.cell, destinations[0])
	var move := MoveAction.new()
	move.init(unit, path, null)
	assert_bool(_game.squad_manager.queue_action(unit.squad, move)).override_failure_message(
			"fixture: the move was refused, so the pass would concede instead of playing").is_true()


func _mobile_player_unit() -> Unit:
	for child in _game.units_root.get_children():
		var unit := child as Unit
		if unit == null or unit.get_faction() != Team.Faction.PLAYER:
			continue
		var reachable: Array[Vector2i] = _game.get_move_range(_game.compute_move_range(unit), unit)
		if not reachable.is_empty():
			return unit
	return null


# process_frame resumes coroutines BEFORE node _process, so one frame is stale.
func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()
