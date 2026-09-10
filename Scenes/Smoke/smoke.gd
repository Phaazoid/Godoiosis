extends Node
class_name ExportSmoke

# The export smoke DRIVER (#868) -- it runs INSIDE a packed build and makes that build do the one
# thing a plain boot never does: load every authored mission and check units reached the board.
#
# WHY THIS EXISTS AT ALL. Three export-only breaks shipped in the three weeks to 2026-09-09, and
# the suite is structurally blind to all of them because CI runs from SOURCE, where `addons/` is
# present and `Foo.tres` is a real file. The untested property is "the artifact we ship works",
# and only the artifact can answer it.
#
# WHY IT LOADS A MISSION rather than just booting. Measured on the #867 build: a boot that stops
# at the title screen exits 0 with a two-line log and catches NOTHING, because nothing on the
# title screen loads a mission. The same pack, driven through begin_mission, reports 0 units and
# exits 1. A boot-and-grep smoke test would have missed the bug that cost the most time that day.
#
# WHY IT SHIPS. This scene is in the released pack rather than a CI-only variant, and that is
# deliberate: a pack built with different filters is not the pack the player gets, so a smoke test
# over it would prove something about a build nobody runs. It costs ~1KB, has no entry point from
# any menu, input map or autoload, and runs only when named explicitly on the command line.
#
# WHY `armed = false`. That is begin_mission's existing watch-only boot (#375) -- "nobody there to
# answer it" -- so a roster mission's deployment screen never opens. Headless, an opened screen
# waits for input that cannot come, which is the one way this driver could hang forever.
#
# TELEMETRY WRITES NOTHING HERE, by construction rather than by a flag: TelemetryStore's
# _static_init disables persistence whenever DisplayServer is headless, so these runs never reach
# disk and can never be uploaded as if a stranger had played them.

# Per-mission budget. A mission that neither loads nor fails inside this many frames is a FAILURE,
# not a wait -- the whole point is that a headless hang must redden CI rather than run out its job.
const LOAD_TIMEOUT_FRAMES := 600

# The last line is the CONTRACT with tests/export/test_export_smoke.gd, which requires one of these
# to be present. That is what makes `--quit-after` a safe backstop: a driver that dies or hangs
# prints neither, so the run cannot pass by exiting quietly.
const OK_LINE := "SMOKE OK"
const FAIL_LINE := "SMOKE FAIL"

var _loaded := false


func _ready() -> void:
	# Deferred: add_child during another node's setup fails outright ("Parent node is busy setting
	# up children") and takes the process down a frame later.
	var host: Node = (load("res://Scenes/Battle3D/Battle3D.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(host)
	await get_tree().process_frame
	await get_tree().process_frame

	var game: Node = host.find_child("Game", true, false)
	if game == null:
		_fail("the Game node is missing -- Battle3D did not build")
		return

	var missions: Array[String] = game.scenario_manager.get_missions()
	# The vacuous-pass guard every scan test in this project carries: without it a broken scan
	# reads as a clean smoke, which is the failure this whole job exists to stop being silent.
	if missions.is_empty():
		_fail("no missions in the pack -- the scan found nothing to prove")
		return

	game.scenario_manager.board_loaded.connect(func(): _loaded = true)

	for path: String in missions:
		if not await _mission_loads(game, path):
			return

	print("%s -- %d mission(s)" % [OK_LINE, missions.size()])
	get_tree().quit(0)


# One mission, start to units-on-board. False means the failure has already been reported.
func _mission_loads(game: Node, path: String) -> bool:
	_loaded = false
	game.mission_controller.begin_mission(path, false)

	# Signal-driven with a frame BUDGET, not a frame count: the load is synchronous today, so this
	# usually falls through on the first check, and it stays correct if that ever changes.
	var waited := 0
	while not _loaded and waited < LOAD_TIMEOUT_FRAMES:
		await get_tree().process_frame
		waited += 1
	if not _loaded:
		_fail("%s never finished loading (%d frames)" % [path, LOAD_TIMEOUT_FRAMES])
		return false

	var units: int = (game._all_units() as Array).size()
	if units <= 0:
		_fail("%s loaded no units -- authored content did not reach the board" % path)
		return false
	if game.scenario_manager.last_loaded_path != path:
		_fail("%s reports last_loaded_path '%s'" % [path, game.scenario_manager.last_loaded_path])
		return false

	print("  smoke: %s -> %d units" % [path, units])
	return true


func _fail(reason: String) -> void:
	printerr("%s: %s" % [FAIL_LINE, reason])
	print("%s: %s" % [FAIL_LINE, reason])   # stdout too: the runner reads one stream
	get_tree().quit(1)
