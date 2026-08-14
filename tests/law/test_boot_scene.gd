# The boot scene is a LAW here, not a preference: the game ships booting into the 3D view
# (#176 stage 4d, dev ruling 2026-08-14).
#
# WHY THIS EXISTS: nothing else in the suite exercises run/main_scene. Every test
# instantiates its scenes explicitly, so 1415 green cases were structurally blind to it --
# and the setting was SILENTLY REVERTED by a merge-conflict resolution the same day it
# landed. config/version sits on the adjacent line in [application], so resolving a version
# collision dragged this one back with it; everything merged green and the game quietly
# booted into 2D again.
extends GdUnitTestSuite

const BOOT_SCENE := "res://Scenes/Battle3D/Battle3D.tscn"


func test_the_game_boots_into_the_3d_view() -> void:
	var setting := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	assert_str(setting).override_failure_message("run/main_scene is unset").is_not_empty()

	# Compare the RESOLVED path, never the literal: Godot rewrites res:// paths to uid://
	# whenever the project is saved in the editor, and the dev's live session does that
	# routinely. Pinning the spelling would red on a no-op resave.
	var resolved := setting
	if setting.begins_with("uid://"):
		resolved = ResourceUID.get_id_path(ResourceUID.text_to_id(setting))
	assert_str(resolved).override_failure_message(
			"run/main_scene resolves to '%s' — the game no longer boots into the 3D view" % resolved
			).is_equal(BOOT_SCENE)


func test_the_boot_scene_exists_and_loads() -> void:
	# Guards the constant itself: a rename would otherwise red the case above with a
	# misleading "no longer boots into 3D" when the truth is "that file moved".
	assert_bool(ResourceLoader.exists(BOOT_SCENE)).override_failure_message(
			"%s does not exist — update BOOT_SCENE, it moved" % BOOT_SCENE).is_true()
	var packed := load(BOOT_SCENE) as PackedScene
	assert_object(packed).is_not_null()
