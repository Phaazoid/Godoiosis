# Proves BoardFingerprint can actually SEE a leak (#622, leaf B), and — the case that matters most —
# that apply_scenario() genuinely returns a mutated board to its captured state.
#
# That last claim is the whole premise of sharing one Battle3D across a suite instead of rebuilding
# it per case (~58% of CI, #619). If the reset door does not restore, sharing is unsafe and the
# right answer is to keep paying for a fresh scene. So this suite is the thing that decides it, and
# a red here is a finding rather than a chore.
#
# It lives in tests/presentation because it needs the real host, which is precisely the folder the
# work is meant to speed up. That is the correct place for it even so: the witness has to observe
# the same scene the shared fixture would share.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")
const PROLOG := "res://Scenarios/missions/Prolog.tres"

var _scene: Node3D
var _game: Node2D


func before_test() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	PlayerSettings.reset_for_test()
	_scene = SCENE.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_game = _scene.game
	_scene.load_mission(PROLOG)
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	BoardSpace.clear_staging()
	get_tree().root.remove_child(_scene)
	_scene.free()


func _take() -> Dictionary:
	return BoardFingerprint.take(_scene, _game.scenario_manager)


# ==============================================================================
#  No false positives — the property everything else rests on
# ==============================================================================

func test_two_readings_of_an_untouched_board_are_identical() -> void:
	# If this is ever flaky the whole approach is dead, because every case would report a leak it
	# did not cause. It is first for that reason.
	var before := _take()
	await await_idle_frame()
	var after := _take()

	var diff := BoardFingerprint.differences(before, after)
	assert_array(diff).override_failure_message(
		"an untouched board reported movement: %s" % ", ".join(diff)).is_empty()


# ==============================================================================
#  It sees each kind of leak the taxonomy names (#622)
# ==============================================================================

func test_it_sees_a_board_mutation() -> void:
	var before := _take()
	var units: Array[Unit] = []
	for child in _game.units_root.get_children():
		if child is Unit:
			units.append(child as Unit)
	assert_int(units.size()).override_failure_message("Prolog spawned no units").is_greater(0)
	units[0].set_current_hp(units[0].get_current_hp() - 1)

	var diff := BoardFingerprint.differences(before, _take())
	assert_array(diff).override_failure_message("a damaged unit went unnoticed").is_not_empty()


func test_it_sees_a_tuning_static_left_moved() -> void:
	var was := OverlayManager.SQUAD_RING_ALPHA
	var before := _take()
	OverlayManager.SQUAD_RING_ALPHA = was * 0.5 + 0.1
	var diff := BoardFingerprint.differences(before, _take())
	OverlayManager.SQUAD_RING_ALPHA = was

	assert_str(", ".join(diff)).override_failure_message(
		"a moved class knob went unnoticed").contains("SQUAD_RING_ALPHA")


func test_it_sees_a_player_setting_left_flipped() -> void:
	# The leak that shipped: test_board_mirror turns PHOTOSENSITIVITY on to prove the fire holds
	# still, and never turns it off. Harmless while every before_test called reset_for_test(), a
	# real leak the moment that reset became once-per-suite -- and invisible, because nothing here
	# sampled the store. PlayerSettings._state is a static; no scene owns it.
	var was := PlayerSettings.is_on(PlayerSettings.Setting.PHOTOSENSITIVITY)
	var before := _take()
	PlayerSettings.set_on(PlayerSettings.Setting.PHOTOSENSITIVITY, not was)
	var diff := BoardFingerprint.differences(before, _take())
	PlayerSettings.set_on(PlayerSettings.Setting.PHOTOSENSITIVITY, was)

	assert_str(", ".join(diff)).override_failure_message(
		"a flipped player setting went unnoticed").contains("PHOTOSENSITIVITY")


func test_it_sees_an_experiment_flag_left_on() -> void:
	# Experiments._state has the identical shape and the identical exposure (test_staging sets
	# DIORAMA_BYSTANDERS). Two stores, one rule -- both derived from their own DEFS, so a flag added
	# later is covered with no edit to the fingerprint.
	var flag: Experiments.Flag = Experiments.DEFS.keys()[0]
	var was := Experiments.is_on(flag)
	var before := _take()
	Experiments.set_on(flag, not was)
	var diff := BoardFingerprint.differences(before, _take())
	Experiments.set_on(flag, was)

	assert_str(", ".join(diff)).override_failure_message(
		"a flipped experiment flag went unnoticed").contains(str(Experiments.Flag.keys()[flag]))


func test_it_sees_the_hosting_view_left_swapped() -> void:
	# Not board state and not a knob -- the third kind: who owns board INPUT. FLAT_2D stands the 3D
	# picker down and uninstalls the pointer source, so a case that swaps and does not swap back
	# leaves every later case hovering off the real mouse. Found by conversion, not by reasoning:
	# test_overlay_mirror does exactly this, and the two crown cases after it drew nothing.
	var was: Variant = _scene.view
	var before := _take()
	_scene.view = _scene.View.FLAT_2D if was != _scene.View.FLAT_2D else _scene.View.HD_2D
	var diff := BoardFingerprint.differences(before, _take())
	_scene.view = was

	assert_str(", ".join(diff)).override_failure_message(
		"a swapped hosting view went unnoticed").contains("hosting view")


func test_it_sees_staging_left_lifted() -> void:
	# The one piece of board-scoped state that lives in a static (#622); clear_board clears it, and
	# this is what would catch the day it stops.
	var before := _take()
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	BoardSpace.stage(cells, Vector3(0, 40, 0))

	var diff := BoardFingerprint.differences(before, _take())
	BoardSpace.clear_staging()

	assert_str(", ".join(diff)).override_failure_message(
		"a lifted tear-out went unnoticed").contains("staging")


# ==============================================================================
#  The claim leaf A rests on: the reset door really does restore
# ==============================================================================

func test_the_reset_recipe_returns_a_mutated_board_to_its_baseline() -> void:
	# The RECIPE, not apply_scenario alone -- this is what a shared fixture would run per case, and
	# the two extra steps are both there for a measured reason.
	#
	# WARM-UP. WeaponInstance.spaces is lazily grown (`while spaces.size() <= index`) rather than
	# sized from the template, so a freshly made instance holds [] and a loaded one holds [[],[],[]].
	# Both mean "no mods fitted", but it makes capture -> apply -> capture not a fixed point on the
	# FIRST cycle only. Applying once before taking the baseline lands on the fixed point; the
	# underlying churn (an @export whose written form depends on whether anything touched it) is a
	# save-path issue in its own right and is filed separately, not papered over here.
	#
	# DIALOG. load_mission arms the #182 lesson; apply_scenario is the BOARD door and does not
	# re-arm it, so case 1 would run with a timeline live and every later case without. Ending it is
	# part of the reset rather than something the fingerprint should be taught to ignore.
	var pristine: ScenarioData = _game.scenario_manager.capture_scenario("__pristine")
	await _reset_to(pristine)
	var baseline := _take()

	var units: Array[Unit] = []
	for child in _game.units_root.get_children():
		if child is Unit:
			units.append(child as Unit)
	assert_int(units.size()).override_failure_message("Prolog spawned no units").is_greater(1)
	units[0].set_current_hp(maxi(1, units[0].get_current_hp() - 3))
	units[1].movement.set_cell(units[1].movement.cell + Vector2i(1, 0))
	assert_array(BoardFingerprint.differences(baseline, _take())).override_failure_message(
		"the fixture failed to dirty the board, so the restore below proves nothing").is_not_empty()

	await _reset_to(pristine)

	var diff := BoardFingerprint.differences(baseline, _take())
	assert_array(diff).override_failure_message(
		("the reset recipe did NOT restore the baseline. Each line is something a shared fixture "
		+ "would leak between cases:\n  %s") % "\n  ".join(diff)).is_empty()


func _reset_to(pristine: ScenarioData) -> void:
	_game.scenario_manager.apply_scenario(pristine)
	await DialogFixtures.end_all_dialog(self)
	await await_idle_frame()
