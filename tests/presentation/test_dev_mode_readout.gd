# The game window says when dev mode is on.
#
# A WIRE suite, the shape of test_build_readout.gd next door and for the same reason: game.gd can
# emit dev_mode_changed perfectly and the badge can exist, while nothing joins the two. Delete the
# connect line in battle3d._ready and every other suite in the tree still passes -- #103 exactly.
#
# The REAL scene, so what is asserted is the node that ships: a Label authored into Battle3D.tscn
# under the UI CanvasLayer, which draws above the 2D game's container in every hosting view, so
# one node serves HD_2D and FLAT_2D alike (#292). Whether it READS as unmissable is the dev's, by
# playing; nothing here pins a colour, a size or an offset.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"

var _scene: Node3D
var _game: Node2D


func before_test() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var packed := load(SCENE_PATH) as PackedScene
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	_game = _scene.game


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


func test_the_badge_is_absent_until_dev_mode_is_turned_on() -> void:
	# Presence IS the signal (dev call), so "off" has to be genuinely nothing on screen.
	var badge: Label = _scene.get_node("UI/DevMode")
	assert_bool(badge.visible).is_false()

	_game.set_dev_mode(true)

	assert_bool(badge.visible).is_true()
	assert_str(badge.text).is_not_empty()


func test_turning_dev_mode_off_takes_the_badge_away() -> void:
	var badge: Label = _scene.get_node("UI/DevMode")
	_game.set_dev_mode(true)

	_game.set_dev_mode(false)

	assert_bool(badge.visible).is_false()


# The badge reads the INTENT, not game_state == DEV_MODE. The two split on purpose (game.gd's own
# note): game_state is where the board RESTS, so it leaves DEV_MODE the moment any mode is entered
# and a badge driven off it would blink out mid-interaction. Direct-set here deliberately -- the
# claim under test is that this write does NOT reach the badge.
func test_the_badge_follows_the_toggle_and_not_the_board_state() -> void:
	var badge: Label = _scene.get_node("UI/DevMode")
	_game.set_dev_mode(true)

	_game.game_state = _game.GameState.CHOOSING_MOVE

	assert_bool(badge.visible).is_true()


func test_the_badge_is_a_label_of_its_own_and_not_a_field_of_the_help_line() -> void:
	# Structural, and load-bearing for the same reason the checkout readout's twin case is: the
	# help line is rewritten wholesale in demo_mode and rebuilt on every binding change, so a
	# dev-mode word carried inside it is one edit away from vanishing again.
	var help: Label = _scene.get_node("UI/Help")
	var badge: Label = _scene.get_node("UI/DevMode")
	assert_object(badge).is_not_same(help)

	_game.set_dev_mode(true)

	assert_bool(help.visible).is_true()   # the help line is untouched by the badge's arrival
	assert_bool(badge.visible).is_true()
