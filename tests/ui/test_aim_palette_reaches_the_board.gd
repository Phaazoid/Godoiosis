# THE WIRE for #422's palette: the two aim layers must wear the player's palette from the moment
# the board is built, not from the first time an attack is aimed.
#
# Its own suite, and its own fixture, because the palette has to be picked BEFORE the scene is
# instantiated -- `_ready` is what paints these two layers, so a case that sets the setting
# afterwards is asking about a frame that has already gone. tests/ui/test_aim_palette.gd is the pure
# static half and stays that way.
#
# Why it is worth a scene build. `set_aim_colors` repaints on entering an aim and on leaving one
# (game.gd's exit_current_mode), so before the player has EVER aimed an attack these layers hold
# whatever `_ready` gave them -- and the HOVER layer is shared with PICKING_TARGET, so a rescue or a
# squad-up pick on turn one is drawn in it. OverlayMirror polls that same modulate into the 3D AIM
# layer every frame, so a raw read at setup is wrong in both stacks at once.
#
# It found a real gap rather than guarding a hypothetical: with `_ready` reverted to reading the
# statics directly, test_aim_palette, test_watch_aim_reads_as_a_watch and
# test_attack_targeting_visuals were 33 cases green between them. Both ends were correct and
# nothing connected them -- #103's shape.
#
# Fixture is #114's -- the instanced root MUST be named "Main" under /root.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const PALETTE := PlayerSettings.Setting.AIM_PALETTE

var _main: Node
var game: Node2D

# The palette is chosen FIRST, then the board is built under it. That order is the whole fixture.
func before_test() -> void:
	PlayerSettings.reset_for_test()
	PlayerSettings.set_choice(PALETTE, PlayerSettings.AimPalette.HIGH_CONTRAST)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	await await_idle_frame()

func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()
	PlayerSettings.reset_for_test()


func test_a_board_built_under_a_palette_is_already_wearing_it() -> void:
	# DERIVED from the accessors, never a literal: the dev tunes all four authored colours and may
	# retune the palettes, and neither must ever turn this red. What is pinned is that the layer and
	# the accessor AGREE -- and that the layer is not sitting on the authored colour instead, which
	# is the whole failure mode and the half a plain equality check cannot see.
	var overlays: OverlayManager = game.overlay_manager
	assert_that(overlays.hover_overlay.modulate).override_failure_message(
			"the aim footprint was painted at setup without asking the palette"
			).is_equal(OverlayManager.aim_fill_color())
	assert_that(overlays.hover_overlay.modulate).override_failure_message(
			"the aim footprint is on the AUTHORED colour -- _ready read the static directly"
			).is_not_equal(OverlayManager.HOVER_MODULATE)

	assert_that(overlays.attack_overlay.modulate).override_failure_message(
			"the reach fill was painted at setup without asking the palette"
			).is_equal(OverlayManager.attack_reach_color(null))
	assert_that(overlays.attack_overlay.modulate).override_failure_message(
			"the reach fill is on the AUTHORED colour -- _ready read the static directly"
			).is_not_equal(OverlayManager.ATTACK_MODULATE)
