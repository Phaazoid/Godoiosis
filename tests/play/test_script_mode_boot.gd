# The Play API's bridge runs in SCRIPT mode (`-s res://play/play_bridge.gd`), and script mode is a
# different compile than every suite here gets: an autoload name does not resolve in it. From #1034
# (2026-09-27) until #46 fixed it, ModalLock named the Dialogic autoload, the whole headless chain
# failed its first compile in script mode, AIArchetype's static registry was built during that
# failure and stayed empty -- and every bridge-driven enemy turn did nothing, with a green suite,
# because gdUnit runs everything as a scene. This boots the real thing in a child process.
extends GdUnitTestSuite

const PROBE := "res://tests/support/script_mode_probe.gd"


func test_the_headless_chain_compiles_in_script_mode() -> void:
	var out: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", PROBE])
	OS.execute(OS.get_executable_path(), args, out, true)
	var text := "\n".join(out)
	assert_str(text).override_failure_message(
		"script mode did not build the AI registry -- a script in the headless chain names an autoload, "
		+ "or failed to compile some other way:\n%s" % text).contains("SCRIPT MODE PROBE: OK")
	assert_str(text).override_failure_message(
		"script mode boots with errors, which is how the last one hid:\n%s" % text).not_contains("SCRIPT ERROR")
