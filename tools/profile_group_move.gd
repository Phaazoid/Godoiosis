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

	# The overlay/click feasibility sweep (2026-08-04). Cost is per SQUAD, not per destination —
	# that is the whole reason it is not a plan() per cell.
	var all_destinations: Array = game.get_move_range(reach, leader)
	t = Time.get_ticks_usec()
	GroupMoveSolver.followable_destinations(squad, board, all_destinations)
	_stamp("followable_destinations (%d cells)" % all_destinations.size(), Time.get_ticks_usec() - t)

	t = Time.get_ticks_usec()
	GroupMoveSolver.followable_destinations(squad, board, [dest])
	_stamp("followable_destinations (1 cell)", Time.get_ticks_usec() - t)

	t = Time.get_ticks_usec()
	sm.resolve_plan(squad, board)
	_stamp("resolve_plan", Time.get_ticks_usec() - t)

	t = Time.get_ticks_usec()
	game.refresh_action_queue(squad)
	_stamp("refresh_action_queue", Time.get_ticks_usec() - t)

	# HOVER is what game.group_move_followable buys. The sweep is per-SQUAD work, so a single-cell
	# query costs nearly what the whole range does, and hover used to pay it on every cell change.
	# The second stamp is that avoided cost — if it ever approaches the first, the cache stopped
	# being read. Averaged over a sample, warmed first: the sprite churn in show_hover_move_paths is
	# part of the real cost, and one cell is one sample.
	print("\nHOVER — per cell change, averaged over %d destinations" % mini(12, all_destinations.size()))
	game.selected_unit = leader
	game.enter_group_move_mode(leader)   # builds game.group_move_followable, which hover reads
	var sample: Array = all_destinations.slice(0, mini(12, all_destinations.size()))
	for c in sample:
		game.hover_presenter._hover_choosing_group_move(c)   # warm

	t = Time.get_ticks_usec()
	for c in sample:
		game.hover_presenter._hover_choosing_group_move(c)
	var hover_total: int = Time.get_ticks_usec() - t

	t = Time.get_ticks_usec()
	for c in sample:
		GroupMoveSolver.followable_destinations(squad, board, [c])
	var sweep_total: int = Time.get_ticks_usec() - t

	_stamp("hover, per cell change", hover_total / sample.size())
	_stamp("  cost AVOIDED by the mode-entry cache", sweep_total / sample.size())
	game.overlay_manager.clear_hover_move_path()

	print("\nTHE ACTUAL CLICK")
	game.last_clicked_cell = leader.movement.cell
	game.selected_unit = leader   # the click handlers read the stored selection, not the cell
	game.enter_group_move_mode(leader)   # the cache the click reads is built here, not by the click
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
