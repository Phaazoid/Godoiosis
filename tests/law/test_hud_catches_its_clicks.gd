# A CLICK ON THE HUD NEVER REACHES THE BOARD (#929 follow-up), on the real game scene.
#
# The 3D view picks board cells in battle3d._unhandled_input, which a click any Control CATCHES never
# reaches ("UI consumed the event before it reached here"); the flat view's game._unhandled_input is
# the same. So the one thing that keeps a click on the HUD off the board is that something under the
# pointer catches the mouse -- and nothing checked that anything did. The aim strip shipped with every
# node set to IGNORE, and a click on its arrow aimed an attack at the cell underneath. What a real
# click does is test_hud_clicks_stay_off_the_board's to show, on the 3D scene.
#
# THE RULE, on Godot's own picking: a HUD control smaller than the screen must be caught -- it, or an
# ancestor up to the surface's full-screen host, has MOUSE_FILTER_STOP. A PASS that nobody handles
# falls through to the board just as IGNORE does, so only STOP counts. Full-screen hosts (a surface's
# root anchored to the whole screen, the shape PreMissionBar and the strip hang their boxes off) are
# exempt by shape: they must let the board through everywhere their boxes are not.
#
# EVERY CanvasLayer in the game's viewport, not only the HUD's: a surface built on a layer of its own
# (the turn banner is one) is a HUD surface all the same. STRUCTURAL, not a click sweep: every control
# is judged, visible or not, so a surface hidden at rest is judged too. A surface this fixture never
# builds (a card, the update banner, the dialogue box) is not judged here.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

# SEE-THROUGH ON PURPOSE, by node name: a click through one of these lands on the board, and that is
# the design. Each says why. A subtree named here is not walked.
const SEE_THROUGH := {
	"PlaybackHint": "shown only while playback owns the board (PlaybackControl.hint_shown), and "
			+ "battle3d and game refuse every click then",
}

var _main: Node
var game: Node2D


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
	for x in range(6):
		for y in range(4):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	# Built out: the objectives panel draws its rows only once a mission declares something.
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	game.mission_controller.set_objectives(objectives)
	game.refresh_mission_status()
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _walked() -> Array[Control]:
	var out: Array[Control] = []
	for layer in game.get_viewport().find_children("*", "CanvasLayer", true, false):
		for child in layer.get_children():
			_collect(child, out)
	return out


func _collect(node: Node, out: Array[Control]) -> void:
	if SEE_THROUGH.has(String(node.name)):
		return
	var control := node as Control
	if control != null:
		out.append(control)
	for child in node.get_children():
		_collect(child, out)


# A surface's full-screen root: the host its boxes hang off.
static func _is_host(control: Control) -> bool:
	return not (control.get_parent() is Control) \
		and is_equal_approx(control.anchor_left, 0.0) and is_equal_approx(control.anchor_top, 0.0) \
		and is_equal_approx(control.anchor_right, 1.0) and is_equal_approx(control.anchor_bottom, 1.0)


# Whether a click landing on `control` is caught before the board sees it.
static func _caught(control: Control) -> bool:
	var node: Node = control
	while node is Control:
		var at := node as Control
		if at.mouse_filter == Control.MOUSE_FILTER_STOP:
			return true
		if _is_host(at):
			return false
		node = node.get_parent()
	return false


func _offenders() -> Array[String]:
	var view := game.get_viewport()
	var out: Array[String] = []
	for control in _walked():
		if not _is_host(control) and not _caught(control):
			out.append(str(view.get_path_to(control)))
	return out


func test_every_hud_control_a_click_can_land_on_catches_it() -> void:
	var offenders := _offenders()
	assert_array(offenders).override_failure_message(
			"a click on these reaches the board beneath them -- give the box MOUSE_FILTER_STOP, or "
			+ "name the surface in SEE_THROUGH with why:\n  " + "\n  ".join(offenders)).is_empty()


# The walk is not vacuous: it reaches the surfaces this law exists for, the turn banner's own layer
# included.
func test_the_walk_reaches_the_aim_strip_the_objectives_and_the_turn_banner() -> void:
	var names: Array[String] = []
	for control in _walked():
		names.append(String(control.name))
	assert_array(names).contains(["AimStrip", "ObjectivePanel", "TurnLabel"])


# And it sees a see-through box when there is one: a stand-in surface built the way the strip was,
# on a layer nothing else uses -- a future menu's shape.
func test_the_law_sees_a_box_that_lets_clicks_through() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ProbeLayer"
	var host := Control.new()
	host.name = "ProbeHost"
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := PanelContainer.new()
	box.name = "ProbeBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(box)
	layer.add_child(host)
	game.add_child(layer)

	assert_array(_offenders()).contains(["Game/ProbeLayer/ProbeHost/ProbeBox"])
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	assert_array(_offenders()).not_contains(["Game/ProbeLayer/ProbeHost/ProbeBox"])
	layer.free()
