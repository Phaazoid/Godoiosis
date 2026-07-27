extends SceneTree

# Headless profiler for the Group Move click. See docs/performance.md for the recorded numbers,
# the invariants this protects, and why the obvious suspect was the wrong one.
#
#   godot --headless --path <repo> --script res://tools/profile_group_move.gd
#
# Lives outside tests/ on purpose: it extends SceneTree, not GdUnitTestSuite, and the suite runner
# scans res://tests recursively.
#
# Copy this as the starting point for profiling anything else. The reusable parts are the shape —
# boot the REAL Main.tscn, load a REAL scenario, wrap the REAL call in Time.get_ticks_usec() — and
# _plan_signature(), which is how you prove an optimisation didn't change behaviour. Capture a
# signature BEFORE you change anything; "faster" is only half the claim.

const SCENARIO := "res://Scenarios/Castle Assault.tres"

# Recorded 2026-07-26 on the pre-optimisation code, as the equivalence baseline. Regenerate (and
# note why) if the scenario's units or terrain ever change.
const GROUND_TRUTH := [
	"Soldier18|0|(4, 5)|true", "Soldier15|0|(4, 4)|true", "Soldier16|0|(3, 5)|true",
	"Soldier17|0|(5, 4)|true", "Soldier19|0|(3, 6)|true",
]

func _init() -> void:
	_run.call_deferred()

func _stamp(label: String, usec: int) -> void:
	print("  %-42s %7.2f ms" % [label, usec / 1000.0])

# Everything the player can observe about the queued plan, in queue order.
func _plan_signature(squad: Squad) -> Array:
	var sig: Array = []
	for a in squad.action_queue:
		var dest := str(a.get_destination()) if a.action_type == BaseAction.ActionType.MOVE else "-"
		sig.append("%s|%d|%s|%s" % [a.actor.get_unit_name(), a.action_type, dest, str(a.is_valid)])
	return sig

func _run() -> void:
	var main: Node = load("res://Scenes/Main.tscn").instantiate()
	root.add_child(main)
	for i in range(5):
		await process_frame

	var game: Node2D = main.get_node("GameContainer/GameView/Game")
	game.get_node("ScenarioManager").load_scenario(SCENARIO)
	for i in range(5):
		await process_frame

	var sm = game.squad_manager
	var used: Rect2i = game.grid.get_used_rect()
	print("scenario  = ", SCENARIO)
	print("board     = ", used, "  (", used.size.x * used.size.y, " cells)")
	print("units     = ", game.units_root.get_child_count())

	# Biggest player squad — the one a group move actually stresses.
	var squad: Squad = null
	for s in sm.squads:
		if s.leader.get_faction() == Team.Faction.PLAYER:
			if squad == null or s.get_members().size() > squad.get_members().size():
				squad = s
	if squad == null:
		print("ABORT: no player squad in this scenario")
		quit(1)
		return

	var leader: Unit = squad.get_leader()
	var board: BoardContext = game._board()
	var reach: Dictionary = RulesService.compute_move_range(leader, board)
	var dest: Vector2i = leader.movement.cell
	for c in reach.reachable.keys():
		if c != leader.movement.cell:
			dest = c        # farthest-listed reachable cell — a worst-case-ish destination
	print("squad     = ", squad.get_members().size(), " members")
	print("destination = ", dest)

	print("\nPRIMITIVES (one call each)")
	var t := Time.get_ticks_usec()
	game._board()
	_stamp("_board() construction", Time.get_ticks_usec() - t)

	t = Time.get_ticks_usec()
	RulesService.compute_move_range(leader, board)
	_stamp("compute_move_range (1 unit)", Time.get_ticks_usec() - t)

	t = Time.get_ticks_usec()
	GroupMoveSolver.plan(squad, dest, board)
	_stamp("GroupMoveSolver.plan (whole squad)", Time.get_ticks_usec() - t)

	t = Time.get_ticks_usec()
	sm.resolve_plan(squad, board)
	_stamp("resolve_plan", Time.get_ticks_usec() - t)

	t = Time.get_ticks_usec()
	game.refresh_action_queue(squad)
	_stamp("refresh_action_queue", Time.get_ticks_usec() - t)

	print("\nTHE ACTUAL CLICK")
	game.game_state = game.GameState.CHOOSING_GROUP_MOVE
	game.last_clicked_cell = leader.movement.cell
	t = Time.get_ticks_usec()
	game._click_choosing_group_move(dest)
	_stamp("_click_choosing_group_move TOTAL", Time.get_ticks_usec() - t)
	print("  queued actions = ", squad.action_queue.size())

	var sig := _plan_signature(squad)
	print("\nEQUIVALENCE vs the recorded baseline")
	print("  now      = ", sig)
	print("  baseline = ", GROUND_TRUTH)
	print("  IDENTICAL -> ", sig == GROUND_TRUTH)
	print("  (a mismatch means either a real behaviour change, or the scenario moved — check which)")

	print("\nPROFILE DONE")
	quit(0)
