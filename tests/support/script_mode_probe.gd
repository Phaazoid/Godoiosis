# Boots in SCRIPT mode (-s), the way play/play_bridge.gd runs, and says whether the headless chain
# compiled there. An autoload NAME does not resolve in script mode, so one script in the chain naming
# one fails to compile, and a static initialiser that ran during the failure -- AIArchetype's registry
# -- stays empty for the life of the process: the bridge's AI silently never acts (#46). Driven by
# tests/play/test_script_mode_boot.gd, which reads the one line printed here.
extends SceneTree

func _initialize() -> void:
	var ok := load("res://play/play_bridge.gd") != null
	for t: AIArchetype.Type in [AIArchetype.Type.RUSHDOWN, AIArchetype.Type.HOLD, AIArchetype.Type.SENTRY]:
		if not AIArchetype.resolve(t).is_valid():
			ok = false
	print("SCRIPT MODE PROBE: %s" % ("OK" if ok else "FAIL"))
	quit()
