# One Battle3D per SUITE instead of one per case (#622, leaves A and D), with the leak check that
# makes that safe wired in rather than optional.
#
# The four calls mirror gdUnit4's four hooks, and a converted suite is four one-liners:
#
#   var _board := SharedBoard.new(SCENE_PATH, PROLOG)
#   func before():      await _board.open(self)
#   func before_test(): await _board.reset(self)
#   func after_test():  await _board.check(self)   # resets, THEN diffs
#   func after():       _board.close()
#
# WHY THE CHECK IS NOT OPTIONAL. A leak observed by a LATER case is a flake -- it depends on what
# that case happens to look at, so it reproduces sometimes and points at the wrong test when it
# does. check() diffs the whole board against the baseline after EVERY case, so a leak fails at the
# case that caused it, every run, naming the field. Sharing without it would trade a slow suite for
# an unreliable one, which is the wrong trade; sharing WITH it is the trade actually on offer.
#
# FRESH MODE IS THE ORACLE AND THE ESCAPE HATCH (leaf D). Set IOSIS_FRESH_FIXTURE=1 and every suite
# using this rebuilds the scene per case exactly as before, at no loss but time. Two things that
# buys: a converted suite can always be compared against the behaviour it had before conversion
# (divergence between the modes IS a leak, caught deterministically rather than by luck), and if
# sharing ever proves unsound the fallback is an environment variable rather than a revert.
class_name SharedBoard
extends RefCounted

const FRESH_ENV := "IOSIS_FRESH_FIXTURE"

var scene: Node3D
var game: Node2D

var _scene_path: String
var _mission_path: String
var _prepare: Callable
var _pristine: ScenarioData
var _pristine_shot: CameraPose
var _baseline: Dictionary


func _init(scene_path: String, mission_path: String = "") -> void:
	_scene_path = scene_path
	_mission_path = mission_path


static func fresh_mode() -> bool:
	return OS.get_environment(FRESH_ENV) != ""


# --- the four hooks ------------------------------------------------------------------------------

# `prepare` is an optional recipe for a pristine state the scene does not come up in -- it runs
# after the build (and after the mission, if one was named) and BEFORE the baseline is captured, so
# whatever it does becomes the state every case starts from. Stored rather than called here, because
# fresh mode has to run it per case too.
#
# Its one shipped caller is "an empty board": six suites open with clear_board(), and the naive read
# of that -- the scene comes up empty anyway, so drop it -- is WRONG and was measured wrong. Emptying
# is not what those fixtures were buying. clear_board() emits board_loaded, which is what drives
# battle3d._on_board_loaded -> rebuild()/fit_camera()/pointer reset, and without that first load the
# 3D hover wire is never built: test_overlay_mirror's crown case fails, in BOTH modes, which is what
# proved it is a missing recipe rather than a leak. A suite that names a mission gets the same
# emission from load_mission and needs nothing.
func open(suite: GdUnitTestSuite, prepare := Callable()) -> void:
	_prepare = prepare
	if fresh_mode():
		return   # nothing is shared; reset() builds a scene of its own per case
	await _build(suite)
	# WARM-UP, then baseline. capture -> apply -> capture is not a fixed point on the FIRST cycle
	# (WeaponInstance.spaces is lazily grown rather than sized from its template, #624), so the
	# baseline is taken after one reset rather than before it. Without this every case would report
	# a leak that is really a representation change, and the check would be worthless on day one.
	_pristine = game.scenario_manager.capture_scenario("__shared_pristine")
	await _apply(suite)
	_pristine_shot = scene.capture_camera_start()
	_baseline = BoardFingerprint.take(scene, game.scenario_manager)


func reset(suite: GdUnitTestSuite) -> void:
	if fresh_mode():
		await _build(suite)
		return
	await _apply(suite)


# RESETS FIRST, then diffs -- the ordering is load-bearing and was wrong in the first draft.
#
# Diffing the board a case LEFT behind fails every case that legitimately loads a mission or moves a
# unit, which is most of them; that is the case doing its job, not leaking. What must be true is
# that the reset door can UNDO whatever the case did. So this resets and then asks whether the
# board came back -- anything still differing is something clear_board/apply_scenario cannot reach,
# which is exactly the leak the next case would inherit.
#
# Doing it here rather than in before_test is what attributes the leak correctly: after_test still
# belongs to the case that caused it, while before_test would name its innocent successor.
#
# Returns the leak list as well as asserting on it, so a suite that wants to inspect it can.
func check(suite: GdUnitTestSuite) -> PackedStringArray:
	if fresh_mode():
		# End dialog BEFORE the scene dies, exactly as the hand-written fixtures did. Dialogic's
		# layout is parented to the tree ROOT, so it outlives scene.free() and shows up as orphans
		# rather than as a failure -- 142 of them the first time this path ran, against 0 shared,
		# because the shared path ends dialog on every reset and this one had skipped it.
		await DialogFixtures.end_all_dialog(suite)
		_teardown()
		return PackedStringArray()
	await _apply(suite)
	var diff := BoardFingerprint.differences(_baseline,
			BoardFingerprint.take(scene, game.scenario_manager))
	suite.assert_array(diff).override_failure_message(
		("this case leaked state into the shared board. Each line is something the next case would "
		+ "have inherited:\n  %s\n"
		+ "Either undo it in the case, or -- if it belongs to the board -- make the reset door "
		+ "cover it rather than teaching the fingerprint to ignore it.") % "\n  ".join(diff)
	).is_empty()
	return diff


func close() -> void:
	if fresh_mode():
		return   # check() already freed each case's scene
	_teardown()


# --- internals -----------------------------------------------------------------------------------

func _build(suite: GdUnitTestSuite) -> void:
	# The project window size: headless defaults can be tiny, and several presentation reads
	# (picking, the PiP) are resolution-dependent.
	suite.get_tree().root.size = Vector2i(1280, 720)
	PlayerSettings.reset_for_test()   # also cleared per case by _apply; this is fresh mode's copy
	Experiments.reset_for_test()
	scene = (load(_scene_path) as PackedScene).instantiate() as Node3D
	scene.auto_play = false   # the board is loaded explicitly below, if at all
	suite.get_tree().root.add_child(scene)
	await suite.await_idle_frame()
	game = scene.game
	if _mission_path != "":
		scene.load_mission(_mission_path)
		await suite.await_idle_frame()
	if _prepare.is_valid():
		_prepare.call()
		await suite.await_idle_frame()


# The reset RECIPE. apply_scenario begins with clear_board(), so this is the game's own door rather
# than bespoke cleanup -- which is the point: every case run through it exercises the same reset a
# mission-to-mission transition will need (#70), instead of a fresh process hiding whether it works.
#
# Ending dialog is part of the recipe, not an afterthought: load_mission arms the #182 lesson and
# apply_scenario is the BOARD door, so without this the first case runs with a timeline live and
# every later one without.
func _apply(suite: GdUnitTestSuite) -> void:
	if _pristine != null:
		game.scenario_manager.apply_scenario(_pristine)
	_restore_tuning()
	# The two settings stores, for the same reason as the knobs and with a bug of their own to show
	# for it. Both keep a static _state that no scene owns, so the per-case reset_for_test() the
	# hand-written fixtures called is exactly what moved to once-per-suite when a suite converted --
	# and test_board_mirror's photosensitivity case had been relying on it. Clearing them here puts
	# that back where it belongs: the fixture, not thirteen before_test bodies.
	PlayerSettings.reset_for_test()
	Experiments.reset_for_test()
	_restore_session()
	await DialogFixtures.end_all_dialog(suite)
	await suite.await_idle_frame()


# apply_scenario restores the BOARD; a knob is a node property or a class value and it does not
# reach them. That mattered the moment a real suite was converted: test_board_mirror doubles
# BoardMirror.cover_scale to prove the knob reaches bumps already standing, and never puts it back --
# correct in a world where the node was rebuilt per case, a leak the moment one is shared.
#
# Restoring it here rather than editing the case is the deliberate choice: writing a knob in a test
# is a reasonable thing to do, and the fixture is what should make it safe. Only what MOVED is
# written, because write_static runs each knob's re-apply sweep and doing 98 of those per case would
# hand back much of what sharing saves.
func _restore_tuning() -> void:
	if _baseline.is_empty():
		return   # open() has not taken the baseline yet; the first _apply IS the warm-up
	var nodes: Array = _baseline.get("node_knobs", [])
	var table := BoardFingerprint.node_knob_table()
	for i in mini(table.size(), nodes.size()):
		if not LookKnobs.same_value(LookKnobs.read(scene, table[i]), nodes[i]):
			LookKnobs.write(scene, table[i], nodes[i])
	var classes: Array = _baseline.get("class_knobs", [])
	for i in mini(GameKnobs.CLASS_KNOBS.size(), classes.size()):
		if typeof(classes[i]) == TYPE_NIL:
			continue   # a knob with no READ arm; test_game_knobs owns that finding, never write null
		if not LookKnobs.same_value(GameKnobs.read_class(scene, GameKnobs.CLASS_KNOBS[i]), classes[i]):
			GameKnobs.write_class(scene, GameKnobs.CLASS_KNOBS[i], classes[i])


# The SESSION state a case can move: the hosting view, dev mode, and where the pointer is.
# None of it is board content, so apply_scenario has no reach into any of it -- and all of it
# decides what the next case sees. Put back the same way a knob is.
#
# The hosting view first. It is not board state and apply_scenario has
# no reach into it, but it decides WHO OWNS BOARD INPUT: FLAT_2D stands the 3D picker down and
# uninstalls the pointer source HoverPresenter reads, so a case that swaps view and does not swap
# back leaves every later case hovering off the real mouse. test_overlay_mirror does exactly that
# (its FLAT_2D case is asserting that the 2D layer comes back), and the two crown cases after it
# went dark -- a hover that drew nothing, with every individual piece behaving correctly.
#
# Restored through _apply_hosting(), the same door the game's own F4 uses, because assigning the
# property alone changes nothing: the ownership swap is what that call does.
func _restore_session() -> void:
	if _baseline.is_empty() or scene == null:
		return
	var want: Variant = _baseline.get("view")
	if want != null and scene.get("view") != want:
		scene.set("view", want)
		scene._apply_hosting()
	# Dev mode is the same shape one level in, and it is what test_input_bridge's brush cases move.
	# Through set_dev_mode(), not the flag, because the flag alone leaves game_state resting on the
	# old base -- and it goes AFTER apply_scenario rather than before, since set_dev_mode ends in
	# exit_current_mode() and that is what settles game_state onto the right base.
	var dev: Variant = _baseline.get("dev_mode")
	if dev != null and game.get("dev_mode_enabled") != dev:
		game.set_dev_mode(dev)
	# WHERE THE POINTER IS, which is stored twice and reset once. battle3d._pointer_cell is put back
	# to NO_CELL by _on_board_loaded, and HoverPresenter.last_hovered_cell -- its own copy, kept so
	# the poll only works on a CHANGE -- is not, so after a board reload the two disagree. In the
	# game that costs one spurious hover event and nothing notices. Under a shared fixture it is
	# fatal in the other direction: a case that points at the cell the previous case pointed at sees
	# NO CHANGE, so the hover never fires and the crown, the card and the snap simply never happen.
	#
	# Both are zeroed here, and it must be BOTH: setting only the presenter's copy leaves the two
	# disagreeing the other way, and the next frame fires a hover the case never asked for. That is
	# a real asymmetry in the production reset rather than a fixture quirk -- filed, not fixed here,
	# because a board reload is not a mouse move and which of the two should own the answer is a
	# design call.
	if scene.get("_pointer_cell") != null:
		scene.set("_pointer_cell", BoardSpace.NO_CELL)
	var presenter: Variant = game.get("hover_presenter")
	if presenter != null:
		presenter.last_hovered_cell = GridUtils.NO_CELL
	# THE SHOT. board_loaded already calls fit_camera, and that is not enough on purpose: with no
	# authored start it falls through to frame(), which "deliberately never touches yaw" (#234), so
	# a case that orbits the rig leaves the next one looking from somewhere else. pose() is the door
	# that does adopt all three -- the same one an authored camera_start goes through -- and it sets
	# the target yaw as well as the live one, without which the rig eases straight back.
	if _pristine_shot != null:
		var rig: CameraRig3D = scene.get_node_or_null("CameraRig")
		if rig != null:
			rig.pose(_pristine_shot.aim, _pristine_shot.yaw_degrees, _pristine_shot.distance,
					scene._board_volume())


func _teardown() -> void:
	if scene == null:
		return
	BoardSpace.clear_staging()
	scene.get_parent().remove_child(scene)
	scene.free()
	scene = null
	game = null
