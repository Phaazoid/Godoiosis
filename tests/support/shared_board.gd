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
var _pristine: ScenarioData
var _baseline: Dictionary


func _init(scene_path: String, mission_path: String = "") -> void:
	_scene_path = scene_path
	_mission_path = mission_path


static func fresh_mode() -> bool:
	return OS.get_environment(FRESH_ENV) != ""


# --- the four hooks ------------------------------------------------------------------------------

func open(suite: GdUnitTestSuite) -> void:
	if fresh_mode():
		return   # nothing is shared; reset() builds a scene of its own per case
	await _build(suite)
	# WARM-UP, then baseline. capture -> apply -> capture is not a fixed point on the FIRST cycle
	# (WeaponInstance.spaces is lazily grown rather than sized from its template, #624), so the
	# baseline is taken after one reset rather than before it. Without this every case would report
	# a leak that is really a representation change, and the check would be worthless on day one.
	_pristine = game.scenario_manager.capture_scenario("__shared_pristine")
	await _apply(suite)
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
	PlayerSettings.reset_for_test()
	scene = (load(_scene_path) as PackedScene).instantiate() as Node3D
	scene.auto_play = false   # the board is loaded explicitly below, if at all
	suite.get_tree().root.add_child(scene)
	await suite.await_idle_frame()
	game = scene.game
	if _mission_path != "":
		scene.load_mission(_mission_path)
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
	await DialogFixtures.end_all_dialog(suite)
	await suite.await_idle_frame()


func _teardown() -> void:
	if scene == null:
		return
	BoardSpace.clear_staging()
	scene.get_parent().remove_child(scene)
	scene.free()
	scene = null
	game = null
