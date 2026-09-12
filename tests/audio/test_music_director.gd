# THE SCORE (#136 slice 3), on a real Main.tscn through the real doors.
#
# WHAT A GREEN SUITE WOULD MISS WITHOUT THIS. The director is a RECONCILE -- it reads the game every
# frame rather than listening to a signal -- so the thing that can silently not happen is not a
# missing connection but a `_process` that never runs, or one whose two reads are right while nothing
# acts on them. A case that drives no frames cannot tell those apart from a working director, which
# is why every case here awaits frames after a door and asserts the track AFTER the swap.
#
# WHY THE ENEMY-TURN CASE TURNS THE AI OFF, and it is measured rather than stylistic: Pacing.beat and
# CameraController.pan_to both return immediately headless (Pacing.gd's `seconds <= 0.0 or headless`
# escape, CameraRig's twin) and execute_orders runs to completion without awaiting a frame, so an
# AI-controlled turn -- plan, act, and the hand-back at the end of take_faction_turn -- completes
# inside ONE call chain and `_process` never sees ENEMY active at all. With AI off the ENEMY turn
# sits there waiting for a human, which is what makes the swap observable. That is also the argument
# for the rule being SIDE rather than CONTROL: a hotseat enemy turn is a real configuration the dev
# tests in, and it has to sound like the enemy's turn.
#
# A HEADLESS SUITE CANNOT HEAR ANYTHING. What it can see is which player was told to play what, and
# where in the track it was told to start -- the playback position DOES advance here (measured
# 2026-09-11: 0.37 after half a second of wall clock, so the Dummy driver mixes behind real time
# rather than freezing), which is the only reason the resume case below can exist.
#
# Every case runs with CROSSFADE_SECONDS = 0, so a swap lands in one frame. That NEUTRALIZES the feel
# value rather than pinning it: what is under test is which track, in a unit the fade length cannot
# move. after_test puts it back, and the volume row with it -- both are process-wide statics that
# would otherwise ride into every suite after this one in the shard.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const TEST_SAVE_DIR := "user://test_saves_music/"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D
var _fade_was := 0.0
var _volume_was := 0.0


func before_test() -> void:
	_fade_was = MusicDirector.CROSSFADE_SECONDS
	_volume_was = PlayerSettings.level_of(PlayerSettings.Setting.MUSIC_VOLUME)
	MusicDirector.CROSSFADE_SECONDS = 0.0
	# Redirected for test_pause_menu.gd's reason: the boot title screen reads this to decide whether
	# a "Load Game" row exists, and the suite otherwise shares the dev's own play saves.
	ScenarioManager.save_dir = TEST_SAVE_DIR
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	# game._ready DEFERS open_mission_select, so the front door lands a frame or two after the scene
	# -- which is also why the director's very first reconcile may precede it. Nothing is asserted
	# about that frame: the fade starts from silence, so a frame of the wrong track is inaudible, and
	# no test can observe a frame that happens during instantiation anyway.
	await await_idle_frame()
	await await_idle_frame()


func after_test() -> void:
	MusicDirector.CROSSFADE_SECONDS = _fade_was
	PlayerSettings.set_level(PlayerSettings.Setting.MUSIC_VOLUME, _volume_was)
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _director() -> MusicDirector:
	var director: MusicDirector = game.music_director
	assert_object(director).override_failure_message(
		"fixture: game built no music_director").is_not_null()
	return director


func _title_screen() -> MissionSelectScreen:
	var layer: Node = game.get("ui_layer")
	for child: Node in layer.get_children():
		if child is MissionSelectScreen:
			return child as MissionSelectScreen
	return null


# Leave the front door the way the player does -- the Sandbox row's own signal, which closes the
# screen, builds a board and begins a turn. Then clear that board and paint our own, so no case
# asserts anything about what the sandbox happens to contain (the content razor).
func _open_a_board() -> void:
	var screen := _title_screen()
	assert_object(screen).override_failure_message(
		"fixture: no title screen, so there is no real door to leave through").is_not_null()
	screen.sandbox_chosen.emit()
	await await_idle_frame()
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		for y in range(3):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	# Nobody plays the computer's side: every case here drives the hand-off by hand, and an armed AI
	# would run the whole enemy turn inside one call chain (see the header).
	var no_ai: Array[Team.Faction] = []
	game.ai_controller.set_ai_factions(no_ai)
	await await_idle_frame()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


# One hand-off through the End Turn button's own door, then frames for the reconcile to see it.
#
# TWO frames, not one, and it is not padding: awaiting `process_frame` resumes this coroutine at a
# point in the frame that can precede the director's own `_process`, so one frame reads the state
# from BEFORE the swap -- measured, and it reads differently depending on whether a timer await came
# first, which is exactly the kind of intra-frame ordering a case must not depend on. Two frames
# guarantee a full reconcile pass either way.
func _hand_off() -> void:
	await game.end_turn()
	await await_idle_frame()
	await await_idle_frame()


# --- the rule ------------------------------------------------------------------------------------

func test_the_front_door_plays_the_title_track() -> void:
	assert_bool(game.mission_controller.mission_select_is_up()).override_failure_message(
		"fixture: the front door is not up, so this case is not asking its question").is_true()
	assert_int(_director().current_track()).override_failure_message(
		"The title screen should sound like the title screen.") \
		.is_equal(MusicDirector.Track.TITLE)


# ALSO the case that proves _process SWAPS rather than merely settling once: the director starts on
# the title track, so a reconcile that only ever ran at boot would pass every other case here.
func test_leaving_the_front_door_plays_the_battle_track() -> void:
	await _open_a_board()
	assert_bool(game.mission_controller.mission_select_is_up()).override_failure_message(
		"fixture: the door never closed").is_false()
	assert_int(_director().current_track()).is_equal(MusicDirector.Track.BATTLE)


func test_the_enemy_sides_turn_plays_the_enemy_track() -> void:
	await _open_a_board()
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	_spawn(Team.Faction.ENEMY, Vector2i(7, 0))
	await _hand_off()

	assert_int(game.turn_manager.active_faction()).override_failure_message(
		"fixture: the hand-off did not reach ENEMY, so the track says nothing") \
		.is_equal(Team.Faction.ENEMY)
	assert_int(_director().current_track()).override_failure_message(
		"The enemy's turn should sound like the enemy's turn.") \
		.is_equal(MusicDirector.Track.ENEMY)


func test_handing_back_to_the_player_returns_to_the_battle_track() -> void:
	await _open_a_board()
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	_spawn(Team.Faction.ENEMY, Vector2i(7, 0))
	await _hand_off()
	await _hand_off()

	assert_int(game.turn_manager.active_faction()).override_failure_message(
		"fixture: the cycle did not come back round to PLAYER").is_equal(Team.Faction.PLAYER)
	assert_int(_director().current_track()).is_equal(MusicDirector.Track.BATTLE)


# The case that separates SIDE from NOT-THE-PLAYER. An ALLY is not the player and is not an enemy
# either, so `f != PLAYER` and `Team.is_enemy(PLAYER, f)` disagree here and nowhere else on a
# two-faction board -- which is why a "non-ENEMY faction" case would have been blind to it.
func test_an_allied_factions_turn_keeps_the_battle_track() -> void:
	await _open_a_board()
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	_spawn(Team.Faction.ALLY, Vector2i(7, 0))
	await _hand_off()

	assert_int(game.turn_manager.active_faction()).override_failure_message(
		"fixture: the hand-off did not reach ALLY").is_equal(Team.Faction.ALLY)
	assert_int(_director().current_track()).override_failure_message(
		"An ally's turn is not the enemy approaching.").is_equal(MusicDirector.Track.BATTLE)


# --- what a swap does to a track already playing -------------------------------------------------

# BOTH columns of the table in one sequence, because they are two halves of one decision. Asserted
# as a PROPERTY either side of a wide gap -- well into the track versus back at the start -- never as
# a position, which is a wall-clock measurement the Dummy driver lags by its own mixing latency.
func test_battlefield_picks_up_where_it_left_off_and_the_enemy_track_starts_over() -> void:
	await _open_a_board()
	_spawn(Team.Faction.PLAYER, Vector2i(0, 0))
	_spawn(Team.Faction.ENEMY, Vector2i(7, 0))

	await _play_for(0.5)
	var battle_reached := _director().position_of(MusicDirector.Track.BATTLE)
	assert_float(battle_reached).override_failure_message(
		"fixture: the battle track never advanced, so neither half of this case can fail") \
		.is_greater(0.2)

	await _hand_off()                      # -> ENEMY, and Battlefield is remembered
	assert_int(game.turn_manager.active_faction()).override_failure_message(
		"fixture: hand-off 1 did not reach ENEMY, so neither half below is being asked") \
		.is_equal(Team.Faction.ENEMY)
	await _play_for(0.5)
	await _hand_off()                      # -> PLAYER, and Battlefield should resume
	assert_int(game.turn_manager.active_faction()).override_failure_message(
		"fixture: hand-off 2 did not come back to PLAYER") \
		.is_equal(Team.Faction.PLAYER)

	assert_float(_director().position_of(MusicDirector.Track.BATTLE)).override_failure_message(
		"Battlefield restarted instead of picking up; a short loop swapped every turn is then the " +
		"same first seconds all mission.").is_greater(0.2)

	await _hand_off()                      # -> ENEMY again, which should NOT resume
	assert_float(_director().position_of(MusicDirector.Track.ENEMY)).override_failure_message(
		"Enemy Approaching resumed; an approaching cue wants its own opening every time.") \
		.is_less(0.1)


func _play_for(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# --- the import ----------------------------------------------------------------------------------

# A track that does not loop plays once and leaves the rest of the mission silent, which reads as a
# bug in the swap rather than in an import setting. `loop` is not content the dev tunes -- it is a
# build fact about the file, and a mistyped [params] key is ignored in silence.
func test_every_track_is_imported_to_loop() -> void:
	var not_looping: Array[String] = []
	for track: MusicDirector.Track in MusicDirector.TRACKS:
		var stream: AudioStream = MusicDirector.TRACKS[track]["stream"]
		assert_object(stream).override_failure_message(
			"track %d has no stream at all" % track).is_not_null()
		var mp3 := stream as AudioStreamMP3
		if mp3 == null or not mp3.loop:
			not_looping.append(stream.resource_path.get_file())
	assert_array(not_looping).override_failure_message(
		"Tracks that stop at the end instead of looping: %s" % ", ".join(not_looping)).is_empty()

